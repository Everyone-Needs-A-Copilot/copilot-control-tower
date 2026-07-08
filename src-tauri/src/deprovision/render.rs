//! `DeprovisionParseOutcome` -> `DeprovisionView` (M5/S2) — parse-not-compute
//! render, mirroring `render::derive::derive_render_state`'s discipline for
//! the deprovision verb.
//!
//! Allowed here: read what `model::deprovision::parse_deprovision_body`
//! already decided, map it to a render-ready DTO, and pick plain-language
//! copy (SOUL: no raw errors, no CLI stderr ever reaches the UI).
//!
//! **Forbidden here — and everywhere in this module tree
//! (`src-tauri/src/deprovision/`):** any file-deletion, tree-wiping, or
//! retain/keep DECISION. This crate contains ZERO wipe logic; the CLI
//! already computed and PERFORMED the entire deprovision before this
//! function is ever called. `render_deprovision` only renders what the CLI
//! already did. `tests/fitness_m5_no_wipe_logic.rs` (FF-M5-2) source-scans
//! this directory for `fs::remove*`/`remove_dir*`/`remove_file`/`rmdir`/
//! `std::fs::write`/`git clean|reset|rm|checkout` and asserts none are
//! present.
//!
//! `retained_dirty` (invariant #3, never-destroy) is rendered PROMINENTLY
//! and ALWAYS — including when empty, since "no dirty personal work was in
//! the way" is itself honest information, never omitted.
//!
//! `secrets_touched` is rendered as-is; `secrets_alarm` is `true` iff it is
//! nonzero. This is an HONEST ALARM state (invariant #6 — no secret should
//! ever have lived in a layer) and is never hidden, swallowed, or
//! normalized back to a clean `0`.
//!
//! `removed_count` (`removed.materialized`) is rendered with NEUTRAL copy
//! only ("N items removed") — G-M5-4: its exact count semantics are
//! undefined even upstream, so this layer must not editorialize it into
//! "files" or "trees" or any other over-specific noun.

use crate::model::deprovision::{
    parse_deprovision_body, DeprovisionParseOutcome, DeprovisionResult,
    DeprovisionUnreadableReason, DeprovisionVerdict,
};
use serde::Serialize;

/// The render-ready outcome token. `Unreadable` is the 4th, APP-OWNED value —
/// never CLI-emitted — mirroring `render::derive::ClientState`'s CLI-
/// unreadable convention for the doctor verb.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeprovisionOutcomeView {
    Wiped,
    Partial,
    Noop,
    Unreadable,
}

/// The DTO the app would send to the web UI (via a future S6 IPC command) or
/// to an IT-facing renderer. Mirrors `src/types.ts`'s `DeprovisionView`
/// field-for-field. See the module doc for exactly what is and isn't
/// allowed to produce one of these.
#[derive(Debug, Clone, Serialize)]
pub struct DeprovisionView {
    pub outcome: DeprovisionOutcomeView,
    pub unreadable_reason: Option<DeprovisionUnreadableReason>,
    /// Neutral count copy only (G-M5-4) — `None` when the body was
    /// unreadable (nothing confirmed).
    pub removed_count: Option<u64>,
    pub removed_clones: Vec<String>,
    /// The never-destroy reassurance (invariant #3) — always present, even
    /// as an empty list.
    pub retained_dirty: Vec<String>,
    pub secrets_touched: u64,
    /// `true` iff `secrets_touched != 0` — see the module doc's alarm note.
    pub secrets_alarm: bool,
    /// The one honest, plain-language sentence — never raw CLI/JSON error
    /// text (SOUL discipline, same as `render::derive::RenderState.header
    /// .sentence`).
    pub sentence: String,
}

/// The render entry point: raw `deprovision --json` body bytes ->
/// `DeprovisionView`. Pure parse+map — no I/O, no CLI spawn (that's
/// `deprovision::run_deprovision`'s job, one layer up).
pub fn render_deprovision(raw: &[u8]) -> DeprovisionView {
    match parse_deprovision_body(raw) {
        DeprovisionParseOutcome::Unreadable(reason) => render_unreadable(reason),
        DeprovisionParseOutcome::Trusted(verdict) => render_trusted(&verdict),
    }
}

/// Renders the app-owned CLI-unreadable state directly, for callers that
/// never had a body to parse in the first place (a spawn/timeout/I-O
/// failure — see `deprovision::run_deprovision`). Never fabricates a
/// `Wiped`/`Partial`/`Noop` outcome from an absent body.
pub fn render_unreadable(reason: DeprovisionUnreadableReason) -> DeprovisionView {
    DeprovisionView {
        outcome: DeprovisionOutcomeView::Unreadable,
        unreadable_reason: Some(reason),
        removed_count: None,
        removed_clones: Vec::new(),
        retained_dirty: Vec::new(),
        secrets_touched: 0,
        secrets_alarm: false,
        sentence: unreadable_sentence(reason).to_string(),
    }
}

fn render_trusted(v: &DeprovisionVerdict) -> DeprovisionView {
    let secrets_alarm = v.secrets_touched != 0;
    DeprovisionView {
        outcome: outcome_view(v.result),
        unreadable_reason: None,
        removed_count: Some(v.removed_materialized),
        removed_clones: v.removed_clones.clone(),
        retained_dirty: v.retained_dirty.clone(),
        secrets_touched: v.secrets_touched,
        secrets_alarm,
        sentence: sentence_for(v, secrets_alarm),
    }
}

/// `DeprovisionResult` -> `DeprovisionOutcomeView`, a pure lookup — never a
/// computation (same ADR-M1-001 discipline `CliStatus::glyph_badge` follows).
fn outcome_view(result: DeprovisionResult) -> DeprovisionOutcomeView {
    match result {
        DeprovisionResult::Wiped => DeprovisionOutcomeView::Wiped,
        DeprovisionResult::Partial => DeprovisionOutcomeView::Partial,
        DeprovisionResult::Noop => DeprovisionOutcomeView::Noop,
    }
}

/// One sentence per `DeprovisionUnreadableReason` — SOUL discipline (no raw
/// process/JSON error ever reaches this text). Every reason renders as an
/// honest "I can't confirm this" rather than a fabricated success, matching
/// this task's "unknown result => not a clean success" requirement at the
/// copy layer too.
fn unreadable_sentence(reason: DeprovisionUnreadableReason) -> &'static str {
    match reason {
        DeprovisionUnreadableReason::IoError => {
            "I couldn't confirm this org's deprovision — the tool wouldn't start. Nothing here is confirmed removed."
        }
        DeprovisionUnreadableReason::ParseError
        | DeprovisionUnreadableReason::SchemaOutOfRange
        | DeprovisionUnreadableReason::InvalidContent => {
            "I couldn't confirm what happened during this deprovision — I won't guess. Nothing here is confirmed removed."
        }
        DeprovisionUnreadableReason::MissingSecurityField => {
            "I can't confirm this deprovision was safe — a required security field was missing. Treating this as unconfirmed, not successful."
        }
    }
}

/// The one honest status sentence for a trusted verdict. The
/// `secrets_touched` alarm always leads (never buried) when present;
/// `retained_dirty` is always named when non-empty, since that's the
/// never-destroy reassurance the whole point of rendering this exists for.
fn sentence_for(v: &DeprovisionVerdict, secrets_alarm: bool) -> String {
    let mut parts: Vec<String> = Vec::new();

    if secrets_alarm {
        parts.push(format!(
            "ALARM: {} secret(s) were touched during this deprovision — this should never happen. Contact IT/security immediately.",
            v.secrets_touched
        ));
    }

    parts.push(match v.result {
        DeprovisionResult::Wiped => {
            format!(
                "This org's Copilot data was removed ({} item(s) removed).",
                v.removed_materialized
            )
        }
        DeprovisionResult::Partial => format!(
            "Some of this org's Copilot data was removed ({} item(s) removed); the rest is still in place.",
            v.removed_materialized
        ),
        DeprovisionResult::Noop => {
            "There was nothing to remove for this org — its Copilot data was already gone.".to_string()
        }
    });

    if v.retained_dirty.is_empty() {
        parts.push("No personal work was in the way.".to_string());
    } else {
        parts.push(format!(
            "{} personal working tree(s) with unsaved work were kept — never deleted.",
            v.retained_dirty.len()
        ));
    }

    parts.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(name: &str) -> DeprovisionView {
        let path = format!(
            "{}/fixtures/deprovision/corpus/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        render_deprovision(&raw)
    }

    fn render_invalid(name: &str) -> DeprovisionView {
        let path = format!(
            "{}/fixtures/deprovision/invalid/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let raw = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        render_deprovision(&raw)
    }

    #[test]
    fn wiped_clean_renders_wiped_with_retained_dirty_surfaced_and_no_alarm() {
        let view = render("wiped-clean");
        assert_eq!(view.outcome, DeprovisionOutcomeView::Wiped);
        assert!(!view.secrets_alarm);
        assert_eq!(view.secrets_touched, 0);
        assert!(!view.retained_dirty.is_empty());
        assert!(view.sentence.contains("kept"));
        assert!(!view.sentence.to_uppercase().contains("ALARM"));
    }

    #[test]
    fn partial_renders_partial_outcome() {
        let view = render("partial");
        assert_eq!(view.outcome, DeprovisionOutcomeView::Partial);
        assert!(!view.secrets_alarm);
    }

    #[test]
    fn noop_renders_noop_outcome_with_no_alarm() {
        let view = render("noop");
        assert_eq!(view.outcome, DeprovisionOutcomeView::Noop);
        assert_eq!(view.removed_count, Some(0));
        assert!(view.retained_dirty.is_empty());
        assert!(!view.secrets_alarm);
    }

    /// The adversarial fixture: `secrets_touched=1` must render a loud,
    /// never-hidden alarm — not a silent pass, not a swallowed/normalized 0.
    #[test]
    fn secrets_touched_nonzero_renders_an_honest_alarm_never_a_silent_pass() {
        let view = render("secrets-touched-alarm");
        assert!(view.secrets_alarm);
        assert_eq!(view.secrets_touched, 1);
        assert!(view.sentence.to_uppercase().contains("ALARM"));
        // The outcome itself is still rendered (the alarm doesn't erase the
        // rest of the honest report), but the alarm always leads the sentence.
        assert!(view.sentence.to_uppercase().starts_with("ALARM"));
    }

    /// Malformed body -> honest non-success, never a fabricated clean wipe.
    #[test]
    fn malformed_body_renders_unreadable_never_wiped() {
        let view = render_invalid("malformed");
        assert_eq!(view.outcome, DeprovisionOutcomeView::Unreadable);
        assert_eq!(
            view.unreadable_reason,
            Some(DeprovisionUnreadableReason::ParseError)
        );
        assert!(view.removed_count.is_none());
        assert!(!view.secrets_alarm);
    }

    #[test]
    fn missing_secrets_touched_renders_unreadable_with_missing_security_field_reason() {
        let view = render_invalid("missing-secrets-touched");
        assert_eq!(view.outcome, DeprovisionOutcomeView::Unreadable);
        assert_eq!(
            view.unreadable_reason,
            Some(DeprovisionUnreadableReason::MissingSecurityField)
        );
    }

    #[test]
    fn unknown_result_renders_unreadable_never_a_fabricated_wipe() {
        let view = render_invalid("unknown-result");
        assert_ne!(view.outcome, DeprovisionOutcomeView::Wiped);
        assert_eq!(view.outcome, DeprovisionOutcomeView::Unreadable);
    }

    #[test]
    fn render_unreadable_direct_call_never_fabricates_a_success_outcome() {
        for reason in [
            DeprovisionUnreadableReason::IoError,
            DeprovisionUnreadableReason::ParseError,
            DeprovisionUnreadableReason::SchemaOutOfRange,
            DeprovisionUnreadableReason::MissingSecurityField,
            DeprovisionUnreadableReason::InvalidContent,
        ] {
            let view = render_unreadable(reason);
            assert_eq!(view.outcome, DeprovisionOutcomeView::Unreadable);
            assert!(!view.secrets_alarm);
            assert!(view.removed_count.is_none());
            assert!(view.retained_dirty.is_empty());
        }
    }

    #[test]
    fn removed_count_copy_stays_neutral_never_over_interpreted() {
        // G-M5-4: the REMOVED-count phrase specifically must stay neutral
        // ("item(s)"), never editorialized into "files"/"trees" — unlike
        // `retained_dirty`'s copy, which legitimately says "working tree(s)"
        // (that's the correct, already-established term for a dirty
        // personal checkout, not an over-interpretation of an undefined
        // count).
        let view = render("wiped-clean");
        assert!(view.sentence.contains("item(s) removed"));
        assert!(!view.sentence.to_lowercase().contains("file(s) removed"));
        assert!(!view.sentence.to_lowercase().contains("tree(s) removed"));
    }
}
