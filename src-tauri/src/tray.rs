//! Tray glyph construction + live updates (T6).
//!
//! **D-4 finding (Tauri 2.11.5's tray API, verified against the `tauri`
//! crate source, `src/tray/mod.rs`):**
//! - (a) Template images: **supported.** `TrayIconBuilder::icon_as_template`
//!   / `TrayIcon::set_icon_as_template` / the atomic
//!   `set_icon_with_as_template` are macOS-only, real APIs backed by
//!   `NSImage.template`. T6 relies on this directly.
//! - (b) Per-state badge compositing / overlay: **not supported.** There is
//!   no overlay/badge primitive anywhere in the tray or menu API — `icon`/
//!   `set_icon` always replace the *entire* image wholesale. The only other
//!   per-state signal exposed is `set_title` (macOS/Linux only, text next to
//!   the glyph, not an image overlay). **Consequence for T6:** the badge is
//!   composited into the icon's pixel buffer *before* calling
//!   `set_icon_with_as_template` — `render::glyph::composite` produces one
//!   final `Image` per `(StatusState, badge shape)` pair; this module never
//!   layers a badge on top via the tray API (there is no such API).
//!
//! **VoiceOver label (best-effort, flagged gap).** 60-ui-design.md requires
//! the tray item's accessibility label to be the current status sentence.
//! Tauri 2.11.5's tray API exposes no direct `NSAccessibility` label/
//! description setter — `set_tooltip` is the closest available primitive
//! (macOS reads a status item's tooltip as part of its accessibility
//! description). `update` below sets the tooltip to the status sentence as
//! the current best-effort mapping; a native AX patch to set the label
//! explicitly is a real gap, flagged here rather than worked around, for a
//! future task once the API surface allows it.
//!
//! **Reduce-motion.** The tray glyph itself is always a single static,
//! composited bitmap (one per poll) — there is no continuous animation of
//! the menu-bar icon in this architecture (Tauri tray icons are not
//! frame-animated here), so there is no motion to honor/reduce at this
//! layer. The Syncing "ring" and Setup-needed "hollow pulse" motion tokens
//! (`--motion-ring` / `--motion-pulse`) are a popover/T7 CSS concern only.

use crate::render::derive::RenderState;
use crate::render::glyph;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{
    menu::{Menu, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, Wry,
};

/// Fixed id so `timer::poll_once` can look this tray icon back up via
/// `AppHandle::tray_by_id` on every poll, rather than threading a `TrayIcon`
/// handle through the async task by hand.
pub const TRAY_ID: &str = "control-tower-tray";

/// The popover window's label, per `tauri.conf.json`'s `app.windows[0]`.
const POPOVER_LABEL: &str = "popover";

/// D2 (T9 follow-up) focus-fight guard. Clicking the tray while the popover
/// is open blurs the popover as a side effect of the click itself, and the
/// webview's own blur listener (`src/main.ts`) reacts to that by invoking
/// `commands::hide_popover` over IPC. That invoke can land *before*
/// `toggle_popover` below gets to run (native tray click handling and an
/// async IPC round-trip race on the same event loop), so a naive
/// visible-vs-hidden toggle would see "already hidden" and immediately
/// reopen it — the exact reopen-on-the-same-click bug this guard exists to
/// prevent. `hide_popover_window` (the ONE place that ever hides this
/// window — the tray's own toggle and the IPC command both call it, never a
/// second hide implementation) stamps the moment it hid the window here;
/// `toggle_popover` refuses to treat "currently hidden" as "safe to open"
/// again within `AUTO_HIDE_GRACE` of that stamp.
pub struct AutoHideGuard(Mutex<Option<Instant>>);

impl AutoHideGuard {
    pub fn new() -> Self {
        Self(Mutex::new(None))
    }

    fn mark_now(&self) {
        *self.0.lock().unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
    }

    fn hidden_within_grace(&self) -> bool {
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_some_and(|t| t.elapsed() < AUTO_HIDE_GRACE)
    }
}

impl Default for AutoHideGuard {
    fn default() -> Self {
        Self::new()
    }
}

/// Short enough that no legitimate deliberate "close, then quickly reopen"
/// gesture is silently swallowed, long enough to comfortably outlast the
/// click-vs-IPC race described on `AutoHideGuard`.
const AUTO_HIDE_GRACE: Duration = Duration::from_millis(250);

/// Builds the tray item at launch, rendered from `initial` (the app's
/// honest bootstrap holding state — see `commands::initial_render_state` —
/// on the very first launch, or whatever `timer::poll_once` has already
/// stored by the time this runs). Construction and live-update
/// (`update`, below) deliberately share the same composited-image code path
/// (`render::glyph::composite`) so there is exactly one place that maps a
/// glyph token to pixels.
pub fn build(app: &AppHandle<Wry>, initial: &RenderState) -> tauri::Result<()> {
    let quit = PredefinedMenuItem::quit(app, Some("Quit Copilot Control Tower"))?;
    let menu = Menu::with_items(app, &[&quit])?;

    TrayIconBuilder::with_id(TRAY_ID)
        .icon(glyph::composite(&initial.header.glyph_state))
        .icon_as_template(true)
        .menu(&menu)
        // Left click is reserved for toggling the popover (see
        // `on_tray_icon_event` below); right-click still shows the Quit menu
        // via the OS's native context-menu behavior, unaffected by this
        // flag.
        .show_menu_on_left_click(false)
        .tooltip(&initial.header.sentence)
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                toggle_popover(tray.app_handle());
            }
        })
        .build(app)?;

    Ok(())
}

/// Repaints the tray icon + tooltip from a fresh `RenderState` — a pure
/// render of `state.header.glyph_state`/`.sentence` (T5 already decided both;
/// this function does not re-derive anything). Called from
/// `timer::poll_once` after every doctor poll.
pub fn update(tray: &TrayIcon<Wry>, state: &RenderState) -> tauri::Result<()> {
    let icon = glyph::composite(&state.header.glyph_state);
    tray.set_icon_with_as_template(Some(icon), true)?;
    tray.set_tooltip(Some(&state.header.sentence))?;
    Ok(())
}

/// Shows or hides the popover window. Defensive no-op if the window is
/// somehow absent (it's always declared in `tauri.conf.json`'s
/// `app.windows`, per T1) rather than panicking the tray's event callback.
fn toggle_popover(app: &AppHandle<Wry>) {
    let Some(window) = app.get_webview_window(POPOVER_LABEL) else {
        return;
    };
    if window.is_visible().unwrap_or(false) {
        hide_popover_window(app);
        return;
    }

    // D2 focus-fight guard: this same click may have just blurred (and
    // therefore already hidden) the popover before this handler ran — see
    // `AutoHideGuard`'s doc comment. Don't reopen it in that case.
    if let Some(guard) = app.try_state::<AutoHideGuard>() {
        if guard.hidden_within_grace() {
            return;
        }
    }

    let _ = window.show();
    let _ = window.set_focus();
}

/// The ONE place this window is ever hidden — called from the tray's own
/// click-toggle above and from `commands::hide_popover` (Esc / blur, D2),
/// so there is never a second, drifting notion of "closed." Defensive
/// no-op if the window is absent, same as `toggle_popover`. Always stamps
/// `AutoHideGuard` so a subsequent tray click within the grace window
/// doesn't immediately undo this hide.
pub(crate) fn hide_popover_window(app: &AppHandle<Wry>) {
    if let Some(window) = app.get_webview_window(POPOVER_LABEL) {
        let _ = window.hide();
    }
    if let Some(guard) = app.try_state::<AutoHideGuard>() {
        guard.mark_now();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_hide_guard_starts_without_a_recent_hide() {
        let guard = AutoHideGuard::new();
        assert!(!guard.hidden_within_grace());
    }

    #[test]
    fn auto_hide_guard_reports_recent_hide_within_grace() {
        let guard = AutoHideGuard::new();
        guard.mark_now();
        assert!(guard.hidden_within_grace());
    }

    #[test]
    fn auto_hide_guard_expires_after_the_grace_window() {
        let guard = AutoHideGuard::new();
        *guard.0.lock().unwrap() =
            Some(Instant::now() - AUTO_HIDE_GRACE - Duration::from_millis(50));
        assert!(!guard.hidden_within_grace());
    }
}
