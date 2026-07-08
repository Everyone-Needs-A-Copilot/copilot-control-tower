// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // M4 gap-closure (S11): a freshly-staged bundle is launched with
    // `--self-test` (`updater::heartbeat::SELF_TEST_FLAG`) to prove it boots
    // BEFORE `updater::check::apply_update`'s own self-test step ever
    // promotes it — see `updater::selftest`'s own doc. Checked FIRST, before
    // `copilot_control_tower_lib::run()` starts the tray/webview/doctor
    // timer at all: a self-test invocation is a transient, non-resident
    // process that writes one heartbeat and exits, never a second app kind
    // (invariant #2 — single process).
    let args: Vec<String> = std::env::args().collect();
    if copilot_control_tower_lib::updater::selftest::requested(&args) {
        std::process::exit(copilot_control_tower_lib::updater::selftest::run());
    }
    copilot_control_tower_lib::run()
}
