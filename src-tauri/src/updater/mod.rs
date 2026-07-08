//! M4 Stream-D — distribution/signing/watchdog machinery (`.copilot/wp/24.md`,
//! memory `m4-distribution-decisions`, ADR-M4-001/002).
//!
//! **Module split (coordination note, not a suggestion):** this crate's
//! self-update surface is split across two concurrently-worked streams that
//! must not edit each other's files:
//!
//! - [`watchdog`] (Stream-D / S6, owned by `do`) — the on-disk
//!   staged-bundle layout (`current`/`staged`/`last-known-good`) and the
//!   promote-or-rollback *decision* the stable watchdog makes. It consumes
//!   a heartbeat verdict via the local [`watchdog::HeartbeatSource`] seam
//!   trait rather than reaching into `heartbeat.rs` directly, so it compiles
//!   and is fully unit-testable before that module lands.
//! - [`trust`] (M4/S1, `sec`-owned) — the compiled-in minisign trust root +
//!   default update feed (ADR-M4-003, FF-M4-3), and the forced-domain-only
//!   `UpdateFeedURL`/`UpdateChannel`/`AllowSelfUpdate` reader (FF-M4-4).
//! - [`verify`] (M4/S2, `sec`-owned) — `verify_update` (minisign signature +
//!   downgrade + artifact-hash check) and `verify_staple` (offline
//!   Gatekeeper/notarization check) — both fail-closed, no bypass branch
//!   (FF-M4-2, FF-M4-5). Together these are ADR-M4-004's
//!   `Verified(sig+staple, fail-closed)` step.
//! - [`heartbeat`] (M4/S1, `sec`-owned) — DEFINES the heartbeat-file
//!   path/schema and the `--self-test` protocol (this contract did not
//!   exist before M4), and wires a real, file-backed
//!   [`heartbeat::FileHeartbeatSource`] into `watchdog`'s
//!   [`watchdog::HeartbeatSource`] seam — exactly the wiring this module's
//!   doc asked for, rather than a second, redefined heartbeat contract.
//! - [`check`] (M4/S4, `me`-owned) — the update-check/apply TRANSPORT:
//!   fetches the signed manifest (+ signature, + artifact) from
//!   `trust::update_feed_url()` via a trait-based, test-mockable
//!   [`check::FeedFetcher`], hands them to `verify::verify_update`/
//!   `verify::verify_staple` (never reimplemented), and on success stages
//!   the result into `watchdog::StagedLayout` for the next relaunch's
//!   self-test/promote decision. `commands.rs`'s `check_for_update`/
//!   `apply_update` IPC commands are thin `spawn_blocking` wrappers around
//!   this module's own `check_for_update`/`apply_update` functions.
//! - [`dto`] (M4/S4-S5, `me`-owned) — the `UpdateState`/`UpdateStatus` IPC
//!   DTO `check`/`commands.rs` return, mirroring `src/types.ts`'s
//!   already-frozen (S10) shape.
//! - [`launch`] (M4 gap-closure, S11) — the `StagedBundleLauncher` seam:
//!   HOW `check::apply_update` launches a staged bundle's `--self-test`
//!   process (real subprocess in production, injectable fake in tests) —
//!   never the decide/promote/rollback logic itself.
//! - [`rollback_marker`] (M4 gap-closure, S11) — the tiny, non-secret
//!   "last update outcome" marker persisted on a real rollback so a
//!   SUBSEQUENT normal launch's `check::check_for_update` surfaces
//!   `dto::UpdateStatus::RolledBack` exactly once (shown-once, then
//!   cleared).
//! - [`selftest`] (M4 gap-closure, S11) — the `--self-test` PROCESS
//!   entrypoint `main.rs` calls into: wires `heartbeat::{SELF_TEST_FLAG,
//!   run_self_test}` into the actual argv/exit path, which — before this
//!   module — nothing in this crate did.
//! - [`startup`] (M4 gap-closure, S11) — the crash-only reconciliation
//!   `lib.rs::run()`'s `.setup()` calls once per NORMAL launch: resolves a
//!   PRIOR launch's interrupted (never self-tested) staged update via the
//!   same fail-closed `watchdog::run_self_test`, rather than leaving it as
//!   an ambiguous, un-poisoned leftover.
//! - [`circuit_breaker`] (QA gap-closure, D1/ADR-M4-001) — the app-level
//!   launch-failure circuit breaker: a persisted, atomic, non-secret count
//!   of consecutive unproven launches, checked as the FIRST thing
//!   `lib.rs::run()`'s `.setup()` does. Distinct from `startup`/`watchdog`
//!   above, which handle a bad SELF-UPDATE; this handles the
//!   already-promoted `current/` build crash-looping for any OTHER reason.
//!
//! **Gap-closure note (gate this module split existed to prevent):** the
//! self-test/heartbeat/watchdog machinery above (`heartbeat::run_self_test`,
//! `watchdog::{decide, run_self_test}`, `dto::UpdateStatus::RolledBack`) was
//! fully built by M4 Stream-D/S1/S2 but never wired into the live
//! `main.rs`/`lib.rs`/`check::apply_update` path — `launch`/`rollback_marker`
//! /`selftest`/`startup` above, plus `check::confirm_staged_bundle_boots`,
//! are that wiring. See `tests/fitness_self_update_machinery_is_wired.rs`
//! for the regression guard.
//!
//! If you are adding a new module alongside these: add your own `pub mod`
//! line below, one line per module, so two agents editing this file
//! concurrently only ever collide on adjacent insertions, never the same
//! line.

pub mod check;
pub mod circuit_breaker;
pub mod dto;
pub mod heartbeat;
pub mod launch;
pub mod rollback_marker;
pub mod selftest;
pub mod startup;
pub mod trust;
pub mod verify;
pub mod watchdog;
