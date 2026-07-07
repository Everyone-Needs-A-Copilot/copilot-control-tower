//! The wizard IPC DTO contract (S1, defined now; S6 wires the real Tauri
//! commands around it — `.copilot/wp/15.md` S6). Mirrored 1:1 by
//! `src/types.ts`'s wizard section (plain snake_case both sides, same
//! convention as `render::derive::RenderState` / `settings::dto::
//! SettingsState`).
//!
//! **No secret ever crosses this seam (invariant #6).** `SigninState`
//! carries only the device-flow RENDER data (`user_code`,
//! `verification_uri`) plus a terminal `status` — never a token/credential
//! field. See `tests/fitness_no_secret_on_wizard_dto.rs` for the automated
//! guard (a `syn` field-name scan of this file's struct definitions).
//!
//! **No time estimate, ever (Case Law OUT / ADR-M3-003).** `phase_label` is
//! always a NAME ("Setting up Claude…"), never an ETA/countdown/percentage.
//! See `tests/fitness_no_eta_in_wizard.rs`.

use crate::wizard::state::{HoldingReason, StepKind, WizardMode, WizardPhase};
use serde::{Deserialize, Serialize};

/// The sign-in device-flow terminal states (S3 defines the real seam this
/// mirrors — ADR-M3-001; this crate's DTO shape is frozen now so S6/S7 can
/// build against it). `Idle`/`Pending` are pre-terminal (ceremony shown,
/// poll in flight); the last four are the frozen terminal-state vocabulary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SigninStatus {
    Idle,
    Pending,
    Authorized,
    Denied,
    Expired,
    Timeout,
}

/// The device-flow render data ONLY — see the module doc's invariant #6
/// note. Never add a token/secret/credential field here; the CLI writes the
/// keychain directly (S3) and this DTO never sees that value.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SigninState {
    pub status: SigninStatus,
    pub user_code: Option<String>,
    pub verification_uri: Option<String>,
}

/// One of the unmanaged flow's ≤3 questions (S5 fills in real prompts/data;
/// this is the wire shape). `kind` is product-first-aware
/// (`choose-products`, ADR-M3-005) — never a host-framed step.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WizardStep {
    pub id: String,
    pub kind: StepKind,
    pub prompt: String,
    pub done: bool,
}

/// The full wizard IPC surface (S6's `get_wizard_state()` return type).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WizardState {
    pub mode: WizardMode,
    /// The wire-safe phase name (e.g. `"welcome"`, `"materialize"`,
    /// `"holding"`) — see `phase_tag`.
    pub phase: String,
    /// A NAME, never an ETA (see module doc + the fitness test).
    pub phase_label: String,
    pub steps: Vec<WizardStep>,
    pub signin: Option<SigninState>,
    /// The sign-in ceremony's own poll cadence, in seconds — S3's
    /// `SigninSession::interval_secs()`, passed through so the UI polls
    /// `wizard_poll_signin` at the CLI-specified interval instead of
    /// guessing one. `None` whenever `signin` itself is `None` or terminal
    /// (there is no ceremony left to poll). Deliberately kept OFF the frozen
    /// `SigninState` shape (`tests/fitness_no_secret_on_wizard_dto.rs`'s
    /// `signin_state_has_exactly_the_frozen_render_fields` locks that struct
    /// to exactly `{status, user_code, verification_uri}`) — this is
    /// machine polling bookkeeping, not device-flow render data, so it lives
    /// on the envelope instead. **Not an ETA** (`fitness_no_eta_in_wizard.rs`
    /// forbids rendering this as a countdown/"X seconds left" string — it is
    /// consumed only as a `setInterval` argument, never displayed).
    pub signin_interval_secs: Option<u64>,
    /// `true` if and only if `phase == "done"` — and `Done` is reachable,
    /// per `state::transition`, ONLY via a parsed `Healthy` `CliStatus`
    /// (ADR-M3-002). See `to_wizard_state`.
    pub complete: bool,
    /// Plain-language only — never a raw yaml/serde/CLI error string (SOUL
    /// "a Git error to a non-technical person"). `None` unless the current
    /// phase is a holding terminal.
    pub error: Option<String>,
}

/// `WizardPhase` -> its wire-safe tag string. An explicit lookup (not a
/// derived serde tag) so `to_wizard_state` stays a plain, infallible
/// projection with no dependency on how `WizardPhase` itself might someday
/// be (de)serialized.
fn phase_tag(phase: &WizardPhase) -> &'static str {
    match phase {
        WizardPhase::Welcome => "welcome",
        WizardPhase::Detect => "detect",
        WizardPhase::Question => "question",
        WizardPhase::Materialize { .. } => "materialize",
        WizardPhase::Verify => "verify",
        WizardPhase::Teach => "teach",
        WizardPhase::Done => "done",
        WizardPhase::Holding(_) => "holding",
    }
}

/// The one place a `WizardPhase` becomes display text — a NAME, never an ETA
/// (ADR-M3-003). `Materialize`'s CLI-supplied phase name is passed through
/// verbatim once a real one has arrived (it already IS a name, e.g. "Setting
/// up Claude…"); every other phase gets a fixed, plain-language label.
fn phase_label(phase: &WizardPhase) -> String {
    match phase {
        WizardPhase::Welcome => "Welcome".to_string(),
        WizardPhase::Detect => "Looking at your setup…".to_string(),
        WizardPhase::Question => "A couple of quick questions".to_string(),
        WizardPhase::Materialize { phase_name } if !phase_name.is_empty() => phase_name.clone(),
        WizardPhase::Materialize { .. } => "Setting things up…".to_string(),
        WizardPhase::Verify => "Checking everything's healthy…".to_string(),
        WizardPhase::Teach => "You're all set".to_string(),
        WizardPhase::Done => "Done".to_string(),
        WizardPhase::Holding(reason) => holding_label(reason),
    }
}

/// Plain-language holding copy for `phase_label` — never a raw reason code,
/// never blended (P4). Mirrors the sentence style of `render::derive::
/// build_sentence` / `cli_unreadable_sentence` (name the thing, no jargon).
fn holding_label(reason: &HoldingReason) -> String {
    match reason {
        HoldingReason::ItConfigIncomplete { .. } => {
            "IT setup is incomplete. Nothing for you to do — IT has been notified.".to_string()
        }
        HoldingReason::WaitingForNetwork => {
            "I've set up as far as your network allows. I'll finish the rest when you're \
             back online."
                .to_string()
        }
        HoldingReason::VerifyFailed { .. } => {
            "Setup didn't finish cleanly — I'm holding here rather than guessing.".to_string()
        }
        // M1's engine-unreadable copy, verbatim discipline (render::derive::
        // cli_unreadable_sentence) — this is the same fact surfacing during
        // setup instead of on the tray.
        HoldingReason::EngineUnreadable => {
            "I couldn't start the engine to check how setup went. Click to reinstall — \
             it's a fix, not a reset."
                .to_string()
        }
    }
}

/// Plain-language text for `WizardState.error` — only ever populated
/// alongside a `Holding` phase (`to_wizard_state` is the sole caller).
fn holding_error(reason: &HoldingReason) -> String {
    match reason {
        HoldingReason::ItConfigIncomplete { key } => {
            format!("IT setup is incomplete ({key}). IT has been notified.")
        }
        HoldingReason::WaitingForNetwork => {
            "Waiting for a network connection to finish setup.".to_string()
        }
        HoldingReason::VerifyFailed { status } => {
            format!("Setup didn't finish cleanly (status: {status:?}).")
        }
        HoldingReason::EngineUnreadable => {
            "The setup result couldn't be checked because the engine couldn't be read.".to_string()
        }
    }
}

/// `WizardPhase` -> the `WizardState` wire DTO. The ONLY place `complete` is
/// derived: `true` if and only if the phase is `Done` — and `Done` is
/// reachable, per `state::transition`, ONLY via a parsed `Healthy`
/// `CliStatus` (ADR-M3-002). This function fabricates nothing; it is a
/// presentation-only projection of a phase the machine already legally
/// reached (parse-never-compute, invariant #1).
pub fn to_wizard_state(
    mode: WizardMode,
    phase: &WizardPhase,
    steps: Vec<WizardStep>,
    signin: Option<SigninState>,
    signin_interval_secs: Option<u64>,
) -> WizardState {
    let error = match phase {
        WizardPhase::Holding(reason) => Some(holding_error(reason)),
        _ => None,
    };
    WizardState {
        mode,
        phase: phase_tag(phase).to_string(),
        phase_label: phase_label(phase),
        steps,
        signin,
        signin_interval_secs,
        complete: matches!(phase, WizardPhase::Done),
        error,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::state::CliStatus;
    use crate::wizard::state::WizardMode;

    #[test]
    fn welcome_projects_to_the_welcome_tag_and_is_not_complete() {
        let dto = to_wizard_state(
            WizardMode::Unmanaged,
            &WizardPhase::Welcome,
            vec![],
            None,
            None,
        );
        assert_eq!(dto.phase, "welcome");
        assert_eq!(dto.phase_label, "Welcome");
        assert!(!dto.complete);
        assert_eq!(dto.error, None);
    }

    #[test]
    fn materialize_passes_the_cli_supplied_phase_name_through_verbatim() {
        let phase = WizardPhase::Materialize {
            phase_name: "Setting up Claude…".to_string(),
        };
        let dto = to_wizard_state(WizardMode::Managed, &phase, vec![], None, None);
        assert_eq!(dto.phase, "materialize");
        assert_eq!(dto.phase_label, "Setting up Claude…");
    }

    #[test]
    fn materialize_before_any_phase_name_arrives_gets_a_fixed_placeholder_label() {
        let phase = WizardPhase::Materialize {
            phase_name: String::new(),
        };
        let dto = to_wizard_state(WizardMode::Managed, &phase, vec![], None, None);
        assert_eq!(dto.phase_label, "Setting things up…");
    }

    #[test]
    fn complete_is_true_only_for_the_done_phase() {
        for (phase, expect_complete) in [
            (WizardPhase::Welcome, false),
            (WizardPhase::Detect, false),
            (WizardPhase::Question, false),
            (
                WizardPhase::Materialize {
                    phase_name: String::new(),
                },
                false,
            ),
            (WizardPhase::Verify, false),
            (WizardPhase::Teach, false),
            (WizardPhase::Done, true),
        ] {
            let dto = to_wizard_state(WizardMode::Unmanaged, &phase, vec![], None, None);
            assert_eq!(dto.complete, expect_complete, "phase {phase:?}");
        }
    }

    #[test]
    fn holding_phase_carries_a_plain_language_error_and_others_do_not() {
        let holding = WizardPhase::Holding(HoldingReason::ItConfigIncomplete {
            key: "EcosystemSeedURL".to_string(),
        });
        let dto = to_wizard_state(WizardMode::Managed, &holding, vec![], None, None);
        assert_eq!(dto.phase, "holding");
        assert!(dto.error.is_some());
        assert!(dto.error.unwrap().contains("EcosystemSeedURL"));

        let healthy_teach =
            to_wizard_state(WizardMode::Managed, &WizardPhase::Teach, vec![], None, None);
        assert_eq!(healthy_teach.error, None);
    }

    #[test]
    fn verify_failed_holding_error_never_claims_healthy() {
        let holding = WizardPhase::Holding(HoldingReason::VerifyFailed {
            status: CliStatus::SignedOut,
        });
        let dto = to_wizard_state(WizardMode::Unmanaged, &holding, vec![], None, None);
        let err = dto.error.expect("holding must carry an error");
        assert!(!err.to_lowercase().contains("healthy"));
    }

    #[test]
    fn engine_unreadable_holding_never_claims_healthy_or_completion() {
        let holding = WizardPhase::Holding(HoldingReason::EngineUnreadable);
        let dto = to_wizard_state(WizardMode::Managed, &holding, vec![], None, None);
        assert_eq!(dto.phase, "holding");
        assert!(!dto.complete);
        let err = dto.error.expect("holding must carry an error");
        assert!(!err.to_lowercase().contains("healthy"));
        for banned in ["serde", "traceback", "panicked", "exit code"] {
            assert!(
                !dto.phase_label.to_lowercase().contains(banned)
                    && !err.to_lowercase().contains(banned),
                "leaked jargon {banned:?}"
            );
        }
    }

    #[test]
    fn wizard_state_round_trips_through_json() {
        let steps = vec![WizardStep {
            id: "choose-products".to_string(),
            kind: StepKind::ChooseProducts,
            prompt: "Which copilots do you want?".to_string(),
            done: false,
        }];
        let signin = Some(SigninState {
            status: SigninStatus::Pending,
            user_code: Some("ABCD-1234".to_string()),
            verification_uri: Some("https://example.com/device".to_string()),
        });
        let dto = to_wizard_state(
            WizardMode::Unmanaged,
            &WizardPhase::Question,
            steps,
            signin,
            Some(5),
        );

        let json = serde_json::to_string(&dto).expect("serializes");
        let back: WizardState = serde_json::from_str(&json).expect("round-trips");
        assert_eq!(dto, back);
        assert!(json.contains("\"phase\":\"question\""));
        assert!(json.contains("choose-products"));
        assert!(json.contains("\"signin_interval_secs\":5"));
    }

    #[test]
    fn signin_interval_secs_is_none_when_there_is_no_signin_ceremony() {
        let dto = to_wizard_state(
            WizardMode::Managed,
            &WizardPhase::Detect,
            vec![],
            None,
            None,
        );
        assert_eq!(dto.signin_interval_secs, None);
    }

    #[test]
    fn signin_state_carries_only_render_fields() {
        let signin = SigninState {
            status: SigninStatus::Authorized,
            user_code: None,
            verification_uri: None,
        };
        let json = serde_json::to_value(&signin).expect("serializes");
        let obj = json.as_object().expect("object");
        assert_eq!(
            obj.keys()
                .map(String::as_str)
                .collect::<std::collections::BTreeSet<_>>(),
            std::collections::BTreeSet::from(["status", "user_code", "verification_uri"])
        );
    }
}
