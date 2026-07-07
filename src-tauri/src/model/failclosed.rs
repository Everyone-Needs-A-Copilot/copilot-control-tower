//! Fail-closed deserialization adaptors (T3).
//!
//! A missing or malformed security-relevant field is never treated as safe —
//! this is the global contract rule from `docs/01-architecture/cli-contract.md`
//! and it is enforced here, not as scattered `.unwrap_or(...)` calls at call
//! sites.
//!
//! Two genuinely different failure shapes get two different treatments, and
//! this module owns only the second one:
//!
//! - `severity`/`destructive`/`id` (checkers) and `identity`/`scope`/`state`
//!   (auth) are `required` in `doctor.schema.json`. A **structurally absent**
//!   value there is not something this module defaults — it fails the whole
//!   verdict closed to `CliUnreadableReason::MissingSecurityField`, one layer
//!   up in `model::state::parse_doctor_body`. Defaulting a single checker's
//!   missing `severity` to `Fail` and rendering the rest of a body that is
//!   already known to violate its own required-field contract would be
//!   *partial* trust, which is exactly what invariant #1 forbids.
//! - What this module *does* handle: a field that is **present** but whose
//!   value isn't one of the values we recognize (a forward-compat CLI
//!   emitting a severity/auth-state we don't know yet). That case fails
//!   closed to the worst known value rather than rejecting the whole verdict
//!   — `severity` missing/unknown => `Fail` (never `Pass`); an unrecognized
//!   `auth.state` => `Revoked` (the worse of the two known states).

use serde::{Deserialize, Serialize};

/// Checker verdict (`pass`/`warn`/`fail`). See the module doc for the
/// missing-vs-unknown distinction — this type and `severity_from_wire` only
/// resolve the "present but unrecognized" case.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Severity {
    Pass,
    Warn,
    Fail,
}

/// Fail-closed conversion of a raw wire string into `Severity`: anything
/// other than exactly `"pass"`/`"warn"`/`"fail"` becomes `Fail`, never
/// `Pass` — a forward-compatible severity value from a newer CLI still
/// renders as the worst case rather than crashing the whole parse.
pub fn severity_from_wire(raw: &str) -> Severity {
    match raw {
        "pass" => Severity::Pass,
        "warn" => Severity::Warn,
        _ => Severity::Fail,
    }
}

/// Fail-closed credential state. `expired` is transient/recoverable;
/// `revoked` is permanent and worse (`doctor.schema.json`'s `auth[].state`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AuthState {
    Expired,
    Revoked,
}

/// Fail-closed conversion: anything other than exactly `"expired"` becomes
/// `Revoked`, the worse of the two known states — same rationale as
/// `severity_from_wire`.
pub fn auth_state_from_wire(raw: &str) -> AuthState {
    match raw {
        "expired" => AuthState::Expired,
        _ => AuthState::Revoked,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_severities_map_through() {
        assert_eq!(severity_from_wire("pass"), Severity::Pass);
        assert_eq!(severity_from_wire("warn"), Severity::Warn);
        assert_eq!(severity_from_wire("fail"), Severity::Fail);
    }

    #[test]
    fn unknown_severity_fails_closed_to_fail() {
        assert_eq!(severity_from_wire("bogus"), Severity::Fail);
        assert_eq!(severity_from_wire(""), Severity::Fail);
        assert_eq!(severity_from_wire("PASS"), Severity::Fail); // case-sensitive, fails closed
    }

    #[test]
    fn known_auth_states_map_through() {
        assert_eq!(auth_state_from_wire("expired"), AuthState::Expired);
        assert_eq!(auth_state_from_wire("revoked"), AuthState::Revoked);
    }

    #[test]
    fn unknown_auth_state_fails_closed_to_revoked() {
        assert_eq!(auth_state_from_wire("something-new"), AuthState::Revoked);
        assert_eq!(auth_state_from_wire(""), AuthState::Revoked);
    }
}
