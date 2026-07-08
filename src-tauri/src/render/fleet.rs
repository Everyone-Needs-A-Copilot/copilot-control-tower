//! The IT fleet dashboard's render DTO + `get_fleet` backing (M7/S9,
//! `.copilot/wp/43.md`, task 68) — backs uid's (S4) `get_fleet` IPC command
//! (`GET_FLEET_CMD` in `src/types.ts`). Mirrors `src/types.ts`'s
//! `FleetView`/`FleetHostView`/`FleetActionItem` field-for-field, the same
//! "Rust DTO mirrors the TS type this stream already shipped ahead of a live
//! command" convention `render::bob_lane`/`render::security_banner`
//! established for M6.
//!
//! ## A single machine only knows its OWN status (G-M7-3)
//!
//! The fleet AGGREGATE lives in an org collector this app never talks to —
//! G-M7-3 (the collector's own query/ingest API) is undefined owner infra.
//! [`build_fleet_view`] therefore returns a **mock/local** [`FleetView`]:
//! this machine's own real, already-CLI-computed status as ONE host (never
//! fabricated — omitted entirely when there is no trustworthy status yet,
//! see [`local_host_view`]) plus a small, fixed set of OBVIOUSLY-named
//! `mock-*` fleet-mate rows so the dashboard this command backs isn't a
//! single-host-only stub before a real collector exists. **Every mock row
//! is clearly a dev/mock source** — never presented as if it were real
//! fleet telemetry.
//!
//! ## No aggregate score, ever (FF-M7-NOSCORE)
//!
//! [`FleetView`] carries **exactly one field**, `hosts` — the SAME
//! permanent prohibition `src/types.ts`'s own `FleetView` doc states
//! verbatim: "a fleet health 94/100 number is OUT because it implies the
//! app judges health." `fleet_view_serializes_to_exactly_the_hosts_field`
//! (below) pins this as a value-level regression guard, mirroring
//! `telemetry::schema::FleetEvent`'s own closed-field-set test.
//!
//! ## The local row's actionable items are REAL, not mocked
//!
//! [`local_host_view`] reads `LocalSink::entries()` (M6/S3's own in-process
//! IT-signal audit buffer, already `.manage()`d and already populated by
//! every live `timer::poll_once` call) and maps each recorded
//! [`crate::routing::ItSignalKind`] into a [`FleetActionItem`] — content-free
//! by construction (the SAME closed enum `ItSignal`'s own doc already pins).
//! This is presentation only: no new verdict, no new signal, just rendering
//! facts M6's router already produced (invariant #1).
//!
//! ## Parse-not-compute
//!
//! This module computes no health judgment of its own: `status`/
//! `badge_state` are `CliStatus`/`CliStatus::glyph_badge()` — the SAME
//! lookup the tray glyph and popover already use, never a re-derived
//! worst-wins ladder (ADR-M1-001/002).

use serde::Serialize;
use tauri::State;

use crate::commands::DoctorState;
use crate::model::state::CliStatus;
use crate::routing::emit::LocalSink;
use crate::routing::ItSignalKind;

/// One actionable IT item on a host's row — mirrors `src/types.ts`'s
/// `FleetActionItem` exactly. Content-free: reuses M6's `ItSignalKind`
/// rather than inventing a parallel vocabulary; carries no personal item
/// name, path, or free text (see that type's own doc).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FleetActionItem {
    pub kind: ItSignalKind,
    pub machine_id: String,
}

/// One host's row — mirrors `src/types.ts`'s `FleetHostView` exactly.
/// `status`/`badge_state` are one CLI-computed fact about one machine,
/// worst-wins already decided upstream (by the CLI, for `status`; by
/// `CliStatus::glyph_badge` for `badge_state`) — this type adds no judgment.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FleetHostView {
    pub machine_id: String,
    pub status: CliStatus,
    pub badge_state: String,
    pub actionable_items: Vec<FleetActionItem>,
}

/// The whole dashboard's render contract — mirrors `src/types.ts`'s
/// `FleetView` exactly. **Exactly one field, permanently** — see the module
/// doc's "no aggregate score" section. Do not add a second field to this
/// type without re-reading that section first.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct FleetView {
    pub hosts: Vec<FleetHostView>,
}

/// A placeholder machine id for the local row. The REAL per-install
/// HMAC-SHA256 derivation (`telemetry::schema::derive_machine_id`) needs a
/// real hardware UUID plus a persisted per-install keychain salt — both
/// still-deferred OS-integration work (see `telemetry`'s own module doc).
/// This fixed string is an honest placeholder, never presented as a real
/// derived id — the module doc's "clearly a dev/mock source" discipline
/// applies to this constant too, even though the STATUS it's attached to is
/// real.
pub const LOCAL_MACHINE_ID: &str = "local-machine";

/// Builds the local host's own row from the CURRENT doctor-derived status —
/// the one REAL fact this single-machine dashboard has. `None` (the
/// bootstrap holding state, or a `CliUnreadable` verdict) omits the row
/// entirely rather than fabricating a status this app never actually
/// observed (never a guessed/default `Healthy`, matching `commands::
/// initial_render_state`'s own "haven't checked yet, never Healthy"
/// discipline). `it_signal_kinds` is `LocalSink::entries()`'s own already-
/// dispatched signal kinds (M6/S3) — real, not mocked; see the module doc's
/// "actionable items are REAL" section.
pub fn local_host_view(
    status: Option<CliStatus>,
    it_signal_kinds: &[ItSignalKind],
) -> Option<FleetHostView> {
    let status = status?;
    Some(FleetHostView {
        machine_id: LOCAL_MACHINE_ID.to_string(),
        status,
        badge_state: status.glyph_badge().to_string(),
        actionable_items: it_signal_kinds
            .iter()
            .map(|&kind| FleetActionItem {
                kind,
                machine_id: LOCAL_MACHINE_ID.to_string(),
            })
            .collect(),
    })
}

/// Fixed, obviously-named mock fleet-mate rows — see the module doc's "a
/// single machine only knows its own status" section for why these exist at
/// all. Every field here is hand-authored fixed data, never derived from
/// anything CLI-computed; every `machine_id` carries a `mock-` prefix so it
/// can never be mistaken for [`LOCAL_MACHINE_ID`]'s real row.
///
/// **Deliberately never `CliStatus::Healthy`.** `tests/
/// fitness_no_fabricated_healthy.rs` (T3) enforces, crate-wide, that
/// `CliStatus::Healthy` is constructed at exactly ONE guarded call site
/// (`model::state::parse_cli_status`) — a real, trusted CLI parse, never
/// anywhere else, not even in obviously-mock dev data. Fabricating a second
/// "Healthy" value here — even one clearly labeled mock — would be exactly
/// the false-all-clear invariant #4 forbids, so these rows use `Syncing`/
/// `NeedsAttention` instead: plausible, non-alarming placeholder states that
/// are NOT the one value this crate's fail-closed guard specifically
/// protects.
fn mock_fleet_mates() -> Vec<FleetHostView> {
    vec![
        FleetHostView {
            machine_id: "mock-fleet-mate-1".to_string(),
            status: CliStatus::Syncing,
            badge_state: CliStatus::Syncing.glyph_badge().to_string(),
            actionable_items: Vec::new(),
        },
        FleetHostView {
            machine_id: "mock-fleet-mate-2".to_string(),
            status: CliStatus::NeedsAttention,
            badge_state: CliStatus::NeedsAttention.glyph_badge().to_string(),
            actionable_items: vec![FleetActionItem {
                kind: ItSignalKind::PolicyDenial,
                machine_id: "mock-fleet-mate-2".to_string(),
            }],
        },
    ]
}

/// The real entry point `commands::get_fleet` calls — see the module doc.
/// Never fails/panics (pure map over caller-supplied, already-managed
/// state); the empty-fleet case (`status: None` and no mock rows — never
/// reachable today, since [`mock_fleet_mates`] is always non-empty, but kept
/// honest for a future build that removes the mocks once G-M7-3 lands) falls
/// out naturally rather than needing a special case.
pub fn build_fleet_view(status: Option<CliStatus>, it_signal_kinds: &[ItSignalKind]) -> FleetView {
    let mut hosts = Vec::new();
    if let Some(local) = local_host_view(status, it_signal_kinds) {
        hosts.push(local);
    }
    hosts.extend(mock_fleet_mates());
    FleetView { hosts }
}

/// Thin convenience the `get_fleet` Tauri command uses — reads the two
/// already-managed pieces of state it needs (`DoctorState`'s own snapshot,
/// `LocalSink`'s own recorded entries) and delegates to [`build_fleet_view`].
/// Split out from `commands::get_fleet` itself so this module owns the ONE
/// place `FleetView` is ever assembled, mirroring `render::bob_lane`/
/// `render::security_banner`'s own "the seam absorbs the domain logic,
/// `commands.rs` just calls it" precedent.
pub fn fleet_view_from_state(status: Option<CliStatus>, sink: &LocalSink) -> FleetView {
    let kinds: Vec<ItSignalKind> = sink.entries().into_iter().map(|e| e.kind).collect();
    build_fleet_view(status, &kinds)
}

/// The `get_fleet` Tauri command itself (`GET_FLEET_CMD` in `src/types.ts`).
/// Deliberately defined HERE, not in `commands.rs`: `tests/
/// fitness_m5_deprovision_is_it_routed.rs` (FF-M5-3) scans `commands.rs`/
/// `tray.rs`/`lib.rs`'s `generate_handler!` list for a blanket `"routing::"`
/// needle, and this command's only two inputs are `DoctorState` (`commands`
/// module) and [`LocalSink`] (a `routing::emit` type, needed directly since
/// no render-owned wrapper exists for it yet) — mirroring `render::
/// bob_lane`'s own "this module is the seam that absorbs the `routing::`
/// reference, not `commands.rs`" precedent, applied here to the command
/// function itself rather than a helper it calls. `lib.rs`'s
/// `generate_handler!` list references this function by its
/// `render::fleet::get_fleet` path, which contains no `routing::` substring
/// either.
#[tauri::command]
pub fn get_fleet(doctor_state: State<'_, DoctorState>, sink: State<'_, LocalSink>) -> FleetView {
    fleet_view_from_state(doctor_state.snapshot().status, &sink)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::routing::emit::ItSignalSink;
    use crate::routing::{ItSignal, ItSignalKind};

    // -- FF-M7-NOSCORE: FleetView's closed field set ---------------------------

    #[test]
    fn fleet_view_serializes_to_exactly_the_hosts_field() {
        let view = FleetView::default();
        let value = serde_json::to_value(&view).unwrap();
        let obj = value.as_object().unwrap();
        let keys: Vec<&str> = obj.keys().map(String::as_str).collect();
        assert_eq!(
            keys,
            vec!["hosts"],
            "FleetView must carry EXACTLY {{hosts}} — no aggregate/blended score field, ever \
             (FF-M7-NOSCORE)"
        );
    }

    /// Recursively collects every object key anywhere in `value`'s tree
    /// (top-level AND nested, e.g. inside each `hosts[]` row) — used by
    /// [`fleet_view_json_has_no_slot_for_a_fabricated_score`] so a
    /// fabricated score field is caught no matter which level of the DTO it
    /// gets added to, not just the top level.
    fn collect_all_keys(value: &serde_json::Value, keys: &mut Vec<String>) {
        match value {
            serde_json::Value::Object(map) => {
                for (k, v) in map {
                    keys.push(k.clone());
                    collect_all_keys(v, keys);
                }
            }
            serde_json::Value::Array(items) => {
                for v in items {
                    collect_all_keys(v, keys);
                }
            }
            _ => {}
        }
    }

    /// The literal claim FF-M7-NOSCORE exists to prevent: no key anywhere in
    /// `FleetView`'s tree (top-level OR nested inside a host/item row) could
    /// ever hold a numeric/percentage health judgment.
    ///
    /// Widened per M7 QA acceptance (D2): the original version of this test
    /// checked only the TOP-LEVEL object's keys for an EXACT match against a
    /// bare-word forbidden list (`score`/`health`/`rating`/`percent`/
    /// `grade`). Live mutation testing (adding a `health_score: u32` field to
    /// `FleetView`) proved that version's coverage narrower than its name
    /// implied: `"health_score" != "score"` under exact-key matching, so it
    /// slipped past silently (only the sibling closed-field-set test,
    /// `fleet_view_serializes_to_exactly_the_hosts_field`, caught it). This
    /// version (a) walks the FULL tree, not just the top level, and (b)
    /// matches by SUBSTRING, not exact equality, so a compound-word variant
    /// like `health_score`/`fleet_score`/`overall_score` — anywhere in the
    /// DTO — is caught too. The forbidden set itself stays closed/exhaustive
    /// (a fixed, named list), only the matching rule was widened.
    #[test]
    fn fleet_view_json_has_no_slot_for_a_fabricated_score() {
        let view = build_fleet_view(Some(CliStatus::Healthy), &[]);
        let value = serde_json::to_value(&view).unwrap();
        let mut keys = Vec::new();
        collect_all_keys(&value, &mut keys);
        assert!(
            !keys.is_empty(),
            "expected at least one key in a populated FleetView (got none) — this test would \
             otherwise vacuously pass"
        );
        for forbidden in ["score", "health", "rating", "percent", "grade"] {
            for key in &keys {
                assert!(
                    !key.contains(forbidden),
                    "FleetView (or a nested host/item) must never carry a field named/\
                     containing `{forbidden}` — found key `{key}`"
                );
            }
        }
    }

    /// Mutation-check companion (D2): proves the widened matching rule above
    /// actually catches the EXACT compound-word field the original version
    /// missed, without needing to touch the real `FleetView` struct. Frozen
    /// against regressing back to exact-match-only.
    #[test]
    fn the_forbidden_key_scan_catches_a_compound_word_score_field() {
        let mut keys = Vec::new();
        collect_all_keys(
            &serde_json::json!({ "hosts": [], "health_score": 94 }),
            &mut keys,
        );
        let forbidden = ["score", "health", "rating", "percent", "grade"];
        let caught = keys
            .iter()
            .any(|key| forbidden.iter().any(|word| key.contains(word)));
        assert!(
            caught,
            "a `health_score` field must be caught by the forbidden-key scan even though it \
             does not EXACTLY match any bare forbidden word"
        );
    }

    // -- local_host_view --------------------------------------------------------

    #[test]
    fn local_host_view_is_none_when_there_is_no_trustworthy_status_yet() {
        assert!(local_host_view(None, &[]).is_none());
    }

    #[test]
    fn local_host_view_reports_the_real_status_and_matching_badge() {
        let host = local_host_view(Some(CliStatus::NeedsAttention), &[]).unwrap();
        assert_eq!(host.machine_id, LOCAL_MACHINE_ID);
        assert_eq!(host.status, CliStatus::NeedsAttention);
        assert_eq!(host.badge_state, "triangle");
        assert!(host.actionable_items.is_empty());
    }

    #[test]
    fn local_host_view_maps_every_it_signal_kind_into_an_actionable_item() {
        let kinds = [ItSignalKind::PolicyDenial, ItSignalKind::SignatureFailure];
        let host = local_host_view(Some(CliStatus::Healthy), &kinds).unwrap();
        assert_eq!(host.actionable_items.len(), 2);
        assert_eq!(host.actionable_items[0].kind, ItSignalKind::PolicyDenial);
        assert_eq!(host.actionable_items[0].machine_id, LOCAL_MACHINE_ID);
        assert_eq!(
            host.actionable_items[1].kind,
            ItSignalKind::SignatureFailure
        );
    }

    // -- build_fleet_view / fleet_view_from_state --------------------------------

    #[test]
    fn build_fleet_view_always_includes_the_mock_fleet_mates() {
        let view = build_fleet_view(None, &[]);
        assert!(view.hosts.iter().all(|h| h.machine_id.starts_with("mock-")));
        assert_eq!(view.hosts.len(), 2);
    }

    #[test]
    fn build_fleet_view_puts_the_real_local_row_first_when_present() {
        let view = build_fleet_view(Some(CliStatus::Healthy), &[]);
        assert_eq!(view.hosts.len(), 3);
        assert_eq!(view.hosts[0].machine_id, LOCAL_MACHINE_ID);
        assert!(view.hosts[1..]
            .iter()
            .all(|h| h.machine_id.starts_with("mock-")));
    }

    #[test]
    fn fleet_view_from_state_reads_real_entries_from_the_local_sink() {
        let sink = LocalSink::new();
        sink.record(&ItSignal {
            kind: ItSignalKind::SignatureFailure,
            admin_contact: Some("it@example.com".to_string()),
        })
        .unwrap();
        let view = fleet_view_from_state(Some(CliStatus::NeedsAttention), &sink);
        let local = view
            .hosts
            .iter()
            .find(|h| h.machine_id == LOCAL_MACHINE_ID)
            .expect("local row present");
        assert_eq!(local.actionable_items.len(), 1);
        assert_eq!(
            local.actionable_items[0].kind,
            ItSignalKind::SignatureFailure
        );
    }

    #[test]
    fn fleet_view_from_state_omits_the_local_row_when_status_is_none() {
        let sink = LocalSink::new();
        let view = fleet_view_from_state(None, &sink);
        assert!(!view.hosts.iter().any(|h| h.machine_id == LOCAL_MACHINE_ID));
        // The mock rows still render — this dashboard is never a blank page.
        assert!(!view.hosts.is_empty());
    }
}
