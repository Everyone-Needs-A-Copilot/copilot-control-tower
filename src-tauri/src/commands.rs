//! The Rust <-> web-UI seam (T5).
//!
//! Two members from the original architecture WP: a `#[tauri::command]` the
//! popover calls once on open (`get_state`), and an event Rust pushes when a
//! fresh doctor parse changes state (`state-changed`, emitted from
//! `timer::poll_once`). A third command, `refresh_now`, is the manual "sync
//! now" escape hatch — it does not bypass anything, it just triggers the
//! SAME poll path (`timer::poll_once`) immediately instead of waiting for the
//! next tick.
//!
//! A fourth command, `hide_popover` (T9 D2 follow-up), lets the web UI ask
//! Rust to dismiss the popover on Esc or focus-loss/click-outside — the two
//! conventional menu-bar-popover dismissal gestures the tray's own
//! left-click toggle can't see, since those originate in the webview, not
//! from a native tray event. It delegates to `tray::hide_popover_window`,
//! the SAME function the tray's own click-toggle uses to hide this window,
//! so there is never a second, drifting "closed" implementation.
//!
//! The DTO crossing this seam is always the **typed domain state**
//! (`render::derive::RenderState`), never the raw wire JSON — the web UI must
//! never be able to reinterpret unparsed CLI output. See `model/state.rs`
//! and `render/derive.rs`.
//!
//! This module also owns the managed-state container (`DoctorState`): the
//! single source of truth `get_state` reads from and `timer::poll_once`
//! writes to. There is exactly one instance, `.manage()`d once in `lib.rs`'s
//! `.setup()` — no second copy of "the current state" exists anywhere in the
//! process (invariant #2's single-process discipline applies to state, not
//! just to not spawning a second binary).

use crate::model::state::{CliUnreadableReason, ParseOutcome};
use crate::render::derive::{derive_render_state, ClientState, HeaderView, RenderState};
use std::sync::Mutex;
use tauri::{AppHandle, State};

/// Event name Rust emits whenever a fresh doctor parse lands, whether or not
/// the state actually changed (the popover's cross-fade + a11y live region
/// key off a consistent "a poll just completed" signal — see `timer.rs`).
/// Mirrors `src/types.ts`'s `STATE_CHANGED_EVENT` constant.
pub const STATE_CHANGED_EVENT: &str = "state-changed";

/// The one instance of "what does the tray currently show", managed by
/// Tauri (`app.manage(..)` in `lib.rs`). `render` is a plain `std::sync::
/// Mutex` (short, synchronous critical section: read-clone or overwrite,
/// never held across an `.await`); `poll_lock` is the async mutex the doctor
/// timer and `refresh_now` both acquire around the actual `cli::run_doctor`
/// call, so at most one doctor poll is ever in flight at a time (T5's
/// "one-in-flight" requirement) — a concurrent trigger simply waits its turn
/// rather than stacking a second concurrent spawn.
pub struct DoctorState {
    render: Mutex<RenderState>,
    pub(crate) poll_lock: tauri::async_runtime::Mutex<()>,
}

impl DoctorState {
    pub fn new(initial: RenderState) -> Self {
        Self {
            render: Mutex::new(initial),
            poll_lock: tauri::async_runtime::Mutex::new(()),
        }
    }

    pub fn snapshot(&self) -> RenderState {
        self.render
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    pub fn replace(&self, fresh: RenderState) {
        *self.render.lock().unwrap_or_else(|e| e.into_inner()) = fresh;
    }
}

/// The honest bootstrap state held before the app's first doctor poll
/// returns: `client_state: CliUnreadable` with NO reason (distinct from any
/// real I/O/schema failure — `cli_unreadable_reason: None` is only reachable
/// from here, never from `model::state::parse_doctor_body`, which always
/// picks a concrete reason). Deliberately NOT `ClientState::Ok` / any
/// `CliStatus` — this function does not go through the parse boundary at all
/// (there is no CLI body yet to parse), so it must not fabricate one; it is
/// an honest "haven't checked yet", never Healthy, never a guessed status.
pub fn initial_render_state() -> RenderState {
    RenderState {
        client_state: ClientState::CliUnreadable,
        cli_unreadable_reason: None,
        host: None,
        status: None,
        offline: false,
        header: HeaderView {
            glyph_state: "hollow".to_string(),
            sentence: "Checking your setup…".to_string(),
        },
        products: Vec::new(),
        auth_issues: Vec::new(),
    }
}

/// Snapshot pull — the popover calls this once on open. Always returns
/// whatever the last successful (or fail-closed) doctor parse produced,
/// never recomputed here.
#[tauri::command]
pub fn get_state(state: State<'_, DoctorState>) -> RenderState {
    state.snapshot()
}

/// The manual "sync now" escape hatch. Triggers the SAME poll path the timer
/// uses (`timer::poll_once`) immediately; does not bypass the one-in-flight
/// guard, the CLI-spawn boundary, or the parse boundary — it is a trigger,
/// not a shortcut.
#[tauri::command]
pub async fn refresh_now(app: AppHandle) {
    crate::timer::poll_once(&app).await;
}

/// D2 (T9 follow-up): dismisses the popover — the web UI's Esc-keydown and
/// focus-loss/blur listeners (`src/main.ts`) both invoke this. A thin
/// passthrough to `tray::hide_popover_window`; this command owns no window
/// logic of its own (single-process invariant: exactly one place hides this
/// window, reachable from either the native tray click or this IPC seam).
#[tauri::command]
pub fn hide_popover(app: AppHandle) {
    crate::tray::hide_popover_window(&app);
}

/// Shared by `timer.rs`'s exceptional "the poll task itself failed to run"
/// path (e.g. `spawn_blocking` join error) — collapses to the same
/// `CliUnreadableReason::IoError` a genuine spawn failure gets, via the SAME
/// `derive_render_state` pipeline every other outcome goes through (never a
/// hand-built `RenderState` pretending to be a real verdict).
pub(crate) fn unreadable_io_error() -> RenderState {
    derive_render_state(&ParseOutcome::Unreadable(CliUnreadableReason::IoError))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_state_is_never_healthy_and_carries_no_reason() {
        let s = initial_render_state();
        assert_eq!(s.client_state, ClientState::CliUnreadable);
        assert_eq!(s.cli_unreadable_reason, None);
        assert_eq!(s.status, None);
        assert_ne!(
            s.header.glyph_state, "none",
            "bootstrap state must never render the Healthy glyph"
        );
    }

    #[test]
    fn doctor_state_round_trips_through_replace_and_snapshot() {
        let ds = DoctorState::new(initial_render_state());
        let fresh = unreadable_io_error();
        ds.replace(fresh.clone());
        let got = ds.snapshot();
        assert_eq!(got.client_state, fresh.client_state);
        assert_eq!(got.cli_unreadable_reason, fresh.cli_unreadable_reason);
    }
}
