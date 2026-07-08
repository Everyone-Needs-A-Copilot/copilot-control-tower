//! Fail-closed pre-write guard (M2/S3, `.copilot/wp/5.md`, ADR-M2-003).
//!
//! This module makes two invariants true **by construction** on the Settings
//! manifest-write path, not by review discipline:
//!
//! - **Invariant #6** (secrets never enter inheritance content or any git
//!   repo/config file) — [`scan_for_secrets`] refuses any manifest carrying a
//!   value that *looks like* a credential, anywhere in the document, not only
//!   in `auth`.
//! - **Invariant #4 / the SOUL Convenience-Backdoor anti-pattern**
//!   (security-sensitive config is honored only from the managed/forced
//!   domain, never user-set) — [`enforce_write_allowlist`] refuses any
//!   manifest carrying a managed/forced-domain-only key (the update feed, a
//!   mirror, a trust root, `AllowSelfUpdate`, …) under any spelling.
//!
//! ## STRIDE note — the manifest-write trust boundary
//!
//! The trust boundary this module guards is: **user-editable Settings input
//! -> `copilot.layers.yml` -> the `cc` CLI's resolver**, i.e. the moment
//! Bob/an author-typed value crosses from "form input" into "a file the
//! engine trusts and acts on." Threats classified against that boundary:
//!
//! - **Tampering** — a pasted value (secret, or a managed-domain key) alters
//!   the manifest into something the engine will honor as if it were
//!   trustworthy config. Mitigated by both checks below (fail-closed refusal
//!   before any byte reaches disk).
//! - **Information Disclosure** — a credential accidentally pasted into a
//!   form field lands in a file that is machine-local today but is exactly
//!   the kind of artifact that gets zipped into a bug report, synced to a
//!   backup, or (worst case) committed by a future feature that doesn't know
//!   better. Mitigated by [`scan_for_secrets`] treating the manifest as
//!   untrusted content, not just untrusted-at-the-UI-layer.
//! - **Elevation of Privilege** — the named Convenience-Backdoor: a value
//!   that *looks like* ordinary config (an update-feed URL, a trust root) is
//!   actually security-sensitive state that, if user-settable, lets a local
//!   user (or malware with local-user-level access) repoint the update feed
//!   or disable self-update-lockout — a privilege only the managed/forced
//!   domain should hold. Mitigated by [`enforce_write_allowlist`].
//! - **Repudiation** — a refused write must still be attributable and
//!   diagnosable *without* re-exposing the secret. [`GuardError`] carries the
//!   *class* of problem (which field, which kind) but never the offending
//!   value — see the "never echoes a secret" discipline below.
//! - **Spoofing / Denial of Service** — out of scope for this boundary; a
//!   local Settings form has no network identity to spoof, and refusing an
//!   unsafe write is the *correct* availability trade-off (fail closed, per
//!   this module's whole purpose), not a DoS.
//!
//! ## Never echoes a secret
//!
//! [`GuardError::message`] and [`GuardError::field`] describe the *reason* a
//! value was refused ("looks like a GitHub access token") and *where*
//! ("layer \"personal-pablo\", field \"auth\""; a manifest-wide key name for
//! the allowlist check) — **never the value itself**. This mirrors the "a
//! personal item name is un-emittable in telemetry" discipline extended to
//! secret material: the reason/class is loggable, the content never is. Every
//! adversarial test below asserts the exact secret string used in the
//! fixture does not appear anywhere in the resulting `GuardError` (`Display`
//! or `Debug`).
//!
//! ## How S2/S4 must call this
//!
//! Both checks run **before** any byte reaches disk, on the manifest that is
//! about to be written (the merged result, not just the incoming edit — a
//! defense-in-depth pass over the whole document):
//!
//! ```ignore
//! guard::scan_for_secrets(&merged)?;
//! guard::enforce_write_allowlist(&merged)?;
//! // only now: settings::writer::write_manifest(path, &merged)?;
//! ```
//!
//! A `GuardError` converts into `settings::validate::FieldError`
//! ([`From<GuardError> for FieldError`]) so the UI (S7) renders a guard
//! refusal exactly the same way it renders any other validation problem —
//! one error shape end to end, never a raw guard-internal type reaching the
//! DTO layer.
//!
//! Fail-closed everywhere in this module: a value this scanner cannot
//! classify with confidence is **not** waved through — see each heuristic's
//! doc for its specific threshold, chosen to err toward refusing.

use std::collections::HashMap;

use serde_yaml::{Mapping, Value};

use super::manifest::{Layer, LayerManifest, Source};
use super::validate::FieldError;

// ---------------------------------------------------------------------------
// GuardError
// ---------------------------------------------------------------------------

/// Which of the two invariants a refusal enforces.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GuardErrorKind {
    /// Invariant #6 — a credential-shaped value was found.
    SecretDetected,
    /// Invariant #4 — a managed/forced-domain-only key was present.
    DisallowedField,
}

/// A fail-closed refusal from either guard check. Plain language always
/// (SOUL "a Git error to a non-technical person"); **never** carries the
/// offending secret value — only the field it was found in and a
/// human-readable reason/class. See the module doc's "Never echoes a
/// secret" section.
#[derive(Debug, Clone, PartialEq)]
pub struct GuardError {
    pub kind: GuardErrorKind,
    /// `None` for a manifest-wide problem not attributable to one layer
    /// (e.g. a top-level disallowed key).
    pub layer_id: Option<String>,
    /// The offending field/key path (`"auth"`, `"source.repo"`,
    /// `"extra.UpdateFeedURL"`, …) — never the value.
    pub field: String,
    pub message: String,
}

impl std::fmt::Display for GuardError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for GuardError {}

/// Renders a `GuardError` exactly like any other validation problem — S7
/// never needs to know a refusal came from the guard rather than S1's
/// validator.
impl From<GuardError> for FieldError {
    fn from(e: GuardError) -> Self {
        FieldError {
            layer_id: e.layer_id,
            field: e.field,
            message: e.message,
        }
    }
}

fn secret_error(layer_id: Option<String>, field: String, reason: &str) -> GuardError {
    GuardError {
        kind: GuardErrorKind::SecretDetected,
        message: match &layer_id {
            Some(label) => format!(
                "The layer \"{label}\"'s \"{field}\" value looks like {reason}. Credentials must \
                 never be stored in the layer manifest — use a reference (an auth alias, like \
                 \"ssh-personal\") instead, and keep the actual credential in your OS keychain or \
                 SSH agent."
            ),
            None => format!(
                "The \"{field}\" value looks like {reason}. Credentials must never be stored in \
                 the layer manifest — use a reference instead, and keep the actual credential in \
                 your OS keychain or SSH agent."
            ),
        },
        layer_id,
        field,
    }
}

fn disallowed_error(layer_id: Option<String>, field: String, key: &str) -> GuardError {
    GuardError {
        kind: GuardErrorKind::DisallowedField,
        message: format!(
            "Settings tried to save \"{key}\", which is a security-sensitive setting. That value \
             can only be set by your organization's managed configuration — Settings will never \
             change it here."
        ),
        layer_id,
        field,
    }
}

// ---------------------------------------------------------------------------
// scan_for_secrets — invariant #6
// ---------------------------------------------------------------------------

/// Refuses to persist a manifest carrying any value that looks like a
/// credential — a PEM block, a known token-vendor prefix, an AWS access key,
/// a bearer token, a JWT, a `user:pass@` URL, an inline `key=value`
/// credential assignment, or a long high-entropy blob — anywhere in the
/// document (every typed field, and every unmodeled `extra` field, at every
/// nesting level). Fail closed: any string this scanner cannot positively
/// clear is left alone (it does **not** flag ordinary prose), but every
/// heuristic below is deliberately tuned to over-refuse rather than
/// under-refuse a credential-shaped value.
///
/// Returns the **first** problem found (one refusal is enough to block the
/// whole write; the caller — S2/S4 — should re-run after the user fixes it,
/// same UX shape as `validate_layers` failing a write).
pub fn scan_for_secrets(manifest: &LayerManifest) -> Result<(), GuardError> {
    if let Some(version) = &manifest.version {
        if let Some(reason) = scan_value(version) {
            return Err(secret_error(None, "version".to_string(), reason));
        }
    }
    if let Some(e) = scan_mapping_for_secrets(&manifest.extra, None, "extra") {
        return Err(e);
    }

    for layer in &manifest.layers {
        let label = layer_label(layer);
        if let Some(e) = scan_layer_for_secrets(layer, &label) {
            return Err(e);
        }
    }

    Ok(())
}

fn scan_layer_for_secrets(layer: &Layer, label: &str) -> Option<GuardError> {
    let string_fields: [(&str, &Option<String>); 5] = [
        ("id", &layer.id),
        ("role", &layer.role),
        ("product", &layer.product),
        ("unit", &layer.unit),
        ("auth", &layer.auth),
    ];
    for (field, value) in string_fields {
        if let Some(v) = value {
            if let Some(reason) = secret_reason_in(v) {
                return Some(secret_error(
                    Some(label.to_string()),
                    field.to_string(),
                    reason,
                ));
            }
        }
    }
    if let Some(activation) = &layer.activation {
        if let Some(reason) = secret_reason_in(activation) {
            return Some(secret_error(
                Some(label.to_string()),
                "activation".to_string(),
                reason,
            ));
        }
    }
    if let Some(rank) = &layer.rank {
        if let Some(reason) = scan_value(rank) {
            return Some(secret_error(
                Some(label.to_string()),
                "rank".to_string(),
                reason,
            ));
        }
    }
    if let Some(source) = &layer.source {
        if let Some(e) = scan_source_for_secrets(source, label) {
            return Some(e);
        }
    }
    if let Some(e) = scan_mapping_for_secrets(&layer.extra, Some(label.to_string()), "extra") {
        return Some(e);
    }
    None
}

fn scan_source_for_secrets(source: &Source, label: &str) -> Option<GuardError> {
    let fields: [(&str, &Option<String>); 3] = [
        ("source.repo", &source.repo),
        ("source.ref", &source.r#ref),
        ("source.path", &source.path),
    ];
    for (field, value) in fields {
        if let Some(v) = value {
            if let Some(reason) = secret_reason_in(v) {
                return Some(secret_error(
                    Some(label.to_string()),
                    field.to_string(),
                    reason,
                ));
            }
        }
    }
    scan_mapping_for_secrets(&source.extra, Some(label.to_string()), "source.extra")
}

fn scan_mapping_for_secrets(
    mapping: &Mapping,
    layer_id: Option<String>,
    path: &str,
) -> Option<GuardError> {
    for (key, value) in mapping {
        let key_label = key
            .as_str()
            .map(|s| format!("{path}.{s}"))
            .unwrap_or_else(|| path.to_string());
        // QA adversarial finding: a secret can be smuggled in as the MAP KEY
        // itself (an unmodeled `extra` field literally named e.g.
        // `ghp_xxx...: "innocuous value"`), not only as a value — the
        // original version of this function only ever called `scan_value` on
        // `value`, so a credential-shaped KEY sailed through untouched. Check
        // the key string with the same heuristics before falling through to
        // the value check. Deliberately does NOT reuse `key_label` here (that
        // would embed the secret-shaped key text itself into `GuardError`'s
        // `field`, violating "never echoes a secret" for the one case where
        // the offending text IS the field name) — a fixed, redacted label
        // names the *shape* of the problem instead.
        if let Some(key_str) = key.as_str() {
            if let Some(reason) = secret_reason_in(key_str) {
                return Some(secret_error(
                    layer_id.clone(),
                    format!("{path}.<redacted field name>"),
                    reason,
                ));
            }
        }
        if let Some(reason) = scan_value(value) {
            return Some(secret_error(layer_id.clone(), key_label, reason));
        }
    }
    None
}

/// Recurses into a raw `serde_yaml::Value` (used for `extra` catch-alls and
/// the loosely-typed `rank`/`version` fields) looking for a secret-shaped
/// leaf string.
fn scan_value(value: &Value) -> Option<&'static str> {
    match value {
        Value::String(s) => secret_reason_in(s),
        Value::Sequence(seq) => seq.iter().find_map(scan_value),
        Value::Mapping(map) => map.iter().find_map(|(_, v)| scan_value(v)),
        Value::Tagged(t) => scan_value(&t.value),
        Value::Null | Value::Bool(_) | Value::Number(_) => None,
    }
}

/// A human-readable label for `layer_id` in a `GuardError` — mirrors
/// `settings::validate`'s "the layer in position N" fallback, but this
/// module can't reuse that private helper, so it has its own copy of the
/// same rule.
fn layer_label(layer: &Layer) -> String {
    layer
        .id
        .clone()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| "an unnamed layer".to_string())
}

// ---------------------------------------------------------------------------
// Secret-shape heuristics
// ---------------------------------------------------------------------------

const GITHUB_TOKEN_PREFIXES: [&str; 6] = ["ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_"];
const SLACK_TOKEN_PREFIXES: [&str; 5] = ["xoxb-", "xoxp-", "xoxa-", "xoxr-", "xoxs-"];
const INLINE_SECRET_MARKERS: [&str; 10] = [
    "password=",
    "passwd=",
    "secret=",
    "api_key=",
    "apikey=",
    "access_key=",
    "access_token=",
    "auth_token=",
    "client_secret=",
    "private_key=",
];

/// Returns `Some(reason)` describing *why* `value` looks like a credential,
/// or `None` if it clears every heuristic. Fail-closed by design: each
/// individual heuristic is intentionally permissive about matching (a false
/// positive just means a legitimate value has to be re-entered as a
/// reference, which is the safe failure mode) rather than permissive about
/// missing (a false negative is the invariant-#6 violation this module
/// exists to prevent).
fn secret_reason_in(value: &str) -> Option<&'static str> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }

    if value.contains("-----BEGIN") {
        return Some("a PEM-formatted private key or certificate block");
    }
    for prefix in GITHUB_TOKEN_PREFIXES {
        if value.contains(prefix) {
            return Some("a GitHub access token");
        }
    }
    for prefix in SLACK_TOKEN_PREFIXES {
        if value.contains(prefix) {
            return Some("a Slack API token");
        }
    }
    if contains_aws_access_key(value) {
        return Some("an AWS access key ID");
    }
    if value.to_ascii_lowercase().contains("bearer ") {
        return Some("a bearer authorization token");
    }
    if looks_like_jwt(value) {
        return Some("a JSON Web Token");
    }
    if url_has_embedded_credentials(value) {
        return Some("a username and password embedded directly in a URL");
    }
    let lower = value.to_ascii_lowercase();
    if INLINE_SECRET_MARKERS.iter().any(|m| lower.contains(m)) {
        return Some("an inline credential assignment (e.g. password=... or api_key=...)");
    }
    if value
        .split(|c: char| {
            !(c.is_ascii_alphanumeric() || c == '_' || c == '+' || c == '/' || c == '=')
        })
        .any(|token| is_hex_blob(token) || is_high_entropy_token(token))
    {
        return Some("a long, high-entropy string that looks like key material or an access token");
    }

    None
}

/// A 32+ character run of only hex digits — the shape of a raw key
/// fingerprint, a secret hash, or key material pasted as hex. (This also
/// catches a full 40-char git commit SHA; treated as an acceptable
/// trade-off — refusing a legitimate hex `source.ref` is the safe failure
/// mode, and `source.ref` values in practice are almost always a branch or
/// tag name, not a bare SHA, per this app's own fixtures.)
fn is_hex_blob(token: &str) -> bool {
    token.len() >= 32 && token.chars().all(|c| c.is_ascii_hexdigit())
}

/// A long token with Shannon entropy above a threshold typical English
/// words, hyphenated identifiers, or `snake_case`/`SCREAMING_CASE` phrases
/// never reach — the shape of an API key or access token rather than a
/// word, a slug, or a short identifier.
///
/// Two tiers, both fail-closed toward refusing:
/// - **Mixed-class** (>= 2 of {upper, lower, digit}): threshold 4.0 bits/char
///   — the original heuristic.
/// - **Single-class** (e.g. all-lowercase, all-uppercase): a QA adversarial
///   pass found a 40+-char purely-lowercase-alpha secret (a plausible shape
///   for a lowercase-alphabet vendor token or a base32-lowercase credential)
///   sailed through the mixed-class-only check entirely — `class_count < 2`
///   returned `false` unconditionally, regardless of entropy. A single
///   26-symbol alphabet's ceiling (~4.7 bits/char) is lower than a mixed
///   alphanumeric alphabet's, so this tier requires a higher bar (4.5) to
///   stay clear of ordinary long `snake_case`/`SCREAMING_CASE` phrases
///   (measured ~3.6-4.4 bits/char for realistic multi-word identifiers)
///   while still catching genuinely near-random single-case content.
fn is_high_entropy_token(token: &str) -> bool {
    if token.len() < 24 {
        return false;
    }
    let has_upper = token.chars().any(|c| c.is_ascii_uppercase());
    let has_lower = token.chars().any(|c| c.is_ascii_lowercase());
    let has_digit = token.chars().any(|c| c.is_ascii_digit());
    let class_count = [has_upper, has_lower, has_digit]
        .iter()
        .filter(|&&b| b)
        .count();
    let entropy = shannon_entropy(token);
    if class_count >= 2 {
        entropy >= 4.0
    } else {
        entropy >= 4.5
    }
}

fn shannon_entropy(s: &str) -> f64 {
    let len = s.chars().count() as f64;
    if len == 0.0 {
        return 0.0;
    }
    let mut counts: HashMap<char, usize> = HashMap::new();
    for c in s.chars() {
        *counts.entry(c).or_insert(0) += 1;
    }
    counts
        .values()
        .map(|&c| {
            let p = c as f64 / len;
            -p * p.log2()
        })
        .sum()
}

/// `AKIA`/`ASIA` immediately followed by 16 more uppercase-alnum characters
/// (AWS's fixed 20-char access-key-ID shape), anywhere in `value`. Operates
/// on raw bytes throughout (never slices `value` itself as a `&str`), so an
/// arbitrary/adversarial value containing multi-byte UTF-8 near a false
/// `AKIA`/`ASIA`-like run can never panic on a non-char-boundary slice.
fn contains_aws_access_key(value: &str) -> bool {
    let bytes = value.as_bytes();
    for prefix in [b"AKIA".as_slice(), b"ASIA".as_slice()] {
        let mut i = 0usize;
        while i + prefix.len() <= bytes.len() {
            if &bytes[i..i + prefix.len()] == prefix {
                let end = i + 20;
                if end <= bytes.len() {
                    let candidate = &bytes[i..end];
                    if candidate
                        .iter()
                        .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit())
                    {
                        return true;
                    }
                }
            }
            i += 1;
        }
    }
    false
}

/// Three dot-separated base64url segments, each at least 10 chars, the
/// first starting `eyJ` (the base64 encoding of `{"`, JWT's fixed header
/// shape).
fn looks_like_jwt(value: &str) -> bool {
    let parts: Vec<&str> = value.split('.').collect();
    if parts.len() != 3 {
        return false;
    }
    if parts.iter().any(|p| p.len() < 10) {
        return false;
    }
    let is_base64url = |c: char| c.is_ascii_alphanumeric() || c == '-' || c == '_';
    if !parts.iter().all(|p| p.chars().all(is_base64url)) {
        return false;
    }
    parts[0].starts_with("eyJ")
}

/// `scheme://user:pass@host...` — a colon inside the userinfo segment
/// (before the first `@`, before the authority ends at the next `/`) is the
/// `user:pass@` shape; a bare `user@host` with no colon is not flagged
/// (common, not a credential leak on its own).
fn url_has_embedded_credentials(value: &str) -> bool {
    let Some(scheme_end) = value.find("://") else {
        return false;
    };
    let after_scheme = &value[scheme_end + 3..];
    let authority_end = after_scheme.find('/').unwrap_or(after_scheme.len());
    let authority = &after_scheme[..authority_end];
    match authority.find('@') {
        Some(at) => authority[..at].contains(':'),
        None => false,
    }
}

// ---------------------------------------------------------------------------
// enforce_write_allowlist — invariant #4 / the Convenience Backdoor
// ---------------------------------------------------------------------------

/// The closed set of per-layer fields Settings may ever write (D-1-M2,
/// ADR-M2-003) — everything `settings::manifest::Layer` models as a typed
/// field. `source.repo`/`source.ref`/`source.path` are the `Source` struct's
/// typed fields. This constant exists so a future field addition to the
/// model requires a deliberate, reviewable touch to the fitness test in this
/// module's `tests` — see `allowlist_is_a_closed_set_of_exactly_these_fields`.
pub const ALLOWED_LAYER_FIELDS: &[&str] = &[
    "id",
    "role",
    "product",
    "unit",
    "rank",
    "source.repo",
    "source.ref",
    "source.path",
    "auth",
    "activation",
];

/// The closed set of top-level manifest fields Settings may ever write.
pub const ALLOWED_TOP_LEVEL_FIELDS: &[&str] = &["version", "layers"];

/// The exhaustive, explicitly-named deny-list of managed/forced-domain-only
/// keys (`architecture.md` §8.3's "honored ONLY from the managed domain"
/// list, plus the trust-root/signing/lock keys `config.py`/the WP call out).
/// Every entry here is pre-normalized (see [`normalize_key`]) so
/// `UpdateFeedURL`, `update_feed_url`, and `update-feed-url` are all the same
/// check. This is checked against **keys**, not values, so it can run
/// alongside `scan_for_secrets` without colliding with never-destroy's
/// preservation of an unrelated hand-authored field (e.g. `notes:`) — a key
/// not on this list is never refused by this function, only a key that *is*
/// this exact, named, security-sensitive surface.
const DENIED_KEYS: &[&str] = &[
    // architecture.md §8.3 — honored ONLY from the managed/forced domain.
    "orgslug",
    "department",
    "ecosystemseedurl",
    "githubhost",
    "authmode",
    "host",
    "foundationmirror",
    "httpsproxy",
    "updatefeedurl",
    "allowselfupdate",
    // M4/S4-S5 gap sec found: `UpdateChannel` is read solely via the same
    // forced-domain-only reader as `UpdateFeedURL`/`AllowSelfUpdate`
    // (`updater::trust::update_channel`, FF-M4-4) — it was missing from
    // this list, which would have let it be smuggled into
    // `copilot.layers.yml` as ordinary config even though it's exactly as
    // security-sensitive as its two siblings above (a user-writable channel
    // pin is a supply-chain lever: it can steer this app's own self-update
    // onto a `beta`/`pinned:<version>` feed a local user chose, not IT).
    "updatechannel",
    "disablewizard",
    "deprovisioned",
    "admincontact",
    // M5/S1 gap flagged in `managed::keys`'s module doc ("A real,
    // evidence-based gap this freeze surfaces"): `SharedSecretStoreURL`/
    // `SharedSecretStoreTier` (credentials-and-boundary.md §1.6.2 step 6 —
    // an ENDPOINT REFERENCE, never a secret value, but forced-domain-only
    // exactly like every other key in this list) and `LoginItemManaged`
    // (ADR-M5-004) were reader-side registered in `managed::keys::MANAGED_KEYS`
    // but missing here, so nothing stopped Settings from hand-writing one of
    // these three names into `copilot.layers.yml`'s `extra` mapping and
    // having never-destroy preserve it as if it were ordinary unrecognized
    // config — closed by this addition (M5/S5 hardening fix).
    "sharedsecretstoreurl",
    "sharedsecretstoretier",
    "loginitemmanaged",
    // M7/S2 (task 61, ADR-M7-003, FF-M7-OPTIN): `TelemetryEnabled`/
    // `TelemetryEndpoint` are forced-domain-only, security-sensitive keys
    // added to `managed::keys::MANAGED_KEYS` for the analytics opt-in gate
    // (`telemetry::optin`) — deny-listed here so the same
    // Convenience-Backdoor shape closed for the M4/M5 keys above (a value
    // hand-written into `copilot.layers.yml`'s `extra` mapping and preserved
    // by never-destroy as if it were ordinary config) can never smuggle a
    // silent analytics opt-in, or a redirected collector endpoint, in
    // through Settings.
    "telemetryenabled",
    "telemetryendpoint",
    // Trust roots / signing (compiled-in code, never config — invariant #4).
    "rootkey",
    "keyset",
    "policysigners",
    "trustroot",
    "trustroots",
    "signingkey",
    "signingkeys",
    "minisignpubkey",
    // config.py's `layers.lock_source` / `layers.lock_ref` — forced/managed
    // resolution-lock pointers, never a Settings-writable field.
    "locksource",
    "lockref",
    "layers.locksource",
    "layers.lockref",
];

/// Refuses to persist a manifest carrying any key from [`DENIED_KEYS`],
/// anywhere in the document (top-level, per-layer, per-source, at any
/// nesting depth inside an `extra` mapping) — the SOUL Convenience-Backdoor
/// anti-pattern made structurally impossible rather than merely discouraged.
/// A hand-authored field that is merely *unrecognized* (not on the deny
/// list, e.g. a `notes:` field) is **not** refused here — never-destroy
/// preservation of such fields is S2's job and this function does not
/// second-guess it; this function's only job is the named security-sensitive
/// surface.
pub fn enforce_write_allowlist(manifest: &LayerManifest) -> Result<(), GuardError> {
    if let Some(e) = find_denied_key_in_mapping(&manifest.extra, None, "") {
        return Err(e);
    }

    for layer in &manifest.layers {
        let label = layer_label(layer);
        if let Some(e) = find_denied_key_in_mapping(&layer.extra, Some(label.clone()), "") {
            return Err(e);
        }
        if let Some(source) = &layer.source {
            if let Some(e) = find_denied_key_in_mapping(&source.extra, Some(label), "source.") {
                return Err(e);
            }
        }
    }

    Ok(())
}

fn find_denied_key_in_mapping(
    mapping: &Mapping,
    layer_id: Option<String>,
    prefix: &str,
) -> Option<GuardError> {
    for (key, value) in mapping {
        if let Some(key_str) = key.as_str() {
            if is_denied_key(key_str) {
                return Some(disallowed_error(
                    layer_id,
                    format!("{prefix}{key_str}"),
                    key_str,
                ));
            }
        }
        if let Some(e) = find_denied_key_in_value(value, layer_id.clone(), prefix) {
            return Some(e);
        }
    }
    None
}

fn find_denied_key_in_value(
    value: &Value,
    layer_id: Option<String>,
    prefix: &str,
) -> Option<GuardError> {
    match value {
        Value::Mapping(m) => find_denied_key_in_mapping(m, layer_id, prefix),
        Value::Sequence(seq) => seq
            .iter()
            .find_map(|item| find_denied_key_in_value(item, layer_id.clone(), prefix)),
        Value::Tagged(t) => find_denied_key_in_value(&t.value, layer_id, prefix),
        _ => None,
    }
}

fn is_denied_key(key: &str) -> bool {
    DENIED_KEYS.contains(&normalize_key(key).as_str())
}

/// Lowercases and strips everything except letters/digits/`.` — collapses
/// `UpdateFeedURL` / `update_feed_url` / `update-feed-url` to the same
/// string, while keeping `.` so dotted config-style keys
/// (`layers.lock_source`) stay distinguishable from their bare form
/// (`lock_source`).
fn normalize_key(key: &str) -> String {
    key.chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '.')
        .collect::<String>()
        .to_ascii_lowercase()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::manifest::parse_manifest;

    fn fixture_text(name: &str) -> String {
        let path = format!("{}/fixtures/settings/{name}", env!("CARGO_MANIFEST_DIR"));
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"))
    }

    fn fixture_manifest(name: &str) -> LayerManifest {
        parse_manifest(&fixture_text(name)).unwrap_or_else(|e| panic!("parse {name}: {e}"))
    }

    // -- clean manifest passes both checks -----------------------------

    #[test]
    fn a_clean_manifest_passes_the_secret_scan() {
        let manifest = fixture_manifest("valid-multi-layer.yml");
        assert_eq!(scan_for_secrets(&manifest), Ok(()));
    }

    #[test]
    fn a_clean_manifest_passes_the_write_allowlist() {
        let manifest = fixture_manifest("valid-multi-layer.yml");
        assert_eq!(enforce_write_allowlist(&manifest), Ok(()));
    }

    // -- scan_for_secrets: adversarial cases -----------------------------

    #[test]
    fn a_github_token_in_auth_is_refused() {
        let manifest = fixture_manifest("secret-looking-auth.yml");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_eq!(err.field, "auth");
        assert_secret_value_never_leaks(&err, "ghp_1234567890ABCDEFabcdef1234567890AB");
    }

    #[test]
    fn a_url_with_embedded_credentials_is_refused() {
        let manifest = fixture_manifest("secret-embedded-creds-url.yml");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_eq!(err.field, "source.repo");
        assert_secret_value_never_leaks(&err, "ghp_1234567890ABCDEFabcdef1234567890AB");
        assert_secret_value_never_leaks(&err, "x:ghp_1234567890ABCDEFabcdef1234567890AB@");
    }

    #[test]
    fn a_pem_private_key_block_is_refused() {
        let manifest = fixture_manifest("secret-pem-block.yml");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert!(err.message.contains("private key"), "{}", err.message);
        assert_secret_value_never_leaks(&err, "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ");
    }

    #[test]
    fn a_high_entropy_hex_blob_is_refused() {
        let manifest = fixture_manifest("secret-high-entropy-hex.yml");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_secret_value_never_leaks(
            &err,
            "9f8a1c2d3e4b5a6f7089abcdef0123456789abcdef0123456789abcdef01234",
        );
    }

    #[test]
    fn a_high_entropy_mixed_case_token_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: aB3xQ9zK7mP2vN8tR5wL1yJ6hF4dC0sE
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_secret_value_never_leaks(&err, "aB3xQ9zK7mP2vN8tR5wL1yJ6hF4dC0sE");
    }

    /// QA adversarial finding: a long, purely-lowercase-alpha high-entropy
    /// token (no digits, no uppercase — the shape a lowercase-alphabet
    /// vendor token or base32-lowercase credential would take) must still be
    /// refused. Before the fix, `is_high_entropy_token`'s `class_count < 2`
    /// gate let ANY single-character-class string through regardless of
    /// entropy, so this exact shape sailed past the guard entirely.
    #[test]
    fn a_lowercase_only_high_entropy_token_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: qwoeiruzmxnbvcpaslkjfghdtyuiqpwoeirutyfgh
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_secret_value_never_leaks(&err, "qwoeiruzmxnbvcpaslkjfghdtyuiqpwoeirutyfgh");
    }

    /// The same shape found via an embedded query-string value in
    /// `source.repo`, matching the existing embedded-credentials-in-a-URL
    /// coverage pattern.
    #[test]
    fn a_lowercase_only_high_entropy_token_in_a_repo_url_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: "https://example.com/repo.git?token=qwoeiruzmxnbvcpaslkjfghdtyuiqpwoeirutyfgh"
    auth: ssh-personal
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
    }

    /// Ordinary long `snake_case`/`SCREAMING_CASE`/hyphenated phrases (a
    /// realistic honest value someone might type into a free-text field)
    /// must NOT be flagged by the single-class entropy tier — only
    /// genuinely near-random single-case content should be.
    #[test]
    fn ordinary_long_single_case_phrases_are_never_flagged() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
      ref: some-long-descriptive-branch-name-for-a-feature
    auth: ssh-personal
    activation: always
    notes: "SOME_LONG_CONSTANT_NAME_HERE_FOR_TESTING and personal_department_organization_layer"
"#;
        let manifest = parse_manifest(text).expect("should parse");
        assert_eq!(scan_for_secrets(&manifest), Ok(()));
    }

    /// QA adversarial finding: a secret hidden as the KEY of an unmodeled
    /// `extra` field (not its value) must still be refused — before the fix,
    /// `scan_mapping_for_secrets` only ever inspected values.
    #[test]
    fn a_secret_hidden_as_an_extra_field_key_rather_than_its_value_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: ssh-personal
    activation: always
    ghp_1234567890ABCDEFabcdef1234567890AB: "innocuous value"
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_secret_value_never_leaks(&err, "ghp_1234567890ABCDEFabcdef1234567890AB");
    }

    #[test]
    fn a_bearer_token_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: "Bearer sk-abcdefghijklmnopqrstuvwxyz012345"
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_secret_value_never_leaks(&err, "sk-abcdefghijklmnopqrstuvwxyz012345");
    }

    #[test]
    fn an_inline_password_assignment_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: "postgres://db.example.com/mydb?password=hunter2superSecret"
    auth: ssh-personal
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_secret_value_never_leaks(&err, "hunter2superSecret");
    }

    #[test]
    fn an_aws_access_key_id_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: AKIAIOSFODNN7EXAMPLE
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_secret_value_never_leaks(&err, "AKIAIOSFODNN7EXAMPLE");
    }

    #[test]
    fn a_jwt_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dGhpc2lzYWZha2VzaWduYXR1cmU
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_secret_value_never_leaks(&err, "dGhpc2lzYWZha2VzaWduYXR1cmU");
    }

    /// A secret buried in an *unmodeled* per-layer field (S1's `extra`
    /// catch-all) must still be caught — the scan is not limited to typed
    /// fields.
    #[test]
    fn a_secret_hidden_in_an_unmodeled_extra_field_is_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: ssh-personal
    activation: always
    notes: "backup token ghp_ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ just in case"
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = scan_for_secrets(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::SecretDetected);
        assert_eq!(err.field, "extra.notes");
        assert_secret_value_never_leaks(&err, "ghp_ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ");
    }

    /// Ordinary prose, plain repo URLs, short slugs, and version pins must
    /// never trip the scanner — otherwise the guard would be unusable.
    #[test]
    fn ordinary_non_secret_values_are_never_flagged() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:pablitoalejo/claude-copilot-private.git
      ref: main
    auth: ssh-personal
    activation: always
    notes: "hand-added by Pablo — do not remove without asking eng-platform"
  - id: foundation
    role: foundation
    product: claude
    rank: 40
    source:
      repo: https://github.com/Everyone-Needs-A-Copilot/claude-copilot.git
      ref: "^5.13.0"
    auth: anon
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        assert_eq!(scan_for_secrets(&manifest), Ok(()));
    }

    fn assert_secret_value_never_leaks(err: &GuardError, secret_fragment: &str) {
        let display = err.to_string();
        let debug = format!("{err:?}");
        assert!(
            !display.contains(secret_fragment),
            "Display leaked the secret value: {display}"
        );
        assert!(
            !debug.contains(secret_fragment),
            "Debug leaked the secret value: {debug}"
        );
        assert!(
            !err.message.contains(secret_fragment),
            "message leaked the secret value: {}",
            err.message
        );
    }

    // -- enforce_write_allowlist: adversarial cases ----------------------

    #[test]
    fn top_level_and_per_layer_sensitive_key_injection_is_refused() {
        let manifest = fixture_manifest("secret-sensitive-key-injection.yml");
        let err = enforce_write_allowlist(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::DisallowedField);
    }

    /// The exhaustive deny-list fitness test (WP acceptance criterion): every
    /// named security-sensitive key, in every common spelling, is refused —
    /// both as a top-level key and as a per-layer `extra` key.
    #[test]
    fn every_deny_listed_key_is_refused_top_level_and_per_layer() {
        let human_spellings = [
            "UpdateFeedURL",
            "update_feed_url",
            "FoundationMirror",
            "EcosystemSeedURL",
            "HTTPSProxy",
            "GitHubHost",
            "AuthMode",
            "Host",
            "AllowSelfUpdate",
            "UpdateChannel",
            "DisableWizard",
            "Deprovisioned",
            "AdminContact",
            "OrgSlug",
            "Department",
            "SharedSecretStoreURL",
            "shared_secret_store_url",
            "SharedSecretStoreTier",
            "LoginItemManaged",
            "login_item_managed",
            "TelemetryEnabled",
            "telemetry_enabled",
            "TelemetryEndpoint",
            "telemetry_endpoint",
            "root_key",
            "key_set",
            "policy_signers",
            "trust_roots",
            "signing_key",
            "lock_source",
            "lock_ref",
        ];

        for key in human_spellings {
            let top_level_yaml = format!(
                "version: 1\n{key}: \"whatever-value\"\nlayers:\n  - id: personal-pablo\n    role: personal\n    product: claude\n    rank: 10\n    source:\n      repo: git@github-personal:me/repo.git\n    auth: ssh-personal\n    activation: always\n"
            );
            let manifest = parse_manifest(&top_level_yaml)
                .unwrap_or_else(|e| panic!("fixture for {key:?} should parse: {e}"));
            let err = match enforce_write_allowlist(&manifest) {
                Ok(()) => panic!("top-level key {key:?} must be refused"),
                Err(e) => e,
            };
            assert_eq!(err.kind, GuardErrorKind::DisallowedField, "key {key:?}");

            let per_layer_yaml = format!(
                "version: 1\nlayers:\n  - id: personal-pablo\n    role: personal\n    product: claude\n    rank: 10\n    source:\n      repo: git@github-personal:me/repo.git\n    auth: ssh-personal\n    activation: always\n    {key}: \"whatever-value\"\n"
            );
            let manifest = parse_manifest(&per_layer_yaml)
                .unwrap_or_else(|e| panic!("fixture for {key:?} should parse: {e}"));
            let err = match enforce_write_allowlist(&manifest) {
                Ok(()) => panic!("per-layer key {key:?} must be refused"),
                Err(e) => e,
            };
            assert_eq!(err.kind, GuardErrorKind::DisallowedField, "key {key:?}");
        }
    }

    #[test]
    fn a_denied_key_nested_inside_an_unrelated_extra_mapping_is_still_refused() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: ssh-personal
    activation: always
    notes:
      nested:
        AllowSelfUpdate: true
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = enforce_write_allowlist(&manifest).expect_err("must refuse");
        assert_eq!(err.kind, GuardErrorKind::DisallowedField);
    }

    /// A hand-authored, merely-unrecognized field (never-destroy's `notes:`)
    /// must NOT be refused by the allowlist guard — only the named
    /// security-sensitive surface is in scope here.
    #[test]
    fn an_unrelated_hand_authored_field_is_not_refused_by_the_allowlist() {
        let manifest = fixture_manifest("valid-multi-layer.yml");
        assert!(
            manifest
                .layers
                .iter()
                .any(|l| l.extra.contains_key("notes")),
            "fixture should still carry the hand-authored notes field"
        );
        assert_eq!(enforce_write_allowlist(&manifest), Ok(()));
    }

    #[test]
    fn disallowed_field_error_never_echoes_a_secret_shaped_value_either() {
        // Even when the disallowed key's *value* happens to look secret-ish,
        // the allowlist error must still only ever name the key, not the
        // value, and no test elsewhere requires the value to be quoted.
        let text = r#"
version: 1
UpdateFeedURL: "https://evil.example.com/feed.json?token=ghp_totallyASecretValue123456"
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: ssh-personal
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let err = enforce_write_allowlist(&manifest).expect_err("must refuse");
        assert_secret_value_never_leaks(&err, "ghp_totallyASecretValue123456");
        assert_secret_value_never_leaks(&err, "https://evil.example.com/feed.json");
    }

    // -- the allowlist is a closed set (fitness function) -----------------

    /// A future field addition to `Layer`/`LayerManifest` must force a
    /// deliberate edit to this test, so the write surface can never silently
    /// widen. If this test breaks because a field was legitimately added,
    /// update both this constant AND confirm the new field is genuinely
    /// non-security-sensitive before doing so.
    #[test]
    fn allowlist_is_a_closed_set_of_exactly_these_fields() {
        assert_eq!(
            ALLOWED_LAYER_FIELDS,
            &[
                "id",
                "role",
                "product",
                "unit",
                "rank",
                "source.repo",
                "source.ref",
                "source.path",
                "auth",
                "activation",
            ]
        );
        assert_eq!(ALLOWED_TOP_LEVEL_FIELDS, &["version", "layers"]);
        assert_eq!(
            ALLOWED_LAYER_FIELDS.len(),
            10,
            "the write surface widened without a deliberate edit to this test"
        );
    }

    #[test]
    fn normalize_key_collapses_common_spellings_to_the_same_string() {
        assert_eq!(
            normalize_key("UpdateFeedURL"),
            normalize_key("update_feed_url")
        );
        assert_eq!(
            normalize_key("UpdateFeedURL"),
            normalize_key("update-feed-url")
        );
        assert_eq!(normalize_key("lock_source"), "locksource");
        assert_eq!(normalize_key("layers.lock_source"), "layers.locksource");
        assert_ne!(
            normalize_key("lock_source"),
            normalize_key("layers.lock_source"),
            "the bare and dotted forms must stay distinguishable"
        );
    }

    #[test]
    fn guard_error_converts_into_field_error_for_the_ui() {
        let err = disallowed_error(
            Some("personal-pablo".to_string()),
            "extra.UpdateFeedURL".to_string(),
            "UpdateFeedURL",
        );
        let field_error: FieldError = err.into();
        assert_eq!(field_error.layer_id, Some("personal-pablo".to_string()));
        assert_eq!(field_error.field, "extra.UpdateFeedURL");
    }
}
