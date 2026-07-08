//! **FF-M5-4.** The managed login-item (M5/S3, `.copilot/wp/30.md`
//! ADR-M5-004) module never emits `KeepAlive`/watchdog-plist content and
//! never spawns a second resident process. Same cheap, dependency-free
//! text-scan style every other fitness test in this crate already uses
//! (see `fitness_m5_single_forced_boundary.rs`,
//! `fitness_single_process_ff_m4_7.rs`) — no call-graph analysis, no real
//! `SMAppService`.
//!
//! Two distinct claims, both asserted here:
//!
//! 1. **Never emits watchdog-plist content.** `KeepAlive`/`ThrottleInterval`/
//!    `SuccessfulExit` (the `launchd` `KeepAlive` dict's own key names) never
//!    appear anywhere under `src/loginitem/` — that vocabulary belongs
//!    exclusively to `updater::watchdog`/`packaging/launchd/*.plist`
//!    (ADR-M5-004's delineation).
//! 2. **Never spawns a second resident process.** No process-spawning API
//!    (`std::process::Command`, `Command::new`) appears anywhere under
//!    `src/loginitem/` — `SMAppService.register()` only asks the OS to
//!    remember "launch this bundle at next login"; this module itself never
//!    forks/execs anything (invariant #2: one signed binary, no daemon).

use std::fs;
use std::path::{Path, PathBuf};

fn loginitem_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("loginitem")
}

fn collect_rs_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display())) {
        let path = entry.expect("dir entry").path();
        if path.is_dir() {
            collect_rs_files(&path, out);
        } else if path.extension().and_then(|e| e.to_str()) == Some("rs") {
            out.push(path);
        }
    }
}

/// Strips `//...` line comments and `/* ... */` block comments — same
/// approach every other fitness test in this crate already uses, so this
/// test never trips on the ADR-M5-004 doc comment itself naming
/// `KeepAlive`/`launchd` in prose (it deliberately discusses the watchdog to
/// explain the delineation, which is not a violation).
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

fn relative(path: &Path) -> String {
    path.strip_prefix(Path::new(env!("CARGO_MANIFEST_DIR")).join("src"))
        .unwrap_or(path)
        .display()
        .to_string()
}

#[test]
fn loginitem_module_never_emits_watchdog_plist_vocabulary_fitness_ff_m5_4() {
    let mut files = Vec::new();
    collect_rs_files(&loginitem_dir(), &mut files);
    assert!(
        !files.is_empty(),
        "expected to find .rs files under src/loginitem/"
    );

    let watchdog_only_needles = ["KeepAlive", "ThrottleInterval", "SuccessfulExit"];
    let mut offenders: Vec<(String, &str)> = Vec::new();

    for file in &files {
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        let stripped = strip_comments(&raw);
        for needle in watchdog_only_needles {
            if stripped.contains(needle) {
                offenders.push((relative(file), needle));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "the login-item module must never emit/reference watchdog-plist vocabulary \
         (ADR-M5-004's delineation — that stays `updater::watchdog`'s job): {offenders:?}"
    );
}

#[test]
fn loginitem_module_never_spawns_a_second_resident_process_fitness_ff_m5_4() {
    let mut files = Vec::new();
    collect_rs_files(&loginitem_dir(), &mut files);
    assert!(
        !files.is_empty(),
        "expected to find .rs files under src/loginitem/"
    );

    let process_spawn_needles = ["std::process::Command", "Command::new", "process::Command"];
    let mut offenders: Vec<(String, &str)> = Vec::new();

    for file in &files {
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        let stripped = strip_comments(&raw);
        for needle in process_spawn_needles {
            if stripped.contains(needle) {
                offenders.push((relative(file), needle));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "the login-item module must never spawn a process directly — `SMAppService.register()` \
         only asks the OS to remember 'launch this bundle at next login', it does not fork/exec \
         anything itself (invariant #2: one signed binary, no second resident process). Found: \
         {offenders:?}"
    );
}

/// The watchdog plist itself must never claim to be a login-item mechanism —
/// belt-and-suspenders on the same ADR-M5-004 delineation from the other
/// direction (`fitness_watchdog_plist.rs` already asserts `RunAtLoad=false`
/// for the identical reason; this test asserts the plist's own comment still
/// names `SMAppService` as owning login-launch, so the two files can never
/// silently drift apart on which mechanism owns which concern).
#[test]
fn watchdog_plist_still_defers_login_launch_to_smappservice() {
    let repo_root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("src-tauri has a parent (repo root)");
    let plist_dir = repo_root.join("packaging").join("launchd");
    let mut found_reference = false;
    for entry in
        fs::read_dir(&plist_dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", plist_dir.display()))
    {
        let path = entry.expect("dir entry").path();
        if path.extension().and_then(|e| e.to_str()) != Some("plist") {
            continue;
        }
        let xml =
            fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        if xml.contains("SMAppService") {
            found_reference = true;
        }
    }
    assert!(
        found_reference,
        "expected at least one watchdog plist under packaging/launchd/ to document that \
         login-launch is SMAppService's job, not this LaunchAgent's"
    );
}
