//! Shared Task Scheduler helper (M9/Stream-B, task 71) — consumed READ-ONLY
//! by [`super::watchdog`] (Stream-C's crash-restart task, ADR-M9-002) and
//! [`super::loginitem`] (Stream-E's logon-trigger task). Neither of those two
//! streams may edit this file: a single shared helper here is what keeps
//! their two `schtasks /Create` calls from independently reinventing (and
//! silently drifting on) argv-quoting/XML-import conventions — see
//! `windows`'s own module doc for the full ownership table.
//!
//! ## Why shell out to `schtasks.exe`, not the Task Scheduler COM API
//!
//! `schtasks.exe` is a stable, documented, admin-free-for-per-user-tasks CLI
//! shipped with every Windows version this app targets. Shelling out to it
//! (matching this crate's OWN precedent — `cli::spawn` already shells out to
//! an external binary rather than hand-rolling a lower-level API) avoids
//! pulling the COM-based `ITaskService` surface (and its associated
//! `CoInitialize`/apartment-threading concerns) into this crate for a
//! mechanism two streams each only need a handful of verbs from
//! (`/Create`, `/Delete`, `/Query`). Both C and E ship their own XML task
//! definition template (`packaging/taskscheduler/*.xml`) — this module never
//! generates XML itself, it only imports one via `/XML`.
//!
//! ## Owner-gated
//!
//! None of the three functions below have ever been executed — there is no
//! Windows toolchain on this machine (`schtasks.exe` doesn't exist here
//! either). Real verification (does `/Create /XML` actually register a
//! failure-triggered restart, not a periodic-repeat trigger; does `/Delete`
//! cleanly no-op on an already-removed task) is owner-gated to a real
//! Windows box, per ADR-M9-005/006.

#![cfg(windows)]

use std::path::Path;
use std::process::Command;

/// Imports a task definition from an XML file: `schtasks /Create /TN
/// <task_name> /XML <xml_path> /F`. `/F` forces overwrite of an
/// existing task with the same name — this call is idempotent
/// re-registration, safe to run on every app launch/update, matching
/// `loginitem::install`'s "registering an already-registered item is a
/// no-op from the OS's perspective" discipline.
///
/// Callers (Stream-C, Stream-E) own the XML template's CONTENT — this
/// helper never generates or validates task-definition XML itself, it only
/// shells out to import whatever file `xml_path` names.
pub fn create_task_from_xml(task_name: &str, xml_path: &Path) -> Result<(), String> {
    let output = Command::new("schtasks")
        .args(["/Create", "/TN", task_name, "/XML"])
        .arg(xml_path)
        .arg("/F")
        .output()
        .map_err(|e| format!("failed to spawn schtasks /Create for {task_name:?}: {e}"))?;

    if !output.status.success() {
        return Err(format!(
            "schtasks /Create failed for {task_name:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(())
}

/// Removes a scheduled task: `schtasks /Delete /TN <task_name> /F`. A
/// missing task (already removed, or never registered) is treated as
/// success, not an error — mirrors `loginitem::remove`'s "unconditional,
/// idempotent" contract, so the never-orphan self-check (Stream-C) and the
/// uninstall path (Stream-I) can both call this without first checking
/// existence.
pub fn delete_task(task_name: &str) -> Result<(), String> {
    let output = Command::new("schtasks")
        .args(["/Delete", "/TN", task_name, "/F"])
        .output()
        .map_err(|e| format!("failed to spawn schtasks /Delete for {task_name:?}: {e}"))?;

    if output.status.success() {
        return Ok(());
    }

    // schtasks reports a missing task via a non-zero exit + a specific
    // stderr message rather than a distinct exit code — treat "the task
    // does not exist" as success (idempotent delete), anything else as a
    // genuine failure. The exact stderr text is owner-gated to confirm
    // against a real Windows box; this heuristic is Stream-B's best-effort
    // starting point, not a verified contract.
    let stderr = String::from_utf8_lossy(&output.stderr);
    if stderr.to_ascii_lowercase().contains("cannot find") {
        return Ok(());
    }
    Err(format!(
        "schtasks /Delete failed for {task_name:?}: {stderr}"
    ))
}

/// Whether a scheduled task currently exists: `schtasks /Query /TN
/// <task_name>`. This is the enablement PROBE Stream-E's "background-running
/// is off" detection needs (parity B-H3) and Stream-C's never-orphan
/// self-check ("does my own scheduled task still exist") both consume —
/// never an error for "task not found", only for a genuine failure to run
/// `schtasks` at all.
pub fn query_task_exists(task_name: &str) -> Result<bool, String> {
    let output = Command::new("schtasks")
        .args(["/Query", "/TN", task_name])
        .output()
        .map_err(|e| format!("failed to spawn schtasks /Query for {task_name:?}: {e}"))?;
    Ok(output.status.success())
}
