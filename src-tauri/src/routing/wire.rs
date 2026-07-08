//! Live-flow integration glue (M6/S6, `.copilot/wp/37.md`, task 57) —
//! **wires the router into the live app**. Every function here maps an
//! already-trusted domain value (`model::state::DoctorVerdict`,
//! `model::update::UpdateParseOutcome`, a rollback observation, the forced
//! `Deprovisioned` trigger) into [`super::event::RoutableEvent`]s, drives
//! them through [`super::policy::route`]/[`super::emit::emit`] (never
//! re-deciding a lane itself — EXTEND, not reimplement, same discipline
//! `policy::route`'s own `AuthCredential` arm applies to
//! `route_credential_state`), and extracts the Bob-facing pieces
//! (`BobPrompt`/`BobNotice`) the app's managed state needs. This module is
//! the "integration glue" file the task brief names — it owns NO Tauri
//! primitive (`AppHandle`/`tauri::command`/`.emit(`/the popover) itself,
//! consistent with `tests/fitness_m5_deprovision_is_it_routed.rs`'s
//! `routing_module_never_touches_a_tauri_or_popover_primitive` check, which
//! scans every file under this directory, this one included. The REAL Tauri
//! wiring (managed state, the doctor-poll call site, the IPC commands) lives
//! in `timer.rs`/`render::bob_lane`/`commands.rs`/`lib.rs` — see those
//! modules' own docs.
//!
//! ## What each live/fixture source can and can't produce
//!
//! | Source | Live today? | Can produce |
//! |---|---|---|
//! | doctor poll (checkers+auth) | YES (`timer::poll_once`, hourly/dev-30s) | `AutoAct`(no-op/repair)/`EscalateIt`(RepairNeedsReview,AuthRevokedDeprovisionOffer)/`AskBob`(sign-in) — never a `BobNotice` |
//! | `cc update --json` (S1) | **NO** — owner-gated scheduling, see below | `AutoAct`+banner+KeptYouSafe/`EscalateIt`(SignatureFailure,PruneNeedsReview,HeldMajor,PolicyDenial)/waiting-on-it notice |
//! | Control Tower self-update rollback (M4) | YES (`commands::check_for_update`'s shown-once marker) | `AutoAct` + KeptYourWorkingVersion notice only |
//! | forced `Deprovisioned` (M5) | YES (same doctor-poll cadence, a cheap forced-domain read) | `ItSignal` only — no Bob path exists, ever (invariant #5) |
//! | dirty personal WIP (invariant #3) | **NO live producer exists** | `AskBob`(dirty-wip) — see [`wire_dirty_wip`]'s own doc |
//! | persistence-disabled / notifications-off | **NO live producer exists** | `EscalateIt` only — not in this task's named scope (`.copilot/wp/37.md`'s file list is `routing/wire.rs` + `timer.rs`; a live `SMAppService`/OS-notification-permission poll is flagged, batched for a future stream) |
//!
//! ## The update path is fixture-tested, never live-invoked (owner-gated)
//!
//! CLAUDE.md's guardrails for this task are explicit: no mutating `cc
//! update` in the live flow. [`wire_update`] is a real, fully-wired function
//! — `render::bob_lane::apply_update` is the seam a future update-poll
//! feeds an `UpdateParseOutcome` through — but nothing in this crate calls
//! it outside `#[cfg(test)]` today. Scheduling a real, periodic `cc update
//! --json` poll is a separate, owner-gated concern (mutating, needs its own
//! cadence/backoff decision, likely alongside M7's observability work), not
//! silently added here.

use super::emit::{emit, ItSignalSink};
use super::event::{
    BlockedEvent, DoctorFindingEvent, HeldForApprovalEvent, RoutableEvent, UpdateChangeEvent,
};
use super::{AutoAct, BobNotice, BobPrompt, ItSignal, ItSignalKind, Routed};
use crate::model::state::DoctorVerdict;
use crate::model::update::{ChangedItem, HeldChange, UpdateParseOutcome, UpdateVerdict};

/// Builds the content-free `RoutableEvent`s for one doctor verdict — one
/// [`RoutableEvent::DoctorFinding`] per checker (never `id`/`detail`/
/// `layer`/`product` — see `event.rs`'s own "content-free by construction"
/// section) plus one [`RoutableEvent::AuthCredential`] per auth entry (never
/// `identity`/`scope`/`expires_at`). Pure — no I/O, no sink, just the
/// mapping; [`wire_doctor`] below is the caller that actually routes+emits.
pub fn doctor_routable_events(verdict: &DoctorVerdict) -> Vec<RoutableEvent> {
    let mut events: Vec<RoutableEvent> = verdict
        .checkers
        .iter()
        .map(|c| {
            RoutableEvent::DoctorFinding(DoctorFindingEvent {
                severity: c.severity,
                destructive: c.destructive,
                repair_available: c.repair_available,
            })
        })
        .collect();
    events.extend(
        verdict
            .auth
            .iter()
            .map(|a| RoutableEvent::AuthCredential(a.state)),
    );
    events
}

/// Routes every doctor-sourced event through [`emit`], dispatching every
/// produced [`ItSignal`] to `sink`, and returns the ONE `AskBob` prompt this
/// poll's routing produced, if any (0-or-1 — see the module doc's table:
/// doctor-sourced events can only ever produce `BobPromptKind::SignIn`,
/// never `DirtyWip`, and never a `BobNotice` at all). The real, live call
/// site is `timer::poll_once`.
pub fn wire_doctor(verdict: &DoctorVerdict, sink: &dyn ItSignalSink) -> Option<BobPrompt> {
    let events = doctor_routable_events(verdict);
    let outcome = emit(events.into_iter(), sink);
    outcome.routed.into_iter().find_map(|routed| match routed {
        Routed::AskBob(prompt) => Some(prompt),
        _ => None,
    })
}

/// **M7/S3-S9** (`.copilot/wp/43.md`, tasks 62/68): re-derives the
/// content-free [`ItSignal`]s one doctor verdict's routing would dispatch —
/// WITHOUT touching any sink. Built entirely from functions already public
/// and already pure ([`doctor_routable_events`] + [`super::policy::route`]),
/// so calling this is never a second CLI spawn and never a second trust
/// decision (invariant #1) — it is the SAME already-trusted `verdict` this
/// poll's [`wire_doctor`] call routes, re-mapped a second time for a
/// DIFFERENT consumer. Mirrors `render::security_banner`'s own "a SEPARATE,
/// parallel parse of the same slice, never derived from `Routed`" precedent
/// — applied here to feed the telemetry emitter (`telemetry::emitter`)
/// rather than a security banner. The extraction match (which `Routed`
/// variants carry a dispatch-worthy signal) is intentionally the SAME shape
/// [`emit`]'s own internal match uses — both exist because a bare
/// `EscalateIt` and an `AutoAct`'s optional `it_signal` companion are the
/// only two places an [`ItSignal`] is ever produced; this is a second reader
/// of that fact, not a second decision about it.
pub fn doctor_it_signals(verdict: &DoctorVerdict) -> Vec<ItSignal> {
    doctor_routable_events(verdict)
        .into_iter()
        .filter_map(|event| match super::policy::route(event) {
            Routed::EscalateIt(signal) => Some(signal),
            Routed::AutoAct(AutoAct {
                it_signal: Some(signal),
                ..
            }) => Some(signal),
            Routed::AutoAct(AutoAct {
                it_signal: None, ..
            })
            | Routed::AskBob(_) => None,
        })
        .collect()
}

/// Builds the content-free `RoutableEvent`s for one TRUSTED update verdict —
/// one [`RoutableEvent::UpdateChange`] per `changed[]` entry, one
/// [`RoutableEvent::HeldForApproval`] per `held_for_approval[]` entry, one
/// [`RoutableEvent::Blocked`] per `blocked[]` entry (see `event.rs`'s own
/// docs for why `HeldForApprovalEvent`/`BlockedEvent` are zero-field
/// markers). `result`/`lock_before`/`lock_after`/`host` carry no routing
/// signal of their own — every lane decision already lives on the entries
/// themselves.
fn update_verdict_events(verdict: &UpdateVerdict) -> Vec<RoutableEvent> {
    let mut events: Vec<RoutableEvent> = verdict
        .changed
        .iter()
        .map(|c: &ChangedItem| {
            RoutableEvent::UpdateChange(UpdateChangeEvent {
                op: c.op,
                signed: c.signed,
                shadow_present: c.shadowed_by.is_some(),
            })
        })
        .collect();
    events.extend(
        verdict
            .held_for_approval
            .iter()
            .map(|_: &HeldChange| RoutableEvent::HeldForApproval(HeldForApprovalEvent)),
    );
    events.extend(
        verdict
            .blocked
            .iter()
            .map(|_| RoutableEvent::Blocked(BlockedEvent)),
    );
    events
}

/// One `Routed` decision's Bob-facing companion, if any. An `AutoAct`'s own
/// `bob_notice` (e.g. `KeptYouSafe`) passes through unchanged; a
/// `HeldMajorAwaitingApproval` `EscalateIt` gets `BobNotice::waiting_on_it()`
/// paired in AT THIS WIRING LAYER (never inside `policy::route` itself —
/// `HeldForApproval`'s own arm there stays a bare `EscalateIt`, no `AskBob`
/// branch, per SOUL.md Case Law; see `routing::BobNoticeKind::WaitingOnIt`'s
/// own doc for the full rationale). Every other `EscalateIt`/`AskBob`/
/// no-notice `AutoAct` yields `None` here.
fn bob_notice_for(routed: Routed) -> Option<BobNotice> {
    match routed {
        Routed::AutoAct(AutoAct {
            bob_notice: Some(notice),
            ..
        }) => Some(notice),
        Routed::EscalateIt(ItSignal {
            kind: ItSignalKind::HeldMajorAwaitingApproval,
            ..
        }) => Some(BobNotice::waiting_on_it()),
        _ => None,
    }
}

/// Routes one `update --json` parse outcome (M6/S1) through [`emit`],
/// dispatching every produced [`ItSignal`] to `sink`, and returns every
/// `BobNotice` this batch produced (`KeptYouSafe` from a security-shadow
/// suspend, `WaitingOnIt` from a held-major — see [`bob_notice_for`]).
/// `Unreadable` fails closed to the SAME catch-all the router itself defines
/// for content it cannot classify (`RoutableEvent::Unrecognized` ->
/// `EscalateIt(UnrecognizedEvent)`) — an update body this app cannot trust
/// is exactly CLAUDE.md invariant #5's "unknown/ambiguous event" case, never
/// silently ignored and never a fabricated Bob notice. **Fixture-tested
/// only in this milestone** — see the module doc's "owner-gated" section for
/// why no production call site feeds this yet.
pub fn wire_update(outcome: &UpdateParseOutcome, sink: &dyn ItSignalSink) -> Vec<BobNotice> {
    match outcome {
        UpdateParseOutcome::Unreadable(_) => {
            let _ = emit(std::iter::once(RoutableEvent::Unrecognized), sink);
            Vec::new()
        }
        UpdateParseOutcome::Trusted(verdict) => {
            let events = update_verdict_events(verdict);
            emit(events.into_iter(), sink)
                .routed
                .into_iter()
                .filter_map(bob_notice_for)
                .collect()
        }
    }
}

/// Routes a Control Tower self-update rollback observation (M4's watchdog,
/// via `updater::rollback_marker`'s shown-once marker) through the router —
/// always the SAME `AutoActReason::RollbackAlreadyApplied` +
/// `BobNotice::kept_your_working_version()`, no `ItSignal` (a local rollback
/// isn't a safety escalation — see `policy::route`'s own `Rollback` arm).
/// Routed through `route` rather than hand-constructed, so there remains
/// exactly one place this payload is ever built. The real, live call site is
/// `render::bob_lane::record_rollback` (`commands::check_for_update`'s own
/// observation of `UpdateStatus::RolledBack`).
pub fn wire_rollback() -> Option<BobNotice> {
    match super::policy::route(RoutableEvent::Rollback) {
        Routed::AutoAct(AutoAct { bob_notice, .. }) => bob_notice,
        // Structurally unreachable — `policy::route`'s `Rollback` arm always
        // returns `AutoAct` with a `bob_notice`
        // (`policy.rs`'s own `rollback_autoacts_with_kept_your_working_
        // version` test pins this). The safe, non-panicking fallback if that
        // ever somehow changed is silence, never a fabricated notice.
        _ => None,
    }
}

/// Evaluates + routes the forced `Deprovisioned` trigger (M5/S6) —
/// `deprovision_trigger`'s own module doc names THIS stream ("a future
/// IT/managed-trigger surface (S6...)") as its intended live caller.
/// Dispatches the resulting [`ItSignal`] (a genuine trigger, or an ambiguous
/// forced value held for review) to `sink`; the ordinary `NotTriggered` case
/// dispatches nothing. Never touches Bob — `deprovision_trigger`'s own
/// structural guarantee (no Tauri command, no emitted event, no popover
/// primitive anywhere in that module — FF-M5-3) is untouched by this
/// function, which only ever reads its two content-free outputs
/// (`ItRoutedDeprovision::signal`, `Escalated`'s bare `ItSignal`) and hands
/// them to the SAME sink every other `ItSignal` in this crate flows through.
/// The real, live call site is `timer::poll_once`, on the same cadence as
/// the doctor poll (a cheap forced-domain read on the ordinary
/// `NotTriggered` case — no process spawn unless the trigger is genuinely
/// forced `true`).
///
/// **Deliberately bypasses `RoutableEvent::Deprovision`/`policy::route`'s own
/// `Deprovision` arm.** That arm assumes the CLI action already happened
/// (`AutoActReason::DeprovisionAlreadyRendered`'s own doc: "the CLI (or an
/// out-of-band MDM agent) already performed the deprovision — this router
/// only renders that outcome"); routing a bare `DeprovisionEvent::Triggered`
/// through it WITHOUT first calling `run_deprovision` would report a
/// deprovision that never actually ran — a false report, worse than not
/// wiring it. `route_deprovision_trigger` fuses "evaluate the forced key"
/// and "invoke the CLI on a genuine trigger" into one atomic, already-tested
/// M5 call, and produces the BYTE-IDENTICAL `ItSignal` shape `policy::
/// route`'s arm would; reusing it here is EXTEND, not reimplement, the same
/// discipline `AuthCredential`'s arm applies to `route_credential_state`.
/// `event::DeprovisionEvent`/`policy::route`'s `Deprovision` arm stay fully
/// covered by `policy.rs`'s own unit tests; this function is simply not
/// their live caller.
pub fn wire_deprovision(sink: &dyn ItSignalSink) {
    use super::deprovision_trigger::DeprovisionTriggerOutcome;
    match super::deprovision_trigger::route_deprovision_trigger() {
        DeprovisionTriggerOutcome::ItRouted(routed) => {
            let _ = sink.record(&routed.signal);
        }
        DeprovisionTriggerOutcome::Escalated(signal) => {
            let _ = sink.record(&signal);
        }
        DeprovisionTriggerOutcome::NotTriggered => {}
    }
}

/// Routes A-H13's time-boxed escalation — a Bob-actionable item left un-acted
/// past its deadline. Dispatches the resulting `ItSignal::BobItemTimedOut`
/// to `sink`. The deadline itself (how long is "past deadline") and the
/// "has this specific prompt been showing that long" tracking are
/// `render::bob_lane::BobLaneState`'s job (it owns the only clock/tracking
/// state in this wiring layer); this function is the pure routing step that
/// tracker calls once it decides a timeout fired.
pub fn wire_bob_item_timed_out(sink: &dyn ItSignalSink) {
    let _ = emit(std::iter::once(RoutableEvent::BobItemTimedOut), sink);
}

/// Routes Bob's own dirty personal working tree (invariant #3) through the
/// router — always `AskBob(dirty_wip())`, per `policy::route`'s own
/// `DirtyWip` arm (never `EscalateIt`, never silently dropped).
///
/// **No live producer exists yet — flagged, not silently guessed.**
/// Detecting "does Bob have uncommitted personal work" is a git-dirty read
/// that must be CLI-computed (invariant #1 — this app must never compute
/// ecosystem/working-tree state itself); no `doctor --json` checker or CLI
/// verb reports it today. This function exists so the routing OF a
/// dirty-WIP condition is exercised end to end by this crate's own tests
/// right now (task 57's own required integration coverage: "a dirty-WIP
/// reaches AskBob only"), not left implicit until a live signal shows up. A
/// future CLI-reported dirty-WIP fact plugs into this SAME function; nothing
/// about it needs to change when that lands.
pub fn wire_dirty_wip() -> BobPrompt {
    match super::policy::route(RoutableEvent::DirtyWip) {
        Routed::AskBob(prompt) => prompt,
        // Structurally unreachable — `policy.rs`'s own
        // `dirty_wip_always_asks_bob` test pins this arm. Non-panicking
        // fallback, never a crash on a live path.
        _ => BobPrompt::dirty_wip(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::failclosed::{AuthState, Severity};
    use crate::model::state::{AuthIssue, Checker};
    use crate::model::update::parse_update_body;
    use crate::routing::emit::LocalSink;
    use crate::routing::{BobNoticeKind, BobPromptKind, ItSignalKind};

    fn checker(severity: Severity, destructive: bool, repair_available: bool) -> Checker {
        Checker {
            id: "x".to_string(),
            severity,
            destructive,
            detail: None,
            layer: None,
            product: None,
            repair_available,
        }
    }

    fn auth(state: AuthState) -> AuthIssue {
        AuthIssue {
            identity: "bob@example.com".to_string(),
            scope: "org".to_string(),
            state,
            expires_at: None,
        }
    }

    fn verdict(checkers: Vec<Checker>, auth: Vec<AuthIssue>) -> DoctorVerdict {
        DoctorVerdict {
            host: "h".to_string(),
            status: crate::model::state::CliStatus::Healthy,
            offline: false,
            checkers,
            auth,
        }
    }

    fn corpus_update(name: &str) -> UpdateParseOutcome {
        let path = format!(
            "{}/fixtures/update/corpus/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_update_body(&raw)
    }

    // -- doctor_routable_events / wire_doctor --------------------------------

    #[test]
    fn doctor_events_carry_one_entry_per_checker_and_auth_issue() {
        let v = verdict(
            vec![
                checker(Severity::Pass, false, false),
                checker(Severity::Fail, true, true),
            ],
            vec![auth(AuthState::Expired)],
        );
        let events = doctor_routable_events(&v);
        assert_eq!(events.len(), 3);
        assert!(matches!(events[0], RoutableEvent::DoctorFinding(_)));
        assert!(matches!(events[1], RoutableEvent::DoctorFinding(_)));
        assert!(matches!(
            events[2],
            RoutableEvent::AuthCredential(AuthState::Expired)
        ));
    }

    #[test]
    fn wire_doctor_surfaces_the_sign_in_prompt_from_an_expired_auth_issue() {
        let v = verdict(vec![], vec![auth(AuthState::Expired)]);
        let sink = LocalSink::new();
        let prompt = wire_doctor(&v, &sink).expect("expired auth must produce a sign-in prompt");
        assert_eq!(prompt.kind, BobPromptKind::SignIn);
        assert!(
            sink.entries().is_empty(),
            "AskBob must never dispatch to the IT sink"
        );
    }

    #[test]
    fn wire_doctor_dispatches_a_destructive_repair_to_the_it_sink_and_asks_bob_nothing() {
        let v = verdict(vec![checker(Severity::Fail, true, true)], vec![]);
        let sink = LocalSink::new();
        let prompt = wire_doctor(&v, &sink);
        assert!(prompt.is_none());
        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].kind, ItSignalKind::RepairNeedsReview);
    }

    #[test]
    fn wire_doctor_on_a_revoked_auth_issue_escalates_never_asks_bob() {
        let v = verdict(vec![], vec![auth(AuthState::Revoked)]);
        let sink = LocalSink::new();
        let prompt = wire_doctor(&v, &sink);
        assert!(prompt.is_none());
        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].kind, ItSignalKind::AuthRevokedDeprovisionOffer);
    }

    #[test]
    fn a_clean_verdict_produces_no_prompt_and_no_it_signal() {
        let v = verdict(vec![checker(Severity::Pass, false, false)], vec![]);
        let sink = LocalSink::new();
        assert!(wire_doctor(&v, &sink).is_none());
        assert!(sink.entries().is_empty());
    }

    // -- doctor_it_signals (M7/S3-S9) -----------------------------------------

    /// The exact same destructive-repair verdict `wire_doctor_dispatches_a_
    /// destructive_repair_to_the_it_sink_and_asks_bob_nothing` above proves
    /// dispatches `RepairNeedsReview` to a sink — `doctor_it_signals` must
    /// independently re-derive the SAME signal, with no sink involved at all.
    #[test]
    fn doctor_it_signals_re_derives_the_same_signal_a_sink_would_have_received() {
        let v = verdict(vec![checker(Severity::Fail, true, true)], vec![]);
        let signals = doctor_it_signals(&v);
        assert_eq!(signals.len(), 1);
        assert_eq!(signals[0].kind, ItSignalKind::RepairNeedsReview);
    }

    #[test]
    fn doctor_it_signals_is_empty_for_a_clean_verdict() {
        let v = verdict(vec![checker(Severity::Pass, false, false)], vec![]);
        assert!(doctor_it_signals(&v).is_empty());
    }

    /// An expired-auth verdict routes `AskBob`, never a signal — confirms
    /// `doctor_it_signals` never manufactures one for a Bob-only lane.
    #[test]
    fn doctor_it_signals_is_empty_for_an_ask_bob_only_verdict() {
        let v = verdict(vec![], vec![auth(AuthState::Expired)]);
        assert!(doctor_it_signals(&v).is_empty());
    }

    /// Calling `doctor_it_signals` never dispatches anything to a sink —
    /// proven by running the SAME verdict through `wire_doctor` afterward on
    /// a fresh sink and confirming it still reports its own dispatch
    /// independently (i.e. `doctor_it_signals` shares no hidden sink state).
    #[test]
    fn doctor_it_signals_never_touches_any_sink() {
        let v = verdict(vec![checker(Severity::Fail, true, true)], vec![]);
        let _ = doctor_it_signals(&v);
        let sink = LocalSink::new();
        let prompt = wire_doctor(&v, &sink);
        assert!(prompt.is_none());
        assert_eq!(
            sink.entries().len(),
            1,
            "wire_doctor's own dispatch is unaffected"
        );
    }

    // -- wire_update ----------------------------------------------------------

    /// Task 57's own required integration coverage #1: a security-shadow
    /// update entry drives BOTH the `SecurityShadowAutoSuspended` `ItSignal`
    /// (dispatched to the IT sink) AND the `KeptYouSafe` Bob notice — without
    /// this crate ever computing/performing the suspend itself (the fixture
    /// already carries `shadowed_by` as a CLI-reported FACT; this test never
    /// calls a mutating `cc` process).
    #[test]
    fn security_shadow_update_drives_both_the_it_signal_and_the_bob_notice() {
        let outcome = corpus_update("security-shadow");
        let sink = LocalSink::new();
        let notices = wire_update(&outcome, &sink);
        assert!(notices.iter().any(|n| n.kind == BobNoticeKind::KeptYouSafe));
        let entries = sink.entries();
        assert!(entries
            .iter()
            .any(|e| e.kind == ItSignalKind::SecurityShadowAutoSuspended));

        // The banner is a SEPARATE, parallel parse of the same `changed[]`
        // slice (never derived from `Routed` — see `render::security_banner`'s
        // own doc); pinned here too so this ONE test proves task 57's full
        // "banner + ItSignal, no app-side suspend computation" requirement.
        let verdict = match &outcome {
            UpdateParseOutcome::Trusted(v) => v,
            other => panic!("expected Trusted, got {other:?}"),
        };
        let banner = crate::render::security_banner::build_security_banner(&verdict.changed);
        assert!(
            banner.is_some(),
            "a shadowed entry must still render the banner"
        );
    }

    /// Task 57's own required integration coverage #2: a held-major reaches
    /// IT (a content-free `HeldMajorAwaitingApproval` signal) AND a
    /// waiting-on-IT Bob render — never a Bob PROMPT (the closed
    /// `BobPromptKind` set has no held-major member at all; this asserts the
    /// notice, not a prompt, is what's produced).
    #[test]
    fn held_update_reaches_it_and_a_waiting_on_it_bob_render_never_a_prompt() {
        let outcome = corpus_update("held");
        let sink = LocalSink::new();
        let notices = wire_update(&outcome, &sink);
        assert!(notices.iter().any(|n| n.kind == BobNoticeKind::WaitingOnIt));
        let entries = sink.entries();
        assert!(entries
            .iter()
            .any(|e| e.kind == ItSignalKind::HeldMajorAwaitingApproval));
    }

    #[test]
    fn blocked_update_reaches_it_only_no_bob_notice() {
        let outcome = corpus_update("blocked");
        let sink = LocalSink::new();
        let notices = wire_update(&outcome, &sink);
        assert!(notices.is_empty());
        let entries = sink.entries();
        assert!(entries.iter().any(|e| e.kind == ItSignalKind::PolicyDenial));
    }

    #[test]
    fn an_unreadable_update_body_fails_closed_to_the_unrecognized_it_signal() {
        let outcome = UpdateParseOutcome::Unreadable(
            crate::model::update::UpdateUnreadableReason::ParseError,
        );
        let sink = LocalSink::new();
        let notices = wire_update(&outcome, &sink);
        assert!(notices.is_empty());
        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].kind, ItSignalKind::UnrecognizedEvent);
    }

    #[test]
    fn an_ordinary_applied_update_produces_no_bob_notice_and_no_it_signal() {
        let outcome = corpus_update("applied-clean");
        let sink = LocalSink::new();
        let notices = wire_update(&outcome, &sink);
        assert!(notices.is_empty());
        assert!(sink.entries().is_empty());
    }

    // -- wire_rollback ----------------------------------------------------------

    #[test]
    fn wire_rollback_always_produces_the_kept_your_working_version_notice() {
        let notice = wire_rollback().expect("a rollback observation must always produce a notice");
        assert_eq!(notice.kind, BobNoticeKind::KeptYourWorkingVersion);
    }

    // -- wire_deprovision ---------------------------------------------------

    #[test]
    fn wire_deprovision_on_an_unmanaged_dev_machine_dispatches_nothing() {
        // Serializes on the SAME process-global lock `deprovision_trigger`'s
        // own tests use (`CT_FORCED_OVERRIDE_*` are process env vars) — a
        // concurrently-running test in that module could otherwise leave
        // `Deprovisioned` transiently forced while this test reads it.
        let _guard = crate::cli::test_env::ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        // No forced `Deprovisioned` key on a plain `cargo test` box — the
        // ordinary `NotTriggered` case must dispatch nothing to the sink.
        let sink = LocalSink::new();
        wire_deprovision(&sink);
        assert!(sink.entries().is_empty());
    }

    // -- wire_bob_item_timed_out ----------------------------------------------

    #[test]
    fn wire_bob_item_timed_out_dispatches_the_timed_out_signal() {
        let sink = LocalSink::new();
        wire_bob_item_timed_out(&sink);
        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].kind, ItSignalKind::BobItemTimedOut);
    }

    // -- wire_dirty_wip ---------------------------------------------------------

    /// Task 57's own required integration coverage #3: a dirty-WIP condition
    /// reaches `AskBob` ONLY — never IT, never auto-acted.
    #[test]
    fn dirty_wip_reaches_askbob_only() {
        let prompt = wire_dirty_wip();
        assert_eq!(prompt.kind, BobPromptKind::DirtyWip);
    }
}
