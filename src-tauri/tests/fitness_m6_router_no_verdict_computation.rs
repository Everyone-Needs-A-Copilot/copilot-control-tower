//! FF-M6-D (M6/S2, task 53, `SOUL.md` Principle 1 / *The Second Pilot*
//! anti-pattern): the router computes NO health verdict, resolution, or
//! signature check of its own. `routing::event`/`routing::policy` may only
//! MAP already-parsed, already-trusted CLI facts to a lane — they must never
//! re-parse raw CLI output, re-run a worst-wins ladder, or call any of the
//! parse-boundary functions the wire/domain layers already own
//! (`model::state::parse_doctor_body`, `model::update::parse_update_body`,
//! and their internal 1:1-lookup helpers). Same cheap, dependency-free
//! text-scan style every other fitness test in this crate uses
//! (`fitness_m5_no_wipe_logic.rs`'s FF-M5-2 is the direct precedent: a
//! forbidden-needle scan over a narrowly-governed file set).

use std::fs;
use std::path::{Path, PathBuf};

fn src_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("src")
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

fn read_production_source(path: &Path) -> String {
    let raw = fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    strip_cfg_test_blocks(&strip_comments(&raw))
}

/// The exact parse-boundary/verdict-computing function CALL SITES (deliberately
/// including the trailing `(` so a mere TYPE reference — e.g. `Severity`,
/// `ChangeOp`, `AuthState`, all of which the router legitimately reads as
/// already-parsed data — never trips this scan; only an actual re-invocation
/// of a parsing/computing function would).
const FORBIDDEN_NEEDLES: [&str; 9] = [
    "parse_doctor_body(",
    "parse_update_body(",
    "parse_cli_status(",
    "parse_result(",
    "parse_op(",
    "severity_from_wire(",
    "auth_state_from_wire(",
    "serde_json::from_str(",
    "serde_json::from_slice(",
];

/// The exact two files this task owns and this invariant governs — scoped
/// narrowly, not the whole crate, matching `fitness_m5_no_wipe_logic.rs`'s
/// own scoping rationale (legitimate JSON/parse code exists elsewhere in the
/// crate for the actually-owned parse boundaries; this fitness function's
/// job is proving the ROUTING surface specifically carries none).
fn governed_files() -> Vec<PathBuf> {
    let src = src_dir().join("routing");
    vec![src.join("event.rs"), src.join("policy.rs")]
}

#[test]
fn router_source_calls_no_parse_boundary_or_verdict_computing_function() {
    let files = governed_files();
    let mut offenders: Vec<(PathBuf, &str)> = Vec::new();

    for file in &files {
        let production_only = read_production_source(file);
        for needle in FORBIDDEN_NEEDLES {
            if production_only.contains(needle) {
                offenders.push((file.clone(), needle));
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "found a parse-boundary/verdict-computing call inside the router (invariant #1 — the \
         router only maps already-trusted CLI facts to a lane; it never re-parses raw CLI \
         output or re-derives a verdict itself): {offenders:?}"
    );
}

/// `route`'s own doc names the exact fields it reads. This test is a coarse
/// but concrete guard against the router growing a NEW field read from
/// outside that known-safe set without review — confirms `policy.rs`
/// references only the already-established domain types
/// (`Severity`/`ChangeOp`/`AuthState`) and never the WIRE types
/// (`*Wire` structs, which are pre-fail-closed-gate and would mean the
/// router is reading unvalidated content).
#[test]
fn policy_never_references_a_raw_wire_type() {
    let policy_path = src_dir().join("routing").join("policy.rs");
    let production_only = read_production_source(&policy_path);

    const WIRE_TYPE_NEEDLES: [&str; 4] = ["DoctorWire", "CheckerWire", "UpdateWire", "ChangedWire"];
    let mut offenders = Vec::new();
    for needle in WIRE_TYPE_NEEDLES {
        if production_only.contains(needle) {
            offenders.push(needle);
        }
    }

    assert!(
        offenders.is_empty(),
        "policy.rs references a raw wire type ({offenders:?}) — the router must only ever \
         consume already-fail-closed-gated domain values via RoutableEvent, never pre-gate wire \
         structs"
    );
}

/// Belt-and-suspenders: confirms the scan itself is exercising real,
/// nonempty files.
#[test]
fn governed_files_actually_exist_and_are_nonempty() {
    for file in governed_files() {
        let raw =
            fs::read_to_string(&file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()));
        assert!(
            !raw.trim().is_empty(),
            "{} is unexpectedly empty",
            file.display()
        );
    }
}
