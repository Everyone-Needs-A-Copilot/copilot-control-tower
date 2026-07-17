//! Typed serde model of `copilot.layers.yml` — the layer manifest `cc`
//! reads (`docs/10-reference/four-tier-topology.md` §4). Mirrors the shape the
//! REAL consumer/authority enforces:
//! `claude-copilot/tools/cc/src/cc/core/ecosystem/manifest.py`
//! (`REQUIRED_LAYER_FIELDS`, `load_layers`, `validate_layers`).
//!
//! **Every known field is `Option`, deliberately** — the same discipline as
//! `model/doctor.rs`'s wire layer (see that module's doc for the full
//! rationale). This struct's only job is "did this parse as *something*
//! shaped like a layer manifest". Required-ness is a semantic question
//! `settings::validate` answers one layer up, so "missing `auth`" and "not
//! YAML at all" stay two distinguishable failures instead of collapsing
//! into one generic `serde` error.
//!
//! **Round-trips faithfully.** Every struct here carries a
//! `#[serde(flatten)] extra: serde_yaml::Mapping` catch-all for fields this
//! app doesn't model yet, so parsing a hand-authored manifest and
//! re-emitting it never silently drops a field the UI never showed — this
//! is the never-destroy groundwork S2's atomic writer builds on
//! (ADR-M2-002, `.copilot/wp/5.md`).

use serde::{Deserialize, Serialize};

/// The whole `copilot.layers.yml` document.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct LayerManifest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<serde_yaml::Value>,
    #[serde(default)]
    pub layers: Vec<Layer>,
    /// Any other top-level key this app doesn't model yet — preserved
    /// verbatim across parse -> emit.
    #[serde(flatten)]
    pub extra: serde_yaml::Mapping,
}

/// One layer entry. Required per `validate_layers`: `id, role, rank,
/// product, source(.repo), auth, activation`. `unit` is optional (only
/// meaningful for `role: department`). Every field is `Option` here — see
/// the module doc for why.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct Layer {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    /// Open vocabulary (not a closed enum) — `personal`/`department`/`org`/
    /// `foundation` are the *known* roles the UX understands, but an
    /// unrecognized role still parses.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    /// Kept as a raw YAML value (not `i64`) so the validator can tell "not
    /// present" apart from "present but not a whole number" (a float or a
    /// boolean) instead of a generic serde type-mismatch error swallowing
    /// that distinction.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rank: Option<serde_yaml::Value>,
    /// Config-driven, not a closed enum (e.g. `knowledge`/`cli`/`claude`/
    /// `codex` today; a fifth product is a data edit).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub product: Option<String>,
    /// Only meaningful for `role: department` — the department-selection
    /// key (four-tier-topology.md §5). Optional everywhere else.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unit: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<Source>,
    /// A REFERENCE only (e.g. `ssh-personal`, `anon`, `gh-device`) — never a
    /// credential value (D-4, `.copilot/wp/5.md`). S1 does not scan this for
    /// secrets; that is S3's fail-closed write-time guard, built on top of
    /// this model.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auth: Option<String>,
    /// `always` | `includeIf:<glob>`. S1 only requires this be present and
    /// non-empty, matching `manifest.py` — it does not validate the glob
    /// shape (the CLI is the final authority on that).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub activation: Option<String>,
    /// Any other per-layer key this app doesn't model yet (e.g. a
    /// hand-authored comment-like `notes:` field) — preserved verbatim.
    #[serde(flatten)]
    pub extra: serde_yaml::Mapping,
}

/// `layer.source` — required to carry at least `repo`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct Source {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub repo: Option<String>,
    // `ref` is a Rust keyword, hence the raw identifier + explicit rename.
    #[serde(rename = "ref", default, skip_serializing_if = "Option::is_none")]
    pub r#ref: Option<String>,
    /// Optional — lets one repo serve multiple layers (`(repo, path)` as
    /// the layer root).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(flatten)]
    pub extra: serde_yaml::Mapping,
}

/// A `copilot.layers.yml` that failed to parse as YAML at all — never a
/// field-shape/semantic problem (those are `validate::FieldError`s on an
/// already-parsed `LayerManifest`). The message always leads with plain
/// language before any parser detail, mirroring `manifest.py`'s
/// `ManifestError` framing for this same failure mode (the CLI is the final
/// authority on this wording, so this stays close to it rather than
/// inventing new phrasing).
#[derive(Debug, Clone, PartialEq)]
pub struct ManifestParseError {
    pub message: String,
}

impl std::fmt::Display for ManifestParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for ManifestParseError {}

/// Parses a `copilot.layers.yml` document's text into the typed model. Does
/// NOT validate required-ness/rank rules — call
/// `settings::validate::validate_layers` on the result next (mirrors
/// `manifest.py`'s `load_layers` / `validate_layers` split).
pub fn parse_manifest(text: &str) -> Result<LayerManifest, ManifestParseError> {
    serde_yaml::from_str(text).map_err(|e| ManifestParseError {
        message: format!(
            "This layer manifest isn't valid YAML, so it can't be read: {e}. \
             If you edited it by hand, check for a missing colon, dash, or indentation."
        ),
    })
}

/// Re-emits the typed model back to YAML text. S1 scope is the pure
/// serialization step only — S2 owns the atomic, backed-up,
/// temp+fsync+rename FILE write that calls this.
pub fn to_yaml_string(manifest: &LayerManifest) -> Result<String, ManifestParseError> {
    serde_yaml::to_string(manifest).map_err(|e| ManifestParseError {
        message: format!("Couldn't turn this manifest back into YAML: {e}."),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> String {
        let path = format!("{}/fixtures/settings/{name}", env!("CARGO_MANIFEST_DIR"));
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"))
    }

    #[test]
    fn valid_manifest_parses_into_typed_layers() {
        let text = fixture("valid-multi-layer.yml");
        let manifest = parse_manifest(&text).expect("should parse");
        assert_eq!(manifest.layers.len(), 4);
        assert_eq!(manifest.layers[0].id.as_deref(), Some("personal-pablo"));
        assert_eq!(manifest.layers[0].role.as_deref(), Some("personal"));
        assert_eq!(
            manifest.layers[0]
                .source
                .as_ref()
                .and_then(|s| s.repo.as_deref()),
            Some("git@github-personal:pablitoalejo/claude-copilot-private.git")
        );
    }

    /// Never-destroy groundwork (ADR-M2-002): a field the UI doesn't model
    /// (`notes:`, hand-added by a human) must survive parse -> emit.
    #[test]
    fn round_trip_preserves_unknown_field() {
        let text = fixture("valid-multi-layer.yml");
        let manifest = parse_manifest(&text).expect("should parse");

        let dept_layer = manifest
            .layers
            .iter()
            .find(|l| l.role.as_deref() == Some("department"))
            .expect("fixture has a department layer");
        assert!(
            dept_layer.extra.contains_key("notes"),
            "fixture's hand-authored `notes` field should be captured in `extra`"
        );

        let re_emitted = to_yaml_string(&manifest).expect("should re-emit");
        let reparsed = parse_manifest(&re_emitted).expect("re-emitted text should parse");
        assert_eq!(manifest, reparsed, "round trip must be lossless");

        let dept_layer_again = reparsed
            .layers
            .iter()
            .find(|l| l.role.as_deref() == Some("department"))
            .expect("still has a department layer after round trip");
        assert!(
            dept_layer_again.extra.contains_key("notes"),
            "`notes` must survive a parse -> emit -> parse round trip"
        );
    }

    #[test]
    fn not_yaml_at_all_is_a_plain_language_parse_error() {
        let err = parse_manifest(": : : not yaml {{{").unwrap_err();
        assert!(
            err.message.contains("isn't valid YAML"),
            "message should lead with plain language, got: {}",
            err.message
        );
    }

    #[test]
    fn empty_document_parses_to_an_empty_manifest() {
        // An empty file is valid (empty) YAML — `layers` defaults to empty,
        // which is a *semantic* problem for `validate::validate_layers`,
        // not a parse failure.
        let manifest = parse_manifest("").expect("empty document should parse");
        assert!(manifest.layers.is_empty());
    }
}
