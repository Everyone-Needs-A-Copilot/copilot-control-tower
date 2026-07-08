//! The un-dismissable security-banner render DTO (M6/S4, `.copilot/wp/37.md`,
//! task 55) — the HONEST surface for a security fix the router
//! (`routing::policy::route`, M6/S2) AUTO-ACTED on (Flow 7, "The Fix That
//! Acts Itself",
//! `docs/product-design/04-experience-design/50-ux-design.md`). This is a
//! PARSE of `model::update::ChangedItem`'s already-CLI-computed
//! `shadowed_by` field (invariant #1 — computes NO verdict of its own), NOT
//! a second router: `routing::policy::route`'s `UpdateChange` arm is the
//! ONLY place that decides whether the CLI's auto-suspend actually
//! happened; this module only decides whether to RENDER the honest
//! past-tense line about it, keyed on the exact same CLI-computed fact
//! (`shadowed_by.is_some()`, i.e. `routing::event::UpdateChangeEvent::
//! shadow_present`) the router itself uses for its
//! `AutoActReason::SecurityShadowOverrideSuspended` arm.
//!
//! ## Distinct from `routing::BobNotice::kept_you_safe` — the re-affirm gap
//!
//! `routing`'s `BobNotice` is a deliberately ACTION-FREE quiet mention
//! (`src/types.ts`'s own doc: "there is nothing here for Bob to do... MUST
//! NOT carry any alarm styling" — and `render/copy.ts`'s `BOB_KEPT_YOU_SAFE`
//! doc says so explicitly: it DROPS the source deck's "Re-affirm your
//! version ▸" affordance on purpose, because the Bob-lane's closed
//! `BobPromptKind` set forbids adding a third, security-approval-shaped
//! control there). [`SecurityBanner`] is the type that DOES carry that
//! affordance — the one Bob-facing surface allowed to offer "Re-affirm your
//! version", because re-affirming his own prior override is never itself
//! the "let Bob approve a security decision" anti-pattern SOUL.md's Case Law
//! forbids: the fix ALREADY WON (the auto-suspend is a fait accompli,
//! invariant #1), and re-affirming only ever re-asserts *his own* override
//! going forward — ownership preserved, never a security-approval gate.
//!
//! ## Re-affirm-only — structurally cannot be dismissed
//!
//! [`SecurityBanner`] has exactly two fields: `message` (past-tense, per
//! `70-copy-voice.md`'s "Past-tense for anything already handled") and
//! `reaffirm_label` (the one affordance). There is no `dismiss`/`clear`/
//! `approve` field, and no method that could ever mark one "resolved" —
//! `tests/fitness_m6_security_banner_reaffirm_only.rs` is the structural
//! source-scan proof, mirroring `fitness_m6_itsignal_content_free.rs`'s
//! "`ItSignal` itself still has exactly two fields" check applied to this
//! type instead.
//!
//! ## Fail-closed: an absent trailer is the WORST case, never a free pass
//!
//! `model::update`'s own module doc names this module by number
//! ("Treating an absent trailer as the WORST case... is the security-banner
//! renderer's job (M6/S-E)") — [`build_security_banner`] honors that
//! directly: it keys ONLY on `shadowed_by.is_some()` (the CLI's own record
//! that an auto-suspend actually happened), never on whether
//! `severity_trailer` also happens to be present. A shadowed entry with NO
//! `severity_trailer` text still renders the banner; the ABSENCE of trailer
//! text is never read as "safe to stay silent."
//!
//! ## Content-free (no personal item name)
//!
//! Both fields are compiled-in `&'static str` copy — never CLI-supplied
//! text — matching `routing::BobPrompt`'s/`routing::BobNotice`'s own
//! discipline: there is nothing here to interpolate, so nothing here can
//! ever carry `ChangedItem::item`/`dimension`/`layer`/`shadowed_by`'s
//! identifier text.

use crate::model::update::ChangedItem;
use serde::Serialize;
use std::sync::Mutex;

/// The un-dismissable security banner. See the module doc for the full
/// contract — exactly two fields, both `&'static str`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct SecurityBanner {
    pub message: &'static str,
    pub reaffirm_label: &'static str,
}

impl SecurityBanner {
    /// Copy sourced verbatim from `70-copy-voice.md` § F / Flow 7 — the
    /// SAME message text `routing::BobNotice::kept_you_safe` uses, plus the
    /// re-affirm affordance that notice deliberately omits (see the module
    /// doc's "Distinct from `BobNotice`" section).
    pub fn kept_you_safe() -> Self {
        Self {
            message: "Kept you safe — a security fix replaced a component you'd overridden.",
            reaffirm_label: "Re-affirm your version",
        }
    }
}

/// Parses `changed` (an already-trusted `UpdateVerdict::changed`,
/// `model::update`'s own parse boundary) for the Flow-7 security-shadow
/// entry and renders it as a [`SecurityBanner`] — `None` when no entry in
/// this update carries a live shadow (silence-is-success, P1; a plain
/// signed update, a prune, or a signature failure all yield `None` here,
/// the same as they yield no `routing::ItSignalKind::
/// SecurityShadowAutoSuspended` in the router). Returns the banner for the
/// FIRST shadowed entry found — the banner is singular per Flow 7's own "no
/// prompt, no decision, no badge to clear" framing (one honest line, not one
/// per shadowed item).
pub fn build_security_banner(changed: &[ChangedItem]) -> Option<SecurityBanner> {
    changed
        .iter()
        .any(|item| item.shadowed_by.is_some())
        .then(SecurityBanner::kept_you_safe)
}

/// M6/S6 (task 57, `.copilot/wp/37.md`): the Tauri-managed single instance
/// `commands::get_security_banner` reads from and `render::bob_lane::
/// apply_update` writes to — mirrors `commands::DoctorState`'s "exactly one
/// instance, replaced not accumulated" discipline (invariant #2). `.manage()`d
/// once in `lib.rs`'s `.setup()`, alongside `render::bob_lane::BobLaneState`.
/// Lives here (not `commands.rs`) for the SAME reason `BobLaneState` lives in
/// `render::bob_lane` — see that module's own doc.
#[derive(Default)]
pub struct SecurityBannerState {
    inner: Mutex<Option<SecurityBanner>>,
}

impl SecurityBannerState {
    pub fn new() -> Self {
        Self::default()
    }

    /// A snapshot for `commands::get_security_banner` to return. Fail-closed
    /// to `None` (no banner) on a poisoned lock — never a panic surfaced to
    /// the IPC boundary, matching `BobLaneState::snapshot`'s own recovery.
    pub fn snapshot(&self) -> Option<SecurityBanner> {
        *self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Replaces the current banner wholesale — never accumulates. `None`
    /// clears it (the current update parse carried no live security-shadow
    /// entry), matching `build_security_banner`'s own "silence is success"
    /// contract.
    pub fn replace(&self, banner: Option<SecurityBanner>) {
        *self.inner.lock().unwrap_or_else(|e| e.into_inner()) = banner;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::update::{parse_update_body, ChangeOp, UpdateParseOutcome};

    fn changed_item(
        op: ChangeOp,
        signed: bool,
        severity_trailer: Option<&str>,
        shadowed_by: Option<&str>,
    ) -> ChangedItem {
        ChangedItem {
            dimension: "cli".to_string(),
            layer: "personal".to_string(),
            item: "agents/reviewer.md".to_string(),
            op,
            from: None,
            to: None,
            signed,
            severity_trailer: severity_trailer.map(str::to_string),
            shadowed_by: shadowed_by.map(str::to_string),
        }
    }

    #[test]
    fn a_shadowed_entry_yields_the_past_tense_kept_you_safe_banner_with_a_reaffirm_affordance() {
        let changed = vec![changed_item(
            ChangeOp::Added,
            false,
            Some("unsigned content shadows a signed org-tier file"),
            Some("org/agents/reviewer.md"),
        )];
        let banner = build_security_banner(&changed).expect("a shadowed entry must yield a banner");
        assert_eq!(
            banner.message,
            "Kept you safe — a security fix replaced a component you'd overridden."
        );
        assert_eq!(banner.reaffirm_label, "Re-affirm your version");
    }

    #[test]
    fn a_non_security_changed_entry_yields_no_banner() {
        let changed = vec![changed_item(ChangeOp::Updated, true, None, None)];
        assert!(build_security_banner(&changed).is_none());
    }

    #[test]
    fn an_empty_changed_list_yields_no_banner() {
        assert!(build_security_banner(&[]).is_none());
    }

    /// Fail-closed: an absent `severity_trailer` on a shadowed entry still
    /// renders the banner — the module doc's "an absent trailer is the
    /// WORST case, never a free pass" section, exercised end to end through
    /// the real parse boundary (`signed`/`severity_trailer` both absent from
    /// the wire, `shadowed_by` present).
    #[test]
    fn missing_signed_and_severity_trailer_on_a_shadowed_entry_still_fails_closed_to_a_banner() {
        let raw = br#"{
            "schema_version": "1.0",
            "result": "applied",
            "lock_before": "a1b2c3d",
            "lock_after": "e4f5a6b",
            "changed": [
                { "dimension": "cli", "layer": "personal", "item": "agents/reviewer.md", "op": "added", "shadowed_by": "org/agents/reviewer.md" }
            ]
        }"#;
        let verdict = match parse_update_body(raw) {
            UpdateParseOutcome::Trusted(v) => v,
            other => panic!("expected Trusted, got {other:?}"),
        };
        assert!(
            !verdict.changed[0].signed,
            "an absent wire `signed` must default to false, never true"
        );
        assert_eq!(verdict.changed[0].severity_trailer, None);
        let banner = build_security_banner(&verdict.changed);
        assert!(
            banner.is_some(),
            "a shadowed entry must still render the banner even with no severity_trailer text \
             and an absent signed field"
        );
    }

    #[test]
    fn the_first_shadowed_entry_wins_the_banner_is_singular() {
        let changed = vec![
            changed_item(ChangeOp::Updated, true, None, None),
            changed_item(ChangeOp::Added, false, Some("security"), Some("org/x")),
        ];
        assert!(build_security_banner(&changed).is_some());
    }

    /// Pins `SecurityBanner`'s serialized shape — the value-level half of
    /// `tests/fitness_m6_security_banner_reaffirm_only.rs`'s source-scan
    /// proof that no third (`dismiss`/`clear`/`approve`) field ever exists.
    #[test]
    fn security_banner_serializes_to_exactly_message_and_reaffirm_label() {
        let banner = SecurityBanner::kept_you_safe();
        let value = serde_json::to_value(banner).expect("SecurityBanner must serialize");
        let obj = value
            .as_object()
            .expect("SecurityBanner serializes to an object");
        let mut keys: Vec<&str> = obj.keys().map(|k| k.as_str()).collect();
        keys.sort_unstable();
        assert_eq!(keys, vec!["message", "reaffirm_label"]);
    }

    // -- SecurityBannerState (M6/S6) -----------------------------------------

    #[test]
    fn a_new_state_snapshots_to_none() {
        assert!(SecurityBannerState::new().snapshot().is_none());
    }

    #[test]
    fn replace_then_snapshot_round_trips() {
        let state = SecurityBannerState::new();
        state.replace(Some(SecurityBanner::kept_you_safe()));
        assert!(state.snapshot().is_some());
    }

    #[test]
    fn replacing_with_none_clears_a_previously_set_banner() {
        let state = SecurityBannerState::new();
        state.replace(Some(SecurityBanner::kept_you_safe()));
        state.replace(None);
        assert!(state.snapshot().is_none());
    }
}
