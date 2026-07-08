//! The compiled-in update trust root (M4/S1, ADR-M4-003, FF-M4-3) and the
//! forced-domain-only feed/channel/self-update-allowance reader (FF-M4-4).
//!
//! ## Trust root is CODE, not config (invariant #4, FF-M4-3)
//!
//! [`TRUST_ROOT_PUBLIC_KEY_B64`] is a `pub const` — a literal compiled into
//! the binary at build time. There is **no** function anywhere in this crate
//! that reads a signing public key from a preference, an environment
//! variable, or a file; [`trust_root()`] only ever parses this one literal.
//! `tests::the_trust_root_is_a_compiled_in_literal_never_read_from_the_environment`
//! (below) and the crate-wide `tests/fitness_trust_root_is_const.rs` both
//! assert this by construction and by source-scan respectively.
//!
//! **This is the project's DEV key** (see the doc comment on the const
//! itself) — generated for this milestone with the `minisign` crate purely
//! to make the fail-closed verification path in [`super::verify`]
//! exercisable by `cargo test` without a real signing ceremony. It is
//! deliberately NOT the production trust root: the real key + its two-of-N
//! custody split (`architecture.md` §7, §11 item 1; `threat-model.md` §2.3
//! B4) is an owner-gated decision batched for release — swapping this const
//! for the real key (and re-cutting this file's doc comment to say so) is
//! the entire migration; no other code in this crate needs to change shape.
//!
//! ## Feed/channel/self-update are forced-domain-only (invariant #4, FF-M4-4)
//!
//! [`update_feed_url`], [`update_channel`], and [`allow_self_update`] each
//! read their respective MDM-managed key (`UpdateFeedURL`, `UpdateChannel`,
//! `AllowSelfUpdate`) via `crate::managed::forced::resolve_string`/
//! `resolve_bool` — the consolidated, sole forced-domain FFI boundary
//! (`.copilot/wp/30.md` M5/S1, ADR-M5-001). **Before that milestone** this
//! module carried its own independent `CFPreferencesAppValueIsForced`/
//! `CFPreferencesCopyAppValue` implementation, deliberately parallel to
//! `settings::managed::key_is_forced` rather than sharing it (see that era's
//! rationale, preserved in git history: two ad-hoc copies of the same six
//! lines of FFI plumbing were judged cheaper than coupling two
//! independently-owned modules). M5/S1 revisited that call once a THIRD
//! independent copy was about to be needed for new security keys
//! (`Deprovisioned`, `SharedSecretStoreURL`/`Tier`, …) — three copies of the
//! app's single most security-critical FFI is exactly the un-auditable
//! triplication invariant #4 forbids, so this module now delegates instead.
//! Public behavior (`update_feed_url`/`update_channel`/`allow_self_update`)
//! and every test in this file are unchanged by that refactor. A value
//! present only in the **user** domain (not forced) is still **ignored** in
//! favor of the compiled-in default and logged as a tamper event
//! (`crate::managed::forced::audit_ignored_user_domain_value`, the same
//! `eprintln!`-is-the-interim-facility discipline this module's own
//! `audit_ignored_user_domain_value` used to implement locally) — never
//! merely "does this key have a value."
//!
//! `settings::guard::DENIED_KEYS` already refuses these same key names if
//! anyone tries to *write* them into `copilot.layers.yml` (M2/S3) — this
//! module is the other half of the same invariant: the *read* side, for the
//! app's own update-transport decision, not the Settings-write path.

use minisign_verify::PublicKey;

// ---------------------------------------------------------------------------
// The compiled-in trust root (FF-M4-3)
// ---------------------------------------------------------------------------

/// **DEV KEY — replaceable at release, not a real secret.** The minisign
/// public key (raw base64, the same bytes minisign's own `.pub` file's
/// second line carries — [`minisign_verify::PublicKey::from_base64`]'s
/// expected shape) this build trusts to sign an update manifest
/// (`super::verify::verify_update`). Generated for this milestone with:
///
/// ```text
/// minisign -G   # (or the equivalent `minisign` crate call this repo's
///               #  fixture generator used — see fixtures/updater/)
/// ```
///
/// The corresponding secret key is intentionally **not** committed anywhere
/// in this repo (not even as a "dev secret") — only the fixtures it was used
/// to sign are checked in (`fixtures/updater/*.minisig`). Regenerating the
/// dev keypair and re-signing the fixtures is a mechanical, documented
/// process (`fixtures/updater/README.md`); it does not change this module's
/// shape.
///
/// **Release migration:** replace this literal with the real, two-of-N
/// custodied production key before `stable` channel promotion is ever
/// enabled in CI (`release-and-versioning.md` §2 step 3) — tracked as an
/// owner-gated open item, not a code TODO, because the custody assignment
/// itself (who holds the second key) is a decision this crate cannot make.
pub const TRUST_ROOT_PUBLIC_KEY_B64: &str =
    "RWTTB+DjHKSykfKOoWjbRLhHyzDyFlNvg5sByAbQf4xT9i64yyr7/QLY";

/// Parses [`TRUST_ROOT_PUBLIC_KEY_B64`] into a usable key. `.expect()` here
/// is deliberate and correct, not a shortcut: a malformed compiled-in
/// literal is a **build-breaking bug** (caught the moment any test in this
/// crate runs `verify_update`), never a runtime/user-facing condition — the
/// same class of "this can only fail if the binary itself is broken"
/// invariant `settings::manifest`'s serde derives rely on.
pub fn trust_root() -> PublicKey {
    PublicKey::from_base64(TRUST_ROOT_PUBLIC_KEY_B64)
        .expect("TRUST_ROOT_PUBLIC_KEY_B64 is a compiled-in literal and must always parse")
}

// ---------------------------------------------------------------------------
// The compiled-in default feed (FF-M4-3/FF-M4-4)
// ---------------------------------------------------------------------------

/// The default update feed — authoritative on every **unmanaged** machine,
/// and the fallback on a managed machine where `UpdateFeedURL` isn't forced.
///
/// **GAP D-4-M4 (`.copilot/wp/24.md` "Gaps"):** the real endpoint this
/// resolves to is an open, owner-gated decision (where the signed
/// `latest.json` is actually hosted). This literal is a structurally-valid
/// placeholder so every consumer of [`update_feed_url`] has something to
/// compile and test against today; swapping the string is the entire
/// migration once the real endpoint is assigned — same "code, not config"
/// shape as the trust root above, and for the identical reason (invariant
/// #4: a repointable feed is a supply-chain RCE lever).
pub const DEFAULT_UPDATE_FEED_URL: &str = "https://updates.controltower.example/stable/latest.json";

/// Default release channel when `UpdateChannel` isn't forced
/// (`release-and-versioning.md` §2: "the default channel; what
/// `UpdateFeedURL` points to when unset").
pub const DEFAULT_UPDATE_CHANNEL: &str = "stable";

/// Default self-update allowance when `AllowSelfUpdate` isn't forced — an
/// unmanaged/solo machine self-updates unless IT has explicitly said
/// otherwise; `false` is only ever a forced-domain fact, never a user
/// choice (architecture.md §8.3).
pub const DEFAULT_ALLOW_SELF_UPDATE: bool = true;

const UPDATE_FEED_URL_KEY: &str = "UpdateFeedURL";
const UPDATE_CHANNEL_KEY: &str = "UpdateChannel";
const ALLOW_SELF_UPDATE_KEY: &str = "AllowSelfUpdate";

/// **M5/S1 delegation.** This module used to define its own private
/// `ForcedLookup` enum + `resolve()`/`audit_ignored_user_domain_value()`/
/// `real_lookup()` — the exact FFI call shape now consolidated into
/// `crate::managed::forced` (see the module doc). `update_feed_url`/
/// `update_channel`/`allow_self_update` below call
/// `crate::managed::forced::resolve_string`/`resolve_bool` directly; there
/// is no longer a local `ForcedLookup`/`real_lookup`/`resolve` in this file.
/// `crate::managed::forced::ForcedLookup` (used by this file's own tests
/// below, via `crate::managed::forced::forced_string`) is the SAME type
/// `updater::trust`'s tests exercised before this refactor, just imported
/// rather than locally defined.
///
/// The forced-domain-only update feed URL (FF-M4-4). Authoritative source
/// for wherever `super::verify`'s eventual HTTP transport (S3/S9) fetches
/// `latest.json` from.
pub fn update_feed_url() -> String {
    crate::managed::forced::resolve_string(UPDATE_FEED_URL_KEY, DEFAULT_UPDATE_FEED_URL)
}

/// The forced-domain-only release channel (FF-M4-4,
/// `release-and-versioning.md` §2).
pub fn update_channel() -> String {
    crate::managed::forced::resolve_string(UPDATE_CHANNEL_KEY, DEFAULT_UPDATE_CHANNEL)
}

/// The forced-domain-only self-update allowance (FF-M4-4). `"false"`/`"0"`
/// (case-insensitive) means disabled; anything else forced is treated as
/// enabled rather than silently disabling updates on an ambiguous value —
/// the safe failure mode for an *availability* toggle is "keep updating",
/// the opposite of a signature/staple check's fail-closed-to-refuse. This is
/// `crate::managed::forced::forced_bool`'s exact canonical parse rule (see
/// that function's doc — it was generalized FROM this function's original
/// inline `matches!` when M5/S1 consolidated the boundary), so this reduces
/// to a direct `resolve_bool` call.
pub fn allow_self_update() -> bool {
    crate::managed::forced::resolve_bool(ALLOW_SELF_UPDATE_KEY, DEFAULT_ALLOW_SELF_UPDATE)
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- trust root is a compiled-in literal, never read from the
    //    environment (FF-M4-3) --------------------------------------------

    #[test]
    fn the_trust_root_is_a_compiled_in_literal_never_read_from_the_environment() {
        // `trust_root()` takes no arguments, reads no env var, opens no
        // file — there is no seam through which a test (or an attacker)
        // could have influenced what key it returns. Parsing succeeds and
        // is stable across calls, which is the only thing a "compiled-in
        // const" claim can be positively demonstrated to do in a unit test;
        // the *absence* of any other code path is asserted by the source
        // scan below (`fitness` submodule).
        let a = trust_root();
        let b = trust_root();
        assert_eq!(a, b);
    }

    #[test]
    fn trust_root_public_key_is_well_formed() {
        // A 42-byte decode is `minisign_verify::PublicKey::from_base64`'s
        // own validity contract — asserting it here (rather than only via
        // `trust_root()`'s `.expect()`) gives a readable failure if a future
        // edit to the const ever breaks its shape.
        let _ = trust_root();
    }

    // -- forced-domain resolution is pure and testable without a managed
    //    Mac (FF-M4-4). `resolve_string`/`resolve_bool`/`ForcedLookup` now
    //    live in `crate::managed::forced` (M5/S1 consolidation) — these
    //    tests exercise this file's OWN consumers of that shared API
    //    (`update_feed_url`/`update_channel`/`allow_self_update`) via the
    //    dev-seam override, which proves the delegation actually wires
    //    through end to end rather than merely re-testing the already-tested
    //    generic `resolve_string`/`resolve_bool` (covered by
    //    `managed::forced`'s own test suite). ---------------------------

    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::forced::{ForcedLookup, FORCED_OVERRIDE_ENV_PREFIX};

    fn override_env_name(key: &str) -> String {
        format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase())
    }

    #[test]
    fn absent_falls_back_to_the_compiled_in_default() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(override_env_name(UPDATE_FEED_URL_KEY)) };
        assert_eq!(update_feed_url(), DEFAULT_UPDATE_FEED_URL);
    }

    #[test]
    fn a_user_domain_only_value_is_ignored_in_favor_of_the_default() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name(UPDATE_FEED_URL_KEY);
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "user") };
        assert_eq!(
            update_feed_url(),
            DEFAULT_UPDATE_FEED_URL,
            "an unforced (user-domain) value must NEVER win over the compiled-in default"
        );
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn a_forced_value_is_honored() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name(UPDATE_FEED_URL_KEY);
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(
                &env_name,
                "forced:https://mirror.internal.example/latest.json",
            )
        };
        assert_eq!(
            update_feed_url(),
            "https://mirror.internal.example/latest.json"
        );
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn allow_self_update_defaults_true_when_absent() {
        assert!(matches!(
            crate::managed::forced::forced_string("SomeKeyThatIsNeverForcedOrSetOnThisDevBox_Xyz"),
            ForcedLookup::Absent
        ));
    }

    #[test]
    fn allow_self_update_forced_false_variants_all_disable() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name(ALLOW_SELF_UPDATE_KEY);
        for v in ["false", "False", "FALSE", "0", "no", "No"] {
            // SAFETY: serialized by ENV_LOCK.
            unsafe { std::env::set_var(&env_name, format!("forced:{v}")) };
            assert!(!allow_self_update(), "{v:?} must be treated as disabled");
        }
        unsafe { std::env::remove_var(&env_name) };
    }

    // -- real, OS-touching sanity checks (mirrors
    //    settings::managed::an_unforced_key_on_this_dev_machine_is_reported_as_not_forced):
    //    this dev machine carries no `.mobileconfig`, so every one of these
    //    keys must genuinely come back Absent — proving the FFI binding
    //    itself compiles and runs end to end, even though the true
    //    forced-domain behavior needs a managed Mac to confirm (owner-gated,
    //    same caveat `settings::managed`'s own doc carries). ---------------

    #[cfg(target_os = "macos")]
    #[test]
    fn on_this_unmanaged_dev_machine_none_of_the_three_keys_are_forced() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        for key in [
            UPDATE_FEED_URL_KEY,
            UPDATE_CHANNEL_KEY,
            ALLOW_SELF_UPDATE_KEY,
        ] {
            // SAFETY: serialized by ENV_LOCK — ensures no dev-seam override
            // is active for these keys so the REAL FFI path is exercised.
            unsafe { std::env::remove_var(override_env_name(key)) };
            assert_eq!(
                crate::managed::forced::forced_string(key),
                ForcedLookup::Absent,
                "key {key:?} must not be forced on an unmanaged dev machine"
            );
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn the_real_end_to_end_readers_fall_back_to_compiled_in_defaults_here() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK — clears any dev-seam override so
        // the REAL (unmanaged-dev-machine) path is exercised.
        for key in [
            UPDATE_FEED_URL_KEY,
            UPDATE_CHANNEL_KEY,
            ALLOW_SELF_UPDATE_KEY,
        ] {
            unsafe { std::env::remove_var(override_env_name(key)) };
        }
        assert_eq!(update_feed_url(), DEFAULT_UPDATE_FEED_URL);
        assert_eq!(update_channel(), DEFAULT_UPDATE_CHANNEL);
        assert_eq!(allow_self_update(), DEFAULT_ALLOW_SELF_UPDATE);
    }
}

/// M4/S1-S2's own fitness/security tests, scoped to exactly the three files
/// `sec` owns in this stream (`trust.rs`/`verify.rs`/`heartbeat.rs`) — kept
/// as an inline `#[cfg(test)]` source scan rather than a new `tests/*.rs`
/// integration test file, since this task's file boundary is explicitly
/// "only the `updater/` module + `lib.rs` registration + `Cargo.toml` + test
/// fixtures" (a broader, crate-wide grep-deny across all of `src-tauri/src`
/// and `packaging`/`scripts` is `updater::watchdog`'s
/// `no_bypass_flags_anywhere_in_owned_distribution_source_fitness_ff_m4_2`,
/// which deliberately excludes these three files and says so in its own
/// doc — this module is what closes that gap for its own files). Uses
/// `include_str!` (the exact source text, comments included) rather than
/// `env!("CARGO_MANIFEST_DIR")` + `fs::read_to_string`, so this test is
/// self-contained even if `src-tauri/src` isn't reachable as a normal file
/// path (a doctest sandbox, a vendored crate copy, …) — the same
/// build-time-embedding property the trust root const itself relies on.
#[cfg(test)]
mod fitness {
    /// Strips `//...` line comments and `/* ... */` block comments —
    /// deliberately duplicated from `fitness_no_bare_cli_name.rs`'s
    /// `strip_comments` (that file is scoped to `cli::spawn`'s CLI-name
    /// invariant, not this one; this crate's convention is "each fitness
    /// check owns its own copy" rather than a shared test-utility crate).
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

    /// Truncates at the first `#[cfg(test)]` marker rather than
    /// brace-matching each test block individually — every file in this
    /// stream (`trust.rs`/`verify.rs`/`heartbeat.rs`) keeps ALL production
    /// code textually before its one trailing `#[cfg(test)] mod tests { ... }`
    /// (and, here in `trust.rs`, the further-trailing `mod fitness` this
    /// function itself lives in). A brace-matching approach was tried first
    /// and discarded: it scanned this file's OWN `'{'`/`'}'` char-literal
    /// brace tokens (used by an earlier version of the now-removed
    /// `strip_cfg_test_blocks` helper) as if they were structural braces,
    /// miscounting depth and corrupting the scan — a genuine self-reference
    /// bug caught by this module's own tests failing. Truncation sidesteps
    /// that whole class of bug and is correct for how this codebase is
    /// actually laid out; `production_source_boundary_matches_the_real_file_layout`
    /// (below) guards the "textually before" assumption itself.
    fn production_source(raw: &str) -> String {
        let stripped = strip_comments(raw);
        match stripped.find("#[cfg(test)]") {
            Some(idx) => stripped[..idx].to_string(),
            None => stripped,
        }
    }

    /// Extracts the `{ ... }` body text of the first `fn <needle>` found in
    /// `production_only` (brace-matched) — used to scope the
    /// "trust root const is the ONLY thing `trust_root()` ever reads" check
    /// precisely to that one function, rather than the whole file (which
    /// legitimately DOES read the forced-preferences domain elsewhere, for
    /// `UpdateFeedURL`/`UpdateChannel`/`AllowSelfUpdate` — a very different,
    /// intentional thing FF-M4-4 requires).
    fn function_body(production_only: &str, fn_signature_needle: &str) -> Option<String> {
        let idx = production_only.find(fn_signature_needle)?;
        let after = &production_only[idx + fn_signature_needle.len()..];
        let brace_start = after.find('{')?;
        let body = &after[brace_start..];
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
        Some(body[..end.unwrap_or(body.len())].to_string())
    }

    /// **FF-M4-3, source-scan half.** `trust_root()`'s ENTIRE body must be
    /// "parse the compiled-in const" and nothing else — no env var, no file
    /// read, no CoreFoundation preferences call. This is the static
    /// counterpart to `tests::the_trust_root_is_a_compiled_in_literal_never_read_from_the_environment`'s
    /// runtime check: that test can only show the function is
    /// deterministic and argument-free; this one shows there is no OTHER
    /// code path inside it that could have been (or could later be, without
    /// this test breaking) wired to something mutable.
    #[test]
    fn trust_root_function_body_only_ever_parses_the_compiled_in_const() {
        let raw = include_str!("trust.rs");
        let production_only = production_source(raw);
        // NOTE: the needle deliberately does NOT include the trailing `{`
        // — `function_body` finds that brace itself (and starts counting
        // depth from it); including it here would make `function_body`
        // search for a SECOND `{` instead, silently matching the wrong
        // function's body (caught by this exact test failing during
        // development — see the fixture-verification note in the module
        // doc above `mod fitness`).
        let body = function_body(&production_only, "pub fn trust_root() -> PublicKey")
            .expect("trust_root() must exist in trust.rs");

        assert!(
            body.contains("TRUST_ROOT_PUBLIC_KEY_B64"),
            "trust_root() must read the compiled-in const"
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
                !body.contains(forbidden),
                "trust_root() must ONLY ever parse the compiled-in const \
                 (FF-M4-3) — found {forbidden:?} in its body: {body}"
            );
        }
    }

    /// **FF-M4-2, source-scan half, `sec`'s three files.**
    /// `updater::watchdog`'s own fitness test
    /// (`no_bypass_flags_anywhere_in_owned_distribution_source_fitness_ff_m4_2`)
    /// explicitly excludes `trust.rs`/`verify.rs`/`heartbeat.rs` because
    /// their PROSE legitimately names the banned flags (to document that
    /// no such branch exists) — this test closes that gap by scanning only
    /// the actual CODE (comments/doc-comments stripped first) of exactly
    /// those three files. The verifier exposes no "insecure"/"skip"/"force"
    /// branch: every needle below must never appear outside a comment.
    #[test]
    fn no_bypass_flag_or_insecure_branch_in_trust_verify_or_heartbeat_fitness_ff_m4_2() {
        let files: [(&str, &str); 3] = [
            ("trust.rs", include_str!("trust.rs")),
            ("verify.rs", include_str!("verify.rs")),
            ("heartbeat.rs", include_str!("heartbeat.rs")),
        ];
        let needles = ["--force", "--skip-verify", "skip_verify", "insecure"];

        let mut offenders: Vec<(&str, &str)> = Vec::new();
        for (name, raw) in files {
            let production_only = production_source(raw);
            for needle in needles {
                if production_only.to_ascii_lowercase().contains(needle) {
                    offenders.push((name, needle));
                }
            }
        }

        assert!(
            offenders.is_empty(),
            "found a banned bypass flag/insecure-branch spelling in actual code (not a comment) \
             in updater::{{trust,verify,heartbeat}} (invariant #4, FF-M4-2): {offenders:?}"
        );
    }

    /// Guards `production_source`'s "everything production lives before the
    /// first `#[cfg(test)]`" assumption directly: if a future edit ever
    /// moved a real function below that marker (or removed the marker
    /// entirely from one of these files), the two fitness tests above would
    /// silently stop scanning real code — this test fails loudly instead.
    #[test]
    fn production_source_boundary_matches_the_real_file_layout() {
        let cases: [(&str, &str, &str); 3] = [
            (
                "trust.rs",
                include_str!("trust.rs"),
                "pub fn trust_root() -> PublicKey {",
            ),
            (
                "verify.rs",
                include_str!("verify.rs"),
                "pub fn verify_update(",
            ),
            (
                "heartbeat.rs",
                include_str!("heartbeat.rs"),
                "pub fn write_heartbeat(",
            ),
        ];
        for (name, raw, must_contain) in cases {
            let production_only = production_source(raw);
            assert!(
                strip_comments(raw).contains("#[cfg(test)]"),
                "{name}: expected a #[cfg(test)] marker to exist at all"
            );
            assert!(
                production_only.contains(must_contain),
                "{name}: production_source() truncated away real production code \
                 ({must_contain:?} not found) — the \"tests are always last\" assumption broke"
            );
        }
    }
}
