//! The self-update transport's IPC DTO (M4/S4-S5, `.copilot/wp/24.md`) —
//! mirrored 1:1 by `src/types.ts`'s `UpdateStatus`/`UpdateState` (S10 froze
//! that shape first; this module is the Rust side catching up to it, same
//! "UI builds to the frozen shape, Rust reconciles" convention
//! `settings::dto`'s own header doc used for S1/S6).
//!
//! **This is a DIFFERENT signal from `render::derive::CliStatus`'s**
//! `UpdateAvailable`/`UpdatingApp` — those two are the CLI-parsed,
//! worst-wins verdict about a PRODUCT (Claude Copilot, CLI Copilot, …)
//! needing an update (invariant #1, parse-never-compute, already rendered by
//! M1). `UpdateState` is Control Tower's own binary's self-update TRANSPORT
//! (ADR-M4-004: "M4 must not re-derive [the doctor] verdict; it owns only
//! the transport") — `updater::check` is the only module that constructs
//! one, never a second, drifting notion of "the current update state".
//!
//! Field names are plain snake_case on both sides (no `rename_all` on the
//! struct itself), same convention as `render::derive::RenderState` and
//! `settings::dto::SettingsState` — the web UI reads these fields directly.
//! `status` DOES use `rename_all = "kebab-case"` (the enum, not the struct)
//! so `UpToDate`/`RolledBack` serialize as exactly `"up-to-date"`/
//! `"rolled-back"` — the literal strings `src/types.ts`'s `UpdateStatus`
//! union already names.

use serde::{Deserialize, Serialize};

/// Mirrors `src/types.ts`'s `UpdateStatus` union exactly — ten variants,
/// closed set (frozen by the S10 task brief; a wire-format change here is a
/// deliberate, coordinated edit on both sides, never a silent drift).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum UpdateStatus {
    Idle,
    Checking,
    UpToDate,
    Available,
    Downloading,
    Verifying,
    Staging,
    Ready,
    RolledBack,
    Error,
}

/// The self-update transport's own render contract — see the module doc.
/// `message` is ALWAYS plain language (never raw signature/heartbeat/
/// watchdog text), mirroring `wizard::dto::WizardState`'s `error` field
/// discipline exactly: every `Some(..)` this module ever constructs is
/// either one of `updater::verify::VerifyError`'s own already-plain-language
/// `Display` strings (never leaks key material/secrets, per that module's
/// own test) or a hand-written sentence from `updater::check` — never a raw
/// `std::io::Error`/`reqwest::Error` `Display` (those can carry a local
/// filesystem path or a raw transport error Bob has no use for).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateState {
    pub status: UpdateStatus,
    pub available_version: Option<String>,
    pub current_version: String,
    pub message: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A cheap drift guard against `src/types.ts`'s `UpdateStatus` union,
    /// same spirit as `settings::dto`'s own
    /// `layer_row_serializes_with_plain_snake_case_field_names` test — if a
    /// variant's wire spelling ever drifts from the frozen TS union, this
    /// fails loudly instead of silently mismatching in the browser console.
    #[test]
    fn every_status_variant_serializes_to_the_exact_frozen_ts_spelling() {
        let cases: &[(UpdateStatus, &str)] = &[
            (UpdateStatus::Idle, "\"idle\""),
            (UpdateStatus::Checking, "\"checking\""),
            (UpdateStatus::UpToDate, "\"up-to-date\""),
            (UpdateStatus::Available, "\"available\""),
            (UpdateStatus::Downloading, "\"downloading\""),
            (UpdateStatus::Verifying, "\"verifying\""),
            (UpdateStatus::Staging, "\"staging\""),
            (UpdateStatus::Ready, "\"ready\""),
            (UpdateStatus::RolledBack, "\"rolled-back\""),
            (UpdateStatus::Error, "\"error\""),
        ];
        for (status, wire) in cases {
            assert_eq!(serde_json::to_string(status).unwrap(), *wire);
        }
    }

    #[test]
    fn update_state_serializes_with_plain_snake_case_field_names() {
        let state = UpdateState {
            status: UpdateStatus::Available,
            available_version: Some("9.9.9".to_string()),
            current_version: "0.1.0".to_string(),
            message: None,
        };
        let json = serde_json::to_value(&state).expect("serializes");
        for field in ["status", "available_version", "current_version", "message"] {
            assert!(
                json.get(field).is_some(),
                "missing field {field:?} in {json:?}"
            );
        }
    }

    #[test]
    fn update_state_round_trips_through_json() {
        let state = UpdateState {
            status: UpdateStatus::RolledBack,
            available_version: None,
            current_version: "1.2.3".to_string(),
            message: Some("Kept your working version.".to_string()),
        };
        let json = serde_json::to_string(&state).expect("serializes");
        let back: UpdateState = serde_json::from_str(&json).expect("deserializes");
        assert_eq!(back, state);
    }
}
