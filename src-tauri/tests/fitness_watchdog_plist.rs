//! M4 Stream-D fitness functions (`.copilot/wp/24.md` "Fitness functions",
//! Case Law SOUL.md line 147/408).
//!
//! **FF-M4-1 — `KeepAlive` is never `true`.** The watchdog LaunchAgent plist
//! must declare `KeepAlive` as a dict containing exactly
//! `SuccessfulExit=false`; a bare `<true/>` (or a `RunAtLoad` that's
//! unconditionally `true`, defeating the SMAppService/watchdog split) fails
//! this test. A bare `KeepAlive=true` restarts unconditionally, resurrecting
//! the app after an intentional Quit and crash-looping a bad self-update
//! (ADR-M4-001).
//!
//! This is a text-level lint against the checked-in plist **template**
//! (`packaging/launchd/*.plist`) — not a live `launchctl`/plist-parsing
//! round trip (constraint: no `launchctl load` against the live system in
//! this session). `plutil -lint` (a real, side-effect-free command) is run
//! separately as a shell-level check; this test asserts the *semantic*
//! invariant `plutil` itself doesn't know about.

use std::fs;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    // CARGO_MANIFEST_DIR is `<repo>/src-tauri`; the packaging tree lives at
    // the repo root, one level up.
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("src-tauri has a parent (repo root)")
        .to_path_buf()
}

fn watchdog_plists() -> Vec<PathBuf> {
    let dir = repo_root().join("packaging").join("launchd");
    let mut out = Vec::new();
    for entry in fs::read_dir(&dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display())) {
        let path = entry.expect("dir entry").path();
        if path.extension().and_then(|e| e.to_str()) == Some("plist") {
            out.push(path);
        }
    }
    out
}

/// Very small hand-rolled plist-dict scan: finds the `<key>KeepAlive</key>`
/// entry and returns the raw XML value that immediately follows it (either
/// `<true/>`, `<false/>`, or a `<dict>...</dict>` block) — enough to assert
/// FF-M4-1 without pulling in a plist-parsing crate for one lint.
fn keep_alive_value(xml: &str) -> String {
    let marker = "<key>KeepAlive</key>";
    let idx = xml
        .find(marker)
        .unwrap_or_else(|| panic!("no <key>KeepAlive</key> entry found in plist"));
    let after = xml[idx + marker.len()..].trim_start();
    if after.starts_with("<dict>") {
        let end = after
            .find("</dict>")
            .expect("KeepAlive dict has a closing </dict>");
        after[..end + "</dict>".len()].to_string()
    } else if let Some(rest) = after.strip_prefix("<true/>") {
        let _ = rest;
        "<true/>".to_string()
    } else if let Some(rest) = after.strip_prefix("<false/>") {
        let _ = rest;
        "<false/>".to_string()
    } else {
        panic!("KeepAlive value is neither <dict>, <true/>, nor <false/>: {after}");
    }
}

#[test]
fn keep_alive_is_never_a_bare_true_fitness_ff_m4_1() {
    let plists = watchdog_plists();
    assert!(
        !plists.is_empty(),
        "expected at least one watchdog plist under packaging/launchd/"
    );

    for plist in &plists {
        let xml =
            fs::read_to_string(plist).unwrap_or_else(|e| panic!("read {}: {e}", plist.display()));
        let value = keep_alive_value(&xml);
        assert_ne!(
            value,
            "<true/>",
            "{}: KeepAlive is a bare <true/> — BANNED (ADR-M4-001): this \
             resurrects the app after an intentional Quit and crash-loops a \
             bad self-update. Must be a dict with SuccessfulExit=false.",
            plist.display()
        );
        assert!(
            value.starts_with("<dict>"),
            "{}: KeepAlive must be a dict, found: {value}",
            plist.display()
        );
        assert!(
            value.contains("<key>SuccessfulExit</key>") && value.contains("<false/>"),
            "{}: KeepAlive dict must contain SuccessfulExit=false, found: {value}",
            plist.display()
        );
    }
}

#[test]
fn run_at_load_is_never_true_login_launch_is_smappservices_job() {
    // Belt-and-suspenders on the same theme: this LaunchAgent is a
    // crash-only watchdog, not a login-launch mechanism (that's
    // SMAppService's job — architecture.md §3). RunAtLoad=true here would
    // mean launchd starts the app at every login in addition to
    // SMAppService, a double-launch race this repo's design explicitly
    // rejects.
    for plist in watchdog_plists() {
        let xml =
            fs::read_to_string(&plist).unwrap_or_else(|e| panic!("read {}: {e}", plist.display()));
        let marker = "<key>RunAtLoad</key>";
        let idx = xml
            .find(marker)
            .unwrap_or_else(|| panic!("{}: no RunAtLoad entry", plist.display()));
        let after = xml[idx + marker.len()..].trim_start();
        assert!(
            after.starts_with("<false/>"),
            "{}: RunAtLoad must be false (login-launch is SMAppService's job)",
            plist.display()
        );
    }
}

/// FF-M4-2 — no bypass flags. `--force`/`--skip-verify` must never appear
/// as literal, constructed arguments in the files THIS stream (Stream-D)
/// actually authored: `updater::watchdog`/`updater::mod`, and the
/// `packaging/`/`scripts/` distribution tree. Deliberately file-scoped
/// rather than directory-scoped for `src-tauri/src/updater` — that
/// directory also holds `sec`'s concurrently-landed `trust.rs`/`verify.rs`/
/// `heartbeat.rs` (this stream's constraint: consume their API, never edit
/// or gate on their file contents), and those files legitimately *document*
/// the fail-closed "never accepts `--force`/`--skip-verify`" contract by
/// naming the banned flags in prose — this test must not fail on their
/// wording. Their own verification is `sec`'s responsibility, not this
/// stream's fitness test to assert.
#[test]
fn no_bypass_flags_anywhere_in_owned_distribution_source_fitness_ff_m4_2() {
    let root = repo_root();
    let src_tauri = root.join("src-tauri").join("src").join("updater");
    let scan_files = [src_tauri.join("mod.rs"), src_tauri.join("watchdog.rs")];
    let scan_dirs = [root.join("packaging"), root.join("scripts")];

    let needles = ["--force", "--skip-verify"];
    let mut offenders: Vec<(PathBuf, &str)> = Vec::new();

    let mut files: Vec<PathBuf> = scan_files.into_iter().filter(|f| f.exists()).collect();
    for dir in &scan_dirs {
        if dir.exists() {
            collect_files(dir, &mut files);
        }
    }

    for file in files {
        // Skip this fitness test file itself — it names both flags in its
        // own doc comments/assertions.
        if file.file_name().and_then(|n| n.to_str()) == Some("fitness_watchdog_plist.rs") {
            continue;
        }
        let content = fs::read_to_string(&file).unwrap_or_default();
        for needle in needles {
            if content.contains(needle) {
                offenders.push((file.clone(), needle));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "found a banned bypass flag in Stream-D-owned distribution source (invariant #4, FF-M4-2): {offenders:?}"
    );
}

fn collect_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display())) {
        let path = entry.expect("dir entry").path();
        if path.is_dir() {
            collect_files(&path, out);
        } else {
            out.push(path);
        }
    }
}
