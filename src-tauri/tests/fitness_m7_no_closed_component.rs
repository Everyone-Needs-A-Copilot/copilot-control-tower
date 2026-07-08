//! FF-M7-NO-CLOSED-COMPONENT (M7/S10, `scratchpad/qa-m7-acceptance.md` D1).
//! SOUL Founding Decision #1: this app is **pure OSS, no paid/closed/hosted/
//! proprietary component, ever** — openness IS the security guarantee (the
//! named anti-pattern this decision exists to prevent is the "Ledger"
//! precedent: a nominally-open project with a closed/hosted component that
//! quietly became the actual point of control). Every OTHER named M7 fitness
//! function (`fitness_m7_telemetry_schema_content_free.rs`,
//! `fitness_m7_telemetry_optin.rs`,
//! `fitness_m7_telemetry_transport_content_free.rs`,
//! `fitness_m7_two_of_n_signing.rs`) has a dedicated regression guard; this
//! invariant did not (M7 QA acceptance, D1) — it held today only by manual
//! grep. This file closes that gap.
//!
//! ## What this test DOES guarantee
//!
//! - `Cargo.toml` and `Cargo.lock` (direct AND transitive dependencies)
//!   introduce no crate whose exact name is on [`DENIED_DEPENDENCY_NAMES`] —
//!   a SMALL, NAMED, commented denylist of publicly-known closed/hosted-SaaS
//!   analytics/APM/error-tracking client crates (Sentry, Datadog, Segment,
//!   Mixpanel, etc.) plus Stripe (SOUL's own named paid/hosted vocabulary)
//!   and Firebase (a proprietary hosted backend). Matching is done by exact,
//!   word-tokenized crate name — not raw substring — specifically so it does
//!   NOT false-positive on an unrelated OSS crate that merely CONTAINS one of
//!   these words as a substring of a longer name (e.g. `unicode-segmentation`
//!   is not `segment`; see `the_scan_does_not_false_positive_on_a_similarly-
//!   named_oss_crate` below, a real regression this file's first draft would
//!   have introduced had it used naive substring matching).
//! - `src-tauri/src/telemetry/*.rs` imports none of those same names — i.e.
//!   the telemetry transport stays behind the generic, content-free
//!   `TelemetryTransport` trait (`telemetry::emitter`); nothing in that
//!   directory reaches for a concrete third-party analytics/hosted client
//!   directly.
//!
//! ## What this test does NOT guarantee (read before relying on it)
//!
//! - **This is a regression TRIPWIRE, not an exhaustive registry scan.** The
//!   denylist is a small, hand-maintained set of publicly-known closed/
//!   hosted-SaaS crate names — it cannot catch a closed/hosted dependency
//!   whose crate name doesn't happen to be on the list, a vendored/`git =`
//!   dependency under an unlisted name, or a closed component introduced
//!   some way OTHER than a Cargo dependency (e.g. a hand-rolled HTTP call to
//!   a paid API with no corresponding crate at all — that requires the doc/
//!   vocabulary grep this file's own predecessor QA pass did manually, which
//!   this test does not repeat).
//! - **A determined contributor can always widen or delete the denylist.**
//!   That's the deliberate design, not a hole: doing so is a small, visible,
//!   reviewable diff to a file named exactly `fitness_m7_no_closed_
//!   component.rs` — the same trust model every other fitness function in
//!   this crate already accepts (nothing here is un-editable; the point is
//!   that editing it is a LOUD, intentional, reviewable act, not a silent
//!   side effect of adding an unrelated dependency).
//! - It does not vet a dependency's LICENSE (MIT/Apache/GPL/etc.) — only
//!   whether its NAME matches a known closed/hosted-SaaS-client crate. A
//!   permissively-licensed crate that happens to be a thin client for a paid
//!   hosted service is exactly what this list targets; a copyleft-licensed
//!   but otherwise fully-OSS crate is out of scope here (a separate concern).

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

fn crate_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf()
}

fn read_to_string(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

/// Known closed/hosted-telemetry/analytics/proprietary crate names — a
/// SMALL, NAMED, COMMENTED tripwire (see this file's module doc for what it
/// does and does not guarantee), not an exhaustive registry scan. Each entry
/// names one publicly-known closed/hosted-SaaS-client crate whose mere
/// presence in this crate's dependency graph would be the Ledger anti-
/// pattern SOUL Founding Decision #1 exists to forbid.
const DENIED_DEPENDENCY_NAMES: &[&str] = &[
    "sentry",    // Sentry — hosted APM/error-tracking SaaS client
    "datadog",   // Datadog — hosted APM/metrics SaaS client
    "newrelic",  // New Relic — hosted APM SaaS client
    "segment",   // Segment.io — hosted customer-data/analytics SaaS client
    "mixpanel",  // Mixpanel — hosted product-analytics SaaS client
    "amplitude", // Amplitude — hosted product-analytics SaaS client
    "posthog",   // PostHog — ships a hosted-first client; excluded out of caution
    "bugsnag",   // Bugsnag — hosted error-tracking SaaS client
    "rollbar",   // Rollbar — hosted error-tracking SaaS client
    "honeycomb", // Honeycomb.io — hosted observability SaaS client
    "appsignal", // AppSignal — hosted APM SaaS client
    "firebase",  // Firebase — proprietary hosted backend platform
    "stripe",    // Stripe — paid/hosted billing SDK (SOUL's own named vocabulary)
];

/// Splits `s` on any non-alphanumeric byte and lowercases each piece — used
/// to turn a whole `Cargo.toml`/`Cargo.lock`/source file into a set of exact
/// word tokens, so the scan below can check for an EXACT denylisted crate
/// name rather than a raw substring (a raw substring check would false-
/// positive on e.g. `unicode-segmentation` merely containing `segment`).
fn tokenize(s: &str) -> HashSet<String> {
    s.split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|t| !t.is_empty())
        .map(|t| t.to_ascii_lowercase())
        .collect()
}

/// The actual scan logic, factored out so the mutation-check tests below can
/// exercise it against a FAKE fixture string without ever touching the real
/// `Cargo.toml`/`Cargo.lock` (a real denylisted dependency is never actually
/// added to this repo's manifest just to test this).
fn find_denied_dependency_names(manifest_or_lock_source: &str) -> Vec<&'static str> {
    let tokens = tokenize(manifest_or_lock_source);
    DENIED_DEPENDENCY_NAMES
        .iter()
        .copied()
        .filter(|needle| tokens.contains(*needle))
        .collect()
}

#[test]
fn cargo_toml_introduces_no_known_closed_or_hosted_dependency() {
    let path = crate_root().join("Cargo.toml");
    let source = read_to_string(&path);
    let hits = find_denied_dependency_names(&source);
    assert!(
        hits.is_empty(),
        "Cargo.toml names a denylisted closed/hosted/proprietary crate: {hits:?} — SOUL \
         Founding Decision #1 (pure OSS, no paid/closed/hosted/proprietary component) forbids \
         this. If this is a genuine false positive, resolve it in \
         DENIED_DEPENDENCY_NAMES/this test's own doc, not by deleting the assertion."
    );
}

#[test]
fn cargo_lock_introduces_no_known_closed_or_hosted_dependency() {
    let path = crate_root().join("Cargo.lock");
    if !path.exists() {
        // Cargo.lock's presence/generation is outside this test's control
        // (some workflows regenerate it on demand); if it's genuinely
        // absent, the Cargo.toml scan above is still authoritative. Skip
        // rather than fail on a file this test doesn't own the existence of.
        return;
    }
    let source = read_to_string(&path);
    let hits = find_denied_dependency_names(&source);
    assert!(
        hits.is_empty(),
        "Cargo.lock resolves a denylisted closed/hosted/proprietary crate: {hits:?} — even a \
         TRANSITIVE dependency on one of these would violate SOUL Founding Decision #1"
    );
}

/// Mutation check: proves the scan itself actually fires, against a FAKE
/// fixture string — never against the real `Cargo.toml`/`Cargo.lock`.
#[test]
fn the_scan_fires_on_a_fixture_containing_a_denied_dependency_name() {
    let fixture = "[dependencies]\nsentry = \"0.32\"\nserde = \"1\"\n";
    assert_eq!(
        find_denied_dependency_names(fixture),
        vec!["sentry"],
        "the denylist scan must fire on a fixture that names a known denylisted crate"
    );
}

/// The false-positive this file's naive first draft (raw substring match)
/// would have introduced: `unicode-segmentation` is a real, ordinary OSS
/// crate already transitively resolved in this crate's own `Cargo.lock` (see
/// the earlier `grep` this file's authoring session ran) — it must NEVER be
/// flagged just because its name contains the substring `segment`.
#[test]
fn the_scan_does_not_false_positive_on_a_similarly_named_oss_crate() {
    let fixture = "name = \"unicode-segmentation\"\nversion = \"1.0.0\"\n";
    assert!(
        find_denied_dependency_names(fixture).is_empty(),
        "unicode-segmentation must never be flagged merely for containing the substring \
         `segment` — the scan must match exact tokens, not raw substrings"
    );
}

#[test]
fn the_scan_does_not_false_positive_on_this_crates_own_ordinary_oss_dependencies() {
    let fixture = "[dependencies]\nserde = \"1\"\ntauri = \"2\"\nreqwest = \"0.13\"\nsha2 = \
                   \"0.10\"\nminisign-verify = \"0.2.5\"\n";
    assert!(find_denied_dependency_names(fixture).is_empty());
}

// -- telemetry transport source scan -----------------------------------------

fn telemetry_src_dir() -> PathBuf {
    crate_root().join("src").join("telemetry")
}

/// `telemetry/`'s only allowed egress point is the generic
/// `TelemetryTransport` trait (`telemetry::emitter`) — see `fitness_m7_
/// telemetry_transport_content_free.rs`, which already pins that trait's
/// signature. This scan is a DIFFERENT, complementary check: that no file in
/// the directory imports a concrete third-party hosted-analytics client by
/// name in the first place (the transport-content-free test would not catch
/// a hosted SDK import that never touches `send`'s own signature).
#[test]
fn telemetry_source_imports_no_hosted_analytics_sdk_by_name() {
    let dir = telemetry_src_dir();
    let entries = fs::read_dir(&dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display()));
    let mut checked_any = false;
    for entry in entries {
        let entry = entry.unwrap_or_else(|e| panic!("read_dir entry: {e}"));
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("rs") {
            continue;
        }
        checked_any = true;
        let source = read_to_string(&path);
        let hits = find_denied_dependency_names(&source);
        assert!(
            hits.is_empty(),
            "{} references a denylisted hosted-analytics-SDK name {hits:?} — telemetry/ must \
             stay behind the generic TelemetryTransport trait, never a direct third-party \
             client import",
            path.display()
        );
    }
    assert!(
        checked_any,
        "expected at least one .rs file in src/telemetry/ — the directory this test scans \
         appears to be empty or missing, which would make this test vacuously pass"
    );
}
