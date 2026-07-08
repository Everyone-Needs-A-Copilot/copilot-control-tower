//! Windows [`PlatformWatchdogSignal`](crate::platform::PlatformWatchdogSignal)
//! — the Task Scheduler crash-only watchdog (M9/Stream-C, task 72,
//! ADR-M9-002, `docs/01-architecture/windows-parity.md` §1 row 1 / §3 Q1,
//! `.copilot/wp/53.md`). Fills the STUB Stream-B (task 71) pre-created so
//! this stream would have a collision-free file.
//!
//! ## The two halves of "crash-only" on Windows
//!
//! 1. **Liveness proof** ([`PlatformWatchdogSignal::observe`], below): the
//!    SAME `updater::heartbeat::FileHeartbeatSource` file contract M4
//!    already built and unit-tests platform-neutrally — reused UNCHANGED,
//!    exactly the way `platform::macos::MacWatchdogSignal` wraps it (this
//!    file's [`WindowsWatchdogSignal`] mirrors that struct's shape field for
//!    field). Only the heartbeat file's ROOT differs
//!    ([`windows_heartbeat_root`], `%LOCALAPPDATA%\...`) because Windows has
//!    no `$HOME`/`Library` convention — the heartbeat SCHEMA and
//!    hang-detection polling logic in `updater::heartbeat` are not
//!    re-derived or duplicated here.
//! 2. **The OS-level relaunch mechanism** ([`install`]/[`uninstall`],
//!    below): a Task Scheduler task imported from the checked-in
//!    `packaging/taskscheduler/controltower-watchdog.xml` template via
//!    [`super::schtasks::create_task_from_xml`] — a single `<LogonTrigger>`
//!    (fires once per user logon; belt-and-suspenders against a
//!    double-launch race with Stream-E's SEPARATE logon-trigger login-item
//!    task via both `MultipleInstancesPolicy=IgnoreNew` in the task XML
//!    itself AND this crate's existing `tauri-plugin-single-instance` guard,
//!    `lib.rs` — invariant #2, never a second resident process) plus a
//!    `<RestartOnFailure>` settings block (retry COUNT + INTERVAL — Task
//!    Scheduler's own name for "relaunch the action if its process exits
//!    non-zero", the direct analogue of launchd's
//!    `KeepAlive={SuccessfulExit:false}`). **Never** a `<TimeTrigger>`/
//!    `<CalendarTrigger>` with a `<Repetition>` block — that IS the
//!    forbidden "repeat every N minutes" resurrect-always anti-pattern
//!    (ADR-M9-002), guarded by
//!    `tests/fitness_m9_windows_watchdog_no_periodic_trigger.rs` (this
//!    stream's parity to the macOS `fitness_watchdog_plist.rs`'s FF-M4-1
//!    check).
//!
//! ## App-level circuit breaker + hang detection — reused, not re-derived
//!
//! `updater::circuit_breaker::{record_launch_attempt,
//! schedule_clean_run_after_healthy_uptime}` are called unconditionally from
//! `lib.rs::run()`'s `.setup()` — already cross-platform (no
//! `#[cfg(target_os = "macos")]` on either call site) — so the SAME "N
//! non-zero exits in a window -> stop relaunching, surface reinstall"
//! app-level breaker already covers Windows today, with zero changes needed
//! in this file. This module's job is only the two Windows-specific halves
//! above.
//!
//! ## OWNER-GATED (be honest, not just fast — ADR-M9-006)
//!
//! - Whether Task Scheduler's `RestartOnFailure` actually behaves
//!   crash-only under a real crash/hang on real hardware. There is no
//!   Windows toolchain on this machine — `schtasks.exe` doesn't exist
//!   here either — so none of this file, nor `super::schtasks`, has ever
//!   been compiled for a Windows target, let alone run.
//! - [`RESTART_RETRY_COUNT`]/[`RESTART_RETRY_INTERVAL`] are a documented
//!   STARTING POINT, reused from the SAME judgment-call defaults
//!   `updater::circuit_breaker` already flags as
//!   owner-ratification-pending on macOS
//!   (`ABNORMAL_LAUNCH_THRESHOLD`/`CRASH_WINDOW`) — not independently
//!   re-derived or Windows-native-tuned.
//! - Whether a `<LogonTrigger>` race against Stream-E's separate
//!   login-item task is genuinely harmless depends on this crate's
//!   `tauri-plugin-single-instance` guard behaving the same way on Windows
//!   as it does on macOS (plausible — it is the same cross-platform Tauri
//!   plugin — but not verified here) plus `MultipleInstancesPolicy` actually
//!   suppressing the second Task Scheduler-launched instance on a real box.
//!
//! ## Known pre-existing gap, not introduced or fixed by this task
//!
//! `updater::check::default_layout_root()` — the actual PRODUCTION call site
//! `apply_update`/`confirm_staged_bundle_boots` use for the SELF-UPDATE
//! heartbeat — still hardcodes `updater::heartbeat::default_heartbeat_root`'s
//! macOS-shaped `$HOME/Library/Application Support/...` path unconditionally,
//! with no Windows arm. [`windows_heartbeat_root`] below is this file's own,
//! separate root for [`WindowsWatchdogSignal::production`] — available for a
//! FUTURE cross-platform rewiring of `default_layout_root` itself, which is
//! out of this task's owned-files scope (`platform/windows/watchdog.rs` +
//! packaging + this stream's fitness test only, per the task's own file
//! list). Flagged here so it stays discoverable, not silently left as a
//! surprise for whichever stream eventually rewires `updater::check`.

#![cfg(windows)]

use crate::platform::PlatformWatchdogSignal;
use crate::updater::heartbeat::FileHeartbeatSource;
use crate::updater::watchdog::{HeartbeatOutcome, HeartbeatSource};
use std::path::{Path, PathBuf};
use std::time::Duration;

/// This crate's own Task Scheduler task path/name for the crash-restart
/// watchdog — folder-qualified (Task Scheduler organizes tasks into
/// folders) and distinct from Stream-E's separate logon-trigger login-item
/// task, so `schtasks /Query`/`/Delete` can never accidentally address the
/// wrong task.
pub const WATCHDOG_TASK_NAME: &str = r"\EveryoneNeedsACopilot\ControlTowerWatchdog";

/// The checked-in Task Scheduler XML template
/// (`packaging/taskscheduler/controltower-watchdog.xml`), embedded at
/// compile time so [`install`] never depends on a relative-path disk read
/// succeeding at runtime. The macOS equivalent (`install-watchdog.sh`)
/// instead reads its plist template from disk and substitutes placeholders
/// via a shell script at INSTALL time; this Rust port keeps the same
/// "reviewed checked-in template, substituted, never hand-edited in place"
/// discipline in-process instead of shelling out to `sed`.
const TASK_XML_TEMPLATE: &str =
    include_str!("../../../../packaging/taskscheduler/controltower-watchdog.xml");

/// The template placeholder [`render_task_xml`] substitutes with the real,
/// absolute app executable path. This module never resolves that path
/// itself — a caller supplies it (see `windows::cli_path`, Stream-H, for how
/// the translocation/hijack-safe install path is resolved).
const APP_EXE_PLACEHOLDER: &str = "__APP_EXE__";

/// OWNER-GATED TUNING (see module doc): Task Scheduler's own restart-cap
/// knob, distinct from (and layered underneath) the app-level
/// `updater::circuit_breaker` — the same two-layer shape launchd's
/// `ThrottleInterval` (OS-level, dumb, fixed cadence) plus the app-level
/// breaker (smart, counting, windowed) already has on macOS. Reused as a
/// starting point, not Windows-native-tuned.
pub const RESTART_RETRY_COUNT: u32 = 3;

/// The retry interval, as a [`Duration`] for any Rust-side reasoning about
/// it. Must be kept in sync BY HAND with the checked-in XML template's own
/// `<RestartOnFailure><Interval>PT1M</Interval>...` value (ISO-8601 `PT1M`
/// = 1 minute) — this module does not (and, given the schema's ISO-8601
/// duration format, cannot cheaply) generate the XML's interval value FROM
/// this constant; a future session could add a fitness test cross-checking
/// the two if drift ever becomes a real risk.
pub const RESTART_RETRY_INTERVAL: Duration = Duration::from_secs(60);

/// Windows equivalent of `updater::heartbeat::default_heartbeat_root` —
/// deliberately NOT added to that (cross-platform, M4-owned) module, which
/// this stream does not own; kept local to this file instead. Mirrors its
/// exact discipline: returns `None` only when the underlying OS environment
/// variable itself isn't set, never a guessed fallback location.
pub fn windows_heartbeat_root() -> Option<PathBuf> {
    std::env::var_os("LOCALAPPDATA").map(|dir| {
        PathBuf::from(dir)
            .join("EveryoneNeedsACopilot")
            .join("ControlTower")
            .join("updater")
    })
}

/// Generic over any [`HeartbeatSource`] so this wrapper is unit-testable
/// against a fake — identical shape to `platform::macos::MacWatchdogSignal`;
/// no new decision logic is invented for the Windows side of this trait.
#[derive(Debug, Clone)]
pub struct WindowsWatchdogSignal<H: HeartbeatSource = FileHeartbeatSource>(H);

impl WindowsWatchdogSignal<FileHeartbeatSource> {
    /// The production constructor. Returns `None` only when
    /// [`windows_heartbeat_root`] itself would (`%LOCALAPPDATA%` unset) —
    /// the same "never guess a fallback location" discipline
    /// `MacWatchdogSignal::production` already establishes.
    pub fn production(expected_app_version: impl Into<String>) -> Option<Self> {
        let layout_root = windows_heartbeat_root()?;
        Some(Self(FileHeartbeatSource {
            layout_root,
            expected_app_version: expected_app_version.into(),
        }))
    }
}

impl<H: HeartbeatSource> WindowsWatchdogSignal<H> {
    /// Test-only: wrap an injected fake directly.
    #[cfg(test)]
    pub(crate) fn wrapping(source: H) -> Self {
        Self(source)
    }
}

impl<H: HeartbeatSource> PlatformWatchdogSignal for WindowsWatchdogSignal<H> {
    fn observe(&self, staged: &Path, timeout: Duration) -> HeartbeatOutcome {
        self.0.observe(staged, timeout)
    }
}

// ---------------------------------------------------------------------------
// Task Scheduler registration — install / uninstall / never-orphan self-check
// ---------------------------------------------------------------------------

/// Renders [`TASK_XML_TEMPLATE`] with `app_exe` substituted for
/// [`APP_EXE_PLACEHOLDER`] — the in-process equivalent of
/// `install-watchdog.sh`'s `sed` substitution. A plain string replace, not a
/// templating engine: this crate takes no new dependency for one
/// placeholder, matching that script's own minimalism.
fn render_task_xml(app_exe: &Path) -> String {
    TASK_XML_TEMPLATE.replace(APP_EXE_PLACEHOLDER, &app_exe.display().to_string())
}

/// Registers the crash-only watchdog task, idempotently (safe to call on
/// every launch/update — [`super::schtasks::create_task_from_xml`]'s own
/// `/F` force-overwrite makes re-registration a no-op from the OS's
/// perspective, matching `loginitem::install`'s discipline). Writes the
/// rendered XML to a process-unique temp file (Task Scheduler's `/XML`
/// switch only accepts a file path, never stdin) and removes the temp file
/// afterward regardless of outcome — the temp file is scratch space, never
/// the source of truth (the checked-in template is).
pub fn install(app_exe: &Path) -> Result<(), String> {
    let xml = render_task_xml(app_exe);
    let temp_path = std::env::temp_dir().join(format!(
        "controltower-watchdog-task-{}.xml",
        std::process::id()
    ));
    std::fs::write(&temp_path, &xml)
        .map_err(|e| format!("couldn't write temp task XML {}: {e}", temp_path.display()))?;

    let result = super::schtasks::create_task_from_xml(WATCHDOG_TASK_NAME, &temp_path);
    let _ = std::fs::remove_file(&temp_path);
    result
}

/// Unregisters the watchdog task — unconditional, idempotent (see
/// [`super::schtasks::delete_task`]'s own contract: a missing task is
/// success, not an error).
pub fn uninstall() -> Result<(), String> {
    super::schtasks::delete_task(WATCHDOG_TASK_NAME)
}

/// The never-orphan self-check (ADR-M9-005's "MSI never-orphan" design,
/// mirroring the macOS watchdog's own `Program`-path poll + self-`bootout`
/// discipline, `architecture.md` §7, fixes B-H2): `true` exactly when
/// `app_exe` no longer exists AND the watchdog task is still registered —
/// the caller's cue to call [`uninstall`] so a drag-to-delete-equivalent
/// removal (or an MSI uninstall whose own uninstall custom action didn't
/// run) doesn't leave a scheduled task pointing at a vanished executable
/// forever. Deliberately returns a bool rather than calling [`uninstall`]
/// itself — the caller decides WHEN this check runs (e.g. once per normal
/// launch, alongside `updater::startup::reconcile_interrupted_update`); this
/// function only answers WHETHER it should act.
pub fn is_orphaned(app_exe: &Path) -> Result<bool, String> {
    if app_exe.exists() {
        return Ok(false);
    }
    super::schtasks::query_task_exists(WATCHDOG_TASK_NAME)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FixedHeartbeat(HeartbeatOutcome);
    impl HeartbeatSource for FixedHeartbeat {
        fn observe(&self, _staged: &Path, _timeout: Duration) -> HeartbeatOutcome {
            self.0
        }
    }

    // -- PlatformWatchdogSignal delegation (mirrors
    // platform::macos::MacWatchdogSignal's own tests exactly — same trait,
    // same shape; these run only on a real Windows build, never here). ------

    #[test]
    fn observe_delegates_straight_through_on_alive() {
        let wrapper = WindowsWatchdogSignal::wrapping(FixedHeartbeat(HeartbeatOutcome::Alive));
        assert_eq!(
            PlatformWatchdogSignal::observe(
                &wrapper,
                Path::new(r"C:\staged"),
                Duration::from_secs(1)
            ),
            HeartbeatOutcome::Alive
        );
    }

    #[test]
    fn observe_delegates_straight_through_on_timeout() {
        let wrapper = WindowsWatchdogSignal::wrapping(FixedHeartbeat(HeartbeatOutcome::Timeout));
        assert_eq!(
            PlatformWatchdogSignal::observe(
                &wrapper,
                Path::new(r"C:\staged"),
                Duration::from_millis(10)
            ),
            HeartbeatOutcome::Timeout
        );
    }

    #[test]
    fn observe_delegates_straight_through_on_malformed() {
        let wrapper = WindowsWatchdogSignal::wrapping(FixedHeartbeat(HeartbeatOutcome::Malformed));
        assert_eq!(
            PlatformWatchdogSignal::observe(
                &wrapper,
                Path::new(r"C:\staged"),
                Duration::from_millis(10)
            ),
            HeartbeatOutcome::Malformed
        );
    }

    #[test]
    fn production_uses_windows_heartbeat_root_or_none_when_localappdata_is_unset() {
        // Mirrors the exact contract `windows_heartbeat_root()` itself
        // documents — this wrapper adds no second fallback rule.
        let direct = windows_heartbeat_root();
        let via_wrapper = WindowsWatchdogSignal::production("9.9.9");
        assert_eq!(direct.is_some(), via_wrapper.is_some());
    }

    // -- render_task_xml -----------------------------------------------------

    #[test]
    fn render_task_xml_substitutes_the_app_exe_placeholder() {
        let xml = render_task_xml(Path::new(r"C:\Program Files\ControlTower\controltower.exe"));
        assert!(
            !xml.contains(APP_EXE_PLACEHOLDER),
            "placeholder must be fully substituted"
        );
        assert!(xml.contains(r"C:\Program Files\ControlTower\controltower.exe"));
    }

    #[test]
    fn render_task_xml_never_introduces_a_periodic_repeat_trigger() {
        // The exact regression this stream's dedicated crate-test-binary
        // fitness test also guards
        // (`tests/fitness_m9_windows_watchdog_no_periodic_trigger.rs`) —
        // duplicated here as a fast, in-module check against the RENDERED
        // (post-substitution) XML, not just the checked-in template.
        let xml = render_task_xml(Path::new(r"C:\controltower.exe"));
        for forbidden in ["<TimeTrigger>", "<CalendarTrigger>", "<Repetition>"] {
            assert!(
                !xml.contains(forbidden),
                "rendered task XML must never contain {forbidden} — that is the \
                 forbidden periodic-repeat-trigger anti-pattern (ADR-M9-002)"
            );
        }
        assert!(
            xml.contains("<RestartOnFailure>"),
            "must configure RestartOnFailure — the crash-only restart mechanism"
        );
        assert!(
            xml.contains("<LogonTrigger>"),
            "must use a LogonTrigger (fires once per logon), never a periodic one"
        );
    }

    // -- is_orphaned -----------------------------------------------------

    #[test]
    fn is_orphaned_is_false_when_the_app_exe_still_exists() {
        // A path guaranteed to exist regardless of platform (this crate's
        // own manifest) — `app_exe.exists()` short-circuits before any real
        // `schtasks` call would be attempted.
        let existing = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
        assert_eq!(is_orphaned(&existing), Ok(false));
    }
}
