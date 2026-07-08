//! FF-M6-C (M6/S2, task 53, extends M5's `it_signal_serializes_to_exactly_
//! kind_and_admin_contact`): `ItSignal` stays content-free BY CONSTRUCTION
//! after M6's extension — no field can ever carry a personal item name. Two
//! independent structural proofs, plus the value-level serialization pin
//! already exercised in `routing::tests` (`every_extended_it_signal_kind_
//! still_serializes_to_exactly_kind_and_admin_contact`):
//!
//! 1. **`ItSignal` itself still has exactly two fields** (`kind`,
//!    `admin_contact`) — a source scan of its struct declaration, so a
//!    future field addition (e.g. threading `item`/`dimension`/`layer`
//!    through for a "richer" IT signal) is caught here, at the type
//!    declaration, not discovered downstream in a renderer.
//! 2. **Every `ItSignalKind` variant is a bare, fieldless discriminant** — a
//!    source scan of the enum declaration proving NONE of the M5 or M6
//!    variants carries associated data (`(String)`/`{ .. }`). This is the
//!    mechanism that makes embedding a personal item name in an `ItSignal`
//!    IMPOSSIBLE, not merely discouraged (the same "impossible by
//!    construction" standard `SOUL.md`'s *The Leak* anti-pattern applies to
//!    the inheritance-sync path, applied here to the IT-escalation path): if
//!    `ItSignalKind` can never hold data, there is no field anywhere in this
//!    type for a caller to accidentally populate with one.

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

fn mod_rs_source() -> String {
    read_production_source(&src_dir().join("routing").join("mod.rs"))
}

#[test]
fn it_signal_struct_still_declares_exactly_kind_and_admin_contact() {
    let production_only = mod_rs_source();

    let marker = "pub struct ItSignal {";
    let start = production_only
        .find(marker)
        .expect("expected routing/mod.rs to declare `pub struct ItSignal`");
    let body_start = start + marker.len();
    let rest = &production_only[body_start..];
    let end = rest
        .find('}')
        .expect("unbalanced braces in ItSignal struct");
    let body = &rest[..end];

    // Each field declaration is `pub <name>: <type>,` — extract the field
    // names only.
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
        vec!["kind", "admin_contact"],
        "ItSignal must carry EXACTLY these two fields — see the module doc's \
         'content-free by construction' section"
    );
}

/// Every `ItSignalKind` variant — declared across all three call sites this
/// enum lives in the same declaration for (M5's original three + M6's
/// additions) — must be a bare identifier with no `(...)`/`{...}` payload.
#[test]
fn no_itsignalkind_variant_carries_associated_data() {
    let production_only = mod_rs_source();

    let marker = "pub enum ItSignalKind {";
    let start = production_only
        .find(marker)
        .expect("expected routing/mod.rs to declare `pub enum ItSignalKind`");
    let body_start = start + marker.len();
    let rest = &production_only[body_start..];
    let end = rest
        .find('}')
        .expect("unbalanced braces in ItSignalKind enum");
    let body = &rest[..end];

    let variants: Vec<&str> = body
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();

    assert!(
        variants.len() >= 13,
        "expected at least 13 ItSignalKind variants (3 from M5 + 7 named by task 53 + this \
         task's own well-justified additions), found {}: {variants:?}",
        variants.len()
    );

    let mut offenders = Vec::new();
    for variant in &variants {
        if variant.contains('(') || variant.contains('{') {
            offenders.push(*variant);
        }
    }

    assert!(
        offenders.is_empty(),
        "the following ItSignalKind variants carry associated data (forbidden — a variant with \
         a payload could carry a personal item name into the content-free IT channel): {offenders:?}"
    );
}

/// Belt-and-suspenders: confirms the scan itself is exercising a real,
/// nonempty file.
#[test]
fn governed_file_actually_exists_and_is_nonempty() {
    let path = src_dir().join("routing").join("mod.rs");
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    assert!(
        !raw.trim().is_empty(),
        "{} is unexpectedly empty",
        path.display()
    );
}
