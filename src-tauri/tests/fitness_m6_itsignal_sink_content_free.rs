//! M6/S3 fitness function (task 54): the `ItSignalSink` emission seam
//! (`src-tauri/src/routing/emit.rs`) accepts ONLY the content-free
//! `ItSignal` type — there is no path for a personal item name to reach it.
//! Same cheap, dependency-free text-scan style every other fitness test in
//! this crate already uses (see `fitness_m6_itsignal_content_free.rs`,
//! `fitness_m5_single_forced_boundary.rs`) — no call-graph analysis, no live
//! process, just a source-declaration scan that fails loudly the moment a
//! future edit widens the seam's input type.
//!
//! Three independent structural proofs:
//!
//! 1. **`ItSignalSink::record`'s signature takes exactly `&ItSignal`** — a
//!    source scan of the trait declaration, so a future "richer" signal type
//!    threaded through this seam (e.g. one that also carries `item`/
//!    `dimension`/`layer`) is caught here, at the trait boundary, not
//!    discovered downstream in a real transport.
//! 2. **`LocalSinkEntry` carries only `kind`/`admin_contact`/`deliverable`**
//!    — the ONE default sink this task builds retains nothing beyond what
//!    `ItSignal` itself already carries, plus the one derived
//!    deliverability bit; no `bob_action`/`fallback`/free-text field exists
//!    for a caller to populate with content.
//! 3. **No path from a `RoutableEvent`'s own fields into a dispatched
//!    signal** — `emit`'s dispatch sites (`sink.record(signal)`) only ever
//!    pass a `Routed::EscalateIt`'s payload or an `AutoAct`'s `it_signal`
//!    companion, both already-constructed `ItSignal` values from
//!    `routing::policy::route` — this test greps `emit.rs` for any
//!    `.record(` call that is NOT one of those two forms.

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

fn emit_rs_source() -> String {
    read_production_source(&src_dir().join("routing").join("emit.rs"))
}

#[test]
fn itsignalsink_record_takes_exactly_a_content_free_itsignal_reference() {
    let production_only = emit_rs_source();

    let marker = "fn record(&self, signal: &ItSignal) -> Result<(), ItSignalSinkError>;";
    assert!(
        production_only.contains(marker),
        "expected `routing/emit.rs`'s `ItSignalSink` trait to declare exactly this `record` \
         signature — a widened signature (a second parameter, or a richer signal type) is \
         exactly the leak this fitness function exists to catch. Source:\n{production_only}"
    );
}

#[test]
fn local_sink_entry_declares_exactly_kind_admin_contact_and_deliverable() {
    let production_only = emit_rs_source();

    let marker = "pub struct LocalSinkEntry {";
    let start = production_only
        .find(marker)
        .expect("expected routing/emit.rs to declare `pub struct LocalSinkEntry`");
    let body_start = start + marker.len();
    let rest = &production_only[body_start..];
    let end = rest
        .find('}')
        .expect("unbalanced braces in LocalSinkEntry struct");
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
        vec!["kind", "admin_contact", "deliverable"],
        "LocalSinkEntry must carry EXACTLY these three fields — see routing/emit.rs's module \
         doc's 'content-free by construction' section"
    );
}

#[test]
fn every_sink_dispatch_site_passes_an_already_constructed_itsignal_value() {
    let production_only = emit_rs_source();

    let dispatch_sites: Vec<&str> = production_only
        .lines()
        .filter(|line| line.contains(".record("))
        .collect();

    assert!(
        !dispatch_sites.is_empty(),
        "expected at least one `sink.record(...)` dispatch site in routing/emit.rs"
    );

    for site in &dispatch_sites {
        assert!(
            site.contains("sink.record(signal)"),
            "expected every dispatch site to pass the already-routed `signal` binding verbatim \
             (never a freshly-assembled struct literal at the call site, which could smuggle an \
             extra field in) — offending line: {site:?}"
        );
    }
}

#[test]
fn governed_file_actually_exists_and_is_nonempty() {
    let path = src_dir().join("routing").join("emit.rs");
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    assert!(
        !raw.trim().is_empty(),
        "{} is unexpectedly empty",
        path.display()
    );
}
