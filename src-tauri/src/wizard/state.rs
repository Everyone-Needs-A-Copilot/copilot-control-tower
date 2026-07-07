//! The wizard state machine (S1, `.copilot/wp/15.md` §2 S1): `WizardMode` /
//! `WizardPhase` / `HoldingReason` / `WizardEvent`, and the pure
//! `transition()` function that decides legal phase-to-phase moves. No I/O,
//! no CLI spawn, no health computation lives here — every phase is a NAMED
//! state a caller (S4/S5, later) drives from real CLI-verb events; this file
//! only encodes which moves between them are legal.
//!
//! ## The phase model (ta's WP, S1 acceptance)
//!
//! `Welcome -> Detect -> [Question]* -> Materialize(phase) -> Verify -> Teach
//! -> Done`, with two named holding terminals reachable at `Detect`/`Verify`:
//! `Holding(ItConfigIncomplete{key})` (a managed profile fails
//! schema-validate — S4, Flow 3) and `Holding(WaitingForNetwork)` (first run
//! completes foundation-only, offline — S4, Flow 4). A third holding reason,
//! `Holding(VerifyFailed{status})`, is the general fail-closed catch-all for
//! every other non-Healthy `Verify` outcome (signed-out, needs-attention,
//! offline, …) so **no** verify result other than a parsed
//! `CliStatus::Healthy` can ever reach `Teach`/`Done` (ADR-M3-002 —
//! "terminal Healthy is parsed from doctor, never asserted by the wizard").
//!
//! `Question` is the unmanaged ≤3-question flow (S5); `WizardEvent::
//! DetectedManaged` skips straight to `Materialize` — 0 questions, the
//! managed-silent acceptance criterion (S4). `WizardEvent::
//! DetectedUnmanagedNoQuestions` covers the "single host / single team,
//! auto-derived" sub-case (S5) — still 0 Bob-facing questions even though
//! the machine is unmanaged.
//!
//! `Holding -> Detect` (`HoldingResolved`) models the resumability hook S2/S4
//! need (a settling-window retry, or "back online") without this file owning
//! any timer/poll logic itself — that's S2/S4's job; this is just the legal
//! transition.

use crate::model::state::CliStatus;
use serde::{Deserialize, Serialize};

/// Managed (MDM-delivered ecosystem, silent ~0-question first run) vs
/// unmanaged (solo/guided, ≤3 questions) — branches via
/// `settings::managed::is_managed()` (S4/S5 wire the real call; this type is
/// the pure model of the branch). Crosses the DTO seam directly (S6), so it
/// carries `Serialize`/`Deserialize`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WizardMode {
    Managed,
    Unmanaged,
}

/// One question/step the unmanaged flow may ask (S5's ≤3-question flow).
/// Product-first (ADR-M3-005): `ChooseProducts` renders the 4-product model
/// (Knowledge/CLI/Claude/Codex), never a host-framed "Claude/Codex/Both" — S5
/// fills in the real prompts/products; this file only carries the step
/// shape + its place in the transition table. Crosses the DTO seam directly
/// (`dto::WizardStep::kind`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum StepKind {
    ChooseProducts,
    LayerSetup,
    SignIn,
}

/// The named holding terminals (never Done/Healthy). Not a DTO type on its
/// own — `dto::to_wizard_state` projects one of these into a plain-language
/// `error` string; it never crosses the wire as this Rust shape (and
/// `VerifyFailed`'s `CliStatus` payload has no `Deserialize` impl, so this
/// type deliberately stays Rust-internal).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HoldingReason {
    /// The managed profile is absent-after-settling-window or
    /// present-but-invalid (S4, Flow 3) — `key` names the offending field,
    /// plain language (never raw yaml/serde text).
    ItConfigIncomplete { key: String },
    /// First run completed foundation-only, offline (S4, Flow 4).
    WaitingForNetwork,
    /// `Verify` produced a real, trusted `CliStatus` that is anything other
    /// than `Healthy` — the general fail-closed catch-all so *no* verify
    /// outcome except a parsed Healthy can ever reach `Teach`/`Done`.
    VerifyFailed { status: CliStatus },
    /// `Verify` couldn't produce a trusted status AT ALL — the doctor spawn/
    /// parse came back `CliUnreadable` (S4: the engine missing, hung, or
    /// speaking a schema this app can't safely read). Its own named reason
    /// because it is a different fact from a trusted non-Healthy verdict:
    /// there is no `CliStatus` to carry, and the honest copy is M1's
    /// "I couldn't start the engine", not "setup didn't finish cleanly".
    EngineUnreadable,
}

/// The named setup phases (S1 acceptance: "phases are named states rendered
/// from CLI-verb events"). `Materialize` carries the CLI-supplied phase name
/// verbatim (e.g. "Setting up Claude…") — never a time estimate (ADR-M3-003);
/// `dto::to_wizard_state` is the only place this crate turns a phase into
/// display text, and a fitness test (`tests/fitness_no_eta_in_wizard.rs`)
/// forbids any ETA/countdown string there. Rust-internal like
/// `HoldingReason` — `dto::to_wizard_state` projects this into the DTO's
/// `phase`/`phase_label` strings, it never crosses the wire as this shape.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WizardPhase {
    Welcome,
    Detect,
    Question,
    Materialize { phase_name: String },
    Verify,
    Teach,
    Done,
    Holding(HoldingReason),
}

/// Every event the (later) S4/S5 orchestration feeds the machine.
/// Deliberately narrow — this crate does not invent a generic "next" event;
/// every legal move names the CLI-verb outcome that justified it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WizardEvent {
    Begin,
    DetectedManaged,
    DetectedUnmanagedWithQuestions,
    DetectedUnmanagedNoQuestions,
    ManagedProfileInvalid {
        key: String,
    },
    QuestionAnswered,
    AllQuestionsAnswered,
    PhaseNamed(String),
    MaterializeComplete,
    /// The ONLY way `Verify` ever resolves — carries a `CliStatus` this
    /// crate's M1 parse boundary already decided
    /// (`model::state::parse_doctor_body`, consumed through
    /// `render::derive`). This file computes no verdict of its own; it only
    /// routes a status the CLI already parsed. `status.is_healthy()` is the
    /// one and only gate on reaching `Teach`/`Done`.
    Verified(CliStatus),
    /// `Verify`'s doctor spawn/parse produced no trusted status at all
    /// (`render::derive`'s `ClientState::CliUnreadable`) — routes to
    /// `Holding(EngineUnreadable)`, never a guess at a verdict (S4).
    VerifyUnreadable,
    OfflineFoundationOnly,
    TeachAcknowledged,
    HoldingResolved,
}

/// Why a `transition` call was rejected. Carries the phase actually current
/// and the event that didn't apply to it — plain data, no formatting logic
/// (that's a caller/UI concern, not this pure function's).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransitionError {
    pub from: WizardPhase,
    pub event: WizardEvent,
}

/// THE pure transition function (S1 acceptance: "a pure, testable transition
/// function — no I/O"). Every legal `(phase, event)` pair is listed
/// explicitly; anything else is `Err` — there is no wildcard fallback that
/// would let an illegal jump silently succeed.
pub fn transition(
    current: &WizardPhase,
    event: WizardEvent,
) -> Result<WizardPhase, TransitionError> {
    use WizardPhase::*;

    let next = match (current, &event) {
        (Welcome, WizardEvent::Begin) => Detect,

        // Managed silent path (S4): 0 questions, straight to Materialize.
        (Detect, WizardEvent::DetectedManaged) => Materialize {
            phase_name: String::new(),
        },
        // Unmanaged, but nothing ambiguous to ask (S5's auto-derive
        // sub-case): also 0 questions.
        (Detect, WizardEvent::DetectedUnmanagedNoQuestions) => Materialize {
            phase_name: String::new(),
        },
        (Detect, WizardEvent::DetectedUnmanagedWithQuestions) => Question,
        (Detect, WizardEvent::ManagedProfileInvalid { key }) => {
            Holding(HoldingReason::ItConfigIncomplete { key: key.clone() })
        }
        (Detect, WizardEvent::OfflineFoundationOnly) => Holding(HoldingReason::WaitingForNetwork),

        (Question, WizardEvent::QuestionAnswered) => Question,
        (Question, WizardEvent::AllQuestionsAnswered) => Materialize {
            phase_name: String::new(),
        },

        (Materialize { .. }, WizardEvent::PhaseNamed(name)) => Materialize {
            phase_name: name.clone(),
        },
        (Materialize { .. }, WizardEvent::MaterializeComplete) => Verify,

        // THE Done-needs-doctor guard (ADR-M3-002): the only path to `Teach`
        // (and, from there, `Done`) is a `Verified` event whose `CliStatus`
        // reads Healthy. Every other status — a real, trusted, non-Healthy
        // verdict — holds, never completes.
        (Verify, WizardEvent::Verified(status)) => {
            if status.is_healthy() {
                Teach
            } else {
                Holding(HoldingReason::VerifyFailed { status: *status })
            }
        }
        (Verify, WizardEvent::OfflineFoundationOnly) => Holding(HoldingReason::WaitingForNetwork),
        // No trusted status existed to route on at all — as fail-closed as a
        // non-Healthy verdict, with its own honest reason (never a guess).
        (Verify, WizardEvent::VerifyUnreadable) => Holding(HoldingReason::EngineUnreadable),

        (Teach, WizardEvent::TeachAcknowledged) => Done,

        // Resumability hook (S2/S4): a settling-window retry or "back
        // online" re-enters at Detect, never re-asks already-answered
        // questions (never-destroy, ADR-M3-004) — S2 owns the checkpoint
        // that makes that concrete; this is just the legal phase move.
        (Holding(_), WizardEvent::HoldingResolved) => Detect,

        _ => {
            return Err(TransitionError {
                from: current.clone(),
                event,
            })
        }
    };

    Ok(next)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn step(from: &WizardPhase, event: WizardEvent) -> WizardPhase {
        transition(from, event).unwrap_or_else(|e| {
            panic!(
                "expected a legal transition from {:?} via {:?}",
                e.from, e.event
            )
        })
    }

    #[test]
    fn welcome_begins_into_detect() {
        assert_eq!(
            step(&WizardPhase::Welcome, WizardEvent::Begin),
            WizardPhase::Detect
        );
    }

    #[test]
    fn managed_silent_path_asks_zero_questions() {
        // Welcome -> Detect -> Materialize, never touching Question at all.
        let p = step(&WizardPhase::Welcome, WizardEvent::Begin);
        let p = step(&p, WizardEvent::DetectedManaged);
        assert_eq!(
            p,
            WizardPhase::Materialize {
                phase_name: String::new()
            }
        );
    }

    #[test]
    fn unmanaged_single_host_single_team_also_asks_zero_questions() {
        let p = step(
            &WizardPhase::Detect,
            WizardEvent::DetectedUnmanagedNoQuestions,
        );
        assert_eq!(
            p,
            WizardPhase::Materialize {
                phase_name: String::new()
            }
        );
    }

    #[test]
    fn unmanaged_ambiguous_host_enters_question_phase() {
        let p = step(
            &WizardPhase::Detect,
            WizardEvent::DetectedUnmanagedWithQuestions,
        );
        assert_eq!(p, WizardPhase::Question);
    }

    #[test]
    fn question_phase_stays_in_question_until_all_answered() {
        let p = step(&WizardPhase::Question, WizardEvent::QuestionAnswered);
        assert_eq!(p, WizardPhase::Question);
        let p = step(&p, WizardEvent::AllQuestionsAnswered);
        assert_eq!(
            p,
            WizardPhase::Materialize {
                phase_name: String::new()
            }
        );
    }

    #[test]
    fn materialize_phase_named_updates_label_without_leaving_materialize() {
        let start = WizardPhase::Materialize {
            phase_name: String::new(),
        };
        let named = step(
            &start,
            WizardEvent::PhaseNamed("Setting up Claude…".to_string()),
        );
        assert_eq!(
            named,
            WizardPhase::Materialize {
                phase_name: "Setting up Claude…".to_string()
            }
        );
    }

    #[test]
    fn materialize_complete_moves_to_verify() {
        let m = WizardPhase::Materialize {
            phase_name: "Setting up Claude…".to_string(),
        };
        assert_eq!(
            step(&m, WizardEvent::MaterializeComplete),
            WizardPhase::Verify
        );
    }

    #[test]
    fn verify_healthy_reaches_teach_then_done() {
        let teach = step(
            &WizardPhase::Verify,
            WizardEvent::Verified(CliStatus::Healthy),
        );
        assert_eq!(teach, WizardPhase::Teach);
        let done = step(&teach, WizardEvent::TeachAcknowledged);
        assert_eq!(done, WizardPhase::Done);
    }

    #[test]
    fn verify_non_healthy_status_holds_never_completes() {
        for status in [
            CliStatus::SignedOut,
            CliStatus::NeedsAttention,
            CliStatus::Offline,
            CliStatus::SetupNeeded,
            CliStatus::Syncing,
            CliStatus::UpdateAvailable,
            CliStatus::ItConfigIncomplete,
            CliStatus::WaitingForNetwork,
            CliStatus::UpdatingApp,
        ] {
            let outcome = step(&WizardPhase::Verify, WizardEvent::Verified(status));
            match outcome {
                WizardPhase::Holding(HoldingReason::VerifyFailed { status: s }) => {
                    assert_eq!(s, status);
                }
                other => panic!(
                    "status {status:?} must route to Holding(VerifyFailed), got {other:?} \
                     (no false-complete)"
                ),
            }
            assert_ne!(outcome, WizardPhase::Teach);
            assert_ne!(outcome, WizardPhase::Done);
        }
    }

    #[test]
    fn done_is_unreachable_without_a_verified_healthy_event() {
        // No direct Verify -> Done, no Materialize -> Done, no Question ->
        // Done — TeachAcknowledged is the ONLY event that ever produces
        // Done, and it's only legal from Teach, which itself is only
        // reachable via Verified(Healthy).
        for phase in [
            WizardPhase::Welcome,
            WizardPhase::Detect,
            WizardPhase::Question,
            WizardPhase::Materialize {
                phase_name: String::new(),
            },
            WizardPhase::Verify,
        ] {
            assert!(
                transition(&phase, WizardEvent::TeachAcknowledged).is_err(),
                "TeachAcknowledged must be illegal from {phase:?}"
            );
        }
    }

    #[test]
    fn managed_profile_invalid_holds_with_the_offending_key() {
        let outcome = step(
            &WizardPhase::Detect,
            WizardEvent::ManagedProfileInvalid {
                key: "EcosystemSeedURL".to_string(),
            },
        );
        assert_eq!(
            outcome,
            WizardPhase::Holding(HoldingReason::ItConfigIncomplete {
                key: "EcosystemSeedURL".to_string()
            })
        );
    }

    #[test]
    fn offline_foundation_only_holds_waiting_for_network_from_detect_and_verify() {
        assert_eq!(
            step(&WizardPhase::Detect, WizardEvent::OfflineFoundationOnly),
            WizardPhase::Holding(HoldingReason::WaitingForNetwork)
        );
        assert_eq!(
            step(&WizardPhase::Verify, WizardEvent::OfflineFoundationOnly),
            WizardPhase::Holding(HoldingReason::WaitingForNetwork)
        );
    }

    #[test]
    fn verify_unreadable_holds_with_its_own_reason_never_a_guessed_verdict() {
        let outcome = step(&WizardPhase::Verify, WizardEvent::VerifyUnreadable);
        assert_eq!(
            outcome,
            WizardPhase::Holding(HoldingReason::EngineUnreadable)
        );
        assert_ne!(outcome, WizardPhase::Teach);
        assert_ne!(outcome, WizardPhase::Done);
        // And it resumes the same way every holding terminal does.
        assert_eq!(
            step(&outcome, WizardEvent::HoldingResolved),
            WizardPhase::Detect
        );
    }

    #[test]
    fn holding_resolved_returns_to_detect_never_re_running_the_wizard() {
        let holding = WizardPhase::Holding(HoldingReason::WaitingForNetwork);
        assert_eq!(
            step(&holding, WizardEvent::HoldingResolved),
            WizardPhase::Detect
        );
    }

    #[test]
    fn illegal_transitions_are_rejected_not_silently_accepted() {
        let err = transition(&WizardPhase::Welcome, WizardEvent::AllQuestionsAnswered)
            .expect_err("Welcome + AllQuestionsAnswered must be illegal");
        assert_eq!(err.from, WizardPhase::Welcome);
        assert_eq!(err.event, WizardEvent::AllQuestionsAnswered);

        assert!(transition(&WizardPhase::Done, WizardEvent::Begin).is_err());
        assert!(transition(&WizardPhase::Teach, WizardEvent::QuestionAnswered).is_err());
        assert!(transition(&WizardPhase::Question, WizardEvent::MaterializeComplete).is_err());
    }
}
