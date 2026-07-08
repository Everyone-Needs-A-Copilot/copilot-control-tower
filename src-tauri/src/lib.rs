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
//! - `commands` — T5/T8/D2/M2-S6: the `get_state`/`refresh_now`/
//!   `hide_popover` Tauri commands + `state-changed` event (the doctor
//!   seam), plus `get_settings`/`save_settings`/`open_settings_window` (the
//!   Settings seam) and `check_for_update`/`apply_update` (M4/S5, thin
//!   `spawn_blocking` wrappers over `updater::check`) — the whole
//!   Rust<->web-UI IPC surface lives here.
//! - `settings` — M2: the layer-manifest model + validator + never-destroy
//!   writer + secret/security guard + authoring policy + managed gate
//!   (`copilot.layers.yml`) — everything `commands::get_settings`/
//!   `save_settings` wire together (see that module's doc for the full S1-S5
//!   split).
//! - `wizard` — M3: the first-run wizard's pure phase/transition state
//!   machine + IPC DTOs (S1), first-run persistence (S2), the sign-in
//!   device-flow seam (S3), and the managed-silent (S4) / unmanaged-guided
//!   (S5) orchestration flows (`.copilot/wp/15.md`). The IPC commands +
//!   window that wire it all together (S6) live in `commands.rs` alongside
//!   the M1/M2 surface, and are registered/managed below.
//! - `deprovision` — M5/S2: the `cc deprovision <org> --json` DTO + render
//!   (parse-not-compute — see that module's own doc). No wipe/retain logic
//!   anywhere in it; the CLI performs the deprovision, this module only
//!   asks what happened and renders it honestly (never-destroy
//!   `retained_dirty`, the `secrets_touched` alarm). Its trigger/routing
//!   caller is `routing::deprovision_trigger` (M5/S6, below) — still no
//!   Tauri command or any Bob-facing affordance anywhere in the chain
//!   (invariant #5).
//! - `managed` — M5/S1: the SOLE `CFPreferences` forced-domain FFI boundary
//!   (`managed::forced`) + the frozen managed-key registry (`managed::keys`)
//!   — see that module's own doc. `settings::managed`/`updater::trust`
//!   delegate their forced-domain reads here rather than each carrying an
//!   independent FFI call.
//! - `routing` — M5/S6 + M6/S2-S6: route-by-competence (invariant #5,
//!   architecture.md §9). `Actor`/`ItSignal`/`route_credential_state` (auth
//!   `expired` -> Bob's own re-auth, `revoked` -> a content-free IT offer)
//!   plus `deprovision_trigger` (the forced `Deprovisioned` key ->
//!   `deprovision::run_deprovision` -> an IT-routed render); M6 extends this
//!   into the full router (`event`/`policy`/`emit`) and `wire` (M6/S6, task
//!   57) — the live-flow integration glue `timer::poll_once` and
//!   `render::bob_lane`/`commands::check_for_update` call. The module itself
//!   still touches no Tauri primitive directly — see its own doc and
//!   `tests/fitness_m5_deprovision_is_it_routed.rs` (FF-M5-3), which also
//!   keeps `commands.rs`/`tray.rs`/this file's own handler-list free of a
//!   direct `routing::` reference (`render::bob_lane`/`render::
//!   security_banner` are the seam the Bob-facing IPC surface crosses
//!   through instead — see those modules' own docs).
//!
//! Nothing in this file computes ecosystem state. If a change here starts
//! looking like resolution/sync/signature/merge/health-scoring logic, it
//! belongs in the `copilot`/`cc` CLI instead (invariant #1).

// M7/S6-S7 (`.copilot/wp/43.md`, tasks 65/66): the Admin-mode `ecosystem.yml`
// seed generator (`admin::seed`) + the on-demand red/green preflight
// (`admin::preflight`) — see that module's own doc for the full SOUL/gap
// framing. `pub` — reached from `tests/` fixture-drift/fitness files and
// `examples/gen_seed_fixture.rs`, separate crates/binaries linked against
// `copilot_control_tower_lib`, matching `mobileconfig`'s own precedent. No
// Tauri command wired to it yet (Admin-mode's own IPC surface is a later,
// unscheduled stream) — this task's scope is the generator + preflight pure
// functions only.
pub mod admin;
// T5 (`timer::poll_once`) is the real call site for `cli::run_doctor` — see
// `timer.rs`.
mod cli;
mod commands;
// M5/S2 (`.copilot/wp/30.md`): the deprovision DTO + render (parse-not-
// compute) — `cc deprovision <org> --json` spawn + fail-closed parse +
// honest render (never-destroy `retained_dirty`, the `secrets_touched`
// alarm). No Tauri command wired to it yet (route-by-competence, invariant
// #5): the IT/managed trigger surface is a later stream (S6), not this one.
// `pub` for the same reason `model`/`render`/`settings` are — reached from
// `tests/fitness_m5_no_wipe_logic.rs`, a separate crate linked against
// `copilot_control_tower_lib`.
pub mod deprovision;
// M5/S1 (`.copilot/wp/30.md`): the sole `CFPreferences` forced-domain FFI
// boundary + frozen managed-key registry. `pub` — reached from
// `tests/fitness_m5_single_forced_boundary.rs`, a separate crate linked
// against `copilot_control_tower_lib`.
pub mod managed;
// M5/S3 (`.copilot/wp/30.md`, ADR-M5-004): the managed login-item —
// `SMAppService` launch-at-login + the `LoginItemManaged` forced-domain
// enablement decision, DISTINCT from the M4 crash-only `launchd` watchdog
// (`updater::watchdog`) — see `loginitem`'s own module doc for the full
// delineation. `pub` — reached from
// `tests/fitness_m5_loginitem_not_watchdog.rs`, a separate crate linked
// against `copilot_control_tower_lib`. Not yet wired to a Tauri
// command/uninstaller call site (that wiring is a later stream, matching
// `deprovision`'s own "not yet wired" precedent above).
pub mod loginitem;
// M5/S4 (`.copilot/wp/30.md`): the Admin-mode `.mobileconfig` generator —
// PURE Rust, iterates `managed::keys::MANAGED_KEYS` (never a second
// hand-maintained key list), asserts its own emitted domain equals
// `managed::keys::APPLICATION_ID` (FF-M5-6, closes G-M5-1), and never emits
// a secret value (FF-M5-7). `pub` — reached from
// `tests/fitness_m5_generator_domain_and_no_secrets.rs` and
// `examples/gen_mobileconfig_fixture.rs`, both separate crates/binaries
// linked against `copilot_control_tower_lib`. No real MDM upload (owner-
// gated) — see `mobileconfig`'s own module doc.
pub mod mobileconfig;
// `pub` (T3): `model`/`render`/`settings` are reached from `tests/` and
// `examples/gen_dev_fixtures.rs` (separate crates linked against
// `copilot_control_tower_lib`), which need `model::state::parse_doctor_body`,
// `render::derive::derive_render_state`, and (from M2 on) the settings
// model/validator/DTOs. `cli`/`commands`/`timer`/`tray` stay private —
// nothing outside this crate needs them.
pub mod model;
// M9/Stream-B (`.copilot/wp/52.md`, task 71, ADR-M9-001): the light
// platform-abstraction module — traits only where a mock is genuinely
// needed (forced-config, login-item, watchdog-signal, secret-store), cfg
// pub-use aliasing elsewhere (tray art, CLI path). The macOS impl
// (`platform::macos`) is a THIN wrapper delegating to the already-existing
// `managed::forced`/`loginitem::smappservice`/`updater::watchdog`/
// `render::glyph`/`cli::path` — a pure refactor, no logic moved, every one
// of those modules' own public API and tests are unchanged. Pre-creates
// every Windows shared surface (`platform::windows`, `Cargo.toml`'s
// `cfg(windows)` dependency block) so the six parallel Windows streams
// (C-H) each fill in exactly one stub file without colliding on this
// foundation. `pub` — reached from
// `tests/fitness_m9_platform_windows_cfg_gated.rs`, a separate crate linked
// against `copilot_control_tower_lib`.
pub mod platform;
pub mod render;
// M5/S6 (`.copilot/wp/30.md`, task 49): route-by-competence — the forced
// `Deprovisioned` trigger + the auth-revoked -> IT-routed offer. `pub` —
// reached from `tests/fitness_m5_deprovision_is_it_routed.rs`, a separate
// crate linked against `copilot_control_tower_lib`. Not wired to any Tauri
// command (invariant #5 — see `routing`'s own module doc).
pub mod routing;
pub mod settings;
// M7/S1 (`.copilot/wp/43.md`, task 60): the isolated telemetry stream's
// content-free `FleetEvent` wire type (`telemetry::schema`) — see that
// module's own doc for scope (schema only; the opt-in gate, the real
// emitter, and the fleet dashboard are separate, later streams). `pub` —
// reached from `tests/fitness_m7_telemetry_schema_content_free.rs`, a
// separate crate linked against `copilot_control_tower_lib`.
pub mod telemetry;
mod timer;
mod tray;
// M4 Stream-D (S6) + gap-closure (S11): staged-bundle layout + promote/
// rollback decision, trust/verify/heartbeat, and (S11) the wiring that
// actually puts that machinery on the live path — the `--self-test` process
// entrypoint (`updater::selftest`, called from `main.rs`), the synchronous
// self-test `apply_update` now runs (`updater::check::
// confirm_staged_bundle_boots`), and the crash-only startup reconciliation
// below (`updater::startup`) — see `updater/mod.rs`.
pub mod updater;
pub mod wizard;

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
            commands::hide_popover,
            commands::get_settings,
            commands::save_settings,
            commands::open_settings_window,
            commands::get_wizard_state,
            commands::get_wizard_product_catalog,
            commands::is_first_run,
            commands::wizard_advance,
            commands::wizard_choose_products,
            commands::wizard_set_layers,
            commands::wizard_begin_signin,
            commands::wizard_poll_signin,
            commands::open_wizard_window,
            commands::check_for_update,
            commands::apply_update,
            commands::get_bob_lane,
            commands::get_security_banner,
            render::fleet::get_fleet
        ])
        .setup(|app| {
            // ADR-M4-001 (QA gap-closure D1): the app-level launch-failure
            // circuit breaker — see `updater::circuit_breaker`'s own doc.
            // Runs as the VERY FIRST thing in `.setup()`, before even the
            // interrupted-update reconciliation below, because this guards
            // against the CURRENT/promoted build itself crash-looping for
            // ANY reason — the normal startup path (tray build, doctor
            // timer, wizard, that reconciliation) is exactly the code that
            // could be the thing crashing, so none of it may run before
            // this check has had a chance to say "stop". Fail-closed by
            // construction: an ambiguous marker trips the breaker rather
            // than guessing a fresh start (see that module's doc).
            if crate::updater::circuit_breaker::record_launch_attempt()
                == crate::updater::circuit_breaker::LaunchDecision::CircuitOpen
            {
                // Enter the honest degraded state instead of the normal
                // (possibly crash-causing) startup path: still `.manage()`
                // `DoctorState` (so `get_state`/a stray popover load never
                // panics on unmanaged state) and still build a tray — never
                // a false Healthy, the tray icon still cannot lie — but skip
                // the doctor timer, the wizard, and the interrupted-update
                // reconciliation, since restarting that machinery is exactly
                // the risk this breaker exists to stop taking.
                let degraded = commands::circuit_breaker_render_state();
                app.manage(commands::DoctorState::new(degraded.clone()));
                app.manage(tray::AutoHideGuard::new());
                tray::build(app.handle(), &degraded)?;
                return Ok(());
            }

            // M4 gap-closure (S11): a crash-only, idempotent check for a
            // PRIOR launch's interrupted (never self-tested) staged update —
            // see `updater::startup`'s own doc. Runs first, before anything
            // else in setup touches tray/doctor state, so a leftover
            // `staged/` from a killed/crashed previous launch is never left
            // ambiguous. This is NOT the `--self-test` entrypoint itself
            // (that's `main.rs`, which exits before `run()` is ever called)
            // and does not start a second process (invariant #2).
            crate::updater::startup::reconcile_interrupted_update();

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

            // M6/S6 (task 57, `.copilot/wp/37.md`): the router's own managed
            // state — the shared content-free IT-signal sink (`routing::
            // emit::LocalSink`, M6/S3) every wiring call dispatches through,
            // plus the Bob-lane/security-banner aggregations
            // `commands::get_bob_lane`/`get_security_banner` read from and
            // `timer::poll_once`/`commands::check_for_update` write to.
            // Managed once, here, alongside `DoctorState` (invariant #2).
            app.manage(routing::emit::LocalSink::new());
            app.manage(render::bob_lane::BobLaneState::new());
            app.manage(render::security_banner::SecurityBannerState::new());

            // M7/S9 (`.copilot/wp/43.md`, task 68): the telemetry emitter's
            // own managed state — the additional, opt-in-gated remote sink
            // `timer::poll_once` dispatches every doctor poll's content-free
            // `FleetEvent`s through, alongside (never instead of) the
            // `LocalSink` above. `TelemetryState::production()` ships the
            // real transport SEAM behind a `MockTransport` (the real HTTP
            // transport to an org's own collector endpoint is owner-gated,
            // G-M7-3 — see `telemetry::emitter`'s own doc) — reaching it at
            // all still requires the forced/managed opt-in carrier to
            // resolve `Enabled`, which no dev/default install ever does.
            app.manage(telemetry::emitter::TelemetryState::production());

            // D2 (T9 follow-up): the tray click-toggle / Esc-and-blur
            // `hide_popover` race guard (see `tray::AutoHideGuard`) — managed
            // once, here, alongside `DoctorState`, before the tray is built.
            app.manage(tray::AutoHideGuard::new());

            // M3/S6: the wizard's own orchestration state — managed once,
            // here, alongside `DoctorState` (invariant #2's "exactly one
            // instance of state" discipline applies here too). Decides
            // managed-vs-unmanaged immediately (a cheap, synchronous
            // `settings::managed::is_managed()` check — see
            // `commands::WizardIpcState::new`'s own doc), but runs neither
            // flow until the wizard window's first `wizard_advance` call.
            app.manage(commands::WizardIpcState::new());

            // T6: the real aviator template-mask glyph + per-state badge
            // compositing, rendered from the bootstrap state above.
            tray::build(app.handle(), &initial)?;

            // T5: starts the doctor poll loop — a Tokio task inside THIS
            // process (invariant #2), immediate poll then ~1h cadence.
            timer::start(app.handle().clone());

            // ADR-M4-001 (QA gap-closure D1): once this launch stays up past
            // `circuit_breaker::HEALTHY_UPTIME`, it has proven itself clean —
            // reset the crash-loop counter the check above just incremented.
            // Only reached on the non-circuit-open path (the branch above
            // returns early), matching that module's "call once, on the
            // normal startup path" contract.
            crate::updater::circuit_breaker::schedule_clean_run_after_healthy_uptime();

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

            // M3/S6: the wizard window switches the app to `Regular`
            // activation policy while open (`commands::open_wizard_window`)
            // — a first-run setup wizard is a foreground task, unlike the
            // Accessory-only tray/popover. Flip back to `Accessory` the
            // moment it closes, here (registered once, at setup) rather than
            // scattered across every place the window might close
            // (B-L1/C5). Defensive no-op if the window is somehow absent.
            if let Some(wizard_window) = app.get_webview_window("wizard") {
                let app_handle = app.handle().clone();
                wizard_window.on_window_event(move |event| {
                    if matches!(
                        event,
                        tauri::WindowEvent::CloseRequested { .. } | tauri::WindowEvent::Destroyed
                    ) {
                        #[cfg(target_os = "macos")]
                        let _ =
                            app_handle.set_activation_policy(tauri::ActivationPolicy::Accessory);
                    }
                });
            }

            // First-run gating (S6): auto-open the wizard on launch only
            // when the first run has genuinely never reached `Done`
            // (`wizard::persistence::is_first_run`, S2 — honest-degrade:
            // treats an unreadable CLI as "still first run", never as
            // "already set up"). Mirrors the `CT_SHOW_POPOVER_ON_LAUNCH` test
            // hook's show+focus shape, but driven by real persisted state
            // instead of an env var.
            if crate::wizard::persistence::is_first_run() {
                commands::open_wizard_window(app.handle().clone());
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
