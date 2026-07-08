//! Wire-format serde structs + the parse boundary for `cc deprovision <org>
//! --json`, mirroring `docs/01-architecture/schemas/deprovision.schema.json`
//! exactly (M5/S2, `.copilot/wp/30.md`).
//!
//! Same two-layer split `model::doctor`/`model::state` already established
//! for the doctor verb, collapsed into one file because the deprovision
//! shape is small (4 top-level fields, no nested checker/auth arrays):
//!
//! - The **wire layer** (`DeprovisionWire`/`RemovedWire`): every field is
//!   `Option`, deliberately, even the schema's `required` ones — see
//!   `model::doctor`'s module doc for why (so a missing-field parse failure
//!   is differentiable from "not JSON at all", one layer up).
//! - The **domain layer** (`DeprovisionResult`/`DeprovisionVerdict`/
//!   `DeprovisionUnreadableReason`/`DeprovisionParseOutcome`) plus the parse
//!   boundary itself, `parse_deprovision_body`.
//!
//! ## THE PARSE BOUNDARY (invariant #1 — "parse, never compute")
//!
//! `parse_deprovision_body` is the ONLY place a `DeprovisionVerdict` is ever
//! constructed. It performs ZERO wipe/retain/removal logic of its own — the
//! CLI already computed and PERFORMED the deprovision before this function
//! ever runs; this function only decides whether the CLI's already-final
//! report can be trusted enough to render. `deprovision::render` (one layer
//! up) may only MAP this decision to display copy — see
//! `tests/fitness_m5_no_wipe_logic.rs` (FF-M5-2), which source-scans this
//! file and the `deprovision/` module for any filesystem-deletion or
//! `git clean|reset|rm|checkout` primitive and asserts none exist.
//!
//! ## Fail-closed philosophy (this verb's own twist on it)
//!
//! Every structurally-absent required field (`schema_version`/`result`/
//! `removed.materialized`/`removed.clones`/`retained_dirty`) fails the whole
//! body closed to `ParseError` — there is no partial trust of a body that
//! doesn't match its own contract.
//!
//! `secrets_touched` gets a DIFFERENT, stricter treatment than an ordinary
//! missing field: this is the one field the schema itself says `MUST be 0`
//! (`deprovision.schema.json`'s `const: 0`), so its structural ABSENCE fails
//! closed to `MissingSecurityField` (mirroring `model::state`'s treatment of
//! `severity`/`destructive`/`identity`/`scope`/`state` — a missing
//! security-relevant field is never defaulted to "safe"). Its PRESENCE with
//! a nonzero value is deliberately **not** an unreadable/rejected body at
//! all — a `secrets_touched: 1` body still parses to `Trusted`, carrying the
//! real count, so `deprovision::render` can surface the loud, honest alarm
//! invariant #6 demands. Collapsing a nonzero `secrets_touched` to
//! `Unreadable` would DELETE the very information ("a secret was touched")
//! the alarm exists to surface — the worse failure mode here is silence, not
//! an untrusted parse.
//!
//! An unrecognized `result` string (present, but not one of `wiped`/
//! `partial`/`noop`) fails closed to `InvalidContent` — same treatment
//! `model::state::parse_cli_status` gives an unrecognized `status` string.
//! This is the concrete mechanism behind this task's "unknown result => not
//! a clean success, never a fabricated 'wiped cleanly'" requirement: an
//! `Unreadable` outcome can never render as `Wiped`.

use crate::model::envelope;
use serde::{Deserialize, Serialize};

/// The raw wire shape of a `deprovision --json` body. Every field is
/// `Option`, deliberately — see the module doc.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeprovisionWire {
    pub schema_version: Option<String>,
    pub result: Option<String>,
    pub removed: Option<RemovedWire>,
    pub retained_dirty: Option<Vec<String>>,
    pub secrets_touched: Option<i64>,
}

/// `removed`'s nested shape. `materialized` is a signed integer on the wire
/// side deliberately (never `u64`) so a negative count — itself impossible
/// content, since a count can't be negative — is representable and
/// rejectable, rather than failing generic JSON deserialization before this
/// module gets a chance to report *which* field was the problem.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RemovedWire {
    pub materialized: Option<i64>,
    pub clones: Option<Vec<String>>,
}

/// The 3 CLI-emitted result values, mapped 1:1 from `deprovision.result`
/// (ADR-M1-001-style lookup — never a computation).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeprovisionResult {
    Wiped,
    Partial,
    Noop,
}

/// Maps a wire `result` string to `DeprovisionResult` — a 1:1 lookup, never
/// a computation. An unrecognized string is content this app cannot trust;
/// the caller routes that to `DeprovisionUnreadableReason::InvalidContent`,
/// never to a guessed result (see the module doc's "unknown result" note).
fn parse_result(raw: &str) -> Option<DeprovisionResult> {
    match raw {
        "wiped" => Some(DeprovisionResult::Wiped),
        "partial" => Some(DeprovisionResult::Partial),
        "noop" => Some(DeprovisionResult::Noop),
        _ => None,
    }
}

/// The APP-OWNED reason a `deprovision --json` body could not be trusted.
/// Never a value the CLI emits itself. See the module doc for exactly which
/// condition maps to which variant.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeprovisionUnreadableReason {
    /// The CLI could not be spawned/reached at all, or exited abnormally —
    /// chosen by `deprovision::run_deprovision` (the spawn boundary), never
    /// by this file. Included here (rather than as a second enum) so
    /// `deprovision::render` has exactly one reason type to map, matching
    /// `model::state::CliUnreadableReason`'s shape.
    IoError,
    /// Not JSON at all, or a required field is structurally absent.
    ParseError,
    /// `schema_version` unparseable or outside the supported range, either
    /// direction — as fatal as `model::state`'s identical check.
    SchemaOutOfRange,
    /// `secrets_touched` is structurally absent — the one field the schema
    /// says MUST be present and MUST be 0; its absence is never treated as
    /// "assume 0 and move on".
    MissingSecurityField,
    /// `result` is present but not one of `wiped`/`partial`/`noop` — content
    /// that parses but isn't trustworthy.
    InvalidContent,
}

/// One fully-validated, trustworthy `deprovision --json` report — everything
/// `deprovision::render` needs, with every fail-closed gate already applied.
/// There is no path to construct this type except `parse_deprovision_body`
/// returning `DeprovisionParseOutcome::Trusted`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeprovisionVerdict {
    pub result: DeprovisionResult,
    /// G-M5-4: `removed.materialized`'s exact count semantics are undefined
    /// even upstream. Carried through as a bare, non-negative count — never
    /// interpreted as "files" or "trees" here or downstream.
    pub removed_materialized: u64,
    pub removed_clones: Vec<String>,
    /// Dirty/human-owned working trees the CLI preserved, never destroyed
    /// (invariant #3). May legitimately be empty (no dirty tree was in the
    /// way) — that is itself honest information, not an omission.
    pub retained_dirty: Vec<String>,
    /// MUST be `0` per the schema's `const: 0`. A nonzero value here is not
    /// a parse failure — it is real, trusted content that
    /// `deprovision::render` must surface as a loud alarm (invariant #6).
    pub secrets_touched: u64,
}

/// The result of attempting to parse+trust a raw `deprovision --json` body.
/// The parse-never-compute boundary as a *type*: no third variant, and
/// nothing downstream re-derives a result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeprovisionParseOutcome {
    Trusted(DeprovisionVerdict),
    Unreadable(DeprovisionUnreadableReason),
}

/// THE parse boundary (invariant #1). Never called with a raw process exit
/// code — spawn-level I/O failure is `deprovision::run_deprovision`'s job
/// (it maps directly to `DeprovisionUnreadableReason::IoError` without ever
/// calling this function); this function only ever sees a body that was
/// actually printed.
pub fn parse_deprovision_body(raw: &[u8]) -> DeprovisionParseOutcome {
    let text = match std::str::from_utf8(raw) {
        Ok(t) => t,
        Err(_) => {
            return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        }
    };

    let wire: DeprovisionWire = match serde_json::from_str(text) {
        Ok(w) => w,
        Err(_) => {
            return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        }
    };

    let schema_version = match wire.schema_version.as_deref() {
        Some(v) => v,
        None => {
            return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        }
    };
    let parsed_version = match envelope::parse_schema_version(schema_version) {
        Some(v) => v,
        None => {
            return DeprovisionParseOutcome::Unreadable(
                DeprovisionUnreadableReason::SchemaOutOfRange,
            )
        }
    };
    if !envelope::schema_version_in_range(parsed_version) {
        return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::SchemaOutOfRange);
    }

    let raw_result = match wire.result.as_deref() {
        Some(r) => r,
        None => {
            return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        }
    };
    let result = match parse_result(raw_result) {
        Some(r) => r,
        None => {
            return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::InvalidContent)
        }
    };

    let removed = match wire.removed {
        Some(r) => r,
        None => {
            return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        }
    };
    let removed_materialized = match removed.materialized {
        Some(m) if m >= 0 => m as u64,
        // Absent, or negative (a count can never be negative) — both are
        // exactly as untrustworthy; G-M5-4 leaves the semantics open, but "a
        // non-negative count" is the one thing this app CAN verify.
        _ => return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError),
    };
    let removed_clones = match removed.clones {
        Some(c) => c,
        None => {
            return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        }
    };

    let retained_dirty = match wire.retained_dirty {
        Some(d) => d,
        None => {
            return DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        }
    };

    // `secrets_touched` — see the module doc's "fail-closed philosophy"
    // section for why structurally-absent and negative both fail the whole
    // body closed, while present-and-nonzero does NOT (it becomes an alarmed
    // Trusted verdict, not an Unreadable one).
    let secrets_touched = match wire.secrets_touched {
        Some(s) if s >= 0 => s as u64,
        Some(_) | None => {
            return DeprovisionParseOutcome::Unreadable(
                DeprovisionUnreadableReason::MissingSecurityField,
            )
        }
    };

    DeprovisionParseOutcome::Trusted(DeprovisionVerdict {
        result,
        removed_materialized,
        removed_clones,
        retained_dirty,
        secrets_touched,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn corpus(name: &str) -> DeprovisionParseOutcome {
        let path = format!(
            "{}/fixtures/deprovision/corpus/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_deprovision_body(&raw)
    }

    fn invalid(name: &str) -> DeprovisionParseOutcome {
        let path = format!(
            "{}/fixtures/deprovision/invalid/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_deprovision_body(&raw)
    }

    #[test]
    fn wiped_clean_fixture_parses_trusted_with_zero_secrets_touched_and_a_retained_tree() {
        match corpus("wiped-clean") {
            DeprovisionParseOutcome::Trusted(v) => {
                assert_eq!(v.result, DeprovisionResult::Wiped);
                assert_eq!(v.secrets_touched, 0);
                assert!(!v.retained_dirty.is_empty());
            }
            other => panic!("expected Trusted, got {other:?}"),
        }
    }

    #[test]
    fn partial_fixture_parses_trusted() {
        match corpus("partial") {
            DeprovisionParseOutcome::Trusted(v) => assert_eq!(v.result, DeprovisionResult::Partial),
            other => panic!("expected Trusted, got {other:?}"),
        }
    }

    #[test]
    fn noop_fixture_parses_trusted_with_nothing_removed() {
        match corpus("noop") {
            DeprovisionParseOutcome::Trusted(v) => {
                assert_eq!(v.result, DeprovisionResult::Noop);
                assert_eq!(v.removed_materialized, 0);
                assert!(v.removed_clones.is_empty());
            }
            other => panic!("expected Trusted, got {other:?}"),
        }
    }

    /// The adversarial secrets_touched=1 fixture is NOT rejected — it is
    /// real, trusted content the render layer must alarm on. Collapsing this
    /// to Unreadable would hide the exact fact invariant #6 needs surfaced.
    #[test]
    fn secrets_touched_nonzero_fixture_still_parses_trusted_carrying_the_real_count() {
        match corpus("secrets-touched-alarm") {
            DeprovisionParseOutcome::Trusted(v) => {
                assert_eq!(v.secrets_touched, 1);
            }
            other => {
                panic!("expected Trusted (adversarial content, not a parse failure), got {other:?}")
            }
        }
    }

    #[test]
    fn malformed_json_fails_closed_to_parse_error_never_a_fabricated_wipe() {
        assert!(matches!(
            invalid("malformed"),
            DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn missing_secrets_touched_fails_closed_to_missing_security_field() {
        assert!(matches!(
            invalid("missing-secrets-touched"),
            DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::MissingSecurityField)
        ));
    }

    #[test]
    fn unknown_result_value_fails_closed_to_invalid_content_never_wiped() {
        assert!(matches!(
            invalid("unknown-result"),
            DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::InvalidContent)
        ));
    }

    #[test]
    fn schema_version_above_max_fails_closed() {
        assert!(matches!(
            invalid("schema-version-above-max"),
            DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::SchemaOutOfRange)
        ));
    }

    #[test]
    fn every_invalid_fixture_is_unreadable_never_trusted_as_wiped() {
        for name in [
            "malformed",
            "missing-secrets-touched",
            "unknown-result",
            "schema-version-above-max",
        ] {
            match invalid(name) {
                DeprovisionParseOutcome::Unreadable(_) => {}
                DeprovisionParseOutcome::Trusted(v) => {
                    panic!("fixture {name} must be Unreadable, got Trusted({v:?})")
                }
            }
        }
    }

    #[test]
    fn non_utf8_bytes_are_a_parse_error() {
        let raw: &[u8] = &[0xff, 0xfe, 0x00, 0x01];
        assert!(matches!(
            parse_deprovision_body(raw),
            DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn empty_body_is_a_parse_error() {
        assert!(matches!(
            parse_deprovision_body(b""),
            DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn negative_materialized_count_fails_closed() {
        let raw = br#"{
            "schema_version": "1.0",
            "result": "wiped",
            "removed": { "materialized": -1, "clones": [] },
            "retained_dirty": [],
            "secrets_touched": 0
        }"#;
        assert!(matches!(
            parse_deprovision_body(raw),
            DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn negative_secrets_touched_fails_closed_to_missing_security_field() {
        let raw = br#"{
            "schema_version": "1.0",
            "result": "wiped",
            "removed": { "materialized": 0, "clones": [] },
            "retained_dirty": [],
            "secrets_touched": -1
        }"#;
        assert!(matches!(
            parse_deprovision_body(raw),
            DeprovisionParseOutcome::Unreadable(DeprovisionUnreadableReason::MissingSecurityField)
        ));
    }
}
