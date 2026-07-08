//! FF-M6-A (M6/S2, task 53): every `RoutableEvent` variant routes to exactly
//! one lane — exhaustive, no unrouted event. Two independent proofs:
//!
//! 1. **Source-level**: `routing::policy::route`'s `match` on `RoutableEvent`
//!    contains NO `_ =>` (or `_ if`) wildcard arm. Rust's own exhaustiveness
//!    checker already forces every current variant to have an arm (or the
//!    crate fails to compile) — this scan proves that guarantee can never be
//!    silently defeated by a future contributor adding a catch-all that would
//!    let a NEW variant compile without ever being routed. Same cheap,
//!    dependency-free text-scan style every other fitness test in this crate
//!    uses (`fitness_m5_deprovision_is_it_routed.rs`,
//!    `fitness_m5_no_wipe_logic.rs`).
//! 2. **Value-level**: constructs one instance of every `RoutableEvent`
//!    variant (`routing::policy::tests::
//!    every_routable_event_variant_produces_exactly_one_routed_value`,
//!    exercised as an ordinary `cargo test`, referenced here so this file's
//!    own doc names both halves of the proof) and confirms `route` returns a
//!    concrete `Routed` for each, never panicking.

use std::fs;
use std::path::{Path, PathBuf};

fn src_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("src")
}

/// Strips `//...` line comments and `/* ... */` block comments — same
/// approach every other fitness test in this crate uses, so a needle
/// mentioned only in a doc comment never trips this test.
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
/// same logic every other fitness test in this crate duplicates
/// independently (see `fitness_m5_deprovision_is_it_routed.rs`'s identical
/// helper's own doc for why it's copied rather than shared).
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

/// Extracts the `route`'s `match` body from `policy.rs`'s production source
/// (comments/tests already stripped) — from the `match event {` opener to
/// its balanced closing brace.
fn route_match_body(production_only: &str) -> String {
    let marker = "match event {";
    let start = production_only
        .find(marker)
        .expect("expected policy.rs to contain `match event {` inside `route`");
    let body_start = start + marker.len() - 1; // include the opening brace
    let body = &production_only[body_start..];
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
    let end = end.expect("unbalanced braces in route's match");
    body[..end].to_string()
}

#[test]
fn routes_match_has_no_wildcard_arm_hiding_an_unrouted_event() {
    let policy_path = src_dir().join("routing").join("policy.rs");
    let production_only = read_production_source(&policy_path);
    let match_body = route_match_body(&production_only);

    // A wildcard match arm (`_ =>` or `_ if ...=>`) would let a brand-new
    // `RoutableEvent` variant compile silently unrouted — forbidden.
    assert!(
        !match_body.contains("_ =>") && !match_body.contains("_ if"),
        "routing::policy::route's match on RoutableEvent must have no `_ =>`/`_ if` wildcard \
         arm — every event class must be named explicitly so a new RoutableEvent variant is a \
         compile error here until this table grows a row for it"
    );
}

/// Every `RoutableEvent` variant declared in `event.rs` must have at least
/// one corresponding arm inside `route`'s match body in `policy.rs` — a
/// second, independent proof alongside the wildcard-absence check above (in
/// case a future refactor restructures the match without introducing a
/// wildcard, e.g. an early return that skips a variant entirely).
#[test]
fn every_declared_routable_event_variant_has_a_named_arm_in_the_policy_match() {
    let event_path = src_dir().join("routing").join("event.rs");
    let event_source = read_production_source(&event_path);

    let policy_path = src_dir().join("routing").join("policy.rs");
    let policy_production = read_production_source(&policy_path);
    let match_body = route_match_body(&policy_production);

    // Parse the `pub enum RoutableEvent { ... }` variant list.
    let enum_marker = "pub enum RoutableEvent {";
    let enum_start = event_source
        .find(enum_marker)
        .expect("expected event.rs to declare `pub enum RoutableEvent`");
    let enum_body_start = enum_start + enum_marker.len();
    let enum_rest = &event_source[enum_body_start..];
    let enum_end = enum_rest
        .find('}')
        .expect("unbalanced braces in RoutableEvent enum");
    let enum_body = &enum_rest[..enum_end];

    let variants: Vec<&str> = enum_body
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.split('(').next().unwrap_or(s).trim())
        .collect();

    assert!(
        variants.len() >= 11,
        "expected at least 11 RoutableEvent variants (task 53's own scope list), found {}: {variants:?}",
        variants.len()
    );

    let mut missing = Vec::new();
    for variant in &variants {
        let needle = format!("RoutableEvent::{variant}");
        if !match_body.contains(&needle) {
            missing.push(*variant);
        }
    }

    assert!(
        missing.is_empty(),
        "the following RoutableEvent variants have no arm in route's match body: {missing:?}"
    );
}

/// Belt-and-suspenders: confirms the scan itself is exercising real,
/// nonempty files.
#[test]
fn governed_files_actually_exist_and_are_nonempty() {
    for rel in ["routing/event.rs", "routing/policy.rs", "routing/mod.rs"] {
        let path = src_dir().join(rel);
        let raw =
            fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        assert!(
            !raw.trim().is_empty(),
            "{} is unexpectedly empty",
            path.display()
        );
    }
}
