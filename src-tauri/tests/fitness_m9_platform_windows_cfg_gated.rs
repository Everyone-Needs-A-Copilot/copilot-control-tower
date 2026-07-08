//! M9/Stream-B (task 71, `.copilot/wp/52.md` ADR-M9-001) — Windows code must
//! NEVER accidentally compile into a macOS build. There is no Windows
//! toolchain on this machine, so the only verification possible here is a
//! source-scan proving every `platform::windows` surface is `#[cfg(windows)]`-
//! gated, belt-and-suspenders, at BOTH the module-declaration site
//! (`platform/mod.rs`, `platform/windows/mod.rs`) and inside each individual
//! file. Same cheap, dependency-free text-scan style every other fitness
//! test in this crate already uses (see `fitness_m5_single_forced_boundary.rs`,
//! `fitness_m5_loginitem_not_watchdog.rs`) — no call-graph analysis, no
//! `--target x86_64-pc-windows-msvc` build (not installed on this machine;
//! see this test's own final check, which honestly reports whether one is
//! available rather than assuming either way).

use std::fs;
use std::path::{Path, PathBuf};

fn platform_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("platform")
}

fn windows_dir() -> PathBuf {
    platform_dir().join("windows")
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

fn relative(path: &Path) -> String {
    path.strip_prefix(Path::new(env!("CARGO_MANIFEST_DIR")).join("src"))
        .unwrap_or(path)
        .display()
        .to_string()
}

/// Gate 1 (declaration site): `platform/mod.rs` must declare `pub mod
/// windows;` with `#[cfg(windows)]` immediately preceding it — the SAME
/// pattern the existing macOS-only dependency block in `Cargo.toml` and
/// `managed::forced`'s own `#[cfg(target_os = "macos")]` split already use
/// in this crate.
#[test]
fn platform_mod_gates_the_windows_module_declaration_fitness_m9() {
    let src = fs::read_to_string(platform_dir().join("mod.rs")).expect("read platform/mod.rs");
    let idx = src
        .find("pub mod windows;")
        .expect("expected `pub mod windows;` in platform/mod.rs");
    let preceding = &src[..idx];
    let last_line = preceding.lines().last().unwrap_or("");
    assert!(
        last_line.contains("#[cfg(windows)]"),
        "expected `#[cfg(windows)]` on the line immediately before `pub mod windows;` in \
         platform/mod.rs — found {last_line:?} instead"
    );
}

/// Gate 1, companion: the macOS module declaration is likewise gated (so a
/// non-macOS, non-Windows target — e.g. a Linux dev build of this crate —
/// gets neither module, rather than accidentally compiling the macOS
/// wrapper's `objc2`/`core-foundation` calls).
#[test]
fn platform_mod_gates_the_macos_module_declaration_fitness_m9() {
    let src = fs::read_to_string(platform_dir().join("mod.rs")).expect("read platform/mod.rs");
    let idx = src
        .find("pub mod macos;")
        .expect("expected `pub mod macos;` in platform/mod.rs");
    let preceding = &src[..idx];
    let last_line = preceding.lines().last().unwrap_or("");
    assert!(
        last_line.contains(r#"#[cfg(target_os = "macos")]"#),
        "expected `#[cfg(target_os = \"macos\")]` on the line immediately before `pub mod macos;` \
         in platform/mod.rs — found {last_line:?} instead"
    );
}

/// Gate 1, companion: the two cfg-aliased surfaces (`tray_art`, `cli_path`)
/// are ALSO gated per-arm — a macOS build must never see the `windows::`
/// alias arm compile, and vice versa.
#[test]
fn platform_mod_gates_both_arms_of_the_tray_art_and_cli_path_aliases_fitness_m9() {
    let src = fs::read_to_string(platform_dir().join("mod.rs")).expect("read platform/mod.rs");
    for alias_use in [
        "pub use crate::render::glyph as tray_art;",
        "pub use windows::tray as tray_art;",
        "pub use crate::cli::path as cli_path;",
        // `rustfmt` collapses a same-named `as` alias — this is
        // `windows::cli_path` re-exported under its own (already-matching)
        // name, not a typo.
        "pub use windows::cli_path;",
    ] {
        let idx = src
            .find(alias_use)
            .unwrap_or_else(|| panic!("expected {alias_use:?} in platform/mod.rs"));
        let preceding = &src[..idx];
        let last_line = preceding.lines().last().unwrap_or("");
        assert!(
            last_line.contains("#[cfg("),
            "expected a #[cfg(...)] gate on the line immediately before {alias_use:?} — found \
             {last_line:?} instead"
        );
    }
}

/// Gate 2 (belt-and-suspenders, per-file): `platform/windows/mod.rs` and
/// EVERY `.rs` file directly under `platform/windows/` must carry its own
/// `#![cfg(windows)]` inner attribute, independent of the declaration-site
/// gate above — so even a future refactor that drops the outer `#[cfg]` by
/// accident still can't compile this code into a non-Windows build.
#[test]
fn every_file_under_platform_windows_carries_its_own_cfg_windows_gate_fitness_m9() {
    let mut files = Vec::new();
    collect_rs_files(&windows_dir(), &mut files);
    assert!(
        !files.is_empty(),
        "expected to find .rs files under src/platform/windows/"
    );

    let expected_seams = [
        "cli_path.rs",
        "forced.rs",
        "loginitem.rs",
        "schtasks.rs",
        "secret_store.rs",
        "tray.rs",
        "watchdog.rs",
        "mod.rs",
    ];
    for seam in expected_seams {
        assert!(
            files
                .iter()
                .any(|f| f.file_name().and_then(|n| n.to_str()) == Some(seam)),
            "expected platform/windows/{seam} to exist (pre-created shared surface, task 71)"
        );
    }

    let mut offenders = Vec::new();
    for file in &files {
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        if !raw.contains("#![cfg(windows)]") {
            offenders.push(relative(file));
        }
    }
    assert!(
        offenders.is_empty(),
        "every file under platform/windows/ must carry its own `#![cfg(windows)]` inner \
         attribute (belt-and-suspenders with the declaration-site gate) — missing it in: \
         {offenders:?}"
    );
}

/// Windows-only crates (`winreg`, `keyring`, `windows`) must be declared
/// under `Cargo.toml`'s `[target.'cfg(windows)'.dependencies]` block, never
/// the top-level `[dependencies]` — the same target-gating discipline the
/// pre-existing macOS-only block already established for
/// `core-foundation`/`objc2-service-management`. A misplaced entry in
/// `[dependencies]` would pull a Windows-only crate into every platform's
/// build unconditionally.
#[test]
fn windows_only_crates_are_declared_under_the_target_cfg_windows_dependencies_block_fitness_m9() {
    let repo_root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let cargo_toml =
        fs::read_to_string(repo_root.join("Cargo.toml")).expect("read src-tauri/Cargo.toml");

    let windows_block_start = cargo_toml
        .find("[target.'cfg(windows)'.dependencies]")
        .expect("expected a [target.'cfg(windows)'.dependencies] section in Cargo.toml");
    let windows_block = &cargo_toml[windows_block_start..];
    // The block ends at the next top-level `[` heading (or EOF).
    let windows_block_end = windows_block[1..]
        .find("\n[")
        .map(|i| i + 1)
        .unwrap_or(windows_block.len());
    let windows_block = &windows_block[..windows_block_end];

    let before_windows_block = &cargo_toml[..windows_block_start];

    for crate_name in ["winreg", "keyring", "windows"] {
        assert!(
            windows_block.contains(crate_name),
            "expected {crate_name:?} to appear inside [target.'cfg(windows)'.dependencies] — \
             not found"
        );
        // Belt-and-suspenders: the SAME crate name must not ALSO appear
        // naked in the unconditional `[dependencies]` section above the
        // windows block (a bare substring check is intentionally coarse —
        // this crate's Cargo.toml has no naming collision with these three
        // literal crate names anywhere else).
        let unconditional_declares_it = before_windows_block.lines().any(|line| {
            line.trim_start().starts_with(&format!("{crate_name} ="))
                || line.trim_start().starts_with(&format!("{crate_name}="))
        });
        assert!(
            !unconditional_declares_it,
            "{crate_name:?} must not ALSO be declared in the unconditional [dependencies] section"
        );
    }
}

/// Honest reporting, per this task's own verification-boundary constraint:
/// note whether a `x86_64-pc-windows-msvc`/`-gnu` target is installed on
/// this machine, without treating either answer as a pass/fail condition —
/// this crate makes NO claim that Windows code has been build- or
/// test-verified anywhere in this suite.
#[test]
fn windows_target_availability_is_reported_honestly_not_assumed_fitness_m9() {
    let output = std::process::Command::new("rustup")
        .args(["target", "list", "--installed"])
        .output();
    match output {
        Ok(out) if out.status.success() => {
            let installed = String::from_utf8_lossy(&out.stdout);
            let has_windows_target = installed
                .lines()
                .any(|l| l.contains("pc-windows-msvc") || l.contains("pc-windows-gnu"));
            eprintln!(
                "[fitness_m9] a Windows Rust target is {}installed on this machine — Windows \
                 code has NOT been build- or test-verified either way (owner-gated per \
                 ADR-M9-005/006).",
                if has_windows_target { "" } else { "NOT " }
            );
        }
        _ => {
            eprintln!(
                "[fitness_m9] `rustup target list --installed` is unavailable on this machine — \
                 cannot report Windows-target availability either way. Windows code has NOT been \
                 build- or test-verified (owner-gated per ADR-M9-005/006)."
            );
        }
    }
    // No assertion — this test exists to print the honest status line above
    // into `cargo test`'s captured-on-failure output / `--nocapture` output,
    // never to gate on it.
}
