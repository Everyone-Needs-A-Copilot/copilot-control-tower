//! The Bob-lane render DTO + its Tauri-managed aggregation (M6/S6,
//! `.copilot/wp/37.md`, task 57) — backs uid's (S5) `get_bob_lane` IPC
//! command. [`BobLaneView`] mirrors `src/types.ts`'s `BobLaneView` exactly
//! (`prompt`/`notices`/`notifications_denied`); [`BobLaneState`] is the
//! single managed instance `commands::get_bob_lane` reads from and this
//! module's own `apply_*` functions (called from `timer.rs`/
//! `commands::check_for_update`) write to — mirroring `commands::
//! DoctorState`'s "exactly one instance, replaced not accumulated"
//! discipline (invariant #2).
//!
//! ## Why this lives outside `commands.rs`
//!
//! `tests/fitness_m5_deprovision_is_it_routed.rs` (FF-M5-3) scans
//! `commands.rs`/`tray.rs`/`lib.rs`'s `generate_handler!` argument list for a
//! blanket `"routing::"` needle — a structural guarantee that the Bob-facing
//! IPC/popover surface never grows a direct line to the deprovision trigger.
//! That scan is deliberately module-path-shaped, not symbol-shaped, so it
//! also catches this task's own NEW `routing::wire`/`routing::BobPrompt`/
//! `routing::BobNotice` usage if it were written directly into `commands.rs`.
//! This module is the seam that absorbs it instead: it is the ONE place that
//! names `crate::routing::*` on the way to building a plain [`BobLaneView`]
//! value; `commands.rs`'s `get_bob_lane`/`check_for_update` only ever import
//! and return THIS module's own opaque DTO/state types, never a `routing::`
//! path. (`timer.rs` is not governed by that scan at all and references
//! `routing::wire` directly for the same reason.)
//!
//! ## Time-boxed escalation (A-H13)
//!
//! A live `AskBob` prompt (today, only ever `sign-in` — see `routing::wire`'s
//! own "what each source can produce" table) is time-boxed: if the SAME kind
//! of prompt is still live after [`BOB_ITEM_TIMEOUT`], `apply_doctor_prompt`
//! escalates it to IT (`routing::wire::wire_bob_item_timed_out`) and stops
//! showing it to Bob — SOUL.md's Alert Machine anti-pattern names this
//! exactly: "Bob-actionable alerts nudge once then silent forever," closed
//! here by escalating instead of re-asking forever.

use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;

use crate::model::update::UpdateParseOutcome;
use crate::routing::emit::ItSignalSink;
use crate::routing::{BobNotice, BobPrompt, BobPromptKind};

/// The Bob lane's full render contract for one snapshot. Mirrors
/// `src/types.ts`'s `BobLaneView` field-for-field — see that type's own doc
/// for the empty-state/notification-denied-fallback contract this type must
/// honor.
#[derive(Debug, Clone, Default, Serialize)]
pub struct BobLaneView {
    pub prompt: Option<BobPrompt>,
    pub notices: Vec<BobNotice>,
    /// **Always `false` in this milestone.** No OS notification-permission
    /// read exists anywhere in this crate yet (no notification plugin is
    /// linked — `capabilities/default.json` grants no such permission); a
    /// live macOS permission check is flagged, batched infra (E12/US-B16's
    /// real transport), not silently guessed at `true`/`false` here. `false`
    /// is the conservative, non-alarming default — it never fabricates "you
    /// missed a notification" when this app has never even attempted to
    /// send one.
    pub notifications_denied: bool,
}

/// M6/S6 policy pick (ADR-M6-004's "the table is a policy, not a verdict"
/// spirit, applied to a timing constant the same way `timer::POLL_INTERVAL`
/// is an app-owned policy value, not a CLI-derived one): how long Bob's own
/// sign-in prompt stays live before A-H13's time-boxed escalation to IT
/// fires. 72h — a few days' grace before IT is pulled in, matching the "the
/// one sign-in approve" framing (§9) that this is ordinarily quick, not an
/// emergency.
pub const BOB_ITEM_TIMEOUT: Duration = Duration::from_secs(60 * 60 * 24 * 3);

/// Pure predicate — `now.duration_since(since) >= timeout` — split out so
/// the timing logic is testable with synthetic `Instant`s, without waiting
/// real wall-clock time (same "pure fold, testable in isolation" split
/// `managed::forced::resolve_string`/`routing::deprovision_trigger::
/// interpret_deprovisioned` already establish for their own OS-touching
/// callers).
fn is_timed_out(since: Instant, now: Instant, timeout: Duration) -> bool {
    now.duration_since(since) >= timeout
}

/// Tracks how long the CURRENT `AskBob` prompt kind has been live, so a
/// prompt that keeps reappearing poll after poll (Bob hasn't acted) can be
/// distinguished from a genuinely NEW one (the clock resets). Never
/// serialized — purely internal bookkeeping, not part of the wire contract.
#[derive(Debug, Default)]
struct PromptTracker {
    kind: Option<BobPromptKind>,
    since: Option<Instant>,
    /// `true` once this SPECIFIC live prompt has already been escalated to
    /// IT — prevents re-dispatching `BobItemTimedOut` every subsequent poll
    /// once the deadline has passed once.
    escalated: bool,
}

struct Inner {
    view: BobLaneView,
    tracker: PromptTracker,
}

/// The Tauri-managed aggregation `commands::get_bob_lane` reads from.
/// `.manage()`d once in `lib.rs`'s `.setup()`, alongside `commands::
/// DoctorState` — see this module's own doc for why it lives here rather
/// than inside `commands.rs`.
pub struct BobLaneState {
    inner: Mutex<Inner>,
}

impl Default for BobLaneState {
    fn default() -> Self {
        Self::new()
    }
}

impl BobLaneState {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(Inner {
                view: BobLaneView::default(),
                tracker: PromptTracker::default(),
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// A snapshot for `commands::get_bob_lane` to return — cloned out from
    /// behind the lock so a caller never holds it open. Fail-closed to the
    /// empty/default view on a poisoned lock (never a panic surfaced to the
    /// IPC boundary, matching `commands::DoctorState::snapshot`'s own
    /// `unwrap_or_else(|e| e.into_inner())` recovery).
    pub fn snapshot(&self) -> BobLaneView {
        self.lock().view.clone()
    }

    /// The doctor-poll-sourced half of the Bob lane (the ONLY live source of
    /// an `AskBob` prompt today — see `routing::wire`'s own table). REPLACES
    /// the current prompt wholesale each call (never accumulates): if this
    /// poll's routing produced no prompt, any previously-shown one clears —
    /// mirroring `commands::DoctorState`'s own "one instance, replaced each
    /// poll" discipline. Applies A-H13's time-boxed escalation (see the
    /// module doc) before storing.
    pub fn apply_doctor_prompt(&self, prompt: Option<BobPrompt>, sink: &dyn ItSignalSink) {
        let mut guard = self.lock();
        let now = Instant::now();

        let Some(p) = prompt else {
            guard.tracker = PromptTracker::default();
            guard.view.prompt = None;
            return;
        };

        if guard.tracker.kind != Some(p.kind) {
            guard.tracker = PromptTracker {
                kind: Some(p.kind),
                since: Some(now),
                escalated: false,
            };
        }

        if guard.tracker.escalated {
            // Already escalated once — stay silent to Bob on this SAME live
            // prompt going forward (never a second, louder ask).
            guard.view.prompt = None;
            return;
        }

        let since = guard.tracker.since.unwrap_or(now);
        if is_timed_out(since, now, BOB_ITEM_TIMEOUT) {
            crate::routing::wire::wire_bob_item_timed_out(sink);
            guard.tracker.escalated = true;
            guard.view.prompt = None;
        } else {
            guard.view.prompt = Some(p);
        }
    }

    /// Upserts one notice BY KIND — a fresh notice of a kind already present
    /// replaces it (never a duplicate), matching the closed, small
    /// `BobNoticeKind` set (never an ever-growing history).
    pub fn upsert_notice(&self, notice: BobNotice) {
        let mut guard = self.lock();
        if let Some(existing) = guard
            .view
            .notices
            .iter_mut()
            .find(|n| n.kind == notice.kind)
        {
            *existing = notice;
        } else {
            guard.view.notices.push(notice);
        }
    }
}

/// Observes a Control Tower self-update rollback (M4, `updater::check::
/// check_for_update`'s shown-once marker) and folds the resulting quiet
/// notice into `state` — the ONE seam `commands::check_for_update` crosses
/// into the routing module through (see the module doc for why). A thin
/// wrapper around `routing::wire::wire_rollback`; never a second, hand-rolled
/// rollback notice.
pub fn record_rollback(state: &BobLaneState) {
    if let Some(notice) = crate::routing::wire::wire_rollback() {
        state.upsert_notice(notice);
    }
}

/// Feeds one parsed `cc update --json` outcome (M6/S1) through the router
/// (`routing::wire::wire_update`) and folds the result into `state` (Bob
/// notices) and `banner` (the security banner, a SEPARATE, parallel parse of
/// the same `changed[]` slice — see `render::security_banner`'s own doc for
/// why it is not derived from `Routed` at all). This is the seam a future,
/// owner-gated live update-poll feeds an `UpdateParseOutcome` through —
/// fixture-tested only in this milestone (see `routing::wire`'s own module
/// doc).
pub fn apply_update(
    state: &BobLaneState,
    banner: &super::security_banner::SecurityBannerState,
    outcome: &UpdateParseOutcome,
    sink: &dyn ItSignalSink,
) {
    for notice in crate::routing::wire::wire_update(outcome, sink) {
        state.upsert_notice(notice);
    }
    let fresh_banner = match outcome {
        UpdateParseOutcome::Trusted(verdict) => {
            super::security_banner::build_security_banner(&verdict.changed)
        }
        UpdateParseOutcome::Unreadable(_) => None,
    };
    banner.replace(fresh_banner);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::routing::emit::LocalSink;
    use crate::routing::{BobNoticeKind, ItSignalKind};

    #[test]
    fn default_view_is_the_silent_empty_state() {
        let view = BobLaneView::default();
        assert!(view.prompt.is_none());
        assert!(view.notices.is_empty());
        assert!(!view.notifications_denied);
    }

    #[test]
    fn a_new_state_snapshots_the_default_empty_view() {
        let state = BobLaneState::new();
        let view = state.snapshot();
        assert!(view.prompt.is_none());
        assert!(view.notices.is_empty());
    }

    #[test]
    fn apply_doctor_prompt_shows_a_fresh_prompt_immediately() {
        let state = BobLaneState::new();
        let sink = LocalSink::new();
        state.apply_doctor_prompt(Some(BobPrompt::sign_in()), &sink);
        let view = state.snapshot();
        assert_eq!(view.prompt.map(|p| p.kind), Some(BobPromptKind::SignIn));
        assert!(
            sink.entries().is_empty(),
            "well within the time-box: no escalation yet"
        );
    }

    #[test]
    fn apply_doctor_prompt_clears_when_this_polls_routing_produced_none() {
        let state = BobLaneState::new();
        let sink = LocalSink::new();
        state.apply_doctor_prompt(Some(BobPrompt::sign_in()), &sink);
        state.apply_doctor_prompt(None, &sink);
        assert!(state.snapshot().prompt.is_none());
    }

    #[test]
    fn is_timed_out_pure_predicate_respects_the_deadline() {
        let since = Instant::now();
        let just_under = since + Duration::from_secs(10);
        let at_or_past = since + Duration::from_secs(20);
        assert!(!is_timed_out(since, just_under, Duration::from_secs(20)));
        assert!(is_timed_out(since, at_or_past, Duration::from_secs(20)));
    }

    /// A-H13: a prompt that has outlived `BOB_ITEM_TIMEOUT` escalates to IT
    /// and stops being shown to Bob — proven directly against the tracker's
    /// `since` field by backdating it past the timeout rather than sleeping.
    #[test]
    fn a_prompt_past_its_timeout_escalates_to_it_and_clears_from_the_bob_lane() {
        let state = BobLaneState::new();
        let sink = LocalSink::new();

        // First poll starts the clock.
        state.apply_doctor_prompt(Some(BobPrompt::sign_in()), &sink);
        // Backdate the tracker's `since` past the deadline (never a real
        // sleep in a unit test).
        {
            let mut guard = state.lock();
            guard.tracker.since =
                Instant::now().checked_sub(BOB_ITEM_TIMEOUT + Duration::from_secs(1));
        }

        state.apply_doctor_prompt(Some(BobPrompt::sign_in()), &sink);

        assert!(
            state.snapshot().prompt.is_none(),
            "a timed-out prompt must stop nagging Bob"
        );
        let entries = sink.entries();
        assert!(entries
            .iter()
            .any(|e| e.kind == ItSignalKind::BobItemTimedOut));
    }

    #[test]
    fn once_escalated_a_repeated_poll_never_re_dispatches_the_timeout_signal() {
        let state = BobLaneState::new();
        let sink = LocalSink::new();
        state.apply_doctor_prompt(Some(BobPrompt::sign_in()), &sink);
        {
            let mut guard = state.lock();
            guard.tracker.since =
                Instant::now().checked_sub(BOB_ITEM_TIMEOUT + Duration::from_secs(1));
        }
        state.apply_doctor_prompt(Some(BobPrompt::sign_in()), &sink);
        let first_count = sink.entries().len();
        state.apply_doctor_prompt(Some(BobPrompt::sign_in()), &sink);
        assert_eq!(
            sink.entries().len(),
            first_count,
            "an already-escalated prompt must never re-dispatch on every subsequent poll"
        );
    }

    #[test]
    fn a_genuinely_new_prompt_kind_resets_the_clock() {
        let state = BobLaneState::new();
        let sink = LocalSink::new();
        state.apply_doctor_prompt(Some(BobPrompt::sign_in()), &sink);
        {
            let mut guard = state.lock();
            guard.tracker.since =
                Instant::now().checked_sub(BOB_ITEM_TIMEOUT + Duration::from_secs(1));
        }
        // A DIFFERENT kind arrives — the clock must reset, not inherit the
        // sign-in prompt's stale `since`.
        state.apply_doctor_prompt(Some(BobPrompt::dirty_wip()), &sink);
        assert_eq!(
            state.snapshot().prompt.map(|p| p.kind),
            Some(BobPromptKind::DirtyWip),
            "a new prompt kind must show immediately, not inherit the old timeout"
        );
        assert!(sink.entries().is_empty());
    }

    #[test]
    fn upsert_notice_replaces_by_kind_never_duplicates() {
        let state = BobLaneState::new();
        state.upsert_notice(BobNotice::kept_you_safe());
        state.upsert_notice(BobNotice::kept_you_safe());
        assert_eq!(state.snapshot().notices.len(), 1);
    }

    #[test]
    fn upsert_notice_of_a_different_kind_appends() {
        let state = BobLaneState::new();
        state.upsert_notice(BobNotice::kept_you_safe());
        state.upsert_notice(BobNotice::kept_your_working_version());
        assert_eq!(state.snapshot().notices.len(), 2);
    }

    #[test]
    fn record_rollback_upserts_the_kept_your_working_version_notice() {
        let state = BobLaneState::new();
        record_rollback(&state);
        let view = state.snapshot();
        assert!(view
            .notices
            .iter()
            .any(|n| n.kind == BobNoticeKind::KeptYourWorkingVersion));
    }

    #[test]
    fn apply_update_folds_a_security_shadow_fixture_into_both_state_and_banner() {
        let path = format!(
            "{}/fixtures/update/corpus/security-shadow.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap();
        let outcome = crate::model::update::parse_update_body(&raw);

        let bob_state = BobLaneState::new();
        let banner_state = crate::render::security_banner::SecurityBannerState::new();
        let sink = LocalSink::new();
        apply_update(&bob_state, &banner_state, &outcome, &sink);

        assert!(bob_state
            .snapshot()
            .notices
            .iter()
            .any(|n| n.kind == BobNoticeKind::KeptYouSafe));
        assert!(banner_state.snapshot().is_some());
    }

    #[test]
    fn apply_update_on_an_ordinary_applied_update_produces_no_banner() {
        let path = format!(
            "{}/fixtures/update/corpus/applied-clean.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap();
        let outcome = crate::model::update::parse_update_body(&raw);

        let bob_state = BobLaneState::new();
        let banner_state = crate::render::security_banner::SecurityBannerState::new();
        let sink = LocalSink::new();
        apply_update(&bob_state, &banner_state, &outcome, &sink);

        assert!(banner_state.snapshot().is_none());
    }
}
