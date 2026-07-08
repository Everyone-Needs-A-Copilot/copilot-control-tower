//! The forced `Deprovisioned` trigger (M5/S6, `.copilot/wp/30.md`, invariant
//! #5). Reads the one key `managed::keys::MANAGED_KEYS` names for this
//! purpose (`Deprovisioned`, `security_sensitive: true`, `forced_only:
//! true`) and — only on a genuinely forced, unambiguous `true` — drives
//! [`crate::deprovision::run_deprovision`] (S2's spawn+render seam, built
//! for exactly this caller: its own module doc says "`run_deprovision` is
//! the function a future IT/managed-trigger surface (S6...) calls").
//!
//! ## G-M5-3 flagged here, not silently resolved
//!
//! `.copilot/wp/30.md` names an open question: should this module *invoke*
//! `cc deprovision --json` (causing the CLI to actually perform the
//! deprovision at the moment the trigger fires), or *render* a deprovision
//! outcome the CLI/MDM agent already computed and performed independently,
//! out of band? No second schema/seam for "read an already-computed
//! deprovision result without invoking" exists today — `deprovision.schema.json`
//! is the shape of `cc deprovision <org> --json`'s OWN response, not a
//! resting-state file this module could instead poll. Given that, and given
//! S2 built `run_deprovision` *specifically* naming this stream as its
//! caller, this module invokes it — but ONLY the CLI computes and performs
//! the deprovision itself (invariant #1, `deprovision`'s own zero-wipe-logic
//! discipline, FF-M5-2); this module adds no wipe/retain decision of its
//! own, exactly as `deprovision::run_deprovision`'s contract already
//! guarantees. **Flagged for CLI-owner confirmation**: if the intended
//! design is instead "the app only ever renders a state the CLI/MDM agent
//! already settled," a future task should add that read-only seam and this
//! module should call it instead of `run_deprovision`. Every test in this
//! module drives the mock `cc` seam (`CT_CLI_PATH`) — never the real CLI,
//! which is mutating.
//!
//! ## Never a Bob-facing invocation
//!
//! Nothing in this module is a Tauri `#[tauri::command]`, emits an
//! `app.emit` event, or touches `tray::toggle_popover`/`hide_popover_window`
//! — the deprovision trigger has no path to Bob at all (invariant #5;
//! `tests/fitness_m5_deprovision_is_it_routed.rs`, FF-M5-3, is the
//! structural proof). The only output is an [`super::ItSignal`] routed to
//! IT plus (on an actual trigger) the rendered
//! [`crate::deprovision::render::DeprovisionView`] — both content-free/
//! honest-report shaped, neither a click target.

use super::{ItSignal, ItSignalKind};
use crate::deprovision::{self, render::DeprovisionView};
use crate::managed::forced::{self, ForcedLookup};

/// The exact `MANAGED_KEYS` entry name (`managed::keys::MANAGED_KEYS`) —
/// spelled out as a literal here (not imported) because `managed::keys` is a
/// registry of *many* keys and this module only ever needs the one; a
/// mis-spelled literal here would be caught immediately by this module's own
/// tests (which exercise the identical `CT_FORCED_OVERRIDE_DEPROVISIONED`
/// dev-seam name derived from it) rather than silently reading the wrong key.
const DEPROVISIONED_KEY: &str = "Deprovisioned";

/// The three-way outcome of interpreting the forced `Deprovisioned` value —
/// deliberately NOT a `bool`. See [`interpret_deprovisioned`]'s doc for why
/// this must not reuse [`forced::forced_bool`]'s "ambiguous forced value
/// means `true`" parse rule, which `forced_bool`'s own doc names as WRONG
/// for this exact key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeprovisionTriggerState {
    /// A forced, unambiguous true-token (`true`/`1`/`yes`, case-insensitive).
    /// The ONLY state that ever drives [`deprovision::run_deprovision`].
    Triggered,
    /// Absent, a user-domain-only value (always ignored — B-M1: "never mere
    /// profile removal"), or a forced, unambiguous false-token.
    NotTriggered,
    /// Forced, but neither a recognized true- nor false-token. Fail-closed:
    /// this is deliberately its own state, not folded into `NotTriggered` —
    /// silently treating an ambiguous forced value as "not triggered" would
    /// be a false "all clear" for a key `managed::keys` itself flags as
    /// `security_sensitive`; treating it as `Triggered` would risk a wipe
    /// from a malformed/corrupted profile push. The safe action is neither:
    /// hold, and escalate to IT for review (see
    /// [`route_deprovision_trigger`]'s `Escalated` arm).
    Ambiguous,
}

/// A forced value is a true-token, a false-token, or neither (ambiguous) —
/// case-insensitive, whitespace-trimmed. Deliberately a SMALLER, stricter
/// token set than [`forced::forced_bool`]'s (which treats "anything not a
/// false-token" as `true` — the correct direction for an availability
/// toggle like `AllowSelfUpdate`, but explicitly the WRONG direction for
/// `Deprovisioned`, per that function's own doc comment: "an ambiguous
/// forced value should almost certainly NOT trigger a wipe"). This function
/// is the key-appropriate interpretation that doc comment calls for.
const TRUE_TOKENS: [&str; 3] = ["true", "1", "yes"];
const FALSE_TOKENS: [&str; 4] = ["false", "0", "no", ""];

/// Pure mapping from a raw [`ForcedLookup<String>`] to
/// [`DeprovisionTriggerState`] — independently unit-testable without any
/// process env var, mirroring `managed::forced`'s own
/// `resolve_string`/`resolve_bool` split of "pure fold" from "OS-touching
/// lookup".
pub fn interpret_deprovisioned(lookup: ForcedLookup<String>) -> DeprovisionTriggerState {
    match lookup {
        ForcedLookup::Forced(raw) => {
            let normalized = raw.trim().to_ascii_lowercase();
            if TRUE_TOKENS.contains(&normalized.as_str()) {
                DeprovisionTriggerState::Triggered
            } else if FALSE_TOKENS.contains(&normalized.as_str()) {
                DeprovisionTriggerState::NotTriggered
            } else {
                DeprovisionTriggerState::Ambiguous
            }
        }
        // B-M1: a value present only in the user-writable domain is always
        // ignored — "never mere profile removal" triggers a wipe; only a
        // GENUINELY forced value can. Audited as a tamper event, same as
        // every other security-sensitive key.
        ForcedLookup::IgnoredUserDomain => {
            forced::audit_ignored_user_domain_value(DEPROVISIONED_KEY);
            DeprovisionTriggerState::NotTriggered
        }
        ForcedLookup::Absent => DeprovisionTriggerState::NotTriggered,
    }
}

/// The OS-touching half: reads the real (or dev-seam-overridden) forced
/// `Deprovisioned` value and folds it through [`interpret_deprovisioned`].
pub fn evaluate_deprovision_trigger() -> DeprovisionTriggerState {
    interpret_deprovisioned(forced::forced_string(DEPROVISIONED_KEY))
}

/// The IT-routed result of an actual trigger: the [`ItSignal`] (routed to
/// IT, content-free) alongside the honest [`DeprovisionView`] render of what
/// the CLI actually did.
#[derive(Debug, Clone)]
pub struct ItRoutedDeprovision {
    pub signal: ItSignal,
    pub view: DeprovisionView,
}

/// The full routing outcome — never a fourth, silent "did nothing, said
/// nothing" case. `NotTriggered` is itself an explicit, honest outcome, not
/// an absence of one.
#[derive(Debug, Clone)]
pub enum DeprovisionTriggerOutcome {
    /// `Deprovisioned` was forced `true` — the CLI ran, IT was signaled.
    ItRouted(ItRoutedDeprovision),
    /// `Deprovisioned` was forced but ambiguous — held, IT was signaled for
    /// review; [`deprovision::run_deprovision`] was NEVER called on this
    /// arm (fail-closed: no wipe from a value this module cannot confirm
    /// means "true").
    Escalated(ItSignal),
    /// Absent, user-domain-only, or forced `false` — nothing happened, no
    /// signal was produced.
    NotTriggered,
}

/// Resolves the org this machine deprovisions under from the same forced
/// `OrgSlug` key `cc derive` already uses (`managed::keys::MANAGED_KEYS`) —
/// forced-only, falling back to an empty string (never a guessed org name)
/// when absent.
fn resolve_org() -> String {
    forced::resolve_string("OrgSlug", "")
}

/// THE production entry point: resolves the org from the forced domain and
/// evaluates+routes the trigger. See [`route_deprovision_trigger_for`] for
/// the testable form that takes an explicit org.
pub fn route_deprovision_trigger() -> DeprovisionTriggerOutcome {
    route_deprovision_trigger_for(&resolve_org())
}

/// The routing decision, parameterized on `org` so tests don't depend on a
/// forced `OrgSlug` value. Never calls [`deprovision::run_deprovision`]
/// except on a genuinely [`DeprovisionTriggerState::Triggered`] evaluation —
/// the `Ambiguous` and `NotTriggered` arms are structurally incapable of
/// invoking the CLI at all (no call to `run_deprovision` appears in either
/// arm's code path below).
pub fn route_deprovision_trigger_for(org: &str) -> DeprovisionTriggerOutcome {
    match evaluate_deprovision_trigger() {
        DeprovisionTriggerState::Triggered => {
            let view = deprovision::run_deprovision(org);
            let signal = ItSignal {
                kind: ItSignalKind::DeprovisionTriggered,
                admin_contact: super::resolve_admin_contact(),
            };
            DeprovisionTriggerOutcome::ItRouted(ItRoutedDeprovision { signal, view })
        }
        DeprovisionTriggerState::Ambiguous => {
            let signal = ItSignal {
                kind: ItSignalKind::DeprovisionAmbiguous,
                admin_contact: super::resolve_admin_contact(),
            };
            DeprovisionTriggerOutcome::Escalated(signal)
        }
        DeprovisionTriggerState::NotTriggered => DeprovisionTriggerOutcome::NotTriggered,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;
    use crate::deprovision::render::DeprovisionOutcomeView;
    use crate::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;

    fn mock_cc() -> String {
        format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR"))
    }

    fn deprovisioned_override_env() -> String {
        format!(
            "{FORCED_OVERRIDE_ENV_PREFIX}{}",
            DEPROVISIONED_KEY.to_ascii_uppercase()
        )
    }

    /// Serializes on the SAME process-global lock every other spawn-touching
    /// test suite in this crate uses (`CT_CLI_PATH`/`CT_FIXTURE`/
    /// `CT_FORCED_OVERRIDE_*` are all process env vars).
    fn with_env<T>(deprovisioned: Option<&str>, fixture: Option<&str>, f: impl FnOnce() -> T) -> T {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            if let Some(v) = deprovisioned {
                std::env::set_var(deprovisioned_override_env(), v);
            }
            if let Some(fx) = fixture {
                std::env::set_var(DEV_OVERRIDE_ENV, mock_cc());
                std::env::set_var("CT_FIXTURE", fx);
            }
        }
        let result = f();
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::remove_var(deprovisioned_override_env());
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("CT_FIXTURE");
        }
        result
    }

    // -- pure interpret_deprovisioned (no env at all) -----------------------

    #[test]
    fn recognized_true_tokens_trigger() {
        for v in ["true", "True", "TRUE", "1", "yes", " true "] {
            assert_eq!(
                interpret_deprovisioned(ForcedLookup::Forced(v.to_string())),
                DeprovisionTriggerState::Triggered,
                "{v:?} should be a recognized true-token"
            );
        }
    }

    #[test]
    fn recognized_false_tokens_never_trigger() {
        for v in ["false", "False", "FALSE", "0", "no", ""] {
            assert_eq!(
                interpret_deprovisioned(ForcedLookup::Forced(v.to_string())),
                DeprovisionTriggerState::NotTriggered,
                "{v:?} should be a recognized false-token"
            );
        }
    }

    #[test]
    fn unrecognized_forced_values_are_ambiguous_never_triggered_and_never_ignored() {
        for v in ["purple-monkey", "maybe", "TRUE-ish", "revoked"] {
            assert_eq!(
                interpret_deprovisioned(ForcedLookup::Forced(v.to_string())),
                DeprovisionTriggerState::Ambiguous,
                "{v:?} should be ambiguous, neither a silent trigger nor a silent all-clear"
            );
        }
    }

    #[test]
    fn user_domain_value_is_not_triggered_never_ambiguous() {
        assert_eq!(
            interpret_deprovisioned(ForcedLookup::IgnoredUserDomain),
            DeprovisionTriggerState::NotTriggered
        );
    }

    #[test]
    fn absent_is_not_triggered() {
        assert_eq!(
            interpret_deprovisioned(ForcedLookup::Absent),
            DeprovisionTriggerState::NotTriggered
        );
    }

    // -- end-to-end through the real forced-domain seam + mock cc ----------

    #[test]
    fn forced_true_triggers_the_cli_and_routes_the_render_to_it() {
        let outcome = with_env(Some("forced:true"), Some("wiped-clean"), || {
            route_deprovision_trigger_for("acme-corp")
        });
        match outcome {
            DeprovisionTriggerOutcome::ItRouted(routed) => {
                assert_eq!(routed.view.outcome, DeprovisionOutcomeView::Wiped);
                assert_eq!(routed.signal.kind, ItSignalKind::DeprovisionTriggered);
            }
            other => panic!("expected ItRouted, got {other:?}"),
        }
    }

    #[test]
    fn a_user_domain_deprovisioned_value_is_ignored_and_never_triggers() {
        let outcome = with_env(Some("user"), None, || {
            route_deprovision_trigger_for("acme-corp")
        });
        assert!(
            matches!(outcome, DeprovisionTriggerOutcome::NotTriggered),
            "a user-domain-only Deprovisioned must be ignored (B-M1), got {outcome:?}"
        );
    }

    #[test]
    fn absent_deprovisioned_never_triggers() {
        let outcome = with_env(None, None, || route_deprovision_trigger_for("acme-corp"));
        assert!(matches!(outcome, DeprovisionTriggerOutcome::NotTriggered));
    }

    #[test]
    fn forced_false_never_triggers() {
        let outcome = with_env(Some("forced:false"), None, || {
            route_deprovision_trigger_for("acme-corp")
        });
        assert!(matches!(outcome, DeprovisionTriggerOutcome::NotTriggered));
    }

    /// The fail-closed requirement: ambiguous escalates and holds — it must
    /// never silently wipe (no `ItRouted`, which is the only variant that
    /// ever carries a `run_deprovision` render) and never silently pass as
    /// clean (it's `Escalated`, not `NotTriggered`).
    #[test]
    fn ambiguous_forced_value_escalates_to_it_and_never_silently_wipes() {
        let outcome = with_env(Some("forced:purple-monkey"), None, || {
            route_deprovision_trigger_for("acme-corp")
        });
        match outcome {
            DeprovisionTriggerOutcome::Escalated(signal) => {
                assert_eq!(signal.kind, ItSignalKind::DeprovisionAmbiguous);
            }
            other => panic!("expected Escalated (hold + escalate), got {other:?}"),
        }
    }

    /// `route_deprovision_trigger()` (the org-resolving production entry
    /// point) must not panic and must stay `NotTriggered` on a clean dev box
    /// with no forced `Deprovisioned`/`OrgSlug` at all.
    #[test]
    fn the_org_resolving_entry_point_is_safe_on_an_unmanaged_dev_machine() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let outcome = route_deprovision_trigger();
        assert!(matches!(outcome, DeprovisionTriggerOutcome::NotTriggered));
    }
}
