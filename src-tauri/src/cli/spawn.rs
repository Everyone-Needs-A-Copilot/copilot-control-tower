//! `cc doctor --json` invocation (T4).
//!
//! `Command::new(abs_path).arg("doctor").arg("--json")`, resolved exclusively
//! via `cli::path::resolve()` — never a bare `cc`/`copilot`, a fitness
//! function (grep-denied at CI, see
//! `tests/fitness_no_bare_cli_name.rs`). Hard timeout (kill on expiry).
//! Captures stdout (JSON, handed to `model::state::parse_doctor_body` for
//! fail-closed deserialize), stderr (diagnostics — never shown to Bob), and
//! the exit status.
//!
//! Exit-code contract (maps to render state, never to a fabricated verdict):
//! - `0` clean / `1` any-fail => **both** carry a real, parse-worthy body.
//!   The CLI's own worst-wins ladder already decided `status`; this module
//!   does not re-derive anything from the exit code — it just hands the
//!   bytes to `parse_doctor_body`, which re-verifies content regardless of
//!   how "successful" the exit looked (the poisoned-body-on-exit-0
//!   adversarial fixture depends on this: exit 0 is NOT a shortcut to trust).
//! - `2` env-error => do **not** trust the body at all; render
//!   `CliUnreadable` (`exit_2`).
//! - spawn error / timeout / any other exit code => `CliUnreadable`
//!   (`io_error`) — this module never guesses a verdict from an unreadable
//!   process outcome. (non-UTF8 / unparseable JSON / schema out of range /
//!   missing security field are `parse_doctor_body`'s job, not this
//!   module's — see `DoctorRunOutcome::Body`.)

use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[cfg(unix)]
use std::os::unix::process::CommandExt;

use crate::model::state::CliUnreadableReason;

/// Hard timeout for a single `cc doctor --json` invocation — bounded so a
/// hung CLI can never wedge the doctor timer (T5) or a manual refresh. Not a
/// security-sensitive/managed-domain setting (it's a liveness bound, not
/// policy); not currently configurable at all in production, by design —
/// only `doctor_with_timeout` (below) exposes the knob, and only for tests.
const DOCTOR_TIMEOUT: Duration = Duration::from_secs(15);

/// How often the polling loop checks whether the child has exited while
/// waiting out the timeout.
const POLL_INTERVAL: Duration = Duration::from_millis(20);

/// The result of a completed (or abandoned) `cc doctor --json` invocation, at
/// the exit-code-classification granularity only. `Body` makes NO judgment
/// about whether the bytes are trustworthy — that's `parse_doctor_body`'s
/// job (T3); this type only decides whether a body exists to hand it at all.
#[derive(Debug)]
pub enum DoctorRunOutcome {
    /// Exit 0 or 1 — parse-worthy, per the exit-code contract above.
    Body(Vec<u8>),
    /// Exit 2 / spawn failure / timeout / any other exit code — no
    /// trustworthy body exists; the reason IS the render-ready state.
    Unreadable(CliUnreadableReason),
}

/// Runs `<cli_path> doctor --json` with the default hard timeout. The
/// production entry point (called from `cli::run_doctor`); tests use
/// `doctor_with_timeout` to exercise the timeout path without waiting out
/// the full production timeout.
pub fn doctor(cli_path: &Path) -> DoctorRunOutcome {
    doctor_with_timeout(cli_path, DOCTOR_TIMEOUT)
}

/// Same as `doctor`, with an explicit timeout — the seam this module's own
/// tests use to prove the timeout path fails closed quickly rather than
/// waiting `DOCTOR_TIMEOUT`'s full duration.
pub fn doctor_with_timeout(cli_path: &Path, timeout: Duration) -> DoctorRunOutcome {
    let mut command = Command::new(cli_path);
    command
        .arg("doctor")
        .arg("--json")
        // M4/S5 (`.copilot/wp/24.md`): Control Tower is the SINGLE owner of
        // the vendored `cc` (ADR-M4-005) — this env var tells `cc` to
        // disable its own `self-update`, so the two binaries never fight
        // over who updates the CLI. Set on every spawn of `cc` this crate
        // performs (not just `doctor`), never conditionally — there is no
        // scenario where Control Tower spawns a `cc` it does NOT want to be
        // the sole updater of.
        .env("COPILOT_MANAGED_BY", "controltower")
        // Never inherit the parent's stdin — this is a menu-bar app with no
        // interactive terminal; an inherited stdin could otherwise let a
        // misbehaving CLI block waiting on input that will never arrive.
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    {
        // Put the child in its own process GROUP (pgid = the child's own
        // pid) so a timeout kill can reap the whole tree, not just the
        // immediate child. Without this, a CLI that shells out further
        // (e.g. to `sleep`, or any subprocess of its own) leaves an orphan
        // behind that still holds the stdout pipe's write end open —
        // `stdout_reader`'s `read_to_end` would then block until THAT
        // orphan happens to exit on its own, silently defeating the whole
        // point of a hard timeout.
        command.process_group(0);
    }
    let spawned = command.spawn();

    let mut child = match spawned {
        Ok(c) => c,
        // Couldn't even start the process (missing binary, not executable,
        // permission denied, etc.) — an I/O failure, never a fabricated
        // verdict. `cli::path::resolve()` should have already screened most
        // of these out, but a TOCTOU race (binary removed between resolve
        // and spawn) is still possible, so this arm is real, not dead code.
        Err(_) => return DoctorRunOutcome::Unreadable(CliUnreadableReason::IoError),
    };

    // Drain stdout/stderr on their own threads WHILE polling for exit, so a
    // chatty child can never deadlock this call on a full pipe buffer.
    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();
    let stdout_reader = std::thread::spawn(move || read_all(stdout_pipe));
    // stderr is diagnostics only (never shown to Bob, per the module doc) —
    // still drained so the child can't block on a full stderr pipe either.
    let stderr_reader = std::thread::spawn(move || read_all(stderr_pipe));

    let start = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) => {
                if start.elapsed() >= timeout {
                    break None;
                }
                std::thread::sleep(POLL_INTERVAL);
            }
            // `try_wait()` itself failing is as unreadable as a timeout —
            // fail closed rather than looping forever on a broken wait().
            Err(_) => break None,
        }
    };

    let status = match status {
        Some(s) => s,
        None => {
            // Timeout (or a wait() error): kill the WHOLE process group
            // (see the `process_group(0)` note above), reap, and fail
            // closed — never wait indefinitely for a hung CLI or its
            // orphaned descendants. Kill/wait/join errors here are inert
            // (the process may have already exited in the race between the
            // last `try_wait` and now); either way we are already
            // committed to `Unreadable`.
            #[cfg(unix)]
            kill_process_group(child.id());
            #[cfg(not(unix))]
            let _ = child.kill();
            let _ = child.wait();
            let _ = stdout_reader.join();
            let _ = stderr_reader.join();
            return DoctorRunOutcome::Unreadable(CliUnreadableReason::IoError);
        }
    };

    let stdout = stdout_reader.join().unwrap_or_default();
    let _stderr = stderr_reader.join().unwrap_or_default();

    match status.code() {
        // 0 clean / 1 any-checker-fail — see the module doc's exit-code
        // contract: both carry a real body, routed through the SAME path.
        // `parse_doctor_body` re-verifies content regardless of exit code.
        Some(0) | Some(1) => DoctorRunOutcome::Body(stdout),
        // 2: env error — do not trust any body, even if one was printed.
        Some(2) => DoctorRunOutcome::Unreadable(CliUnreadableReason::Exit2),
        // Any other exit code (including `None`, e.g. signal-terminated) —
        // fail closed, never guess.
        _ => DoctorRunOutcome::Unreadable(CliUnreadableReason::IoError),
    }
}

/// Sends `SIGKILL` to the whole process GROUP `pid` leads (negative pid is
/// the POSIX convention for "target the group, not just this one process") —
/// see the `process_group(0)` note at the spawn site for why a plain
/// `child.kill()` (single-process) isn't enough to bound a timeout. No new
/// crate dependency: `kill(2)` is part of libSystem/libc, already linked
/// into every Unix binary.
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

    fn mock_cc() -> std::path::PathBuf {
        std::path::PathBuf::from(format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR")))
    }

    fn corpus_path(name: &str) -> String {
        format!("{}/fixtures/corpus/{name}.json", env!("CARGO_MANIFEST_DIR"))
    }

    fn invalid_path(name: &str) -> String {
        format!(
            "{}/fixtures/invalid/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        )
    }

    fn run(fixture_path: &str) -> DoctorRunOutcome {
        // `CT_FIXTURE` is process-global and `cli::mod`'s tests also set it
        // (via the mock CLI, through `run_doctor`) — lock the SAME
        // `ENV_LOCK` those tests use (see `cli::test_env`) so parallel
        // `cargo test` execution can't interleave two fixtures mid-spawn.
        let _guard = crate::cli::test_env::ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var("CT_FIXTURE", fixture_path) };
        let outcome = doctor(&mock_cc());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var("CT_FIXTURE") };
        outcome
    }

    #[test]
    fn exit_0_healthy_fixture_yields_a_body() {
        match run(&corpus_path("healthy-clean-fleet")) {
            DoctorRunOutcome::Body(bytes) => {
                assert!(!bytes.is_empty());
                assert!(std::str::from_utf8(&bytes).unwrap().contains("\"healthy\""));
            }
            other => panic!("expected Body, got {other:?}"),
        }
    }

    #[test]
    fn exit_1_fail_fixture_still_yields_a_body_not_unreadable() {
        // needs-attention-codex-dept-fail has a `fail` checker, so mock-cc
        // exits 1 — the contract says this still carries a real body.
        match run(&corpus_path("needs-attention-codex-dept-fail")) {
            DoctorRunOutcome::Body(bytes) => {
                assert!(!bytes.is_empty());
                assert!(std::str::from_utf8(&bytes)
                    .unwrap()
                    .contains("\"needs-attention\""));
            }
            other => {
                panic!("expected Body (exit 1 must not be treated as unreadable), got {other:?}")
            }
        }
    }

    #[test]
    fn exit_2_maps_to_unreadable_exit_2() {
        match run("exit-2") {
            DoctorRunOutcome::Unreadable(CliUnreadableReason::Exit2) => {}
            other => panic!("expected Unreadable(Exit2), got {other:?}"),
        }
    }

    #[test]
    fn poisoned_body_on_exit_0_still_yields_a_body_for_t3_to_reject() {
        // checker-missing-severity has no `fail` checker, so mock-cc exits 0
        // even though the body is structurally invalid — proving this module
        // does NOT special-case a clean exit as automatically trustworthy;
        // it hands the body onward exactly like any other exit-0 case.
        match run(&invalid_path("checker-missing-severity")) {
            DoctorRunOutcome::Body(bytes) => assert!(!bytes.is_empty()),
            other => panic!("expected Body (T3 must reject it on content), got {other:?}"),
        }
    }

    #[test]
    fn nonexistent_binary_maps_to_unreadable_io_error() {
        let bogus = std::path::PathBuf::from("/nonexistent/definitely-not-a-real-cc-binary");
        match doctor(&bogus) {
            DoctorRunOutcome::Unreadable(CliUnreadableReason::IoError) => {}
            other => panic!("expected Unreadable(IoError), got {other:?}"),
        }
    }

    #[test]
    fn a_hung_child_times_out_to_unreadable_io_error() {
        // A tiny script that sleeps well past the timeout under test —
        // proves the hard-timeout kill path without waiting out the
        // production `DOCTOR_TIMEOUT`.
        let dir = std::env::temp_dir().join(format!(
            "ct-spawn-timeout-test-{}-{:?}",
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
        let outcome = doctor_with_timeout(&script, Duration::from_millis(200));
        let elapsed = start.elapsed();

        assert!(
            matches!(
                outcome,
                DoctorRunOutcome::Unreadable(CliUnreadableReason::IoError)
            ),
            "expected Unreadable(IoError) on timeout, got {outcome:?}"
        );
        assert!(
            elapsed < Duration::from_secs(2),
            "timeout path took {elapsed:?}, expected it to fail closed near the 200ms bound, \
             not wait out the child's full 5s sleep"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn doctor_spawns_cc_with_copilot_managed_by_controltower_fitness_m4_s5() {
        // ADR-M4-005 (`.copilot/wp/24.md`): Control Tower is the single
        // owner of the vendored `cc` — every spawn of it must disable `cc`'s
        // own `self-update` via this env var, so the two updaters never
        // fight. A tiny script that echoes the env var back as this "doctor"
        // run's JSON body proves it's actually present in the CHILD's
        // environment (not just set on the `Command` and silently dropped),
        // exercising the real spawn path rather than inspecting `Command`
        // internals (which `std::process::Command` doesn't expose anyway).
        let dir = std::env::temp_dir().join(format!(
            "ct-spawn-managed-by-test-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let script = dir.join("env-echoing-cc");
        std::fs::write(
            &script,
            "#!/bin/sh\nprintf '{\"managed_by\": \"%s\"}' \"$COPILOT_MANAGED_BY\"\n",
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&script).unwrap().permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&script, perms).unwrap();
        }

        match doctor(&script) {
            DoctorRunOutcome::Body(bytes) => {
                let body = std::str::from_utf8(&bytes).unwrap();
                assert!(
                    body.contains("\"managed_by\": \"controltower\""),
                    "expected COPILOT_MANAGED_BY=controltower in the spawned child's own \
                     environment, got body: {body:?}"
                );
            }
            other => panic!("expected Body, got {other:?}"),
        }

        let _ = std::fs::remove_dir_all(&dir);
    }
}
