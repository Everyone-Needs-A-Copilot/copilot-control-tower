//! Wire-format serde structs mirroring
//! `docs/01-architecture/schemas/doctor.schema.json` exactly (T3).
//!
//! Top level: `schema_version`, `host`, `score` (0-100, deliberately *never*
//! read again after this struct — see the "no-compute" fitness test), `status`
//! (the CLI-computed ~10-state worst-wins enum), `offline`, `checkers[]`
//! (`id`, `severity`, `destructive` required; `detail`/`repair`/`layer`/
//! `product`/`local_sha`/`remote_sha`/`path`/`escalate` optional), `auth[]`
//! (`identity`, `scope`, `state` (`expired`|`revoked`), `expires_at`).
//!
//! **Every field here is `Option`, deliberately — even the schema's
//! `required` ones.** This struct's only job is "did this parse as *some*
//! JSON shaped roughly like a doctor verdict". If a required field were
//! non-`Option`, a missing field would fail `serde_json::from_str` with one
//! generic error, collapsing every "which required field is missing" case
//! into an undifferentiated parse error. `model::state::parse_doctor_body`
//! needs to tell "missing `severity`" (→ `CliUnreadableReason::MissingSecurityField`)
//! apart from "not JSON at all" (→ `CliUnreadableReason::ParseError`), so the
//! requiredness check happens explicitly, one layer up, over this
//! permissive struct.
//!
//! `#[serde(deny_unknown_fields)]` on the top level mirrors the schema's own
//! `"additionalProperties": false` — an unexpected extra top-level key is
//! itself untrustworthy content. `checkers[]`/`auth[]` items stay open
//! (`additionalProperties: true` in the schema); unrecognized extra fields on
//! those are silently ignored, matching serde's default.

use serde::Deserialize;

/// The raw wire shape of a `doctor --json` body. See the module doc for why
/// every field — including the schema's `required` ones — is `Option` here.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DoctorWire {
    pub schema_version: Option<String>,
    pub host: Option<String>,
    pub score: Option<i64>,
    pub generated_at: Option<String>,
    pub status: Option<String>,
    pub offline: Option<bool>,
    pub checkers: Option<Vec<CheckerWire>>,
    pub auth: Option<Vec<AuthWire>>,
}

/// One checker entry. `id`/`severity`/`destructive` are the three
/// schema-`required`, security-relevant fields; their structural absence is
/// resolved (to `CliUnreadableReason::MissingSecurityField`) by
/// `model::state::parse_doctor_body`, not by this struct.
#[derive(Debug, Deserialize)]
pub struct CheckerWire {
    pub id: Option<String>,
    pub severity: Option<String>,
    pub detail: Option<String>,
    pub repair: Option<String>,
    pub destructive: Option<bool>,
    pub layer: Option<String>,
    pub product: Option<String>,
    pub local_sha: Option<String>,
    pub remote_sha: Option<String>,
    pub path: Option<String>,
    pub escalate: Option<String>,
}

/// One auth entry. `identity`/`scope`/`state` are schema-required.
#[derive(Debug, Deserialize)]
pub struct AuthWire {
    pub identity: Option<String>,
    pub scope: Option<String>,
    pub state: Option<String>,
    pub expires_at: Option<String>,
}
