//! M9 Stream-I (task 78) — the WiX uninstall CUSTOM ACTION helper
//! (`main.wxs`'s `RunUninstallCleanup`/`UninstallCleanupBinary`), the
//! Windows analog of the macOS signed uninstaller's
//! `launchctl bootout` + `SMAppService.unregister()` + Keychain-cleanup
//! sequence (`architecture.md` §7, fixes B-H2, `packaging/launchd/
//! uninstall-watchdog.sh`).
//!
//! ## HARD reality (be honest)
//!
//! No Windows toolchain, no `schtasks.exe`, exists on this machine. This
//! file has never been compiled for a Windows target, never run, never
//! wired into a real MSI. It DOES compile as a plain `rustc --edition 2021
//! --crate-type bin` unit on macOS (it only uses `std::process::Command`
//! to shell out — the shelling-out code itself is not Windows-specific,
//! only its runtime effect is), which is this task's own honest
//! verification boundary: a syntax/type-check pass here, nothing more. The
//! REAL verification — does WiX's `Binary`/`CustomAction` embedding
//! actually invoke this compiled `.exe` deferred, with the right working
//! directory, during a genuine `msiexec /x` uninstall — is owner-gated to
//! a real Windows box + WiX toolchain.
//!
//! ## Standalone, not a `src-tauri` crate module — deliberately
//!
//! This file is a **freestanding binary**, not part of the `src-tauri`
//! library crate `platform::windows::*` already implements (Stream-B/C/E's
//! `schtasks.rs`/`watchdog.rs`/`loginitem.rs`) — WiX's `<Binary>` element
//! embeds a compiled EXE by file path, not a Rust library function, so a
//! separate, minimal compiled artifact is how a WiX custom action can ever
//! run arbitrary logic without a scripting-host dependency (VBScript
//! custom actions are deprecated/discouraged; a compiled EXE is WiX's own
//! documented recommendation). Its `schtasks /Delete` calls below
//! DUPLICATE (never CALL) `platform::windows::schtasks::delete_task`'s
//! shape deliberately — this binary cannot depend on the `src-tauri`
//! library crate (different build unit, packaged into the MSI itself
//! rather than the app bundle) — but it is kept intentionally tiny (two
//! idempotent `schtasks /Delete` calls, nothing else) specifically so
//! there is barely anything that COULD drift out of sync with the real
//! task names those modules own. The task name STRING LITERALS below are
//! copy-checked against `platform::windows::watchdog::WATCHDOG_TASK_NAME`
//! and `platform::windows::loginitem::LOGON_TASK_NAME` by
//! `tests/fitness_m9_windows_uninstall_task_names_match.rs` (a macOS-runnable
//! source-scan, run from the `src-tauri` crate's own test suite — see that
//! file for the exact cross-check).
//!
//! ## What this binary REMOVES vs. RETAINS (never-destroy, invariant #3)
//!
//! **Removes** (disposable, app-owned, safe to delete unconditionally):
//! - The crash-only watchdog scheduled task
//!   (`\EveryoneNeedsACopilot\ControlTowerWatchdog`, Stream-C, ADR-M9-002).
//! - The logon-trigger login-item scheduled task
//!   (`EveryoneNeedsACopilot\ControlTowerLogon`, Stream-E, ADR-M5-004's
//!   Windows counterpart).
//! - Both deletions are idempotent (a missing task is treated as success,
//!   matching `platform::windows::schtasks::delete_task`'s own contract) —
//!   safe to re-run, safe if one or both tasks were never registered (e.g.
//!   an install that ran with `LoginItemManaged=false`).
//!
//! **Retains** (never-destroy — this binary must NEVER touch these):
//! - `%LocalAppData%\EveryoneNeedsACopilot\ControlTower\` — the app's own
//!   state directory (heartbeat file, staged-update scratch, logs, and
//!   any future user-authored content). This mirrors the exact macOS
//!   never-destroy rule (`CLAUDE.md` invariant #3): an uninstall removes
//!   the app + its disposable OS-registration state, never a user's own
//!   data. **This binary contains NO recursive-delete call against this
//!   path, deliberately** — WiX's own `RemoveFolder`/component-removal
//!   machinery in `main.wxs` only ever targets the INSTALL directory
//!   (`APPLICATIONFOLDER`, under `%LocalAppData%\Programs\...` — the
//!   binaries), a physically different path from the STATE directory
//!   (`%LocalAppData%\EveryoneNeedsACopilot\ControlTower\`) — the two
//!   never collide, so no extra guard logic is needed here to keep them
//!   apart; there is simply no code path in this file that could delete
//!   the state directory even by accident.
//! - `HKLM\Software\Policies\ENAC\ControlTower` — the IT/MDM-managed
//!   forced-config domain (`windows-parity.md` §1 row 3, ADR-M9-003). This
//!   installer never writes to `HKLM` at all (per-user install,
//!   `main.wxs`'s own `HKCU`-only component keys) and this uninstall
//!   binary never reads OR writes it either — that hive belongs to
//!   whatever GPO/Intune console manages it, never to this app's own
//!   install/uninstall lifecycle, in either direction.
//! - **No Windows Credential Manager entries** — because Control Tower
//!   itself never writes any. This is a real finding, not an oversight:
//!   `platform::windows::secret_store::WindowsSecretStore` (Stream-G,
//!   task 76, already shipped) is, by ratified design, an
//!   ENDPOINT-REFERENCE-ONLY implementation — it reads two forced-domain
//!   registry values and never calls the Windows Credential Manager /
//!   DPAPI API at all (see that module's own doc: "this module never
//!   calls a keychain/Credential-Manager API... resolving a secret VALUE
//!   from the store is the CLI's job, never this app's"). The task
//!   description that seeded this stream ("clears the Credential Manager
//!   entries (Stream-G)") predates that ratified scope narrowing; this
//!   binary does NOT fabricate a Credential Manager cleanup step for
//!   state this app never writes in the first place — doing so would be
//!   new, dead, unverifiable capability with nothing real to clean up. If
//!   a future milestone changes that scope (Control Tower itself gaining
//!   a real secret-storage role), the corresponding uninstall cleanup is
//!   a new, reviewed change to THIS file at that time, not something to
//!   guess at today.
//!
//! ## The other orphan vector — not this binary's job
//!
//! This binary covers the STANDARD uninstall path (`msiexec /x` / Add-or-
//! Remove-Programs), which is the common case. The OTHER named orphan
//! vector — a user deleting the per-user install folder directly (the
//! Windows analog of dragging a macOS `.app` to the Trash) without ever
//! running an uninstall — is `platform::windows::watchdog::is_orphaned`'s
//! job (Stream-C, already shipped): the app self-checks, on a SUBSEQUENT
//! run (e.g. after a reinstall), whether its own scheduled task points at
//! a now-vanished executable, and self-unregisters if so. `windows-
//! parity.md` §1 row 11 already names the residual gap in that path
//! honestly (a task orphaned by manual folder deletion, with no
//! subsequent reinstall/run ever, has no code path to notice) — this
//! binary does not attempt to close that gap; the two mechanisms are
//! complementary, not redundant.

use std::process::Command;

/// Must match `platform::windows::watchdog::WATCHDOG_TASK_NAME` exactly —
/// cross-checked by `tests/fitness_m9_windows_uninstall_task_names_match.rs`.
const WATCHDOG_TASK_NAME: &str = r"\EveryoneNeedsACopilot\ControlTowerWatchdog";

/// Must match `platform::windows::loginitem::LOGON_TASK_NAME` exactly —
/// cross-checked by `tests/fitness_m9_windows_uninstall_task_names_match.rs`.
const LOGON_TASK_NAME: &str = r"EveryoneNeedsACopilot\ControlTowerLogon";

/// Deletes one scheduled task, idempotently — a missing task (`schtasks`
/// exits non-zero with a "cannot find" message) is treated as success,
/// mirroring `platform::windows::schtasks::delete_task`'s own contract
/// exactly (duplicated here, not called — see the module doc's "Standalone"
/// section for why this binary cannot depend on that library crate).
/// Bare `Command::new("schtasks")`, matching the EXISTING precedent
/// `platform::windows::schtasks` itself already established (that module
/// was not sec-flagged for a hijack risk the way `dsregcmd` was in Stream-D's
/// review) — this binary does not invent a stricter discipline that
/// diverges from the shipped module it must stay consistent with.
fn delete_task_idempotent(task_name: &str) {
    let output = Command::new("schtasks")
        .args(["/Delete", "/TN", task_name, "/F"])
        .output();

    match output {
        Ok(o) if o.status.success() => {
            eprintln!("[controltower-uninstall] removed scheduled task: {task_name}");
        }
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            if stderr.to_ascii_lowercase().contains("cannot find") {
                eprintln!(
                    "[controltower-uninstall] scheduled task already absent (no-op): {task_name}"
                );
            } else {
                // Deliberately non-fatal: `main.wxs` wires this custom
                // action with `Return="ignore"` — a scheduled-task
                // deletion failure must never abort or roll back an
                // otherwise-successful MSI uninstall (the app's files
                // being removed is the primary guarantee; a leftover
                // scheduled task pointing at a vanished binary is
                // "orphaned," not "broken install," and is exactly the
                // residual gap this module doc's own "other orphan
                // vector" section already names honestly).
                eprintln!(
                    "[controltower-uninstall] warning: schtasks /Delete failed for {task_name}: {stderr}"
                );
            }
        }
        Err(e) => {
            eprintln!(
                "[controltower-uninstall] warning: failed to spawn schtasks for {task_name}: {e}"
            );
        }
    }
}

fn main() {
    // Order is immaterial — the two tasks are independent, differently-named
    // scheduled tasks (Stream-C's crash-restart task, Stream-E's separate
    // logon-persistence task); neither deletion depends on the other having
    // run first.
    delete_task_idempotent(WATCHDOG_TASK_NAME);
    delete_task_idempotent(LOGON_TASK_NAME);

    // Deliberately does nothing else: no registry cleanup (HKCU component
    // keys are WiX's own job via normal component removal; HKLM policy is
    // never this app's to touch), no Credential Manager cleanup (nothing to
    // clean — see module doc), no deletion of
    // `%LocalAppData%\EveryoneNeedsACopilot\ControlTower\` app state
    // (never-destroy, invariant #3).
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The two task names this binary targets must stay distinct from each
    /// other — a copy-paste bug that pointed both consts at the same string
    /// would silently make one of the two scheduled tasks un-removable by
    /// this uninstall path.
    #[test]
    fn watchdog_and_logon_task_names_are_distinct() {
        assert_ne!(WATCHDOG_TASK_NAME, LOGON_TASK_NAME);
    }

    #[test]
    fn task_names_are_non_empty_and_folder_qualified() {
        // Both real task names live in the `EveryoneNeedsACopilot` Task
        // Scheduler folder — a sanity check that a future edit doesn't
        // silently flatten either name to an unqualified/global task name
        // that could collide with an unrelated task on the same machine.
        assert!(WATCHDOG_TASK_NAME.contains("EveryoneNeedsACopilot"));
        assert!(LOGON_TASK_NAME.contains("EveryoneNeedsACopilot"));
    }
}
