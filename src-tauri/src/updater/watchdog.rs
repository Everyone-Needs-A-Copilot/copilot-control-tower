//! Staged-bundle layout + promote/rollback decision (M4 Stream-D, S6;
//! ADR-M4-002, `release-and-versioning.md` §5, FF-M4-6).
//!
//! **Ownership (`CLAUDE.md` invariant #2 — single process):** the watchdog
//! here is `launchd` itself (crash-only relaunch of the *same* signed
//! binary — see `packaging/launchd/`), never a second resident process.
//! What this module owns is the *decision logic* the app's own
//! `--self-test` startup path calls into: given a staged self-update and a
//! heartbeat verdict, should it be promoted or rolled back — plus the
//! on-disk layout that decision operates over. That logic runs transiently,
//! inside the one app binary, at the start of a launchd-triggered relaunch;
//! it is not itself a daemon.
//!
//! ## Staged-bundle layout
//!
//! ```text
//! <support-dir>/updater/
//!   current/            the version currently running / promoted
//!   staged/              a downloaded, signature+staple-verified candidate
//!                        awaiting its self-test heartbeat
//!   last-known-good/     the previous `current`, kept exactly one
//!                        generation deep so a bad promote can still be
//!                        recovered from without re-downloading
//!   poisoned/<version>   a marker for a version that failed its heartbeat
//!                        — that channel must never re-serve it
//!                        (release-and-versioning.md §5 step 4)
//! ```
//!
//! Each of `current`/`staged`/`last-known-good` is a directory containing at
//! minimum a `VERSION` file (the real layout also holds the staged `.app`
//! bundle itself; this module's tests exercise the directory-rename/marker
//! bookkeeping, not bundle contents, which belong to the actual updater
//! transport).
//!
//! ## The heartbeat seam
//!
//! [`HeartbeatSource`] is a small trait, not a concrete reader — the actual
//! heartbeat-file format/path is `sec`'s `updater/heartbeat.rs` (not landed
//! as of this session; see this module's parent doc). Once it exists, wire
//! it to this trait (or have this trait's only impl simply call it) instead
//! of duplicating the heartbeat contract here. [`decide`] is fail-closed by
//! construction (FF-M4-6): anything other than a clean, on-time heartbeat
//! rolls back — there is no third "unsure, promote anyway" branch.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// The on-disk staged-bundle layout root (a directory containing
/// `current`/`staged`/`last-known-good`/`poisoned`). Construct with
/// [`StagedLayout::new`]; the four accessor methods are the only paths any
/// caller should compute — never string-concatenate a sibling path by hand.
#[derive(Debug, Clone)]
pub struct StagedLayout {
    root: PathBuf,
}

impl StagedLayout {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn current(&self) -> PathBuf {
        self.root.join("current")
    }

    pub fn staged(&self) -> PathBuf {
        self.root.join("staged")
    }

    pub fn last_known_good(&self) -> PathBuf {
        self.root.join("last-known-good")
    }

    /// The poison marker for a specific version — an empty file whose mere
    /// *presence* is the fact recorded (no content needed): "this channel
    /// must never re-serve this version" (release-and-versioning.md §5).
    pub fn poison_marker(&self, version: &str) -> PathBuf {
        self.root.join("poisoned").join(version)
    }

    pub fn is_poisoned(&self, version: &str) -> bool {
        self.poison_marker(version).is_file()
    }
}

/// What the (eventual, `sec`-owned) heartbeat check observed for a staged
/// bundle's `--self-test` launch. Deliberately three variants, not a bool —
/// [`decide`] treats `Timeout` and `Malformed` identically (both roll back),
/// but keeping them distinct lets a caller log *why* separately from the
/// pass/fail verdict, mirroring `cli::path::PathError`'s "same outcome,
/// distinguishable cause" shape.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeartbeatOutcome {
    /// The staged bundle wrote its early liveness heartbeat within the
    /// launch-attempt window. The only outcome that promotes.
    Alive,
    /// No heartbeat was observed before the launch-attempt window elapsed
    /// (crash, hang, or never got far enough to write it).
    Timeout,
    /// A heartbeat file was observed but failed to parse / didn't match the
    /// expected schema — treated identically to `Timeout` (fail-closed: an
    /// unreadable heartbeat is not evidence of health).
    Malformed,
}

/// The seam this module consumes rather than redefines — see the module
/// doc. A real implementation (once `sec`'s `heartbeat.rs` lands) launches
/// the staged bundle with `--self-test` and watches for its heartbeat file;
/// this trait exists so [`decide`]/[`promote`]/[`rollback`] are fully
/// unit-testable today against a fake.
pub trait HeartbeatSource {
    fn observe(&self, staged: &Path, timeout: Duration) -> HeartbeatOutcome;
}

/// What the watchdog should do with a staged bundle, given a heartbeat
/// verdict.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    Promote,
    RollBack { poisoned_version: String },
}

/// FF-M4-6, fail-closed: only [`HeartbeatOutcome::Alive`] promotes.
/// `Timeout` and `Malformed` both roll back — there is no "promote anyway"
/// branch for an inconclusive heartbeat, matching M1's fail-closed doctor
/// parse (absence is refusal, not success).
pub fn decide(outcome: HeartbeatOutcome, staged_version: &str) -> Decision {
    match outcome {
        HeartbeatOutcome::Alive => Decision::Promote,
        HeartbeatOutcome::Timeout | HeartbeatOutcome::Malformed => Decision::RollBack {
            poisoned_version: staged_version.to_string(),
        },
    }
}

/// Runs a [`HeartbeatSource`] against `layout`'s staged bundle and applies
/// whatever [`decide`] returns — the single call site a real caller (the
/// app's `--self-test` startup path) needs, so the "observe then act"
/// sequence can't be split and reordered by accident.
pub fn run_self_test(
    layout: &StagedLayout,
    staged_version: &str,
    timeout: Duration,
    source: &dyn HeartbeatSource,
) -> io::Result<Decision> {
    let outcome = source.observe(&layout.staged(), timeout);
    let decision = decide(outcome, staged_version);
    match &decision {
        Decision::Promote => promote(layout)?,
        Decision::RollBack { poisoned_version } => rollback(layout, poisoned_version)?,
    }
    Ok(decision)
}

/// Promotes `staged` to `current`, keeping the prior `current` as exactly
/// one generation of `last-known-good` (ADR-M4-002: "a bad promote can still
/// be recovered from"). No-op-safe: if `staged` doesn't exist, this is an
/// error (a caller should only promote after a real self-test pass).
fn promote(layout: &StagedLayout) -> io::Result<()> {
    let current = layout.current();
    let staged = layout.staged();
    let lkg = layout.last_known_good();

    if !staged.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("no staged bundle at {}", staged.display()),
        ));
    }

    if current.exists() {
        if lkg.exists() {
            fs::remove_dir_all(&lkg)?;
        }
        fs::rename(&current, &lkg)?;
    }
    fs::rename(&staged, &current)?;
    Ok(())
}

/// Discards the staged bundle, leaves `current` exactly as it was (the
/// previously-working version keeps running — release-and-versioning.md
/// §5 step 3), and records the poison marker so this channel never re-offers
/// `poisoned_version` (§5 step 4).
fn rollback(layout: &StagedLayout, poisoned_version: &str) -> io::Result<()> {
    let staged = layout.staged();
    if staged.exists() {
        fs::remove_dir_all(&staged)?;
    }
    let marker = layout.poison_marker(poisoned_version);
    if let Some(parent) = marker.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&marker, b"")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    /// A fresh, uniquely-named scratch directory under the OS temp dir —
    /// avoids a `tempfile` dependency (Cargo.toml is `sec`'s file in this
    /// stream split; see `mod.rs`'s doc) while still giving each test its
    /// own isolated root.
    fn scratch_dir(name: &str) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("ct-watchdog-test-{name}-{pid}-{n}"));
        fs::create_dir_all(&dir).expect("create scratch dir");
        dir
    }

    fn make_bundle_dir(path: &Path, version: &str) {
        fs::create_dir_all(path).expect("create bundle dir");
        fs::write(path.join("VERSION"), version).expect("write VERSION");
    }

    struct FixedHeartbeat(HeartbeatOutcome);
    impl HeartbeatSource for FixedHeartbeat {
        fn observe(&self, _staged: &Path, _timeout: Duration) -> HeartbeatOutcome {
            self.0
        }
    }

    #[test]
    fn decide_promotes_only_on_alive() {
        assert_eq!(decide(HeartbeatOutcome::Alive, "1.2.0"), Decision::Promote);
    }

    #[test]
    fn decide_rolls_back_on_timeout_fitness_ff_m4_6() {
        assert_eq!(
            decide(HeartbeatOutcome::Timeout, "1.2.0"),
            Decision::RollBack {
                poisoned_version: "1.2.0".to_string()
            }
        );
    }

    #[test]
    fn decide_rolls_back_on_malformed_heartbeat_fitness_ff_m4_6() {
        assert_eq!(
            decide(HeartbeatOutcome::Malformed, "1.2.0"),
            Decision::RollBack {
                poisoned_version: "1.2.0".to_string()
            }
        );
    }

    #[test]
    fn never_reaches_promoted_without_an_alive_heartbeat() {
        // A property test in miniature: every non-Alive outcome must map to
        // RollBack, never Promote — the fail-closed contract FF-M4-6 names
        // ("must reach RolledBack{poisoned} and never Promoted").
        for outcome in [HeartbeatOutcome::Timeout, HeartbeatOutcome::Malformed] {
            match decide(outcome, "9.9.9") {
                Decision::RollBack { .. } => {}
                Decision::Promote => panic!("outcome {outcome:?} must never promote"),
            }
        }
    }

    #[test]
    fn promote_moves_staged_to_current_and_keeps_prior_current_as_last_known_good() {
        let root = scratch_dir("promote");
        let layout = StagedLayout::new(&root);
        make_bundle_dir(&layout.current(), "1.0.0");
        make_bundle_dir(&layout.staged(), "1.1.0");

        let decision = run_self_test(
            &layout,
            "1.1.0",
            Duration::from_secs(1),
            &FixedHeartbeat(HeartbeatOutcome::Alive),
        )
        .expect("run_self_test");

        assert_eq!(decision, Decision::Promote);
        assert!(!layout.staged().exists(), "staged should be consumed");
        assert_eq!(
            fs::read_to_string(layout.current().join("VERSION")).unwrap(),
            "1.1.0"
        );
        assert_eq!(
            fs::read_to_string(layout.last_known_good().join("VERSION")).unwrap(),
            "1.0.0"
        );

        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn rollback_discards_staged_keeps_current_and_poisons_the_version() {
        let root = scratch_dir("rollback");
        let layout = StagedLayout::new(&root);
        make_bundle_dir(&layout.current(), "1.0.0");
        make_bundle_dir(&layout.staged(), "1.1.0-bad");

        let decision = run_self_test(
            &layout,
            "1.1.0-bad",
            Duration::from_millis(50),
            &FixedHeartbeat(HeartbeatOutcome::Timeout),
        )
        .expect("run_self_test");

        assert_eq!(
            decision,
            Decision::RollBack {
                poisoned_version: "1.1.0-bad".to_string()
            }
        );
        assert!(!layout.staged().exists(), "bad staged bundle is discarded");
        assert_eq!(
            fs::read_to_string(layout.current().join("VERSION")).unwrap(),
            "1.0.0",
            "current (previously-working version) must be untouched"
        );
        assert!(layout.is_poisoned("1.1.0-bad"));
        assert!(
            !layout.is_poisoned("1.0.0"),
            "the good version is never poisoned"
        );

        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_poisoned_version_stays_poisoned_across_layout_instances() {
        let root = scratch_dir("poison-persist");
        let layout_a = StagedLayout::new(&root);
        make_bundle_dir(&layout_a.current(), "1.0.0");
        make_bundle_dir(&layout_a.staged(), "1.1.0-bad");
        rollback(&layout_a, "1.1.0-bad").expect("rollback");

        // A fresh StagedLayout over the same root (e.g. a subsequent process
        // launch checking "have we already tried and poisoned this
        // version") must see the same marker — poisoning is a fact on disk,
        // not in-memory state.
        let layout_b = StagedLayout::new(&root);
        assert!(layout_b.is_poisoned("1.1.0-bad"));

        fs::remove_dir_all(&root).ok();
    }
}
