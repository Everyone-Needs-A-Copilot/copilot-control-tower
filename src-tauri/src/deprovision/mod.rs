//! Deprovision orchestration (M5/S2, `.copilot/wp/30.md`) — spawns `cc
//! deprovision <org> --json` and hands the raw body to `render::
//! render_deprovision`. **Parse-not-compute end to end**: this module (and
//! everything under it) contains ZERO wipe/retain/removal logic. The CLI
//! computes AND PERFORMS the entire deprovision before `run_deprovision`
//! ever runs; this crate only asks it what happened and renders the answer
//! honestly. `tests/fitness_m5_no_wipe_logic.rs` (FF-M5-2) source-scans this
//! whole directory for any filesystem-deletion or `git clean|reset|rm|
//! checkout` primitive and asserts none are present — that fitness test IS
//! the invariant, not just documentation of it.
//!
//! ## Route-by-competence (invariant #5) — NOT a Bob-facing entry point
//!
//! `run_deprovision` is the function a future IT/managed-trigger surface
//! (S6 — auth-revoked -> offer, or an IT-routed action) calls. This task
//! builds the DTO + render only; there is deliberately no Tauri `#[command]`
//! wired to it yet, and no "deprovision me" affordance anywhere a
//! non-technical end user could trigger it — deprovisioning an org is an
//! IT/managed/leaver action, never a Bob-initiated one.
//!
//! ## Why this module spawns its own `Command`, not `cli::spawn`
//!
//! `cli::spawn` is scoped to the `doctor` verb by its own module doc (single
//! call site the `.arg("doctor")`-shape fitness test, `tests/
//! fitness_no_bare_cli_name.rs`, protects). `wizard::signin` already
//! established the precedent for a second verb (`auth`): re-apply the SAME
//! spawn policy `cli::spawn::doctor_with_timeout` uses (resolve the CLI via
//! `cli::path::resolve()` — absolute, translocation-safe, never a bare
//! `cc`/`copilot` name; hard per-invocation timeout; process-group kill on
//! expiry; drained stdout/stderr on their own threads so a chatty child
//! can't deadlock the call; nulled stdin) in that verb's own module, rather
//! than widening `cli::spawn`'s scope. `run_deprovision_cli` below mirrors
//! `wizard::signin::run_auth` line-for-line for the same reason.
//!
//! ## NEVER runs against the real CLI in tests
//!
//! `cc deprovision` is MUTATING — it would actually wipe `~/.claude`. Every
//! test in this module (and `render`'s) drives `CT_CLI_PATH` at
//! `fixtures/mock-cc`, which never touches the filesystem beyond printing a
//! canned fixture body (see `fixtures/deprovision/README.md`).

pub mod render;

use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[cfg(unix)]
use std::os::unix::process::CommandExt;

use crate::cli::path;
use crate::model::deprovision::DeprovisionUnreadableReason;
use render::DeprovisionView;

/// Hard per-invocation timeout — same bound `cli::spawn::DOCTOR_TIMEOUT` and
/// `wizard::signin::AUTH_INVOKE_TIMEOUT` use, for the same reason: a hung
/// CLI must never wedge this call.
const DEPROVISION_INVOKE_TIMEOUT: Duration = Duration::from_secs(15);

/// How often the spawn-liveness loop checks whether the child has exited —
/// same value as `cli::spawn::POLL_INTERVAL`/`wizard::signin::
/// INVOKE_LIVENESS_CHECK`, duplicated (not imported) for the same reason
/// those two duplicate it from each other: each verb's spawn policy is
/// self-contained in its own module.
const INVOKE_LIVENESS_CHECK: Duration = Duration::from_millis(20);

/// The single entry point a future trigger surface (S6) calls: resolve the
/// CLI path, spawn `deprovision <org> --json`, and render whatever comes
/// back — trusted or not. Never a fabricated `Wiped`/`Partial`/`Noop`
/// outcome from a spawn failure.
pub fn run_deprovision(org: &str) -> DeprovisionView {
    let cli_path = match path::resolve() {
        Ok(p) => p,
        Err(_) => return render::render_unreadable(DeprovisionUnreadableReason::IoError),
    };
    match run_deprovision_cli(&cli_path, org, DEPROVISION_INVOKE_TIMEOUT) {
        Ok(body) => render::render_deprovision(&body),
        Err(reason) => render::render_unreadable(reason),
    }
}

/// Runs `<cli_path> deprovision <org> --json`, hard-timeout-bounded exactly
/// like `cli::spawn::doctor_with_timeout`/`wizard::signin::run_auth` — see
/// the module doc's "why this module spawns its own Command" section.
/// Returns the raw stdout bytes on a clean (`0`) exit; any spawn failure,
/// non-zero exit, or timeout collapses to
/// `DeprovisionUnreadableReason::IoError` — this contract has no documented
/// per-exit-code semantics the way `doctor`'s `0`/`1`/`2` does (`cli-
/// contract.md`'s `deprovision` row names no exit codes), so every non-clean
/// exit is treated uniformly, never guessed at.
fn run_deprovision_cli(
    cli_path: &Path,
    org: &str,
    timeout: Duration,
) -> Result<Vec<u8>, DeprovisionUnreadableReason> {
    let mut command = Command::new(cli_path);
    command.arg("deprovision").arg(org).arg("--json");
    // M4/S5 (ADR-M4-005): Control Tower is the single owner of the vendored
    // `cc` — set on every spawn of it, deprovision included, so the two
    // binaries never fight over who updates the CLI.
    command.env("COPILOT_MANAGED_BY", "controltower");
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    {
        command.process_group(0);
    }

    let mut child = command
        .spawn()
        .map_err(|_| DeprovisionUnreadableReason::IoError)?;

    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();
    let stdout_reader = std::thread::spawn(move || read_all(stdout_pipe));
    // stderr is diagnostics only (never shown to Bob) — drained so the child
    // can't block on a full stderr pipe either.
    let stderr_reader = std::thread::spawn(move || read_all(stderr_pipe));

    let start = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) => {
                if start.elapsed() >= timeout {
                    break None;
                }
                std::thread::sleep(INVOKE_LIVENESS_CHECK);
            }
            Err(_) => break None,
        }
    };

    let status = match status {
        Some(s) => s,
        None => {
            // Timeout (or a wait() error): kill the whole process group,
            // reap, and fail closed — never wait indefinitely for a hung CLI
            // or its orphaned descendants.
            #[cfg(unix)]
            kill_process_group(child.id());
            #[cfg(not(unix))]
            let _ = child.kill();
            let _ = child.wait();
            let _ = stdout_reader.join();
            let _ = stderr_reader.join();
            return Err(DeprovisionUnreadableReason::IoError);
        }
    };

    let stdout = stdout_reader.join().unwrap_or_default();
    let _stderr = stderr_reader.join().unwrap_or_default();

    match status.code() {
        Some(0) => Ok(stdout),
        // Non-zero (including the mock's exit-2 env-error convention) or
        // signal-terminated (`None`) — fail closed, never guess a result
        // from an unsuccessful exit.
        _ => Err(DeprovisionUnreadableReason::IoError),
    }
}

/// Sends `SIGKILL` to the whole process GROUP `pid` leads — identical to
/// `cli::spawn::kill_process_group`/`wizard::signin::kill_process_group`,
/// duplicated (not imported) because each verb's module owns its own spawn
/// policy per this file's module doc.
#[cfg(unix)]
fn kill_process_group(pid: u32) {
    extern "C" {
        fn kill(pid: i32, sig: i32) -> i32;
    }
    const SIGKILL: i32 = 9;
    // SAFETY: `kill(2)` is a simple, well-defined libc call with no
    // preconditions beyond a valid signal number (satisfied: SIGKILL is a
    // real signal). A negative, nonexistent pgid is a documented no-op
    // (ESRCH), not undefined behavior.
    unsafe {
        kill(-(pid as i32), SIGKILL);
    }
}

fn read_all(pipe: Option<impl Read>) -> Vec<u8> {
    let mut buf = Vec::new();
    if let Some(mut p) = pipe {
        let _ = p.read_to_end(&mut buf);
    }
    buf
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;
    use render::DeprovisionOutcomeView;

    fn mock_cc() -> String {
        format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR"))
    }

    /// Serializes on the SAME process-global lock `cli::path`/`cli::spawn`/
    /// `wizard::signin`'s own tests use — `CT_CLI_PATH`/`CT_FIXTURE` are
    /// process env vars, and `cargo test` runs suites in parallel by
    /// default.
    fn with_fixture<T>(fixture: &str, f: impl FnOnce() -> T) -> T {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, mock_cc());
            std::env::set_var("CT_FIXTURE", fixture);
        }
        let result = f();
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("CT_FIXTURE");
        }
        result
    }

    fn with_cli_path<T>(cli_path: &Path, f: impl FnOnce() -> T) -> T {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(DEV_OVERRIDE_ENV, cli_path) };
        let result = f();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };
        result
    }

    #[test]
    fn wiped_clean_fixture_renders_wiped_end_to_end_through_the_mock_spawn() {
        let view = with_fixture("wiped-clean", || run_deprovision("acme-corp"));
        assert_eq!(view.outcome, DeprovisionOutcomeView::Wiped);
        assert!(!view.secrets_alarm);
    }

    #[test]
    fn partial_fixture_renders_partial_end_to_end() {
        let view = with_fixture("partial", || run_deprovision("acme-corp"));
        assert_eq!(view.outcome, DeprovisionOutcomeView::Partial);
    }

    #[test]
    fn noop_fixture_renders_noop_end_to_end() {
        let view = with_fixture("noop", || run_deprovision("acme-corp"));
        assert_eq!(view.outcome, DeprovisionOutcomeView::Noop);
    }

    /// The adversarial fixture proves the alarm survives the FULL spawn ->
    /// parse -> render pipeline, not just the render unit tests.
    #[test]
    fn secrets_touched_alarm_fixture_renders_the_alarm_end_to_end() {
        let view = with_fixture("secrets-touched-alarm", || run_deprovision("acme-corp"));
        assert!(view.secrets_alarm);
        assert_eq!(view.secrets_touched, 1);
    }

    #[test]
    fn malformed_fixture_renders_unreadable_end_to_end_never_a_fabricated_wipe() {
        let view = with_fixture("malformed", || run_deprovision("acme-corp"));
        assert_eq!(view.outcome, DeprovisionOutcomeView::Unreadable);
    }

    #[test]
    fn exit_2_fixture_renders_unreadable_io_error() {
        let view = with_fixture("exit-2", || run_deprovision("acme-corp"));
        assert_eq!(view.outcome, DeprovisionOutcomeView::Unreadable);
        assert_eq!(
            view.unreadable_reason,
            Some(DeprovisionUnreadableReason::IoError)
        );
    }

    #[test]
    fn missing_cli_path_renders_unreadable_io_error() {
        let view = with_cli_path(
            Path::new("/nonexistent/definitely-not-a-real-cc-binary"),
            || run_deprovision("acme-corp"),
        );
        assert_eq!(view.outcome, DeprovisionOutcomeView::Unreadable);
        assert_eq!(
            view.unreadable_reason,
            Some(DeprovisionUnreadableReason::IoError)
        );
    }

    #[test]
    fn a_hung_cli_times_out_to_unreadable_io_error_never_hangs() {
        let dir = std::env::temp_dir().join(format!(
            "ct-deprovision-timeout-test-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let script = dir.join("hung-cc");
        std::fs::write(&script, "#!/bin/sh\nsleep 5\necho '{}'\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&script).unwrap().permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&script, perms).unwrap();
        }

        let start = Instant::now();
        let result = run_deprovision_cli(&script, "acme-corp", Duration::from_millis(200));
        let elapsed = start.elapsed();

        assert_eq!(result, Err(DeprovisionUnreadableReason::IoError));
        assert!(
            elapsed < Duration::from_secs(2),
            "expected the hard timeout to fire near its 200ms bound, took {elapsed:?}"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Proves the org is actually forwarded as a positional arg (the frozen
    /// `copilot deprovision <org> --json` shape), not silently dropped.
    #[test]
    fn org_argument_is_forwarded_to_the_spawned_process() {
        let dir = std::env::temp_dir().join(format!(
            "ct-deprovision-org-arg-test-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let script = dir.join("echo-args-cc");
        std::fs::write(&script, "#!/bin/sh\nprintf '%s' \"$2\"\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&script).unwrap().permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&script, perms).unwrap();
        }

        // $2 is the org positional (argv: deprovision <org> --json) —
        // deliberately not valid JSON, so this exercises argument-forwarding
        // only; the exit code is still 0 so `run_deprovision_cli` returns
        // `Ok`, letting the test assert on the raw bytes it captured.
        let result = run_deprovision_cli(&script, "acme-corp", DEPROVISION_INVOKE_TIMEOUT);
        assert_eq!(result, Ok(b"acme-corp".to_vec()));

        let _ = std::fs::remove_dir_all(&dir);
    }
}
