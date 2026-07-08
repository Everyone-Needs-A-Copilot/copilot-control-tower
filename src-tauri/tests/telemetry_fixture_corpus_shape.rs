//! Validates `fixtures/telemetry/*.json` (M7/S1, task 60) against
//! `telemetry::schema::FleetEvent`'s closed, content-free shape — the
//! outgoing-wire analog of `fixtures/validate.py`'s incoming `doctor`
//! corpus check, done in Rust (`cargo test` only, per this task's
//! constraints — no Python validator for an outgoing type nothing in this
//! app deserializes). `FleetEvent` is Serialize-only (mirrors
//! `routing::ItSignal`'s own precedent — an outbound safety/telemetry
//! payload this app constructs and sends, never parses back), so these
//! fixtures are validated as raw JSON shape/value checks rather than
//! round-tripped through a `Deserialize` impl.

use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;

fn fixtures_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures")
        .join("telemetry")
}

const EXPECTED_KEYS: &[&str] = &[
    "schema_version",
    "machine_id",
    "host",
    "status",
    "event_kind",
    "occurred_at",
    "escalate",
    "occurrence_count",
];

const KNOWN_HOSTS: &[&str] = &["claude-code", "codex"];

const KNOWN_STATUSES: &[&str] = &[
    "setup-needed",
    "it-config-incomplete",
    "healthy",
    "syncing",
    "update-available",
    "needs-attention",
    "signed-out",
    "offline",
    "waiting-for-network",
    "updating-app",
];

const KNOWN_KINDS: &[&str] = &[
    "status_change",
    "security_shadow_suspended",
    "held_major",
    "onboarding_stalled",
    "rollback",
    "revoked",
    "signature_failure",
    "policy_conflict",
    "persistence_disabled",
    "notifications_off",
    "deprovision_triggered",
];

fn load(name: &str) -> Value {
    let path = fixtures_dir().join(name);
    let raw = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_str(&raw).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
}

fn assert_matches_fleet_event_shape(name: &str, value: &Value) {
    let obj = value
        .as_object()
        .unwrap_or_else(|| panic!("{name}: not a JSON object"));

    let mut keys: Vec<&str> = obj.keys().map(String::as_str).collect();
    keys.sort_unstable();
    let mut expected = EXPECTED_KEYS.to_vec();
    expected.sort_unstable();
    assert_eq!(keys, expected, "{name}: unexpected key set");

    let host = value["host"]
        .as_str()
        .unwrap_or_else(|| panic!("{name}: host not a string"));
    assert!(KNOWN_HOSTS.contains(&host), "{name}: unknown host {host}");

    let status = value["status"]
        .as_str()
        .unwrap_or_else(|| panic!("{name}: status not a string"));
    assert!(
        KNOWN_STATUSES.contains(&status),
        "{name}: unknown status {status}"
    );

    let kind = value["event_kind"]
        .as_str()
        .unwrap_or_else(|| panic!("{name}: event_kind not a string"));
    assert!(
        KNOWN_KINDS.contains(&kind),
        "{name}: unknown event_kind {kind}"
    );

    assert_eq!(
        value["schema_version"], "1.0",
        "{name}: unexpected schema_version"
    );

    let machine_id = value["machine_id"]
        .as_str()
        .unwrap_or_else(|| panic!("{name}: machine_id not a string"));
    assert!(
        machine_id.starts_with("m-")
            && machine_id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-'),
        "{name}: machine_id `{machine_id}` doesn't look like a synthetic opaque id \
         (no personal name/hostname allowed in the fixture corpus)"
    );

    assert!(
        value["occurred_at"].as_str().is_some_and(|s| !s.is_empty()),
        "{name}: occurred_at missing/empty"
    );
    assert!(
        value["escalate"].is_boolean(),
        "{name}: escalate not a bool"
    );
    assert!(
        value["occurrence_count"].as_u64().is_some(),
        "{name}: occurrence_count not a non-negative integer"
    );

    // Belt-and-suspenders: no forbidden content-bearing key anywhere, even
    // one a hand-edited fixture might sneak in outside the expected set
    // (the `keys == expected` assertion above already catches this, this
    // just names the intent explicitly for a future fixture author).
    for forbidden in ["detail", "name", "path", "item", "layer", "identity", "org"] {
        assert!(
            !obj.contains_key(forbidden),
            "{name}: forbidden key `{forbidden}` present"
        );
    }
}

#[test]
fn status_change_fixture_matches_the_fleet_event_shape() {
    assert_matches_fleet_event_shape("status-change.json", &load("status-change.json"));
}

#[test]
fn security_shadow_fixture_matches_the_fleet_event_shape() {
    assert_matches_fleet_event_shape("security-shadow.json", &load("security-shadow.json"));
}

#[test]
fn onboarding_stalled_fixture_matches_the_fleet_event_shape() {
    assert_matches_fleet_event_shape("onboarding-stalled.json", &load("onboarding-stalled.json"));
}

#[test]
fn rollback_fixture_matches_the_fleet_event_shape() {
    assert_matches_fleet_event_shape("rollback.json", &load("rollback.json"));
}

#[test]
fn corpus_directory_has_exactly_the_four_expected_fixtures() {
    let mut names: Vec<String> = fs::read_dir(fixtures_dir())
        .expect("fixtures/telemetry must exist")
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    assert_eq!(
        names,
        vec![
            "onboarding-stalled.json",
            "rollback.json",
            "security-shadow.json",
            "status-change.json",
        ]
    );
}
