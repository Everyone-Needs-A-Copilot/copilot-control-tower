//! ADR-M4-001 — the app-level launch-failure circuit breaker (QA gap-closure
//! D1, `scratchpad/qa-m4-acceptance.md`).
//!
//! `updater::circuit_breaker`'s own unit tests (`src/updater/
//! circuit_breaker.rs`) prove the counting/threshold/window/fail-closed
//! MECHANISM is correct in isolation. They do NOT prove it is actually
//! reachable from a real launch — the QA report's own words describe
//! exactly this failure mode for the sibling self-update machinery before
//! S11 wired it up: "fully built... but never wired into the live
//! `main.rs`/`lib.rs`... path" (`updater/mod.rs`'s "Gap-closure note").
//! This file is the anti-orphan guard so the circuit breaker can't quietly
//! become dead code the same way.
//!
//! Same cheap, dependency-free text-scan style every other fitness test in
//! this crate already uses — no live Tauri app, no real launch.

use std::fs;
use std::path::{Path, PathBuf};

fn src_tauri_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf()
}

fn read(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

fn strip_comments(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let bytes = src.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'/') {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
        } else if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'*') {
            i += 2;
            while i < bytes.len() && !(bytes[i] == b'*' && bytes.get(i + 1) == Some(&b'/')) {
                i += 1;
            }
            i += 2;
        } else {
            out.push(bytes[i] as char);
            i += 1;
        }
    }
    out
}

fn lib_rs_production_source() -> String {
    let raw = read(&src_tauri_root().join("src").join("lib.rs"));
    strip_comments(&raw)
}

/// `lib.rs::run()`'s `.setup()` must call
/// `updater::circuit_breaker::record_launch_attempt()` and branch on its
/// result — the ADR's whole point is that this decision gates EVERYTHING
/// else `.setup()` does, so a caller that merely calls the function without
/// ever reading its return value would not actually be guarded by it.
#[test]
fn setup_calls_record_launch_attempt_and_branches_on_its_result() {
    let production = lib_rs_production_source();

    assert!(
        production.contains("updater::circuit_breaker::record_launch_attempt()"),
        "lib.rs::run()'s .setup() must call \
         updater::circuit_breaker::record_launch_attempt() — otherwise ADR-M4-001's circuit \
         breaker exists only as unreachable code, exactly the gap this crate's own \
         updater/mod.rs doc warns the self-update machinery once fell into"
    );
    assert!(
        production.contains("LaunchDecision::CircuitOpen"),
        "the call site must branch on LaunchDecision::CircuitOpen — calling \
         record_launch_attempt() without ever reading its result would silently increment the \
         counter forever without the breaker ever actually being able to open"
    );
}

/// The circuit-breaker check must run BEFORE every other piece of normal
/// startup machinery it is meant to gate: the interrupted-update
/// reconciliation, the tray build, and the doctor timer. If any of those
/// could run first, a crash inside THEM would never even reach the breaker
/// check on a subsequent relaunch's earlier code path — the whole point is
/// that this is the FIRST thing `.setup()` does.
#[test]
fn the_circuit_breaker_check_runs_before_reconciliation_tray_and_timer() {
    let production = lib_rs_production_source();

    let setup_idx = production
        .find(".setup(|app| {")
        .expect("lib.rs must define a .setup(|app| { ... }) closure");
    let breaker_idx = production[setup_idx..]
        .find("updater::circuit_breaker::record_launch_attempt()")
        .map(|i| i + setup_idx)
        .expect("record_launch_attempt() must be called inside .setup()");
    let reconcile_idx = production[setup_idx..]
        .find("updater::startup::reconcile_interrupted_update()")
        .map(|i| i + setup_idx)
        .expect("reconcile_interrupted_update() must still be called inside .setup()");
    let tray_build_idx = production[setup_idx..]
        .find("tray::build(app.handle()")
        .map(|i| i + setup_idx)
        .expect("tray::build(...) must still be called inside .setup()");
    let timer_start_idx = production[setup_idx..]
        .find("timer::start(app.handle()")
        .map(|i| i + setup_idx)
        .expect("timer::start(...) must still be called inside .setup()");

    assert!(
        breaker_idx < reconcile_idx,
        "the circuit-breaker check must textually precede the interrupted-update \
         reconciliation — a crash inside that reconciliation must itself be counted by the \
         breaker on the NEXT launch, which only holds if the breaker check runs first"
    );
    assert!(
        breaker_idx < tray_build_idx && breaker_idx < timer_start_idx,
        "the circuit-breaker check must textually precede the tray build and the doctor timer \
         start — those are exactly the kind of normal-startup machinery a crash-looping build \
         might be crashing inside of, so the breaker must have a chance to say 'stop' before \
         either ever runs"
    );
}

/// The tripped branch must actually stop short of the normal startup path
/// (an early `return Ok(())`) rather than merely logging and falling
/// through anyway — a breaker that trips but still starts the timer/wizard
/// regardless would not be "stopping relaunching" in any real sense.
#[test]
fn the_tripped_branch_returns_early_before_the_normal_startup_path() {
    let production = lib_rs_production_source();

    let breaker_idx = production
        .find("updater::circuit_breaker::record_launch_attempt()")
        .expect("record_launch_attempt() must be called in lib.rs");
    let circuit_open_idx = production[breaker_idx..]
        .find("LaunchDecision::CircuitOpen")
        .map(|i| i + breaker_idx)
        .expect("must branch on LaunchDecision::CircuitOpen");
    let early_return_idx = production[circuit_open_idx..]
        .find("return Ok(())")
        .map(|i| i + circuit_open_idx)
        .expect("the CircuitOpen branch must contain an early `return Ok(())`");
    let timer_start_idx = production
        .find("timer::start(app.handle()")
        .expect("timer::start(...) must still exist in lib.rs for the normal path");

    assert!(
        early_return_idx < timer_start_idx,
        "the circuit-open branch's early return must appear BEFORE the normal-path \
         timer::start(...) call — otherwise a tripped breaker would still fall through to the \
         exact startup machinery it exists to stop"
    );
}

/// The degraded state built on trip must still `.manage()` `DoctorState` and
/// build a tray — an honest degraded UI, never a silent process with no
/// managed state at all (which would panic any stray `get_state` IPC call
/// from an auto-loaded window) and never a state so incomplete it can't be
/// rendered.
#[test]
fn the_tripped_branch_still_manages_doctor_state_and_builds_a_tray() {
    let production = lib_rs_production_source();

    let circuit_open_idx = production
        .find("LaunchDecision::CircuitOpen")
        .expect("must branch on LaunchDecision::CircuitOpen");
    let early_return_idx = production[circuit_open_idx..]
        .find("return Ok(())")
        .map(|i| i + circuit_open_idx)
        .expect("the CircuitOpen branch must contain an early `return Ok(())`");
    let branch_body = &production[circuit_open_idx..early_return_idx];

    assert!(
        branch_body.contains("commands::circuit_breaker_render_state()"),
        "the tripped branch must build its RenderState via \
         commands::circuit_breaker_render_state() — an honest degraded state, never a fabricated \
         Healthy or an omitted/absent state"
    );
    assert!(
        branch_body.contains("DoctorState::new"),
        "the tripped branch must still .manage() a DoctorState so a stray get_state IPC call \
         (e.g. an auto-loaded popover window) never panics on unmanaged state"
    );
    assert!(
        branch_body.contains("tray::build(app.handle()"),
        "the tripped branch must still build a tray — the tray icon must never simply vanish \
         with no explanation (invariant #4: it still cannot lie, but it must still exist)"
    );
}

/// The clean-run scheduling call must exist on the NORMAL (non-circuit-open)
/// path, after the timer starts — proof this launch survives past
/// `circuit_breaker::HEALTHY_UPTIME` is what resets the counter the trip
/// check above increments; without this call the counter could only ever
/// grow, and every fleet would eventually trip regardless of health.
#[test]
fn the_normal_path_schedules_the_healthy_uptime_clean_run_reset() {
    let production = lib_rs_production_source();

    let timer_start_idx = production
        .find("timer::start(app.handle()")
        .expect("timer::start(...) must exist in lib.rs");
    assert!(
        production[timer_start_idx..]
            .contains("circuit_breaker::schedule_clean_run_after_healthy_uptime()"),
        "lib.rs must call \
         updater::circuit_breaker::schedule_clean_run_after_healthy_uptime() on the normal \
         startup path — without it, a launch that survives can never prove itself clean, and \
         the counter this crate's own circuit_breaker.rs increments on every launch would only \
         ever grow, eventually tripping every healthy fleet too"
    );
}
