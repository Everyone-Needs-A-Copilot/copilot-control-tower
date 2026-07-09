//! `ParseOutcome` -> `RenderState` (T3/T5, ADR-M1-001/002).
//!
//! Allowed here: read what `model::state::parse_doctor_body` already
//! decided, map `CliStatus` -> its badge token (a pure lookup,
//! `CliStatus::glyph_badge`), bucket `checkers[]` by `(product, layer)` for
//! display, and pick attribution text (e.g. "worst per-checker `severity`
//! present in that bucket" — a min/max over already-CLI-computed verdicts,
//! i.e. presentation, and "which already-reported finding does the status
//! sentence name" — again a pick among existing facts, never an invented
//! one).
//!
//! Forbidden here: computing a health score (`score` is never read past
//! `model::doctor::DoctorWire` — see the "no-compute" fitness test),
//! rolling a group of checkers up into a *new* 10-state status per
//! product/layer, running a worst-wins ladder that produces a verdict the
//! CLI didn't emit, any signature/merge/sync/wipe logic. If a per-product or
//! per-layer *status* is needed and the CLI doesn't emit one, that roll-up is
//! CLI work (Decision D-1) — this module must not synthesize it; the M1
//! floor is the raw per-checker severity badge (ADR-M1-002).
//!
//! `RenderState` mirrors `src/types.ts`'s `RenderState` field-for-field —
//! this is the DTO the IPC seam serializes for T5's `get_state()` /
//! `state-changed` (T7 renders it; `examples/gen_dev_fixtures.rs` emits
//! canned copies to `src/dev-fixtures/*.json` so T7 can build against real
//! data before the live seam exists).

use crate::model::failclosed::{AuthState, Severity};
use crate::model::state::{Checker, CliStatus, CliUnreadableReason, DoctorVerdict, ParseOutcome};
use serde::Serialize;

/// `"ok"` when the last parse produced a trustworthy verdict, `"cli_unreadable"`
/// otherwise. Mirrors `src/types.ts`'s `ClientState`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ClientState {
    Ok,
    CliUnreadable,
}

/// Per-(product,layer) bucket severity — `None` when no checker touched that
/// bucket at all, distinct from a checker actually reporting `Pass` there.
/// Mirrors `src/types.ts`'s `LayerSeverity`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LayerSeverity {
    Pass,
    Warn,
    Fail,
    None,
}

#[derive(Debug, Clone, Serialize)]
pub struct HeaderView {
    pub glyph_state: String,
    pub sentence: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct LayerView {
    pub layer: String,
    pub severity: LayerSeverity,
    pub badge_state: String,
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProductView {
    pub product: String,
    pub worst_severity: Severity,
    pub layers: Vec<LayerView>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AuthIssueView {
    pub identity: String,
    pub scope: String,
    pub state: AuthState,
    pub expires_at: Option<String>,
}

/// The DTO the app sends to the web UI over IPC. Mirrors `src/types.ts`'s
/// `RenderState` field-for-field. See the module doc for exactly what is and
/// isn't allowed to produce one of these.
#[derive(Debug, Clone, Serialize)]
pub struct RenderState {
    pub client_state: ClientState,
    pub cli_unreadable_reason: Option<CliUnreadableReason>,
    pub host: Option<String>,
    pub status: Option<CliStatus>,
    pub offline: bool,
    pub header: HeaderView,
    pub products: Vec<ProductView>,
    pub auth_issues: Vec<AuthIssueView>,
}

/// The initial declared product set (70-copy-voice.md § Implementation
/// Notes: "Knowledge Copilot, CLI Copilot, Claude Copilot, Codex Copilot are
/// the initial set, not a hardcoded list") — always rendered even if a
/// fixture's checkers never mention one, so the popover's product list is
/// stable across polls. Any *additional* product key seen in `checkers[]` is
/// appended after these (config-driven, per `doctor.schema.json`'s
/// `checkers[].product` comment: "not a closed enum").
const KNOWN_PRODUCTS: [&str; 4] = ["knowledge", "cli", "claude", "codex"];

/// The 4 layers, fixed order, per 60-ui-design.md's four-layer expansion.
const LAYERS: [&str; 4] = ["foundation", "org", "dept", "personal"];

/// The render entry point: `ParseOutcome` -> `RenderState`.
pub fn derive_render_state(outcome: &ParseOutcome) -> RenderState {
    match outcome {
        ParseOutcome::Unreadable(reason) => render_unreadable(*reason),
        ParseOutcome::Trusted(verdict) => render_trusted(verdict),
    }
}

fn render_unreadable(reason: CliUnreadableReason) -> RenderState {
    RenderState {
        client_state: ClientState::CliUnreadable,
        cli_unreadable_reason: Some(reason),
        host: None,
        status: None,
        offline: false,
        header: HeaderView {
            glyph_state: "bang".to_string(),
            sentence: cli_unreadable_sentence(reason).to_string(),
        },
        products: Vec::new(),
        auth_issues: Vec::new(),
    }
}

fn render_trusted(verdict: &DoctorVerdict) -> RenderState {
    RenderState {
        client_state: ClientState::Ok,
        cli_unreadable_reason: None,
        host: Some(verdict.host.clone()),
        status: Some(verdict.status),
        offline: verdict.offline,
        header: HeaderView {
            glyph_state: verdict.status.glyph_badge().to_string(),
            sentence: build_sentence(verdict),
        },
        products: bucket_products(verdict),
        auth_issues: verdict
            .auth
            .iter()
            .map(|a| AuthIssueView {
                identity: a.identity.clone(),
                scope: a.scope.clone(),
                state: a.state,
                expires_at: a.expires_at.clone(),
            })
            .collect(),
    }
}

/// 70-copy-voice.md § Errors / § A — one sentence per `CliUnreadableReason`,
/// traced verbatim (mirrors `src/render/copy.ts`'s `CLI_UNREADABLE_SENTENCE`).
fn cli_unreadable_sentence(reason: CliUnreadableReason) -> &'static str {
    match reason {
        CliUnreadableReason::IoError | CliUnreadableReason::Exit2 => {
            "I couldn't start the engine. Click to reinstall — it's a fix, not a reset."
        }
        CliUnreadableReason::SchemaOutOfRange => "Versions don't match — click to update.",
        CliUnreadableReason::ParseError
        | CliUnreadableReason::MissingSecurityField
        | CliUnreadableReason::InvalidContent => {
            "Versions don't match — click to update. I won't guess when I can't read this safely."
        }
    }
}

fn severity_rank(s: Severity) -> u8 {
    match s {
        Severity::Pass => 0,
        Severity::Warn => 1,
        Severity::Fail => 2,
    }
}

fn severity_to_layer_severity(s: Severity) -> LayerSeverity {
    match s {
        Severity::Pass => LayerSeverity::Pass,
        Severity::Warn => LayerSeverity::Warn,
        Severity::Fail => LayerSeverity::Fail,
    }
}

/// PLACEHOLDER (see module doc + ADR-M1-002). 60-ui-design.md's badge-shape
/// table is keyed by the 11-state STATUS machine, not by a bare checker
/// `severity` — there is no authoritative severity->shape table today. This
/// is the M1 floor ADR-M1-002 calls "the raw severity badge (pass/warn/fail
/// shape)": `pass` reuses the existing up-to-date dot; `warn`/`fail` borrow
/// the closest-fitting shapes from the same family (`triangle`, `bang`) as a
/// legible stand-in. Revisit once the CLI emits a real per-layer status
/// (Decision D-1) instead of guessing a richer shape from `escalate`/`repair`
/// content, which would cross into verdict synthesis.
fn severity_badge(s: Severity) -> &'static str {
    match s {
        Severity::Pass => "pass",
        Severity::Warn => "triangle",
        Severity::Fail => "bang",
    }
}

fn bucket_products(verdict: &DoctorVerdict) -> Vec<ProductView> {
    let mut product_keys: Vec<String> = KNOWN_PRODUCTS.iter().map(|s| (*s).to_string()).collect();
    for c in &verdict.checkers {
        if let Some(p) = &c.product {
            if !product_keys.contains(p) {
                product_keys.push(p.clone());
            }
        }
    }

    product_keys
        .into_iter()
        .map(|key| {
            let layers: Vec<LayerView> = LAYERS
                .iter()
                .map(|layer_key| bucket_layer(verdict, &key, layer_key))
                .collect();
            let worst_severity = layers
                .iter()
                .filter_map(|l| match l.severity {
                    LayerSeverity::None => None,
                    LayerSeverity::Pass => Some(Severity::Pass),
                    LayerSeverity::Warn => Some(Severity::Warn),
                    LayerSeverity::Fail => Some(Severity::Fail),
                })
                .fold(None, |acc: Option<Severity>, s| match acc {
                    Some(a) if severity_rank(a) >= severity_rank(s) => Some(a),
                    _ => Some(s),
                })
                // PLACEHOLDER: no layer of this product was touched by any
                // checker at all — defaults to Pass ("silence is success",
                // 60-ui-design.md), never a fabricated Fail. This is
                // distinct from the fail-closed rule for a *checker that IS
                // present but missing a security field* (that case never
                // reaches this function — it fails the whole verdict closed
                // in `model::state::parse_doctor_body`).
                .unwrap_or(Severity::Pass);
            ProductView {
                product: product_label(&key),
                worst_severity,
                layers,
            }
        })
        .collect()
}

fn bucket_layer(verdict: &DoctorVerdict, product_key: &str, layer_key: &str) -> LayerView {
    let worst = worst_in_bucket(verdict, product_key, layer_key);
    match worst {
        None => LayerView {
            layer: layer_key.to_string(),
            severity: LayerSeverity::None,
            badge_state: "none".to_string(),
            detail: None,
        },
        Some(c) => LayerView {
            layer: layer_key.to_string(),
            severity: severity_to_layer_severity(c.severity),
            badge_state: severity_badge(c.severity).to_string(),
            detail: c.detail.clone(),
        },
    }
}

fn worst_in_bucket<'a>(
    verdict: &'a DoctorVerdict,
    product_key: &str,
    layer_key: &str,
) -> Option<&'a Checker> {
    let mut worst: Option<&Checker> = None;
    for c in verdict.checkers.iter().filter(|c| {
        c.product.as_deref() == Some(product_key) && c.layer.as_deref() == Some(layer_key)
    }) {
        worst = Some(match worst {
            Some(w) if severity_rank(w.severity) >= severity_rank(c.severity) => w,
            _ => c,
        });
    }
    worst
}

/// The single worst-severity checker that carries both `product` and
/// `layer` (needed to attribute the status sentence) — first-occurring on a
/// tie, for determinism. A pick among already-CLI-reported findings, never
/// an invented one.
fn worst_checker(verdict: &DoctorVerdict) -> Option<&Checker> {
    let mut best: Option<&Checker> = None;
    for c in verdict
        .checkers
        .iter()
        .filter(|c| c.product.is_some() && c.layer.is_some())
    {
        best = Some(match best {
            Some(b) if severity_rank(b.severity) >= severity_rank(c.severity) => b,
            _ => c,
        });
    }
    best
}

/// 70-copy-voice.md § A — `{Product}` display name. `knowledge`/`cli`/
/// `claude`/`codex` are the initial declared set; anything else is a
/// PLACEHOLDER title-case of the raw key (products are "config-driven, not a
/// closed enum" per `doctor.schema.json`'s `checkers[].product` comment, and
/// the copy deck doesn't enumerate a name for a product it doesn't know
/// about yet).
fn product_label(raw: &str) -> String {
    match raw {
        "knowledge" => "Knowledge Copilot".to_string(),
        "cli" => "CLI Copilot".to_string(),
        "claude" => "Claude Copilot".to_string(),
        "codex" => "Codex Copilot".to_string(),
        other => title_case(other),
    }
}

/// `{Layer}` as it appears mid-sentence in every copy-voice.md example
/// ("...department layer needs sign-in.") — always lowercase, `dept` spelled
/// out to `department`.
fn layer_label_lower(raw: &str) -> String {
    match raw {
        "dept" => "department".to_string(),
        other => other.to_string(),
    }
}

fn title_case(raw: &str) -> String {
    raw.split(['-', '_'])
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// 70-copy-voice.md § A — the top-line status sentence. Flat states
/// (Healthy, IT-config-incomplete, Waiting-for-network, Offline,
/// Setup-needed, Updating-app) use the exact fixed copy; the attributed
/// states (Syncing, Signed-out, Needs-attention, Update-available) name the
/// worst **product and layer** per E21/US-B08, picked via `worst_checker` —
/// a presentation-only pick among already-CLI-reported findings, never an
/// invented one. The "Everything else is up to date" clause (Implementation
/// Notes, 70-copy-voice.md) is only appended when every *other* checker
/// actually parsed `pass` — never asserted.
fn build_sentence(verdict: &DoctorVerdict) -> String {
    match verdict.status {
        CliStatus::Healthy => "Everything's in sync across all your copilots.".to_string(),
        CliStatus::ItConfigIncomplete => {
            "Your IT setup isn't finished yet. Nothing for you to do — IT has been told.".to_string()
        }
        CliStatus::WaitingForNetwork => {
            "I've set up as far as your network allows. I'll finish your company setup when you're back online."
                .to_string()
        }
        CliStatus::Offline => "You're offline — showing your last synced setup.".to_string(),
        CliStatus::SetupNeeded => "Let's set up your copilot.".to_string(),
        CliStatus::UpdatingApp => "Updating Control Tower…".to_string(),
        CliStatus::Syncing => match worst_checker(verdict) {
            Some(c) => format!(
                "{} — {} layer updating…",
                product_label(c.product.as_deref().unwrap_or("")),
                layer_label_lower(c.layer.as_deref().unwrap_or(""))
            ),
            None => "Syncing…".to_string(),
        },
        CliStatus::SignedOut => attributed_sentence(verdict, "needs sign-in", "Signed out. Sign in to keep everything in sync."),
        CliStatus::NeedsAttention => attributed_sentence(verdict, "needs a repair", "Something needs a repair."),
        CliStatus::UpdateAvailable => match worst_checker(verdict) {
            Some(c) => format!(
                "{} — an update is available for the {} layer.",
                product_label(c.product.as_deref().unwrap_or("")),
                layer_label_lower(c.layer.as_deref().unwrap_or(""))
            ),
            None => "An update is available.".to_string(),
        },
    }
}

fn attributed_sentence(verdict: &DoctorVerdict, action_phrase: &str, fallback: &str) -> String {
    match worst_checker(verdict) {
        Some(worst) => {
            let product = product_label(worst.product.as_deref().unwrap_or(""));
            let layer = layer_label_lower(worst.layer.as_deref().unwrap_or(""));
            let others_all_pass = verdict
                .checkers
                .iter()
                .all(|c| std::ptr::eq(c, worst) || c.severity == Severity::Pass);
            if others_all_pass {
                format!("{product} — {layer} layer {action_phrase}. Everything else is up to date.")
            } else {
                format!("{product} — {layer} layer {action_phrase}.")
            }
        }
        None => fallback.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::state::parse_doctor_body;

    fn render(name: &str) -> RenderState {
        let path = format!("{}/fixtures/corpus/{name}.json", env!("CARGO_MANIFEST_DIR"));
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        derive_render_state(&parse_doctor_body(&raw))
    }

    #[test]
    fn healthy_fixture_renders_all_sixteen_buckets_as_pass() {
        let rs = render("healthy-clean-fleet");
        assert_eq!(rs.client_state, ClientState::Ok);
        assert_eq!(rs.header.glyph_state, "none");
        assert_eq!(
            rs.header.sentence,
            "Everything's in sync across all your copilots."
        );
        assert_eq!(rs.products.len(), 4);
        for p in &rs.products {
            assert_eq!(p.worst_severity, Severity::Pass);
            assert_eq!(p.layers.len(), 4);
            for l in &p.layers {
                assert_eq!(l.severity, LayerSeverity::Pass);
                assert_eq!(l.badge_state, "pass");
            }
        }
    }

    #[test]
    fn needs_attention_fixture_buckets_the_fail_checker_under_codex_dept() {
        let rs = render("needs-attention-codex-dept-fail");
        let codex = rs
            .products
            .iter()
            .find(|p| p.product == "Codex Copilot")
            .expect("codex product present");
        assert_eq!(codex.worst_severity, Severity::Fail);
        let dept = codex.layers.iter().find(|l| l.layer == "dept").unwrap();
        assert_eq!(dept.severity, LayerSeverity::Fail);
        assert_eq!(dept.badge_state, "bang");

        let claude = rs
            .products
            .iter()
            .find(|p| p.product == "Claude Copilot")
            .unwrap();
        assert_eq!(claude.worst_severity, Severity::Warn);

        // Not "Everything else is up to date" — claude/dept is also non-pass.
        assert_eq!(
            rs.header.sentence,
            "Codex Copilot — department layer needs a repair."
        );
    }

    #[test]
    fn signed_out_fixture_names_the_right_product_and_layer_with_everything_else_clause() {
        let rs = render("signed-out-claude-personal");
        assert_eq!(
            rs.header.sentence,
            "Claude Copilot — personal layer needs sign-in. Everything else is up to date."
        );
        assert_eq!(rs.auth_issues.len(), 1);
        assert_eq!(rs.auth_issues[0].state, AuthState::Expired);
    }

    #[test]
    fn cli_unreadable_never_renders_a_status_host_or_products() {
        let rs = derive_render_state(&ParseOutcome::Unreadable(
            CliUnreadableReason::SchemaOutOfRange,
        ));
        assert_eq!(rs.client_state, ClientState::CliUnreadable);
        assert_eq!(rs.status, None);
        assert_eq!(rs.host, None);
        assert!(rs.products.is_empty());
        assert_eq!(rs.header.glyph_state, "bang");
        assert_eq!(
            rs.cli_unreadable_reason,
            Some(CliUnreadableReason::SchemaOutOfRange)
        );
    }

    #[test]
    fn exit_2_reason_renders_the_engine_wont_start_copy() {
        let rs = derive_render_state(&ParseOutcome::Unreadable(CliUnreadableReason::Exit2));
        assert_eq!(
            rs.header.sentence,
            "I couldn't start the engine. Click to reinstall — it's a fix, not a reset."
        );
    }

    #[test]
    fn offline_fixture_is_never_healthy_glyph() {
        let rs = render("offline");
        assert_ne!(rs.header.glyph_state, "none");
        assert_eq!(rs.status, Some(CliStatus::Offline));
    }
}
