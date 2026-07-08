//! Route-by-competence (M5/S6, `.copilot/wp/30.md`, invariant #5,
//! `docs/01-architecture/architecture.md` §9 — the Bob-agency model).
//! **Extended by M6/S2 (task 53)** into the full router: `event`
//! ([`event::RoutableEvent`], the exhaustive event union) + `policy`
//! ([`policy::route`], the pure declarative classifier) — see both modules'
//! own docs. This top-level module still owns the pieces M5 built
//! ([`Actor`], [`ItSignal`]/[`ItSignalKind`], [`route_credential_state`],
//! [`deprovision_trigger`]) PLUS the M6 additions below ([`Routed`],
//! [`AutoAct`]/[`AutoActReason`], [`BobPrompt`]/[`BobPromptKind`],
//! [`BobNotice`]/[`BobNoticeKind`]) — `policy::route` calls
//! `route_credential_state` directly for the auth arm rather than
//! duplicating its expired-vs-revoked decision (EXTEND, not reimplement).
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
//! ## THE full router — [`Routed`] and its three lanes (M6/S2)
//!
//! [`Routed`] is the pure classifier's output type, per task 53's own
//! spelling: `AutoAct(...) | EscalateIt(ItSignal) | AskBob(BobPrompt)`. A
//! fourth, orthogonal output — [`BobNotice`] — is NOT a fourth lane; it is a
//! quiet, past-tense, non-actionable companion payload some `AutoAct`
//! decisions carry (e.g. the security-shadow auto-suspend also tells Bob
//! "kept you safe", and a rollback tells him "kept your working version"),
//! alongside an OPTIONAL companion [`ItSignal`] (the same auto-suspend also,
//! separately, tells IT — §9: "never leave a Bob notification as the sole
//! control on an active security exposure"). Both companions live on
//! [`AutoAct`] itself, not as separate `Routed` variants, so `Routed` stays
//! the exact 3-variant closed set task 53 names.
//!
//! ## The closed-set Bob lane (SOUL.md Principle 2 / the Alert Machine)
//!
//! [`BobPromptKind`] has EXACTLY two variants — `SignIn`/`DirtyWip` — because
//! those are the only two non-deferrable decisions about Bob's OWN data (his
//! credential, his uncommitted work). This is enforced at the type level
//! (adding a third variant is a reviewed, visible diff to this enum, never
//! an ad hoc string elsewhere) and re-verified structurally by
//! `tests/fitness_m6_askbob_closed_set.rs` (FF-M6-B). SOUL.md Case Law is
//! explicit that a held-major, a policy denial, and a self-unblock request
//! are all **OUT** as Bob-facing prompts — `policy::route`'s `HeldForApproval`/
//! `Blocked` arms have no `AskBob` branch AT ALL (a match arm that always
//! returns `EscalateIt`, not a runtime check that happens to agree).
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
pub mod emit;
pub mod event;
pub mod policy;
// M6/S6 (task 57, `.copilot/wp/37.md`): the live-flow integration glue —
// maps an already-trusted `DoctorVerdict`/`UpdateParseOutcome`/rollback
// observation into `RoutableEvent`s, drives them through `policy::route`/
// `emit::emit`, and extracts the Bob-facing pieces (`BobPrompt`/`BobNotice`)
// callers (`timer.rs`, `commands.rs` via `render::bob_lane`) fold into the
// live Tauri state. See that module's own doc for the full wiring map and
// which sources have no live producer yet (dirty-WIP, persistence-disabled,
// notifications-off — flagged, not silently guessed).
pub mod wire;

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

    // -- M6/S2 additions (task 53) below. Every variant here stays a bare,
    // fieldless discriminant, same as the three M5 variants above — see
    // `tests/fitness_m6_itsignal_content_free.rs` (FF-M6-C) for the
    // structural proof that NO `ItSignalKind` variant can ever carry
    // associated data, which makes embedding a personal item name in one
    // impossible by construction, not merely discouraged.
    /// `held_for_approval[]` — a held-major update awaiting IT's centrally-
    /// declared approval authority (architecture.md §9, SOUL.md Case Law:
    /// "Held-major routes to IT's dashboard as an *actionable* item" / "Let
    /// Bob approve a held-major upgrade to clear the badge" is OUT).
    HeldMajorAwaitingApproval,
    /// `blocked[]` — a capability-policy conflict. §9: "capability-policy
    /// conflicts (IT action-log only, never a Bob notification)".
    PolicyDenial,
    /// A `changed[]` entry with `shadowed_by` set — the CLI already
    /// auto-suspended a personal override so a security fix wins. SOUL.md
    /// Case Law: "Auto-suspend a security-shadowing override + escalate to
    /// IT" — "The Fix That Acts Itself". Always paired with
    /// `Routed::AutoAct`'s `it_signal`, never emitted alone.
    SecurityShadowAutoSuspended,
    /// A `changed[]` entry that is unsigned (`signed: false`) with no
    /// shadowing override to suspend — a signature failure, one of §9's
    /// named content-free safety signals ("sig-fail").
    SignatureFailure,
    /// The login item / `launchd` watchdog was found disabled — §9's named
    /// safety signal.
    PersistenceDisabled,
    /// OS notification permission is denied/unavailable — §9's A-H10
    /// fallback: high-severity events re-route to the IT channel.
    NotificationsDisabled,
    /// A-H13: a Bob-actionable item was left un-acted past its time-box —
    /// "time-boxed escalation to IT", never a second, louder Bob prompt.
    BobItemTimedOut,
    /// A `changed[]` entry with `op: pruned` — the reconciling sync removed
    /// something. Bob cannot judge whether a prune was safe (SOUL.md
    /// Alert Machine: "notify Bob when… let the user approve/unblock" is
    /// OUT); without a recently-used/usage signal to distinguish a quiet,
    /// past-tense Bob notice from a silent removal (architecture.md §9's
    /// A-H9, flagged G-M6-3 — usage-source data does not exist yet), every
    /// prune fails closed to IT review rather than guessing "safe to stay
    /// silent" or fabricating a Bob-facing decision.
    PruneNeedsReview,
    /// A doctor checker finding whose repair is either destructive or has
    /// no repair token at all — not reversible, or nothing to auto-apply.
    /// Bob cannot judge a destructive repair (proximity to the menu bar is
    /// not competence, SOUL.md Principle 2); this is not his own data, so it
    /// is never `AskBob` either.
    RepairNeedsReview,
    /// The fail-closed catch-all for `RoutableEvent::Unrecognized` — an
    /// event the emission layer could not classify. CLAUDE.md invariant #5:
    /// "an unknown/ambiguous event... routes to EscalateIt... NEVER silently
    /// AutoAct and NEVER AskBob".
    UnrecognizedEvent,
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

// == M6/S2 additions (task 53) ==============================================
//
// `Routed`/`AutoAct`/`AutoActReason`/`BobPrompt`/`BobPromptKind`/`BobNotice`/
// `BobNoticeKind` — the full router's output types. `policy::route` is the
// only place any of these is EVER constructed with a non-static-copy payload
// (mirroring `parse_doctor_body`/`parse_update_body`'s "the parse boundary is
// the only construction site" discipline, applied here to the routing
// boundary instead of the parse boundary).

/// Why an `AutoAct` fired — never itself Bob- or IT-facing content (the
/// companion [`ItSignal`]/[`BobNotice`] on [`AutoAct`] carry that, when
/// present); this is an internal/audit-trail label a future logging seam can
/// render, not a user-facing string, so it stays a bare enum rather than a
/// copy string.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutoActReason {
    /// An ordinary reversible change the CLI already applied — §9's
    /// re-materialize / re-clone / ff-pull / apply-signed-patches bucket.
    OrdinaryUpdateApplied,
    /// A checker's own non-destructive repair token, applied — reversible,
    /// and not a decision Bob has the basis to make (which fix to run).
    NonDestructiveRepairApplied,
    /// §9's "Fix That Acts Itself" — a personal override shadowing a
    /// security fix was auto-suspended so the fixed version wins
    /// immediately (reversible: Bob re-affirms later).
    SecurityShadowOverrideSuspended,
    /// M4's crash-only watchdog already rolled back to last-known-good; this
    /// router only renders that outcome.
    RollbackAlreadyApplied,
    /// M5's forced-`Deprovisioned` trigger already ran (or the CLI/MDM agent
    /// performed the deprovision out of band); this router only renders the
    /// outcome and tells IT — never Bob (see `deprovision_trigger`'s own
    /// "never a Bob-facing invocation" doc, which this arm never
    /// contradicts: no Bob path exists on this variant at all).
    DeprovisionAlreadyRendered,
    /// A benign no-op (`ChangeOp::Unchanged`, or a `pass` checker finding) —
    /// nothing for anyone to judge or act on.
    NoActionNeeded,
}

/// The `AutoAct` lane's payload. `it_signal`/`bob_notice` are companions, not
/// alternatives — see the module doc's "THE full router" section for why a
/// security-shadow auto-suspend legitimately carries BOTH at once (§9: an
/// auto-acted safety event is reported to Bob quietly AND told to IT in
/// parallel, never left as a Bob notification alone on a live exposure).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AutoAct {
    pub reason: AutoActReason,
    pub it_signal: Option<ItSignal>,
    pub bob_notice: Option<BobNotice>,
}

/// The router's total output — exactly the three lanes task 53 names,
/// verbatim: `AutoAct(...) | EscalateIt(ItSignal) | AskBob(BobPrompt)`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Routed {
    AutoAct(AutoAct),
    EscalateIt(ItSignal),
    AskBob(BobPrompt),
}

/// The CLOSED SET of exactly two non-deferrable decisions about Bob's own
/// data — see the module doc's "closed-set Bob lane" section.
/// `#[non_exhaustive]` is deliberately NOT applied: a third variant is a
/// reviewed, visible diff to this exact enum, the one place in the whole
/// crate that could ever widen who Bob is asked about.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum BobPromptKind {
    SignIn,
    DirtyWip,
}

/// A single, quiet, respectful interruption about Bob's own data. Mirrors
/// `src/types.ts`'s `BobPrompt` shape exactly (`kind`/`title`/`detail`/
/// `action_label`, all strings) — every field here is `&'static str`: this
/// router's own copy is fixed, compiled-in text, never assembled from
/// CLI-supplied content (there is nothing to interpolate; the closed set is
/// two prompts, not a template).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct BobPrompt {
    pub kind: BobPromptKind,
    pub title: &'static str,
    pub detail: &'static str,
    pub action_label: &'static str,
}

impl BobPrompt {
    /// Copy sourced verbatim from `70-copy-voice.md` § D / `render/copy.ts`'s
    /// `BOB_SIGNIN_*` constants (the S5/uid stream already built the web-UI
    /// side to this exact text) — kept in sync deliberately, not
    /// independently invented, so Bob reads the identical sentence whether
    /// this fires as a system notification or the in-popover fallback.
    pub fn sign_in() -> Self {
        Self {
            kind: BobPromptKind::SignIn,
            title: "CLI Copilot needs you to sign in again for its department layer — it's a quick browser step.",
            detail: "CLI Copilot — department layer needs sign-in. Everything else is up to date.",
            action_label: "Sign in…",
        }
    }

    /// Copy sourced verbatim from `70-copy-voice.md` § E / `render/copy.ts`'s
    /// `BOB_DIRTY_WIP_*` constants.
    pub fn dirty_wip() -> Self {
        Self {
            kind: BobPromptKind::DirtyWip,
            title: "You have unsaved personal work. Save or commit it, then I'll sync.",
            detail: "I never touch your own files without you.",
            action_label: "Show me…",
        }
    }
}

/// The set of quiet, non-actionable notices Bob sees for an event he has no
/// basis to act on. Mirrors `src/types.ts`'s `BobNoticeKind`. `KeptYouSafe`/
/// `KeptYourWorkingVersion` report something already AUTO-ACTED (past
/// tense); `WaitingOnIt` (M6/S6, task 57) is the one exception to that
/// framing — a held-major hasn't been acted on at all, it is EscalateIt's
/// own companion render (architecture.md §9's event->lane matrix: "held-major
/// routes to IT's dashboard as an *actionable* item... Bob sees a
/// non-actionable 'waiting on IT'"; `70-copy-voice.md` row 93/168's "waiting
/// on IT... nothing you need to do" is this notice's copy source). It still
/// belongs on `BobNotice` rather than a fourth `Routed` variant: from Bob's
/// side it renders IDENTICALLY to the other two (a quiet, static line, no
/// action, no alarm) — `policy::route`'s `HeldForApproval` arm itself stays
/// untouched (still a bare `EscalateIt`, still has NO `AskBob` branch,
/// per SOUL.md Case Law); `routing::wire` (task 57) is what pairs that
/// `EscalateIt(HeldMajorAwaitingApproval)` with this notice at the wiring
/// layer, one level above the pure classifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum BobNoticeKind {
    KeptYouSafe,
    KeptYourWorkingVersion,
    WaitingOnIt,
}

/// A quiet, PAST-TENSE report of something already handled — never an
/// action/dismiss/approve field (per `70-copy-voice.md`'s "Past-tense for
/// anything already handled" voice rule); see `src/types.ts`'s `BobNotice`
/// doc for why a re-affirm/approve control is deliberately absent even here.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct BobNotice {
    pub kind: BobNoticeKind,
    pub message: &'static str,
}

impl BobNotice {
    /// Copy sourced verbatim from `70-copy-voice.md` § F /
    /// `render/copy.ts`'s `BOB_KEPT_YOU_SAFE`.
    pub fn kept_you_safe() -> Self {
        Self {
            kind: BobNoticeKind::KeptYouSafe,
            message: "Kept you safe — a security fix replaced a component you'd overridden.",
        }
    }

    /// Copy sourced verbatim from `70-copy-voice.md`'s Errors microcopy table
    /// ("Bad self-update (E14)" Bob row) / `render/copy.ts`'s
    /// `BOB_KEPT_YOUR_WORKING_VERSION`.
    pub fn kept_your_working_version() -> Self {
        Self {
            kind: BobNoticeKind::KeptYourWorkingVersion,
            message: "Kept your working version — an update didn't start cleanly, so I rolled it back. Nothing broke.",
        }
    }

    /// M6/S6 (task 57). Copy sourced from `70-copy-voice.md` row 93
    /// ("...an org-layer update is waiting on IT." / "Nothing you need to
    /// do.") and row 168 ("We're waiting on IT" / "...There's nothing for
    /// you to do — IT has been told automatically."), generalized to drop
    /// the product/layer name (content-free by construction, matching
    /// `BobPrompt`'s own fixed-copy discipline — `HeldForApprovalEvent`
    /// itself carries no such field to interpolate; see `event.rs`'s doc).
    pub fn waiting_on_it() -> Self {
        Self {
            kind: BobNoticeKind::WaitingOnIt,
            message: "An update is waiting on IT — nothing for you to do.",
        }
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

    /// Every M6 `ItSignalKind` addition must still serialize through the
    /// SAME two-field shape — an extra field on any one variant would be a
    /// silent widening of the content-free contract this whole enum exists
    /// to hold.
    #[test]
    fn every_extended_it_signal_kind_still_serializes_to_exactly_kind_and_admin_contact() {
        for kind in [
            ItSignalKind::HeldMajorAwaitingApproval,
            ItSignalKind::PolicyDenial,
            ItSignalKind::SecurityShadowAutoSuspended,
            ItSignalKind::SignatureFailure,
            ItSignalKind::PersistenceDisabled,
            ItSignalKind::NotificationsDisabled,
            ItSignalKind::BobItemTimedOut,
            ItSignalKind::PruneNeedsReview,
            ItSignalKind::RepairNeedsReview,
            ItSignalKind::UnrecognizedEvent,
        ] {
            let signal = ItSignal {
                kind,
                admin_contact: None,
            };
            let value = serde_json::to_value(&signal).expect("ItSignal must serialize");
            let obj = value.as_object().expect("ItSignal serializes to an object");
            let mut keys: Vec<&str> = obj.keys().map(|k| k.as_str()).collect();
            keys.sort_unstable();
            assert_eq!(keys, vec!["admin_contact", "kind"], "kind={kind:?}");
        }
    }

    /// `BobPrompt`/`BobNotice` mirror `src/types.ts`'s shapes exactly —
    /// pinned here so a future field addition on either side is caught
    /// immediately, not discovered as a runtime mismatch downstream (S6/S7).
    #[test]
    fn bob_prompt_serializes_to_exactly_the_four_ts_mirrored_fields() {
        for prompt in [BobPrompt::sign_in(), BobPrompt::dirty_wip()] {
            let value = serde_json::to_value(prompt).expect("BobPrompt must serialize");
            let obj = value
                .as_object()
                .expect("BobPrompt serializes to an object");
            let mut keys: Vec<&str> = obj.keys().map(|k| k.as_str()).collect();
            keys.sort_unstable();
            assert_eq!(keys, vec!["action_label", "detail", "kind", "title"]);
        }
    }

    #[test]
    fn bob_notice_serializes_to_exactly_the_two_ts_mirrored_fields() {
        for notice in [
            BobNotice::kept_you_safe(),
            BobNotice::kept_your_working_version(),
            BobNotice::waiting_on_it(),
        ] {
            let value = serde_json::to_value(notice).expect("BobNotice must serialize");
            let obj = value
                .as_object()
                .expect("BobNotice serializes to an object");
            let mut keys: Vec<&str> = obj.keys().map(|k| k.as_str()).collect();
            keys.sort_unstable();
            assert_eq!(keys, vec!["kind", "message"]);
        }
    }

    /// `BobPromptKind`/`BobNoticeKind` must serialize to the EXACT string
    /// literals `src/types.ts`'s `BobPromptKind`/`BobNoticeKind` union types
    /// name, kebab-case — a mismatch here would silently break the Bob-lane
    /// UI's discriminated union at the wire boundary.
    #[test]
    fn bob_prompt_and_notice_kinds_serialize_to_the_exact_kebab_case_ts_strings() {
        assert_eq!(
            serde_json::to_value(BobPromptKind::SignIn).unwrap(),
            serde_json::json!("sign-in")
        );
        assert_eq!(
            serde_json::to_value(BobPromptKind::DirtyWip).unwrap(),
            serde_json::json!("dirty-wip")
        );
        assert_eq!(
            serde_json::to_value(BobNoticeKind::KeptYouSafe).unwrap(),
            serde_json::json!("kept-you-safe")
        );
        assert_eq!(
            serde_json::to_value(BobNoticeKind::KeptYourWorkingVersion).unwrap(),
            serde_json::json!("kept-your-working-version")
        );
        assert_eq!(
            serde_json::to_value(BobNoticeKind::WaitingOnIt).unwrap(),
            serde_json::json!("waiting-on-it")
        );
    }

    /// Pins every `ItSignalKind` variant's exact serialized string against
    /// `src/types.ts`'s `ItSignalKind` union — a mismatch here would silently
    /// break the TS mirror's discriminated union at the wire boundary, the
    /// same regression guard `bob_prompt_and_notice_kinds_serialize_to_the_
    /// exact_kebab_case_ts_strings` above provides for the Bob-lane types.
    #[test]
    fn it_signal_kind_serializes_to_the_exact_snake_case_ts_strings() {
        let expected = [
            (ItSignalKind::DeprovisionTriggered, "deprovision_triggered"),
            (ItSignalKind::DeprovisionAmbiguous, "deprovision_ambiguous"),
            (
                ItSignalKind::AuthRevokedDeprovisionOffer,
                "auth_revoked_deprovision_offer",
            ),
            (
                ItSignalKind::HeldMajorAwaitingApproval,
                "held_major_awaiting_approval",
            ),
            (ItSignalKind::PolicyDenial, "policy_denial"),
            (
                ItSignalKind::SecurityShadowAutoSuspended,
                "security_shadow_auto_suspended",
            ),
            (ItSignalKind::SignatureFailure, "signature_failure"),
            (ItSignalKind::PersistenceDisabled, "persistence_disabled"),
            (
                ItSignalKind::NotificationsDisabled,
                "notifications_disabled",
            ),
            (ItSignalKind::BobItemTimedOut, "bob_item_timed_out"),
            (ItSignalKind::PruneNeedsReview, "prune_needs_review"),
            (ItSignalKind::RepairNeedsReview, "repair_needs_review"),
            (ItSignalKind::UnrecognizedEvent, "unrecognized_event"),
        ];
        for (kind, expected_str) in expected {
            assert_eq!(
                serde_json::to_value(kind).unwrap(),
                serde_json::json!(expected_str),
                "kind={kind:?}"
            );
        }
    }
}
