//! **FF-M7-TWO-OF-N** — the two-of-N signing custody fitness function (M7/S5,
//! `.copilot/wp` task 64, `architecture.md` §7/§11 item 1, flagged G-M7-4).
//!
//! Extends M4's single-root fitness guarantees
//! (`updater::trust`'s own `mod fitness`, and this crate's
//! `fitness_no_bare_cli_name.rs`-style source scans) to the new k-of-N
//! surface (`updater::multisig`, `updater::verify::verify_update_multisig`)
//! without weakening or duplicating what M4 already proved about the
//! single-root path. Same cheap, dependency-free text-scan style every other
//! fitness test in this crate uses — no call-graph analysis, no live signing
//! ceremony.
//!
//! What this file asserts, end to end:
//! 1. `THRESHOLD_K` is `>= 2` by source inspection (never silently `1`).
//! 2. The N trust roots are compiled-in array literals, never a
//!    file/env/preference read.
//! 3. An artifact with only `k-1` valid signatures is REFUSED
//!    (`verify_update_multisig` itself, via the real fixture corpus).
//! 4. Duplicate signatures from the SAME root don't count as two independent
//!    approvals.
//! 5. A wrong-key/garbage signature never counts toward the threshold.
//! 6. The live self-update transport calls the k-of-N verifier, not the old
//!    single-root verifier.
//!
//! Items 3-5 are also unit-tested directly inside
//! `updater::verify`'s own `#[cfg(test)]` module (closer to the code, exact
//! same fixtures) — this file re-proves them at the integration-test layer,
//! through the crate's PUBLIC `verify_update_multisig` entrypoint, so the
//! guarantee survives even if `updater::verify`'s internal
//! `verify_update_multisig_against` test seam is ever refactored away.

use std::fs;
use std::path::{Path, PathBuf};

use copilot_control_tower_lib::updater::multisig;
use copilot_control_tower_lib::updater::verify::{verify_update_multisig, VerifyError};

fn src_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("src")
}

fn fixtures_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures")
        .join("updater")
}

fn read_fixture(name: &str) -> Vec<u8> {
    let path = fixtures_dir().join(name);
    fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

fn read_fixture_string(name: &str) -> String {
    String::from_utf8(read_fixture(name)).unwrap_or_else(|e| panic!("utf8 {name}: {e}"))
}

/// Same strip-comments helper every fitness test in this crate carries its
/// own copy of.
fn strip_comments(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let bytes = src.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'/') {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
        } else if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'*') {
            i += 2;
            while i < bytes.len() && !(bytes[i] == b'*' && bytes.get(i + 1) == Some(&b'/')) {
                i += 1;
            }
            i += 2;
        } else {
            out.push(bytes[i] as char);
            i += 1;
        }
    }
    out
}

/// Removes every `#[cfg(test)] ... { ... }` item's body (brace-matched) —
/// identical logic to `fitness_m5_single_forced_boundary.rs`'s own copy
/// (duplicated per this crate's "each fitness check owns its own copy"
/// convention). Needed here for the exact same reason that file needed it:
/// `updater::multisig`'s own `mod fitness` legitimately names the forbidden
/// needle strings (`"env::var"`, `"--force"`, etc.) as STRING LITERALS
/// inside its scan logic — those literals are not real production code and
/// must not trip this crate-level test's scan.
fn strip_cfg_test_blocks(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let marker = "#[cfg(test)]";
    let mut rest = src;
    while let Some(idx) = rest.find(marker) {
        out.push_str(&rest[..idx]);
        let after_marker = &rest[idx + marker.len()..];
        let brace_start = match after_marker.find('{') {
            Some(b) => b,
            None => {
                out.push_str(marker);
                rest = after_marker;
                continue;
            }
        };
        let body = &after_marker[brace_start..];
        let mut depth = 0i32;
        let mut end = None;
        for (pos, ch) in body.char_indices() {
            match ch {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        end = Some(pos + 1);
                        break;
                    }
                }
                _ => {}
            }
        }
        let end = end.unwrap_or(body.len());
        rest = &body[end..];
    }
    out.push_str(rest);
    out
}

fn multisig_rs() -> String {
    fs::read_to_string(src_dir().join("updater").join("multisig.rs")).expect("read multisig.rs")
}

fn check_rs() -> String {
    fs::read_to_string(src_dir().join("updater").join("check.rs")).expect("read check.rs")
}

/// Production-only source (comments stripped, `#[cfg(test)]` blocks
/// stripped) — what the two source-scan tests below actually inspect.
fn multisig_production_source() -> String {
    strip_cfg_test_blocks(&strip_comments(&multisig_rs()))
}

fn check_production_source() -> String {
    strip_cfg_test_blocks(&strip_comments(&check_rs()))
}

// ---------------------------------------------------------------------------
// 1. THRESHOLD_K is never 1 (or 0) — source-scan half.
// ---------------------------------------------------------------------------

#[test]
fn threshold_k_is_never_one_or_zero_by_source_inspection() {
    let stripped = strip_comments(&multisig_rs());
    let needle = "pub const THRESHOLD_K: usize = ";
    let idx = stripped
        .find(needle)
        .expect("THRESHOLD_K const must be declared in updater/multisig.rs");
    let after = &stripped[idx + needle.len()..];
    let end = after
        .find(';')
        .expect("THRESHOLD_K declaration must be terminated with ;");
    let literal = after[..end].trim();
    let value: usize = literal.parse().unwrap_or_else(|_| {
        panic!("THRESHOLD_K must be a plain integer literal, found {literal:?}")
    });
    assert!(
        value >= 2,
        "FF-M7-TWO-OF-N: THRESHOLD_K must be two-of-N (>=2); found {value}"
    );
}

/// The same fact, proven by the RUNTIME value the compiled binary actually
/// carries — belt-and-suspenders alongside the source-scan above (the same
/// "two independent detectors" convention `fitness_no_fabricated_healthy.rs`
/// documents for its own highest-severity invariant).
#[test]
#[allow(clippy::assertions_on_constants)]
fn threshold_k_is_never_one_or_zero_at_runtime() {
    assert!(multisig::THRESHOLD_K >= 2);
}

// ---------------------------------------------------------------------------
// 2. The N trust roots are compiled-in code, never config.
// ---------------------------------------------------------------------------

#[test]
fn trust_roots_are_compiled_in_array_literals_never_read_from_env_or_file() {
    let stripped = multisig_production_source();
    assert!(
        stripped.contains("pub const TRUST_ROOTS_B64"),
        "expected a compiled-in TRUST_ROOTS_B64 const array in updater/multisig.rs"
    );
    for forbidden in [
        "env::var",
        "std::env",
        "fs::read",
        "File::open",
        "CFPreferencesCopyAppValue",
        "CFPreferencesAppValueIsForced",
    ] {
        assert!(
            !stripped.contains(forbidden),
            "FF-M7-TWO-OF-N: updater/multisig.rs must never read a trust root from anywhere \
             but its own compiled-in literals — found {forbidden:?}"
        );
    }
}

#[test]
fn trust_roots_count_is_at_least_the_threshold() {
    assert!(multisig::TRUST_ROOTS_B64.len() >= multisig::THRESHOLD_K);
}

#[test]
fn no_bypass_flag_anywhere_in_multisig_source() {
    let stripped = multisig_production_source();
    for needle in ["--force", "--skip-verify", "skip_verify", "insecure"] {
        assert!(
            !stripped.to_ascii_lowercase().contains(needle),
            "FF-M7-TWO-OF-N: found a banned bypass flag/insecure-branch spelling in \
             updater/multisig.rs: {needle:?}"
        );
    }
}

#[test]
fn live_update_transport_calls_the_multisig_verifier() {
    let stripped = check_production_source();
    assert!(
        stripped.contains("verify::verify_update_multisig("),
        "FF-M7-TWO-OF-N: updater/check.rs production code must route live update \
         manifest verification through verify_update_multisig"
    );
    assert!(
        !stripped.contains("verify::verify_update(&"),
        "FF-M7-TWO-OF-N: updater/check.rs production code must not keep the live \
         self-update transport on the single-root verifier"
    );
}

// ---------------------------------------------------------------------------
// 3. k-1 valid signatures are REFUSED, exercised through the public API.
// ---------------------------------------------------------------------------

#[test]
fn public_api_refuses_an_artifact_with_only_k_minus_one_valid_signatures() {
    let artifact = read_fixture("artifact.bin");
    let manifest = read_fixture("multisig-manifest.json");
    let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");

    let err = verify_update_multisig(&artifact, &[&sig_a], &manifest).expect_err(
        "FF-M7-TWO-OF-N: a single valid signature must never meet a two-of-N threshold",
    );
    assert!(
        matches!(err, VerifyError::InsufficientSignatures { valid: 1, .. }),
        "expected InsufficientSignatures{{valid: 1, ..}}, got {err:?}"
    );
}

#[test]
fn public_api_accepts_k_valid_distinct_signatures() {
    let artifact = read_fixture("artifact.bin");
    let manifest = read_fixture("multisig-manifest.json");
    let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
    let sig_b = read_fixture_string("multisig-manifest.json.rootB.minisig");

    // NOTE: `multisig-manifest.json`'s app_version (9.9.9) is expected to be
    // newer than whatever this crate's own Cargo.toml version currently is
    // — same convention M4's own `valid-manifest.json` fixture relies on
    // (see `updater::verify`'s `old_current()` test helper doc). If this
    // ever starts failing because the crate version caught up to 9.9.9,
    // bump the fixture's `app_version`, not this assertion.
    verify_update_multisig(&artifact, &[&sig_a, &sig_b], &manifest)
        .expect("two distinct valid signatures must satisfy the compiled-in two-of-N threshold");
}

// ---------------------------------------------------------------------------
// 4. Duplicate signatures from the SAME root don't count as two.
// ---------------------------------------------------------------------------

#[test]
fn public_api_does_not_double_count_a_duplicated_same_root_signature() {
    let artifact = read_fixture("artifact.bin");
    let manifest = read_fixture("multisig-manifest.json");
    let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");

    let err = verify_update_multisig(&artifact, &[&sig_a, &sig_a], &manifest)
        .expect_err("FF-M7-TWO-OF-N: the same root's signature submitted twice must not satisfy a two-of-N threshold");
    assert!(
        matches!(err, VerifyError::InsufficientSignatures { valid: 1, .. }),
        "expected InsufficientSignatures{{valid: 1, ..}} (one distinct root, not two), got {err:?}"
    );
}

// ---------------------------------------------------------------------------
// 5. A wrong-key/garbage signature never counts toward the threshold.
// ---------------------------------------------------------------------------

#[test]
fn public_api_ignores_a_garbage_signature_entirely() {
    let artifact = read_fixture("artifact.bin");
    let manifest = read_fixture("multisig-manifest.json");
    let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
    let garbage = read_fixture_string("garbage.minisig");

    let err = verify_update_multisig(&artifact, &[&sig_a, &garbage], &manifest)
        .expect_err("one valid signature plus one garbage signature is still below threshold");
    assert!(
        matches!(err, VerifyError::InsufficientSignatures { valid: 1, .. }),
        "expected InsufficientSignatures{{valid: 1, ..}}, got {err:?}"
    );
}

#[test]
fn public_api_ignores_a_signature_from_a_key_outside_the_compiled_in_set() {
    let artifact = read_fixture("artifact.bin");
    let manifest = read_fixture("multisig-manifest.json");
    let sig_a = read_fixture_string("multisig-manifest.json.rootA.minisig");
    let attacker_sig = read_fixture_string("multisig-manifest.json.attacker.minisig");

    let err = verify_update_multisig(&artifact, &[&sig_a, &attacker_sig], &manifest)
        .expect_err("a non-compiled-in-root signature must never count toward the threshold");
    assert!(
        matches!(err, VerifyError::InsufficientSignatures { valid: 1, .. }),
        "expected InsufficientSignatures{{valid: 1, ..}}, got {err:?}"
    );
}
