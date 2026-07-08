//! `RoutableEvent` — M6/S2 (task 53), the exhaustive union of every event
//! class [`super::policy::route`] classifies. Architecture:
//! `docs/01-architecture/architecture.md` §9 (the Bob-agency model),
//! `SOUL.md` Principle 2 ("route by actor-competence × reversibility, not
//! event-class"), `CLAUDE.md` invariant #5. Extends M5's `routing` module
//! (`super::{Actor, ItSignal, ItSignalKind, route_credential_state}`) rather
//! than duplicating it — [`RoutableEvent::AuthCredential`] below is routed by
//! calling the EXISTING `route_credential_state`, never re-deciding
//! expired-vs-revoked here.
//!
//! ## Every variant carries only what competence×reversibility needs
//!
//! Two deliberate content-free-by-construction choices, mirroring the
//! discipline `super::ItSignal`'s own module doc already applies to the
//! OUTPUT side, applied here to the INPUT side:
//!
//! - **No personal/ecosystem item identifiers cross into an event at all.**
//!   [`UpdateChangeEvent`] carries `op`/`signed`/the two trailer PRESENCE
//!   booleans — never `dimension`/`layer`/`item`/`from`/`to`/the trailer TEXT
//!   itself (all of which live on `model::update::ChangedItem`, one layer
//!   up). [`DoctorFindingEvent`] carries `severity`/`destructive`/whether a
//!   repair token exists — never `id`/`detail`/`layer`/`product`/the repair
//!   token TEXT. A router that never receives a personal name cannot leak one
//!   into an [`super::ItSignal`] by construction, the same "impossible, not
//!   merely discouraged" standard `SOUL.md`'s *The Leak* anti-pattern demands
//!   of the inheritance path. [`HeldForApprovalEvent`]/[`BlockedEvent`] carry
//!   NOTHING — their lane never varies by content (see their own docs), so
//!   they are zero-field markers; there is no field to leak.
//! - **`escalate` (the checker's free-text "who this finding should escalate
//!   to" string, `doctor.schema.json`) is deliberately NOT threaded into
//!   [`DoctorFindingEvent`] at all.** The field is open-ended prose ("e.g.
//!   'user'"), not a closed enum; matching on its literal content would
//!   either (a) be exactly the content-interpretation Principle 1
//!   (parse-never-compute) forbids, or (b) risk manufacturing an ad hoc
//!   `AskBob` outside the closed two-kind set `BobPromptKind` enforces (see
//!   `super::BobPromptKind`'s doc). The lane is decided structurally from
//!   `destructive`/repair-availability instead — see
//!   [`super::policy::route`]'s `DoctorFinding` arm.
//!
//! ## `Pass` findings are structurally unroutable
//!
//! [`DoctorFindingEvent::severity`] is `model::failclosed::Severity`, the
//! full 3-value wire type (`Pass`/`Warn`/`Fail`) — `Pass` is a real, legal
//! value here (not excluded by a narrower type) because a `Pass` finding
//! still needs a lane in the exhaustive `route()` match (it gets the benign
//! `AutoActReason::NoActionNeeded`, never fabricated as anything worse). This
//! is a deliberate simplicity trade-off over introducing a parallel
//! `Warn`/`Fail`-only severity type purely to shave one match arm.
//!
//! ## `Unrecognized` — the fail-closed catch-all (CLAUDE.md invariant #5)
//!
//! `RoutableEvent::Unrecognized` exists for exactly one purpose: an event the
//! emission layer (S3+) received but could not classify into any of the
//! other variants (a genuinely new/ambiguous CLI event shape a future schema
//! bump introduces before this router is updated to understand it). Task 53's
//! own fail-closed requirement — "an unknown/ambiguous event... routes to
//! EscalateIt (safe: tell IT) — NEVER silently AutoAct and NEVER AskBob" — is
//! encoded by giving this variant NO fields at all (there is nothing content-
//! bearing to route on) and a single hard-coded policy arm; see
//! `tests/fitness_m6_router_exhaustive.rs`.

use crate::model::failclosed::{AuthState, Severity};
use crate::model::update::ChangeOp;

/// A `doctor --json` checker finding, past M1's own fail-closed parse gate
/// (`model::state::Checker`). `repair_available` is the boolean-only distillate
/// of the wire `repair: Option<String>` token (`model::doctor::CheckerWire`) —
/// a future emission seam (S3+) threads `repair.is_some()` through without
/// ever passing the repair TOKEN TEXT itself into this router.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DoctorFindingEvent {
    pub severity: Severity,
    /// Whether the associated repair (if any) is destructive — security-
    /// relevant per `doctor.schema.json`'s own description: "a missing value
    /// is treated as destructive (fail-closed)". `model::state::Checker`
    /// already enforces that upstream; this router never re-derives it.
    pub destructive: bool,
    /// `true` only when the CLI supplied a non-null `repair` token. A
    /// checker with no repair token at all cannot be auto-acted on — there
    /// is nothing to apply.
    pub repair_available: bool,
}

/// One `update --json` `changed[]` entry, past M6/S1's fail-closed parse gate
/// (`model::update::ChangedItem`). See the module doc's "content-free by
/// construction" section for why `dimension`/`layer`/`item`/`from`/`to`/the
/// trailer TEXT never appear here — only the two CLI-computed booleans this
/// router's policy actually branches on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UpdateChangeEvent {
    pub op: ChangeOp,
    /// A missing wire `signed` already defaulted to `false` one layer up
    /// (`model::update`'s own module doc) — never re-defaulted here.
    pub signed: bool,
    /// `true` only when `shadowed_by` was present (non-null) on the wire —
    /// "an active personal override is shadowing this change" is a
    /// CLI-computed FACT the router reads, never re-derives. See the module
    /// doc for why the shadowing item's IDENTITY never crosses into this
    /// struct.
    pub shadow_present: bool,
}

/// The forced `Deprovisioned` trigger's already-evaluated state (M5's
/// `deprovision_trigger::DeprovisionTriggerState`, narrowed to the two states
/// that are genuinely ROUTABLE events — `NotTriggered` means nothing
/// happened, so the emission layer never constructs a
/// [`RoutableEvent::Deprovision`] for it at all; there is no third arm to
/// route). Kept as this router's OWN small enum, decoupled from M5's
/// I/O-touching `evaluate_deprovision_trigger`/`route_deprovision_trigger`
/// (this router is pure — see `super::policy`'s module doc), rather than
/// reusing M5's type directly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeprovisionEvent {
    /// A forced, unambiguous `true` — the CLI already ran.
    Triggered,
    /// Forced, but neither a recognized true- nor false-token — held, never
    /// silently treated as clean.
    Ambiguous,
}

/// One `held_for_approval[]` entry. Zero fields: `held_for_approval` always
/// routes `EscalateIt` regardless of `dimension`/`from`/`to`/`reason` (§9:
/// "held-major approval... IT approves centrally, Bob sees a non-actionable
/// 'waiting on IT'") — there is no content that could change this event's
/// lane, so none is carried. See `SOUL.md`'s Alert Machine anti-pattern /
/// Case Law: "Let Bob approve a held-major upgrade to clear the badge —
/// OUT."
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HeldForApprovalEvent;

/// One `blocked[]` entry. Zero fields, for two reasons: (1) `blocked[]` is a
/// deliberately OPEN wire shape the app cannot interpret (`model::update`'s
/// own "G-M6-4" doc — `BlockedEntry` retains raw JSON verbatim, never
/// reinterpreted), so this router has no trustworthy content to branch on
/// even if it wanted to; (2) every `blocked[]` entry routes `EscalateIt`
/// unconditionally (a capability-policy conflict is "IT action-log only,
/// never a Bob notification" per architecture.md §9) regardless of content
/// even if it WERE interpretable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BlockedEvent;

/// The exhaustive union of every event class the router classifies (task 53
/// scope list, verbatim): a doctor checker finding, an update `changed[]`
/// entry, a `held_for_approval[]` entry, a `blocked[]` entry, an auth state,
/// a deprovision trigger, a rollback outcome, dirty personal WIP,
/// persistence-disabled, notifications-off, a time-boxed Bob item, and the
/// fail-closed unrecognized catch-all. `#[non_exhaustive]` is deliberately
/// NOT applied — a new event class is a reviewed addition to this enum
/// (compiler-enforced exhaustiveness in `policy::route`'s match), never a
/// silent wildcard elsewhere in the crate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoutableEvent {
    DoctorFinding(DoctorFindingEvent),
    UpdateChange(UpdateChangeEvent),
    HeldForApproval(HeldForApprovalEvent),
    Blocked(BlockedEvent),
    /// M5's `model::failclosed::AuthState` — reused directly, routed by
    /// calling `super::route_credential_state`, never re-decided here.
    AuthCredential(AuthState),
    Deprovision(DeprovisionEvent),
    /// M4's crash-only-watchdog rollback outcome. Zero fields: a rollback
    /// always routes the same way regardless of which version was poisoned
    /// (the poisoned version STRING is Bob-facing render content for a later
    /// stream, never a routing input — see `updater::rollback_marker`).
    Rollback,
    /// Bob's own uncommitted personal work (invariant #3, never-destroy).
    /// Zero fields: this is always his own data, always `AskBob` — there is
    /// no CLI-computed field that could ever change that.
    DirtyWip,
    /// A safety signal: persistence (the login item / `launchd` watchdog)
    /// was found disabled. Content-free safety signal per architecture.md
    /// §9's list — always `EscalateIt`.
    PersistenceDisabled,
    /// A safety signal: OS notification permission is denied/unavailable.
    /// Always `EscalateIt` (architecture.md §9's A-H10 fallback: "if
    /// notification permission is denied, high-severity events... re-route
    /// to the IT channel").
    NotificationsOff,
    /// A-H13: a Bob-actionable item (his sign-in, his dirty WIP) was left
    /// un-acted past its time-box. Always `EscalateIt` — never a second,
    /// louder `AskBob` (SOUL.md Alert Machine: "Bob-actionable alerts nudge
    /// once then silent forever" is the failure this closes, by escalating
    /// instead of re-asking).
    BobItemTimedOut,
    /// The fail-closed catch-all — see the module doc's own section.
    Unrecognized,
}
