//! FF-M7-OPTIN — the analytics telemetry opt-in gate + endpoint resolution
//! (M7/S2, task 61, ADR-M7-003, `docs/08-observability/observability.md` §6,
//! memory `m7-observability-admin-decisions` G-M7-1).
//!
//! ## The invariant this file exists to hold
//!
//! Analytics telemetry is **off by default, everywhere**, and can be turned
//! on **only** by a trusted carrier — never by a value sitting in the
//! ordinary user-writable preferences domain. This mirrors, byte for byte,
//! the same "security-sensitive state is honored only from a forced/managed
//! domain, never user-editable config" discipline `managed::forced` already
//! enforces for `UpdateFeedURL`/`AdminContact`/etc. (invariant #4) — applied
//! here to a NEW pair of keys this task adds to that same frozen registry.
//!
//! This module does not implement the emitter, the transport, or any
//! network call — it answers exactly one question: **given what the trusted
//! carrier currently says, is analytics telemetry enabled, and if so, where
//! does it go?** [`telemetry_optin`] returns a closed, two-variant
//! [`TelemetryDecision`] — `Enabled { endpoint }` or `Disabled` — and that is
//! the entire public surface S3's emitter needs to gate on.
//!
//! ## G-M7-1 — carrier divergence, resolved for this build (flagged, not
//! silently picked)
//!
//! Two sources disagree on where the analytics opt-in lives:
//!
//! - The M7 brief (`.copilot/wp/43.md` ADR-M7-003, task 61's own
//!   description) says "enabled via forced/managed domain."
//! - The canonical `observability.md` §1/§6 says analytics opt-in
//!   (`telemetry.enabled`/`telemetry.endpoint`) lives in the org's own
//!   **signed `ecosystem.yml`**, surfaced to the app only as a future CLI
//!   `--json` field — because the app cannot itself verify an
//!   `ecosystem.yml` signature (invariant #1: parse, never compute). Only
//!   `AdminContact` (the SAFETY channel, a different carrier entirely per
//!   ADR-M7-003's "two carriers, not one flag") is named as forced-domain in
//!   that doc.
//!
//! Neither source is followed uncritically. **What this build does:**
//! default OFF; read the opt-in decision from a **trusted carrier behind a
//! seam** ([`TelemetryCarrier`]) rather than hard-wiring either answer
//! directly into the gate function. The **interim implementation** of that
//! seam is the forced/managed domain (`managed::forced`, via
//! [`ForcedDomainCarrier`]) — the ONLY carrier this crate can independently
//! verify today (there is no CLI `--json` field for `telemetry.enabled`/
//! `telemetry.endpoint` yet — G-M7-2 in the architecture memory: "fleet-event
//! schema not yet a versioned `--json` home," and no such field exists for
//! the opt-in itself either). A user-domain value for either key is IGNORED
//! (resolves to the compiled-in default: disabled/absent), exactly like
//! every other entry in `managed::keys::MANAGED_KEYS`.
//!
//! The **documented seam for the eventual CLI-field carrier**: once WS-A
//! exposes `telemetry.enabled`/`telemetry.endpoint` as parsed fields on some
//! `--json` verb (sourced from the CLI's own verified read of the signed
//! `ecosystem.yml`), a second [`TelemetryCarrier`] implementation reads those
//! parsed fields instead of `managed::forced` — no change to
//! [`telemetry_optin`]'s signature or to [`TelemetryDecision`], only a new
//! carrier plugged into the same seam. **Which of the two carriers is the
//! FINAL, ship-worthy source of truth is owner-gated (G-M7-1)** — this build
//! ships the forced-domain interim carrier as the default so the gate is
//! real and testable today, not left unimplemented pending that ratification.
//!
//! ## Fail-safe composition: enable requires BOTH parts, or it's Disabled
//!
//! A forced `TelemetryEnabled=true` with no forced `TelemetryEndpoint` (or
//! vice versa) resolves to [`TelemetryDecision::Disabled`] — **never** a
//! guessed/default endpoint (`observability.md` §6: "not a reduced payload,
//! not a default endpoint guessed from convention"). Both facts must
//! independently clear the trusted-carrier bar before a single analytics
//! byte is permitted to leave the machine.

use crate::managed::forced;

/// The managed-key name for the analytics opt-in boolean. Frozen in
/// [`crate::managed::keys::MANAGED_KEYS`] — see that module for the
/// evidence-based `security_sensitive`/`forced_only` classification.
pub const TELEMETRY_ENABLED_KEY: &str = "TelemetryEnabled";

/// The managed-key name for the analytics collector endpoint. An ENDPOINT
/// REFERENCE only (owner infra, G-M7-3) — never a secret, matching the same
/// "URL reference, not credential material" shape `SharedSecretStoreURL`
/// already established in this registry.
pub const TELEMETRY_ENDPOINT_KEY: &str = "TelemetryEndpoint";

/// The outcome of the opt-in gate — the ONLY two shapes S3's emitter (or any
/// future caller) ever needs to branch on. Deliberately not an `Option` or a
/// `bool` + separate endpoint getter: bundling the endpoint INSIDE the
/// `Enabled` variant makes "enabled but no endpoint" structurally
/// unrepresentable as a callable-looking success case — a caller cannot
/// accidentally match `Enabled` and then unwrap a missing endpoint, because
/// there is no such state to construct.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TelemetryDecision {
    /// Analytics telemetry is enabled; send events to `endpoint`. Only ever
    /// constructed when BOTH the enable flag and the endpoint were resolved
    /// from a trusted carrier (see [`telemetry_optin`]).
    Enabled { endpoint: String },
    /// The default, and the safe fallback for every absent/partial/
    /// untrusted-carrier case. No analytics bytes are ever sent.
    Disabled,
}

impl TelemetryDecision {
    /// `true` only for [`TelemetryDecision::Enabled`] — convenience for a
    /// caller that only needs the boolean fact, not the endpoint.
    pub fn is_enabled(&self) -> bool {
        matches!(self, TelemetryDecision::Enabled { .. })
    }

    /// The endpoint, if enabled. `None` for `Disabled` — there is never a
    /// "disabled but here's a leftover endpoint" state to accidentally read.
    pub fn endpoint(&self) -> Option<&str> {
        match self {
            TelemetryDecision::Enabled { endpoint } => Some(endpoint.as_str()),
            TelemetryDecision::Disabled => None,
        }
    }
}

/// The trusted-carrier seam (G-M7-1). A `TelemetryCarrier` answers exactly
/// two questions — "is analytics forced-enabled" and "what's the
/// forced-endpoint" — without [`telemetry_optin`] itself knowing whether the
/// answer came from the forced/managed domain or (in a future build) a
/// parsed CLI `--json` field. Every method returns the SAME three-way shape
/// `managed::forced::ForcedLookup` already established for exactly this
/// reason: "is there a value" is the wrong question, "is it TRUSTED" is the
/// one that matters, and a user-domain value must resolve identically to
/// "absent" (ignored, never honored) regardless of which concrete carrier is
/// plugged in.
pub trait TelemetryCarrier {
    /// Whether the carrier says analytics is enabled. An
    /// [`forced::ForcedLookup::IgnoredUserDomain`] here is the exact
    /// Convenience-Backdoor shape invariant #4 forbids — the carrier itself
    /// (not this trait) is responsible for auditing that case, exactly as
    /// `managed::forced` already does.
    fn enabled(&self) -> forced::ForcedLookup<bool>;

    /// Whether the carrier provides an endpoint, and what it is.
    fn endpoint(&self) -> forced::ForcedLookup<String>;
}

/// The interim (G-M7-1) trusted carrier: the forced/managed domain, read via
/// [`crate::managed::forced`] — the same FFI boundary every other
/// security-sensitive managed key in this app goes through. See the module
/// doc's "carrier divergence" section for why this is the interim answer,
/// not (yet) the owner-ratified final one.
pub struct ForcedDomainCarrier;

impl TelemetryCarrier for ForcedDomainCarrier {
    fn enabled(&self) -> forced::ForcedLookup<bool> {
        forced::forced_bool(TELEMETRY_ENABLED_KEY)
    }

    fn endpoint(&self) -> forced::ForcedLookup<String> {
        forced::forced_string(TELEMETRY_ENDPOINT_KEY)
    }
}

/// The default, real entry point every caller (S3's emitter) should use:
/// resolves the opt-in decision against the interim trusted carrier
/// ([`ForcedDomainCarrier`]). See [`telemetry_optin_via`] for the
/// carrier-generic form this delegates to (used directly by this module's
/// own tests, and by a future CLI-field carrier once G-M7-1 is ratified).
pub fn telemetry_optin() -> TelemetryDecision {
    telemetry_optin_via(&ForcedDomainCarrier)
}

/// The carrier-generic gate. Default `Disabled`; `Enabled` only when BOTH
/// [`TelemetryCarrier::enabled`] resolves to `Forced(true)` AND
/// [`TelemetryCarrier::endpoint`] resolves to a `Forced` non-empty string —
/// every other combination (absent, user-domain, enabled-without-endpoint,
/// endpoint-without-enabled, forced `false`) resolves to `Disabled`,
/// fail-safe (`observability.md` §6: "absent ⇒ zero analytics bytes leave
/// the machine... never a guessed endpoint").
pub fn telemetry_optin_via(carrier: &dyn TelemetryCarrier) -> TelemetryDecision {
    let enabled = matches!(carrier.enabled(), forced::ForcedLookup::Forced(true));
    if !enabled {
        return TelemetryDecision::Disabled;
    }

    match carrier.endpoint() {
        forced::ForcedLookup::Forced(endpoint) if !endpoint.trim().is_empty() => {
            TelemetryDecision::Enabled { endpoint }
        }
        // A forced-but-empty endpoint string is treated identically to
        // "no endpoint" — never guessed, never substituted (§6).
        _ => TelemetryDecision::Disabled,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::keys::{ManagedKey, MANAGED_KEYS};

    /// Confirms both new keys are actually present, and correctly
    /// classified, in the frozen `managed::keys::MANAGED_KEYS` registry this
    /// module reads through `managed::forced`.
    fn registry_entry(name: &str) -> Option<&'static ManagedKey> {
        MANAGED_KEYS.iter().find(|k| k.name == name)
    }

    // -- registry wiring: the two new keys are real, forced-only,
    //    security-sensitive entries in the frozen registry ------------------

    #[test]
    fn telemetry_enabled_key_is_registered_forced_only_and_security_sensitive() {
        let entry = registry_entry(TELEMETRY_ENABLED_KEY)
            .unwrap_or_else(|| panic!("{TELEMETRY_ENABLED_KEY} must be in MANAGED_KEYS"));
        assert!(entry.forced_only, "TelemetryEnabled must be forced_only");
        assert!(
            entry.security_sensitive,
            "TelemetryEnabled must be security_sensitive"
        );
    }

    #[test]
    fn telemetry_endpoint_key_is_registered_forced_only_and_security_sensitive() {
        let entry = registry_entry(TELEMETRY_ENDPOINT_KEY)
            .unwrap_or_else(|| panic!("{TELEMETRY_ENDPOINT_KEY} must be in MANAGED_KEYS"));
        assert!(entry.forced_only, "TelemetryEndpoint must be forced_only");
        assert!(
            entry.security_sensitive,
            "TelemetryEndpoint must be security_sensitive"
        );
    }

    // -- TelemetryDecision shape -----------------------------------------

    #[test]
    fn disabled_reports_not_enabled_and_no_endpoint() {
        let d = TelemetryDecision::Disabled;
        assert!(!d.is_enabled());
        assert_eq!(d.endpoint(), None);
    }

    #[test]
    fn enabled_reports_enabled_and_its_endpoint() {
        let d = TelemetryDecision::Enabled {
            endpoint: "https://telemetry.example.org/collect".to_string(),
        };
        assert!(d.is_enabled());
        assert_eq!(d.endpoint(), Some("https://telemetry.example.org/collect"));
    }

    // -- a minimal mock carrier for the pure telemetry_optin_via matrix,
    //    independent of the env-var dev seam (belt + suspenders alongside
    //    the real-carrier env-seam tests below) ----------------------------

    struct MockCarrier {
        enabled: forced::ForcedLookup<bool>,
        endpoint: forced::ForcedLookup<String>,
    }

    impl TelemetryCarrier for MockCarrier {
        fn enabled(&self) -> forced::ForcedLookup<bool> {
            self.enabled.clone()
        }
        fn endpoint(&self) -> forced::ForcedLookup<String> {
            self.endpoint.clone()
        }
    }

    #[test]
    fn mock_forced_enable_and_forced_endpoint_yields_enabled() {
        let carrier = MockCarrier {
            enabled: forced::ForcedLookup::Forced(true),
            endpoint: forced::ForcedLookup::Forced("https://org.example/collect".to_string()),
        };
        assert_eq!(
            telemetry_optin_via(&carrier),
            TelemetryDecision::Enabled {
                endpoint: "https://org.example/collect".to_string()
            }
        );
    }

    #[test]
    fn mock_forced_enable_without_endpoint_is_disabled_fail_safe() {
        let carrier = MockCarrier {
            enabled: forced::ForcedLookup::Forced(true),
            endpoint: forced::ForcedLookup::Absent,
        };
        assert_eq!(telemetry_optin_via(&carrier), TelemetryDecision::Disabled);
    }

    #[test]
    fn mock_forced_endpoint_without_enable_is_disabled() {
        let carrier = MockCarrier {
            enabled: forced::ForcedLookup::Absent,
            endpoint: forced::ForcedLookup::Forced("https://org.example/collect".to_string()),
        };
        assert_eq!(telemetry_optin_via(&carrier), TelemetryDecision::Disabled);
    }

    #[test]
    fn mock_user_domain_enable_is_ignored_stays_disabled() {
        let carrier = MockCarrier {
            enabled: forced::ForcedLookup::IgnoredUserDomain,
            endpoint: forced::ForcedLookup::Forced("https://org.example/collect".to_string()),
        };
        assert_eq!(telemetry_optin_via(&carrier), TelemetryDecision::Disabled);
    }

    #[test]
    fn mock_forced_false_is_disabled_even_with_a_forced_endpoint() {
        let carrier = MockCarrier {
            enabled: forced::ForcedLookup::Forced(false),
            endpoint: forced::ForcedLookup::Forced("https://org.example/collect".to_string()),
        };
        assert_eq!(telemetry_optin_via(&carrier), TelemetryDecision::Disabled);
    }

    #[test]
    fn mock_absent_everything_is_disabled() {
        let carrier = MockCarrier {
            enabled: forced::ForcedLookup::Absent,
            endpoint: forced::ForcedLookup::Absent,
        };
        assert_eq!(telemetry_optin_via(&carrier), TelemetryDecision::Disabled);
    }

    #[test]
    fn mock_forced_enable_with_a_forced_but_empty_endpoint_is_disabled() {
        let carrier = MockCarrier {
            enabled: forced::ForcedLookup::Forced(true),
            endpoint: forced::ForcedLookup::Forced("   ".to_string()),
        };
        assert_eq!(telemetry_optin_via(&carrier), TelemetryDecision::Disabled);
    }

    // -- the real ForcedDomainCarrier + telemetry_optin(), driven through
    //    managed::forced's dev-mockable per-key env seam (FF-M7-OPTIN's
    //    required unit-test coverage, per this task's brief) --------------

    fn set_forced(key: &str, value: &str) {
        // SAFETY: serialized by ENV_LOCK, matching every other
        // `managed::forced` env-seam test in this crate.
        unsafe {
            std::env::set_var(
                format!(
                    "{}{}",
                    forced::FORCED_OVERRIDE_ENV_PREFIX,
                    key.to_ascii_uppercase()
                ),
                value,
            )
        };
    }

    fn clear_forced(key: &str) {
        unsafe {
            std::env::remove_var(format!(
                "{}{}",
                forced::FORCED_OVERRIDE_ENV_PREFIX,
                key.to_ascii_uppercase()
            ))
        };
    }

    /// Default (no carrier at all) ⇒ Disabled. FF-M7-OPTIN's first
    /// assertion: "no carrier → Disabled."
    #[test]
    fn ff_m7_optin_default_no_carrier_is_disabled() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);
        assert_eq!(telemetry_optin(), TelemetryDecision::Disabled);
    }

    /// FF-M7-OPTIN: forced enable + forced endpoint ⇒ Enabled.
    #[test]
    fn ff_m7_optin_forced_enable_and_forced_endpoint_yields_enabled() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_forced(TELEMETRY_ENABLED_KEY, "forced:true");
        set_forced(
            TELEMETRY_ENDPOINT_KEY,
            "forced:https://collect.acme-corp.example/v1",
        );
        assert_eq!(
            telemetry_optin(),
            TelemetryDecision::Enabled {
                endpoint: "https://collect.acme-corp.example/v1".to_string()
            }
        );
        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);
    }

    /// FF-M7-OPTIN: forced enable, NO endpoint ⇒ Disabled (fail-safe — never
    /// a guessed endpoint).
    #[test]
    fn ff_m7_optin_forced_enable_without_endpoint_is_disabled() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_forced(TELEMETRY_ENABLED_KEY, "forced:true");
        clear_forced(TELEMETRY_ENDPOINT_KEY);
        assert_eq!(telemetry_optin(), TelemetryDecision::Disabled);
        clear_forced(TELEMETRY_ENABLED_KEY);
    }

    /// FF-M7-OPTIN: a user-domain (non-forced) `TelemetryEnabled=true` is
    /// IGNORED — stays Disabled, even with a forced endpoint present.
    #[test]
    fn ff_m7_optin_user_domain_enable_is_ignored_stays_disabled() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_forced(TELEMETRY_ENABLED_KEY, "user");
        set_forced(
            TELEMETRY_ENDPOINT_KEY,
            "forced:https://collect.acme-corp.example/v1",
        );
        assert_eq!(telemetry_optin(), TelemetryDecision::Disabled);
        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);
    }

    /// A user-domain endpoint (even with a genuinely forced enable) is
    /// likewise ignored — neither half of the pair may be smuggled in from
    /// the user-writable domain.
    #[test]
    fn ff_m7_optin_user_domain_endpoint_is_ignored_stays_disabled() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_forced(TELEMETRY_ENABLED_KEY, "forced:true");
        set_forced(TELEMETRY_ENDPOINT_KEY, "user");
        assert_eq!(telemetry_optin(), TelemetryDecision::Disabled);
        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);
    }

    /// A forced `TelemetryEnabled=false` stays Disabled even with a forced
    /// endpoint present — the enable flag is not merely "any forced value
    /// wins," its resolved boolean must be `true`.
    #[test]
    fn ff_m7_optin_forced_false_stays_disabled_even_with_forced_endpoint() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_forced(TELEMETRY_ENABLED_KEY, "forced:false");
        set_forced(
            TELEMETRY_ENDPOINT_KEY,
            "forced:https://collect.acme-corp.example/v1",
        );
        assert_eq!(telemetry_optin(), TelemetryDecision::Disabled);
        clear_forced(TELEMETRY_ENABLED_KEY);
        clear_forced(TELEMETRY_ENDPOINT_KEY);
    }
}
