//! Anti-orphan fitness test (M4 gap-closure, S11): the crash-only
//! self-test/staged-bundle rollback machinery
//! (`updater::heartbeat::{SELF_TEST_FLAG, run_self_test}`,
//! `updater::watchdog::{decide, run_self_test}`,
//! `updater::dto::UpdateStatus::RolledBack`) was fully built by M4
//! Stream-D/S1/S2, but — until this task — nothing in `main.rs`, `lib.rs`,
//! or `updater::check::apply_update` ever actually called into it. It
//! compiled, it was unit-tested in isolation, and it was completely dead on
//! the live path.
//!
//! This test pins the wiring described in `updater/mod.rs`'s own
//! "Gap-closure note" so it can't silently regress back to dead code — a
//! text-level scan (same style `tests/fitness_watchdog_plist.rs`'s own
//! `no_bypass_flags_...` checks and `updater::check.rs`'s own `mod fitness`
//! use: cheap, dependency-free, no call-graph analysis needed).
//!
//! Every needle below is checked against PRODUCTION source only (comments
//! and `#[cfg(test)]` code stripped first, via the same `strip_comments`/
//! "cut at the first `#[cfg(test)]` marker" convention `updater::check.rs`'s
//! own `mod fitness` established) — a needle appearing only in a doc comment
//! (e.g. this very file's own module doc, or `updater/mod.rs`'s "Gap-closure
//! note", both of which legitimately name these symbols in prose) must never
//! be mistaken for real wiring.

use std::fs;
use std::path::{Path, PathBuf};

fn src_tauri_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf()
}

fn read(relative: &str) -> String {
    let path = src_tauri_root().join(relative);
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

/// Production-only source: comments stripped, then truncated at the first
/// `#[cfg(test)]` marker — see `updater::check.rs`'s own `mod fitness` for
/// the original of this exact pattern (duplicated per that module's own
/// "each fitness check owns its own copy" convention, since this is a
/// separate `tests/` crate that can't `use` a private helper from the lib).
fn production_source(raw: &str) -> String {
    let stripped = strip_comments(raw);
    match stripped.find("#[cfg(test)]") {
        Some(idx) => stripped[..idx].to_string(),
        None => stripped,
    }
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

#[test]
fn main_rs_checks_for_the_self_test_flag_before_starting_the_normal_app() {
    let main = production_source(&read("src/main.rs"));
    assert!(
        main.contains("updater::selftest::requested"),
        "main.rs no longer checks updater::selftest::requested() — the --self-test \
         entrypoint (heartbeat::SELF_TEST_FLAG/run_self_test) has regressed to dead code"
    );
    assert!(
        main.contains("updater::selftest::run()"),
        "main.rs no longer calls updater::selftest::run() when --self-test is present"
    );
    assert!(
        main.contains("copilot_control_tower_lib::run()"),
        "main.rs must still fall through to the normal app for a non-self-test launch"
    );
}

#[test]
fn lib_rs_runs_startup_reconciliation_before_the_normal_app_starts() {
    let lib = production_source(&read("src/lib.rs"));
    assert!(
        lib.contains("updater::startup::reconcile_interrupted_update"),
        "lib.rs's setup() no longer calls updater::startup::reconcile_interrupted_update() — \
         an interrupted staged update would be silently trusted on the next launch"
    );
}

#[test]
fn apply_update_actually_drives_watchdogs_run_self_test_not_just_stage_and_report_ready() {
    let check = production_source(&read("src/updater/check.rs"));
    assert!(
        check.contains("watchdog::run_self_test("),
        "updater::check.rs's production code no longer calls watchdog::run_self_test — \
         apply_update would report Ready without ever proving the staged bundle boots \
         (the exact gap this fitness test exists to catch)"
    );
    assert!(
        check.contains("UpdateStatus::RolledBack"),
        "updater::check.rs's production code never constructs UpdateStatus::RolledBack — \
         a failed self-test would have nothing honest to report"
    );
    assert!(
        check.contains("StagedBundleLauncher") && check.contains("launch_self_test"),
        "updater::check.rs no longer wires the injectable staged-bundle launcher seam"
    );
    assert!(
        check.contains("rollback_marker::take_rollback_outcome")
            && check.contains("rollback_marker::record_rollback"),
        "updater::check.rs no longer reads/writes the rollback-outcome marker — a rollback \
         would never be surfaced to a subsequent normal launch"
    );
}

#[test]
fn startup_rs_actually_drives_watchdogs_run_self_test_for_an_interrupted_update() {
    let startup = production_source(&read("src/updater/startup.rs"));
    assert!(
        startup.contains("watchdog::run_self_test("),
        "updater::startup.rs no longer reconciles an interrupted staged update via \
         watchdog::run_self_test — a leftover staged/ from a crashed launch could be \
         silently trusted on the next one"
    );
}

#[test]
fn selftest_rs_actually_drives_heartbeats_run_self_test() {
    let selftest = production_source(&read("src/updater/selftest.rs"));
    assert!(
        selftest.contains("heartbeat::run_self_test("),
        "updater::selftest.rs no longer calls heartbeat::run_self_test — the --self-test \
         protocol (write SelfTestStarted, smoke-check, write SelfTestOk) has regressed to \
         dead code"
    );
}
