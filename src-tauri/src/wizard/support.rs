//! Small shared helpers used by both `managed_flow.rs` (S4) and
//! `unmanaged_flow.rs` (S5), `.copilot/wp/15.md` §2 S4/S5. Factored out here
//! rather than duplicated twice — unlike each flow's own verb-spawning
//! policy (which each module deliberately owns per its own doc, mirroring
//! `signin.rs`'s precedent), these two helpers are pure, verb-agnostic glue
//! around `state::transition` and the M1 `RenderState` that both flows drive
//! IDENTICALLY, so a single shared implementation is the honest read of Kent
//! Beck's "no duplication" over "each stream owns its own file."

use crate::model::state::CliStatus;
use crate::render::derive::{ClientState, RenderState};
use crate::wizard::state::{self, WizardEvent, WizardPhase};

/// Drives `state::transition`, panicking only on a truly illegal move —
/// every call site in `managed_flow`/`unmanaged_flow` passes an event its own
/// logic has already proven legal for the phase it's in (mirrors
/// `persistence.rs`'s identical `unwrap_or_else(|e| unreachable!(...))`
/// discipline for its own `Holding -> HoldingResolved` call). Never used with
/// user-controlled input that could make the "impossible" branch reachable —
/// see each call site.
pub(crate) fn must_transition(phase: &WizardPhase, event: WizardEvent) -> WizardPhase {
    state::transition(phase, event).unwrap_or_else(|e| {
        unreachable!(
            "illegal wizard transition from {:?} via {:?} — a flow orchestrator drove an event \
             its own logic should have already proven legal for the phase it was in",
            e.from, e.event
        )
    })
}

/// Maps a fresh `RenderState` (M1's `cli::run_doctor()` output) to the ONE
/// legal `WizardEvent` that routes `Verify` onward — this IS the parse-
/// never-compute boundary for the wizard's own Verify step (ADR-M3-002):
/// every branch below just relays a status M1's own parse boundary already
/// decided; it never re-derives one. `CliStatus::WaitingForNetwork` gets its
/// own dedicated event (`OfflineFoundationOnly`) rather than falling into the
/// generic `Verified(status)` -> `Holding(VerifyFailed)` catch-all, so a
/// foundation-only/offline first run lands on `state.rs`'s own NAMED
/// `HoldingReason::WaitingForNetwork` terminal (Flow 4) instead of the
/// generic one — see `state.rs`'s module doc for why that terminal exists
/// separately from the catch-all.
pub(crate) fn verify_event_from_render(render: &RenderState) -> WizardEvent {
    match render.client_state {
        ClientState::CliUnreadable => WizardEvent::VerifyUnreadable,
        ClientState::Ok => match render.status {
            Some(CliStatus::WaitingForNetwork) => WizardEvent::OfflineFoundationOnly,
            Some(status) => WizardEvent::Verified(status),
            // `client_state: Ok` always carries a `status` in this crate's
            // own `render::derive` (see `render_trusted`) — this arm exists
            // only so this function stays total, never a panic on a shape
            // M1 itself would never actually produce.
            None => WizardEvent::VerifyUnreadable,
        },
    }
}

/// Drives `Verify -> {Teach | Holding}` from a fresh doctor poll, then — in
/// the Silent-First-Light / guided-first-run discipline both flows share —
/// auto-acknowledges `Teach` straight to `Done`. Neither backend flow has a
/// further question to ask once Healthy is confirmed; a "click to finish"
/// affordance, if S7/S8's UI wants one, is a presentation-only pause on an
/// already-`Done` state, not a gate this orchestration layer needs to model.
pub(crate) fn drive_verify(phase: WizardPhase, render: &RenderState) -> WizardPhase {
    let event = verify_event_from_render(render);
    let verified = must_transition(&phase, event);
    if matches!(verified, WizardPhase::Teach) {
        must_transition(&verified, WizardEvent::TeachAcknowledged)
    } else {
        verified
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::derive::HeaderView;

    fn render_ok(status: CliStatus) -> RenderState {
        RenderState {
            client_state: ClientState::Ok,
            cli_unreadable_reason: None,
            host: Some("h".to_string()),
            status: Some(status),
            offline: false,
            header: HeaderView {
                glyph_state: status.glyph_badge().to_string(),
                sentence: "irrelevant".to_string(),
            },
            products: Vec::new(),
            auth_issues: Vec::new(),
        }
    }

    #[test]
    fn healthy_render_reaches_done_via_teach() {
        let phase = must_transition(&WizardPhase::Welcome, WizardEvent::Begin);
        let phase = must_transition(&phase, WizardEvent::DetectedManaged);
        let phase = must_transition(&phase, WizardEvent::MaterializeComplete);
        let done = drive_verify(phase, &render_ok(CliStatus::Healthy));
        assert_eq!(done, WizardPhase::Done);
    }

    #[test]
    fn waiting_for_network_status_lands_on_the_dedicated_holding_reason() {
        use crate::wizard::state::HoldingReason;
        let phase = must_transition(&WizardPhase::Welcome, WizardEvent::Begin);
        let phase = must_transition(&phase, WizardEvent::DetectedManaged);
        let phase = must_transition(&phase, WizardEvent::MaterializeComplete);
        let holding = drive_verify(phase, &render_ok(CliStatus::WaitingForNetwork));
        assert_eq!(
            holding,
            WizardPhase::Holding(HoldingReason::WaitingForNetwork),
            "must be the dedicated reason, not the generic VerifyFailed catch-all"
        );
    }

    #[test]
    fn other_non_healthy_statuses_fall_into_the_generic_verify_failed_catch_all() {
        use crate::wizard::state::HoldingReason;
        let phase = must_transition(&WizardPhase::Welcome, WizardEvent::Begin);
        let phase = must_transition(&phase, WizardEvent::DetectedManaged);
        let phase = must_transition(&phase, WizardEvent::MaterializeComplete);
        let holding = drive_verify(phase, &render_ok(CliStatus::SignedOut));
        assert_eq!(
            holding,
            WizardPhase::Holding(HoldingReason::VerifyFailed {
                status: CliStatus::SignedOut
            })
        );
    }

    #[test]
    fn cli_unreadable_render_holds_engine_unreadable_never_healthy() {
        use crate::wizard::state::HoldingReason;
        let phase = must_transition(&WizardPhase::Welcome, WizardEvent::Begin);
        let phase = must_transition(&phase, WizardEvent::DetectedManaged);
        let phase = must_transition(&phase, WizardEvent::MaterializeComplete);
        let render = RenderState {
            client_state: ClientState::CliUnreadable,
            cli_unreadable_reason: Some(crate::model::state::CliUnreadableReason::IoError),
            host: None,
            status: None,
            offline: false,
            header: HeaderView {
                glyph_state: "bang".to_string(),
                sentence: "irrelevant".to_string(),
            },
            products: Vec::new(),
            auth_issues: Vec::new(),
        };
        let holding = drive_verify(phase, &render);
        assert_eq!(
            holding,
            WizardPhase::Holding(HoldingReason::EngineUnreadable)
        );
    }
}
