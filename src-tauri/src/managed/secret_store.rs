//! The managed shared secret-store **endpoint reference** reader (M5/S5,
//! `.copilot/wp/30.md` task 48, `credentials-and-boundary.md` §1.6.2 step 6 /
//! §1.6.3 rung 1 / §1.6.4).
//!
//! ## Reference, never a value (invariant #6 — the whole point of this file)
//!
//! `credentials-and-boundary.md` §1.6.4 is explicit: the shared secret store
//! is "a resolution-time API the CLI calls, not a channel content flows
//! through." This module reads exactly two forced-domain preferences —
//! `SharedSecretStoreURL` and `SharedSecretStoreTier` — and returns them
//! packaged as [`SecretStoreRef`], **an endpoint reference (where + which
//! tier), never a secret value**. This module:
//!
//! - never calls a keychain API (no `Security.framework`/`security` binary/
//!   `keyring` crate anywhere in this file);
//! - never performs an HTTP/network fetch (no `reqwest`/`ureq`/socket call
//!   anywhere in this file) — resolving a secret **value** from the store is
//!   the CLI's job at `requires_secret` resolution time
//!   (`credentials-and-boundary.md` §3's table: "Owns it — performs the
//!   scoped, authenticated API read... Control Tower: No role"), not this
//!   app's;
//! - never caches anything to disk — every call re-reads the forced domain.
//!
//! [`SecretStoreRef`] itself carries only `url: String` + `tier: String` — no
//! field named `secret`/`token`/`password`/`value` exists on it, checked both
//! by [`tests::secret_store_ref_has_no_secret_value_field`] (a `Debug`-format
//! grep of a live instance's field names) and by
//! `tests/fitness_m5_secretstore_reference_only.rs` (a source-scan of this
//! file, matching the style `settings::guard`'s
//! `no_entry_carries_anything_that_looks_like_a_literal_secret_value` and
//! `managed::keys`'s companion test already established).
//!
//! ## Forced-domain-only; a user-domain value is IGNORED (invariant #4)
//!
//! [`secret_store_endpoint`] reads both keys via [`super::forced::forced_string`]
//! — the sole audited `CFPreferences` boundary (M5/S1). A value present only
//! in the ordinary user-writable preferences domain (never forced) is
//! **never honored**: it is audited as a tamper event
//! (`super::forced::audit_ignored_user_domain_value`) and the lookup is
//! treated exactly like [`super::forced::ForcedLookup::Absent`] — see
//! `credentials-and-boundary.md` §1.6.2 step 6, "If no managed key is
//! present, the CLI treats the shared-store rung as absent, never
//! misconfigured, and falls through the ladder without guessing a URL from
//! convention or environment." This module never guesses either.
//!
//! ## Absent is normal, not an error (§1.6.6 — the graceful floor)
//!
//! [`secret_store_endpoint`] returns `Option<SecretStoreRef>`, not a
//! `Result`. `None` means exactly one thing to every caller: "this rung of
//! the credential-resolution ladder is absent — fall through to the per-user
//! OS keychain floor (§1.4/§1.6.3 rung 2)," which is the unconditional,
//! always-available baseline (§1.6.6: "a company with neither a shared
//! secret store nor MDM is not blocked"). An absent/incomplete endpoint
//! reference is never rendered as a failure state of its own — per the WP,
//! any downstream UI treats a store miss exactly like any other resolution
//! miss, reusing the existing `Signed-out`-shaped state (no new status
//! class; that render-side wiring is a future stream's concern, not this
//! reader's).
//!
//! An endpoint reference requires **both** halves to be genuinely forced —
//! `SharedSecretStoreURL` alone, or `SharedSecretStoreTier` alone, is an
//! incomplete reference and is treated as absent (`None`), never as a
//! half-populated struct with an empty string standing in for the missing
//! half.

use super::forced::{audit_ignored_user_domain_value, forced_string, ForcedLookup};

/// The two forced-domain key names this module reads — pulled from the
/// frozen registry's literal spellings (`managed::keys::MANAGED_KEYS`) so a
/// future rename of either key in the registry is the one place a mismatch
/// would need fixing; kept as local consts (rather than looking the strings
/// up out of `MANAGED_KEYS` at runtime) to match every other reader in this
/// crate (`updater::trust`'s `UPDATE_FEED_URL_KEY`, etc.) — see this
/// module's own `tests::key_names_match_the_frozen_registry` for the
/// drift guard.
const SHARED_SECRET_STORE_URL_KEY: &str = "SharedSecretStoreURL";
const SHARED_SECRET_STORE_TIER_KEY: &str = "SharedSecretStoreTier";

/// A managed shared secret store's **endpoint reference** — where it lives
/// and which tier-scoped project/namespace this machine's members are
/// authorized against. **Not a secret.** No field here is ever a value read
/// from, or destined for, the store itself — see the module doc's "reference,
/// never a value" section. Deliberately does not derive `Serialize` (nothing
/// in this milestone's scope needs to hand this to the CLI-facing frontend
/// yet; a future consumer adding that derive should re-read this doc first).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SecretStoreRef {
    /// The store's connection endpoint (e.g.
    /// `https://secrets.acme-corp.internal`) — a location, not a credential.
    pub url: String,
    /// Which tier-scoped project/namespace this machine's members resolve
    /// against (`credentials-and-boundary.md` §1.6.2 step 3) — an
    /// identifier, not a credential.
    pub tier: String,
}

/// Reads the managed shared secret-store endpoint reference, forced-domain-
/// ONLY. Returns `None` — never an error — when either key is absent, or
/// present only in the (untrusted) user domain, per §1.6.2 step 6: "absent,
/// never guessed." A caller receiving `None` falls through to the per-user
/// OS keychain floor (§1.4) exactly as it would for any other rung miss.
pub fn secret_store_endpoint() -> Option<SecretStoreRef> {
    let url = match forced_string(SHARED_SECRET_STORE_URL_KEY) {
        ForcedLookup::Forced(v) => v,
        ForcedLookup::IgnoredUserDomain => {
            audit_ignored_user_domain_value(SHARED_SECRET_STORE_URL_KEY);
            return None;
        }
        ForcedLookup::Absent => return None,
    };
    let tier = match forced_string(SHARED_SECRET_STORE_TIER_KEY) {
        ForcedLookup::Forced(v) => v,
        ForcedLookup::IgnoredUserDomain => {
            audit_ignored_user_domain_value(SHARED_SECRET_STORE_TIER_KEY);
            return None;
        }
        ForcedLookup::Absent => return None,
    };

    Some(SecretStoreRef { url, tier })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;

    fn set_override(key: &str, value: &str) {
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK, same discipline every other
        // dev-seam test in this crate (`managed::forced`, `updater::trust`)
        // already uses.
        unsafe { std::env::set_var(&env_name, value) };
    }

    fn clear_override(key: &str) {
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(&env_name) };
    }

    // -- forced-present: honored -----------------------------------------

    #[test]
    fn a_genuinely_forced_endpoint_is_returned() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
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

    // -- absent: rung treated as absent, no error -------------------------

    #[test]
    fn absent_both_keys_returns_none() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_override(SHARED_SECRET_STORE_URL_KEY, "absent");
        set_override(SHARED_SECRET_STORE_TIER_KEY, "absent");

        let endpoint = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(endpoint, None);
    }

    #[test]
    fn url_forced_but_tier_absent_is_an_incomplete_reference_treated_as_absent() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
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
    fn tier_forced_but_url_absent_is_an_incomplete_reference_treated_as_absent() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_override(SHARED_SECRET_STORE_URL_KEY, "absent");
        set_override(SHARED_SECRET_STORE_TIER_KEY, "forced:engineering");

        let endpoint = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(endpoint, None);
    }

    // -- user-domain-only: ignored + audited, never honored ----------------

    #[test]
    fn a_user_domain_only_url_is_ignored_never_honored() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
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
    fn a_user_domain_only_tier_is_ignored_never_honored() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_override(
            SHARED_SECRET_STORE_URL_KEY,
            "forced:https://secrets.acme-corp.internal",
        );
        set_override(SHARED_SECRET_STORE_TIER_KEY, "user");

        let endpoint = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(endpoint, None);
    }

    #[test]
    fn both_keys_user_domain_only_returns_none() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_override(SHARED_SECRET_STORE_URL_KEY, "user");
        set_override(SHARED_SECRET_STORE_TIER_KEY, "user");

        let endpoint = secret_store_endpoint();

        clear_override(SHARED_SECRET_STORE_URL_KEY);
        clear_override(SHARED_SECRET_STORE_TIER_KEY);

        assert_eq!(endpoint, None);
    }

    // -- drift guard: local key consts match the frozen registry ----------

    #[test]
    fn key_names_match_the_frozen_registry() {
        let names: Vec<&str> = crate::managed::keys::MANAGED_KEYS
            .iter()
            .map(|k| k.name)
            .collect();
        assert!(names.contains(&SHARED_SECRET_STORE_URL_KEY));
        assert!(names.contains(&SHARED_SECRET_STORE_TIER_KEY));
    }

    // -- fitness (unit half): the DTO carries no secret-value field --------

    /// A crude but effective check, matching the style
    /// `settings::guard`'s own secret-shape fitness tests already use: a
    /// `Debug`-formatted instance's text can only ever contain the two field
    /// NAMES this struct declares (`url`, `tier`) plus their values — never
    /// a third field named `secret`/`token`/`password`/`value`. The
    /// authoritative, source-scan half of this same assertion lives in
    /// `tests/fitness_m5_secretstore_reference_only.rs` (crate-integration
    /// tests can read this file's literal source text; a unit test cannot
    /// reflect on its own struct's field names at runtime in safe Rust).
    #[test]
    fn secret_store_ref_has_no_secret_value_field() {
        let debug = format!(
            "{:?}",
            SecretStoreRef {
                url: "https://example.invalid".to_string(),
                tier: "engineering".to_string(),
            }
        );
        assert!(debug.contains("url:"));
        assert!(debug.contains("tier:"));
        for forbidden in ["secret:", "token:", "password:", "value:"] {
            assert!(
                !debug.to_ascii_lowercase().contains(forbidden),
                "SecretStoreRef's Debug output unexpectedly contains {forbidden:?} — \
                 invariant #6 violation"
            );
        }
    }
}
