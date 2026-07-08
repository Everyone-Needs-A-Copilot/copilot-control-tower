//! The liveness-heartbeat file contract + `--self-test` protocol (M4/S1,
//! ADR-M4-002, FF-M4-6). **This contract is DEFINED here, by M4** — there is
//! no pre-existing heartbeat file anywhere else in this crate or the CLI;
//! this module is the single source of truth for its path, schema, and the
//! read/write/parse functions every other consumer (this crate's own
//! `--self-test` entrypoint, and `updater::watchdog`'s promote/rollback
//! decision) must use rather than re-deriving.
//!
//! ## Why a file, and why here
//!
//! `updater::watchdog::decide` (Stream-D/S6, already landed) is fail-closed
//! by construction: it promotes on `watchdog::HeartbeatOutcome::Alive`
//! and rolls back on anything else. What it does NOT define is *how* a
//! freshly-staged, freshly-launched bundle proves it's alive — that's this
//! module's job. A file (not a socket/pipe/shared memory) is the simplest
//! mechanism that survives the exact failure modes this needs to survive: a
//! staged bundle that crashes immediately, hangs forever, or never gets far
//! enough to open a socket at all still leaves an honestly-absent (or
//! honestly-stale) heartbeat file for the reader to observe — there is no
//! "the channel itself might not exist yet" ambiguity a socket/pipe would
//! introduce.
//!
//! ## Path
//!
//! `<layout-root>/heartbeat.json`, where `<layout-root>` is the SAME
//! directory `updater::watchdog::StagedLayout`'s `root` already denotes
//! (`current`/`staged`/`last-known-good`/`poisoned` siblings) — this file is
//! deliberately NOT inside `staged/` or `current/` (which get renamed and
//! discarded across a promote/rollback): a fixed, layout-root-relative path
//! is one both the about-to-be-promoted-or-discarded staged process and the
//! decision-maker can agree on regardless of which bundle directory is
//! which at any given moment. [`default_heartbeat_root`] gives the
//! `$HOME`-derived default (matching `settings::writer::default_manifest_path`'s
//! "returns `None` only when `$HOME` isn't set at all" discipline); a caller
//! with a more specific layout root (tests, or a future explicit
//! configuration) should prefer [`heartbeat_path`] directly.
//!
//! ## Schema (`schema_version` "1.0")
//!
//! ```json
//! {
//!   "schema_version": "1.0",
//!   "pid": 12345,
//!   "app_version": "0.2.0",
//!   "phase": "self-test-ok",
//!   "written_at_unix_ms": 1750000000000
//! }
//! ```
//!
//! `phase` is one of `"self-test-started"` / `"self-test-ok"`
//! ([`HeartbeatPhase`]) — two states, not a bool, so a caller can
//! distinguish "the process launched at all" from "the process declared
//! itself healthy" when diagnosing a rollback, even though
//! [`FileHeartbeatSource`]'s promote/rollback DECISION only ever treats
//! `SelfTestOk` (matching pid + app_version) as promotable; anything else —
//! including a stale `SelfTestOk` left over from a previous run, or no file
//! at all — is "not yet proven alive", never "assume it's fine".
//!
//! ## The `--self-test` protocol
//!
//! [`SELF_TEST_FLAG`] is the argv flag a staged bundle is launched with;
//! [`run_self_test`] is the contract for what its `main()` must do on
//! seeing it — write `SelfTestStarted` immediately, run a caller-supplied
//! smoke check, then write `SelfTestOk` only on success. Wiring the actual
//! argv parse into `lib.rs`/`main.rs`'s startup path, and deciding what the
//! real smoke check probes, is Stream-D's S6/S11 (`do`, per `.copilot/wp/24.md`'s
//! Stream-A/Stream-D split) — this module exposes the contract as a plain
//! function so that wiring has something concrete to call, not a
//! re-derivation of this file format.

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use super::watchdog::{HeartbeatOutcome, HeartbeatSource};

pub const HEARTBEAT_SCHEMA_VERSION: &str = "1.0";

/// The argv flag a staged bundle is launched with to run its self-test
/// (ADR-M4-002: "launches it `--self-test`"). A literal constant, not a
/// magic string repeated at each call site.
pub const SELF_TEST_FLAG: &str = "--self-test";

/// The two liveness phases a heartbeat can declare — see the module doc for
/// why this isn't a bool.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum HeartbeatPhase {
    SelfTestStarted,
    SelfTestOk,
}

/// The on-disk heartbeat document — see the module doc's schema block.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Heartbeat {
    pub schema_version: String,
    pub pid: u32,
    pub app_version: String,
    pub phase: HeartbeatPhase,
    pub written_at_unix_ms: u64,
}

/// Every way reading/writing/parsing a heartbeat can fail — every variant
/// here means "treat this as NOT alive" to any promote/rollback decision
/// consuming it (mirrors `VerifyError`'s "every variant refuses" shape,
/// FF-M4-6's fail-closed framing extended to the heartbeat side).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HeartbeatError {
    /// No file at the expected path yet — the ordinary "still waiting"
    /// case, not a corruption signal.
    NotFound,
    /// The file exists but isn't valid JSON, or is JSON but doesn't match
    /// [`Heartbeat`]'s shape, or carries an unrecognized `schema_version`.
    Malformed(String),
    /// A filesystem-level problem other than "not found" (permissions, a
    /// path component existing as a file where a directory was expected,
    /// …).
    Io(String),
    /// [`run_self_test`]'s caller-supplied smoke check returned `false` —
    /// distinct from an I/O problem so a caller can tell "we couldn't even
    /// check" apart from "we checked, and it failed".
    SmokeCheckFailed,
}

impl std::fmt::Display for HeartbeatError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HeartbeatError::NotFound => write!(f, "no heartbeat file yet"),
            HeartbeatError::Malformed(reason) => {
                write!(f, "heartbeat file is unreadable: {reason}")
            }
            HeartbeatError::Io(reason) => write!(f, "couldn't access the heartbeat file: {reason}"),
            HeartbeatError::SmokeCheckFailed => write!(f, "self-test smoke check failed"),
        }
    }
}

impl std::error::Error for HeartbeatError {}

/// `$HOME`-derived default heartbeat layout root
/// (`~/Library/Application Support/com.everyoneneedsacopilot.controltower/updater`)
/// — `None` only when `$HOME` isn't set at all, matching
/// `settings::writer::default_manifest_path`'s discipline exactly (never
/// guesses a fallback location).
pub fn default_heartbeat_root() -> Option<PathBuf> {
    std::env::var_os("HOME").map(|home| {
        PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("com.everyoneneedsacopilot.controltower")
            .join("updater")
    })
}

/// The heartbeat file's path given a layout root (see the module doc for
/// why it's a fixed sibling of `current`/`staged`, not inside either).
pub fn heartbeat_path(layout_root: &Path) -> PathBuf {
    layout_root.join("heartbeat.json")
}

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Atomically writes a fresh [`Heartbeat`] to `path` — temp-file-in-the-
/// same-directory + `fsync` + `rename`, the identical crash-safety shape
/// `settings::writer::atomic_write` already established (duplicated rather
/// than shared across the module-ownership boundary in `mod.rs`'s doc; both
/// are a handful of lines and independently auditable).
pub fn write_heartbeat(
    path: &Path,
    app_version: &str,
    phase: HeartbeatPhase,
) -> Result<(), HeartbeatError> {
    let heartbeat = Heartbeat {
        schema_version: HEARTBEAT_SCHEMA_VERSION.to_string(),
        pid: std::process::id(),
        app_version: app_version.to_string(),
        phase,
        written_at_unix_ms: now_unix_ms(),
    };
    let json = serde_json::to_vec_pretty(&heartbeat)
        .map_err(|e| HeartbeatError::Io(format!("couldn't encode the heartbeat: {e}")))?;

    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .ok_or_else(|| HeartbeatError::Io("heartbeat path has no parent directory".to_string()))?;
    std::fs::create_dir_all(parent)
        .map_err(|e| HeartbeatError::Io(format!("couldn't create {}: {e}", parent.display())))?;

    let pid = std::process::id();
    let nonce = now_unix_ms();
    let temp_path = parent.join(format!(".heartbeat.{pid}.{nonce}.tmp"));

    let write_result = (|| -> std::io::Result<()> {
        use std::io::Write as _;
        let mut file = std::fs::File::create(&temp_path)?;
        file.write_all(&json)?;
        file.sync_all()?;
        Ok(())
    })();

    if let Err(e) = write_result {
        let _ = std::fs::remove_file(&temp_path);
        return Err(HeartbeatError::Io(format!(
            "couldn't write the heartbeat: {e}"
        )));
    }

    std::fs::rename(&temp_path, path).map_err(|e| {
        let _ = std::fs::remove_file(&temp_path);
        HeartbeatError::Io(format!("couldn't finalize the heartbeat: {e}"))
    })
}

/// Reads and parses the heartbeat at `path`. Fail-closed: any problem other
/// than "the file legitimately doesn't exist yet" ([`HeartbeatError::NotFound`])
/// is still an error, never a fabricated/default [`Heartbeat`] — a caller
/// (e.g. [`FileHeartbeatSource::observe`]) treats every error variant as
/// "not proven alive".
pub fn read_heartbeat(path: &Path) -> Result<Heartbeat, HeartbeatError> {
    let raw = match std::fs::read_to_string(path) {
        Ok(raw) => raw,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Err(HeartbeatError::NotFound),
        Err(e) => return Err(HeartbeatError::Io(e.to_string())),
    };
    let heartbeat: Heartbeat =
        serde_json::from_str(&raw).map_err(|e| HeartbeatError::Malformed(e.to_string()))?;
    if heartbeat.schema_version != HEARTBEAT_SCHEMA_VERSION {
        return Err(HeartbeatError::Malformed(format!(
            "unrecognized heartbeat schema_version {:?}",
            heartbeat.schema_version
        )));
    }
    Ok(heartbeat)
}

/// The `--self-test` contract (see the module doc): write `SelfTestStarted`
/// immediately, run `smoke_check`, and write `SelfTestOk` only if it
/// returns `true`. `smoke_check` is caller-supplied because what "actually
/// works" checks for THIS app (tray builds, webview inits, whatever S6
/// decides) is Stream-D's decision, not this module's — this function only
/// owns the heartbeat-writing PROTOCOL around whatever that check is.
pub fn run_self_test(
    heartbeat_path: &Path,
    app_version: &str,
    smoke_check: impl FnOnce() -> bool,
) -> Result<(), HeartbeatError> {
    write_heartbeat(heartbeat_path, app_version, HeartbeatPhase::SelfTestStarted)?;
    if smoke_check() {
        write_heartbeat(heartbeat_path, app_version, HeartbeatPhase::SelfTestOk)?;
        Ok(())
    } else {
        Err(HeartbeatError::SmokeCheckFailed)
    }
}

// ---------------------------------------------------------------------------
// The watchdog seam — implements `updater::watchdog::HeartbeatSource`
// ---------------------------------------------------------------------------

/// Wires this module's real, file-backed heartbeat into
/// `updater::watchdog::HeartbeatSource` — per `updater::mod`'s coordination
/// note, this is additive (a new `impl`), never a redefinition of
/// `watchdog`'s `HeartbeatOutcome`/`decide` contract. Polls
/// [`read_heartbeat`] at a short, fixed tick until either a matching
/// `SelfTestOk` is observed (-> `Alive`), a heartbeat is observed but
/// [`HeartbeatError::Malformed`] (-> `Malformed`, no point waiting out the
/// rest of the timeout for a file that's already provably corrupt), or
/// `timeout` elapses with nothing conclusive (-> `Timeout`).
pub struct FileHeartbeatSource {
    pub layout_root: PathBuf,
    pub expected_app_version: String,
}

const POLL_TICK: Duration = Duration::from_millis(5);

impl HeartbeatSource for FileHeartbeatSource {
    fn observe(&self, _staged: &Path, timeout: Duration) -> HeartbeatOutcome {
        let path = heartbeat_path(&self.layout_root);
        let deadline = Instant::now() + timeout;

        loop {
            match read_heartbeat(&path) {
                Ok(hb)
                    if hb.phase == HeartbeatPhase::SelfTestOk
                        && hb.app_version == self.expected_app_version =>
                {
                    return HeartbeatOutcome::Alive;
                }
                // Present but not yet the confirmed-healthy state for THIS
                // staged version (still `SelfTestStarted`, or a stale
                // heartbeat from a previous run/version) — keep waiting,
                // it may still transition before the deadline.
                Ok(_) => {}
                Err(HeartbeatError::NotFound) => {}
                // A confirmed-corrupt file is conclusive NOW — no amount of
                // additional waiting turns malformed JSON into a valid
                // heartbeat.
                Err(HeartbeatError::Malformed(_)) => return HeartbeatOutcome::Malformed,
                // A transient I/O race (e.g. observed mid-rename) — keep
                // polling; a persistent problem simply runs out the clock
                // and reports `Timeout`, which is the correct fail-closed
                // outcome either way.
                Err(HeartbeatError::Io(_)) | Err(HeartbeatError::SmokeCheckFailed) => {}
            }

            if Instant::now() >= deadline {
                return HeartbeatOutcome::Timeout;
            }
            std::thread::sleep(POLL_TICK);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    /// Same no-`tempfile`-dependency scratch-dir approach
    /// `updater::watchdog`'s own tests use (`Cargo.toml` stays `sec`'s file
    /// in this stream split — see `mod.rs`'s doc — so this mirrors that
    /// module's test helper rather than adding a dependency).
    fn scratch_dir(name: &str) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("ct-heartbeat-test-{name}-{pid}-{n}"));
        std::fs::create_dir_all(&dir).expect("create scratch dir");
        dir
    }

    // -- write/read round-trip ------------------------------------------

    #[test]
    fn a_written_heartbeat_round_trips_exactly() {
        let root = scratch_dir("roundtrip");
        let path = heartbeat_path(&root);
        write_heartbeat(&path, "1.2.3", HeartbeatPhase::SelfTestOk).expect("write");

        let hb = read_heartbeat(&path).expect("read");
        assert_eq!(hb.schema_version, HEARTBEAT_SCHEMA_VERSION);
        assert_eq!(hb.app_version, "1.2.3");
        assert_eq!(hb.phase, HeartbeatPhase::SelfTestOk);
        assert_eq!(hb.pid, std::process::id());

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn reading_a_heartbeat_that_was_never_written_is_not_found_not_a_panic() {
        let root = scratch_dir("absent");
        let path = heartbeat_path(&root);
        assert_eq!(read_heartbeat(&path), Err(HeartbeatError::NotFound));
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_malformed_heartbeat_file_fails_closed_as_malformed() {
        let root = scratch_dir("malformed");
        let path = heartbeat_path(&root);
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(&path, b"not json at all").unwrap();

        match read_heartbeat(&path) {
            Err(HeartbeatError::Malformed(_)) => {}
            other => panic!("expected Malformed, got {other:?}"),
        }
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn an_unrecognized_schema_version_is_treated_as_malformed_not_silently_accepted() {
        let root = scratch_dir("schema-drift");
        let path = heartbeat_path(&root);
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(
            &path,
            r#"{"schema_version":"99.0","pid":1,"app_version":"1.0.0","phase":"self-test-ok","written_at_unix_ms":0}"#,
        )
        .unwrap();

        match read_heartbeat(&path) {
            Err(HeartbeatError::Malformed(_)) => {}
            other => panic!("expected Malformed, got {other:?}"),
        }
        std::fs::remove_dir_all(&root).ok();
    }

    // -- run_self_test protocol ------------------------------------------

    #[test]
    fn run_self_test_writes_started_then_ok_on_a_passing_smoke_check() {
        let root = scratch_dir("selftest-ok");
        let path = heartbeat_path(&root);

        run_self_test(&path, "2.0.0", || true).expect("self-test should succeed");

        let hb = read_heartbeat(&path).expect("read");
        assert_eq!(hb.phase, HeartbeatPhase::SelfTestOk);
        assert_eq!(hb.app_version, "2.0.0");

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn run_self_test_leaves_started_not_ok_when_the_smoke_check_fails() {
        let root = scratch_dir("selftest-fail");
        let path = heartbeat_path(&root);

        let err = run_self_test(&path, "2.0.0", || false).expect_err("must fail");
        assert_eq!(err, HeartbeatError::SmokeCheckFailed);

        // The FILE, however, still shows `SelfTestStarted` — proving a
        // crash-before-healthy leaves an honest trail rather than either no
        // file or a fabricated `SelfTestOk`.
        let hb = read_heartbeat(&path).expect("read");
        assert_eq!(hb.phase, HeartbeatPhase::SelfTestStarted);

        std::fs::remove_dir_all(&root).ok();
    }

    // -- FileHeartbeatSource / the watchdog seam (FF-M4-6) -----------------

    #[test]
    fn observe_reports_alive_when_a_matching_self_test_ok_heartbeat_is_present() {
        let root = scratch_dir("observe-alive");
        let path = heartbeat_path(&root);
        write_heartbeat(&path, "3.0.0", HeartbeatPhase::SelfTestOk).expect("write");

        let source = FileHeartbeatSource {
            layout_root: root.clone(),
            expected_app_version: "3.0.0".to_string(),
        };
        let outcome = source.observe(&root.join("staged"), Duration::from_millis(200));
        assert_eq!(outcome, HeartbeatOutcome::Alive);

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn observe_times_out_when_no_heartbeat_ever_appears_fitness_ff_m4_6() {
        let root = scratch_dir("observe-timeout");
        let source = FileHeartbeatSource {
            layout_root: root.clone(),
            expected_app_version: "3.0.0".to_string(),
        };
        let outcome = source.observe(&root.join("staged"), Duration::from_millis(30));
        assert_eq!(outcome, HeartbeatOutcome::Timeout);

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn observe_reports_malformed_immediately_without_waiting_out_the_full_timeout() {
        let root = scratch_dir("observe-malformed");
        let path = heartbeat_path(&root);
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(&path, b"garbage, not json").unwrap();

        let source = FileHeartbeatSource {
            layout_root: root.clone(),
            expected_app_version: "3.0.0".to_string(),
        };
        let start = Instant::now();
        let outcome = source.observe(&root.join("staged"), Duration::from_secs(5));
        assert_eq!(outcome, HeartbeatOutcome::Malformed);
        assert!(
            start.elapsed() < Duration::from_secs(1),
            "a confirmed-malformed heartbeat must not wait out the rest of the timeout"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn observe_never_promotes_on_a_stale_heartbeat_for_a_different_app_version() {
        // A leftover heartbeat from a PREVIOUS self-test (different
        // version) must not be mistaken for THIS staged version being
        // alive — it should behave exactly like "not yet observed" and
        // eventually time out.
        let root = scratch_dir("observe-stale-version");
        let path = heartbeat_path(&root);
        write_heartbeat(&path, "1.0.0-old", HeartbeatPhase::SelfTestOk).expect("write");

        let source = FileHeartbeatSource {
            layout_root: root.clone(),
            expected_app_version: "2.0.0-new".to_string(),
        };
        let outcome = source.observe(&root.join("staged"), Duration::from_millis(30));
        assert_eq!(outcome, HeartbeatOutcome::Timeout);

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn default_heartbeat_root_is_under_home_application_support() {
        if let Some(root) = default_heartbeat_root() {
            assert!(root.ends_with("com.everyoneneedsacopilot.controltower/updater"));
        }
    }
}
