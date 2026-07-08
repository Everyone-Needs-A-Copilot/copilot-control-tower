//! FF-M5-1 / FF-M5-5 — the consolidated, audited forced-domain boundary
//! (M5/S1, `.copilot/wp/30.md` ADR-M5-001, invariant #4).
//!
//! Same cheap, dependency-free text-scan style every other fitness test in
//! this crate already uses (see `fitness_no_bare_cli_name.rs`,
//! `fitness_single_process_ff_m4_7.rs`) — no call-graph analysis, no live
//! `CFPreferences`/managed Mac.

use std::fs;
use std::path::{Path, PathBuf};

fn src_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("src")
}

fn collect_rs_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display())) {
        let path = entry.expect("dir entry").path();
        if path.is_dir() {
            collect_rs_files(&path, out);
        } else if path.extension().and_then(|e| e.to_str()) == Some("rs") {
            out.push(path);
        }
    }
}

/// Strips `//...` line comments and `/* ... */` block comments — same
/// approach every other fitness test in this crate already uses.
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
/// identical logic to `fitness_no_bare_cli_name.rs`'s `strip_cfg_test_blocks`
/// (duplicated per this crate's "each fitness check owns its own copy"
/// convention). Needed here because `updater::trust`'s own `mod fitness`
/// test legitimately names both FFI symbols as forbidden-needle STRING
/// LITERALS (asserting they never appear in `trust_root()`'s body) — those
/// string literals are not a real FFI call site and must not trip this
/// test's scan.
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

/// A `src`-relative path for readable failure output.
fn relative(path: &Path) -> String {
    path.strip_prefix(src_dir())
        .unwrap_or(path)
        .display()
        .to_string()
}

/// **FF-M5-1.** `CFPreferencesAppValueIsForced` and `CFPreferencesCopyAppValue`
/// — the two raw FFI symbols this crate's entire invariant-#4 forced-domain
/// guarantee rests on — must appear in exactly ONE file anywhere under
/// `src/`: `managed/forced.rs`. Before M5/S1 these appeared independently in
/// `settings/managed.rs` (M2) AND `updater/trust.rs` (M4) — two ad-hoc
/// copies of the app's single most security-critical FFI call. This test is
/// the standing, regression-proof guard that a THIRD copy (or a
/// resurrection of either removed copy) never lands again: every future
/// consumer must call through `managed::forced`'s typed API instead of
/// touching the raw C functions itself.
#[test]
fn cfpreferences_ffi_calls_appear_in_exactly_one_file_fitness_ff_m5_1() {
    let mut files = Vec::new();
    collect_rs_files(&src_dir(), &mut files);
    assert!(!files.is_empty(), "expected to find .rs files under src/");

    let expected_home = src_dir().join("managed").join("forced.rs");
    assert!(
        files.contains(&expected_home),
        "expected {} to exist and be scanned",
        expected_home.display()
    );

    for needle in ["CFPreferencesAppValueIsForced", "CFPreferencesCopyAppValue"] {
        let mut sites: Vec<String> = Vec::new();
        for file in &files {
            let raw =
                fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
            let stripped = strip_cfg_test_blocks(&strip_comments(&raw));
            if stripped.contains(needle) {
                sites.push(relative(file));
            }
        }
        assert_eq!(
            sites,
            vec![relative(&expected_home)],
            "{needle} must appear in EXACTLY ONE file (managed/forced.rs) — invariant #4's \
             forced-domain boundary must stay a single, auditable surface. Found it in: {sites:?}"
        );
    }
}

/// **FF-M5-1, companion check.** The two modules that USED to carry their
/// own independent FFI implementation (`settings::managed`,
/// `updater::trust`) must now delegate — i.e. reference
/// `crate::managed::forced`/`managed::forced` — rather than silently having
/// no forced-domain reads left at all (which would be a correctness
/// regression, not a consolidation).
#[test]
fn settings_managed_and_updater_trust_delegate_to_the_consolidated_boundary() {
    let settings_managed = fs::read_to_string(src_dir().join("settings").join("managed.rs"))
        .expect("read settings/managed.rs");
    let updater_trust = fs::read_to_string(src_dir().join("updater").join("trust.rs"))
        .expect("read updater/trust.rs");

    assert!(
        strip_comments(&settings_managed).contains("managed::forced::"),
        "settings::managed must delegate to managed::forced (M5/S1 consolidation)"
    );
    assert!(
        strip_comments(&updater_trust).contains("managed::forced::"),
        "updater::trust must delegate to managed::forced (M5/S1 consolidation)"
    );
}

/// **FF-M5-5.** Every key in the frozen registry
/// (`managed::keys::MANAGED_KEYS`) is honored ONLY from the forced domain —
/// no key may ever fall through to a user-domain value. This is already
/// unit-tested structurally inside `managed::forced`'s own
/// `resolve_string`/`resolve_bool` (an `IgnoredUserDomain` lookup always
/// folds to the default, never the ignored value) and inside
/// `managed::keys`'s own `every_registered_key_is_forced_only_fitness_ff_m5_5`
/// (every registry entry is `forced_only: true`) — this integration-level
/// test closes the gap between those two unit-level guarantees by actually
/// driving the dev-seam override end to end, for every registered key, and
/// confirming `IgnoredUserDomain` never wins.
#[test]
fn every_registry_key_ignores_a_user_domain_only_value_end_to_end_fitness_ff_m5_5() {
    use copilot_control_tower_lib::managed::forced::{forced_string, FORCED_OVERRIDE_ENV_PREFIX};
    use copilot_control_tower_lib::managed::keys::MANAGED_KEYS;

    for key in MANAGED_KEYS {
        let env_name = format!(
            "{FORCED_OVERRIDE_ENV_PREFIX}{}",
            key.name.to_ascii_uppercase()
        );
        // SAFETY: this test process does not otherwise touch these
        // per-key env vars concurrently — each key gets its own uniquely
        // named override var (no shared global like `CT_MANAGED_OVERRIDE`),
        // so no cross-test lock is needed here the way the crate's
        // in-process unit tests need `cli::test_env::ENV_LOCK`.
        unsafe { std::env::set_var(&env_name, "user") };
        let lookup = forced_string(key.name);
        unsafe { std::env::remove_var(&env_name) };

        assert!(
            !lookup.is_forced(),
            "key {:?} reported Forced for a user-domain-only value — invariant #4 violation",
            key.name
        );
    }
}

/// The dev-mockable per-key override seam is compiled out of a genuine
/// shipped release build (same discipline as `cli::path::DEV_OVERRIDE_ENV`
/// — see that module's doc for the full argument). Static half: the gate
/// annotation itself must be present on both the constant and its readers.
/// The dynamic half (a real `strings` scan of a fresh `cargo build
/// --release` artifact showing zero occurrences) cannot run inside `cargo
/// test` itself (it requires a full release build as a separate step) —
/// it's the S1 summary's documented manual verification step, matching
/// `cli::path`'s own "batched" precedent for the equivalent claim about
/// `CT_CLI_PATH`.
#[test]
fn the_forced_override_seam_is_gated_out_of_release_builds() {
    let raw = fs::read_to_string(src_dir().join("managed").join("forced.rs"))
        .expect("read managed/forced.rs");
    let gate = "#[cfg(any(debug_assertions, test, feature = \"dev-seam\"))]";
    let occurrences = raw.matches(gate).count();
    assert!(
        occurrences >= 3,
        "expected the dev-seam gate to cover the override constant and its two reader \
         functions (found {occurrences} occurrences of {gate:?}) — a genuine `cargo build \
         --release` must compile CT_FORCED_OVERRIDE_* out entirely, not merely leave it unread"
    );
    assert!(
        raw.contains("pub const FORCED_OVERRIDE_ENV_PREFIX"),
        "expected FORCED_OVERRIDE_ENV_PREFIX to exist as a gated public constant"
    );
}
