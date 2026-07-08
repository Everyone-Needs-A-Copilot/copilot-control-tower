//! Wire-format serde structs + the parse boundary for `copilot update --json`,
//! mirroring `docs/01-architecture/schemas/update.schema.json` exactly (M6/S1,
//! `.copilot/wp/37.md`, task 52). This is the router's (M6/S2) PRIMARY input —
//! before this file, no `update --json` parse model existed at all
//! (`updater/dto.rs` is the UNRELATED Tauri self-update DTO).
//!
//! Same two-layer split `model::doctor`/`model::state` established for the
//! doctor verb, collapsed into one file the way `model::deprovision` already
//! is (M5/S2) — this shape is small enough (5 required top-level fields, one
//! nested array of small objects) not to need a separate wire/domain file
//! pair:
//!
//! - The **wire layer** (`UpdateWire`/`ChangedWire`/`HeldWire`): every field
//!   is `Option`, deliberately, even the schema's `required` ones — see
//!   `model::doctor`'s module doc for why (a missing-field parse failure
//!   needs to be differentiable from "not JSON at all", one layer up).
//! - The **domain layer** (`UpdateVerdict`/`UpdateResult`/`ChangeOp`/
//!   `ChangedItem`/`HeldChange`/`BlockedEntry`/`UpdateUnreadableReason`/
//!   `UpdateParseOutcome`) plus the parse boundary itself,
//!   `parse_update_body`.
//!
//! ## THE PARSE BOUNDARY (invariant #1 — "parse, never compute")
//!
//! `parse_update_body` is the ONLY place an `UpdateVerdict` is ever
//! constructed. The CLI already computed and PERFORMED the reconciling sync
//! before this function ever runs (`result`/`op`/`signed`/`severity_trailer`
//! are the CLI's own facts); this function only decides whether the CLI's
//! already-final report can be trusted enough to route. Nothing here resolves
//! a merge, computes a verdict, or re-derives which changes should have
//! applied — that all happened upstream, in the CLI. The router (M6/S2)
//! consumes `UpdateParseOutcome` and classifies it into a routing lane; it
//! MUST NOT re-parse the raw body itself.
//!
//! ## Fail-closed philosophy (this verb's own field-by-field twist on it)
//!
//! Every structurally-absent field that's required at the top level
//! (`schema_version`/`result`/`lock_before`/`lock_after`/`changed`), or that
//! identifies a `changed[]`/`held_for_approval[]` entry
//! (`dimension`/`layer`/`item`/`op` for a change; `dimension`/`from`/`to`/
//! `reason` for a held entry), fails the WHOLE body closed to `ParseError` or
//! `MissingSecurityField` — there is no partial trust of a body that doesn't
//! match its own contract, mirroring `model::state`'s treatment of a
//! checker's missing `id`/`severity`/`destructive`.
//!
//! `op` gets the same whole-body-closed treatment for a specific reason:
//! `ChangeOp::Unchanged` is a legitimately benign value, so a structurally
//! *absent* `op` must never silently become "unchanged" (the one op value
//! that looks safe to ignore) — it is rejected the same way a missing
//! `dimension`/`layer`/`item` is, never defaulted.
//!
//! `signed` gets a DIFFERENT, per-entry (not whole-body) treatment, called
//! out explicitly by the schema's own security note
//! (`changed[].signed`'s description: "a missing value is treated as
//! unsigned"): a structurally absent `signed` on one `changed[]` entry
//! defaults that single entry to `false` (unsigned) rather than rejecting the
//! entire update result. This is the field-level analogue of
//! `model::deprovision`'s `secrets_touched` handling — the worst-case value
//! (`unsigned`) is itself real, renderable, actionable content (it drives the
//! un-dismissable security banner downstream), so collapsing it to
//! `Unreadable` would DELETE the very fact ("this content is unsigned") the
//! fail-closed rule exists to surface. `signed` is never defaulted to `true`.
//!
//! `severity_trailer`/`shadowed_by` are schema-optional and nullable; this
//! layer preserves that nullability exactly as `Option<String>` rather than
//! coercing an absent/null value into an empty string that could read as "no
//! trailer" — collapsing the ambiguity here would itself be an unsafe
//! interpretation. Treating an absent trailer as the WORST case (assume a
//! security-relevant trailer *could* be present) is the security-banner
//! renderer's job (M6/S-E), one layer above this parse boundary; this
//! module's job is only to never lose the distinction.
//!
//! An unrecognized `result` string (present, but not one of `applied`/
//! `up-to-date`/`held`/`blocked`/`offline`) fails closed to `InvalidContent`
//! — same treatment `model::state::parse_cli_status` gives an unrecognized
//! `status` string and `model::deprovision::parse_result` gives an
//! unrecognized `result` string. This is the concrete mechanism behind this
//! task's "unknown result => never a fabricated 'applied cleanly'"
//! requirement: an `Unreadable` outcome can never render as `Applied`.
//!
//! ## `blocked[]` — an OPEN shape (G-M6-4, not frozen upstream)
//!
//! `update.schema.json`'s own `$comment` on `blocked` says the upstream
//! design shows no concrete example item shape for this array (only an empty
//! `blocked: []`). Rather than guess a shape that could silently drop a real
//! blocked item the moment the CLI's actual shape diverges from a guess, this
//! module models each `blocked[]` element as an opaque `BlockedEntry`
//! wrapping the raw `serde_json::Value` — every element that round-trips as a
//! JSON object is RETAINED, verbatim, never dropped and never
//! reinterpreted. A dropped blocked item would be a missed escalation (it
//! routes to `EscalateIt` downstream, per this module's own doc comment on
//! `BlockedEntry`) — the single worst failure mode this array can have. When
//! G-M6-4 closes upstream and the CLI freezes a concrete `blocked[]` item
//! shape, this type should gain a typed variant alongside (or instead of)
//! the opaque fallback.

use crate::model::envelope;
use serde::{Deserialize, Serialize};

/// The raw wire shape of an `update --json` body. Every field is `Option`,
/// deliberately — see the module doc. `#[serde(deny_unknown_fields)]` mirrors
/// the schema's top-level `"additionalProperties": false`.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpdateWire {
    pub schema_version: Option<String>,
    pub host: Option<String>,
    pub result: Option<String>,
    pub lock_before: Option<String>,
    pub lock_after: Option<String>,
    pub changed: Option<Vec<ChangedWire>>,
    pub held_for_approval: Option<Vec<HeldWire>>,
    /// Deliberately `serde_json::Value`, not a typed struct — see the module
    /// doc's "`blocked[]` — an OPEN shape" section (G-M6-4).
    pub blocked: Option<Vec<serde_json::Value>>,
}

/// One `changed[]` entry. `dimension`/`layer`/`item`/`op`/`signed` are the
/// schema's `required` fields on this shape; `#[serde(deny_unknown_fields)]`
/// mirrors the schema's `"additionalProperties": false` on `changed[]`
/// items (unlike `held_for_approval[]`/`blocked[]`, which stay open).
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChangedWire {
    pub dimension: Option<String>,
    pub layer: Option<String>,
    pub item: Option<String>,
    pub op: Option<String>,
    pub from: Option<String>,
    pub to: Option<String>,
    pub signed: Option<bool>,
    pub severity_trailer: Option<String>,
    pub shadowed_by: Option<String>,
}

/// One `held_for_approval[]` entry. `dimension`/`from`/`to`/`reason` are
/// schema-required; the item itself is `"additionalProperties": true`
/// (open), matching `model::doctor`'s `CheckerWire`/`AuthWire` — no
/// `deny_unknown_fields` here, an unrecognized extra field is silently
/// ignored rather than rejecting the whole body.
#[derive(Debug, Deserialize)]
pub struct HeldWire {
    pub dimension: Option<String>,
    pub from: Option<String>,
    pub to: Option<String>,
    pub reason: Option<String>,
}

/// The 5 CLI-emitted `result` values, mapped 1:1 from `update.result`
/// (ADR-M1-001-style lookup — never a computation).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum UpdateResult {
    Applied,
    UpToDate,
    Held,
    Blocked,
    Offline,
}

/// The 4 CLI-emitted `changed[].op` values, mapped 1:1. `Pruned` is the
/// reconciling-sync deletion the router surfaces distinctly (per this
/// module's doc + `cli-contract.md`'s `update` row); `Unchanged` is the
/// benign value a structurally-absent `op` must never be defaulted to (see
/// the module doc).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ChangeOp {
    Added,
    Updated,
    Pruned,
    Unchanged,
}

/// The APP-OWNED reason an `update --json` body could not be trusted. Never
/// a value the CLI emits itself. See the module doc for exactly which
/// condition maps to which variant.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum UpdateUnreadableReason {
    /// The CLI could not be spawned/reached at all, or exited abnormally —
    /// chosen by a future spawn boundary (mirroring `deprovision`'s
    /// `IoError`), never by this file. Included here so a router-facing
    /// caller has exactly one reason type to match, matching
    /// `model::state::CliUnreadableReason`/`model::deprovision::
    /// DeprovisionUnreadableReason`'s shape.
    IoError,
    /// Not JSON at all, or a required top-level/identifying field is
    /// structurally absent (`schema_version`/`result`/`lock_before`/
    /// `lock_after`/`changed`, or a `changed[]`/`held_for_approval[]`
    /// entry's `dimension`/`layer`/`item`/`from`/`to`/`reason`).
    ParseError,
    /// `schema_version` unparseable or outside the supported range, either
    /// direction — as fatal as `model::state`'s identical check.
    SchemaOutOfRange,
    /// A `changed[]` entry's `op` is structurally absent (never defaulted to
    /// `Unchanged`), or a `held_for_approval[]` entry is missing one of its
    /// required fields.
    MissingSecurityField,
    /// `result` or a `changed[]` entry's `op` is present but not one of the
    /// recognized values — content that parses but isn't trustworthy.
    InvalidContent,
}

/// One `changed[]` entry, already past the fail-closed gate: `dimension`/
/// `layer`/`item`/`op` are guaranteed present (their structural absence
/// fails the whole update result closed before this type is ever
/// constructed — see `parse_update_body`). `signed` is guaranteed present
/// too, but via a DIFFERENT mechanism: a structurally-absent wire `signed`
/// is defaulted to `false` here rather than rejecting the body (see the
/// module doc) — this field is never `true` unless the CLI explicitly said
/// so.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChangedItem {
    pub dimension: String,
    pub layer: String,
    pub item: String,
    pub op: ChangeOp,
    pub from: Option<String>,
    pub to: Option<String>,
    pub signed: bool,
    /// Security-trailer text driving the un-dismissable banner; `None` when
    /// absent OR explicitly null on the wire (both collapse identically —
    /// see the module doc). Rendered by a later stream (M6/S-E), never
    /// interpreted here.
    pub severity_trailer: Option<String>,
    /// Identifier of the layer/item shadowing this one; same nullability
    /// treatment as `severity_trailer`.
    pub shadowed_by: Option<String>,
}

/// One `held_for_approval[]` entry, past the same fail-closed gate as
/// `ChangedItem` — every field guaranteed present (structural absence of
/// any one fails the whole update result closed).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HeldChange {
    pub dimension: String,
    pub from: String,
    pub to: String,
    pub reason: String,
}

/// One `blocked[]` entry, retained verbatim as opaque JSON. See the module
/// doc's "`blocked[]` — an OPEN shape" section (G-M6-4) for why this is
/// deliberately NOT a typed struct: an unrecognized/future shape must never
/// be silently dropped, since a dropped blocked item is a missed
/// `EscalateIt` route downstream.
#[derive(Debug, Clone, PartialEq)]
pub struct BlockedEntry(pub serde_json::Value);

/// The fully-validated, trustworthy contents of an `update --json` result —
/// everything the router (M6/S2) needs, with every fail-closed gate already
/// applied. There is no path to construct this type except
/// `parse_update_body` returning `UpdateParseOutcome::Trusted`.
#[derive(Debug, Clone, PartialEq)]
pub struct UpdateVerdict {
    /// Not schema-required (see `update.schema.json`'s `$comment` on
    /// `host`) — carried through as-is, never defaulted to a fabricated
    /// hostname.
    pub host: Option<String>,
    pub result: UpdateResult,
    pub lock_before: String,
    pub lock_after: String,
    pub changed: Vec<ChangedItem>,
    /// May legitimately be empty (nothing held this run) — that is itself
    /// honest information, not an omission.
    pub held_for_approval: Vec<HeldChange>,
    /// May legitimately be empty. See `BlockedEntry`'s doc for why every
    /// present element is retained rather than filtered.
    pub blocked: Vec<BlockedEntry>,
}

/// The result of attempting to parse+trust a raw `update --json` body. The
/// parse-never-compute boundary as a *type*: no third variant, and nothing
/// downstream (the router, M6/S2) may re-derive a result from the raw body.
#[derive(Debug, Clone, PartialEq)]
pub enum UpdateParseOutcome {
    Trusted(UpdateVerdict),
    Unreadable(UpdateUnreadableReason),
}

/// Maps a wire `result` string to `UpdateResult` — a 1:1 lookup, never a
/// computation. An unrecognized string is content this app cannot trust; the
/// caller routes that to `UpdateUnreadableReason::InvalidContent`, never to a
/// guessed result (never a fabricated "applied").
fn parse_result(raw: &str) -> Option<UpdateResult> {
    match raw {
        "applied" => Some(UpdateResult::Applied),
        "up-to-date" => Some(UpdateResult::UpToDate),
        "held" => Some(UpdateResult::Held),
        "blocked" => Some(UpdateResult::Blocked),
        "offline" => Some(UpdateResult::Offline),
        _ => None,
    }
}

/// Maps a wire `op` string to `ChangeOp` — a 1:1 lookup, never a
/// computation. An unrecognized string fails closed to `InvalidContent`,
/// distinct from a structurally-ABSENT `op` (which fails closed to
/// `MissingSecurityField`, one layer up in `parse_update_body`) — see the
/// module doc for why those are different failure shapes.
fn parse_op(raw: &str) -> Option<ChangeOp> {
    match raw {
        "added" => Some(ChangeOp::Added),
        "updated" => Some(ChangeOp::Updated),
        "pruned" => Some(ChangeOp::Pruned),
        "unchanged" => Some(ChangeOp::Unchanged),
        _ => None,
    }
}

/// THE parse boundary (invariant #1). Never called with a raw process exit
/// code — spawn-level I/O failure is a future spawn boundary's job (it would
/// map directly to `UpdateUnreadableReason::IoError` without ever calling
/// this function, mirroring `deprovision::run_deprovision`); this function
/// only ever sees a body that was actually printed.
pub fn parse_update_body(raw: &[u8]) -> UpdateParseOutcome {
    let text = match std::str::from_utf8(raw) {
        Ok(t) => t,
        Err(_) => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError),
    };

    let wire: UpdateWire = match serde_json::from_str(text) {
        Ok(w) => w,
        Err(_) => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError),
    };

    let schema_version = match wire.schema_version.as_deref() {
        Some(v) => v,
        None => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError),
    };
    let parsed_version = match envelope::parse_schema_version(schema_version) {
        Some(v) => v,
        // Unparseable is as fatal as out-of-range (envelope.rs's contract) —
        // same reason, no separate "malformed version" bucket.
        None => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::SchemaOutOfRange),
    };
    if !envelope::schema_version_in_range(parsed_version) {
        return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::SchemaOutOfRange);
    }

    let raw_result = match wire.result.as_deref() {
        Some(r) => r,
        None => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError),
    };
    let result = match parse_result(raw_result) {
        Some(r) => r,
        // Present but unrecognized: content that parses but isn't
        // trustworthy — never a fabricated "applied cleanly".
        None => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::InvalidContent),
    };

    let lock_before = match wire.lock_before.filter(|v| !v.is_empty()) {
        Some(v) => v,
        None => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError),
    };
    let lock_after = match wire.lock_after.filter(|v| !v.is_empty()) {
        Some(v) => v,
        None => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError),
    };

    let raw_changed = match wire.changed {
        Some(c) => c,
        None => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError),
    };

    let mut changed = Vec::with_capacity(raw_changed.len());
    for c in raw_changed {
        let dimension = match c.dimension.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => {
                return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
            }
        };
        let layer = match c.layer.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => {
                return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
            }
        };
        let item = match c.item.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => {
                return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
            }
        };
        // `op` structurally absent => the whole update result is unreadable
        // — see the module doc for why this NEVER defaults to `Unchanged`.
        let raw_op = match c.op.as_deref() {
            Some(v) => v,
            None => {
                return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
            }
        };
        let op = match parse_op(raw_op) {
            Some(v) => v,
            None => return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::InvalidContent),
        };
        // FAIL-CLOSED, per-entry (not whole-body): a structurally-absent
        // `signed` becomes `false` (unsigned) — never `true`. See the
        // module doc's "Fail-closed philosophy" section for why this is a
        // different failure shape than `dimension`/`layer`/`item`/`op`
        // above.
        let signed = c.signed.unwrap_or(false);
        changed.push(ChangedItem {
            dimension,
            layer,
            item,
            op,
            from: c.from,
            to: c.to,
            signed,
            severity_trailer: c.severity_trailer,
            shadowed_by: c.shadowed_by,
        });
    }

    let mut held_for_approval = Vec::new();
    for h in wire.held_for_approval.unwrap_or_default() {
        let dimension = match h.dimension.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => {
                return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
            }
        };
        let from = match h.from.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => {
                return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
            }
        };
        let to = match h.to.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => {
                return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
            }
        };
        let reason = match h.reason.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => {
                return UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
            }
        };
        held_for_approval.push(HeldChange {
            dimension,
            from,
            to,
            reason,
        });
    }

    // `blocked[]` — an OPEN shape (G-M6-4). Every element is retained
    // verbatim; see `BlockedEntry`'s own doc for why nothing here filters or
    // reinterprets a single element.
    let blocked = wire
        .blocked
        .unwrap_or_default()
        .into_iter()
        .map(BlockedEntry)
        .collect();

    UpdateParseOutcome::Trusted(UpdateVerdict {
        host: wire.host,
        result,
        lock_before,
        lock_after,
        changed,
        held_for_approval,
        blocked,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn corpus(name: &str) -> UpdateParseOutcome {
        let path = format!(
            "{}/fixtures/update/corpus/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_update_body(&raw)
    }

    fn invalid(name: &str) -> UpdateParseOutcome {
        let path = format!(
            "{}/fixtures/update/invalid/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_update_body(&raw)
    }

    fn assert_trusted(outcome: UpdateParseOutcome) -> UpdateVerdict {
        match outcome {
            UpdateParseOutcome::Trusted(v) => v,
            UpdateParseOutcome::Unreadable(reason) => {
                panic!("expected Trusted, got Unreadable({reason:?})")
            }
        }
    }

    #[test]
    fn applied_clean_fixture_parses_trusted_with_signed_changes() {
        let v = assert_trusted(corpus("applied-clean"));
        assert_eq!(v.result, UpdateResult::Applied);
        assert!(!v.changed.is_empty());
        assert!(v.changed.iter().all(|c| c.signed));
    }

    #[test]
    fn up_to_date_fixture_parses_trusted_with_no_changes() {
        let v = assert_trusted(corpus("up-to-date"));
        assert_eq!(v.result, UpdateResult::UpToDate);
        assert!(v.changed.is_empty());
    }

    #[test]
    fn held_fixture_parses_trusted_with_held_for_approval_populated() {
        let v = assert_trusted(corpus("held"));
        assert_eq!(v.result, UpdateResult::Held);
        assert!(!v.held_for_approval.is_empty());
        let held = &v.held_for_approval[0];
        assert!(!held.dimension.is_empty());
        assert!(!held.reason.is_empty());
    }

    #[test]
    fn blocked_fixture_parses_trusted_with_blocked_entries_retained() {
        let v = assert_trusted(corpus("blocked"));
        assert_eq!(v.result, UpdateResult::Blocked);
        assert!(!v.blocked.is_empty());
    }

    #[test]
    fn offline_fixture_parses_trusted() {
        let v = assert_trusted(corpus("offline"));
        assert_eq!(v.result, UpdateResult::Offline);
    }

    #[test]
    fn pruned_change_fixture_preserves_the_pruned_op() {
        let v = assert_trusted(corpus("pruned-change"));
        assert!(v.changed.iter().any(|c| c.op == ChangeOp::Pruned));
    }

    #[test]
    fn security_shadow_fixture_carries_severity_trailer_and_shadowed_by() {
        let v = assert_trusted(corpus("security-shadow"));
        let shadowed = v
            .changed
            .iter()
            .find(|c| c.shadowed_by.is_some())
            .expect("fixture must carry a shadowed_by change");
        assert!(shadowed.severity_trailer.is_some());
        assert!(!shadowed.signed, "shadowed change must be unsigned");
    }

    /// The adversarial missing-`signed` fixture is NOT rejected — it is real,
    /// trusted content, defaulted to unsigned. Collapsing this to Unreadable
    /// would hide the exact fact ("this content is unsigned") the fail-closed
    /// rule exists to surface.
    #[test]
    fn missing_signed_fixture_parses_trusted_defaulted_to_unsigned() {
        let v = assert_trusted(corpus("missing-signed"));
        let entry = v
            .changed
            .iter()
            .find(|c| c.item == "missing-signed-item")
            .expect("fixture must contain the missing-signed item");
        assert!(!entry.signed, "missing signed must NEVER default to true");
    }

    /// A missing `signed` must never be treated as trusted-signed, proven
    /// directly (not just via the fixture) so this invariant can't regress
    /// silently if the fixture's shape ever changes.
    #[test]
    fn missing_signed_is_never_treated_as_signed() {
        let raw = br#"{
            "schema_version": "1.0",
            "result": "applied",
            "lock_before": "aaaaaaa",
            "lock_after": "bbbbbbb",
            "changed": [
                { "dimension": "cli", "layer": "org", "item": "x", "op": "updated" }
            ]
        }"#;
        let v = assert_trusted(parse_update_body(raw));
        assert!(!v.changed[0].signed);
    }

    #[test]
    fn missing_op_fails_closed_never_a_benign_no_op() {
        assert!(matches!(
            invalid("missing-op"),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
        ));
    }

    #[test]
    fn unrecognized_top_level_field_fails_closed_to_parse_error() {
        assert!(matches!(
            invalid("unknown-extra-field"),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn malformed_json_fails_closed_to_parse_error_never_a_fabricated_applied() {
        assert!(matches!(
            invalid("malformed"),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn schema_version_above_max_fails_closed() {
        assert!(matches!(
            invalid("schema-version-above-max"),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::SchemaOutOfRange)
        ));
    }

    #[test]
    fn schema_version_below_min_fails_closed() {
        assert!(matches!(
            invalid("schema-version-below-min"),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::SchemaOutOfRange)
        ));
    }

    #[test]
    fn unknown_result_value_fails_closed_to_invalid_content_never_applied() {
        assert!(matches!(
            invalid("unknown-result"),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::InvalidContent)
        ));
    }

    #[test]
    fn every_invalid_fixture_is_unreadable_never_trusted_as_applied() {
        for name in [
            "missing-op",
            "unknown-extra-field",
            "malformed",
            "schema-version-above-max",
            "schema-version-below-min",
            "unknown-result",
        ] {
            match invalid(name) {
                UpdateParseOutcome::Unreadable(_) => {}
                UpdateParseOutcome::Trusted(v) => {
                    panic!("fixture {name} must be Unreadable, got Trusted({v:?})")
                }
            }
        }
    }

    #[test]
    fn non_utf8_bytes_are_a_parse_error() {
        let raw: &[u8] = &[0xff, 0xfe, 0x00, 0x01];
        assert!(matches!(
            parse_update_body(raw),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn empty_body_is_a_parse_error() {
        assert!(matches!(
            parse_update_body(b""),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn missing_held_entry_field_fails_closed_to_missing_security_field() {
        let raw = br#"{
            "schema_version": "1.0",
            "result": "held",
            "lock_before": "aaaaaaa",
            "lock_after": "aaaaaaa",
            "changed": [],
            "held_for_approval": [
                { "dimension": "cli", "from": "1.2.0", "to": "2.0.0" }
            ]
        }"#;
        assert!(matches!(
            parse_update_body(raw),
            UpdateParseOutcome::Unreadable(UpdateUnreadableReason::MissingSecurityField)
        ));
    }

    /// An unrecognized `blocked[]` element shape is retained, not dropped —
    /// the concrete mechanism behind G-M6-4's "open shape, fail closed to
    /// retain" requirement.
    #[test]
    fn unrecognized_blocked_shape_is_retained_not_dropped() {
        let raw = br#"{
            "schema_version": "1.0",
            "result": "blocked",
            "lock_before": "aaaaaaa",
            "lock_after": "aaaaaaa",
            "changed": [],
            "blocked": [
                { "some_future_field": "not-yet-frozen", "nested": { "a": 1 } },
                { "reason": "capability-policy-denial" }
            ]
        }"#;
        let v = assert_trusted(parse_update_body(raw));
        assert_eq!(v.blocked.len(), 2);
        assert_eq!(
            v.blocked[0].0["some_future_field"],
            serde_json::json!("not-yet-frozen")
        );
        assert_eq!(
            v.blocked[1].0["reason"],
            serde_json::json!("capability-policy-denial")
        );
    }

    #[test]
    fn missing_severity_trailer_and_shadowed_by_parse_as_none_not_a_false_safe_default() {
        let raw = br#"{
            "schema_version": "1.0",
            "result": "applied",
            "lock_before": "aaaaaaa",
            "lock_after": "bbbbbbb",
            "changed": [
                { "dimension": "cli", "layer": "org", "item": "x", "op": "updated", "signed": true }
            ]
        }"#;
        let v = assert_trusted(parse_update_body(raw));
        assert_eq!(v.changed[0].severity_trailer, None);
        assert_eq!(v.changed[0].shadowed_by, None);
    }

    #[test]
    fn explicit_null_severity_trailer_and_shadowed_by_also_parse_as_none() {
        let raw = br#"{
            "schema_version": "1.0",
            "result": "applied",
            "lock_before": "aaaaaaa",
            "lock_after": "bbbbbbb",
            "changed": [
                { "dimension": "cli", "layer": "org", "item": "x", "op": "updated", "signed": true, "severity_trailer": null, "shadowed_by": null }
            ]
        }"#;
        let v = assert_trusted(parse_update_body(raw));
        assert_eq!(v.changed[0].severity_trailer, None);
        assert_eq!(v.changed[0].shadowed_by, None);
    }
}
