//! Startup reconciliation (M4 gap-closure, S11 item 4): a crash-only check
//! run once at the START of every NORMAL app launch (`lib.rs::run()`'s
//! `.setup()`) — never the `--self-test` entrypoint itself
//! (`updater::selftest`), never a resident loop (invariant #2) — that
//! notices and resolves a PRIOR launch's `check::apply_update()` having
//! been interrupted mid-self-test: the whole app killed or crashed after
//! staging a bundle (`check::confirm_staged_bundle_boots` launched it) but
//! BEFORE that function ever reached `watchdog::run_self_test`'s
//! promote-or-rollback decision.
//!
//! A leftover `staged/` directory in that state is never implicitly trusted
//! on the next launch — this reconciles it via the SAME fail-closed
//! `watchdog::run_self_test` (never re-implemented) using a heartbeat
//! source that always reports `Timeout`, exactly matching what a genuinely
//! crashed/hung self-test would already have produced (FF-M4-6: absence of
//! proof is never treated as proof of health).
//!
//! `current/`/`last-known-good/` are never touched by this reconciliation —
//! `watchdog`'s own rollback path (which this indirectly calls) only ever
//! discards `staged/` and writes a poison marker, so "ensure the app is
//! running the last-known-good" is automatically already true: this
//! reconciliation runs INSIDE the process that already IS `current/`
//! (nothing promoted it away out from under it); it just makes sure a
//! half-decided `staged/` never lingers as an ambiguous, un-poisoned
//! leftover a later launch might mistakenly trust.

use std::path::Path;
use std::time::Duration;

use super::check;
use super::rollback_marker;
use super::watchdog::{self, HeartbeatOutcome, HeartbeatSource, StagedLayout};

/// A [`HeartbeatSource`] that always reports [`HeartbeatOutcome::Timeout`]
/// immediately — there is, by definition, no live self-test process to
/// observe here: whatever process would have run one, on a PRIOR launch,
/// already crashed or was killed before finishing. Fail-closed: an
/// interrupted, never-confirmed self-test is never silently promoted just
/// because the app happens to be starting up again.
struct NeverAliveSource;

impl HeartbeatSource for NeverAliveSource {
    fn observe(&self, _staged: &Path, _timeout: Duration) -> HeartbeatOutcome {
        HeartbeatOutcome::Timeout
    }
}

/// The production entry point — `lib.rs::run()`'s `.setup()` calls this
/// once, before the tray/doctor-timer machinery starts.
pub fn reconcile_interrupted_update() {
    reconcile_interrupted_update_at(&check::default_layout_root());
}

/// The testable core — `layout_root` is an explicit parameter so tests
/// exercise this against a scratch directory instead of the real
/// `$HOME/Library/Application Support/…` (the same `*_at` production-wrapper
/// split every other entry point in this module tree uses).
pub(crate) fn reconcile_interrupted_update_at(layout_root: &Path) {
    let layout = StagedLayout::new(layout_root);
    let staged = layout.staged();
    if !staged.is_dir() {
        // The ordinary case on every normal launch: no interrupted update.
        return;
    }

    let staged_version = std::fs::read_to_string(staged.join("VERSION"))
        .map(|s| s.trim().to_string())
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string());

    // `NeverAliveSource` always reports `Timeout`, so `watchdog::decide`
    // (called inside `run_self_test`) always resolves to `Decision::
    // RollBack` here — still routed through the real `watchdog::
    // run_self_test` rather than a hand-rolled discard, so this
    // reconciliation can never drift from the SAME fail-closed
    // decide/promote/rollback code every other caller uses.
    if let Ok(watchdog::Decision::RollBack { poisoned_version }) =
        watchdog::run_self_test(&layout, &staged_version, Duration::ZERO, &NeverAliveSource)
    {
        rollback_marker::record_rollback(layout_root, &poisoned_version);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn scratch_dir(name: &str) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("ct-startup-test-{name}-{pid}-{n}"));
        std::fs::create_dir_all(&dir).expect("create scratch dir");
        dir
    }

    #[test]
    fn a_leftover_staged_bundle_is_discarded_poisoned_and_marked_for_the_next_launch() {
        let root = scratch_dir("interrupted");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();
        std::fs::create_dir_all(layout.staged()).unwrap();
        std::fs::write(layout.staged().join("VERSION"), "2.0.0-interrupted").unwrap();

        reconcile_interrupted_update_at(&root);

        assert!(
            !layout.staged().exists(),
            "an interrupted staged bundle must be discarded"
        );
        assert_eq!(
            std::fs::read_to_string(layout.current().join("VERSION")).unwrap(),
            "1.0.0",
            "current (last-known-good — already what's running) must be untouched"
        );
        assert!(layout.is_poisoned("2.0.0-interrupted"));
        assert_eq!(
            rollback_marker::take_rollback_outcome(&root).as_deref(),
            Some("2.0.0-interrupted"),
            "the NEXT normal launch's check_for_update must surface this once"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn no_staged_bundle_is_a_no_op_never_fabricates_a_rollback() {
        let root = scratch_dir("clean");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();

        reconcile_interrupted_update_at(&root);

        assert!(
            rollback_marker::take_rollback_outcome(&root).is_none(),
            "a clean launch with nothing staged must never fabricate a rollback marker"
        );
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn calling_it_twice_in_a_row_is_safe_idempotent() {
        let root = scratch_dir("idempotent");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();
        std::fs::create_dir_all(layout.staged()).unwrap();
        std::fs::write(layout.staged().join("VERSION"), "2.0.0-bad").unwrap();

        reconcile_interrupted_update_at(&root);
        // Second call: nothing staged anymore, must be a clean no-op that
        // never re-poisons or re-records a marker that was already cleared.
        let _ = rollback_marker::take_rollback_outcome(&root);
        reconcile_interrupted_update_at(&root);

        assert!(!layout.staged().exists());
        assert!(rollback_marker::take_rollback_outcome(&root).is_none());
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_staged_bundle_with_no_readable_version_file_is_still_discarded_and_poisoned_as_unknown() {
        let root = scratch_dir("no-version");
        let layout = StagedLayout::new(&root);
        std::fs::create_dir_all(layout.current()).unwrap();
        std::fs::write(layout.current().join("VERSION"), "1.0.0").unwrap();
        // A `staged/` directory that exists but never got as far as writing
        // its own VERSION marker — an even earlier crash than usual.
        std::fs::create_dir_all(layout.staged()).unwrap();

        reconcile_interrupted_update_at(&root);

        assert!(!layout.staged().exists());
        assert!(layout.is_poisoned("unknown"));
        assert_eq!(
            rollback_marker::take_rollback_outcome(&root).as_deref(),
            Some("unknown")
        );
        std::fs::remove_dir_all(&root).ok();
    }
}
