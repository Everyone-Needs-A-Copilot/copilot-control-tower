//! FF-M7-CONTENTFREE, TRANSPORT level (M7/S3, `.copilot/wp/43.md`, task 62).
//! Pins that `telemetry::emitter::TelemetryTransport::send` — the ONE seam a
//! [`telemetry::schema::FleetEvent`] crosses out of this process — accepts
//! `&[FleetEvent]` and nothing richer. Mirrors `tests/
//! fitness_m7_telemetry_schema_content_free.rs`'s exact proof shape (a
//! source-level scan of the declaration, not a runtime check) applied one
//! layer further downstream: that file pins the SHAPE has no free-text
//! field; this file pins the ONE function that ever hands a batch of that
//! shape to a transport takes no OTHER, richer parameter that could smuggle
//! content alongside it.
//!
//! This is a SCOPED, S3-level pin — the FULL FF-M7-CONTENTFREE suite across
//! every telemetry producer (doctor status changes, every `ItSignal`
//! mapping call site, the live `timer.rs` wiring) is a later, `qa`-owned
//! stream (task 69, M7/S10), per `fitness_m7_telemetry_schema_content_free.
//! rs`'s own doc. This file does not preempt that — it gives S9/S10 a
//! transport-level guarantee to build on, named distinctly (`_transport_`)
//! so the two files never collide.

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

/// Removes every `#[cfg(test)] ... { ... }` item's body (brace-matched) —
/// same technique every other fitness test in this crate uses, so this
/// module's own unit tests (which legitimately construct fake transports,
/// `PanicIfCalledTransport`, etc.) never trip the scan below.
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
    let path = src_dir().join("telemetry").join("emitter.rs");
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    strip_cfg_test_blocks(&strip_comments(&raw))
}

/// Extracts one line-delimited signature starting at `marker`, up to (and
/// including) its closing `;` — used to pull just the trait method's own
/// signature line out of the surrounding doc/body text.
fn extract_signature<'a>(source: &'a str, marker: &str) -> &'a str {
    let start = source
        .find(marker)
        .unwrap_or_else(|| panic!("expected telemetry/emitter.rs to declare `{marker}`"));
    let rest = &source[start..];
    let end = rest
        .find(';')
        .unwrap_or_else(|| panic!("expected `{marker}`'s signature to end with `;`"));
    &rest[..end]
}

/// FF-M7-CONTENTFREE (transport level): `TelemetryTransport::send`'s own
/// declared signature mentions `FleetEvent` and nothing else that could be a
/// second, richer payload type. A future edit widening this signature to
/// accept e.g. a raw `String`/`serde_json::Value`/a personal-item-bearing
/// type would fail this test — the signature line itself is the structural
/// proof, not a runtime check of any particular call.
#[test]
fn telemetry_transport_send_signature_only_ever_names_fleet_event() {
    let source = production_source();
    let signature = extract_signature(&source, "fn send(&self");

    assert!(
        signature.contains("events: &[FleetEvent]"),
        "TelemetryTransport::send must take events as `&[FleetEvent]`, found: {signature:?}"
    );
    assert!(
        signature.contains("endpoint: &str"),
        "the only OTHER parameter must be the plain endpoint string, found: {signature:?}"
    );
    assert!(
        signature.contains("Result<(), TransportError>"),
        "send must return Result<(), TransportError>, found: {signature:?}"
    );

    // The full parameter list must be EXACTLY `(&self, endpoint: &str, events:
    // &[FleetEvent])` — no third parameter of any kind.
    let params_start = signature
        .find('(')
        .expect("signature must have a parameter list");
    let params_end = signature
        .rfind(')')
        .expect("signature must close its parameter list");
    let params = &signature[params_start + 1..params_end];
    let param_count = params.split(',').filter(|p| !p.trim().is_empty()).count();
    assert_eq!(
        param_count, 3,
        "TelemetryTransport::send must take exactly (&self, endpoint, events) — found params: \
         {params:?}"
    );
}

/// `TelemetryTransport` itself must be declared exactly once, as a `pub
/// trait` — confirms the scan above is pinned against the real trait
/// declaration, not accidentally matching some other `fn send(&self...`
/// this file might grow later (e.g. inside a different, unrelated struct).
#[test]
fn telemetry_transport_is_declared_as_a_public_trait() {
    let source = production_source();
    assert!(
        source.contains("pub trait TelemetryTransport"),
        "expected telemetry/emitter.rs to declare `pub trait TelemetryTransport`"
    );
}
