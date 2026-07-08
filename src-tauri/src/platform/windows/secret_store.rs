//! Windows [`PlatformSecretStore`](crate::platform::PlatformSecretStore) —
//! M9/Stream-G (task 76, `sec`). **No Windows toolchain exists on this
//! machine** — authored and `fmt`/`clippy`-reviewed only, never compiled or
//! run.
//!
//! ## Scope (read this before adding anything to this file — invariant #6)
//!
//! [`crate::platform::PlatformSecretStore`]'s own doc is explicit: this
//! trait covers **only the ENDPOINT-REFERENCE half** this app owns (the
//! managed shared secret store's `url`/`tier`, never a secret value) — the
//! SAME scope [`crate::platform::macos::secret_store::MacSecretStore`]
//! already implements as a thin wrapper over
//! [`crate::managed::secret_store::secret_store_endpoint`]. This module is
//! that trait's Windows sibling: [`secret_store_endpoint`] reads the SAME
//! two forced-domain keys (`SharedSecretStoreURL`, `SharedSecretStoreTier`
//! — [`crate::managed::keys::MANAGED_KEYS`], never a second,
//! independently-spelled pair) via [`super::forced`] (Stream-D's
//! `HKLM\...\Policies` + domain-join/MDM-enrollment-gated reader,
//! ADR-M9-003) instead of macOS's `CFPreferences` boundary — same three-way
//! semantics, same "both halves must be genuinely forced or the reference
//! is absent" rule, ported through a different OS boundary rather than
//! reimplemented ad hoc.
//!
//! **This module never calls a keychain/Credential-Manager API, never
//! performs an HTTP fetch, and never caches to disk** — identical
//! discipline to `managed::secret_store`'s own module doc, enforced by this
//! task's own fitness test,
//! `tests/fitness_m9_windows_secret_store_no_secret_leak.rs` (the Windows
//! sibling of `tests/fitness_m5_secretstore_reference_only.rs`).
//! [`SecretStoreRef`](crate::managed::secret_store::SecretStoreRef) itself
//! is reused unchanged (`url: String` + `tier: String`, no field named
//! `secret`/`token`/`password`/`value`) — this module does not define its
//! own DTO.
//!
//! ## What this module deliberately does NOT implement, and why (evidence,
//! not a guess)
//!
//! The task brief that seeded this stub file (task 76's own description,
//! and `windows-parity.md` §1 row 4 / ADR-M9-001's own seam note) also
//! names **Windows Credential Manager / DPAPI via the `keyring` crate** —
//! i.e., a real per-secret STORAGE backend, not merely an endpoint
//! reference — as something "Stream-G" covers. Reading the actual,
//! already-ratified interfaces this task must fill in (not a
//! reinterpretation — direct textual evidence):
//!
//! - [`crate::platform::PlatformSecretStore`]'s own doc comment (`platform/mod.rs`):
//!   "Windows' real per-secret storage backend (Credential Manager/DPAPI
//!   via the `keyring` crate, `windows::secret_store`, Stream-G) is a
//!   **DIFFERENT, lower-level concern this app itself never touches
//!   directly** (the CLI resolves the actual secret VALUE —
//!   `credentials-and-boundary.md` §1.6.4). **This trait covers only the
//!   ENDPOINT-REFERENCE half this app owns.**"
//! - This file's own pre-existing stub doc (Stream-B, task 71): "The REAL
//!   per-secret storage backend... is a separate, lower-level concern this
//!   app itself never calls directly... this stub exists for the
//!   reference-only half, not the keyring integration itself."
//! - `managed::secret_store`'s own module doc (the module this one ports):
//!   "never calls a keychain API... never performs an HTTP/network fetch...
//!   resolving a secret **value** from the store is the CLI's job... not
//!   this app's."
//! - `credentials-and-boundary.md` §3's own ownership table: for "Shared
//!   secret store connection," the CLI "**Owns it**"; Control Tower's row
//!   says "**No role**."
//!
//! All four sources agree: actually calling Credential Manager/DPAPI to
//! store or retrieve a secret VALUE is the **CLI's** job, never this app's
//! (Tauri/Rust `src-tauri` crate) — matching invariant #1 ("parse, never
//! compute": Control Tower renders and invokes, it does not itself perform
//! resolution). **Implementing a `keyring`-backed store/retrieve function
//! in this file would be new, uncalled, dead capability that contradicts
//! all four of the sources above and would widen this app's own attack
//! surface for no product need** — nothing in this crate would ever call
//! it (there is no code path anywhere in `src-tauri` that resolves a secret
//! VALUE at all; that is deliberately absent by design). Security review
//! (this task): **do not add it.** The `keyring = { ..., features =
//! ["windows-native"] }` dependency Stream-B pre-declared in `Cargo.toml`
//! under `[target.'cfg(windows)'.dependencies]` remains declared (removing
//! it is Stream-B's file, out of this task's scope, and a future Windows
//! CLI-side companion binary in a *different* crate may legitimately want
//! the same call shape as a real macOS Keychain-backed implementation
//! would use — the comment there says exactly this) but is **not used
//! anywhere in this file**, matching macOS's own `secret_store.rs`, which
//! likewise never imports `security-framework` despite living in the same
//! crate that (elsewhere, in the CLI it supervises, not here) ultimately
//! depends on Keychain access.
//!
//! If a future milestone genuinely needs Control Tower itself to read/write
//! Windows Credential Manager directly (a scope change from what's ratified
//! today), that is a new ADR, not a silent addition to this file — flag it
//! for @agent-ta, don't implement it under this task's authority.

#![cfg(windows)]

use crate::managed::secret_store::SecretStoreRef;
use crate::platform::PlatformSecretStore;

/// The two forced-domain key names this module reads — literal-matched
/// against `managed::keys::MANAGED_KEYS`, exactly as
/// `managed::secret_store`'s own local consts are (see that module's own
/// `tests::key_names_match_the_frozen_registry` for the drift guard this
/// module's tests mirror below).
const SHARED_SECRET_STORE_URL_KEY: &str = "SharedSecretStoreURL";
const SHARED_SECRET_STORE_TIER_KEY: &str = "SharedSecretStoreTier";

/// Reads the managed shared secret-store endpoint reference via
/// [`super::forced`] (Stream-D, ADR-M9-003) — the Windows sibling of
/// [`crate::managed::secret_store::secret_store_endpoint`]. Returns `None`
/// — never an error — when either key is absent, or present but not
/// genuinely forced (unenrolled machine, or, in principle, a simulated
/// user-domain dev-seam value) — same "both halves must be forced or the
/// reference is absent" rule, same graceful-floor semantics (a caller
/// receiving `None` falls through to the per-user OS keychain floor exactly
/// as it would for any other rung miss, `credentials-and-boundary.md`
/// §1.6.3).
pub fn secret_store_endpoint() -> Option<SecretStoreRef> {
    use super::forced::forced_string;
    use crate::managed::forced::ForcedLookup;

    // Mirrors managed::secret_store::secret_store_endpoint's exact
    // three-way handling per key (Forced / IgnoredUserDomain / Absent) —
    // duplicated rather than shared because the two modules read through
    // different OS boundaries (`crate::managed::forced` vs.
    // `super::forced`) and this task's scope is `platform/windows/*.rs`
    // only. Both keys are read via `forced_string` directly (never via a
    // default-falling-back resolver) so a half-populated reference is never
    // synthesized from a fallback default.

    let url = match forced_string(SHARED_SECRET_STORE_URL_KEY) {
        ForcedLookup::Forced(v) => v,
        ForcedLookup::IgnoredUserDomain => {
            crate::managed::forced::audit_ignored_user_domain_value(SHARED_SECRET_STORE_URL_KEY);
            return None;
        }
        ForcedLookup::Absent => return None,
    };
    let tier = match forced_string(SHARED_SECRET_STORE_TIER_KEY) {
        ForcedLookup::Forced(v) => v,
        ForcedLookup::IgnoredUserDomain => {
            crate::managed::forced::audit_ignored_user_domain_value(SHARED_SECRET_STORE_TIER_KEY);
            return None;
        }
        ForcedLookup::Absent => return None,
    };

    Some(SecretStoreRef { url, tier })
}

/// Zero-field — carries no state of its own; delegates straight through to
/// [`secret_store_endpoint`], matching
/// [`crate::platform::macos::secret_store::MacSecretStore`]'s exact shape.
#[derive(Debug, Default, Clone, Copy)]
pub struct WindowsSecretStore;

impl PlatformSecretStore for WindowsSecretStore {
    fn secret_store_endpoint(&self) -> Option<SecretStoreRef> {
        secret_store_endpoint()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::managed::keys::MANAGED_KEYS;
    use crate::platform::windows::forced::FORCED_OVERRIDE_ENV_PREFIX;

    fn set_override(key: &str, value: &str) {
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: single-threaded test, uniquely named per-key var.
        unsafe { std::env::set_var(&env_name, value) };
    }

    fn clear_override(key: &str) {
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: single-threaded test.
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn a_genuinely_forced_endpoint_is_returned() {
        set_override(
            SHARED_SECRET_STORE_URL_KEY,
            "forced:https://secrets.acme-corp.internal",
        );
        set_override(SHARED_SECRET_STORE_TIER_KEY, "forced:engineering");

        let endpoint = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(
            endpoint,
            Some(SecretStoreRef {
                url: "https://secrets.acme-corp.internal".to_string(),
                tier: "engineering".to_string(),
            })
        );
    }

    #[test]
    fn absent_both_keys_returns_none() {
        set_override(SHARED_SECRET_STORE_URL_KEY, "absent");
        set_override(SHARED_SECRET_STORE_TIER_KEY, "absent");

        let endpoint = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(endpoint, None);
    }

    #[test]
    fn url_forced_but_tier_absent_is_an_incomplete_reference_treated_as_absent() {
        set_override(
            SHARED_SECRET_STORE_URL_KEY,
            "forced:https://secrets.acme-corp.internal",
        );
        set_override(SHARED_SECRET_STORE_TIER_KEY, "absent");

        let endpoint = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(
            endpoint, None,
            "a half-populated reference must never be returned — both halves must be forced"
        );
    }

    #[test]
    fn a_user_domain_only_url_is_ignored_never_honored() {
        set_override(SHARED_SECRET_STORE_URL_KEY, "user");
        set_override(SHARED_SECRET_STORE_TIER_KEY, "forced:engineering");

        let endpoint = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(
            endpoint, None,
            "invariant #4: a user-domain (non-forced) value must never be honored, even if the \
             other half of the reference is genuinely forced"
        );
    }

    #[test]
    fn wrapper_matches_the_free_function() {
        set_override(
            SHARED_SECRET_STORE_URL_KEY,
            "forced:https://secrets.acme-corp.internal",
        );
        set_override(SHARED_SECRET_STORE_TIER_KEY, "forced:engineering");

        let wrapper = WindowsSecretStore;
        let via_wrapper = wrapper.secret_store_endpoint();
        let via_direct = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(via_wrapper, via_direct, "the wrapper must never diverge");
    }

    #[test]
    fn key_names_match_the_frozen_registry() {
        let names: Vec<&str> = MANAGED_KEYS.iter().map(|k| k.name).collect();
        assert!(names.contains(&SHARED_SECRET_STORE_URL_KEY));
        assert!(names.contains(&SHARED_SECRET_STORE_TIER_KEY));
    }
}
