//! The content-free `ItSignal` emission SEAM (M6/S3, `.copilot/wp/37.md`,
//! task 54) — the boundary [`Routed::EscalateIt`] (and an [`AutoAct`]'s
//! optional [`ItSignal`] companion) crosses on its way OUT of this crate
//! (ADR-M6-003). Mirrors `updater::launch::StagedBundleLauncher`'s and
//! `loginitem::smappservice::LoginItemService`'s identical seam shape: a
//! small trait ([`ItSignalSink`]), a default in-process impl ([`LocalSink`]),
//! and [`emit`] — the ONE function that routes a stream of
//! [`super::event::RoutableEvent`]s and dispatches every [`ItSignal`] it
//! produces to a sink, so a live caller (S6) never has to re-derive "which
//! `Routed` variants carry an `ItSignal`" itself.
//!
//! ## The real IT delivery channel is owner-gated infra (G-M6-1)
//!
//! This module owns exactly the SEAM — [`ItSignalSink`] — and the ONE
//! default implementation that needs no fleet infrastructure at all
//! ([`LocalSink`]: an in-process, non-secret audit buffer). HOW a signal
//! actually reaches a real `AdminContact` (a fleet-dashboard event, an MDM
//! endpoint, a batched telemetry POST) is M7 (observability transport) /
//! M8 (Admin govern-queue) infra this task deliberately does not build, per
//! the task brief's "define the seam so M7/M8 plug in without reshaping
//! `ItSignal`". A future real sink drops in behind the SAME [`ItSignalSink`]
//! trait; nothing in [`emit`] or [`super::policy`] changes when it lands.
//!
//! ## Content-free by construction, not by convention
//!
//! [`ItSignalSink::record`] takes `&`[`ItSignal`] — the SAME content-free
//! type [`ItSignal`]'s own module doc already pins to exactly
//! `{kind, admin_contact}` (`it_signal_serializes_to_exactly_kind_and_
//! admin_contact`, `tests/fitness_m6_itsignal_content_free.rs`). There is no
//! second, richer type this seam could accidentally accept instead — the
//! trait signature itself is the structural proof a personal item name
//! cannot reach a sink through this boundary; see
//! `tests/fitness_m6_itsignal_sink_content_free.rs` for the source-level pin
//! of that signature.
//!
//! ## Fail-closed: a sink failure never silently drops a signal
//!
//! [`emit`] never discards an [`ItSignal`] on a sink error — every
//! [`ItSignalSinkError`] is both (a) audited via `eprintln!`
//! (`audit_sink_failure`, the same interim facility
//! `managed::forced::audit_ignored_user_domain_value` uses — no
//! logging/tracing crate exists in this crate yet) and (b) retained in
//! [`EmitOutcome::sink_errors`] for the caller to surface/retry. A dropped
//! signal on a live security exposure would be exactly the "false all-clear"
//! CLAUDE.md's fail-closed invariant forbids.
//!
//! ## `AdminContact: None` is "undeliverable", never a Bob fallback
//!
//! [`LocalSink`] records `deliverable: false` when [`ItSignal::admin_contact`]
//! is `None` (no IT to escalate to — an unmanaged/solo machine) — the signal
//! still exists locally (so it is auditable, never silently vanished) but is
//! NOT delivered anywhere. Per [`ItSignal`]'s own doc and M5's
//! deprovision-is-IT-only rule, this NEVER falls back to surfacing the
//! signal as something Bob can act on; an undeliverable IT signal just stays
//! undeliverable.

use std::fmt;
use std::sync::Mutex;

use super::event::RoutableEvent;
use super::policy::route;
use super::{AutoAct, ItSignal, ItSignalKind, Routed};

/// Talking to a sink failed. Carries only a short, human-readable
/// description — never a raw signal payload re-embedded in the error text
/// (there is nothing content-bearing to leak in the first place; see the
/// module doc's "content-free by construction" section).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItSignalSinkError(pub String);

impl fmt::Display for ItSignalSinkError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "IT signal sink error: {}", self.0)
    }
}

impl std::error::Error for ItSignalSinkError {}

/// The emission seam — trait-based, matching `LoginItemService`'s/
/// `StagedBundleLauncher`'s identical dependency-injection shape. Every real
/// or fake implementation receives ONLY a content-free [`ItSignal`] — see
/// the module doc's "content-free by construction" section.
pub trait ItSignalSink {
    /// Records one content-free safety signal. Implementations decide their
    /// own delivery/retry semantics; [`emit`] treats any `Err` as
    /// "undelivered, never silently dropped" (see the module doc).
    fn record(&self, signal: &ItSignal) -> Result<(), ItSignalSinkError>;
}

/// One retained [`LocalSink`] entry — the signal plus whether it was
/// actually deliverable (`admin_contact.is_some()`). `deliverable: false`
/// records "undeliverable" rather than silently vanishing, and — per M5's
/// own deprovision-is-IT-only rule — never becomes a Bob-actionable
/// fallback (see the module doc's own section on this).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalSinkEntry {
    pub kind: ItSignalKind,
    pub admin_contact: Option<String>,
    pub deliverable: bool,
}

/// The M6 default [`ItSignalSink`] — an in-process, non-secret audit buffer.
/// This is deliberately the ONLY sink this task builds: the real IT
/// transport is owner-gated infra (G-M6-1, see the module doc). A future
/// caller (M7/M8) is free to ALSO wrap this in a batching/telemetry sink
/// that reads [`entries`](LocalSink::entries) and forwards them; this type
/// itself never reaches outside this process.
#[derive(Debug, Default)]
pub struct LocalSink {
    entries: Mutex<Vec<LocalSinkEntry>>,
}

impl LocalSink {
    pub fn new() -> Self {
        Self::default()
    }

    /// A snapshot of everything recorded so far, oldest first. Cloned out
    /// from behind the lock so a caller never holds it open.
    pub fn entries(&self) -> Vec<LocalSinkEntry> {
        self.entries
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }
}

impl ItSignalSink for LocalSink {
    fn record(&self, signal: &ItSignal) -> Result<(), ItSignalSinkError> {
        let mut guard = self
            .entries
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        guard.push(LocalSinkEntry {
            kind: signal.kind,
            admin_contact: signal.admin_contact.clone(),
            deliverable: signal.admin_contact.is_some(),
        });
        Ok(())
    }
}

/// Emits the sink-failure audit line via `eprintln!` — see the module doc's
/// "fail-closed" section. Carries only the signal's [`ItSignalKind`] (a
/// closed, content-free enum) and the sink error text — never anything
/// beyond what the sink implementation itself already legitimately holds.
fn audit_sink_failure(kind: ItSignalKind, error: &ItSignalSinkError) {
    eprintln!(
        "[copilot-control-tower] audit: IT signal sink failed for kind={kind:?}: {error} — the \
         signal is retained in EmitOutcome::sink_errors, never silently dropped."
    );
}

/// The result of one [`emit`] call: every [`Routed`] decision, in order (for
/// the caller/wiring — an `AutoAct`'s own effect, e.g. actually applying a
/// non-destructive repair, and an `AskBob` prompt's own delivery, are
/// neither this module's job), plus any sink failures encountered along the
/// way.
#[derive(Debug, Default)]
pub struct EmitOutcome {
    pub routed: Vec<Routed>,
    pub sink_errors: Vec<ItSignalSinkError>,
}

/// THE emission entry point. Routes every `event` via [`route`] (never
/// re-deciding a lane itself — EXTEND, not reimplement, the same discipline
/// `policy::route`'s own `AuthCredential` arm applies to
/// `route_credential_state`) and dispatches every [`ItSignal`] it produces to
/// `sink` — both a bare [`Routed::EscalateIt`] AND an [`AutoAct`]'s optional
/// `it_signal` companion (the security-shadow auto-suspend's "IT told in
/// parallel" case; `super::policy`'s own module doc: "never leave a Bob
/// notification as the sole control on a live exposure"). `AskBob`/an
/// `AutoAct`'s own effect are NOT this function's job — every [`Routed`]
/// value is returned in [`EmitOutcome::routed`] for the caller to act on.
pub fn emit(events: impl Iterator<Item = RoutableEvent>, sink: &dyn ItSignalSink) -> EmitOutcome {
    let mut outcome = EmitOutcome::default();

    for event in events {
        let routed = route(event);

        let signal_to_dispatch: Option<&ItSignal> = match &routed {
            Routed::EscalateIt(signal) => Some(signal),
            Routed::AutoAct(AutoAct {
                it_signal: Some(signal),
                ..
            }) => Some(signal),
            Routed::AutoAct(AutoAct {
                it_signal: None, ..
            })
            | Routed::AskBob(_) => None,
        };

        if let Some(signal) = signal_to_dispatch {
            if let Err(err) = sink.record(signal) {
                audit_sink_failure(signal.kind, &err);
                outcome.sink_errors.push(err);
            }
        }

        outcome.routed.push(routed);
    }

    outcome
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;
    use crate::model::failclosed::{AuthState, Severity};
    use crate::model::update::ChangeOp;
    use crate::routing::event::{DoctorFindingEvent, UpdateChangeEvent};
    use crate::routing::AutoActReason;

    fn admin_contact_override_env() -> String {
        format!("{FORCED_OVERRIDE_ENV_PREFIX}ADMINCONTACT")
    }

    /// A sink whose `record` always fails — proves [`emit`] neither panics
    /// nor silently swallows the failure.
    struct FailingSink;
    impl ItSignalSink for FailingSink {
        fn record(&self, _signal: &ItSignal) -> Result<(), ItSignalSinkError> {
            Err(ItSignalSinkError("simulated sink outage".to_string()))
        }
    }

    #[test]
    fn emit_dispatches_a_bare_escalateit_signal_to_the_sink() {
        let sink = LocalSink::new();
        let outcome = emit(std::iter::once(RoutableEvent::PersistenceDisabled), &sink);
        assert!(outcome.sink_errors.is_empty());
        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].kind, ItSignalKind::PersistenceDisabled);
        assert_eq!(outcome.routed.len(), 1);
        assert!(matches!(outcome.routed[0], Routed::EscalateIt(_)));
    }

    /// The security-shadow `AutoAct` carries an `it_signal` companion — per
    /// the module doc, `emit` dispatches that companion too, not only a bare
    /// `EscalateIt`.
    #[test]
    fn emit_dispatches_an_autoacts_it_signal_companion_to_the_sink() {
        let sink = LocalSink::new();
        let event = RoutableEvent::UpdateChange(UpdateChangeEvent {
            op: ChangeOp::Updated,
            signed: false,
            shadow_present: true,
        });
        let outcome = emit(std::iter::once(event), &sink);
        assert!(outcome.sink_errors.is_empty());
        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].kind, ItSignalKind::SecurityShadowAutoSuspended);
        assert!(matches!(outcome.routed[0], Routed::AutoAct(_)));
    }

    /// An `AutoAct` with NO `it_signal` companion (an ordinary applied
    /// change) and an `AskBob` (auth expired) both dispatch nothing — the
    /// sink stays empty, and the `Routed` value is still returned to the
    /// caller.
    #[test]
    fn emit_never_dispatches_a_plain_autoact_or_an_askbob_to_the_sink() {
        let sink = LocalSink::new();
        let events = [
            RoutableEvent::UpdateChange(UpdateChangeEvent {
                op: ChangeOp::Updated,
                signed: true,
                shadow_present: false,
            }),
            RoutableEvent::AuthCredential(AuthState::Expired),
        ];
        let outcome = emit(events.into_iter(), &sink);
        assert!(sink.entries().is_empty());
        assert_eq!(outcome.routed.len(), 2);
        assert!(matches!(outcome.routed[0], Routed::AutoAct(_)));
        assert!(matches!(outcome.routed[1], Routed::AskBob(_)));
    }

    #[test]
    fn emit_returns_every_routed_decision_in_order() {
        let sink = LocalSink::new();
        let events = [
            RoutableEvent::DoctorFinding(DoctorFindingEvent {
                severity: Severity::Pass,
                destructive: false,
                repair_available: false,
            }),
            RoutableEvent::Blocked(crate::routing::event::BlockedEvent),
            RoutableEvent::DirtyWip,
        ];
        let outcome = emit(events.into_iter(), &sink);
        assert_eq!(outcome.routed.len(), 3);
        assert!(matches!(
            outcome.routed[0],
            Routed::AutoAct(AutoAct {
                reason: AutoActReason::NoActionNeeded,
                ..
            })
        ));
        assert!(matches!(outcome.routed[1], Routed::EscalateIt(_)));
        assert!(matches!(outcome.routed[2], Routed::AskBob(_)));
    }

    #[test]
    fn local_sink_records_undeliverable_when_admin_contact_is_none() {
        let sink = LocalSink::new();
        sink.record(&ItSignal {
            kind: ItSignalKind::PolicyDenial,
            admin_contact: None,
        })
        .expect("LocalSink::record never fails");
        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        assert!(
            !entries[0].deliverable,
            "no AdminContact configured must record as undeliverable"
        );
        assert_eq!(entries[0].admin_contact, None);
    }

    #[test]
    fn local_sink_records_deliverable_when_admin_contact_is_present() {
        let sink = LocalSink::new();
        sink.record(&ItSignal {
            kind: ItSignalKind::SignatureFailure,
            admin_contact: Some("it@example.com".to_string()),
        })
        .expect("LocalSink::record never fails");
        let entries = sink.entries();
        assert!(entries[0].deliverable);
        assert_eq!(entries[0].admin_contact.as_deref(), Some("it@example.com"));
    }

    #[test]
    fn local_sink_never_offers_a_bob_actionable_field_on_an_undeliverable_entry() {
        // Structural: `LocalSinkEntry` has exactly `kind`/`admin_contact`/
        // `deliverable` — there is no `bob_action`/`prompt`/`fallback` field
        // to even populate. This test pins the value-level behavior;
        // `tests/fitness_m6_itsignal_sink_content_free.rs` pins the
        // declaration itself.
        let sink = LocalSink::new();
        sink.record(&ItSignal {
            kind: ItSignalKind::DeprovisionTriggered,
            admin_contact: None,
        })
        .unwrap();
        let entry = &sink.entries()[0];
        assert!(!entry.deliverable);
        assert_eq!(entry.admin_contact, None);
    }

    /// A user-domain-only `AdminContact` override is ignored by
    /// `resolve_admin_contact` (M5 tamper-audit, pinned again here end to
    /// end through `emit`) — the resulting `ItSignal.admin_contact` is
    /// `None`, so the `LocalSink` entry records undeliverable, never the
    /// tampered value.
    #[test]
    fn a_user_domain_admin_contact_is_ignored_end_to_end_through_emit() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(admin_contact_override_env(), "user") };

        let sink = LocalSink::new();
        let outcome = emit(std::iter::once(RoutableEvent::NotificationsOff), &sink);
        assert!(outcome.sink_errors.is_empty());
        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].admin_contact, None);
        assert!(!entries[0].deliverable);

        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(admin_contact_override_env()) };
    }

    /// A sink failure is audited (via `eprintln!` — not asserted here, no
    /// stdout-capture facility in this crate) and, critically, retained in
    /// `EmitOutcome::sink_errors` rather than silently discarded — the
    /// fail-closed proof this module's whole doc exists for.
    #[test]
    fn a_sink_failure_is_retained_never_silently_dropped() {
        let sink = FailingSink;
        let outcome = emit(std::iter::once(RoutableEvent::PersistenceDisabled), &sink);
        assert_eq!(outcome.sink_errors.len(), 1);
        assert_eq!(outcome.sink_errors[0].0, "simulated sink outage");
        // The Routed decision itself is still returned even though the sink
        // failed to record it — a sink outage must never also swallow the
        // routing outcome.
        assert_eq!(outcome.routed.len(), 1);
        assert!(matches!(outcome.routed[0], Routed::EscalateIt(_)));
    }

    #[test]
    fn it_signal_sink_error_display_never_panics_on_an_empty_message() {
        let err = ItSignalSinkError(String::new());
        assert_eq!(err.to_string(), "IT signal sink error: ");
    }

    #[test]
    fn emit_over_an_empty_iterator_produces_an_empty_outcome() {
        let sink = LocalSink::new();
        let outcome = emit(std::iter::empty(), &sink);
        assert!(outcome.routed.is_empty());
        assert!(outcome.sink_errors.is_empty());
        assert!(sink.entries().is_empty());
    }
}
