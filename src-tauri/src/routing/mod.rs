//! Route-by-competence (M5/S6, `.copilot/wp/30.md`, invariant #5,
//! `docs/01-architecture/architecture.md` §9 — the Bob-agency model).
//!
//! §9 routes by **actor-competence × reversibility**, not event-class, in
//! three lanes: **AUTO-ACT** (reversible, Bob can't judge it), **ESCALATE TO
//! IT** (Bob is unqualified or can't action it), **ASK BOB** (rare — only
//! when he's the sole competent actor about his own data). This module owns
//! the ONE routing decision this milestone's two deprovision-adjacent
//! triggers need: [`Actor`] + [`ItSignal`] (the ESCALATE-TO-IT lane's
//! content-free payload shape) + [`route_credential_state`] (auth
//! `expired` vs `revoked` — §9 names `revoked` explicitly as an
//! auth-revoked safety signal; `expired` is ordinary "the one sign-in
//! approve" ASK-BOB territory, since re-authenticating is Bob's own data,
//! not IT's). [`deprovision_trigger`] applies the same [`ItSignal`] shape to
//! the forced `Deprovisioned` trigger.
//!
//! ## Deprovision is categorically IT-only — not merely "usually escalated"
//!
//! §9's escalation ladder has three lanes, and ordinary safety signals
//! (sig-fail, policy-conflict, stalled-onboarding, persistence-disabled,
//! notifications-off) fall back to an **in-app popover** when no
//! `AdminContact` is configured (`docs/08-observability/observability.md`:
//! "the underlying signal still surfaces in-app... because a solo user is
//! the only actor who could ever act on it anyway"). **Deprovision is a
//! deliberate exception to that fallback.** A wipe/deprovision action must
//! never become something Bob can click, regardless of whether
//! `AdminContact` is configured — the safe behavior on an unmanaged/solo
//! machine with no IT to escalate to is "the signal exists but is
//! undeliverable" (`ItSignal.admin_contact == None`), never "ask Bob to
//! confirm his own wipe." This is why [`ItSignal`] carries no
//! Bob-actionable affordance at all — see [`deprovision_trigger`]'s own doc
//! for the trigger-side half of this, and
//! `tests/fitness_m5_deprovision_is_it_routed.rs` (FF-M5-3) for the
//! structural proof neither path ever reaches a Tauri command, an emitted
//! event, or the popover window.
//!
//! ## Content-free by construction, not by convention
//!
//! §9: "the IT channel carries **content-free safety signals**." [`ItSignal`]
//! enforces this at the type level — its only fields are [`ItSignalKind`]
//! (a closed enum naming *which* safety fact fired) and `admin_contact`
//! (the escalation endpoint itself, read forced-domain-only via
//! [`crate::managed::forced`]). It deliberately carries **no** `identity`,
//! `scope`, `org`, or `expires_at` — none of `model::state::AuthIssue`'s
//! fields cross into this type, even though [`route_credential_state`]'s
//! caller has them in hand. `it_signal_serializes_to_exactly_kind_and_admin_contact`
//! (below) pins the serialized shape as a regression guard.

pub mod deprovision_trigger;

use crate::managed::forced::{self, ForcedLookup};
use crate::model::failclosed::AuthState;
use serde::Serialize;

/// Which of §9's two non-AUTO-ACT lanes a decision routes to. `Bob` is
/// intentionally the rare case (§9: "ASK BOB (rare) — only when he is the
/// sole competent actor about his own data").
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Actor {
    Bob,
    It,
}

/// The specific content-free safety fact an [`ItSignal`] reports. Closed
/// (non-`#[non_exhaustive]`) deliberately — a new signal kind is a new
/// variant here, reviewed alongside this module's own IT-only guarantee,
/// never an ad hoc string.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ItSignalKind {
    /// The forced `Deprovisioned` key was observed `true` — the deprovision
    /// CLI ran and [`deprovision_trigger::route_deprovision_trigger`]'s
    /// [`deprovision::render::DeprovisionView`](crate::deprovision::render::DeprovisionView)
    /// carries what actually happened.
    DeprovisionTriggered,
    /// The forced `Deprovisioned` key was present but neither a recognized
    /// true- nor false-token — held, never treated as a trigger, and never
    /// silently dropped either (fail-closed: escalate, don't guess).
    DeprovisionAmbiguous,
    /// `doctor`'s `auth[].state == revoked` (or an unrecognized state,
    /// which `model::failclosed::auth_state_from_wire` already fails closed
    /// to `Revoked`) — a fail-closed **offer**, not an action: IT decides
    /// whether to actually trigger a deprovision via MDM.
    AuthRevokedDeprovisionOffer,
}

/// The ESCALATE-TO-IT lane's payload — see the module doc's "content-free by
/// construction" section for why these two fields are the ENTIRE shape.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ItSignal {
    pub kind: ItSignalKind,
    /// The forced-domain `AdminContact` endpoint, if one is configured.
    /// `None` means "no IT to escalate to" (an unmanaged/solo machine) —
    /// the signal still exists (callers may still log/render it locally)
    /// but there is nowhere to deliver it; per the module doc, this NEVER
    /// falls back to a Bob-actionable deprovision affordance the way an
    /// ordinary safety signal falls back to the popover (A-H10).
    pub admin_contact: Option<String>,
}

/// Resolves the forced-domain `AdminContact` endpoint via
/// [`crate::managed::forced`] — forced-only, exactly like every other
/// security-sensitive key in [`crate::managed::keys::MANAGED_KEYS`]. A
/// user-domain-only value is ignored (audited as a tamper event by
/// [`forced::audit_ignored_user_domain_value`], the same facility
/// [`forced::resolve_string`] uses) rather than honored — a local user must
/// never be able to redirect where a safety escalation about *them* goes.
fn resolve_admin_contact() -> Option<String> {
    match forced::forced_string("AdminContact") {
        ForcedLookup::Forced(v) if !v.trim().is_empty() => Some(v),
        ForcedLookup::Forced(_) => None,
        ForcedLookup::IgnoredUserDomain => {
            forced::audit_ignored_user_domain_value("AdminContact");
            None
        }
        ForcedLookup::Absent => None,
    }
}

/// The routing decision for one `doctor` `auth[]` credential finding.
/// `expired` is transient and recoverable — it's Bob's own data, so it
/// stays ASK-BOB territory (his own re-sign-in; §9's "the one sign-in
/// approve"). `revoked` is permanent and worse (`model::failclosed`'s own
/// fail-closed direction: an *unrecognized* wire state already collapses to
/// `Revoked`, never `Expired`) — the leaver/IT path, never a Bob-facing wipe
/// prompt (invariant #5).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CredentialRouting {
    /// Bob's own re-authentication — no IT signal is produced for this case
    /// at all (an `ItSignal` is only ever constructed on the `Revoked` arm
    /// below, never speculatively).
    BobReAuth,
    /// A fail-closed deprovision **offer** routed to IT — never an action
    /// this crate performs itself.
    ItDeprovisionOffer(ItSignal),
}

/// THE routing decision this task's auth-revoked path exists to make. See
/// [`CredentialRouting`]'s doc for the expired-vs-revoked rationale.
pub fn route_credential_state(state: AuthState) -> CredentialRouting {
    match state {
        AuthState::Expired => CredentialRouting::BobReAuth,
        AuthState::Revoked => CredentialRouting::ItDeprovisionOffer(ItSignal {
            kind: ItSignalKind::AuthRevokedDeprovisionOffer,
            admin_contact: resolve_admin_contact(),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;

    fn admin_contact_override_env() -> String {
        format!("{FORCED_OVERRIDE_ENV_PREFIX}ADMINCONTACT")
    }

    #[test]
    fn expired_routes_to_bob_reauth_and_produces_no_it_signal() {
        assert_eq!(
            route_credential_state(AuthState::Expired),
            CredentialRouting::BobReAuth
        );
    }

    #[test]
    fn revoked_routes_to_an_it_deprovision_offer_never_bob() {
        match route_credential_state(AuthState::Revoked) {
            CredentialRouting::ItDeprovisionOffer(signal) => {
                assert_eq!(signal.kind, ItSignalKind::AuthRevokedDeprovisionOffer);
            }
            other => panic!("expected ItDeprovisionOffer, got {other:?}"),
        }
    }

    /// An unrecognized wire auth state already fails closed to `Revoked`
    /// one layer down (`model::failclosed::auth_state_from_wire`) before
    /// this function ever sees it — this test pins that the IT-routing
    /// consequence of that fail-closed default is itself correct: an
    /// ambiguous/unknown credential state routes to IT, never to a
    /// fabricated "it's fine, just re-sign-in" Bob lane.
    #[test]
    fn the_worse_known_auth_state_always_routes_to_it_never_bob() {
        assert!(matches!(
            route_credential_state(AuthState::Revoked),
            CredentialRouting::ItDeprovisionOffer(_)
        ));
    }

    #[test]
    fn admin_contact_resolution_honors_a_forced_value() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(admin_contact_override_env(), "forced:it@example.com");
        }
        assert_eq!(resolve_admin_contact(), Some("it@example.com".to_string()));
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(admin_contact_override_env()) };
    }

    #[test]
    fn admin_contact_resolution_ignores_a_user_domain_value() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(admin_contact_override_env(), "user") };
        assert_eq!(
            resolve_admin_contact(),
            None,
            "a user-domain AdminContact must never redirect where a safety signal goes"
        );
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(admin_contact_override_env()) };
    }

    #[test]
    fn admin_contact_resolution_absent_is_none_not_a_fabricated_endpoint() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(admin_contact_override_env(), "absent") };
        assert_eq!(resolve_admin_contact(), None);
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(admin_contact_override_env()) };
    }

    /// Regression guard for the module doc's "content-free by construction"
    /// claim: pins the exact serialized key set so a future field addition
    /// (e.g. accidentally threading `identity`/`org` through) is caught
    /// here, not discovered downstream in an IT-facing renderer.
    #[test]
    fn it_signal_serializes_to_exactly_kind_and_admin_contact() {
        let signal = ItSignal {
            kind: ItSignalKind::AuthRevokedDeprovisionOffer,
            admin_contact: Some("it@example.com".to_string()),
        };
        let value = serde_json::to_value(&signal).expect("ItSignal must serialize");
        let obj = value.as_object().expect("ItSignal serializes to an object");
        let mut keys: Vec<&str> = obj.keys().map(|k| k.as_str()).collect();
        keys.sort_unstable();
        assert_eq!(keys, vec!["admin_contact", "kind"]);
    }
}
