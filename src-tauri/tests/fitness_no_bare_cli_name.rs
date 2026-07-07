//! T4 fitness function (architecture WP "Fitness functions": "No bare CLI
//! name") — the only place this crate may construct a `std::process::Command`
//! for the `cc`/`copilot` binary is `cli::spawn::doctor_with_timeout`, and
//! even there it must be built from the caller-supplied, already-resolved
//! `cli_path` argument (via `cli::path::resolve()`), never a literal `"cc"`
//! or `"copilot"` string. A bare name would resolve through $PATH — exactly
//! the `gh copilot` shim collision and hijack risk invariant #4 forbids.
//!
//! This is a pure text scan of the crate's own production source (`src/`,
//! `#[cfg(test)]` blocks excluded — a test fixture path like
//! `fixtures/mock-cc` is not the invariant under test here), independent of
//! the compiled/visibility boundary, for the same reason
//! `fitness_no_fabricated_healthy.rs` scans source rather than binary
//! output: it needs to see literal source, not macro-expanded code.

use std::fs;
use std::path::{Path, PathBuf};

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
/// approach as `fitness_no_fabricated_healthy.rs`'s `strip_comments`.
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
/// identical logic to `fitness_no_fabricated_healthy.rs`'s
/// `strip_cfg_test_blocks`, duplicated rather than shared so each fitness
/// test file stays independently readable/auditable.
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

const FORBIDDEN_NEEDLES: [&str; 4] = [
    "Command::new(\"cc\")",
    "Command::new(\"copilot\")",
    "Command::new(\"cc\",",
    "Command::new(\"copilot\",",
];

#[test]
fn no_bare_cc_or_copilot_command_construction_anywhere_in_production_source() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut files = Vec::new();
    collect_rs_files(&src_dir, &mut files);
    assert!(
        !files.is_empty(),
        "expected to find .rs files under {}",
        src_dir.display()
    );

    let mut offenders: Vec<(PathBuf, &str)> = Vec::new();
    for file in &files {
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        let production_only = strip_cfg_test_blocks(&strip_comments(&raw));
        for needle in FORBIDDEN_NEEDLES {
            if production_only.contains(needle) {
                offenders.push((file.clone(), needle));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "found a bare `cc`/`copilot` Command construction (would resolve through $PATH — \
         the gh-copilot-shim-collision / hijack risk invariant #4 forbids): {offenders:?}. \
         Every CLI spawn must go through `cli::path::resolve()`'s already-resolved absolute \
         path, never a literal name."
    );
}

/// `cli::spawn` is the ONLY module allowed to construct a
/// `std::process::Command` for the CLI at all (per its own module doc) —
/// this doesn't forbid `Command::new` generally (other tooling, e.g. a
/// future `open`/`kill` utility call, may legitimately need it), only
/// re-confirms the CLI-spawn boundary is exactly one file.
#[test]
fn command_new_for_a_path_variable_is_confined_to_cli_spawn() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut files = Vec::new();
    collect_rs_files(&src_dir, &mut files);

    let spawn_rs = src_dir.join("cli").join("spawn.rs");
    let mut sites: Vec<PathBuf> = Vec::new();
    for file in &files {
        if *file == spawn_rs {
            continue;
        }
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        let production_only = strip_cfg_test_blocks(&strip_comments(&raw));
        // Looks for the doctor/--json invocation shape specifically, not
        // every possible `Command::new` (a narrower, less brittle check than
        // banning the constructor outright).
        if production_only.contains(".arg(\"doctor\")") {
            sites.push(file.clone());
        }
    }

    assert!(
        sites.is_empty(),
        "found a `doctor --json`-shaped invocation outside cli/spawn.rs: {sites:?} — the \
         CLI-spawn boundary must stay exactly one file (cli::spawn's module doc)"
    );
}
