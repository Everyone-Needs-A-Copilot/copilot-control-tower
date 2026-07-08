//! Two-of-N signing custody (M7/S5, `.copilot/wp` task 64, ADR-M4-003/004's
//! successor for the trust-root half): extends [`super::trust`]'s single
//! compiled-in `TRUST_ROOT_PUBLIC_KEY_B64` to a compiled-in **array of N**
//! trust roots and a **k-of-N threshold** (`architecture.md` §7/§11 item 1,
//! `threat-model.md` §2.3 B4) — no single popped/lost signing key can
//! unilaterally authorize a fleet-wide update.
//!
//! ## Why a new module rather than editing `trust.rs` in place
//!
//! `trust.rs` is M4's file, and its single-root `trust_root()`/
//! `TRUST_ROOT_PUBLIC_KEY_B64` are still the exact path `verify::verify_update`
//! uses today (kept working, unmodified, per this task's own instruction —
//! there is no reason to migrate that call site: `verify_update_multisig`
//! below is an ADDITIONAL, stricter entrypoint the transport can move to
//! independently). Putting the k-of-N array in its own file means the two
//! trust models (one compiled-in root vs. N compiled-in roots + a threshold)
//! are never accidentally conflated by a future edit to either file, and
//! `trust.rs`'s existing fitness scans (`trust_root_function_body_only_ever_
//! parses_the_compiled_in_const`, the FF-M4-2 bypass-flag scan) stay scoped
//! to exactly what they always scanned.
//!
//! ## The k-of-N model
//!
//! - [`TRUST_ROOTS_B64`] — a compiled-in `[&str; N]` array of minisign public
//!   keys, the SAME shape as `trust::TRUST_ROOT_PUBLIC_KEY_B64` (raw base64,
//!   never a file/env/preference read — see `fitness` submodule below and
//!   `tests/fitness_m7_two_of_n_signing.rs`). **DEV KEYS** — three dev
//!   keypairs generated for this milestone purely so the k-of-N verification
//!   path is exercisable by `cargo test` without a real signing ceremony
//!   (identical rationale to `trust.rs`'s own dev key doc comment). The real
//!   two-of-N production keys + who holds the second (and here, third)
//!   custodian are an **owner-gated, batched-for-release decision**
//!   (`architecture.md` §11 item 1, flagged G-M7-4) — swapping this array's
//!   literals for the real custodied keys is the entire migration; this
//!   module's shape does not change.
//! - [`THRESHOLD_K`] — the number of DISTINCT roots (out of [`TRUST_ROOTS_B64`])
//!   that must each independently produce a valid signature over the exact
//!   same manifest bytes before [`super::verify::verify_update_multisig`]
//!   treats the manifest as authenticated. **Always `>= 2`** — a compile-time
//!   assertion below makes `THRESHOLD_K == 1` (or `0`) a build-breaking bug,
//!   never a silently-shipped regression to single-key trust
//!   (`docs/05-security/signing-custody.md`'s policy statement; the fitness
//!   test's `k_is_never_one_or_zero` is the same assertion's independent,
//!   test-harness-visible mirror).
//!
//! ## What "distinct roots" means (and why it's checked this way)
//!
//! [`super::verify::verify_update_multisig`] does not merely count "how many
//! supplied signature strings verified" — two different signature blobs that
//! both happen to verify against the SAME root must count as **one**, not
//! two (an attacker — or a careless build script — duplicating a single
//! custodian's signature must never look like an independent second
//! custodian's approval). The verifier tracks which root INDEX each valid
//! signature matched and de-duplicates by that index before comparing
//! against [`THRESHOLD_K`]. See that function's doc and
//! `tests/fitness_m7_two_of_n_signing.rs`'s
//! `duplicate_signatures_from_the_same_root_do_not_count_twice`.
//!
//! ## What this module deliberately does NOT do
//!
//! It does not re-implement minisign parsing/verification (that stays in
//! `minisign_verify`, the one vetted crypto dependency `trust.rs`/`verify.rs`
//! already use) and it does not touch the downgrade/artifact-hash checks
//! (`verify::after_authenticated` — shared, unchanged, by both the
//! single-root and k-of-N entrypoints). This module's entire job is: "here
//! are N compiled-in public keys, and the minimum number of them that must
//! independently sign."

use minisign_verify::PublicKey;

// ---------------------------------------------------------------------------
// The compiled-in N trust roots (FF-M7-TWO-OF-N)
// ---------------------------------------------------------------------------

/// **DEV KEYS — replaceable at release, not real secrets.** Three minisign
/// public keys (same raw-base64 shape as `trust::TRUST_ROOT_PUBLIC_KEY_B64`),
/// generated for this milestone with the `minisign` crate (full sign+verify,
/// **not** a dependency of this crate — see `fixtures/updater/README.md`'s
/// documented scratch-project process, which this module's keys followed
/// identically). The corresponding secret keys are **not** committed
/// anywhere in this repo — only the fixtures they signed
/// (`fixtures/updater/multisig-*.minisig`) are checked in.
///
/// **Release migration:** replace these three literals with the real,
/// owner-gated two-of-N (or, if a third custodian is assigned, three-key)
/// production roots before `stable` channel promotion is ever enabled in CI
/// (`docs/05-security/signing-custody.md` §"Migration") — tracked as an
/// owner-gated open item (G-M7-4), not a code TODO, because custody
/// assignment (who holds which key) is a decision this crate cannot make.
pub const TRUST_ROOTS_B64: [&str; 3] = [
    // "rootA"
    "RWSCTWsd5UMeemE2HByT9IAqjGZOkfxdm3YMKLfckl5qw/ijp8DprhIs",
    // "rootB"
    "RWSXEcOBXPo+Ol+IsRW/zp+ULS36d53171rm/nNfeB+ezCV9/Of6uXSZ",
    // "rootC"
    "RWQSc31bl8sLb0IQzrCyPpyvCbPKZBdUVwJwoUh6cCdNWF/t4Bx0vCmz",
];

/// The two-of-N threshold: at least this many DISTINCT roots (out of
/// [`TRUST_ROOTS_B64`]) must each independently verify the same manifest
/// bytes. `>= 2` by construction — see the module doc and
/// [`fitness::threshold_k_is_never_one_or_zero`]/
/// `tests/fitness_m7_two_of_n_signing.rs`'s equivalent source-scan.
pub const THRESHOLD_K: usize = 2;

// A single popped/lost key must never be sufficient on its own — this is
// the literal invariant `docs/05-security/signing-custody.md` names as the
// entire point of two-of-N. A future edit that dropped `THRESHOLD_K` to `1`
// (or `0`) fails the BUILD here, not just a test run, since `const`
// evaluation happens at compile time.
const _: () = assert!(
    THRESHOLD_K >= 2,
    "THRESHOLD_K must be two-of-N (>=2) — a single signing root must never be sufficient to authorize an update"
);

// N must be at least K, or the threshold could never be met by construction
// (a mis-sized array is exactly as fail-closed a bug as THRESHOLD_K==1, so
// it gets the identical compile-time treatment).
const _: () = assert!(
    TRUST_ROOTS_B64.len() >= THRESHOLD_K,
    "there must be at least THRESHOLD_K compiled-in trust roots, or two-of-N could never be satisfied"
);

/// Parses every entry of [`TRUST_ROOTS_B64`] into a usable key, in the same
/// order. `.expect()` here mirrors `trust::trust_root()`'s own: a malformed
/// compiled-in literal is a build-breaking bug caught by any test in this
/// crate that calls this function, never a runtime/user-facing condition.
pub fn trust_roots() -> Vec<PublicKey> {
    TRUST_ROOTS_B64
        .iter()
        .map(|b64| {
            PublicKey::from_base64(b64)
                .expect("TRUST_ROOTS_B64 entries are compiled-in literals and must always parse")
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_trust_roots_are_compiled_in_literals_never_read_from_the_environment() {
        // Same shape of proof as `trust::tests::the_trust_root_is_a_compiled_in_
        // literal_never_read_from_the_environment`: no arguments, no env var, no
        // file — deterministic and stable across calls.
        let a = trust_roots();
        let b = trust_roots();
        assert_eq!(a.len(), b.len());
        assert_eq!(a.len(), TRUST_ROOTS_B64.len());
    }

    #[test]
    fn all_n_trust_roots_are_well_formed() {
        let roots = trust_roots();
        assert_eq!(roots.len(), 3);
    }

    #[test]
    fn the_n_trust_roots_are_pairwise_distinct() {
        // A duplicated literal in the array would silently shrink the real
        // custody diversity below what N implies (e.g. two array slots
        // secretly the SAME key would make a nominal "three-of-N" actually
        // only two distinct custodians) — assert the compiled-in array
        // itself has no accidental duplicate before any signature is ever
        // checked against it.
        let mut seen = std::collections::HashSet::new();
        for b64 in TRUST_ROOTS_B64 {
            assert!(
                seen.insert(b64),
                "TRUST_ROOTS_B64 contains a duplicate entry: {b64:?}"
            );
        }
    }

    #[test]
    // `THRESHOLD_K >= 2` is, today, a compile-time-constant-true expression —
    // that IS the invariant this test exists to keep visible at the
    // test-harness level (a second, independent-of-the-`const _: () =
    // assert!` mirror of the same fact, matching this module's own doc's
    // "two detectors" rationale); clippy's `assertions_on_constants` lint
    // would otherwise flag exactly the check that's the point.
    #[allow(clippy::assertions_on_constants)]
    fn threshold_k_is_at_least_two() {
        assert!(THRESHOLD_K >= 2);
    }

    #[test]
    #[allow(clippy::assertions_on_constants)]
    fn threshold_k_never_exceeds_the_number_of_roots() {
        assert!(THRESHOLD_K <= TRUST_ROOTS_B64.len());
    }
}

/// **FF-M7-TWO-OF-N, source-scan half — this module's own copy.** See
/// `trust.rs`'s identical `mod fitness` for why this pattern (inline
/// `#[cfg(test)]` source scan via `include_str!`, rather than a shared
/// helper crate) is this stream's convention: each fitness check owns its
/// own copy so it stays self-contained even outside a normal file-path
/// sandbox. `tests/fitness_m7_two_of_n_signing.rs` re-asserts the same
/// invariants as a crate-level integration test (belt-and-suspenders, not
/// redundant — that file also covers `verify::verify_update_multisig`'s
/// adversarial behavior, which cannot be scoped to this file alone).
#[cfg(test)]
mod fitness {
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

    fn production_source(raw: &str) -> String {
        let stripped = strip_comments(raw);
        match stripped.find("#[cfg(test)]") {
            Some(idx) => stripped[..idx].to_string(),
            None => stripped,
        }
    }

    /// The threshold literal itself must textually be `2` (or higher) —
    /// closes the gap the `const _: () = assert!(...)` compile-time check
    /// can't: that assertion proves `THRESHOLD_K >= 2` for WHATEVER value is
    /// there today, but a source-scan is what lets a reviewer (or a CI
    /// gate) see the actual number without running the build, and it's a
    /// second, independent detector of the same fact (this crate's
    /// established "two detectors" convention for its highest-severity
    /// invariants — see `fitness_no_fabricated_healthy.rs`'s own doc for
    /// the same rationale applied to a different invariant).
    #[test]
    fn threshold_k_source_literal_is_never_one_or_zero() {
        let raw = include_str!("multisig.rs");
        let production_only = production_source(raw);
        let needle = "pub const THRESHOLD_K: usize = ";
        let idx = production_only
            .find(needle)
            .expect("THRESHOLD_K const must exist in multisig.rs");
        let after = &production_only[idx + needle.len()..];
        let end = after
            .find(';')
            .expect("THRESHOLD_K declaration must end in ;");
        let literal = after[..end].trim();
        let value: usize = literal.parse().unwrap_or_else(|_| {
            panic!("THRESHOLD_K must be a plain integer literal, found {literal:?}")
        });
        assert!(
            value >= 2,
            "THRESHOLD_K must be two-of-N (>=2); found {value} in source"
        );
    }

    /// `TRUST_ROOTS_B64` must be a plain array literal in THIS file — never
    /// a call to `std::env::var`, `std::fs::read`, or any preferences FFI.
    /// Mirrors `trust.rs`'s `trust_root_function_body_only_ever_parses_the_
    /// compiled_in_const`, scoped to the array declaration instead of a
    /// function body (there is no function wrapping the array itself; the
    /// array IS the const).
    #[test]
    fn trust_roots_array_is_a_compiled_in_literal_never_read_from_the_environment() {
        let raw = include_str!("multisig.rs");
        let production_only = production_source(raw);
        let needle = "pub const TRUST_ROOTS_B64: [&str; 3] = [";
        assert!(
            production_only.contains(needle),
            "expected TRUST_ROOTS_B64 to be declared as a plain compiled-in array literal"
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
                !production_only.contains(forbidden),
                "multisig.rs must never read a trust root from anywhere but its own compiled-in \
                 literals (FF-M7-TWO-OF-N) — found {forbidden:?}"
            );
        }
    }

    #[test]
    fn no_bypass_flag_or_insecure_branch_in_multisig_fitness_ff_m7_two_of_n() {
        let raw = include_str!("multisig.rs");
        let production_only = production_source(raw);
        let needles = ["--force", "--skip-verify", "skip_verify", "insecure"];
        for needle in needles {
            assert!(
                !production_only.to_ascii_lowercase().contains(needle),
                "found a banned bypass flag/insecure-branch spelling in actual code (not a \
                 comment) in updater::multisig (invariant #4, FF-M7-TWO-OF-N): {needle:?}"
            );
        }
    }
}
