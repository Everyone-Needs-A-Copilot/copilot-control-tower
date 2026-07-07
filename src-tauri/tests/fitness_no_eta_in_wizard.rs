//! M3/S1 fitness function (`.copilot/wp/15.md` §4 fitness function 1,
//! ADR-M3-003, SOUL Case Law OUT): the wizard renders progress by phase
//! NAME, never a time estimate. A grep-deny scan of every forbidden
//! countdown/ETA/percentage phrase across the whole `wizard/` module's
//! production source (comments and `#[cfg(test)]` blocks excluded — same
//! `strip_comments`/`strip_cfg_test_blocks` convention as
//! `fitness_no_bare_cli_name.rs` / `fitness_no_fabricated_healthy.rs`, and
//! for the identical reason: this module's own doc comments necessarily
//! *talk about* the word "ETA" while explaining why it's forbidden, so the
//! scan must look only at what the code could actually put on the wire, not
//! at prose describing the invariant).
//!
//! The needle list is deliberately made of whole PHRASES, not a bare `"eta"`
//! substring — `"eta"` alone would false-positive on ordinary English words
//! (e.g. "metadata", "create", "delete" — several contain "eta"/"ete" runs).
//! Matching complete phrases keeps the check precise instead of forcing
//! awkward wording elsewhere.

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

/// Strips `//...` line comments and `/* ... */` block comments — identical
/// approach to the other fitness tests' `strip_comments`.
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
/// same logic as `fitness_no_fabricated_healthy.rs`'s `strip_cfg_test_blocks`
/// (test fixtures aren't the invariant under test here).
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

fn production_only(raw: &str) -> String {
    strip_cfg_test_blocks(&strip_comments(raw))
}

const FORBIDDEN_PHRASES: [&str; 10] = [
    "ETA",
    "estimated time",
    "estimated at",
    "time remaining",
    "minutes left",
    "seconds left",
    "min left",
    "sec left",
    "% complete",
    "countdown",
];

#[test]
fn wizard_module_never_renders_an_eta_or_countdown_string() {
    let wizard_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("wizard");
    let mut files = Vec::new();
    collect_rs_files(&wizard_dir, &mut files);
    assert!(
        !files.is_empty(),
        "expected to find .rs files under {}",
        wizard_dir.display()
    );

    let mut offenders: Vec<(PathBuf, &str)> = Vec::new();
    for file in &files {
        let raw =
            fs::read_to_string(file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        let prod = production_only(&raw);
        for phrase in FORBIDDEN_PHRASES {
            if prod.contains(phrase) {
                offenders.push((file.clone(), phrase));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "found an ETA/countdown/percentage-as-promise string in the wizard module: \
         {offenders:?} — progress must be rendered by phase NAME only (ADR-M3-003, SOUL Case \
         Law OUT); an app that can't finish honestly must not promise a time it can't keep."
    );
}

/// A companion structural check: every string literal in `dto.rs`'s
/// production code is free of a digit immediately followed by a time unit
/// (a cheap additional net for a phrasing the exact phrase list above might
/// miss, e.g. "2 min" or "30s").
#[test]
fn phase_label_strings_never_pair_a_digit_with_a_time_unit() {
    let dto_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("wizard")
        .join("dto.rs");
    let raw = fs::read_to_string(&dto_path)
        .unwrap_or_else(|e| panic!("read {}: {e}", dto_path.display()));
    let prod = production_only(&raw);

    let bytes = prod.as_bytes();
    for (i, &b) in bytes.iter().enumerate() {
        if b.is_ascii_digit() {
            let rest = &prod[i + 1..];
            let trimmed = rest.trim_start_matches(char::is_whitespace);
            for unit in ["min", "sec", "hour", "ms"] {
                assert!(
                    !trimmed.starts_with(unit),
                    "found a digit immediately followed by a time unit ({unit:?}) near byte {i} \
                     in dto.rs — looks like an ETA string: {:?}",
                    &prod[i.saturating_sub(10)..(i + 20).min(prod.len())]
                );
            }
        }
    }
}
