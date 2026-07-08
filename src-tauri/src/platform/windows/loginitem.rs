//! Windows [`PlatformLoginItem`](crate::platform::PlatformLoginItem) — a
//! per-user, LOGON-trigger Task Scheduler task (M9/Stream-E, task 74,
//! `docs/01-architecture/windows-parity.md` §1 row 2, ADR-M5-004's Windows
//! counterpart). See [`super::schtasks`] for the shared, Stream-B-owned
//! `/Create`/`/Delete`/`/Query` helper this module consumes read-only.
//!
//! ## ADR-M5-004's Windows counterpart — login-launch is DISTINCT from the
//! crash-only watchdog
//!
//! Exactly as `loginitem::mod`'s own ADR-M5-004 documents for macOS: this
//! task answers "should this app start now, at logon" — a completely
//! different question from "did this process die and need resurrecting",
//! which is [`super::watchdog`]'s (Stream-C's) job. **Two mechanisms, ONE
//! binary, per-user, NO second resident process.** This module never spawns
//! a process itself (`schtasks /Create` only asks the OS to remember "start
//! this at next logon"), and the checked-in XML template
//! (`packaging/taskscheduler/logon-task.xml`) carries no
//! `<RestartOnFailure>` element and no periodic repeat trigger — that
//! belongs exclusively to Stream-C's separately-named crash-restart task,
//! imported through the SAME shared [`super::schtasks`] helper under a
//! DIFFERENT task name. `tests/fitness_m9_windows_loginitem_gated_on_managed_config.rs`
//! is this stream's own standing source-scan guard (see that file's doc for
//! exactly what it checks); it does not re-prove the watchdog delineation
//! itself, since it cannot touch `watchdog.rs` (a different stream's file).
//!
//! ## Managed, not user-defeatable — and why Task Scheduler, not the Run key
//!
//! `windows-parity.md` §1 row 2 names `HKCU\...\Run` as "the simpler
//! fallback", but this module deliberately implements ONLY the Task
//! Scheduler logon-trigger task, never a Run-key write. A Bob can delete an
//! ordinary `HKCU\...\Run` value with nothing more than `regedit` or a
//! third-party "startup manager" utility — that is exactly the
//! user-defeatable toggle this feature must NOT be (parity to macOS's
//! managed, force-approved `SMAppService` item). A **GPO/Intune-required**
//! scheduled task, by contrast, is genuinely non-toggleable by a local
//! admin the policy engine re-asserts against — the property this feature
//! actually needs. The empirical question of whether a real GPO/Intune push
//! achieves that in practice is owner-gated (needs a real domain-joined box
//! + console, per `docs/06-deployment/m9-owner-gated-split.md`); the design
//! choice of mechanism is not.
//!
//! ## Gating: folded into `register()`, unlike macOS's one-level-up split
//!
//! On macOS, `loginitem::smappservice::LoginItemService::register()` is
//! purely mechanical — the DECIDE (`loginitem::decide_enablement`, reading
//! the forced `LoginItemManaged` key) lives one level up in `loginitem::mod`,
//! because `SMAppService` itself has an OS-native consent/force-approval
//! concept a managed payload can separately satisfy. Task Scheduler has no
//! such built-in gate: nothing else will refuse to register this task on a
//! `LoginItemManaged=false` fleet, so [`WindowsLoginItem::register`] below
//! calls [`crate::loginitem::decide_enablement`] directly and is a no-op
//! (never calls [`super::schtasks::create_task_from_xml`]) whenever
//! [`crate::loginitem::LoginItemEnablement::should_register`] is `false`.
//! This is the SAME shared DECIDE function macOS's `loginitem::mod` uses —
//! it already reads the forced `LoginItemManaged` key via
//! [`crate::managed::forced::forced_bool`], which is a plain, cross-platform
//! free function that ALREADY has a fail-closed
//! `#[cfg(not(target_os = "macos"))]` stub (returns `Absent` off-macOS,
//! never guesses) — this module reuses that function unchanged rather than
//! reimplementing forced-domain reading, per this task's own scope
//! constraint. Once Stream-D (task 73, `windows::forced`,
//! `PlatformForcedConfig`) lands the real gated `HKLM\...\Policies` read
//! behind that same seam, this module picks it up automatically with **zero
//! code change here** — it consumes the DECIDE layer by calling the shared
//! function, never Stream-D's `windows::forced::WindowsForcedConfig` type
//! directly, and never re-reads the registry itself.
//!
//! [`WindowsLoginItem::unregister`] is unconditional (mirrors
//! `loginitem::mod::remove`'s own "the uninstall path must never register,
//! always removes" contract); [`WindowsLoginItem::status`] is a pure,
//! non-mutating read.
//!
//! ## The `schtasks /Query` enablement probe (parity B-H3)
//!
//! [`probe_to_status`] maps [`super::schtasks::query_task_exists`]'s
//! `Result<bool, String>` to [`LoginItemStatus`] — the exact "neutral
//! status-mapping" this task names, feeding the same "background running is
//! off" Bob-facing detection `loginitem::persistence_state` already collapses
//! [`LoginItemStatus`] into on the macOS side (unchanged, reused as-is).
//! Task Scheduler has no approval-gate concept analogous to
//! `SMAppServiceStatus::RequiresApproval` for a per-user task, so that
//! variant is never produced here — a present task maps to `Enabled`, an
//! absent one (or a query failure) fails closed to `NotFound` rather than
//! guessing.
//!
//! ## Owner-gated
//!
//! None of `schtasks.exe`'s real behavior has ever been exercised — there is
//! no Windows toolchain on this machine (see [`super::schtasks`]'s own
//! doc). What IS reviewable here: the gating order (`register()` consults
//! `decide_enablement()` before ever calling `create_task_from_xml`, proven
//! by `tests/fitness_m9_windows_loginitem_gated_on_managed_config.rs`, a
//! real macOS-executed source scan) and the pure `probe_to_status`/
//! `render_task_xml` mapping functions (unit-tested below — these tests are
//! correct and reviewable but, like every file under `platform/windows/`,
//! never actually run in this session's `cargo test`, since the whole
//! module is `#[cfg(windows)]`-gated out on a macOS host).

#![cfg(windows)]

use std::path::{Path, PathBuf};

use crate::loginitem::decide_enablement;
use crate::loginitem::smappservice::{LoginItemError, LoginItemStatus};
use crate::platform::PlatformLoginItem;

use super::schtasks::{create_task_from_xml, delete_task, query_task_exists};

/// This app's logon-trigger task name — distinct from Stream-C's
/// crash-restart task name (`watchdog.rs` owns that constant; never shared,
/// never reused here) so `schtasks /Query`/`/Delete` against one can never
/// accidentally touch the other.
pub const LOGON_TASK_NAME: &str = "EveryoneNeedsACopilot\\ControlTowerLogon";

/// The checked-in XML task-definition template this module imports via
/// `schtasks /Create /XML` — see that file's own doc for the invariant it
/// encodes (no `<RestartOnFailure>`, no periodic trigger). `CARGO_MANIFEST_
/// DIR` is `<repo>/src-tauri`; this file lives at `src/platform/windows/`,
/// four directories below the repo root, where `packaging/` lives.
const LOGON_TASK_XML_TEMPLATE: &str =
    include_str!("../../../../packaging/taskscheduler/logon-task.xml");

/// The template's one substitution point — the absolute path to this app's
/// own executable, resolved the same translocation/hijack-safe way
/// `platform::windows::cli_path` resolves the vendored CLI's own location
/// (`current_exe()`, canonicalized — never `argv[0]`).
const APP_PATH_PLACEHOLDER: &str = "__APP_PATH__";

/// A per-user Task Scheduler logon-trigger login item. Carries the task name
/// as a field (rather than a bare unit struct) so a future test can register
/// a differently-named task without colliding with a real one, mirroring
/// `platform::windows::watchdog::WindowsWatchdogSignal`'s own doc note about
/// naming this task distinctly from its sibling.
#[derive(Debug, Clone)]
pub struct WindowsLoginItem {
    task_name: String,
}

impl Default for WindowsLoginItem {
    fn default() -> Self {
        Self {
            task_name: LOGON_TASK_NAME.to_string(),
        }
    }
}

impl WindowsLoginItem {
    /// The production constructor — the real, shared logon-task name.
    pub fn production() -> Self {
        Self::default()
    }

    /// Test-only: register/query/delete a differently-named task, so a
    /// (future, real-Windows-run) integration test never risks touching the
    /// production task name.
    #[cfg(test)]
    fn with_task_name(name: &str) -> Self {
        Self {
            task_name: name.to_string(),
        }
    }
}

impl PlatformLoginItem for WindowsLoginItem {
    /// Gated on [`crate::loginitem::decide_enablement`] — see the module
    /// doc's "Gating" section for why this differs from macOS's one-level-up
    /// split. A `LoginItemManaged=false` fleet fact means this method is a
    /// pure no-op: it never calls `create_task_from_xml` at all, so an
    /// explicit forced-domain "do not register" always wins.
    fn register(&self) -> Result<(), LoginItemError> {
        if !decide_enablement().should_register() {
            return Ok(());
        }

        let exe = std::env::current_exe()
            .and_then(|p| p.canonicalize())
            .map_err(|e| {
                LoginItemError(format!("resolving this app's own exe path failed: {e}"))
            })?;

        let rendered = render_task_xml(&exe);
        let xml_path = write_temp_xml(&self.task_name, &rendered).map_err(|e| {
            LoginItemError(format!("writing the logon-task XML template failed: {e}"))
        })?;

        create_task_from_xml(&self.task_name, &xml_path).map_err(LoginItemError)
    }

    /// Unconditional, matching `loginitem::mod::remove`'s own "the uninstall
    /// path must never register, always removes" contract — never gated on
    /// `decide_enablement`, since an uninstall must remove the task
    /// regardless of what the forced domain currently says.
    fn unregister(&self) -> Result<(), LoginItemError> {
        delete_task(&self.task_name).map_err(LoginItemError)
    }

    /// A pure, non-mutating read — see [`probe_to_status`].
    fn status(&self) -> LoginItemStatus {
        probe_to_status(query_task_exists(&self.task_name))
    }
}

/// The neutral status-mapping this task names: `schtasks /Query`'s
/// `Result<bool, String>` (does the task currently exist) to
/// [`LoginItemStatus`]. `Ok(true)` (task present) maps to `Enabled` — Task
/// Scheduler has no per-user approval-gate concept, unlike `SMAppService`,
/// so `RequiresApproval` is never produced here. Both "the task genuinely
/// isn't there" (`Ok(false)`) and "the probe itself failed to run"
/// (`Err(_)`) fail closed to `NotFound` rather than guessing — this mirrors
/// `RealSMAppService::status`'s own "any status this binding doesn't yet
/// name fails closed to `NotFound`" discipline.
fn probe_to_status(probe: Result<bool, String>) -> LoginItemStatus {
    match probe {
        Ok(true) => LoginItemStatus::Enabled,
        Ok(false) => LoginItemStatus::NotFound,
        Err(_) => LoginItemStatus::NotFound,
    }
}

/// Substitutes [`APP_PATH_PLACEHOLDER`] in the checked-in XML template with
/// this app's own absolute exe path. Pure string substitution — no I/O, no
/// registry/Task-Scheduler call, easy to unit-test independent of
/// `schtasks.exe` actually existing.
fn render_task_xml(app_path: &Path) -> String {
    LOGON_TASK_XML_TEMPLATE.replace(APP_PATH_PLACEHOLDER, &app_path.display().to_string())
}

/// Writes the rendered XML to a scratch file `schtasks /Create /XML` can
/// import — `schtasks.exe` (per [`super::schtasks`]'s own doc) only imports
/// a file, it never accepts XML on stdin, so a temp file is unavoidable
/// here. The task-name-derived filename keeps concurrent
/// register()/`with_task_name` test calls (a future real-Windows run) from
/// racing on the same path.
fn write_temp_xml(task_name: &str, rendered: &str) -> std::io::Result<PathBuf> {
    let sanitized: String = task_name
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect();
    let path = std::env::temp_dir().join(format!("ct-logon-task-{sanitized}.xml"));
    std::fs::write(&path, rendered)?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Like every other file under `platform/windows/`, these tests compile
    // and are reviewable but never actually RUN in this session's `cargo
    // test` — the whole module is `#[cfg(windows)]`-gated out on a macOS
    // host, at both the declaration site (`platform/mod.rs`) and this
    // file's own `#![cfg(windows)]` inner attribute. Real execution against
    // `schtasks.exe` is owner-gated to a real Windows box.

    #[test]
    fn probe_ok_true_maps_to_enabled() {
        assert_eq!(probe_to_status(Ok(true)), LoginItemStatus::Enabled);
    }

    #[test]
    fn probe_ok_false_fails_closed_to_not_found_never_a_guessed_requires_approval() {
        assert_eq!(probe_to_status(Ok(false)), LoginItemStatus::NotFound);
    }

    #[test]
    fn probe_err_fails_closed_to_not_found_rather_than_panicking() {
        assert_eq!(
            probe_to_status(Err("schtasks.exe not found".to_string())),
            LoginItemStatus::NotFound
        );
    }

    #[test]
    fn render_task_xml_substitutes_the_app_path_placeholder() {
        let app_path =
            Path::new(r"C:\Users\bob\AppData\Local\Programs\ControlTower\controltower.exe");
        let rendered = render_task_xml(app_path);
        assert!(
            rendered.contains(r"C:\Users\bob\AppData\Local\Programs\ControlTower\controltower.exe")
        );
        assert!(!rendered.contains(APP_PATH_PLACEHOLDER));
    }

    #[test]
    fn render_task_xml_never_introduces_a_restart_on_failure_element() {
        // Standing, regression-proof reminder alongside the module doc's
        // "Two mechanisms, ONE binary" section: this task's own template
        // must never grow a RestartOnFailure element -- that is
        // watchdog.rs's job, a DIFFERENT scheduled task.
        let rendered = render_task_xml(Path::new(r"C:\app.exe"));
        assert!(!rendered.contains("RestartOnFailure"));
    }

    #[test]
    fn production_constructs_without_touching_the_os() {
        let item = WindowsLoginItem::production();
        assert_eq!(item.task_name, LOGON_TASK_NAME);
    }

    #[test]
    fn with_task_name_uses_the_given_name_not_the_production_constant() {
        let item = WindowsLoginItem::with_task_name("TestOnlyTask");
        assert_eq!(item.task_name, "TestOnlyTask");
        assert_ne!(item.task_name, LOGON_TASK_NAME);
    }
}
