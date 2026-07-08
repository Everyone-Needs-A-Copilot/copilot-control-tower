//! M9/Stream-C (task 72, ADR-M9-002) fitness function — Windows parity to
//! the macOS `fitness_watchdog_plist.rs`'s FF-M4-1 ("`KeepAlive` is never
//! `true`") check.
//!
//! **The invariant:** the Windows crash-only watchdog restarts the app
//! ONLY on a failure exit, with an explicit retry cap
//! (`<RestartOnFailure>`), gated on the app's own exit code — never via a
//! periodic "repeat task every N minutes" trigger (`<TimeTrigger>`,
//! `<CalendarTrigger>`, or any `<Repetition>` block), which would be the
//! Task-Scheduler-shaped equivalent of the banned `KeepAlive=true`: it
//! would resurrect the app after an intentional Quit and crash-loop a bad
//! build.
//!
//! This is a text-level source scan against the checked-in XML template
//! (`packaging/taskscheduler/controltower-watchdog.xml`) AND the Rust file
//! that consumes it (`src/platform/windows/watchdog.rs`) — not a live
//! `schtasks /Create`/Task Scheduler round trip (no Windows toolchain, no
//! `schtasks.exe`, on this machine — same constraint
//! `platform::windows::schtasks`'s own module doc names). Same cheap,
//! dependency-free text-scan style every other fitness test in this crate
//! already uses (`fitness_watchdog_plist.rs`,
//! `fitness_m9_platform_windows_cfg_gated.rs`).

use std::fs;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    // CARGO_MANIFEST_DIR is `<repo>/src-tauri`; the packaging tree and this
    // stream's own Rust file both live outside it.
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("src-tauri has a parent (repo root)")
        .to_path_buf()
}

fn watchdog_task_xml() -> PathBuf {
    repo_root()
        .join("packaging")
        .join("taskscheduler")
        .join("controltower-watchdog.xml")
}

fn watchdog_rs() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("platform")
        .join("windows")
        .join("watchdog.rs")
}

const FORBIDDEN_PERIODIC_TRIGGER_CONSTRUCTS: &[&str] =
    &["<TimeTrigger>", "<CalendarTrigger>", "<Repetition>"];

/// Strips `<!-- ... -->` blocks (this file's own doc comments legitimately
/// NAME the forbidden constructs in prose, to explain why they're banned —
/// e.g. the file-level comment says "A `<TimeTrigger>`... is BANNED". A
/// blind text scan would flag that explanation as a violation of itself.
/// This mirrors `fitness_watchdog_plist.rs`'s
/// `no_bypass_flags_anywhere_in_owned_distribution_source_fitness_ff_m4_2`
/// skipping ITS OWN file for the identical reason — the scan must exempt
/// prose that documents the ban, not just the ban itself.
fn strip_xml_comments(xml: &str) -> String {
    let mut out = String::with_capacity(xml.len());
    let mut rest = xml;
    while let Some(start) = rest.find("<!--") {
        out.push_str(&rest[..start]);
        match rest[start..].find("-->") {
            Some(end) => rest = &rest[start + end + "-->".len()..],
            None => {
                rest = "";
                break;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Strips `//`-prefixed line comments (this crate's own `.rs` doc comments
/// legitimately name the forbidden constructs in prose — see
/// [`strip_xml_comments`]'s doc for why that must not itself trip the scan).
/// Line-based and deliberately simple: this crate has no `//` inside a
/// string literal anywhere in `watchdog.rs`'s actual code that would make a
/// naive strip unsafe (confirmed by reading the file).
fn strip_rust_line_comments(src: &str) -> String {
    src.lines()
        .map(|line| match line.find("//") {
            Some(idx) => &line[..idx],
            None => line,
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// Drops everything from the `#[cfg(test)] mod tests { ... }` block onward.
/// `watchdog.rs`'s own in-file unit tests (mirroring
/// `platform::macos::watchdog`'s test-module convention) deliberately
/// contain the literal strings `"<TimeTrigger>"`/`"<CalendarTrigger>"`/
/// `"<Repetition>"` as Rust STRING LITERALS — asserting those constructs are
/// ABSENT from the rendered XML, a legitimate, redundant in-module check,
/// not a comment. A comment-only strip can't distinguish that from a real
/// construction site; scoping the scan to production code only (everything
/// before the test module, which every fitness-test-relevant file in this
/// crate places last) sidesteps the ambiguity entirely.
fn production_code_only(src: &str) -> &str {
    match src.find("#[cfg(test)]") {
        Some(idx) => &src[..idx],
        None => src,
    }
}

#[test]
fn the_checked_in_task_xml_template_never_contains_a_periodic_repeat_trigger() {
    let path = watchdog_task_xml();
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let xml = strip_xml_comments(&raw);

    for forbidden in FORBIDDEN_PERIODIC_TRIGGER_CONSTRUCTS {
        assert!(
            !xml.contains(forbidden),
            "{}: contains {forbidden} (outside of a comment) — this IS the \
             forbidden resurrect-always anti-pattern (ADR-M9-002): a \
             periodic trigger restarts the app on a fixed cadence \
             regardless of exit code, exactly like a banned bare \
             `KeepAlive=true` would on macOS",
            path.display()
        );
    }
}

#[test]
fn the_checked_in_task_xml_template_uses_only_a_logon_trigger_plus_restart_on_failure() {
    let path = watchdog_task_xml();
    let xml = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));

    assert!(
        xml.contains("<LogonTrigger>"),
        "{}: expected a <LogonTrigger> (the one-shot-per-logon start trigger)",
        path.display()
    );
    assert!(
        xml.contains("<RestartOnFailure>"),
        "{}: expected a <RestartOnFailure> settings block — the crash-only \
         restart mechanism this whole task exists for",
        path.display()
    );
    // RestartOnFailure must actually carry both a retry cap AND an
    // interval — a block with neither would be meaningless, and a block
    // with only one is not the shape ADR-M9-002 asks for ("an explicit
    // retry CAP").
    assert!(
        xml.contains("<Count>") && xml.contains("<Interval>"),
        "{}: <RestartOnFailure> must specify both <Count> (the retry cap) \
         and <Interval> (the backoff) — found neither/only one",
        path.display()
    );
}

#[test]
fn the_watchdog_rs_source_never_constructs_a_periodic_repeat_trigger_inline() {
    // Belt-and-suspenders: even if a future edit stopped using the checked-in
    // XML template and started building task XML inline in Rust, it must
    // still never introduce one of the forbidden constructs.
    let path = watchdog_rs();
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let src = strip_rust_line_comments(production_code_only(&raw));

    for forbidden in FORBIDDEN_PERIODIC_TRIGGER_CONSTRUCTS {
        assert!(
            !src.contains(forbidden),
            "{}: contains {forbidden} (outside of a comment) — the Windows \
             watchdog Rust source must never construct a periodic-repeat \
             trigger (ADR-M9-002)",
            path.display()
        );
    }
    // Also guard the `schtasks /SC <frequency>` shape some Task Scheduler
    // CLI examples use for a periodic schedule (this crate's own
    // `schtasks.rs` helper never takes a `/SC` flag today — this assertion
    // is a regression guard against that changing silently in this file).
    for schedule_flag in ["/SC MINUTE", "/SC HOURLY", "/SC DAILY", "/SC WEEKLY"] {
        assert!(
            !src.contains(schedule_flag),
            "{}: contains {schedule_flag:?} — a `/SC` periodic-schedule flag \
             is the forbidden resurrect-always anti-pattern (ADR-M9-002)",
            path.display()
        );
    }
}

#[test]
fn the_watchdog_rs_source_consumes_the_shared_schtasks_helper_never_reinventing_it() {
    // ADR-M9-001/schtasks.rs's own doc: Stream-C consumes
    // `super::schtasks::{create_task_from_xml, delete_task,
    // query_task_exists}` READ-ONLY rather than shelling out to
    // `schtasks.exe` itself a second, independently-drifting way.
    let path = watchdog_rs();
    let src = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));

    assert!(
        src.contains("super::schtasks::create_task_from_xml"),
        "{}: expected install() to call super::schtasks::create_task_from_xml",
        path.display()
    );
    assert!(
        src.contains("super::schtasks::delete_task"),
        "{}: expected uninstall() to call super::schtasks::delete_task",
        path.display()
    );
    assert!(
        !src.contains("Command::new(\"schtasks\")"),
        "{}: must not shell out to schtasks.exe directly — that duplicates \
         the shared platform::windows::schtasks helper, which this stream \
         must consume read-only, not reinvent",
        path.display()
    );
}

#[test]
fn the_watchdog_rs_source_carries_its_own_cfg_windows_gate() {
    // Belt-and-suspenders with `fitness_m9_platform_windows_cfg_gated.rs`'s
    // crate-wide sweep — re-asserted narrowly here so this specific
    // fitness test file stands alone as evidence for task 72's own file.
    let path = watchdog_rs();
    let src = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    assert!(
        src.contains("#![cfg(windows)]"),
        "{}: expected a `#![cfg(windows)]` inner attribute",
        path.display()
    );
}
