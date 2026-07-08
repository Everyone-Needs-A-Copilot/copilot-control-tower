//! FF-M7-OPTIN (M7/S2, task 61, ADR-M7-003, `docs/08-observability/
//! observability.md` §6, memory `m7-observability-admin-decisions` G-M7-1).
//!
//! Behavioral fitness test for the analytics telemetry opt-in gate
//! (`telemetry::optin`), driven end to end through the crate's real public
//! surface (the dev-mockable `managed::forced` env seam + the real
//! `settings::guard::enforce_write_allowlist` deny-list), not just the
//! within-module unit tests `telemetry::optin`'s own `#[cfg(test)]` block
//! already carries. Complements those unit tests rather than duplicating
//! them — this file is the crate-level acceptance pin a reviewer can read
//! without opening `telemetry/optin.rs` at all.
//!
//! **Asserted here (this task's brief, verbatim):**
//! 1. Default is `Disabled` — no carrier at all ⇒ `Disabled`.
//! 2. A user-domain `TelemetryEnabled=true` is IGNORED — stays `Disabled`,
//!    even with a genuinely forced endpoint present (invariant #4's
//!    Convenience-Backdoor prohibition).
//! 3. `Enabled` requires BOTH a forced enable AND a forced endpoint — enable
//!    without endpoint resolves to `Disabled`, fail-safe, never a guessed
//!    endpoint.
//! 4. Both new managed keys (`TelemetryEnabled`, `TelemetryEndpoint`) are in
//!    `settings::guard`'s write-side deny-list — a hand-authored value for
//!    either key in `copilot.layers.yml` is refused, exactly like every
//!    other M4/M5 security-sensitive key.
//!
//! Serialized on `ENV_LOCK` throughout (same lock `managed::forced`'s own
//! tests already share) since this crate's dev-seam env vars are
//! process-global state and `cargo test` runs this crate's tests in
//! parallel by default.

use copilot_control_tower_lib::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;
use copilot_control_tower_lib::settings::guard::{enforce_write_allowlist, GuardErrorKind};
use copilot_control_tower_lib::settings::manifest::parse_manifest;
use copilot_control_tower_lib::telemetry::optin::{
    telemetry_optin, TelemetryDecision, TELEMETRY_ENABLED_KEY, TELEMETRY_ENDPOINT_KEY,
};

use std::sync::Mutex;

// A dedicated lock (rather than reaching into the lib crate's private
// `cli::test_env::ENV_LOCK`, which is `pub(crate)` and not visible from an
// external integration test binary) — serializes only the env-var mutation
// this file itself performs, which is sufficient: no other test file writes
// these two specific `CT_FORCED_OVERRIDE_TELEMETRY*` env vars.
static TELEMETRY_ENV_LOCK: Mutex<()> = Mutex::new(());

fn set_forced(key: &str, value: &str) {
    // SAFETY: serialized by TELEMETRY_ENV_LOCK for the duration of each test
    // below.
    unsafe {
        std::env::set_var(
            format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase()),
            value,
        )
    };
}

fn clear_forced(key: &str) {
    unsafe {
        std::env::remove_var(format!(
            "{FORCED_OVERRIDE_ENV_PREFIX}{}",
            key.to_ascii_uppercase()
        ))
    };
}

fn clear_all() {
    clear_forced(TELEMETRY_ENABLED_KEY);
    clear_forced(TELEMETRY_ENDPOINT_KEY);
}

/// FF-M7-OPTIN #1: no carrier at all ⇒ `Disabled`. The default posture is
/// off, unconditionally.
#[test]
fn ff_m7_optin_default_is_disabled_with_no_carrier() {
    let _guard = TELEMETRY_ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    clear_all();
    assert_eq!(telemetry_optin(), TelemetryDecision::Disabled);
}

/// FF-M7-OPTIN #2: a user-domain `TelemetryEnabled=true` is IGNORED — the
/// gate stays `Disabled` even though a forced endpoint is genuinely present.
#[test]
fn ff_m7_optin_user_domain_enable_is_ignored() {
    let _guard = TELEMETRY_ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    set_forced(TELEMETRY_ENABLED_KEY, "user");
    set_forced(
        TELEMETRY_ENDPOINT_KEY,
        "forced:https://collect.acme-corp.example/v1",
    );
    assert_eq!(
        telemetry_optin(),
        TelemetryDecision::Disabled,
        "a user-writable-domain opt-in value must never be honored (invariant #4)"
    );
    clear_all();
}

/// FF-M7-OPTIN #3a: forced enable, forced endpoint ⇒ `Enabled` with that
/// endpoint. The one genuinely-enabled path.
#[test]
fn ff_m7_optin_forced_enable_and_endpoint_yields_enabled() {
    let _guard = TELEMETRY_ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
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
    clear_all();
}

/// FF-M7-OPTIN #3b: forced enable WITHOUT a forced endpoint ⇒ `Disabled` —
/// fail-safe, never a guessed/default endpoint.
#[test]
fn ff_m7_optin_forced_enable_without_endpoint_is_disabled() {
    let _guard = TELEMETRY_ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    set_forced(TELEMETRY_ENABLED_KEY, "forced:true");
    clear_forced(TELEMETRY_ENDPOINT_KEY);
    assert_eq!(telemetry_optin(), TelemetryDecision::Disabled);
    clear_all();
}

/// FF-M7-OPTIN #3c: a forced endpoint WITHOUT a forced enable ⇒ `Disabled` —
/// an endpoint alone is never sufficient.
#[test]
fn ff_m7_optin_forced_endpoint_without_enable_is_disabled() {
    let _guard = TELEMETRY_ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    clear_forced(TELEMETRY_ENABLED_KEY);
    set_forced(
        TELEMETRY_ENDPOINT_KEY,
        "forced:https://collect.acme-corp.example/v1",
    );
    assert_eq!(telemetry_optin(), TelemetryDecision::Disabled);
    clear_all();
}

/// FF-M7-OPTIN #4: both new managed keys are in `settings::guard`'s
/// write-side deny-list — a hand-authored value for either, top-level or
/// per-layer, is refused exactly like every other M4/M5 security-sensitive
/// key (`AdminContact`, `UpdateFeedURL`, etc.).
#[test]
fn ff_m7_optin_telemetry_keys_are_in_the_settings_guard_deny_list() {
    for key in ["TelemetryEnabled", "TelemetryEndpoint"] {
        let top_level_yaml = format!(
            "version: 1\n{key}: \"whatever-value\"\nlayers:\n  - id: personal-pablo\n    role: personal\n    product: claude\n    rank: 10\n    source:\n      repo: git@github-personal:me/repo.git\n    auth: ssh-personal\n    activation: always\n"
        );
        let manifest = parse_manifest(&top_level_yaml)
            .unwrap_or_else(|e| panic!("fixture for {key:?} should parse: {e}"));
        let err = match enforce_write_allowlist(&manifest) {
            Ok(()) => panic!("top-level key {key:?} must be refused by settings::guard"),
            Err(e) => e,
        };
        assert_eq!(err.kind, GuardErrorKind::DisallowedField, "key {key:?}");

        let per_layer_yaml = format!(
            "version: 1\nlayers:\n  - id: personal-pablo\n    role: personal\n    product: claude\n    rank: 10\n    source:\n      repo: git@github-personal:me/repo.git\n    auth: ssh-personal\n    activation: always\n    {key}: \"whatever-value\"\n"
        );
        let manifest = parse_manifest(&per_layer_yaml)
            .unwrap_or_else(|e| panic!("fixture for {key:?} should parse: {e}"));
        let err = match enforce_write_allowlist(&manifest) {
            Ok(()) => panic!("per-layer key {key:?} must be refused by settings::guard"),
            Err(e) => e,
        };
        assert_eq!(err.kind, GuardErrorKind::DisallowedField, "key {key:?}");
    }
}
