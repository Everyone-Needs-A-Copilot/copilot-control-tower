//! M9/Stream-D fitness function (task 73, ADR-M9-003, invariant #4): the
//! Windows forced-config reader must NEVER read `HKEY_CURRENT_USER`/`HKCU`
//! — the Windows analog of "never honor the user-domain value as forced."
//! Same cheap, dependency-free text-scan style every other fitness test in
//! this crate already uses (`fitness_m5_single_forced_boundary.rs`,
//! `fitness_m5_secretstore_reference_only.rs`) — this is a source-scan of
//! `src/platform/windows/forced.rs`'s **production** source only
//! (`#[cfg(test)]` blocks stripped, comments stripped), so this module's
//! own doc-comment prose *explaining* the never-HKCU rule (which
//! necessarily contains the literal substring "HKCU") can never trip its
//! own guard — comments are stripped before the scan runs, identically to
//! every other fitness test's convention in this crate.
//!
//! Runs on macOS (no Windows toolchain needed) — this is a plain-text scan
//! of a `.rs` file that lives in the repo regardless of build target; it
//! does not compile or execute `platform::windows::forced` at all.

use std::fs;
use std::path::{Path, PathBuf};

fn forced_rs_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("platform")
        .join("windows")
        .join("forced.rs")
}

/// Strips `//...` line comments and `/* ... */` block comments — identical
/// approach to every other fitness test in this crate.
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

/// Removes every `#[cfg(test)] ... { ... }` item's body (brace-matched) —
/// identical logic to `fitness_m5_single_forced_boundary.rs`'s
/// `strip_cfg_test_blocks` (duplicated per this crate's "each fitness check
/// owns its own copy" convention). Needed here because this module's own
/// test suite legitimately drives `dsregcmd`-shaped sample text and env-var
/// names that must never trip this scan.
fn strip_cfg_test_blocks(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let marker = "#[cfg(test)]";
    let mut rest = src;
    while let Some(idx) = rest.find(marker) {
        out.push_str(&rest[..idx]);
        let after_marker = &rest[idx + marker.len()..];
        let brace_start = match after_marker.find('{') {
            Some(b) => b,
            None => {
                out.push_str(marker);
                rest = after_marker;
                continue;
            }
        };
        let body = &after_marker[brace_start..];
        let mut depth = 0i32;
        let mut end = None;
        for (pos, ch) in body.char_indices() {
            match ch {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        end = Some(pos + 1);
                        break;
                    }
                }
                _ => {}
            }
        }
        let end = end.unwrap_or(body.len());
        rest = &body[end..];
    }
    out.push_str(rest);
    out
}

fn production_source() -> String {
    let raw = fs::read_to_string(forced_rs_path())
        .unwrap_or_else(|e| panic!("read {}: {e}", forced_rs_path().display()));
    strip_cfg_test_blocks(&strip_comments(&raw))
}

/// **The core assertion.** Neither `HKEY_CURRENT_USER` nor the bare
/// abbreviation `HKCU` may appear anywhere in this file's production
/// source — ADR-M9-003 / task 73's explicit instruction: "NEVER read HKCU
/// (user-writable) as forced," enforced structurally, not by review
/// discipline.
#[test]
fn windows_forced_reader_never_references_hkcu_fitness_m9() {
    assert!(
        forced_rs_path().exists(),
        "expected src/platform/windows/forced.rs to exist"
    );
    let src = production_source();
    for forbidden in ["HKEY_CURRENT_USER", "HKCU"] {
        assert!(
            !src.contains(forbidden),
            "src/platform/windows/forced.rs unexpectedly references {forbidden:?} in its \
             production source — this module must NEVER read the user-writable registry hive \
             as forced (ADR-M9-003, invariant #4)"
        );
    }
}

/// Positive companion: the reader DOES read `HKEY_LOCAL_MACHINE` — a file
/// that referenced neither hive at all would trivially (and uselessly)
/// pass the check above without doing its job.
#[test]
fn windows_forced_reader_reads_hklm_fitness_m9() {
    let src = production_source();
    assert!(
        src.contains("HKEY_LOCAL_MACHINE"),
        "expected src/platform/windows/forced.rs to read HKEY_LOCAL_MACHINE — a file that reads \
         neither registry hive would vacuously (uselessly) pass the no-HKCU check"
    );
    assert!(
        src.contains(r"SOFTWARE\Policies\ENAC\ControlTower") || src.contains("Policies"),
        "expected the forced reader to target the Policies subtree ADR-M9-003 names"
    );
}

/// The `dsregcmd` subprocess must never be spawned via a bare `PATH`
/// lookup — this review's own security-verdict fix #1 (see
/// `forced.rs`'s module doc "Security verdict" section): a bare
/// `Command::new("dsregcmd")` would let a local admin (or a PATH-hijack)
/// shadow it with a fake binary that always reports "enrolled." This test
/// asserts the literal bare-name invocation never appears; the absolute-path
/// resolver (`dsregcmd_absolute_path`) is what `Command::new` is built from
/// instead.
#[test]
fn dsregcmd_is_never_invoked_via_a_bare_path_lookup_fitness_m9() {
    let src = production_source();
    assert!(
        !src.contains(r#"Command::new("dsregcmd")"#),
        "src/platform/windows/forced.rs must never spawn a bare `dsregcmd` via PATH lookup — \
         resolve an absolute path first (see dsregcmd_absolute_path and this module's own \
         Security verdict section)"
    );
    assert!(
        src.contains("dsregcmd_absolute_path"),
        "expected an absolute-path resolver function to exist and be used"
    );
}
