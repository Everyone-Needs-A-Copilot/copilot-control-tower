//! The doctor poll loop (T5), per ADR-M1-004 (single Tauri process, no
//! daemon): an async task inside *this* process, started from `lib.rs`'s
//! `.setup()`, never a second process and never a fallback loop that outlives
//! the app.
//!
//! **Shape:** an immediate poll on startup, then a poll every
//! [`POLL_INTERVAL`]. Each poll calls `cli::run_doctor()` (T4: resolve ->
//! spawn -> classify -> parse -> derive, in one call), stores the resulting
//! `RenderState` in the managed [`crate::commands::DoctorState`], and emits
//! `commands::STATE_CHANGED_EVENT` so an open popover live-updates (T7/T8)
//! and the tray glyph is repainted (`tray::update`).
//!
//! **One-in-flight.** `cli::run_doctor()` is a *blocking* call (it spawns a
//! child process and waits on it, up to `cli::spawn`'s own hard timeout) —
//! `poll_once` therefore runs it on `tauri::async_runtime::spawn_blocking`,
//! off the async runtime's worker threads, and serializes every call behind
//! `DoctorState::poll_lock` (a `tokio::sync::Mutex`, re-exported as
//! `tauri::async_runtime::Mutex`). The periodic tick and a manual
//! `refresh_now()` (T5 IPC) therefore can never run two doctor polls
//! concurrently: whichever arrives second simply waits its turn behind the
//! lock instead of stacking a second concurrent spawn — this is the M1 floor
//! for "coalesce triggers". Battery/metered backoff is explicitly deferred
//! to WS-B (not built here); M1 polls **only** `doctor` (no freshness /
//! update polling).
//!
//! This module computes nothing: `poll_once` never branches on the parsed
//! content, it only stores and republishes whatever `cli::run_doctor` (T4/T3)
//! already decided (invariant #1).
//!
//! **M6/S6 (task 57, `.copilot/wp/37.md`):** the SAME poll additionally
//! drives the router — `cli::run_doctor_with_outcome`'s `ParseOutcome` (the
//! per-checker/per-auth detail `RenderState` alone doesn't preserve) is fed
//! through `routing::wire::wire_doctor`, and the forced `Deprovisioned`
//! trigger (M5/S6) is evaluated on the SAME cadence via `routing::wire::
//! wire_deprovision`. This module still computes no verdict of its own here
//! either: `wire_doctor`/`wire_deprovision` only MAP an already-trusted
//! verdict to a lane (`policy::route`) and dispatch the result — this file
//! adds no new decision, only the live call site the router needed. Not
//! governed by `tests/fitness_m5_deprovision_is_it_routed.rs` (that scan is
//! scoped to `commands.rs`/`tray.rs`/`lib.rs`'s handler list + everything
//! under `src/routing/`), so this file references `routing::` directly.
//!
//! **M7/S9 (`.copilot/wp/43.md`, task 68):** the SAME poll additionally
//! drives the telemetry emitter — `telemetry::emitter::TelemetryState::
//! emit_for_doctor_verdict` re-derives this poll's content-free
//! `ItSignal`s (`routing::wire::doctor_it_signals`, a pure, sink-free read —
//! never a second CLI spawn) plus this poll's status transition into
//! `telemetry::schema::FleetEvent`s, and hands them to the telemetry sink.
//! **This is purely additive**: the `LocalSink` dispatch above is
//! completely unchanged — telemetry is a SEPARATE, opt-in remote sink
//! behind the SAME content-free discipline, gated by `telemetry::optin::
//! telemetry_optin` (off by default; a call reaches no transport at all
//! when disabled — see `telemetry::emitter`'s own doc).

use crate::commands::DoctorState;
use crate::model::state::ParseOutcome;
use crate::render::bob_lane::BobLaneState;
use crate::routing::emit::LocalSink;
use crate::tray;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};

/// Production poll cadence (~1h, per the architecture WP §4 / Decision D-5).
/// A single named constant so the cadence is grep-able in exactly one place.
#[cfg(not(debug_assertions))]
pub const POLL_INTERVAL: Duration = Duration::from_secs(60 * 60);

/// Dev-only short cadence so a running debug build visibly re-polls without
/// waiting an hour — compiled OUT of release builds entirely (same
/// `#[cfg(debug_assertions)]` discipline as `cli::path::dev_override`, not a
/// runtime toggle), so a shipped build can never be coaxed into hammering the
/// CLI on a short interval.
#[cfg(debug_assertions)]
pub const POLL_INTERVAL: Duration = Duration::from_secs(30);

/// Starts the doctor poll loop as a Tokio task inside this process (invariant
/// #2 — single process, no daemon). Call exactly once, from `lib.rs`'s
/// `.setup()`, after `DoctorState` has been `.manage()`d and the tray has
/// been built (`poll_once` looks both up by handle).
pub fn start(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        // Immediate poll on startup — the managed state starts in the
        // honest bootstrap holding state (`commands::initial_render_state`);
        // this replaces it with a real verdict as soon as one exists.
        poll_once(&app).await;
        loop {
            sleep(POLL_INTERVAL).await;
            poll_once(&app).await;
        }
    });
}

/// Sleeps `d` without blocking the async runtime's worker threads (offloaded
/// to `spawn_blocking`, since this crate takes no direct `tokio` dependency —
/// `tauri::async_runtime` re-exports `tokio::sync::{Mutex, mpsc}` but not
/// `tokio::time`).
async fn sleep(d: Duration) {
    let _ = tauri::async_runtime::spawn_blocking(move || std::thread::sleep(d)).await;
}

/// One poll: resolve+spawn+parse+derive (via `cli::run_doctor`, T4/T3), store
/// the result in managed state, emit `state-changed`, and repaint the tray
/// glyph. Public so `commands::refresh_now` (the manual "sync now" escape
/// hatch) can trigger the exact same path on demand — there is only ever one
/// poll implementation.
pub async fn poll_once(app: &AppHandle) {
    let doctor_state = app.state::<DoctorState>();

    // One-in-flight: the periodic tick and a manual refresh_now() serialize
    // here rather than ever running `cli::run_doctor` concurrently.
    let _in_flight = doctor_state.poll_lock.lock().await;

    // `cli::run_doctor_with_outcome` blocks (spawns + waits on a child
    // process, up to `cli::spawn::DOCTOR_TIMEOUT`) — run it off the async
    // runtime's worker threads. M6/S6: the SAME call already resolves both
    // the render DTO (T3/T5) and the `ParseOutcome` the router needs — never
    // a second doctor spawn just to get the router its input.
    let (parse_outcome, fresh) =
        match tauri::async_runtime::spawn_blocking(crate::cli::run_doctor_with_outcome).await {
            Ok(pair) => pair,
            // The poll task itself failed to run (e.g. panicked) — not a CLI
            // failure, but still "I couldn't get a trustworthy verdict this
            // round". Routes through the SAME derive pipeline every other
            // outcome uses, never a hand-built RenderState.
            Err(_) => (
                ParseOutcome::Unreadable(crate::model::state::CliUnreadableReason::IoError),
                crate::commands::unreadable_io_error(),
            ),
        };

    // M7/S9: the PREVIOUS status, captured before it's overwritten below —
    // `telemetry::emitter::fleet_events_for_poll` needs it to decide whether
    // this poll's status is genuinely NEW (never re-emitted on every poll
    // that just reconfirms the same status).
    let previous_status = doctor_state.snapshot().status;

    doctor_state.replace(fresh.clone());

    // Always emitted, even when the state is unchanged, so the popover's
    // cross-fade and the a11y live region (T7/T8) have a consistent "a poll
    // just completed" signal to key off.
    let _ = app.emit(crate::commands::STATE_CHANGED_EVENT, fresh.clone());

    // Repaint the tray glyph from the SAME fresh state — never a second
    // lookup, never a recomputed token (`tray::update` is a pure render of
    // `fresh.header.glyph_state`/`.sentence`, see `tray.rs`).
    if let Some(icon) = app.tray_by_id(tray::TRAY_ID) {
        let _ = tray::update(&icon, &fresh);
    }

    // M6/S6: route this poll's doctor-sourced facts (checker findings + auth
    // states) through the router, dispatching every produced `ItSignal` to
    // the shared `LocalSink` and folding any resulting `AskBob` prompt into
    // the Bob lane (time-boxed — see `render::bob_lane`'s own doc). A
    // `CliUnreadable` outcome carries no checkers/auth to route at all — the
    // tray/popover already renders that state honestly via `fresh` above;
    // this is not a second, silent channel for the same fact.
    let sink = app.state::<LocalSink>();
    if let ParseOutcome::Trusted(verdict) = &parse_outcome {
        let prompt = crate::routing::wire::wire_doctor(verdict, &*sink);
        let bob_lane = app.state::<BobLaneState>();
        bob_lane.apply_doctor_prompt(prompt, &*sink);

        // M7/S9: the additional, opt-in-gated remote telemetry sink —
        // `LocalSink`'s own dispatch above is unchanged. Off means off:
        // `TelemetryState::emit_for_doctor_verdict` checks the live opt-in
        // gate first and reaches no transport call at all when disabled
        // (the default).
        let telemetry = app.state::<crate::telemetry::emitter::TelemetryState>();
        telemetry.emit_for_doctor_verdict(verdict, previous_status);
    }

    // M6/S6: the forced `Deprovisioned` trigger (M5/S6), evaluated on the
    // SAME cadence — `routing::deprovision_trigger`'s own doc names this
    // stream as its intended live caller. A cheap forced-domain read on the
    // ordinary case; only spawns `cc deprovision` on a genuinely forced
    // `true` (never on a `cargo test`/dev box with no forced key set).
    crate::routing::wire::wire_deprovision(&*sink);
}

#[cfg(test)]
mod tests {
    use super::POLL_INTERVAL;
    use std::time::Duration;

    #[test]
    fn poll_interval_is_never_zero_or_absurdly_short() {
        // A zero/near-zero interval would hammer the CLI; guards against a
        // future edit accidentally leaving a test-only value active.
        assert!(POLL_INTERVAL >= Duration::from_secs(5));
    }

    #[cfg(not(debug_assertions))]
    #[test]
    fn release_cadence_is_one_hour() {
        assert_eq!(POLL_INTERVAL, Duration::from_secs(60 * 60));
    }
}
