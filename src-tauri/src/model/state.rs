//! The typed, fail-closed domain state the UI renders (T3/T5).
//!
//! `CliStatus` (the 10 CLI-emitted states, mapped 1:1 from `doctor.status`)
//! and `CliUnreadableReason` (the 11th, APP-OWNED state — never CLI-emitted,
//! chosen only from I/O/schema failure).
//!
//! Construction of a `CliStatus` is the ONLY place this choice is made, and
//! it is a mapping, never a computation (ADR-M1-001): `parse_cli_status`
//! below is a 1:1 lookup from the CLI's already worst-wins, top-level
//! `status`. This app does not re-run a worst-wins ladder of its own.
//!
//! `CliUnreadableReason` is chosen by the app when, and only when: spawn
//! failed (`io_error`) / exit code 2 (`exit_2`, decided by `cli::spawn`, T4 —
//! this crate only defines the shape T4 reports into) / JSON unparseable
//! (`parse_error`) / `schema_version` out of the supported range, either
//! direction (`schema_out_of_range`) / a required security field absent
//! (`missing_security_field`) / content that parses but self-contradicts,
//! e.g. a claimed-`healthy` verdict with a `fail` checker
//! (`invalid_content`). It outranks any partial `status` — a verdict that
//! cannot be trusted is never rendered as its claimed state.
//!
//! ## THE PARSE BOUNDARY (invariant #1 — "parse, never compute")
//!
//! `parse_doctor_body` below is the boundary. Everything above it in the call
//! graph (`model::doctor`, `model::failclosed`) may deserialize and apply
//! fail-closed field defaults; everything below it (`render::derive`) may
//! only GROUP and MAP what this function already decided — a bucket's
//! severity is the worst of the checkers already in it, never a new verdict,
//! and `header.glyph_state` is a pure lookup (`CliStatus::glyph_badge`), never
//! a recomputed ladder. No function outside this file may construct a
//! `DoctorVerdict` or choose a `CliUnreadableReason`. `CliStatus::Healthy` is
//! constructed at exactly one guarded call site in the whole crate — see
//! `parse_cli_status` and the guard immediately after its call in
//! `parse_doctor_body` (enforced by
//! `tests/fitness_no_fabricated_healthy.rs`).

use crate::model::doctor::DoctorWire;
use crate::model::envelope;
use crate::model::failclosed::{self, AuthState, Severity};
use serde::Serialize;

/// The 10 CLI-emitted status values, mapped 1:1 from `doctor.status`.
/// `rename_all = "kebab-case"` makes this enum's `Serialize` output exactly
/// the wire strings `parse_cli_status` also recognizes on the way in, so the
/// mapping table only has to be written once.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum CliStatus {
    SetupNeeded,
    ItConfigIncomplete,
    Healthy,
    Syncing,
    UpdateAvailable,
    NeedsAttention,
    SignedOut,
    Offline,
    WaitingForNetwork,
    UpdatingApp,
}

impl CliStatus {
    /// `true` only for `Healthy`. Downstream code (`render::derive`'s guard
    /// re-check, tests) should prefer this over spelling the fully-qualified
    /// `CliStatus::Healthy` path, so the crate has exactly one place that
    /// text appears (see the module doc + the fitness test).
    pub fn is_healthy(&self) -> bool {
        matches!(self, Self::Healthy)
    }

    /// The badge-shape token for the tray glyph, per 60-ui-design.md's
    /// Status-Glyph Family table (§ Component Patterns → 1) — a lookup, not
    /// a computation (ADR-M1-001): each of the 10 CLI states maps to exactly
    /// one shape. Values are drawn from the same `BadgeState` vocabulary as
    /// `src/types.ts`.
    pub fn glyph_badge(&self) -> &'static str {
        match self {
            Self::Healthy => "none", // solid silhouette, no badge
            Self::SetupNeeded => "hollow",
            Self::ItConfigIncomplete => "wrench",
            Self::SignedOut => "key",
            Self::NeedsAttention => "triangle",
            Self::Offline => "cloud-slash",
            Self::WaitingForNetwork => "clock",
            Self::Syncing => "ring",
            Self::UpdateAvailable => "update",
            Self::UpdatingApp => "spinner",
        }
    }
}

/// The 11th, APP-OWNED reason a verdict could not be trusted. Never a value
/// the CLI emits inside `doctor --json`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CliUnreadableReason {
    IoError,
    ParseError,
    SchemaOutOfRange,
    MissingSecurityField,
    #[serde(rename = "exit_2")]
    Exit2,
    InvalidContent,
}

/// One CLI checker finding, already past the fail-closed gate: `severity`
/// and `destructive` are guaranteed present (their structural *absence*
/// fails the whole verdict closed before this type is ever constructed —
/// see `parse_doctor_body`), so downstream code never has to re-guess a
/// default.
#[derive(Debug, Clone)]
pub struct Checker {
    pub id: String,
    pub severity: Severity,
    pub destructive: bool,
    pub detail: Option<String>,
    pub layer: Option<String>,
    pub product: Option<String>,
    /// `true` only when the wire `repair` token (`model::doctor::
    /// CheckerWire::repair`) was non-null — the boolean-only distillate M6/S2
    /// (`routing::event::DoctorFindingEvent`'s own doc) names as the router's
    /// input: "a future emission seam (S3+) threads `repair.is_some()`
    /// through without ever passing the repair TOKEN TEXT itself into this
    /// router." M6/S6 (`routing::wire`) is that seam. The repair token TEXT
    /// itself is never carried past this parse boundary at all (M1 never
    /// needed it, and the router must never see it — content-free by
    /// construction, matching `ItSignal`'s own discipline).
    pub repair_available: bool,
}

/// One credential finding, past the same fail-closed gate as `Checker`.
#[derive(Debug, Clone)]
pub struct AuthIssue {
    pub identity: String,
    pub scope: String,
    pub state: AuthState,
    pub expires_at: Option<String>,
}

/// The fully-validated, trustworthy contents of a `doctor --json` verdict —
/// everything `render::derive` needs, with every fail-closed gate already
/// applied. There is no path to construct this type except
/// `parse_doctor_body` returning `ParseOutcome::Trusted`.
#[derive(Debug, Clone)]
pub struct DoctorVerdict {
    pub host: String,
    pub status: CliStatus,
    pub offline: bool,
    pub checkers: Vec<Checker>,
    pub auth: Vec<AuthIssue>,
}

/// The result of attempting to parse+trust a raw `doctor --json` body. This
/// is the parse-never-compute boundary as a *type*: there is no third
/// variant, and nothing downstream of this enum re-derives a status.
#[derive(Debug, Clone)]
pub enum ParseOutcome {
    Trusted(DoctorVerdict),
    Unreadable(CliUnreadableReason),
}

/// Maps a wire `status` string to `CliStatus` — a 1:1 lookup, never a
/// computation (ADR-M1-001). **This is the ONLY place `CliStatus::Healthy` is
/// ever constructed in this crate.** An unrecognized string is content we
/// cannot trust; the caller routes that to `CliUnreadableReason::InvalidContent`,
/// never to a guessed status.
fn parse_cli_status(raw: &str) -> Option<CliStatus> {
    match raw {
        "setup-needed" => Some(CliStatus::SetupNeeded),
        "it-config-incomplete" => Some(CliStatus::ItConfigIncomplete),
        "healthy" => Some(CliStatus::Healthy),
        "syncing" => Some(CliStatus::Syncing),
        "update-available" => Some(CliStatus::UpdateAvailable),
        "needs-attention" => Some(CliStatus::NeedsAttention),
        "signed-out" => Some(CliStatus::SignedOut),
        "offline" => Some(CliStatus::Offline),
        "waiting-for-network" => Some(CliStatus::WaitingForNetwork),
        "updating-app" => Some(CliStatus::UpdatingApp),
        _ => None,
    }
}

/// T8/F4 (sec review remediation — "no audit trail on rejected/poisoned
/// bodies"): the one-line audit message for `CliUnreadableReason::
/// InvalidContent` — the single reason code that means a body actively
/// *lied* (a self-contradictory `healthy` claim, or an unrecognized
/// `status` string), as distinct from the benign version-skew reasons
/// (`ParseError`/`SchemaOutOfRange`/`MissingSecurityField`), which stay
/// silent because they're ordinary staleness, not a tampering signal.
///
/// Carries the reason code + `trigger` (which specific invariant tripped)
/// ONLY — never a value FROM the body. `trigger` is always one of this
/// module's own `&'static str` literals (see its two call sites), never
/// `host`/checker `id`/`detail`/`product`/`layer`/auth `identity` — a
/// personal or ecosystem item name must never reach telemetry, per
/// `docs/05-security/credentials-and-boundary.md`. Split from
/// `audit_invalid_content` below purely so this formatting can be unit
/// tested without capturing stderr.
fn audit_invalid_content_message(trigger: &str) -> String {
    format!("[copilot-control-tower] audit: doctor body rejected as InvalidContent (trigger={trigger}) — see model::state::parse_doctor_body")
}

/// Emits the audit line via `eprintln!` — the interim facility. No logging/
/// tracing crate exists in this crate yet (`Cargo.toml`'s dependency note is
/// explicit that only parse/render/tray/IPC deps belong here); a real
/// log-file or telemetry sink is later-milestone work
/// (`docs/05-security/incident-response.md` already flags tamper-event
/// logging as "specified, not yet implemented" — this is the first concrete
/// emission point for it, so a future sink has something to route).
fn audit_invalid_content(trigger: &str) {
    eprintln!("{}", audit_invalid_content_message(trigger));
}

/// THE parse boundary (invariant #1). See the module doc for the full
/// contract. Never called with a real process exit code — exit-2 handling is
/// `cli::spawn`'s job (T4); this function only ever sees a body.
pub fn parse_doctor_body(raw: &[u8]) -> ParseOutcome {
    let text = match std::str::from_utf8(raw) {
        Ok(t) => t,
        Err(_) => return ParseOutcome::Unreadable(CliUnreadableReason::ParseError),
    };

    let wire: DoctorWire = match serde_json::from_str(text) {
        Ok(w) => w,
        Err(_) => return ParseOutcome::Unreadable(CliUnreadableReason::ParseError),
    };

    let schema_version = match wire.schema_version.as_deref() {
        Some(v) => v,
        None => return ParseOutcome::Unreadable(CliUnreadableReason::ParseError),
    };
    let parsed_version = match envelope::parse_schema_version(schema_version) {
        Some(v) => v,
        // Unparseable is as fatal as out-of-range (envelope.rs's contract) —
        // same reason, no separate "malformed version" bucket.
        None => return ParseOutcome::Unreadable(CliUnreadableReason::SchemaOutOfRange),
    };
    if !envelope::schema_version_in_range(parsed_version) {
        return ParseOutcome::Unreadable(CliUnreadableReason::SchemaOutOfRange);
    }

    let host = match wire.host.filter(|h| !h.is_empty()) {
        Some(h) => h,
        None => return ParseOutcome::Unreadable(CliUnreadableReason::ParseError),
    };
    let offline = match wire.offline {
        Some(o) => o,
        None => return ParseOutcome::Unreadable(CliUnreadableReason::ParseError),
    };
    let raw_checkers = match wire.checkers {
        Some(c) => c,
        None => return ParseOutcome::Unreadable(CliUnreadableReason::ParseError),
    };
    let raw_status = match wire.status.as_deref() {
        Some(s) => s,
        None => return ParseOutcome::Unreadable(CliUnreadableReason::ParseError),
    };

    let mut checkers = Vec::with_capacity(raw_checkers.len());
    for c in raw_checkers {
        let id = match c.id.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => return ParseOutcome::Unreadable(CliUnreadableReason::MissingSecurityField),
        };
        // `severity` structurally absent => the whole verdict is unreadable
        // (schema-`required`). Present-but-unrecognized fails closed to
        // `Fail` inside `severity_from_wire` — see failclosed.rs's module doc
        // for why those are different failure shapes.
        let severity = match c.severity.as_deref() {
            Some(v) => failclosed::severity_from_wire(v),
            None => return ParseOutcome::Unreadable(CliUnreadableReason::MissingSecurityField),
        };
        // `destructive` structurally absent => unreadable, same reasoning.
        let destructive = match c.destructive {
            Some(v) => v,
            None => return ParseOutcome::Unreadable(CliUnreadableReason::MissingSecurityField),
        };
        // M6/S6: presence-only — the repair token TEXT (`c.repair`'s String
        // content) is deliberately dropped here, never carried past this
        // struct; see `Checker::repair_available`'s own doc.
        let repair_available = c.repair.is_some();
        checkers.push(Checker {
            id,
            severity,
            destructive,
            detail: c.detail,
            layer: c.layer,
            product: c.product,
            repair_available,
        });
    }

    let mut auth = Vec::new();
    for a in wire.auth.unwrap_or_default() {
        let identity = match a.identity.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => return ParseOutcome::Unreadable(CliUnreadableReason::MissingSecurityField),
        };
        let scope = match a.scope.filter(|v| !v.is_empty()) {
            Some(v) => v,
            None => return ParseOutcome::Unreadable(CliUnreadableReason::MissingSecurityField),
        };
        let state = match a.state.as_deref() {
            Some(v) => failclosed::auth_state_from_wire(v),
            None => return ParseOutcome::Unreadable(CliUnreadableReason::MissingSecurityField),
        };
        auth.push(AuthIssue {
            identity,
            scope,
            state,
            expires_at: a.expires_at,
        });
    }

    let status = match parse_cli_status(raw_status) {
        Some(s) => s,
        None => {
            // T8/F4: an unrecognized `status` string is content this app
            // cannot trust — audit it (see `audit_invalid_content`'s doc).
            audit_invalid_content("unrecognized_status_value");
            return ParseOutcome::Unreadable(CliUnreadableReason::InvalidContent);
        }
    };

    // THE ONE GUARD ON `Healthy`, mirroring doctor.schema.json's `allOf`
    // (invariant #1 / ADR-M1-001): a `healthy` verdict claimed while
    // offline, or while a `fail` checker or an expired/revoked auth entry is
    // present, contradicts itself. This never upgrades a status TO Healthy —
    // it can only refuse to trust a self-contradictory one (the
    // poisoned-body-on-exit-0 case). This is the single guarded call site
    // the T3 fitness test checks for.
    if status.is_healthy() {
        // T8/F4: which specific invariant(s) tripped — audited together as
        // one event below (never separately from the reject decision, so
        // there's no window where a poisoned body is trusted-but-unlogged).
        let mut triggers: Vec<&'static str> = Vec::new();
        if offline {
            triggers.push("healthy_claimed_while_offline");
        }
        if checkers.iter().any(|c| c.severity == Severity::Fail) {
            triggers.push("healthy_claimed_with_fail_checker");
        }
        if auth
            .iter()
            .any(|a| matches!(a.state, AuthState::Expired | AuthState::Revoked))
        {
            triggers.push("healthy_claimed_with_expired_or_revoked_auth");
        }
        if !triggers.is_empty() {
            audit_invalid_content(&triggers.join("+"));
            return ParseOutcome::Unreadable(CliUnreadableReason::InvalidContent);
        }
    }

    ParseOutcome::Trusted(DoctorVerdict {
        host,
        status,
        offline,
        checkers,
        auth,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn corpus(name: &str) -> ParseOutcome {
        let path = format!("{}/fixtures/corpus/{name}.json", env!("CARGO_MANIFEST_DIR"));
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_doctor_body(&raw)
    }

    fn invalid(name: &str) -> ParseOutcome {
        let path = format!(
            "{}/fixtures/invalid/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_doctor_body(&raw)
    }

    fn assert_trusted_status(outcome: ParseOutcome, expected: CliStatus) {
        match outcome {
            ParseOutcome::Trusted(v) => assert_eq!(v.status, expected),
            ParseOutcome::Unreadable(reason) => {
                panic!("expected Trusted({expected:?}), got Unreadable({reason:?})")
            }
        }
    }

    #[test]
    fn every_corpus_status_round_trips_to_its_mapped_state() {
        assert_trusted_status(corpus("healthy-clean-fleet"), CliStatus::Healthy);
        assert_trusted_status(
            corpus("it-config-incomplete-org-mdm"),
            CliStatus::ItConfigIncomplete,
        );
        assert_trusted_status(
            corpus("needs-attention-codex-dept-fail"),
            CliStatus::NeedsAttention,
        );
        assert_trusted_status(corpus("offline"), CliStatus::Offline);
        assert_trusted_status(corpus("setup-needed-first-run"), CliStatus::SetupNeeded);
        assert_trusted_status(corpus("signed-out-claude-personal"), CliStatus::SignedOut);
        assert_trusted_status(corpus("syncing-knowledge-org"), CliStatus::Syncing);
        assert_trusted_status(
            corpus("update-available-cli-foundation"),
            CliStatus::UpdateAvailable,
        );
        assert_trusted_status(corpus("updating-app-self-update"), CliStatus::UpdatingApp);
        assert_trusted_status(
            corpus("waiting-for-network-startup"),
            CliStatus::WaitingForNetwork,
        );
    }

    #[test]
    fn healthy_fixture_has_all_sixteen_pass_checkers_and_no_auth_issues() {
        match corpus("healthy-clean-fleet") {
            ParseOutcome::Trusted(v) => {
                assert!(!v.offline);
                assert_eq!(v.checkers.len(), 16);
                assert!(v.checkers.iter().all(|c| c.severity == Severity::Pass));
                assert!(v.auth.is_empty());
            }
            other => panic!("expected Trusted, got {other:?}"),
        }
    }

    #[test]
    fn every_invalid_fixture_is_unreadable_never_healthy() {
        for name in [
            "schema-version-above-max",
            "schema-version-below-min",
            "checker-missing-destructive",
            "checker-missing-severity",
            "not-valid-json",
        ] {
            match invalid(name) {
                ParseOutcome::Unreadable(_) => {}
                ParseOutcome::Trusted(v) => {
                    panic!(
                        "fixture {name} must be Unreadable, got Trusted({:?})",
                        v.status
                    )
                }
            }
        }
    }

    #[test]
    fn schema_version_out_of_range_fixtures_report_that_reason() {
        assert!(matches!(
            invalid("schema-version-above-max"),
            ParseOutcome::Unreadable(CliUnreadableReason::SchemaOutOfRange)
        ));
        assert!(matches!(
            invalid("schema-version-below-min"),
            ParseOutcome::Unreadable(CliUnreadableReason::SchemaOutOfRange)
        ));
    }

    #[test]
    fn missing_checker_field_fixtures_report_missing_security_field() {
        assert!(matches!(
            invalid("checker-missing-destructive"),
            ParseOutcome::Unreadable(CliUnreadableReason::MissingSecurityField)
        ));
        assert!(matches!(
            invalid("checker-missing-severity"),
            ParseOutcome::Unreadable(CliUnreadableReason::MissingSecurityField)
        ));
    }

    /// The poisoned-body-on-exit-0 case (fixtures/README.md): both
    /// `checker-missing-*` fixtures are, on their own merits, bodies that
    /// would exit 0 from the mock CLI (no `fail` checker present). This
    /// proves the app fails closed on the BODY's content, not on an exit
    /// code — `parse_doctor_body` never even sees one.
    #[test]
    fn missing_field_fixtures_fail_closed_on_content_alone() {
        for name in ["checker-missing-destructive", "checker-missing-severity"] {
            assert!(matches!(invalid(name), ParseOutcome::Unreadable(_)));
        }
    }

    #[test]
    fn truncated_json_reports_parse_error() {
        assert!(matches!(
            invalid("not-valid-json"),
            ParseOutcome::Unreadable(CliUnreadableReason::ParseError)
        ));
    }

    /// A fabricated body that CLAIMS `status: "healthy"` but contains a
    /// `fail` checker must never be trusted as healthy — the schema's
    /// `allOf` invariant, re-verified fail-closed at the one guarded call
    /// site.
    #[test]
    fn fabricated_healthy_with_fail_checker_is_rejected() {
        let raw = br#"{
            "schema_version": "1.0",
            "host": "poisoned",
            "score": 100,
            "status": "healthy",
            "offline": false,
            "checkers": [
                { "id": "x", "severity": "fail", "destructive": true }
            ],
            "auth": []
        }"#;
        assert!(matches!(
            parse_doctor_body(raw),
            ParseOutcome::Unreadable(CliUnreadableReason::InvalidContent)
        ));
    }

    #[test]
    fn fabricated_healthy_while_offline_is_rejected() {
        let raw = br#"{
            "schema_version": "1.0",
            "host": "poisoned",
            "score": 100,
            "status": "healthy",
            "offline": true,
            "checkers": [],
            "auth": []
        }"#;
        assert!(matches!(
            parse_doctor_body(raw),
            ParseOutcome::Unreadable(CliUnreadableReason::InvalidContent)
        ));
    }

    #[test]
    fn fabricated_healthy_with_revoked_auth_is_rejected() {
        let raw = br#"{
            "schema_version": "1.0",
            "host": "poisoned",
            "score": 100,
            "status": "healthy",
            "offline": false,
            "checkers": [],
            "auth": [ { "identity": "x", "scope": "org", "state": "revoked" } ]
        }"#;
        assert!(matches!(
            parse_doctor_body(raw),
            ParseOutcome::Unreadable(CliUnreadableReason::InvalidContent)
        ));
    }

    #[test]
    fn unknown_status_string_is_invalid_content_not_a_crash() {
        let raw = br#"{
            "schema_version": "1.0",
            "host": "h",
            "score": 0,
            "status": "degraded",
            "offline": false,
            "checkers": [],
            "auth": []
        }"#;
        assert!(matches!(
            parse_doctor_body(raw),
            ParseOutcome::Unreadable(CliUnreadableReason::InvalidContent)
        ));
    }

    #[test]
    fn non_utf8_bytes_are_a_parse_error() {
        let raw: &[u8] = &[0xff, 0xfe, 0x00, 0x01];
        assert!(matches!(
            parse_doctor_body(raw),
            ParseOutcome::Unreadable(CliUnreadableReason::ParseError)
        ));
    }

    #[test]
    fn empty_body_is_a_parse_error() {
        assert!(matches!(
            parse_doctor_body(b""),
            ParseOutcome::Unreadable(CliUnreadableReason::ParseError)
        ));
    }

    /// T8/F4: the audit message names the reason and the trigger only —
    /// never wraps a body-supplied value (host/checker id/detail/product/
    /// layer/identity are all un-emittable, per the module's `trigger`
    /// contract — every call site passes one of ITS OWN `&'static str`
    /// literals, never a field read off the parsed body).
    #[test]
    fn audit_message_names_reason_and_trigger_only() {
        let msg = audit_invalid_content_message("healthy_claimed_while_offline");
        assert!(msg.contains("InvalidContent"));
        assert!(msg.contains("healthy_claimed_while_offline"));
        // Sanity: it must be a fixed, short, structured line, not an
        // arbitrary dump of caller-supplied data.
        assert!(msg.len() < 200, "audit message unexpectedly long: {msg:?}");
    }

    #[test]
    fn audit_message_combines_multiple_triggers_when_more_than_one_invariant_trips() {
        let msg = audit_invalid_content_message(
            "healthy_claimed_while_offline+healthy_claimed_with_fail_checker",
        );
        assert!(msg.contains("healthy_claimed_while_offline+healthy_claimed_with_fail_checker"));
    }
}
