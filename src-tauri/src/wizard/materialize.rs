//! The materialize seam (S4/S5, `.copilot/wp/15.md` §2 S4; ADR-M3-003):
//! spawns `cc update --json` and streams the CLI's own phase NAMES to a
//! caller as they arrive — the wizard's progress display is those names
//! verbatim, never a time estimate (fitness fn 1, `tests/
//! fitness_no_eta_in_wizard.rs`).
//!
//! **Parse-never-compute.** `cc update` is the reconciling materialize verb
//! (WS-A: detect → derive → materialize → prune, never-destroy proven
//! upstream). This module runs it and relays what it says; it performs no
//! clone/sync/merge of its own, and — crucially — **its outcome is never the
//! wizard's verdict.** Whether materialize "worked" is decided by the fresh
//! `doctor status:healthy` parse in the Verify phase that always follows
//! (ADR-M3-002); this module's [`MaterializeOutcome`] only records whether
//! the attempt ran to a clean end, so S8's honesty-on-partial-failure copy
//! can say so — it gates nothing.
//!
//! ## The frozen streaming SHAPE (same D-3-M3/WS-A family as `auth`)
//!
//! The real `cc update --json`'s progress stream isn't frozen upstream yet.
//! This module freezes the SHAPE it needs — NDJSON, one object per stdout
//! line:
//!
//! - `{"phase": "<name>"}` — a named phase began (e.g. "Setting up Claude…");
//!   relayed to the caller verbatim.
//! - `{"done": true}` — the reconcile ran to its clean end.
//!
//! Unknown lines are ignored (a richer real verb may interleave detail this
//! version doesn't render); a missing `done` marker, a non-zero exit, or a
//! hard timeout all yield [`MaterializeOutcome::DidNotComplete`] — honestly
//! recorded, then handed to Verify, which holds on anything the doctor
//! doesn't call Healthy. `mock-cc update` (S9) mirrors this shape; the real
//! verb's freeze is batched into WS-A alongside the other D-3-M3 items.
//!
//! ## Spawn policy
//!
//! Same policy as `cli::spawn::doctor_with_timeout` / `signin::run_auth`
//! (this task's file-ownership map gives the wizard's Stream-A its own verb
//! seams): resolved via `cli::path::resolve()` — never a bare name — nulled
//! stdin, child in its own process group, killed as a group on timeout. The
//! timeout is minutes, not seconds: a first materialize legitimately clones
//! repos. Stdout is read line-by-line on a reader thread so phase names
//! reach the caller live, not after exit.

use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[cfg(unix)]
use std::os::unix::process::CommandExt;

use serde::Deserialize;

/// Hard ceiling on one `cc update --json` run. A first-run materialize
/// clones mirrors, so this is deliberately generous — the bound exists so a
/// hung engine can never wedge the wizard forever, not to police normal
/// duration. (Never surfaced to the user as an estimate — ADR-M3-003.)
const UPDATE_TIMEOUT: Duration = Duration::from_secs(600);

/// How one materialize ATTEMPT ended. Not a verdict (see module doc): both
/// variants route to Verify; `DidNotComplete` only lets S8 say honestly that
/// the attempt itself didn't run clean.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MaterializeOutcome {
    /// Exit 0 and the stream's `{"done": true}` marker both arrived.
    Completed,
    /// Non-zero exit, a missing `done` marker, or a hard-timeout kill.
    DidNotComplete,
}

/// The engine couldn't be run at all (path resolution or spawn failure) —
/// the caller proceeds to Verify, whose own unreadable-doctor path holds
/// with the honest M1 "couldn't start the engine" copy. Fieldless: no raw
/// error string travels (same discipline as `signin::SigninError`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MaterializeUnavailable;

/// One NDJSON stream line. Both fields optional — a line is whatever subset
/// it is; unknown fields are ignored by serde's default, so a richer future
/// verb can't break this parser (and nothing it says beyond these two keys
/// is ever captured).
#[derive(Debug, Deserialize)]
struct StreamLine {
    phase: Option<String>,
    done: Option<bool>,
}

/// Runs `cc update --json`, calling `on_phase` with each CLI-supplied phase
/// name as it arrives (S6 forwards these as `wizard-phase` events). Blocks
/// until the run ends one way or another — callers own their threading.
pub fn run_materialize(
    mut on_phase: impl FnMut(String),
) -> Result<MaterializeOutcome, MaterializeUnavailable> {
    let cli_path = crate::cli::path::resolve().map_err(|_| MaterializeUnavailable)?;
    run_materialize_with(&cli_path, UPDATE_TIMEOUT, &mut on_phase)
}

/// Same as [`run_materialize`] with explicit path + timeout — the seam this
/// module's own tests use to exercise the timeout path quickly.
fn run_materialize_with(
    cli_path: &Path,
    timeout: Duration,
    on_phase: &mut dyn FnMut(String),
) -> Result<MaterializeOutcome, MaterializeUnavailable> {
    let mut command = Command::new(cli_path);
    command
        .arg("update")
        .arg("--json")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    {
        // Own process group, so a timeout kill reaps the whole tree — same
        // rationale as `cli::spawn`'s identical call.
        command.process_group(0);
    }

    let mut child = command.spawn().map_err(|_| MaterializeUnavailable)?;

    // Stream stdout lines to the caller as they arrive via a channel — the
    // reader thread owns the pipe; this thread owns the deadline.
    let stdout_pipe = child.stdout.take();
    let (line_tx, line_rx) = mpsc::channel::<String>();
    let stdout_reader = std::thread::spawn(move || {
        if let Some(pipe) = stdout_pipe {
            for line in BufReader::new(pipe).lines() {
                match line {
                    Ok(l) => {
                        if line_tx.send(l).is_err() {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
        }
    });
    // stderr is diagnostics only (never shown to Bob) — drained so the child
    // can't block on a full stderr pipe.
    let stderr_pipe = child.stderr.take();
    let stderr_reader = std::thread::spawn(move || {
        if let Some(pipe) = stderr_pipe {
            for _ in BufReader::new(pipe).lines() {}
        }
    });

    let deadline = Instant::now() + timeout;
    let mut saw_done = false;
    let mut timed_out = false;

    // Drain the line channel until the reader thread hangs up (child stdout
    // closed) or the deadline passes. `recv_timeout` keeps the deadline
    // honest even when the child goes silent mid-run.
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            timed_out = true;
            break;
        }
        match line_rx.recv_timeout(remaining) {
            Ok(line) => {
                if let Ok(parsed) = serde_json::from_str::<StreamLine>(&line) {
                    if let Some(name) = parsed.phase.filter(|p| !p.is_empty()) {
                        on_phase(name);
                    }
                    if parsed.done == Some(true) {
                        saw_done = true;
                    }
                }
                // Unparseable lines are ignored — see the module doc's
                // "unknown lines" rule.
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                timed_out = true;
                break;
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }

    if timed_out {
        // Kill the whole group, reap, and record an honest DidNotComplete —
        // Verify still runs afterwards and decides everything that matters.
        #[cfg(unix)]
        kill_process_group(child.id());
        #[cfg(not(unix))]
        let _ = child.kill();
        let _ = child.wait();
        let _ = stdout_reader.join();
        let _ = stderr_reader.join();
        return Ok(MaterializeOutcome::DidNotComplete);
    }

    let status = child.wait();
    let _ = stdout_reader.join();
    let _ = stderr_reader.join();

    let clean_exit = matches!(status, Ok(s) if s.code() == Some(0));
    Ok(if clean_exit && saw_done {
        MaterializeOutcome::Completed
    } else {
        MaterializeOutcome::DidNotComplete
    })
}

/// Identical to `cli::spawn::kill_process_group` / `signin::
/// kill_process_group` (both private to their own modules; each verb seam
/// owns its spawn policy — see `signin.rs`'s module doc for the shared
/// rationale).
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write as _;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir() -> PathBuf {
        let n = DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ct-wizard-materialize-test-{}-{:?}-{n}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp test dir");
        dir
    }

    /// A stand-in `cc update` written from a body of shell lines — local to
    /// these tests (the shared `fixtures/mock-cc` gains its real `update`
    /// verb in S9; these tests pin the parser/timeout behavior underneath
    /// it). No env-var seam needed: `run_materialize_with` takes the path
    /// directly, same as `cli::spawn`'s own timeout test.
    fn write_script(dir: &Path, body: &str) -> PathBuf {
        let script = dir.join("mock-cc-update");
        let mut f = std::fs::File::create(&script).unwrap();
        writeln!(f, "#!/bin/sh").unwrap();
        writeln!(f, "{body}").unwrap();
        drop(f);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&script).unwrap().permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&script, perms).unwrap();
        }
        script
    }

    fn run(
        body: &str,
        timeout: Duration,
    ) -> (
        Result<MaterializeOutcome, MaterializeUnavailable>,
        Vec<String>,
    ) {
        let dir = temp_dir();
        let script = write_script(&dir, body);
        let mut phases = Vec::new();
        let outcome = run_materialize_with(&script, timeout, &mut |p| phases.push(p));
        let _ = std::fs::remove_dir_all(&dir);
        (outcome, phases)
    }

    #[test]
    fn phase_names_stream_through_verbatim_and_a_clean_end_completes() {
        let (outcome, phases) = run(
            r#"echo '{"phase": "Setting up Claude…"}'
echo '{"phase": "Setting up Codex…"}'
echo '{"done": true}'
exit 0"#,
            Duration::from_secs(10),
        );
        assert_eq!(outcome, Ok(MaterializeOutcome::Completed));
        assert_eq!(
            phases,
            vec![
                "Setting up Claude…".to_string(),
                "Setting up Codex…".to_string()
            ]
        );
    }

    #[test]
    fn a_nonzero_exit_is_did_not_complete_even_with_a_done_marker() {
        let (outcome, _) = run(
            r#"echo '{"done": true}'
exit 1"#,
            Duration::from_secs(10),
        );
        assert_eq!(outcome, Ok(MaterializeOutcome::DidNotComplete));
    }

    #[test]
    fn a_missing_done_marker_is_did_not_complete_even_on_exit_0() {
        let (outcome, phases) = run(
            r#"echo '{"phase": "Setting up Claude…"}'
exit 0"#,
            Duration::from_secs(10),
        );
        assert_eq!(outcome, Ok(MaterializeOutcome::DidNotComplete));
        assert_eq!(phases, vec!["Setting up Claude…".to_string()]);
    }

    #[test]
    fn junk_lines_are_ignored_not_fatal() {
        let (outcome, phases) = run(
            r#"echo 'not json at all'
echo '{"unknown_key": 1}'
echo '{"phase": ""}'
echo '{"phase": "Real phase"}'
echo '{"done": true}'
exit 0"#,
            Duration::from_secs(10),
        );
        assert_eq!(outcome, Ok(MaterializeOutcome::Completed));
        assert_eq!(
            phases,
            vec!["Real phase".to_string()],
            "junk, unknown keys, and empty names must all be dropped silently"
        );
    }

    #[test]
    fn a_hung_update_times_out_to_did_not_complete_with_phases_already_streamed() {
        // A 200ms bound previously used here was flaky under CI/parallel-CPU
        // contention — spawning the child, flushing its first `echo` through
        // the pipe, and having the reader thread deliver it over the channel
        // can occasionally take longer than 200ms even though the timeout
        // logic itself was firing correctly (a false failure, same disease
        // as `signin.rs`'s hardened flaky test, `.copilot/wp/15.md` S8).
        // 1.5s gives that one-time subprocess/pipe setup generous real-world
        // slack while still asserting the timeout fires well before the
        // child's 5s sleep — never near-instant, but never anywhere close to
        // waiting the sleep out either.
        let start = Instant::now();
        let (outcome, phases) = run(
            r#"echo '{"phase": "Setting up Claude…"}'
sleep 5
echo '{"done": true}'"#,
            Duration::from_millis(1500),
        );
        assert_eq!(outcome, Ok(MaterializeOutcome::DidNotComplete));
        assert_eq!(
            phases,
            vec!["Setting up Claude…".to_string()],
            "phases must have streamed LIVE, before the hang"
        );
        assert!(
            start.elapsed() < Duration::from_secs(4),
            "timeout must fail closed near the 1.5s bound, not wait out the child's 5s sleep"
        );
    }

    #[test]
    fn a_nonexistent_binary_is_honest_unavailability() {
        let mut phases = Vec::new();
        let outcome = run_materialize_with(
            Path::new("/nonexistent/definitely-not-a-real-cc-binary"),
            Duration::from_secs(1),
            &mut |p| phases.push(p),
        );
        assert_eq!(outcome, Err(MaterializeUnavailable));
        assert!(phases.is_empty());
    }
}
