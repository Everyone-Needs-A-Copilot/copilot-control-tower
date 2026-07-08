//! The "last update outcome" marker (M4 gap-closure, S11 item 3).
//!
//! `check::apply_update`'s own process (the OLD binary, still running while
//! it stages+self-tests a candidate — see `check::confirm_staged_bundle_
//! boots`) is not necessarily the session Bob is looking at when a rollback
//! happens; by the time `UpdateStatus::RolledBack` would matter to him, that
//! call may already be returning into a background poll no one's watching.
//! So a rollback decision is ALSO persisted here as a tiny, non-secret
//! marker file — `check::check_for_update`'s own NORMAL (not self-test)
//! call, on the NEXT launch/poll, reads it once, surfaces
//! `UpdateStatus::RolledBack` to the UI exactly once, then clears it:
//! shown-once, never re-shown, never fabricated (the only writer is a REAL
//! rollback decision — `check::confirm_staged_bundle_boots`'s own
//! `Decision::RollBack` arm, and `updater::startup`'s interrupted-update
//! reconciliation).
//!
//! Same atomic-write shape `settings::writer::atomic_write`/
//! `heartbeat::write_heartbeat` already established (temp-file-in-the-
//! same-directory + `fsync` + `rename`) — duplicated rather than shared
//! across the module-ownership boundary, matching `heartbeat.rs`'s own doc's
//! rationale for doing the same thing ("a handful of lines, independently
//! auditable"). Content is non-secret: a version string that already
//! appears in the (public, signed) update manifest, and nothing else — no
//! PII, no credentials, no ETA (invariant #4's "no secret" and this
//! project's "no ETA surfaced" both hold trivially here).

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// The marker's filename — a sibling of `heartbeat.json` under the same
/// layout root `updater::watchdog::StagedLayout`/`updater::heartbeat`
/// already denote (never inside `staged/`/`current`, which get renamed or
/// discarded across a promote/rollback).
const MARKER_FILENAME: &str = "last-update-outcome.json";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Marker {
    poisoned_version: String,
}

fn marker_path(layout_root: &Path) -> PathBuf {
    layout_root.join(MARKER_FILENAME)
}

/// Persists that a rollback just happened for `poisoned_version`. Callers:
/// `check::confirm_staged_bundle_boots`'s `Decision::RollBack` arm, and
/// `updater::startup::reconcile_interrupted_update_at` — both, and only
/// those, are real rollback decisions; this function is never called
/// speculatively.
///
/// Best-effort: a write failure here degrades to "the next launch's toast is
/// silently missed", not a crash — the actual safety property (keep
/// last-known-good running, discard/poison the bad staged version) already
/// happened via `watchdog::run_self_test` regardless of whether this marker
/// write succeeds.
pub(crate) fn record_rollback(layout_root: &Path, poisoned_version: &str) {
    let marker = Marker {
        poisoned_version: poisoned_version.to_string(),
    };
    let Ok(json) = serde_json::to_vec_pretty(&marker) else {
        return;
    };

    let path = marker_path(layout_root);
    let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) else {
        return;
    };
    if std::fs::create_dir_all(parent).is_err() {
        return;
    }

    let temp_path = parent.join(format!(
        ".{MARKER_FILENAME}.tmp-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));

    let write_result = (|| -> std::io::Result<()> {
        use std::io::Write as _;
        let mut file = std::fs::File::create(&temp_path)?;
        file.write_all(&json)?;
        file.sync_all()?;
        Ok(())
    })();

    if write_result.is_err() {
        let _ = std::fs::remove_file(&temp_path);
        return;
    }

    let _ = std::fs::rename(&temp_path, &path);
}

/// Reads and CLEARS the marker (shown-once) — returns
/// `Some(poisoned_version)` exactly once per real rollback, `None` on every
/// subsequent call until another real rollback writes a fresh one.
/// Fail-closed toward "nothing to show": any read/parse problem (including
/// "no marker file", the ordinary case on almost every launch) is `None`,
/// never fabricated content.
pub(crate) fn take_rollback_outcome(layout_root: &Path) -> Option<String> {
    let path = marker_path(layout_root);
    let raw = std::fs::read_to_string(&path).ok()?;
    let marker: Marker = serde_json::from_str(&raw).ok()?;
    let _ = std::fs::remove_file(&path);
    Some(marker.poisoned_version)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn scratch_dir(name: &str) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("ct-rollback-marker-test-{name}-{pid}-{n}"));
        std::fs::create_dir_all(&dir).expect("create scratch dir");
        dir
    }

    #[test]
    fn a_recorded_rollback_is_surfaced_exactly_once_then_cleared() {
        let root = scratch_dir("once");
        record_rollback(&root, "1.2.3-bad");

        assert_eq!(take_rollback_outcome(&root).as_deref(), Some("1.2.3-bad"));
        assert!(
            take_rollback_outcome(&root).is_none(),
            "shown-once: a second read finds nothing"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn no_marker_is_the_ordinary_case_not_an_error() {
        let root = scratch_dir("absent");
        assert!(take_rollback_outcome(&root).is_none());
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_corrupt_marker_file_is_treated_as_absent_fail_closed() {
        let root = scratch_dir("corrupt");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(marker_path(&root), b"not json at all").unwrap();
        assert!(take_rollback_outcome(&root).is_none());
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn recording_twice_overwrites_rather_than_appends() {
        let root = scratch_dir("overwrite");
        record_rollback(&root, "1.0.0-bad");
        record_rollback(&root, "2.0.0-bad");
        assert_eq!(take_rollback_outcome(&root).as_deref(), Some("2.0.0-bad"));
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn write_leaves_no_temp_file_behind() {
        let root = scratch_dir("no-temp");
        record_rollback(&root, "1.0.0-bad");
        let entries: Vec<String> = std::fs::read_dir(&root)
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(entries, vec![MARKER_FILENAME.to_string()]);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn no_marker_file_never_gets_created_by_a_read_that_finds_nothing() {
        let root = scratch_dir("read-only-no-create");
        std::fs::create_dir_all(&root).unwrap();
        let _ = take_rollback_outcome(&root);
        assert!(
            std::fs::read_dir(&root).unwrap().next().is_none(),
            "reading an absent marker must never create anything"
        );
        std::fs::remove_dir_all(&root).ok();
    }
}
