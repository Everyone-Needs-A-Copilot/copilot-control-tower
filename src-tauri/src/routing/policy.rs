//! THE router (M6/S2, task 53): [`route`], a **pure function** — no I/O, no
//! CLI spawn, no filesystem/keychain read except the one forced-domain
//! `AdminContact` lookup [`super::resolve_admin_contact`] already performs
//! for M5 (a config READ, not a computed verdict — see the module's own
//! "parse-not-compute" section below). Fully unit-testable with zero mocking.
//!
//! ## The declarative policy table (ADR-M6-004)
//!
//! [`route`]'s `match` on [`event::RoutableEvent`] IS the policy table task
//! 53 asks for — laid out below as one row per event class, each row reading
//! ONLY the CLI-computed fields that event class carries (never a field from
//! a DIFFERENT event class, never a field this router re-derives). A `match`
//! rather than a literal array-of-rules because every event class here has
//! *structurally different* fields to key on (an auth state isn't a
//! `ChangeOp`) — Rust's own exhaustiveness checker is the audit mechanism: a
//! new [`event::RoutableEvent`] variant is a compile error here until this
//! table grows a row for it, which is a STRONGER guarantee than a runtime
//! lookup table could give (see `tests/fitness_m6_router_exhaustive.rs` for
//! the belt-and-suspenders source-level proof there is no `_ =>` wildcard
//! hiding a future variant).
//!
//! ```text
//! Event class          | CLI fields read                  | Lane
//! ----------------------|-----------------------------------|------------------------------
//! DoctorFinding(Pass)   | severity                          | AutoAct (no-op)
//! DoctorFinding(!Pass)  | destructive=false, repair_available=true | AutoAct (apply repair)
//! DoctorFinding(!Pass)  | destructive=true OR repair_available=false | EscalateIt(RepairNeedsReview)
//! UpdateChange          | shadow_present=true               | AutoAct (suspend) + ItSignal(SecurityShadowAutoSuspended) + BobNotice(KeptYouSafe)
//! UpdateChange          | shadow_present=false, signed=false | EscalateIt(SignatureFailure)
//! UpdateChange          | shadow_present=false, signed=true, op=Pruned | EscalateIt(PruneNeedsReview)
//! UpdateChange          | shadow_present=false, signed=true, op!=Pruned | AutoAct (ordinary sync)
//! HeldForApproval       | (none — always escalates)         | EscalateIt(HeldMajorAwaitingApproval)
//! Blocked               | (none — always escalates)         | EscalateIt(PolicyDenial)
//! AuthCredential         | AuthState (delegated)             | route_credential_state(state)
//! Deprovision(Triggered) | (M5 already ran the CLI)          | AutoAct (render) + ItSignal(DeprovisionTriggered)
//! Deprovision(Ambiguous) | (fail-closed hold)                | EscalateIt(DeprovisionAmbiguous)
//! Rollback               | (none — always the same)          | AutoAct (render) + BobNotice(KeptYourWorkingVersion)
//! DirtyWip                | (none — always his own data)     | AskBob(dirty_wip)
//! PersistenceDisabled     | (none — always escalates)        | EscalateIt(PersistenceDisabled)
//! NotificationsOff        | (none — always escalates)        | EscalateIt(NotificationsDisabled)
//! BobItemTimedOut         | (none — always escalates)        | EscalateIt(BobItemTimedOut)
//! Unrecognized             | (none — fail-closed)            | EscalateIt(UnrecognizedEvent)
//! ```
//!
//! ## Parse-not-compute (FF-M6-4 / SOUL.md Principle 1)
//!
//! This file computes NO health verdict, resolution, or signature check of
//! its own. Every field [`route`] reads (`severity`, `destructive`,
//! `repair_available`, `op`, `signed`, `shadow_present`, [`AuthState`],
//! [`event::DeprovisionEvent`]) was already computed by the CLI and parsed
//! through a fail-closed boundary ONE LAYER UP (`model::state::
//! parse_doctor_body`, `model::update::parse_update_body`,
//! `model::failclosed::auth_state_from_wire`) — this router never calls any
//! of those parse functions itself, never re-derives a severity/op/auth
//! state from raw bytes, and never re-runs a worst-wins ladder. It only maps
//! already-trusted facts to a lane, exactly the same "1:1 lookup, never a
//! computation" discipline `model::state::parse_cli_status`/
//! `model::update::parse_result` already establish for their own boundaries.
//! `tests/fitness_m6_router_no_verdict_computation.rs` (FF-M6-D) is the
//! source-scan proof.

use super::event::{DeprovisionEvent, RoutableEvent};
use super::{AutoAct, AutoActReason, BobPrompt, CredentialRouting, ItSignal, ItSignalKind, Routed};
use crate::model::failclosed::Severity;
use crate::model::update::ChangeOp;

/// THE pure classifier. See the module doc's policy table for the full
/// mapping; each arm below is one row of that table, in the same order.
pub fn route(event: RoutableEvent) -> Routed {
    match event {
        RoutableEvent::DoctorFinding(finding) => {
            if finding.severity == Severity::Pass {
                // A passing checker needs no action from anyone — the
                // benign no-op, never fabricated as a repair or an
                // escalation.
                Routed::AutoAct(AutoAct {
                    reason: AutoActReason::NoActionNeeded,
                    it_signal: None,
                    bob_notice: None,
                })
            } else if !finding.destructive && finding.repair_available {
                // Reversible (non-destructive) + Bob can't judge which fix
                // to run => AUTO-ACT (§9's re-materialize/ff-pull bucket).
                Routed::AutoAct(AutoAct {
                    reason: AutoActReason::NonDestructiveRepairApplied,
                    it_signal: None,
                    bob_notice: None,
                })
            } else {
                // Either the repair is destructive (not reversible — Bob
                // cannot judge a destructive fix, and it is not his own
                // data) or there is no repair token to apply at all.
                // Neither case is Bob's to decide, so it escalates.
                Routed::EscalateIt(ItSignal {
                    kind: ItSignalKind::RepairNeedsReview,
                    admin_contact: super::resolve_admin_contact(),
                })
            }
        }

        RoutableEvent::UpdateChange(change) => {
            if change.shadow_present {
                // §9's "Fix That Acts Itself": reversible + Bob can't judge
                // => AUTO-ACT, with BOTH companions — IT told in parallel
                // (never a Bob notification as the sole control on a live
                // security exposure) and Bob told quietly, past-tense.
                Routed::AutoAct(AutoAct {
                    reason: AutoActReason::SecurityShadowOverrideSuspended,
                    it_signal: Some(ItSignal {
                        kind: ItSignalKind::SecurityShadowAutoSuspended,
                        admin_contact: super::resolve_admin_contact(),
                    }),
                    bob_notice: Some(super::BobNotice::kept_you_safe()),
                })
            } else if !change.signed {
                // Unsigned, not shadow-suspended — a signature failure. Bob
                // has no basis to judge signing; not his own data.
                Routed::EscalateIt(ItSignal {
                    kind: ItSignalKind::SignatureFailure,
                    admin_contact: super::resolve_admin_contact(),
                })
            } else if change.op == ChangeOp::Pruned {
                // Signed, not shadowed, but a removal Bob cannot judge
                // (see `ItSignalKind::PruneNeedsReview`'s own doc for the
                // G-M6-3 usage-source caveat).
                Routed::EscalateIt(ItSignal {
                    kind: ItSignalKind::PruneNeedsReview,
                    admin_contact: super::resolve_admin_contact(),
                })
            } else {
                // Signed, not shadowed, not pruned (Added/Updated/
                // Unchanged) — an ordinary reversible sync the CLI already
                // applied.
                Routed::AutoAct(AutoAct {
                    reason: AutoActReason::OrdinaryUpdateApplied,
                    it_signal: None,
                    bob_notice: None,
                })
            }
        }

        // Zero-field events: the lane never varies by content (see each
        // event type's own doc for why) — always the same arm.
        RoutableEvent::HeldForApproval(_) => Routed::EscalateIt(ItSignal {
            kind: ItSignalKind::HeldMajorAwaitingApproval,
            admin_contact: super::resolve_admin_contact(),
        }),

        RoutableEvent::Blocked(_) => Routed::EscalateIt(ItSignal {
            kind: ItSignalKind::PolicyDenial,
            admin_contact: super::resolve_admin_contact(),
        }),

        // Delegated, not re-decided — EXTEND, not reimplement (task 53's
        // own instruction). `route_credential_state` is M5's own function;
        // this arm only translates its `CredentialRouting` into `Routed`.
        RoutableEvent::AuthCredential(state) => match super::route_credential_state(state) {
            CredentialRouting::BobReAuth => Routed::AskBob(BobPrompt::sign_in()),
            CredentialRouting::ItDeprovisionOffer(signal) => Routed::EscalateIt(signal),
        },

        RoutableEvent::Deprovision(DeprovisionEvent::Triggered) => Routed::AutoAct(AutoAct {
            // The CLI (or an out-of-band MDM agent) already performed the
            // deprovision — this router only renders that outcome and
            // tells IT. There is no Bob branch on this arm at all (invariant
            // #5 — deprovision is categorically IT-only, never a Bob click
            // target; see `deprovision_trigger`'s own module doc).
            reason: AutoActReason::DeprovisionAlreadyRendered,
            it_signal: Some(ItSignal {
                kind: ItSignalKind::DeprovisionTriggered,
                admin_contact: super::resolve_admin_contact(),
            }),
            bob_notice: None,
        }),

        RoutableEvent::Deprovision(DeprovisionEvent::Ambiguous) => Routed::EscalateIt(ItSignal {
            // Fail-closed: an ambiguous forced value never triggers a wipe
            // and never silently passes as clean (mirrors
            // `deprovision_trigger::DeprovisionTriggerState::Ambiguous`).
            kind: ItSignalKind::DeprovisionAmbiguous,
            admin_contact: super::resolve_admin_contact(),
        }),

        RoutableEvent::Rollback => Routed::AutoAct(AutoAct {
            // M4's watchdog already rolled back; this router only renders
            // the outcome to Bob, quietly and past-tense. No IT signal — a
            // bad self-update staying local isn't a safety escalation.
            reason: AutoActReason::RollbackAlreadyApplied,
            it_signal: None,
            bob_notice: Some(super::BobNotice::kept_your_working_version()),
        }),

        RoutableEvent::DirtyWip => Routed::AskBob(BobPrompt::dirty_wip()),

        RoutableEvent::PersistenceDisabled => Routed::EscalateIt(ItSignal {
            kind: ItSignalKind::PersistenceDisabled,
            admin_contact: super::resolve_admin_contact(),
        }),

        RoutableEvent::NotificationsOff => Routed::EscalateIt(ItSignal {
            kind: ItSignalKind::NotificationsDisabled,
            admin_contact: super::resolve_admin_contact(),
        }),

        RoutableEvent::BobItemTimedOut => Routed::EscalateIt(ItSignal {
            kind: ItSignalKind::BobItemTimedOut,
            admin_contact: super::resolve_admin_contact(),
        }),

        // Fail-closed catch-all (CLAUDE.md invariant #5): never AutoAct,
        // never AskBob — see `event::RoutableEvent::Unrecognized`'s doc.
        RoutableEvent::Unrecognized => Routed::EscalateIt(ItSignal {
            kind: ItSignalKind::UnrecognizedEvent,
            admin_contact: super::resolve_admin_contact(),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::failclosed::AuthState;
    use crate::routing::event::{
        BlockedEvent, DoctorFindingEvent, HeldForApprovalEvent, UpdateChangeEvent,
    };
    use crate::routing::{BobNoticeKind, BobPromptKind};

    fn doctor(severity: Severity, destructive: bool, repair_available: bool) -> RoutableEvent {
        RoutableEvent::DoctorFinding(DoctorFindingEvent {
            severity,
            destructive,
            repair_available,
        })
    }

    fn change(op: ChangeOp, signed: bool, shadow_present: bool) -> RoutableEvent {
        RoutableEvent::UpdateChange(UpdateChangeEvent {
            op,
            signed,
            shadow_present,
        })
    }

    // -- the required SOUL-rejection + fail-closed unit cases ---------------

    /// A security-shadow update change: AutoAct renders the suspend, AND
    /// carries BOTH companions — IT signaled, Bob told quietly.
    #[test]
    fn security_shadow_autoacts_with_it_signal_and_bob_notice() {
        let routed = route(change(ChangeOp::Updated, false, true));
        match routed {
            Routed::AutoAct(AutoAct {
                reason,
                it_signal,
                bob_notice,
            }) => {
                assert_eq!(reason, AutoActReason::SecurityShadowOverrideSuspended);
                let signal = it_signal.expect("security shadow must escalate to IT in parallel");
                assert_eq!(signal.kind, ItSignalKind::SecurityShadowAutoSuspended);
                let notice = bob_notice.expect("security shadow must also notify Bob quietly");
                assert_eq!(notice.kind, BobNoticeKind::KeptYouSafe);
            }
            other => panic!("expected AutoAct, got {other:?}"),
        }
    }

    /// A held-major approval is NEVER handed to Bob — SOUL.md Case Law: "Let
    /// Bob approve a held-major upgrade to clear the badge — OUT".
    #[test]
    fn held_for_approval_escalates_to_it_never_bob() {
        let routed = route(RoutableEvent::HeldForApproval(HeldForApprovalEvent));
        match routed {
            Routed::EscalateIt(signal) => {
                assert_eq!(signal.kind, ItSignalKind::HeldMajorAwaitingApproval);
            }
            other => panic!("expected EscalateIt, got {other:?}"),
        }
    }

    /// A policy-blocked change is never handed to Bob to self-unblock —
    /// SOUL.md Case Law: "Let Bob self-unblock a blocked/held update — OUT".
    #[test]
    fn blocked_escalates_to_it_never_bob() {
        let routed = route(RoutableEvent::Blocked(BlockedEvent));
        match routed {
            Routed::EscalateIt(signal) => {
                assert_eq!(signal.kind, ItSignalKind::PolicyDenial);
            }
            other => panic!("expected EscalateIt, got {other:?}"),
        }
    }

    /// A prune Bob cannot judge — never auto-acted silently, never asked of
    /// Bob (see the module doc's policy table + `ItSignalKind::
    /// PruneNeedsReview`'s own G-M6-3 caveat).
    #[test]
    fn a_prune_bob_cant_judge_escalates_to_it() {
        let routed = route(change(ChangeOp::Pruned, true, false));
        match routed {
            Routed::EscalateIt(signal) => {
                assert_eq!(signal.kind, ItSignalKind::PruneNeedsReview);
            }
            other => panic!("expected EscalateIt, got {other:?}"),
        }
    }

    /// Auth `expired` is Bob's own re-authentication — the one sign-in
    /// approve (§9).
    #[test]
    fn auth_expired_asks_bob_to_sign_in() {
        let routed = route(RoutableEvent::AuthCredential(AuthState::Expired));
        match routed {
            Routed::AskBob(prompt) => assert_eq!(prompt.kind, BobPromptKind::SignIn),
            other => panic!("expected AskBob, got {other:?}"),
        }
    }

    /// Auth `revoked` is IT's leaver/deprovision path — never a Bob-facing
    /// wipe prompt (invariant #5).
    #[test]
    fn auth_revoked_escalates_to_it_never_bob() {
        let routed = route(RoutableEvent::AuthCredential(AuthState::Revoked));
        match routed {
            Routed::EscalateIt(signal) => {
                assert_eq!(signal.kind, ItSignalKind::AuthRevokedDeprovisionOffer);
            }
            other => panic!("expected EscalateIt, got {other:?}"),
        }
    }

    /// A rollback always renders as a quiet, past-tense Bob notice — never
    /// a scary failure, never an IT signal (a bad self-update staying local
    /// isn't a safety escalation).
    #[test]
    fn rollback_autoacts_with_kept_your_working_version() {
        let routed = route(RoutableEvent::Rollback);
        match routed {
            Routed::AutoAct(AutoAct {
                reason,
                it_signal,
                bob_notice,
            }) => {
                assert_eq!(reason, AutoActReason::RollbackAlreadyApplied);
                assert!(
                    it_signal.is_none(),
                    "a local rollback is not a safety escalation"
                );
                let notice = bob_notice.expect("a rollback must render a Bob notice");
                assert_eq!(notice.kind, BobNoticeKind::KeptYourWorkingVersion);
            }
            other => panic!("expected AutoAct, got {other:?}"),
        }
    }

    /// The fail-closed catch-all: an unrecognized/ambiguous event escalates
    /// to IT — never a silent AutoAct, never a Bob prompt for something the
    /// router couldn't classify.
    #[test]
    fn unrecognized_event_fails_closed_to_it_never_autoact_never_bob() {
        let routed = route(RoutableEvent::Unrecognized);
        match routed {
            Routed::EscalateIt(signal) => {
                assert_eq!(signal.kind, ItSignalKind::UnrecognizedEvent);
            }
            other => panic!("expected EscalateIt, got {other:?}"),
        }
    }

    // -- additional coverage over the full event surface ---------------------

    #[test]
    fn dirty_wip_always_asks_bob() {
        let routed = route(RoutableEvent::DirtyWip);
        match routed {
            Routed::AskBob(prompt) => assert_eq!(prompt.kind, BobPromptKind::DirtyWip),
            other => panic!("expected AskBob, got {other:?}"),
        }
    }

    #[test]
    fn persistence_disabled_always_escalates() {
        assert!(matches!(
            route(RoutableEvent::PersistenceDisabled),
            Routed::EscalateIt(ItSignal {
                kind: ItSignalKind::PersistenceDisabled,
                ..
            })
        ));
    }

    #[test]
    fn notifications_off_always_escalates() {
        assert!(matches!(
            route(RoutableEvent::NotificationsOff),
            Routed::EscalateIt(ItSignal {
                kind: ItSignalKind::NotificationsDisabled,
                ..
            })
        ));
    }

    #[test]
    fn bob_item_timed_out_always_escalates_never_a_second_prompt() {
        assert!(matches!(
            route(RoutableEvent::BobItemTimedOut),
            Routed::EscalateIt(ItSignal {
                kind: ItSignalKind::BobItemTimedOut,
                ..
            })
        ));
    }

    #[test]
    fn deprovision_triggered_autoacts_and_signals_it_never_bob() {
        let routed = route(RoutableEvent::Deprovision(DeprovisionEvent::Triggered));
        match routed {
            Routed::AutoAct(AutoAct {
                it_signal,
                bob_notice,
                ..
            }) => {
                assert_eq!(
                    it_signal.expect("deprovision must signal IT").kind,
                    ItSignalKind::DeprovisionTriggered
                );
                assert!(bob_notice.is_none(), "deprovision must never notify Bob");
            }
            other => panic!("expected AutoAct, got {other:?}"),
        }
    }

    #[test]
    fn deprovision_ambiguous_escalates_never_wipes_never_bob() {
        let routed = route(RoutableEvent::Deprovision(DeprovisionEvent::Ambiguous));
        match routed {
            Routed::EscalateIt(signal) => {
                assert_eq!(signal.kind, ItSignalKind::DeprovisionAmbiguous);
            }
            other => panic!("expected EscalateIt, got {other:?}"),
        }
    }

    #[test]
    fn a_passing_checker_is_a_benign_autoact_no_signal_no_notice() {
        let routed = route(doctor(Severity::Pass, false, false));
        match routed {
            Routed::AutoAct(AutoAct {
                reason,
                it_signal,
                bob_notice,
            }) => {
                assert_eq!(reason, AutoActReason::NoActionNeeded);
                assert!(it_signal.is_none());
                assert!(bob_notice.is_none());
            }
            other => panic!("expected AutoAct, got {other:?}"),
        }
    }

    #[test]
    fn a_non_destructive_repair_autoacts() {
        let routed = route(doctor(Severity::Fail, false, true));
        assert!(matches!(
            routed,
            Routed::AutoAct(AutoAct {
                reason: AutoActReason::NonDestructiveRepairApplied,
                ..
            })
        ));
    }

    #[test]
    fn a_destructive_repair_escalates_never_bob() {
        let routed = route(doctor(Severity::Fail, true, true));
        assert!(matches!(
            routed,
            Routed::EscalateIt(ItSignal {
                kind: ItSignalKind::RepairNeedsReview,
                ..
            })
        ));
    }

    #[test]
    fn no_repair_token_at_all_escalates_never_bob() {
        let routed = route(doctor(Severity::Warn, false, false));
        assert!(matches!(
            routed,
            Routed::EscalateIt(ItSignal {
                kind: ItSignalKind::RepairNeedsReview,
                ..
            })
        ));
    }

    #[test]
    fn an_unsigned_change_with_no_shadow_is_a_signature_failure() {
        let routed = route(change(ChangeOp::Updated, false, false));
        assert!(matches!(
            routed,
            Routed::EscalateIt(ItSignal {
                kind: ItSignalKind::SignatureFailure,
                ..
            })
        ));
    }

    #[test]
    fn an_ordinary_signed_change_autoacts() {
        for op in [ChangeOp::Added, ChangeOp::Updated, ChangeOp::Unchanged] {
            let routed = route(change(op, true, false));
            assert!(
                matches!(
                    routed,
                    Routed::AutoAct(AutoAct {
                        reason: AutoActReason::OrdinaryUpdateApplied,
                        ..
                    })
                ),
                "op {op:?} should autoact ordinarily, got {routed:?}"
            );
        }
    }

    /// Shadow takes priority over the plain-unsigned check even though a
    /// shadowed entry is itself unsigned (matches the real fixture:
    /// `model::update`'s `security_shadow_fixture_carries_severity_trailer_
    /// and_shadowed_by` pins that a shadowed change is unsigned) — proves the
    /// ordering in `route`'s `UpdateChange` arm is deliberate, not
    /// coincidental.
    #[test]
    fn shadow_present_wins_over_the_plain_unsigned_case() {
        let routed = route(change(ChangeOp::Updated, false, true));
        assert!(matches!(
            routed,
            Routed::AutoAct(AutoAct {
                reason: AutoActReason::SecurityShadowOverrideSuspended,
                ..
            })
        ));
    }

    /// Exhaustiveness proof at the value level: constructs one instance of
    /// EVERY `RoutableEvent` variant (including every field combination that
    /// changes the lane) and asserts `route` returns without panicking and
    /// produces a `Routed` value for each — the runtime companion to the
    /// compiler's own exhaustive-match guarantee (FF-M6-A).
    #[test]
    fn every_routable_event_variant_produces_exactly_one_routed_value() {
        let events = [
            doctor(Severity::Pass, false, false),
            doctor(Severity::Warn, false, true),
            doctor(Severity::Warn, true, true),
            doctor(Severity::Fail, false, false),
            change(ChangeOp::Added, true, false),
            change(ChangeOp::Updated, true, false),
            change(ChangeOp::Pruned, true, false),
            change(ChangeOp::Unchanged, true, false),
            change(ChangeOp::Updated, false, false),
            change(ChangeOp::Updated, false, true),
            RoutableEvent::HeldForApproval(HeldForApprovalEvent),
            RoutableEvent::Blocked(BlockedEvent),
            RoutableEvent::AuthCredential(AuthState::Expired),
            RoutableEvent::AuthCredential(AuthState::Revoked),
            RoutableEvent::Deprovision(DeprovisionEvent::Triggered),
            RoutableEvent::Deprovision(DeprovisionEvent::Ambiguous),
            RoutableEvent::Rollback,
            RoutableEvent::DirtyWip,
            RoutableEvent::PersistenceDisabled,
            RoutableEvent::NotificationsOff,
            RoutableEvent::BobItemTimedOut,
            RoutableEvent::Unrecognized,
        ];
        for event in events {
            // Must not panic; every arm returns a concrete `Routed`.
            let _: Routed = route(event);
        }
    }

    /// FF-M6-B's value-level half: iterates every combination of
    /// `DoctorFinding`/`UpdateChange` field values (the two event classes
    /// with more than one possible lane) and asserts NONE of them ever
    /// produces `AskBob` — only `AuthCredential(Expired)` and `DirtyWip` may.
    #[test]
    fn doctor_and_update_events_never_produce_askbob_across_every_field_combination() {
        for severity in [Severity::Pass, Severity::Warn, Severity::Fail] {
            for destructive in [false, true] {
                for repair_available in [false, true] {
                    let routed = route(doctor(severity, destructive, repair_available));
                    assert!(
                        !matches!(routed, Routed::AskBob(_)),
                        "doctor({severity:?}, destructive={destructive}, repair={repair_available}) \
                         must never produce AskBob, got {routed:?}"
                    );
                }
            }
        }
        for op in [
            ChangeOp::Added,
            ChangeOp::Updated,
            ChangeOp::Pruned,
            ChangeOp::Unchanged,
        ] {
            for signed in [false, true] {
                for shadow_present in [false, true] {
                    let routed = route(change(op, signed, shadow_present));
                    assert!(
                        !matches!(routed, Routed::AskBob(_)),
                        "change(op={op:?}, signed={signed}, shadow={shadow_present}) must never \
                         produce AskBob, got {routed:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn held_and_blocked_never_produce_askbob() {
        assert!(!matches!(
            route(RoutableEvent::HeldForApproval(HeldForApprovalEvent)),
            Routed::AskBob(_)
        ));
        assert!(!matches!(
            route(RoutableEvent::Blocked(BlockedEvent)),
            Routed::AskBob(_)
        ));
    }
}
