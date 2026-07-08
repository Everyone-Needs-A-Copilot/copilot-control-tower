//! FF-M4-7 — single process (M4 QA gap-closure, T29/S12, `.copilot/wp/24.md`).
//!
//! CLAUDE.md invariant #2: "One signed binary = tray + supervisor +
//! scheduler. No separate daemon, no in-app fallback loop... The CLI
//! self-serializes via `flock`... the app is not the lock." M4 extends this
//! to the self-update machinery specifically: `launchd` IS the watchdog (a
//! crash-only relauncher of the SAME signed binary), never a second resident
//! process; a staged bundle's `--self-test` launch is a transient,
//! write-one-heartbeat-then-exit invocation, never a second app kind that
//! keeps running.
//!
//! FF-M4-1 through FF-M4-6 each have a dedicated fitness test
//! (`fitness_watchdog_plist.rs`, `updater::trust`'s/`updater::check`'s own
//! `mod fitness`, `updater::watchdog`'s/`updater::heartbeat`'s own
//! `#[test]`s) — this file closes the one remaining gap: FF-M4-7 had no
//! CI-enforced guard of its own before this test existed (found during the
//! M4 QA acceptance pass, T29/S12; the invariant itself was already correctly
//! upheld by the landed code — this test only makes that a standing,
//! regression-proof guarantee rather than something re-verified by hand each
//! milestone).
//!
//! Same cheap, dependency-free text-scan style every other fitness test in
//! this crate already uses — no call-graph analysis, no live `launchctl`.

use std::fs;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("src-tauri has a parent (repo root)")
        .to_path_buf()
}

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

/// This crate declares exactly one binary target — no second `[[bin]]`
/// entry anywhere in `Cargo.toml` (which would be a second, independently
/// launchable process kind shipped inside the same crate). The vendored
/// `packaging/cc/cc` placeholder is a DIFFERENT product's CLI (verify-not-
/// resign, ADR-M4-005) invoked transiently as a subprocess for `doctor`/etc,
/// never a resident daemon this crate itself defines — it is correctly out
/// of scope for this check.
#[test]
fn cargo_toml_declares_exactly_one_binary_target_fitness_ff_m4_7() {
    let cargo_toml = read(&src_tauri_root().join("Cargo.toml"));
    let bin_sections = cargo_toml.matches("[[bin]]").count();
    assert_eq!(
        bin_sections, 0,
        "Cargo.toml declares an explicit [[bin]] section — this crate must ship exactly the \
         one implicit binary (main.rs); a second [[bin]] target would be a second, \
         independently-launchable process kind, violating invariant #2 (single process)"
    );
}

/// `main.rs`'s `--self-test` branch must unconditionally `std::process::exit`
/// BEFORE the fall-through call to `copilot_control_tower_lib::run()` (the
/// tray/webview/doctor-timer machinery) — structurally guaranteeing a
/// self-test invocation can never ALSO become the resident app. This is the
/// exclusivity `fitness_self_update_machinery_is_wired.rs`'s own
/// `main_rs_checks_for_the_self_test_flag_before_starting_the_normal_app`
/// does not itself pin (that test only proves each symbol is present
/// somewhere in the file, not their relative order/exclusivity).
#[test]
fn main_rs_exits_on_self_test_before_ever_reaching_the_resident_app_fitness_ff_m4_7() {
    let raw = read(&src_tauri_root().join("src").join("main.rs"));
    let production = strip_comments(&raw);

    let requested_idx = production
        .find("updater::selftest::requested")
        .expect("main.rs must check updater::selftest::requested(...)");
    let exit_idx = production
        .find("std::process::exit(copilot_control_tower_lib::updater::selftest::run())")
        .expect("main.rs must exit on the exact self-test run()'s return code");
    let run_idx = production
        .rfind("copilot_control_tower_lib::run()")
        .expect("main.rs must still fall through to the normal app for a non-self-test launch");

    assert!(
        requested_idx < exit_idx,
        "the self-test flag check must textually precede the exit call"
    );
    assert!(
        exit_idx < run_idx,
        "main.rs's self-test exit() must appear BEFORE the normal-app run() call — otherwise \
         a --self-test launch could fall through and ALSO start the tray/webview, becoming a \
         second resident instance of the app rather than a transient, exit-after-one-heartbeat \
         invocation (FF-M4-7, invariant #2)"
    );
}

/// The watchdog LaunchAgent's `ProgramArguments` must point at THIS crate's
/// own bundle binary path — proving `launchd` relaunches the SAME signed
/// binary on crash, never a distinct watchdog/daemon executable shipped
/// alongside it (which would itself be a second resident process kind).
#[test]
fn the_watchdog_plist_relaunches_the_same_app_binary_not_a_distinct_daemon_fitness_ff_m4_7() {
    let plist_path = repo_root()
        .join("packaging")
        .join("launchd")
        .join("com.everyoneneedsacopilot.controltower.plist");
    let xml = read(&plist_path);
    let cargo_toml = read(&src_tauri_root().join("Cargo.toml"));

    let package_name = cargo_toml
        .lines()
        .find_map(|l| {
            let l = l.trim();
            l.strip_prefix("name = \"")
                .and_then(|rest| rest.strip_suffix('"'))
        })
        .expect("Cargo.toml [package] name must be a plain quoted string on its own line");

    let expected = format!("Contents/MacOS/{package_name}");
    assert!(
        xml.contains(&expected),
        "the watchdog plist's ProgramArguments must relaunch \
         `{expected}` (this crate's OWN bundle binary) — found no such path in {}; a \
         mismatched/second binary here would mean launchd is supervising a DIFFERENT \
         executable than the one this crate builds, i.e. a second process kind",
        plist_path.display()
    );
}

/// Every production call site that launches a copy of this crate's own
/// binary (`updater::launch::RealBundleLauncher`) must always pass the
/// `--self-test` flag — a bare relaunch (no flag) would start a SECOND,
/// full, resident instance of the app (tray + webview + doctor timer)
/// running concurrently with the one that spawned it, rather than a
/// transient liveness probe that writes one heartbeat and exits.
#[test]
fn the_staged_bundle_launcher_only_ever_launches_a_self_test_never_a_bare_relaunch_fitness_ff_m4_7()
{
    let raw = read(
        &src_tauri_root()
            .join("src")
            .join("updater")
            .join("launch.rs"),
    );
    let production = strip_comments(&raw);
    let production = match production.find("#[cfg(test)]") {
        Some(idx) => production[..idx].to_string(),
        None => production,
    };

    assert!(
        production.contains("Command::new(&binary)"),
        "RealBundleLauncher::launch_self_test must spawn the staged binary directly"
    );
    // The spawn call and its `.arg(SELF_TEST_FLAG)` must be part of the same
    // builder chain — cheap proxy: SELF_TEST_FLAG's only production
    // reference in this file is the one `.arg(...)` call feeding the one
    // `Command::new` builder above (no second, flagless spawn site exists).
    let command_new_count = production.matches("Command::new(").count();
    let self_test_flag_arg_count = production.matches(".arg(SELF_TEST_FLAG)").count();
    assert_eq!(
        command_new_count, 1,
        "expected exactly one production Command::new(...) spawn site in launch.rs \
         (a second, unguarded spawn site would be a candidate for a bare, unflagged \
         relaunch — a second resident process)"
    );
    assert_eq!(
        self_test_flag_arg_count, 1,
        "expected the one spawn site to carry exactly one .arg(SELF_TEST_FLAG) — every \
         staged-bundle launch this crate performs must be self-test-flagged, never a bare \
         relaunch that would start a second resident app instance (FF-M4-7)"
    );
}
