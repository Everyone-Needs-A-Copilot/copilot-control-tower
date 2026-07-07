//! First-run wizard (M3, `.copilot/wp/15.md`): the state machine + phase
//! model + IPC DTOs. **S1 scope only** — this module defines the pure,
//! testable transition function and the wire DTOs S6/S7 will serialize; it
//! wires no persistence, no real sign-in, no managed/unmanaged orchestration,
//! and no Tauri IPC commands/window. Those land as sibling submodules in
//! later tasks; this file only opens the seams so they have somewhere to
//! land without reshaping what already exists:
//!
//! - `state` (S1, this task) — `WizardMode` / `WizardPhase` / `HoldingReason`
//!   / `WizardEvent` and the pure `transition()` function.
//! - `dto` (S1, this task) — the `WizardState` / `WizardStep` / `SigninState`
//!   IPC contract, mirrored 1:1 by `src/types.ts`.
//! - `persist` (S2) — the `cc config set wizard.completed` /
//!   `wizard.checkpoint` seam (config-pointer, never a Rust
//!   read-modify-write — ADR-M3-004).
//! - `signin` (S3) — the `cc auth <integration> --json` device-flow
//!   passthrough (ADR-M3-001) that produces the `dto::SigninState` this
//!   module already shapes.
//! - `materialize` (S4/S5 shared) — the `cc update --json` seam: relays the
//!   CLI's own phase names verbatim (never an ETA, ADR-M3-003) and never
//!   gates a verdict itself — see that module's doc.
//! - `support` (S4/S5 shared) — the small `state::transition`-driving glue
//!   both flows below use identically (`must_transition`, and mapping a
//!   fresh `RenderState` to the one legal Verify-routing event).
//! - `managed_flow` (S4) — the ~0-question managed silent orchestration
//!   ("Silent First Light") — schema-validates the managed profile FIRST,
//!   then drives Detect -> Materialize -> Verify -> Teach -> Done end to end
//!   in one blocking call (no user interaction to wait on).
//! - `unmanaged_flow` (S5) — the ≤3-question guided flow
//!   (ChooseProducts/LayerSetup/SignIn), a small state machine driven one
//!   step at a time across several IPC round-trips (S6).
//! - `commands` (S6, lands in the crate-root `commands.rs` alongside the
//!   M1/M2 IPC surface) — the Tauri commands and window that serialize
//!   `dto::WizardState` across the seam.
//!
//! **Parse-never-compute (invariant #1).** This module computes no health
//! verdict of its own. The only way `state::WizardPhase::Done` is reachable
//! is via `state::WizardEvent::Verified(CliStatus)` carrying a status this
//! crate's M1 parse boundary (`model::state::parse_doctor_body`, consumed
//! through `render::derive`) already decided — see `state::transition`'s doc
//! for the guard. Anything else routes to a `Holding` terminal, never a
//! fabricated completion (ADR-M3-002).

pub mod dto;
pub mod managed_flow;
pub mod materialize;
pub mod persistence;
pub mod signin;
pub mod state;
mod support;
pub mod unmanaged_flow;
