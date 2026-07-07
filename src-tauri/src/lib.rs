//! Copilot Control Tower — app wiring.
//!
//! **Single process, thin skin (invariants #1 and #2).** This crate is the
//! *entire* supervisor: tray + doctor-timer Tokio task + Tauri commands, all
//! in one binary. There is no separate daemon and this file
//! must never grow one. Every module boundary below exists to keep the
//! parse-never-compute line a *type* boundary, not a convention:
//!
//! - `cli` — T4: resolves and spawns the CLI (absolute, translocation-safe
//!   path only — never a bare `cc`/`copilot`).
//! - `model` — T3: the wire-format serde structs + the fail-closed
//!   deserialize + the typed, app-owned domain state.
//! - `render` — T5/T6: maps domain state -> tray glyph and buckets checkers
//!   for the popover. Presentation only, never a new verdict.
//! - `timer` — T5: the doctor poll loop (Tokio task inside *this* process).
//! - `tray` — T6: builds/updates the tray icon (template image + badge) and
//!   owns the one place the popover window is ever shown/hidden.
//! - `commands` — T5/T8/D2: the `get_state`/`refresh_now`/`hide_popover`
//!   Tauri commands + `state-changed` event, the whole Rust<->web-UI seam.
//!
//! Nothing in this file computes ecosystem state. If a change here starts
//! looking like resolution/sync/signature/merge/health-scoring logic, it
//! belongs in the `copilot`/`cc` CLI instead (invariant #1).

// T5 (`timer::poll_once`) is the real call site for `cli::run_doctor` — see
// `timer.rs`.
mod cli;
mod commands;
// `pub` (T3): `model`/`render` are reached from `tests/` and
// `examples/gen_dev_fixtures.rs` (separate crates linked against
// `copilot_control_tower_lib`), which need `model::state::parse_doctor_body`
// and `render::derive::derive_render_state`. `cli`/`commands`/`timer`/`tray`
// stay private — nothing outside this crate needs them.
pub mod model;
pub mod render;
mod timer;
mod tray;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    use tauri::Manager as _;

    tauri::Builder::default()
        // Must be registered first: a second launch hands its args to the
        // running instance and exits rather than starting a competing tray
        // process (invariant #2 — single process, no daemon, no second copy).
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            // A second launch was attempted; surface the existing popover
            // instead of doing nothing silently. T7 replaces this no-op with
            // "show the popover" once the window-show helper exists.
            let _ = app;
        }))
        .invoke_handler(tauri::generate_handler![
            commands::get_state,
            commands::refresh_now,
            commands::hide_popover
        ])
        .setup(|app| {
            // macOS: menu-bar app, no Dock icon, no Cmd-Tab entry. Must be set
            // on the running app *after* the event loop starts spinning up
            // windows, which is why this lives in `.setup()` rather than
            // config (ActivationPolicy has no tauri.conf.json equivalent).
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            // The single source of truth for "what does the tray currently
            // show" (T5) — managed once, here, before the tray is built or
            // the timer starts, so both always find it via `app.state()`.
            // Starts in the honest bootstrap holding state (never Healthy);
            // the timer's immediate first poll replaces it with a real
            // verdict.
            let initial = commands::initial_render_state();
            app.manage(commands::DoctorState::new(initial.clone()));

            // D2 (T9 follow-up): the tray click-toggle / Esc-and-blur
            // `hide_popover` race guard (see `tray::AutoHideGuard`) — managed
            // once, here, alongside `DoctorState`, before the tray is built.
            app.manage(tray::AutoHideGuard::new());

            // T6: the real aviator template-mask glyph + per-state badge
            // compositing, rendered from the bootstrap state above.
            tray::build(app.handle(), &initial)?;

            // T5: starts the doctor poll loop — a Tokio task inside THIS
            // process (invariant #2), immediate poll then ~1h cadence.
            timer::start(app.handle().clone());

            // T8/T9 test hook, opt-in only: normally the popover only opens
            // via a tray left-click (`tray::toggle_popover`), which manual
            // QA/E2E automation has no coordinate-free way to trigger. Set
            // `CT_SHOW_POPOVER_ON_LAUNCH` (any value) to show+focus it
            // immediately instead — same `get_state`/`state-changed` IPC
            // seam either way, this only skips the click. Unset by default,
            // so normal launches are unaffected.
            if std::env::var_os("CT_SHOW_POPOVER_ON_LAUNCH").is_some() {
                if let Some(window) = app.get_webview_window("popover") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
