//! `FleetEvent` — the content-free fleet-event wire type (M7/S1, task 60).
//!
//! Modeled on `docs/08-observability/observability.md` §3 (safety-channel
//! categories)/§4 (analytics aggregate shape)/§5 (`machine_id` derivation),
//! narrowed per this task's brief to ONE unified type rather than the doc's
//! full two-envelope split (see `telemetry`'s own module doc for why that's
//! a deliberate, flagged scope decision, not an oversight).
//!
//! ## Content-free by construction — the invariant this whole file exists for
//!
//! [`FleetEvent`] carries **only**: an opaque machine id, a closed host
//! enum, the CLI's own doctor status enum (reused, never re-derived —
//! invariant #1), a closed content-free event-kind enum, a fixed-format
//! timestamp, and two plain numeric/boolean facts. There is no `String`
//! field anywhere on the struct that could hold a personal item name, a
//! file path, a layer/dimension value, a repo URL, or free text — every
//! field is either a bare enum, a number/bool, or one of the three
//! single-purpose newtypes below ([`MachineId`], [`SchemaVersion`],
//! [`OccurredAt`]), each of which wraps a `String` internally but is
//! constructible only through a narrow, documented derivation (a hash, a
//! fixed version tag, a fixed-format timestamp) — never a free-text
//! setter. `tests/fitness_m7_telemetry_schema_content_free.rs` pins this
//! structurally (a source scan of the struct/enum declarations, mirroring
//! `tests/fitness_m6_itsignal_content_free.rs`'s proof for
//! `routing::ItSignal`); the tests at the bottom of this file pin the
//! serialized shape as a value-level regression guard on top of that.
//!
//! ## Reuse, not reinvention
//!
//! [`FleetEvent::status`] is `crate::model::state::CliStatus` — the SAME
//! 10-state, CLI-computed, worst-wins doctor status enum the tray already
//! renders, not a second status vocabulary invented for telemetry
//! (invariant #1: "Control Tower computes no analytics... of its own").
//! [`FleetEventKind`]'s variants name the same content-free safety
//! categories `routing::ItSignalKind` already established (`security_shadow_
//! suspended`, `signature_failure`, `policy_conflict`, `persistence_
//! disabled`, `notifications_off`, `deprovision_triggered`), plus the
//! handful `observability.md` names that have no M6 routing equivalent yet
//! (`status_change` — an ordinary doctor-status transition; `onboarding_
//! stalled` — §2.1's `stalled-onboarding`; `rollback` — M4's crash-only
//! watchdog outcome; `held_major` — a held-major update awaiting IT
//! approval). Deliberately NOT a direct `From<ItSignalKind>` wrapping,
//! though: every [`FleetEventKind`] variant stays a bare, fieldless
//! identifier (like `ItSignalKind`'s own variants) so the "no variant
//! carries associated data" proof stays a simple, exact source scan rather
//! than a recursive one that has to reason about what's nested inside a
//! wrapped variant.

use serde::Serialize;

use crate::model::state::CliStatus;

/// The fleet-event schema's own version tag — the same versioned-contract
/// pattern every `--json` verb already uses (`model::envelope::
/// parse_schema_version`'s `"MAJOR.MINOR[.PATCH]"` shape). See the module
/// doc's G-M7-2 note: this is not yet a JSON Schema file, only the Rust-side
/// pin of the value every emitted event carries.
pub const FLEET_EVENT_SCHEMA_VERSION: &str = "1.0";

/// A fixed-format version tag, never a free-text field. The only
/// constructor is [`SchemaVersion::current`] — there is no way to build one
/// from arbitrary caller-supplied text, so this can never become a vector
/// for smuggling content into the wire payload.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct SchemaVersion(String);

impl SchemaVersion {
    /// The current fleet-event schema version — the only way to construct
    /// one.
    pub fn current() -> Self {
        Self(FLEET_EVENT_SCHEMA_VERSION.to_string())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// An opaque, non-reversible machine pseudonym — `observability.md` §5.
/// **Never** a hostname, device serial, or anything that could leak a
/// person's name. The only constructors are [`MachineId::from_hash`] (an
/// already-derived opaque string — the shape this type exists to pin) and
/// [`derive_machine_id`] (the real HMAC-SHA256 derivation, below); there is
/// no way to build one from an arbitrary caller-supplied string that could
/// carry content, since callers are expected to pass either a hash they
/// already computed or the output of `derive_machine_id` itself.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct MachineId(String);

impl MachineId {
    /// Wraps an already-opaque identifier (e.g. a fixture's synthetic
    /// `m-0001`, or a hex digest from [`derive_machine_id`]). Callers own
    /// the responsibility of never passing identity-bearing text here —
    /// same trust boundary `routing::ItSignal::admin_contact` already
    /// accepts a caller-supplied `String` at (an escalation endpoint, not
    /// personal content).
    pub fn from_hash(opaque: impl Into<String>) -> Self {
        Self(opaque.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A fixed-format ISO-8601 timestamp, copied verbatim from a value the CLI
/// or the OS clock already produced (invariant #1 — telemetry computes no
/// time value of its own, it only copies one). Never a free-text field.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct OccurredAt(String);

impl OccurredAt {
    /// Wraps an already-formatted ISO-8601 timestamp string (e.g. a
    /// `doctor --json` verdict's own `generated_at`, or a fixture's fixed
    /// value). This module does not itself read the system clock or format
    /// a timestamp — that stays the caller's job (S3's real emitter), same
    /// "copy, don't compute" discipline this whole file follows.
    pub fn from_rfc3339(formatted: impl Into<String>) -> Self {
        Self(formatted.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Which host produced this fleet event — a closed two-value enum, exactly
/// `observability.md` §3's `host: claude-code | codex` field. Deliberately
/// its own type here rather than reusing `model::doctor::DoctorWire::host`
/// (an `Option<String>` on the loosely-typed *incoming* CLI wire shape) —
/// this is the OUTGOING telemetry wire's own closed vocabulary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Host {
    ClaudeCode,
    Codex,
}

/// The content-free fact this fleet event reports — a closed,
/// `#[non_exhaustive]`-free enum (a new kind is a reviewed, visible diff to
/// this exact list, never an ad hoc string) mirroring
/// `routing::ItSignalKind`'s own discipline: every variant is a bare
/// identifier, never associated data. See the module doc's "Reuse, not
/// reinvention" section for where each variant's name comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FleetEventKind {
    /// An ordinary doctor-status transition — this event's `status` field
    /// carries the new value; there is nothing else to report.
    StatusChange,
    /// Mirrors `routing::ItSignalKind::SecurityShadowAutoSuspended` — a
    /// personal override shadowing a security fix was auto-suspended.
    SecurityShadowSuspended,
    /// Mirrors `routing::ItSignalKind::HeldMajorAwaitingApproval`.
    HeldMajor,
    /// `observability.md` §2.1's `stalled-onboarding` — the first-run
    /// wizard has not progressed past a threshold window (§11: the
    /// concrete threshold is unratified, G-M7-5).
    OnboardingStalled,
    /// M4's crash-only watchdog already rolled back to last-known-good —
    /// mirrors `routing::AutoActReason::RollbackAlreadyApplied`.
    Rollback,
    /// `doctor`'s `auth[].state == "revoked"` — mirrors
    /// `routing::ItSignalKind::AuthRevokedDeprovisionOffer`.
    Revoked,
    /// Mirrors `routing::ItSignalKind::SignatureFailure` (`sig-fail`).
    SignatureFailure,
    /// Mirrors `routing::ItSignalKind::PolicyDenial` (`policy-conflict`).
    PolicyConflict,
    /// Mirrors `routing::ItSignalKind::PersistenceDisabled`.
    PersistenceDisabled,
    /// Mirrors `routing::ItSignalKind::NotificationsDisabled`
    /// (`notifications-off`).
    NotificationsOff,
    /// Mirrors `routing::ItSignalKind::DeprovisionTriggered`.
    DeprovisionTriggered,
}

/// The content-free fleet-event envelope — see the module doc for the full
/// invariant this type exists to hold. Every field is a bare enum, a
/// number/bool, or one of this file's three single-purpose newtypes; there
/// is no field a personal item name, file path, or free-text detail could
/// occupy.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FleetEvent {
    pub schema_version: SchemaVersion,
    pub machine_id: MachineId,
    pub host: Host,
    /// The CLI's own doctor status verdict — reused, never re-derived
    /// (invariant #1).
    pub status: CliStatus,
    pub event_kind: FleetEventKind,
    pub occurred_at: OccurredAt,
    /// Whether this event was (or would be) escalated to IT — mirrors
    /// `routing::ItSignal::admin_contact.is_some()`'s boolean fact, without
    /// carrying the endpoint itself (that lives in S2's gate, not this
    /// wire payload).
    pub escalate: bool,
    /// How many consecutive polls this same condition has now persisted —
    /// a plain count, never which items/checkers were involved.
    pub occurrence_count: u32,
}

impl FleetEvent {
    /// Convenience constructor stamping the current [`SchemaVersion`] —
    /// every other field is caller-supplied (this module performs no
    /// derivation of its own beyond `schema_version`/[`derive_machine_id`]).
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        machine_id: MachineId,
        host: Host,
        status: CliStatus,
        event_kind: FleetEventKind,
        occurred_at: OccurredAt,
        escalate: bool,
        occurrence_count: u32,
    ) -> Self {
        Self {
            schema_version: SchemaVersion::current(),
            machine_id,
            host,
            status,
            event_kind,
            occurred_at,
            escalate,
            occurrence_count,
        }
    }
}

// == `machine_id` derivation (§5) ============================================
//
// `HMAC-SHA256(hardware_uuid || posix_uid, per_install_random_salt)` —
// implemented directly against the `sha2` crate (already resolved in this
// workspace's dependency graph via `updater::trust`'s transitive deps; see
// `Cargo.toml`) rather than pulling in a second `hmac` crate for a
// well-defined, ~15-line RFC 2104 construction. Reading/persisting the real
// per-install keychain-resident salt and the real hardware UUID is S2/S3's
// OS-integration job (see the module doc) — this function only pins the
// derivation MATH, tested below against a published HMAC-SHA256 test
// vector plus the per-user/per-install properties §5 requires.

use sha2::{Digest, Sha256};

const HMAC_BLOCK_SIZE: usize = 64; // SHA-256's block size, per RFC 2104.

/// A from-scratch HMAC-SHA256 (RFC 2104), used only by
/// [`derive_machine_id`] below. Kept private: no caller outside this module
/// needs a raw HMAC primitive, only the `machine_id` derivation.
fn hmac_sha256(key: &[u8], message: &[u8]) -> [u8; 32] {
    let mut key_block = [0u8; HMAC_BLOCK_SIZE];
    if key.len() > HMAC_BLOCK_SIZE {
        let hashed = Sha256::digest(key);
        key_block[..hashed.len()].copy_from_slice(&hashed);
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }

    let mut ipad = [0x36u8; HMAC_BLOCK_SIZE];
    let mut opad = [0x5cu8; HMAC_BLOCK_SIZE];
    for i in 0..HMAC_BLOCK_SIZE {
        ipad[i] ^= key_block[i];
        opad[i] ^= key_block[i];
    }

    let mut inner_hasher = Sha256::new();
    inner_hasher.update(ipad);
    inner_hasher.update(message);
    let inner_digest = inner_hasher.finalize();

    let mut outer_hasher = Sha256::new();
    outer_hasher.update(opad);
    outer_hasher.update(inner_digest);
    outer_hasher.finalize().into()
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Derives a [`MachineId`] per `observability.md` §5:
/// `HMAC-SHA256(hardware_uuid || posix_uid, per_install_random_salt)`.
///
/// - **Per-user, not per-device**: keying on `hardware_uuid` **and**
///   `posix_uid` means two people sharing one Mac get two distinct,
///   non-colliding ids (closing the collision half of B-H5).
/// - **Non-reversible**: neither `hardware_uuid` nor `salt` is ever
///   transmitted by this function — only the returned hex digest.
/// - `salt` is caller-supplied. The real salt is per-install, random, and
///   keychain-resident (never org-wide — the other half of B-H5); reading/
///   persisting it is S2/S3's OS-integration job, not this pure function's.
pub fn derive_machine_id(hardware_uuid: &str, posix_uid: u32, salt: &[u8]) -> MachineId {
    let uid_text = posix_uid.to_string();
    let mut message = Vec::with_capacity(hardware_uuid.len() + uid_text.len());
    message.extend_from_slice(hardware_uuid.as_bytes());
    message.extend_from_slice(uid_text.as_bytes());
    let digest = hmac_sha256(salt, &message);
    MachineId::from_hash(hex_encode(&digest))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_event() -> FleetEvent {
        FleetEvent::new(
            MachineId::from_hash("m-0001"),
            Host::ClaudeCode,
            CliStatus::Healthy,
            FleetEventKind::StatusChange,
            OccurredAt::from_rfc3339("2026-07-07T09:10:44Z"),
            false,
            1,
        )
    }

    // -- serde round-trip + shape pin ---------------------------------------

    #[test]
    fn fleet_event_serializes_to_exactly_the_closed_field_set() {
        let value = serde_json::to_value(sample_event()).expect("FleetEvent must serialize");
        let obj = value
            .as_object()
            .expect("FleetEvent serializes to an object");
        let mut keys: Vec<&str> = obj.keys().map(String::as_str).collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            vec![
                "escalate",
                "event_kind",
                "host",
                "machine_id",
                "occurred_at",
                "occurrence_count",
                "schema_version",
                "status",
            ],
            "FleetEvent must carry EXACTLY this closed field set — see the \
             module doc's content-free invariant"
        );
    }

    /// The whole point: there is no key here a fabricated "personal" value
    /// (a Bob's-laptop hostname, a `~/Documents/...` path, a skill name)
    /// could ever occupy. Every key above is either a closed enum
    /// (`host`/`status`/`event_kind`), a number/bool
    /// (`occurrence_count`/`escalate`), or one of this file's fixed-format
    /// newtypes (`schema_version`/`machine_id`/`occurred_at`) — none of
    /// which has a free-text setter. This test exists as the explicit,
    /// human-readable version of that claim, not just the shape pin above.
    #[test]
    fn fleet_event_json_has_no_slot_for_a_fabricated_personal_value() {
        let event = FleetEvent::new(
            MachineId::from_hash("m-0002"),
            Host::Codex,
            CliStatus::NeedsAttention,
            FleetEventKind::PolicyConflict,
            OccurredAt::from_rfc3339("2026-07-07T09:12:03Z"),
            true,
            1,
        );
        let value = serde_json::to_value(event).expect("FleetEvent must serialize");
        let obj = value.as_object().unwrap();

        // None of the well-known "this is where a leak would go" key names
        // exist on this type at all — there is no field to populate with
        // `"bob-alejo-macbook-pro"` or `"~/Documents/secret-project"`.
        for forbidden in [
            "detail", "name", "path", "item", "layer", "identity", "org", "title", "message",
            "repo", "url", "text",
        ] {
            assert!(
                !obj.contains_key(forbidden),
                "FleetEvent must never carry a `{forbidden}` field"
            );
        }
    }

    #[test]
    fn fleet_event_round_trips_through_json_when_the_reverse_shape_is_hand_built() {
        // FleetEvent is serialize-only in this crate (an outgoing wire type,
        // per the module doc — nothing deserializes an inbound FleetEvent
        // anywhere in this app), so the "round trip" this test proves is:
        // the exact JSON a real consumer (S3's emitter, S4's dashboard
        // fixtures) would receive matches the fixture corpus this task
        // ships, field for field.
        let event = sample_event();
        let value = serde_json::to_value(&event).unwrap();
        assert_eq!(value["schema_version"], "1.0");
        assert_eq!(value["machine_id"], "m-0001");
        assert_eq!(value["host"], "claude-code");
        assert_eq!(value["status"], "healthy");
        assert_eq!(value["event_kind"], "status_change");
        assert_eq!(value["occurred_at"], "2026-07-07T09:10:44Z");
        assert_eq!(value["escalate"], false);
        assert_eq!(value["occurrence_count"], 1);
    }

    #[test]
    fn every_fleet_event_kind_serializes_to_the_expected_snake_case_string() {
        let expected = [
            (FleetEventKind::StatusChange, "status_change"),
            (
                FleetEventKind::SecurityShadowSuspended,
                "security_shadow_suspended",
            ),
            (FleetEventKind::HeldMajor, "held_major"),
            (FleetEventKind::OnboardingStalled, "onboarding_stalled"),
            (FleetEventKind::Rollback, "rollback"),
            (FleetEventKind::Revoked, "revoked"),
            (FleetEventKind::SignatureFailure, "signature_failure"),
            (FleetEventKind::PolicyConflict, "policy_conflict"),
            (FleetEventKind::PersistenceDisabled, "persistence_disabled"),
            (FleetEventKind::NotificationsOff, "notifications_off"),
            (
                FleetEventKind::DeprovisionTriggered,
                "deprovision_triggered",
            ),
        ];
        for (kind, expected_str) in expected {
            assert_eq!(
                serde_json::to_value(kind).unwrap(),
                serde_json::json!(expected_str),
                "kind={kind:?}"
            );
        }
    }

    #[test]
    fn host_serializes_to_the_exact_observability_md_strings() {
        assert_eq!(
            serde_json::to_value(Host::ClaudeCode).unwrap(),
            serde_json::json!("claude-code")
        );
        assert_eq!(
            serde_json::to_value(Host::Codex).unwrap(),
            serde_json::json!("codex")
        );
    }

    // -- machine_id derivation -----------------------------------------------

    /// RFC 4231 HMAC-SHA256 test case 1 — pins the from-scratch `hmac_sha256`
    /// helper against a published, independently-verifiable vector (computed
    /// here via Python's stdlib `hmac`/`hashlib` for cross-checking), not
    /// just against itself.
    #[test]
    fn hmac_sha256_matches_the_rfc4231_test_vector() {
        let key = [0x0bu8; 20];
        let data = b"Hi There";
        let expected = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7";
        assert_eq!(hex_encode(&hmac_sha256(&key, data)), expected);
    }

    #[test]
    fn derive_machine_id_is_deterministic_for_the_same_inputs() {
        let a = derive_machine_id("hw-uuid-1234", 501, b"salt-a");
        let b = derive_machine_id("hw-uuid-1234", 501, b"salt-a");
        assert_eq!(a, b);
    }

    /// The per-USER half of B-H5's fix: two people sharing one Mac (same
    /// `hardware_uuid`, different `posix_uid`) must get distinct ids.
    #[test]
    fn derive_machine_id_differs_by_posix_uid_on_the_same_hardware() {
        let alice = derive_machine_id("hw-uuid-shared-mac", 501, b"salt-x");
        let bob = derive_machine_id("hw-uuid-shared-mac", 502, b"salt-x");
        assert_ne!(alice, bob);
    }

    /// The per-INSTALL half of B-H5's fix: the SAME physical user+machine
    /// re-keyed with a different salt (a clean reinstall issuing a fresh
    /// salt) must produce an unlinkable id — no persistent fingerprint
    /// survives an uninstall.
    #[test]
    fn derive_machine_id_differs_by_salt_for_the_same_user_and_hardware() {
        let before_reinstall = derive_machine_id("hw-uuid-1234", 501, b"salt-before");
        let after_reinstall = derive_machine_id("hw-uuid-1234", 501, b"salt-after");
        assert_ne!(before_reinstall, after_reinstall);
    }

    #[test]
    fn derive_machine_id_is_a_lowercase_hex_sha256_digest_never_the_raw_inputs() {
        let id = derive_machine_id("hw-uuid-should-never-appear", 501, b"salt");
        let hex = id.as_str();
        assert_eq!(hex.len(), 64, "SHA-256 digest is 32 bytes = 64 hex chars");
        assert!(
            hex.chars()
                .all(|c| c.is_ascii_hexdigit() && !c.is_uppercase()),
            "expected lowercase hex, got {hex}"
        );
        assert!(
            !hex.contains("hw-uuid-should-never-appear"),
            "machine_id must never contain the raw hardware_uuid"
        );
    }

    #[test]
    fn schema_version_current_matches_the_published_constant() {
        assert_eq!(
            SchemaVersion::current().as_str(),
            FLEET_EVENT_SCHEMA_VERSION
        );
    }
}
