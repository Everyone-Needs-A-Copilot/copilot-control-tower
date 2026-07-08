//! FF-M7-CONTENTFREE, schema level (M7/S1, task 60, ADR-M7-002). Pins that
//! `telemetry::schema::FleetEvent` — and everything it transitively
//! contains — has no field capable of carrying a personal item name/path/
//! free content, only ids/enums/numbers/timestamps. Mirrors
//! `tests/fitness_m6_itsignal_content_free.rs`'s exact proof shape (a
//! source scan of the struct/enum declarations), applied to the new fleet-
//! event type instead of `routing::ItSignal`.
//!
//! This is the SCHEMA-level pin. `tc task list --prd 7` (task 69, M7/S10,
//! a `qa` agent) later builds the full `FF-M7-CONTENTFREE` fitness test at
//! the TRANSPORT boundary (the real emitter/sink, S3) — this file does not
//! preempt that, it gives S3/S4 (and that later suite) a schema-level
//! guarantee to build on, named distinctly (`_schema_`) so the two files
//! never collide.

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

fn production_source() -> String {
    let path = src_dir().join("telemetry").join("schema.rs");
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    strip_cfg_test_blocks(&strip_comments(&raw))
}

/// Extracts the `{ ... }` body immediately following a `marker` (e.g.
/// `"pub struct FleetEvent {"`), balancing braces — same technique
/// `fitness_m6_itsignal_content_free.rs` uses for `ItSignal`/`ItSignalKind`.
fn extract_body<'a>(source: &'a str, marker: &str) -> &'a str {
    let start = source
        .find(marker)
        .unwrap_or_else(|| panic!("expected telemetry/schema.rs to declare `{marker}`"));
    let body_start = start + marker.len();
    let rest = &source[body_start..];
    let end = rest.find('}').expect("unbalanced braces");
    &rest[..end]
}

#[test]
fn fleet_event_struct_declares_exactly_the_closed_content_free_field_set() {
    let source = production_source();
    let body = extract_body(&source, "pub struct FleetEvent {");

    let fields: Vec<&str> = body
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| {
            s.trim_start_matches("pub ")
                .split(':')
                .next()
                .unwrap_or(s)
                .trim()
        })
        .collect();

    assert_eq!(
        fields,
        vec![
            "schema_version",
            "machine_id",
            "host",
            "status",
            "event_kind",
            "occurred_at",
            "escalate",
            "occurrence_count",
        ],
        "FleetEvent must carry EXACTLY these fields — see schema.rs's module \
         doc's content-free invariant"
    );
}

/// Every `FleetEventKind` variant must be a bare identifier — no `(...)`/
/// `{...}` payload — the same "impossible, not merely discouraged" standard
/// `routing::ItSignalKind` already holds itself to.
#[test]
fn no_fleet_event_kind_variant_carries_associated_data() {
    let source = production_source();
    let body = extract_body(&source, "pub enum FleetEventKind {");

    let variants: Vec<&str> = body
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();

    assert!(
        variants.len() >= 6,
        "expected at least the 6 kinds this task's brief names, found {}: {variants:?}",
        variants.len()
    );

    let offenders: Vec<&&str> = variants
        .iter()
        .filter(|v| v.contains('(') || v.contains('{'))
        .collect();

    assert!(
        offenders.is_empty(),
        "the following FleetEventKind variants carry associated data (forbidden — a \
         payload could carry a personal item name into telemetry): {offenders:?}"
    );
}

/// The three wrapper newtypes (`SchemaVersion`/`MachineId`/`OccurredAt`)
/// must each wrap exactly one field — no second field could smuggle
/// additional, unaudited content alongside the opaque/fixed-format value.
#[test]
fn the_three_wrapper_newtypes_each_declare_exactly_one_field() {
    let source = production_source();
    for (name, marker) in [
        ("SchemaVersion", "pub struct SchemaVersion("),
        ("MachineId", "pub struct MachineId("),
        ("OccurredAt", "pub struct OccurredAt("),
    ] {
        let start = source
            .find(marker)
            .unwrap_or_else(|| panic!("expected telemetry/schema.rs to declare `{marker}`"));
        let rest = &source[start + marker.len()..];
        let end = rest.find(')').expect("unbalanced parens");
        let body = &rest[..end];
        let fields: Vec<&str> = body
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .collect();
        assert_eq!(
            fields.len(),
            1,
            "{name} must wrap exactly one field, found {fields:?}"
        );
    }
}

/// No field on `FleetEvent` is a bare `String`/`Option<String>` — every
/// string-shaped value is behind one of the three single-purpose newtypes,
/// which have their own narrow, non-free-text constructors (asserted by the
/// value-level tests in `telemetry::schema`'s own `#[cfg(test)]` module).
#[test]
fn fleet_event_has_no_bare_string_field() {
    let source = production_source();
    let body = extract_body(&source, "pub struct FleetEvent {");

    for line in body.split(',').map(str::trim).filter(|s| !s.is_empty()) {
        let ty = line.split(':').nth(1).unwrap_or("").trim();
        assert!(
            ty != "String" && ty != "Option<String>",
            "FleetEvent field `{line}` is a bare (free-text-capable) string type — \
             wrap it in a single-purpose newtype instead"
        );
    }
}

#[test]
fn governed_file_actually_exists_and_is_nonempty() {
    let path = src_dir().join("telemetry").join("schema.rs");
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    assert!(
        !raw.trim().is_empty(),
        "{} is unexpectedly empty",
        path.display()
    );
}
