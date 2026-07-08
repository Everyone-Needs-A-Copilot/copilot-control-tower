//! M6/S4 fitness function (task 55): `render::security_banner::
//! SecurityBanner` is structurally RE-AFFIRM-ONLY — it can never be
//! dismissed/cleared/approved away. Same cheap, dependency-free text-scan
//! style every other fitness test in this crate already uses (see
//! `fitness_m6_itsignal_content_free.rs`,
//! `fitness_m6_itsignal_sink_content_free.rs`) — no call-graph analysis, no
//! live process.
//!
//! Two independent structural proofs:
//!
//! 1. **`SecurityBanner` declares exactly `message`/`reaffirm_label`** — a
//!    source scan of the struct declaration, so a future field addition
//!    (`dismiss`/`clear`/`approve`/`resolved`) is caught here, at the type
//!    declaration, not discovered downstream in a renderer that trusts it.
//! 2. **No method on `SecurityBanner`/anywhere in this file spells
//!    dismiss/clear/approve/resolve** — a whole-file text scan (excluding
//!    this doc comment's own prose, which legitimately explains what must
//!    NOT exist) proving the type has no way to construct a "this is
//!    handled now" value other than the fixed `kept_you_safe` past-tense
//!    constructor.

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

fn banner_rs_source() -> String {
    read_production_source(&src_dir().join("render").join("security_banner.rs"))
}

#[test]
fn security_banner_struct_declares_exactly_message_and_reaffirm_label() {
    let production_only = banner_rs_source();

    let marker = "pub struct SecurityBanner {";
    let start = production_only
        .find(marker)
        .expect("expected render/security_banner.rs to declare `pub struct SecurityBanner`");
    let body_start = start + marker.len();
    let rest = &production_only[body_start..];
    let end = rest
        .find('}')
        .expect("unbalanced braces in SecurityBanner struct");
    let body = &rest[..end];

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
        vec!["message", "reaffirm_label"],
        "SecurityBanner must carry EXACTLY these two fields — no dismiss/clear/approve/resolved \
         field may ever be added; see the module doc's 're-affirm-only' section"
    );
}

#[test]
fn no_dismiss_clear_approve_or_resolve_vocabulary_appears_in_production_code() {
    // Production code ONLY (comments stripped) — the module doc's prose is
    // free to explain what must NOT exist (and does, deliberately); this
    // scan proves the CODE itself never spells a way to construct or reach
    // one of these outcomes.
    let production_only = banner_rs_source();
    let lowercase = production_only.to_lowercase();

    for forbidden in ["dismiss", "clear", "approve", "resolved", "acknowledge"] {
        assert!(
            !lowercase.contains(forbidden),
            "render/security_banner.rs's PRODUCTION code must never spell \"{forbidden}\" — a \
             security banner is re-affirm-only, never dismissable/clearable/approvable, and \
             never silently marked resolved"
        );
    }
}

#[test]
fn governed_file_actually_exists_and_is_nonempty() {
    let path = src_dir().join("render").join("security_banner.rs");
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    assert!(
        !raw.trim().is_empty(),
        "{} is unexpectedly empty",
        path.display()
    );
}
