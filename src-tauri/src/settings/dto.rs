//! Settings IPC DTOs (S6/S7's contract) — mirrored 1:1 by
//! `src/types.ts`'s `SettingsState` / `LayerRow` / `FieldError` / `LayerInput`.
//!
//! **S1 defines these types only.** Wiring the real `get_settings()` /
//! `save_settings()` commands around them — the manifest -> `LayerRow`
//! projection, the `LayerInput` -> validated `Layer` assembly — is S6/S4
//! (`.copilot/wp/5.md`). Freezing the shape now lets S4/S6/S7 build against
//! it in parallel, the same way M1's `RenderState` let T5/T7 build in
//! parallel against a static fixture before the real command existed.
//!
//! Field names are plain snake_case on both sides (no `rename_all`), same
//! convention as `render::derive::RenderState` — the web UI reads these
//! fields directly, no camelCase translation layer.

use serde::{Deserialize, Serialize};

pub use super::validate::FieldError;

/// The three tiers Settings can author (D-1-M2, `.copilot/wp/5.md`).
/// Foundation is the base tier and is never user-authored via Settings, so
/// it has no variant here — only what a solo/unmanaged user (or an
/// early-adopter author) can wire.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Tier {
    Org,
    Dept,
    Personal,
}

impl Tier {
    /// The exact wire/JSON spelling (`"org"` / `"dept"` / `"personal"`) —
    /// the same string `#[serde(rename_all = "snake_case")]` produces above.
    /// `settings::authoring` uses this to build a stable `<tier>-<product>`
    /// layer id (matching the convention the Settings web UI's own dev
    /// fixtures use, e.g. `"personal-claude"`, `"dept-cli"`); it is
    /// deliberately NOT the same string as the manifest's `role` vocabulary
    /// (`"department"`, not `"dept"` — four-tier-topology.md §4), which is a
    /// separate mapping `settings::authoring` owns.
    pub(crate) fn wire(self) -> &'static str {
        match self {
            Tier::Org => "org",
            Tier::Dept => "dept",
            Tier::Personal => "personal",
        }
    }
}

/// One layer, projected for the Settings UI. `id`/`rank`/`auth_ref` are
/// always CLI/tier-table derived by the time this DTO is built — never
/// user-typed (D-1-M2) — so this struct carries the *result*, not an
/// editable identity.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LayerRow {
    pub id: String,
    pub product: String,
    pub tier: Tier,
    pub repo_url: String,
    /// A REFERENCE only (e.g. `ssh-personal`, `anon`) — never a credential
    /// value (D-4). Matches `manifest::Layer::auth`'s contract.
    pub auth_ref: String,
    pub rank: i64,
    /// `false` on a managed machine for a locked org/dept row (S5's managed
    /// gate) — Settings renders a locked row read-only rather than omitting
    /// it, so Bob sees "managed by your organization" instead of a vanished
    /// row.
    pub editable: bool,
}

/// The full Settings surface `get_settings()` returns (S6).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SettingsState {
    /// `true` when a forced/managed-domain ecosystem is present (S5) — the
    /// UI locks org/dept editing when this is `true`.
    pub managed: bool,
    pub layers: Vec<LayerRow>,
    /// Every current validation problem, plain language (see
    /// `validate::FieldError`). Empty means the manifest is valid.
    pub errors: Vec<FieldError>,
}

/// What the UI submits on save (S7 -> S6 -> S4). Deliberately narrow — only
/// what a repo-URL form can honestly know. `rank`/`id`/`auth_ref` are NOT
/// here: assigning them is resolution-precedence-adjacent (`rank`) or
/// requires provisioning (`auth_ref`), so they stay Rust-side (S4,
/// decision-gated on D-1-M2) — the UI never invents them, and never probes
/// the repo to guess `auth` (invariant #1: no network I/O in authoring).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LayerInput {
    pub product: String,
    pub tier: Tier,
    pub repo_url: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A cheap drift guard: the field names this struct serializes as are
    /// exactly what `src/types.ts`'s mirror expects (snake_case, no
    /// translation layer). If a field gets renamed here without updating
    /// `types.ts`, this at least catches an accidental `rename_all`
    /// regression on the Rust side.
    #[test]
    fn layer_row_serializes_with_plain_snake_case_field_names() {
        let row = LayerRow {
            id: "personal-pablo".to_string(),
            product: "claude".to_string(),
            tier: Tier::Personal,
            repo_url: "git@github-personal:me/repo.git".to_string(),
            auth_ref: "ssh-personal".to_string(),
            rank: 10,
            editable: true,
        };
        let json = serde_json::to_value(&row).expect("serializes");
        for field in [
            "id", "product", "tier", "repo_url", "auth_ref", "rank", "editable",
        ] {
            assert!(
                json.get(field).is_some(),
                "missing field {field:?} in {json}"
            );
        }
        assert_eq!(json["tier"], "personal");
    }

    #[test]
    fn settings_state_round_trips_through_json() {
        let state = SettingsState {
            managed: false,
            layers: vec![],
            errors: vec![FieldError {
                layer_id: None,
                field: "layers".to_string(),
                message: "This manifest doesn't list any layers yet.".to_string(),
            }],
        };
        let json = serde_json::to_string(&state).expect("serializes");
        assert!(json.contains("\"managed\":false"));
        assert!(json.contains("\"layers\":[]"));
        assert!(json.contains("layer_id"));
    }

    #[test]
    fn layer_input_omits_rank_id_and_auth_ref() {
        let input = LayerInput {
            product: "claude".to_string(),
            tier: Tier::Org,
            repo_url: "git@github-work:acme-corp/copilot-org.git".to_string(),
        };
        let json = serde_json::to_value(&input).expect("serializes");
        for forbidden in ["rank", "id", "auth_ref"] {
            assert!(
                json.get(forbidden).is_none(),
                "LayerInput must not carry {forbidden:?} — it's derived Rust-side"
            );
        }
    }
}
