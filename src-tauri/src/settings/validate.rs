//! Validates layer-manifest invariants — mirrors the REAL consumer/
//! authority's `validate_layers` exactly:
//! `claude-copilot/tools/cc/src/cc/core/ecosystem/manifest.py`.
//!
//! **This validator is a client-side pre-check only.** The CLI's
//! `validate_layers` remains the final fail-closed authority (invariant
//! #1). If in doubt, this file matches that function's rules — it never
//! invents a stricter or looser check.
//!
//! Rules mirrored (see `manifest.py::validate_layers`'s docstring):
//!   - at least one layer is declared;
//!   - every layer has all of `id, role, rank, product, source, auth,
//!     activation`, non-empty;
//!   - `role` and `product` are non-empty strings (open vocabulary, not a
//!     closed enum — any non-empty string is "sane");
//!   - `rank` is an integer;
//!   - ranks are unique — hard error on any equal-rank pair;
//!   - manifest list order agrees with ascending rank;
//!   - `source` is an object with at least a `repo` key.
//!
//! **Deliberately NOT checked here** (out of scope for this validator, per
//! `.copilot/wp/5.md`'s S1/S3 split): `auth`'s *content* is never scanned
//! for secret-shaped values — that is S3's fail-closed write-time guard,
//! built on top of this model. `activation`'s glob shape
//! (`includeIf:<glob>`) is not checked, matching `manifest.py`, which only
//! requires it be present and non-empty.
//!
//! Every message here is plain language — no raw yaml/serde/git text, no
//! stack traces (SOUL "a Git error to a non-technical person"). This is
//! also `dto::FieldError` — the same type `SettingsState.errors` (S6) uses,
//! so there is exactly one error shape from validator to IPC to UI.

use super::manifest::{Layer, LayerManifest};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// One structured, plain-language validation problem.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FieldError {
    /// `None` for a manifest-wide problem (e.g. "no layers declared") that
    /// isn't attributable to one layer.
    pub layer_id: Option<String>,
    /// The offending field name (`"rank"`, `"source.repo"`, …) or a
    /// manifest-wide marker (`"layers"`) when `layer_id` is `None`.
    pub field: String,
    /// Plain language always: names what's wrong and, where it helps, how
    /// to fix it. Never a raw parser/serde/git message.
    pub message: String,
}

/// Validates `manifest.layers` against the rules in the module doc.
/// Returns every problem found (not just the first — unlike
/// `manifest.py`'s fail-fast `raise`, this collects everything so a
/// Settings form (S7) can show every problem in one pass instead of a
/// re-submit loop). An empty result means the manifest is valid.
pub fn validate_layers(manifest: &LayerManifest) -> Vec<FieldError> {
    let layers = &manifest.layers;
    let mut errors = Vec::new();

    if layers.is_empty() {
        errors.push(FieldError {
            layer_id: None,
            field: "layers".to_string(),
            message: "This manifest doesn't list any layers yet, so there's nothing to sync. \
                      Add at least one layer."
                .to_string(),
        });
        return errors;
    }

    let mut seen_ranks: HashMap<i64, String> = HashMap::new();
    let mut prev_rank: Option<i64> = None;

    for (idx, layer) in layers.iter().enumerate() {
        let label = layer_label(layer, idx);

        let mut missing: Vec<&'static str> = Vec::new();
        if is_blank(&layer.id) {
            missing.push("id");
        }
        if is_blank(&layer.role) {
            missing.push("role");
        }
        if layer.rank.is_none() {
            missing.push("rank");
        }
        if is_blank(&layer.product) {
            missing.push("product");
        }
        if layer.source.is_none() {
            missing.push("source");
        }
        if is_blank(&layer.auth) {
            missing.push("auth");
        }
        if is_blank(&layer.activation) {
            missing.push("activation");
        }

        for field in &missing {
            errors.push(FieldError {
                layer_id: Some(label.clone()),
                field: field.to_string(),
                message: format!(
                    "The layer \"{label}\" is missing its {field}. Every layer needs an id, \
                     role, rank, product, source, auth, and activation."
                ),
            });
        }

        if let Some(rank_value) = &layer.rank {
            match rank_as_i64(rank_value) {
                Some(rank) => {
                    if let Some(other_label) = seen_ranks.get(&rank) {
                        errors.push(FieldError {
                            layer_id: Some(label.clone()),
                            field: "rank".to_string(),
                            message: format!(
                                "\"{label}\" and \"{other_label}\" both use rank {rank}. Give \
                                 one of them a different number — ranks must be unique (gaps of \
                                 10, like 10/20/30, leave room to insert a layer later without \
                                 renumbering)."
                            ),
                        });
                    } else {
                        seen_ranks.insert(rank, label.clone());
                    }

                    if let Some(prev) = prev_rank {
                        if rank <= prev {
                            errors.push(FieldError {
                                layer_id: Some(label.clone()),
                                field: "rank".to_string(),
                                message: format!(
                                    "\"{label}\" (rank {rank}) is out of order in the list — its \
                                     rank should be higher than the layer above it (rank {prev}). \
                                     Reorder the list so rank increases from top to bottom \
                                     (highest precedence first)."
                                ),
                            });
                        }
                    }
                    prev_rank = Some(rank);
                }
                None => {
                    errors.push(FieldError {
                        layer_id: Some(label.clone()),
                        field: "rank".to_string(),
                        message: format!(
                            "\"{label}\"'s rank isn't a whole number. Ranks must be plain \
                             integers, like 10, 20, or 30 — lower numbers take precedence."
                        ),
                    });
                }
            }
        }

        if let Some(source) = &layer.source {
            if is_blank(&source.repo) {
                errors.push(FieldError {
                    layer_id: Some(label.clone()),
                    field: "source.repo".to_string(),
                    message: format!(
                        "\"{label}\" doesn't say which repository to sync from. Add a \
                         `source.repo` value (a git URL)."
                    ),
                });
            }
        }
    }

    errors
}

/// A human-readable stand-in for a layer that's missing (or has a blank)
/// `id`, mirroring `manifest.py`'s `<unnamed layer at position {idx}>`, in
/// plain language.
fn layer_label(layer: &Layer, idx: usize) -> String {
    layer
        .id
        .clone()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| format!("the layer in position {} (it has no id yet)", idx + 1))
}

fn is_blank(value: &Option<String>) -> bool {
    match value {
        None => true,
        Some(s) => s.trim().is_empty(),
    }
}

/// `Some(n)` only for a whole-number YAML value (rejects bools, floats,
/// strings, etc.) — mirrors `manifest.py`'s
/// `isinstance(rank, int) and not isinstance(rank, bool)`.
///
/// `pub(crate)` (M2/S4/S6): `settings::authoring` (reading an existing
/// layer's rank to reuse it, and to know which ranks are already taken) and
/// `commands::get_settings` (projecting a `Layer.rank` into `LayerRow.rank`)
/// both need the SAME "is this really a whole-number rank" rule S1 already
/// wrote — never a second, drifting copy of this parse.
pub(crate) fn rank_as_i64(value: &serde_yaml::Value) -> Option<i64> {
    match value {
        serde_yaml::Value::Number(n) => {
            if n.is_i64() {
                n.as_i64()
            } else if n.is_u64() {
                n.as_u64().and_then(|v| i64::try_from(v).ok())
            } else {
                None // a float rank is not a whole number
            }
        }
        _ => None, // bools/strings/sequences/mappings are never a rank
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::manifest::{parse_manifest, LayerManifest};

    fn fixture_manifest(name: &str) -> LayerManifest {
        let path = format!("{}/fixtures/settings/{name}", env!("CARGO_MANIFEST_DIR"));
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_manifest(&text).unwrap_or_else(|e| panic!("parse {path}: {e}"))
    }

    fn assert_no_jargon(errors: &[FieldError]) {
        let banned = [
            "yaml",
            "serde",
            "traceback",
            "panicked",
            "unwrap",
            "stack trace",
            "Err(",
        ];
        for e in errors {
            let lower = e.message.to_lowercase();
            for term in banned {
                assert!(
                    !lower.contains(&term.to_lowercase()),
                    "message leaks jargon {term:?}: {}",
                    e.message
                );
            }
        }
    }

    #[test]
    fn valid_manifest_has_no_errors() {
        let manifest = fixture_manifest("valid-multi-layer.yml");
        let errors = validate_layers(&manifest);
        assert!(errors.is_empty(), "unexpected errors: {errors:?}");
    }

    #[test]
    fn duplicate_rank_is_rejected_with_plain_language() {
        let manifest = fixture_manifest("invalid-duplicate-rank.yml");
        let errors = validate_layers(&manifest);
        assert!(!errors.is_empty());
        assert!(errors
            .iter()
            .any(|e| e.field == "rank" && e.message.contains("both use rank")));
        assert_no_jargon(&errors);
    }

    #[test]
    fn non_ascending_rank_is_rejected_with_plain_language() {
        let manifest = fixture_manifest("invalid-non-ascending-rank.yml");
        let errors = validate_layers(&manifest);
        assert!(errors
            .iter()
            .any(|e| e.field == "rank" && e.message.contains("out of order")));
        assert_no_jargon(&errors);
    }

    #[test]
    fn missing_required_field_is_rejected_with_plain_language() {
        let manifest = fixture_manifest("invalid-missing-required-field.yml");
        let errors = validate_layers(&manifest);
        assert!(errors.iter().any(|e| e.field == "auth"));
        assert_no_jargon(&errors);
    }

    /// D-4 / ADR-M2-003 (`.copilot/wp/5.md`): `auth` is a reference, never a
    /// credential. S1 mirrors `manifest.py::validate_layers`, which has no
    /// opinion on `auth`'s *content* — it only requires the field be a
    /// non-empty string. The fail-closed secret scan is S3's write-time
    /// guard, built ON TOP of this validator (S3 `Depends: S1`). This
    /// fixture doubles as a ready-made secret-shaped value for S3's tests;
    /// asserting here that S1 does NOT reject it keeps the two layers'
    /// responsibilities from blurring together.
    #[test]
    fn secret_looking_auth_is_structurally_valid_s3_refuses_it_not_s1() {
        let manifest = fixture_manifest("secret-looking-auth.yml");
        let errors = validate_layers(&manifest);
        assert!(
            errors.is_empty(),
            "S1 must not scan `auth` content — that's S3's job: {errors:?}"
        );
    }

    #[test]
    fn empty_manifest_is_rejected_as_manifest_wide_error() {
        let manifest = LayerManifest::default();
        let errors = validate_layers(&manifest);
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].layer_id, None);
        assert_no_jargon(&errors);
    }

    #[test]
    fn non_integer_rank_is_rejected() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: "ten"
    source:
      repo: git@github-personal:me/repo.git
    auth: ssh-personal
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let errors = validate_layers(&manifest);
        assert!(errors
            .iter()
            .any(|e| e.field == "rank" && e.message.contains("whole number")));
    }

    #[test]
    fn boolean_rank_is_rejected_not_treated_as_zero_or_one() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: true
    source:
      repo: git@github-personal:me/repo.git
    auth: ssh-personal
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let errors = validate_layers(&manifest);
        assert!(errors
            .iter()
            .any(|e| e.field == "rank" && e.message.contains("whole number")));
    }

    #[test]
    fn missing_source_repo_is_rejected() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      ref: main
    auth: ssh-personal
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let errors = validate_layers(&manifest);
        assert!(errors.iter().any(|e| e.field == "source.repo"));
    }

    /// `manifest.py` gives `product` an explicit `isinstance(str) and
    /// non-empty` check on top of the generic required-field check — an
    /// empty string (as opposed to the key being absent entirely) must
    /// still be rejected as "missing".
    #[test]
    fn empty_string_product_is_rejected_as_missing() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: ""
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: ssh-personal
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let errors = validate_layers(&manifest);
        assert!(
            errors.iter().any(|e| e.field == "product"),
            "expected a product error, got: {errors:?}"
        );
        assert_no_jargon(&errors);
    }

    /// Same as above for `role` — also `isinstance(str) and non-empty` in
    /// `manifest.py`.
    #[test]
    fn empty_string_role_is_rejected_as_missing() {
        let text = r#"
version: 1
layers:
  - id: personal-pablo
    role: ""
    product: claude
    rank: 10
    source:
      repo: git@github-personal:me/repo.git
    auth: ssh-personal
    activation: always
"#;
        let manifest = parse_manifest(text).expect("should parse");
        let errors = validate_layers(&manifest);
        assert!(
            errors.iter().any(|e| e.field == "role"),
            "expected a role error, got: {errors:?}"
        );
        assert_no_jargon(&errors);
    }
}
