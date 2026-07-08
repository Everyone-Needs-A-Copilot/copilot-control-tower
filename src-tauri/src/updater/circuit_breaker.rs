//! ADR-M4-001's app-level launch-failure circuit breaker (QA-flagged D1,
//! `scratchpad/qa-m4-acceptance.md`): `architecture.md`'s own text —
//! "A `ThrottleInterval` + a launch-failure circuit breaker (N non-zero exits
//! in a window → stop relaunching, surface 'reinstall') prevents crash
//! storms" — repeated verbatim across `threat-model.md`/`redteam-
//! platform.md`/`windows-parity.md`/`prd.md` and 4 `docs/product-design/`
//! files, and ratified as Case Law (`SOUL.md` lines 147/408). The plist's own
//! checked-in comment says this half "lives in app code, not here";
//! `ThrottleInterval` (the "dumb", OS-level backoff) already exists in
//! `packaging/launchd/*.plist` — until this module, the "smart" app-level
//! half did not exist anywhere in `src-tauri/src`.
//!
//! ## What this guards against
//!
//! `launchd`'s crash-only watchdog (`KeepAlive={SuccessfulExit:false}`)
//! relaunches the CURRENT/promoted binary on any non-zero exit, forever, at a
//! fixed `ThrottleInterval` cadence — correct for one isolated crash, wrong
//! for a build that crashes on every launch for a reason unrelated to a
//! self-update (a corrupted install, a bad non-update code path, disk
//! full, …). The staged-bundle rollback machinery
//! (`updater::watchdog`/`updater::check::confirm_staged_bundle_boots`)
//! cannot see or fix this: that machinery only ever runs during an update's
//! OWN self-test, never on an ordinary relaunch of the already-promoted
//! `current/` build. This module is the missing escalation: it counts
//! consecutive launches that were never proven clean, and once that count
//! crosses a threshold, tells the caller (`lib.rs::run()`) to stop starting
//! the normal (and possibly crash-causing) app path and enter an honest,
//! degraded "needs attention / reinstall" state instead — never a false
//! Healthy, per invariant #4/CLAUDE.md "the tray icon still cannot lie".
//!
//! ## Mechanics
//!
//! A tiny, non-secret, atomically-written marker
//! (temp-file-in-the-same-directory + `fsync` + `rename` — the SAME
//! crash-safety shape `heartbeat::write_heartbeat`/`rollback_marker::
//! record_rollback` already establish, duplicated per `mod.rs`'s own
//! cross-module-ownership rationale rather than shared) sits alongside
//! `heartbeat.json`/`last-update-outcome.json` under the same layout root
//! (`updater::check::default_layout_root()`, never inside `current`/
//! `staged`/`last-known-good`, which get renamed or discarded across a
//! promote/rollback). It holds one counter —
//! `consecutive_unproven_launches` — plus the wall-clock time it was last
//! touched:
//!
//! - [`record_launch_attempt`] runs as the FIRST thing `lib.rs::run()`'s
//!   `.setup()` does, before anything else (tray build, doctor timer,
//!   wizard, interrupted-update reconciliation) that could itself be the
//!   thing crashing. It INCREMENTS the counter (pessimistic: "this launch
//!   has not yet proven itself") and returns
//!   [`LaunchDecision::CircuitOpen`] once the count reaches
//!   [`ABNORMAL_LAUNCH_THRESHOLD`] — the caller must then skip the normal
//!   startup path.
//! - [`record_clean_run`] is called only after the app has stayed up past
//!   [`HEALTHY_UPTIME`] — a Tokio task started via
//!   [`schedule_clean_run_after_healthy_uptime`] alongside the doctor timer,
//!   mirroring `timer::start`'s own "spawn a task inside this process,
//!   never a second process" shape (invariant #2). It resets the counter to
//!   zero: proof this launch was NOT itself part of a crash loop.
//! - If the app never survives long enough to call `record_clean_run` (it
//!   crashes, hangs and is killed, or is force-quit before `HEALTHY_UPTIME`
//!   elapses), the NEXT launch's `record_launch_attempt` sees the
//!   still-elevated count and increments it further. No separate "was the
//!   last exit code zero or non-zero" plumbing is needed — a launch that
//!   never reaches "proven clean" behaves identically regardless of exactly
//!   how it failed to get there, which is the fail-closed property the ADR
//!   asks for: **ambiguity is treated as a failed launch.**
//!
//! **The window.** ADR-M4-001 says "N non-zero exits in a *window*" — a
//! crash from long ago should not, by itself, count toward today's storm.
//! If the marker's last-touched timestamp is older than [`CRASH_WINDOW`],
//! `record_launch_attempt` treats this launch as the start of a fresh
//! sequence (count reset before incrementing) rather than an (N+1)th
//! continuation. This also gives the breaker a natural, unattended recovery
//! path once the window lapses (standard circuit-breaker "half-open retry"
//! shape) — it does not durably wedge a machine shut solely because a crash
//! happened once, days ago.
//!
//! **Fail-closed on ambiguity.** A marker file that EXISTS but fails to
//! parse (corrupt JSON, unrecognized shape) is never treated as "no
//! history, start fresh" — that would silently fail OPEN exactly when the
//! on-disk state is least trustworthy. Instead it is treated as already at
//! the threshold: `record_launch_attempt` trips the breaker immediately and
//! rewrites the marker to an unambiguous, honest "at threshold" value —
//! matching the "absence/corruption is refusal" discipline `heartbeat.rs`/
//! `verify.rs` already use elsewhere in this module tree. A best-effort
//! WRITE failure (disk full, permissions) degrades the OTHER direction —
//! like `rollback_marker::record_rollback`, it never panics or blocks the
//! launch; this launch's own decision has already been made from whatever
//! was actually readable before the write was attempted.
//!
//! ## Threshold and window are NOT pinned by the ADR
//!
//! `architecture.md`'s ADR-M4-001 names the SHAPE ("N non-zero exits in a
//! window") but never a value for N or the window — the same kind of
//! underspecification `windows-parity.md` §11 already flags for
//! `ThrottleInterval` itself. [`ABNORMAL_LAUNCH_THRESHOLD`]/[`CRASH_WINDOW`]/
//! [`HEALTHY_UPTIME`] below are this session's judgment-call defaults,
//! deliberately named consts (grep-able, one place to change) —
//! **flagged here for owner ratification**, not values read out of the ADR
//! text itself.

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

/// The marker's filename — a sibling of `heartbeat.json`/
/// `last-update-outcome.json` under the same layout root (see module doc).
const MARKER_FILENAME: &str = "launch-circuit-breaker.json";

/// ADR-M4-001's "N" — owner-ratification-pending default (see module doc).
pub const ABNORMAL_LAUNCH_THRESHOLD: u32 = 5;

/// ADR-M4-001's "window" — owner-ratification-pending default (see module
/// doc). Chosen generously relative to `packaging/launchd`'s own
/// `ThrottleInterval=10`s: at 10s between relaunch attempts,
/// [`ABNORMAL_LAUNCH_THRESHOLD`] relaunches within this window is already
/// the crash-storm signature the ADR describes, not a coincidence of
/// unrelated crashes days apart.
pub const CRASH_WINDOW: Duration = Duration::from_secs(10 * 60);

/// How long a launch must stay up before it counts as "proven clean" and
/// resets the counter — owner-ratification-pending default (see module
/// doc). Short enough that a genuinely healthy launch clears it almost
/// immediately; long enough that a launch which crashes moments after
/// finishing `.setup()` — the exact failure mode this breaker exists for —
/// does not.
pub const HEALTHY_UPTIME: Duration = Duration::from_secs(30);

/// What [`record_launch_attempt`] decided for THIS launch, given the
/// persisted history — see the module doc.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LaunchDecision {
    /// Proceed with the normal startup path — the threshold has not been
    /// crossed.
    Proceed,
    /// The breaker has tripped: [`ABNORMAL_LAUNCH_THRESHOLD`] consecutive
    /// unproven launches within [`CRASH_WINDOW`] (or an unreadable/corrupt
    /// marker, fail-closed) — the caller must enter the safe/degraded
    /// state instead of the normal (possibly crash-causing) startup path.
    CircuitOpen,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Marker {
    consecutive_unproven_launches: u32,
    last_touched_unix_ms: u64,
}

fn marker_path(layout_root: &Path) -> PathBuf {
    layout_root.join(MARKER_FILENAME)
}

fn now_unix_ms(now: SystemTime) -> u64 {
    now.duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Atomic write — identical shape to `rollback_marker::record_rollback`
/// (temp-file-in-the-same-directory + `fsync` + `rename`); best-effort,
/// never panics (see module doc's "fail-closed on ambiguity" section for
/// why a write failure is handled differently from a read/parse failure).
fn write_marker(layout_root: &Path, marker: &Marker) {
    let Ok(json) = serde_json::to_vec_pretty(marker) else {
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

/// What the on-disk marker implies for THIS launch's starting count, before
/// incrementing — `None` means "ambiguous, fail closed" (see module doc).
fn previous_count(layout_root: &Path, now: SystemTime) -> Option<u32> {
    let path = marker_path(layout_root);
    match std::fs::read_to_string(&path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Some(0),
        // Any I/O problem OTHER than "no marker yet" is ambiguity, not the
        // ordinary case — fail closed rather than silently starting fresh.
        Err(_) => None,
        Ok(raw) => match serde_json::from_str::<Marker>(&raw) {
            Err(_) => None,
            Ok(marker) => {
                let now_ms = now_unix_ms(now);
                let age_ms = now_ms.saturating_sub(marker.last_touched_unix_ms);
                if age_ms > CRASH_WINDOW.as_millis() as u64 {
                    // Outside the window: an old crash does not haunt a
                    // fresh sequence forever (see module doc's "the
                    // window").
                    Some(0)
                } else {
                    Some(marker.consecutive_unproven_launches)
                }
            }
        },
    }
}

/// The testable core of the startup check — `layout_root`/`now` are
/// explicit so tests exercise this against a scratch directory and a
/// controlled clock instead of `$HOME`/`SystemTime::now()`. See the module
/// doc for the full decision shape.
pub(crate) fn record_launch_attempt_at(layout_root: &Path, now: SystemTime) -> LaunchDecision {
    let (count, tripped) = match previous_count(layout_root, now) {
        Some(prev) => {
            let next = prev.saturating_add(1);
            (next, next >= ABNORMAL_LAUNCH_THRESHOLD)
        }
        // Ambiguous marker: assume the worst rather than guess — trip now,
        // and persist an unambiguous "at threshold" value so the ambiguity
        // does not recur on the very next read.
        None => (ABNORMAL_LAUNCH_THRESHOLD, true),
    };

    write_marker(
        layout_root,
        &Marker {
            consecutive_unproven_launches: count,
            last_touched_unix_ms: now_unix_ms(now),
        },
    );

    if tripped {
        LaunchDecision::CircuitOpen
    } else {
        LaunchDecision::Proceed
    }
}

/// The production entry point — `lib.rs::run()`'s `.setup()` calls this as
/// the FIRST thing it does, before anything else that could itself be the
/// thing crashing (see module doc).
pub fn record_launch_attempt() -> LaunchDecision {
    record_launch_attempt_at(&super::check::default_layout_root(), SystemTime::now())
}

/// The testable core of "this launch proved itself clean" — unconditionally
/// resets the counter to zero (a fresh, non-elevated marker), regardless of
/// whatever it held before.
pub(crate) fn record_clean_run_at(layout_root: &Path, now: SystemTime) {
    write_marker(
        layout_root,
        &Marker {
            consecutive_unproven_launches: 0,
            last_touched_unix_ms: now_unix_ms(now),
        },
    );
}

/// The production entry point — called once the app has stayed up past
/// [`HEALTHY_UPTIME`] (see [`schedule_clean_run_after_healthy_uptime`]).
pub fn record_clean_run() {
    record_clean_run_at(&super::check::default_layout_root(), SystemTime::now());
}

/// Starts the "prove this launch clean" background task — call once, from
/// `lib.rs::run()`'s `.setup()`, only on the NORMAL (not circuit-open)
/// startup path. Mirrors `timer::start`'s "a Tokio task inside this process"
/// shape (invariant #2 — no second process, no daemon): sleeps
/// [`HEALTHY_UPTIME`], then calls [`record_clean_run`] exactly once.
/// Deliberately takes no `AppHandle` — unlike the doctor timer, this task
/// touches no Tauri-managed state, only the on-disk marker.
pub fn schedule_clean_run_after_healthy_uptime() {
    tauri::async_runtime::spawn(async move {
        sleep(HEALTHY_UPTIME).await;
        record_clean_run();
    });
}

/// Sleeps `d` without blocking the async runtime's worker threads —
/// identical shape to `timer::sleep` (this crate takes no direct `tokio`
/// dependency; `tauri::async_runtime` re-exports the primitives it needs).
async fn sleep(d: Duration) {
    let _ = tauri::async_runtime::spawn_blocking(move || std::thread::sleep(d)).await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn scratch_dir(name: &str) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("ct-circuit-breaker-test-{name}-{pid}-{n}"));
        std::fs::create_dir_all(&dir).expect("create scratch dir");
        dir
    }

    fn read_marker(layout_root: &Path) -> Marker {
        let raw = std::fs::read_to_string(marker_path(layout_root)).expect("marker exists");
        serde_json::from_str(&raw).expect("marker parses")
    }

    // -- the core threshold/reset mechanism --------------------------------

    #[test]
    fn n_consecutive_unproven_launches_trip_the_breaker() {
        let root = scratch_dir("trip");
        let mut now = SystemTime::now();

        for i in 1..ABNORMAL_LAUNCH_THRESHOLD {
            let decision = record_launch_attempt_at(&root, now);
            assert_eq!(
                decision,
                LaunchDecision::Proceed,
                "launch {i} of {ABNORMAL_LAUNCH_THRESHOLD} must not trip the breaker yet"
            );
            now += Duration::from_secs(1);
        }

        let decision = record_launch_attempt_at(&root, now);
        assert_eq!(
            decision,
            LaunchDecision::CircuitOpen,
            "the {ABNORMAL_LAUNCH_THRESHOLD}th consecutive unproven launch must trip the breaker"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_clean_run_resets_the_counter_so_the_next_launch_starts_fresh() {
        let root = scratch_dir("reset");
        let mut now = SystemTime::now();

        for _ in 0..(ABNORMAL_LAUNCH_THRESHOLD - 1) {
            record_launch_attempt_at(&root, now);
            now += Duration::from_secs(1);
        }
        assert_eq!(
            read_marker(&root).consecutive_unproven_launches,
            ABNORMAL_LAUNCH_THRESHOLD - 1
        );

        // The app proved itself clean before crashing again.
        record_clean_run_at(&root, now);
        assert_eq!(read_marker(&root).consecutive_unproven_launches, 0);

        // The NEXT launch starts from zero, not from where it left off.
        now += Duration::from_secs(1);
        let decision = record_launch_attempt_at(&root, now);
        assert_eq!(decision, LaunchDecision::Proceed);
        assert_eq!(read_marker(&root).consecutive_unproven_launches, 1);

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn once_tripped_the_breaker_stays_open_within_the_window() {
        let root = scratch_dir("stays-open");
        let mut now = SystemTime::now();

        for _ in 0..ABNORMAL_LAUNCH_THRESHOLD {
            record_launch_attempt_at(&root, now);
            now += Duration::from_secs(1);
        }
        // Another attempt shortly after tripping, still inside the window.
        let decision = record_launch_attempt_at(&root, now);
        assert_eq!(
            decision,
            LaunchDecision::CircuitOpen,
            "a launch shortly after tripping, still within the crash window, must stay open"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    // -- the window ----------------------------------------------------------

    #[test]
    fn a_crash_outside_the_window_does_not_count_toward_a_fresh_storm() {
        let root = scratch_dir("window-expired");
        let mut now = SystemTime::now();

        for _ in 0..(ABNORMAL_LAUNCH_THRESHOLD - 1) {
            record_launch_attempt_at(&root, now);
            now += Duration::from_secs(1);
        }
        assert_eq!(
            read_marker(&root).consecutive_unproven_launches,
            ABNORMAL_LAUNCH_THRESHOLD - 1
        );

        // A long time passes — well outside the crash window — before the
        // next launch. That launch must be treated as the start of a fresh
        // sequence, not the Nth continuation of a long-dead storm.
        now += CRASH_WINDOW + Duration::from_secs(1);
        let decision = record_launch_attempt_at(&root, now);
        assert_eq!(decision, LaunchDecision::Proceed);
        assert_eq!(
            read_marker(&root).consecutive_unproven_launches,
            1,
            "a launch after the window elapses starts a fresh count, not (N-1)+1"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    // -- fail-closed on ambiguity ---------------------------------------------

    #[test]
    fn a_corrupt_marker_trips_the_breaker_immediately_fail_closed() {
        let root = scratch_dir("corrupt");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(marker_path(&root), b"not json at all").unwrap();

        let decision = record_launch_attempt_at(&root, SystemTime::now());
        assert_eq!(
            decision,
            LaunchDecision::CircuitOpen,
            "an unreadable/corrupt marker is ambiguity — ADR-M4-001's own instruction is to \
             treat ambiguity as a failed launch and break the loop, never to guess a fresh start"
        );
        // The marker is rewritten to an unambiguous value, so the ambiguity
        // does not recur every single subsequent read.
        assert_eq!(
            read_marker(&root).consecutive_unproven_launches,
            ABNORMAL_LAUNCH_THRESHOLD
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn no_marker_at_all_is_the_ordinary_first_launch_case_not_an_error() {
        let root = scratch_dir("absent");
        let decision = record_launch_attempt_at(&root, SystemTime::now());
        assert_eq!(
            decision,
            LaunchDecision::Proceed,
            "a genuinely first-ever launch (no marker yet) must proceed normally"
        );
        assert_eq!(read_marker(&root).consecutive_unproven_launches, 1);
        std::fs::remove_dir_all(&root).ok();
    }

    // -- marker hygiene: atomic, never-destroy, non-secret --------------------

    #[test]
    fn the_write_is_atomic_and_leaves_no_temp_file_behind() {
        let root = scratch_dir("atomic");
        record_launch_attempt_at(&root, SystemTime::now());

        let entries: Vec<String> = std::fs::read_dir(&root)
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            entries,
            vec![MARKER_FILENAME.to_string()],
            "only the final marker file should exist — no leftover .tmp file"
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn repeated_writes_overwrite_in_place_never_destroying_the_layout_root_or_siblings() {
        let root = scratch_dir("never-destroy");
        // A sibling file this module must never touch or delete (mirroring
        // heartbeat.json / last-update-outcome.json living alongside it in
        // production).
        std::fs::write(root.join("heartbeat.json"), b"{}").unwrap();

        for _ in 0..3 {
            record_launch_attempt_at(&root, SystemTime::now());
        }

        assert!(
            root.join("heartbeat.json").exists(),
            "the circuit breaker marker write must never destroy an unrelated sibling file"
        );
        assert!(marker_path(&root).exists());

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn the_marker_content_carries_no_secret_only_a_counter_and_a_timestamp() {
        let root = scratch_dir("no-secret");
        record_launch_attempt_at(&root, SystemTime::now());
        let raw = std::fs::read_to_string(marker_path(&root)).unwrap();
        let value: serde_json::Value = serde_json::from_str(&raw).unwrap();
        let keys: Vec<&String> = value.as_object().expect("object").keys().collect();
        assert_eq!(
            keys.len(),
            2,
            "the marker must carry exactly the counter + timestamp, nothing else: {raw}"
        );
        assert!(value.get("consecutive_unproven_launches").is_some());
        assert!(value.get("last_touched_unix_ms").is_some());

        std::fs::remove_dir_all(&root).ok();
    }
}
