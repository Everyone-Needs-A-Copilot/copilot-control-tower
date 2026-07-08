//! Sign-in device-flow seam (S3, `.copilot/wp/15.md` §2 S3; invariant #6;
//! ADR-M3-001; sec-owned — this is the credential boundary).
//!
//! **App holds NO secret.** `begin_signin()` initiates the RFC-8628-shaped
//! device flow (`cc auth --json`) and `poll_signin()` polls it to a terminal
//! state (`cc auth --json --poll`), both spawned through the M1/M2 CLI seam
//! (`cli::path::resolve()` — absolute, translocation-safe, never a bare
//! name). Neither function, nor any type in this file, ever holds a token,
//! access key, or credential: the CLI performs the OAuth exchange and writes
//! the OS keychain itself (`docs/05-security/credentials-and-boundary.md`
//! §1.4/§3); this module only ever surfaces `user_code` / `verification_uri`
//! / the terminal `status` — the exact three fields `dto::SigninState`
//! already freezes (S1) and `tests/fitness_no_secret_on_wizard_dto.rs`
//! already guards. `tests/fitness_signin_seam_holds_no_secret.rs` extends
//! that guard to this file's own intermediate parsing types.
//!
//! **No screen-scrape (Case Law OUT).** This module never shells out to `gh
//! auth status` or parses any human-oriented CLI prose — the one and only
//! seam is the machine-readable `cc auth --json`/`--poll` contract (mirrored
//! today by `fixtures/mock-cc auth`, per D-3-M3 / ADR-M3-001; the real verb
//! is batched to WS-A).
//!
//! **Fail closed, always.** An ambiguous, malformed, empty, or unparseable
//! seam response — or a poll that outlives the ceremony's own `expires_in` —
//! never becomes `Authorized`. It becomes either a plain-language
//! `SigninError` (the CLI couldn't be reached, or its body wasn't the frozen
//! SHAPE) or an honest, non-authorized terminal `SigninState` (`Timeout` on
//! a bounded-poll expiry). There is no "skip verification and proceed as
//! authorized" path anywhere in this file (invariant #4).
//!
//! ## Why this file spawns its own `Command`, not `cli::spawn`
//!
//! `cli::spawn` is scoped to the `doctor` verb by its own module doc, and
//! this task's file-ownership map (`.copilot/wp/15.md` §1) makes S3
//! (sec-owned, this file) responsible for the sign-in seam end-to-end — the
//! same policy `cli::spawn::doctor` already applies (resolve via
//! `cli::path::resolve()`, absolute path only, never a bare `cc`/`copilot`
//! name; hard per-invocation timeout; process-group kill on expiry; drained
//! stdout/stderr on their own threads; nulled stdin) is re-applied here to
//! the `auth` verb, not a second, competing spawn policy. `run_auth` below is
//! deliberately structured to mirror `cli::spawn::doctor_with_timeout`
//! line-for-line for that reason.

use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[cfg(unix)]
use std::os::unix::process::CommandExt;

use serde::Deserialize;

use crate::cli::path;
use crate::wizard::dto::{SigninState, SigninStatus};

/// Hard per-invocation timeout for a single `cc auth --json[--poll]` spawn —
/// mirrors `cli::spawn::DOCTOR_TIMEOUT`'s bound for the same reason: a hung
/// CLI must never wedge the wizard's sign-in step.
const AUTH_INVOKE_TIMEOUT: Duration = Duration::from_secs(15);

/// How often the spawn-liveness loop checks whether the child has exited
/// while waiting out `AUTH_INVOKE_TIMEOUT` — same value as
/// `cli::spawn::POLL_INTERVAL`, duplicated rather than imported (that
/// constant is private to `cli::spawn`, and this module owns its own spawn
/// policy per the module doc above).
const INVOKE_LIVENESS_CHECK: Duration = Duration::from_millis(20);

/// A hard ceiling on the number of poll round-trips `poll_signin` will ever
/// make, independent of the ceremony's advertised `interval`/`expires_in`.
/// Belt-and-suspenders against a degenerate or adversarial ceremony (e.g. an
/// `interval` of `0`) wedging this call in a tight spin — the real bound is
/// the wall-clock deadline computed from `expires_in`; this only guarantees
/// termination even if that arithmetic were ever wrong.
const MAX_POLL_ROUNDTRIPS: u32 = 10_000;

/// Plain-language, secret-free error from the sign-in seam (Git-Error-To-A-
/// Non-Technical-Person discipline applied to auth, matching the doctor
/// seam's `CliUnreadable` copy). Both variants are fieldless — neither can
/// ever be constructed with a raw process/JSON error string, a status code,
/// or any dynamic content, so there is no field for a secret to hide in
/// (confirmed structurally, not just by naming convention, in
/// `tests/fitness_signin_seam_holds_no_secret.rs`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SigninError {
    /// The CLI could not be found, spawned, or exited abnormally (path
    /// resolution failure, spawn failure, a hard-timeout kill, or an exit
    /// code other than `0`) — the same "I couldn't start the engine" fact
    /// `cli::run_doctor` already reports for the doctor seam.
    CliUnavailable,
    /// The CLI ran and exited cleanly, but its body was not the frozen
    /// ceremony/poll SHAPE (unparseable JSON, a missing/empty required
    /// field, or a `status` value outside the frozen terminal vocabulary).
    /// Fails closed rather than guessing — never treated as `Authorized`.
    MalformedResponse,
}

impl std::fmt::Display for SigninError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SigninError::CliUnavailable => write!(
                f,
                "I couldn't start the sign-in step. Click to try again — it's a fix, not a reset."
            ),
            SigninError::MalformedResponse => write!(
                f,
                "Sign-in didn't respond the way I expected, so I stopped rather than guessing. \
                 Please try again."
            ),
        }
    }
}

/// The ceremony plus the polling bounds `begin_signin` learned from the CLI.
/// Deliberately **not** `dto::SigninState` and deliberately **not**
/// `Serialize`/`Deserialize` — `interval_secs`/`expires_in_secs` are
/// polling-bookkeeping this module needs to drive `poll_signin`'s bounded
/// loop; they are not render data, carry no ETA to the user (S1's `dto`
/// module owns the one place a phase becomes display text, and it never
/// does so from these fields), and must never cross the wizard IPC DTO seam
/// (that seam is `dto::SigninState` alone). A caller (S4/S5, later) holds
/// this in memory only for the lifetime of one sign-in attempt, between its
/// `begin_signin` and `poll_signin` calls.
#[derive(Debug, Clone, PartialEq)]
pub struct SigninSession {
    /// The render-safe state the caller hands straight to the wire —
    /// `status: Pending`, plus `user_code`/`verification_uri`. Never a
    /// token; there is no field here to carry one.
    pub state: SigninState,
    interval_secs: u64,
    expires_in_secs: u64,
}

impl SigninSession {
    /// The ceremony's own poll cadence, in seconds — the honest number S8
    /// surfaces to the wizard UI so it polls `wizard_poll_signin` at the
    /// CLI-specified interval instead of a client-side guess. Read-only:
    /// this is polling bookkeeping, never rendered as an ETA/countdown (see
    /// this file's own module doc + `dto.rs`'s `signin_interval_secs` doc).
    pub fn interval_secs(&self) -> u64 {
        self.interval_secs
    }

    /// The ceremony's own expiry, in seconds — exposed alongside
    /// `interval_secs` for a caller that wants it (S8's task brief: "and
    /// expiry if useful"); unused by the current wizard UI, which relies on
    /// the CLI's own terminal `timeout` status rather than a client-side
    /// expiry countdown.
    pub fn expires_in_secs(&self) -> u64 {
        self.expires_in_secs
    }
}

/// The wire shape of the initiate (ceremony) response. Every field is
/// `Option` so a missing key is a normal, representable "absent", not a
/// serde hard-parse-failure that would obscure *which* field was missing —
/// `parse_ceremony` below is the one place that turns "absent/empty" into
/// the fail-closed `MalformedResponse` error. No secret-shaped field exists
/// here by construction — the frozen SHAPE has none (see the module doc's
/// `docs/05-security/credentials-and-boundary.md` citation).
#[derive(Debug, Deserialize)]
struct CeremonyWire {
    user_code: Option<String>,
    verification_uri: Option<String>,
    expires_in: Option<u64>,
    interval: Option<u64>,
}

/// The wire shape of a poll response. Deliberately reads ONLY `status` —
/// even if the CLI (or an adversarial/malfunctioning stand-in) emits extra
/// fields alongside it, `serde`'s default "ignore unknown fields" behavior
/// means anything else in the body is never captured into any Rust value
/// this module holds, let alone forwarded into the DTO. This is the parse-
/// time half of the no-secret-crosses-the-seam guarantee; see
/// `tests/fitness_signin_seam_holds_no_secret.rs` for the adversarial-fixture
/// proof.
#[derive(Debug, Deserialize)]
struct PollWire {
    status: Option<String>,
}

/// Runs `<cli_path> auth --json` (initiate) or `<cli_path> auth --json
/// --poll` (poll), hard-timeout-bounded exactly like
/// `cli::spawn::doctor_with_timeout` — nulled stdin (this is a menu-bar app
/// with no interactive terminal), piped stdout/stderr drained on their own
/// threads (so a chatty child can never deadlock this call on a full pipe
/// buffer), the child placed in its own process group so a timeout kill
/// reaps the whole tree, not just the immediate child. Returns the raw
/// stdout bytes on a clean (`0`) exit; any spawn failure, non-zero exit, or
/// timeout is collapsed to `SigninError::CliUnavailable` — this function
/// makes no attempt to distinguish those cases further, matching
/// `cli::spawn::doctor`'s "an I/O failure, never a fabricated verdict"
/// discipline.
fn run_auth(cli_path: &Path, poll: bool) -> Result<Vec<u8>, SigninError> {
    let mut command = Command::new(cli_path);
    command.arg("auth").arg("--json");
    if poll {
        command.arg("--poll");
    }
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    {
        command.process_group(0);
    }

    let mut child = command.spawn().map_err(|_| SigninError::CliUnavailable)?;

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
                if start.elapsed() >= AUTH_INVOKE_TIMEOUT {
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
            // reap, and fail closed — never wait indefinitely for a hung
            // CLI or its orphaned descendants.
            #[cfg(unix)]
            kill_process_group(child.id());
            #[cfg(not(unix))]
            let _ = child.kill();
            let _ = child.wait();
            let _ = stdout_reader.join();
            let _ = stderr_reader.join();
            return Err(SigninError::CliUnavailable);
        }
    };

    let stdout = stdout_reader.join().unwrap_or_default();
    let _stderr = stderr_reader.join().unwrap_or_default();

    match status.code() {
        Some(0) => Ok(stdout),
        // Non-zero (including the `auth` verb's own exit-2 env-error
        // convention) or signal-terminated (`None`) — fail closed, never
        // guess a status from an unsuccessful exit.
        _ => Err(SigninError::CliUnavailable),
    }
}

/// Sends `SIGKILL` to the whole process GROUP `pid` leads — identical to
/// `cli::spawn::kill_process_group`, duplicated (not imported) because that
/// function is private to `cli::spawn` and this module owns its own spawn
/// policy per the module doc above.
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

/// Parses the initiate response into `(user_code, verification_uri,
/// expires_in, interval)`, failing closed unless all four fields are
/// present, both strings are non-empty, and both numbers are strictly
/// positive (a `0`-second `expires_in`/`interval` is exactly as unusable as
/// a missing one, and must not be allowed to silently become an
/// instant-timeout or a tight-spin poll loop).
fn parse_ceremony(bytes: &[u8]) -> Result<(String, String, u64, u64), SigninError> {
    let wire: CeremonyWire =
        serde_json::from_slice(bytes).map_err(|_| SigninError::MalformedResponse)?;
    let user_code = wire
        .user_code
        .filter(|s| !s.is_empty())
        .ok_or(SigninError::MalformedResponse)?;
    let verification_uri = wire
        .verification_uri
        .filter(|s| !s.is_empty())
        .ok_or(SigninError::MalformedResponse)?;
    let expires_in = wire
        .expires_in
        .filter(|n| *n > 0)
        .ok_or(SigninError::MalformedResponse)?;
    let interval = wire
        .interval
        .filter(|n| *n > 0)
        .ok_or(SigninError::MalformedResponse)?;
    Ok((user_code, verification_uri, expires_in, interval))
}

/// Parses a single poll response into the frozen terminal-state vocabulary.
/// `"pending"` is the one non-terminal value; every other name outside the
/// frozen set (including no `status` field at all, or one that fails to
/// deserialize as a string) is treated exactly like unparseable JSON — an
/// honest refusal to guess, never a fabricated `Authorized`.
fn parse_poll_status(bytes: &[u8]) -> Result<SigninStatus, SigninError> {
    let wire: PollWire =
        serde_json::from_slice(bytes).map_err(|_| SigninError::MalformedResponse)?;
    match wire.status.as_deref() {
        Some("pending") => Ok(SigninStatus::Pending),
        Some("authorized") => Ok(SigninStatus::Authorized),
        Some("denied") => Ok(SigninStatus::Denied),
        Some("expired") => Ok(SigninStatus::Expired),
        Some("timeout") => Ok(SigninStatus::Timeout),
        _ => Err(SigninError::MalformedResponse),
    }
}

/// A terminal `SigninState` — `user_code`/`verification_uri` are cleared
/// (the ceremony is over; there is nothing left for the UI to show or copy),
/// leaving only the one field that matters once the flow has ended: the
/// status itself.
fn terminal(status: SigninStatus) -> SigninState {
    SigninState {
        status,
        user_code: None,
        verification_uri: None,
    }
}

/// Initiate the device flow: spawns `cc auth --json`, resolved via
/// `cli::path::resolve()` (never a bare name — fitness fn 3, reused from
/// M1/M2). On success, returns a `SigninSession` bundling the render-safe
/// `SigninState{status: Pending, user_code, verification_uri}` a caller
/// (S6's IPC command) hands straight to the wire, plus the polling bounds
/// `poll_signin` needs to stay within the ceremony's own `expires_in`/
/// `interval` — never a token; the ceremony's frozen SHAPE has no such field
/// to carry (invariant #6).
pub fn begin_signin() -> Result<SigninSession, SigninError> {
    let cli_path = path::resolve().map_err(|_| SigninError::CliUnavailable)?;
    let body = run_auth(&cli_path, false)?;
    let (user_code, verification_uri, expires_in, interval) = parse_ceremony(&body)?;
    Ok(SigninSession {
        state: SigninState {
            status: SigninStatus::Pending,
            user_code: Some(user_code),
            verification_uri: Some(verification_uri),
        },
        interval_secs: interval,
        expires_in_secs: expires_in,
    })
}

/// Poll to terminal: repeatedly spawns `cc auth --json --poll` at the
/// ceremony's own `interval`, bounded by its own `expires_in`. A poll that
/// never reaches a terminal state within that window returns
/// `SigninState{status: Timeout}` — fail closed, never hangs indefinitely,
/// and never returns `Authorized` on anything but a CLI-reported
/// `"authorized"`. Takes `session` by reference (not by value) so a caller
/// that gets back a transient `Err` (a single dropped/garbled poll) can
/// retry against the SAME session without re-running `begin_signin` — the
/// `user_code` shown to the user stays valid across such a retry.
pub fn poll_signin(session: &SigninSession) -> Result<SigninState, SigninError> {
    let cli_path = path::resolve().map_err(|_| SigninError::CliUnavailable)?;
    poll_until_terminal(
        session,
        || {
            let body = run_auth(&cli_path, true)?;
            parse_poll_status(&body)
        },
        Instant::now,
        std::thread::sleep,
    )
}

/// The bounded-poll core, parametrized over how a single round-trip is
/// performed (`poll_once`) and how time is read/advanced (`now`/`sleep`).
/// [`poll_signin`] wires this to the real CLI spawn and the real wall
/// clock; `tests::a_poll_that_exceeds_expires_in_times_out_never_hangs_
/// never_authorized` wires it to a fake always-pending round and a virtual
/// clock instead, so the deadline arithmetic itself — never hang, never
/// return `Authorized`, always terminate once `expires_in` has passed — is
/// proven deterministically, independent of real subprocess-spawn latency
/// or wall-clock scheduling jitter under CI/parallel-CPU contention (the
/// prior version of that test drove this same logic through a real
/// `Instant::now()`/`thread::sleep`/subprocess spawn and asserted a fixed
/// wall-clock elapsed bound, which could occasionally overrun under load).
fn poll_until_terminal(
    session: &SigninSession,
    mut poll_once: impl FnMut() -> Result<SigninStatus, SigninError>,
    mut now: impl FnMut() -> Instant,
    mut sleep: impl FnMut(Duration),
) -> Result<SigninState, SigninError> {
    let deadline = now() + Duration::from_secs(session.expires_in_secs);
    let interval = Duration::from_secs(session.interval_secs);
    let mut round_trips: u32 = 0;

    loop {
        if now() >= deadline || round_trips >= MAX_POLL_ROUNDTRIPS {
            // Bounded-poll expiry: an honest, non-authorized terminal
            // status, never a hang and never a guess at success.
            return Ok(terminal(SigninStatus::Timeout));
        }
        round_trips += 1;

        let status = poll_once()?;

        match status {
            SigninStatus::Pending => {
                let remaining = deadline.saturating_duration_since(now());
                // Never sleep past the deadline, and never sleep for
                // literally zero (a `0` interval would otherwise spin this
                // loop as fast as the CLI can be spawned) — floor at 1ms.
                let sleep_for = interval.min(remaining).max(Duration::from_millis(1));
                sleep(sleep_for);
            }
            terminal_status => return Ok(terminal(terminal_status)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;

    fn mock_cc() -> String {
        format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR"))
    }

    /// Serializes on the SAME process-global lock `cli::path`/`cli::spawn`/
    /// `cli::mod`'s own tests use — `CT_CLI_PATH`/`CT_AUTH_SCENARIO` are
    /// process env vars, and `cargo test` runs suites in parallel by
    /// default, so every test anywhere in this crate that touches either
    /// var must serialize on one shared mutex, not a lock local to this
    /// module.
    fn with_scenario<T>(scenario: &str, f: impl FnOnce() -> T) -> T {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, mock_cc());
            std::env::set_var("CT_AUTH_SCENARIO", scenario);
        }
        let result = f();
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("CT_AUTH_SCENARIO");
        }
        result
    }

    /// Points `CT_CLI_PATH` at an arbitrary script (used for the
    /// malformed-response and hung-CLI cases mock-cc has no scenario for),
    /// under the same shared lock.
    fn with_cli_path<T>(cli_path: &Path, f: impl FnOnce() -> T) -> T {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(DEV_OVERRIDE_ENV, cli_path) };
        let result = f();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };
        result
    }

    // ---- begin_signin (initiate) ------------------------------------

    #[test]
    fn begin_signin_returns_pending_with_user_code_and_verification_uri_never_a_token() {
        let session = with_scenario("authorized", begin_signin).expect("initiate should succeed");
        assert_eq!(session.state.status, SigninStatus::Pending);
        assert_eq!(session.state.user_code.as_deref(), Some("WDJB-MJHT"));
        assert_eq!(
            session.state.verification_uri.as_deref(),
            Some("https://example.com/device")
        );
        assert_eq!(session.interval_secs, 5);
        assert_eq!(session.expires_in_secs, 900);

        // Structural guarantee, not just a value check: format the whole
        // session and confirm no token-shaped substring is even possible to
        // see — `SigninSession`/`SigninState` simply have no field to carry
        // one (see tests/fitness_signin_seam_holds_no_secret.rs for the AST
        // version of this same claim).
        let debug = format!("{session:?}");
        for needle in ["token", "secret", "credential", "access_key"] {
            assert!(
                !debug.to_lowercase().contains(needle),
                "SigninSession Debug output unexpectedly contained {needle:?}: {debug}"
            );
        }
    }

    #[test]
    fn begin_signin_fails_closed_on_env_error_exit_2() {
        let result = with_scenario("exit-2", begin_signin);
        assert_eq!(result, Err(SigninError::CliUnavailable));
    }

    // ---- poll_signin — each frozen terminal scenario ------------------

    fn fresh_session() -> SigninSession {
        SigninSession {
            state: SigninState {
                status: SigninStatus::Pending,
                user_code: Some("WDJB-MJHT".to_string()),
                verification_uri: Some("https://example.com/device".to_string()),
            },
            interval_secs: 5,
            expires_in_secs: 900,
        }
    }

    #[test]
    fn poll_signin_maps_authorized() {
        let session = fresh_session();
        let result = with_scenario("authorized", || poll_signin(&session));
        assert_eq!(
            result,
            Ok(SigninState {
                status: SigninStatus::Authorized,
                user_code: None,
                verification_uri: None,
            })
        );
    }

    #[test]
    fn poll_signin_maps_denied() {
        let session = fresh_session();
        let result = with_scenario("denied", || poll_signin(&session));
        assert_eq!(result.map(|s| s.status), Ok(SigninStatus::Denied));
    }

    #[test]
    fn poll_signin_maps_expired() {
        let session = fresh_session();
        let result = with_scenario("expired", || poll_signin(&session));
        assert_eq!(result.map(|s| s.status), Ok(SigninStatus::Expired));
    }

    #[test]
    fn poll_signin_maps_cli_reported_timeout() {
        let session = fresh_session();
        let result = with_scenario("timeout", || poll_signin(&session));
        assert_eq!(result.map(|s| s.status), Ok(SigninStatus::Timeout));
    }

    #[test]
    fn poll_signin_env_error_exit_2_fails_closed_never_authorized() {
        let session = fresh_session();
        let result = with_scenario("exit-2", || poll_signin(&session));
        assert_eq!(result, Err(SigninError::CliUnavailable));
    }

    // ---- bounded polling: an ever-pending poll times out --------------

    #[test]
    fn a_poll_that_exceeds_expires_in_times_out_never_hangs_never_authorized() {
        // Deterministic clock + a fake always-pending round — this test
        // used to drive `poll_signin` against a REAL 1s wall-clock deadline
        // and a real mock-cc subprocess spawn per round-trip, asserting a
        // fixed `elapsed < 3s` wall-clock bound. Under CI/parallel-CPU
        // contention a single subprocess spawn can occasionally take longer
        // than that bound even though the deadline logic itself fired
        // correctly — a false failure, not a real one. Driving
        // `poll_until_terminal` directly with a virtual clock and a no-op
        // fake round removes BOTH real-time sources of flakiness (wall-clock
        // sleeping and subprocess-spawn latency) while asserting the exact
        // same guarantee: a poll that outlives its own `expires_in` reaches
        // `Timeout`, never `Authorized`, and never hangs.
        use std::cell::Cell;

        let session = SigninSession {
            state: SigninState {
                status: SigninStatus::Pending,
                user_code: Some("WDJB-MJHT".to_string()),
                verification_uri: Some("https://example.com/device".to_string()),
            },
            interval_secs: 1,
            expires_in_secs: 5,
        };

        // Jumps forward 10 simulated seconds on every read — deterministically
        // exceeds the 5s `expires_in` on the very next check, regardless of
        // how fast or slow the test process itself is actually scheduled.
        let clock = Cell::new(Instant::now());
        let now = || {
            let current = clock.get();
            clock.set(current + Duration::from_secs(10));
            current
        };

        let mut poll_calls = 0u32;
        let poll_once = || {
            poll_calls += 1;
            Ok(SigninStatus::Pending) // mirrors mock-cc's "pending" scenario: never resolves on its own
        };

        let start = Instant::now();
        let result = poll_until_terminal(&session, poll_once, now, |_| {});
        let elapsed = start.elapsed();

        assert_eq!(result, Ok(terminal(SigninStatus::Timeout)));
        assert!(
            elapsed < Duration::from_millis(500),
            "expected the virtual-clock deadline to fire near-instantly (no real sleep or \
             subprocess spawn involved), took {elapsed:?}"
        );
        assert!(
            poll_calls <= 2,
            "expected the deadline to fire within the first couple of poll rounds, got \
             {poll_calls} calls"
        );
    }

    #[test]
    fn zero_expires_in_times_out_immediately_without_ever_spawning() {
        let session = SigninSession {
            state: SigninState {
                status: SigninStatus::Pending,
                user_code: Some("WDJB-MJHT".to_string()),
                verification_uri: Some("https://example.com/device".to_string()),
            },
            interval_secs: 0,
            expires_in_secs: 0,
        };
        // A DETERMINISTICALLY-resolvable CLI path (the mock, under the same
        // shared `ENV_LOCK` every other `CT_CLI_PATH`-touching test in this
        // module uses) proves this never even tries to SPAWN it, once the
        // deadline has already elapsed — pure fail-closed bookkeeping.
        //
        // Test-isolation fix (found chasing an M4 `cargo test --release`
        // flake): this test previously called `poll_signin` with NO
        // `CT_CLI_PATH` override and no `ENV_LOCK` guard at all. `poll_signin`
        // unconditionally calls `cli::path::resolve()` BEFORE its own
        // zero-deadline bookkeeping ever runs — with no override set (the
        // `cargo test` binary is not a macOS app bundle), `resolve()` fails
        // closed to `PathError::NotVendored`, so the assertion below would
        // (correctly, by this file's own fail-closed discipline) see
        // `Err(CliUnavailable)`, not the `Ok(Timeout)` this test expects.
        // The ONLY reason this ever passed was an accidental, unlocked race:
        // whichever sibling test elsewhere in this same test binary happened
        // to have `CT_CLI_PATH` set to the real mock at that exact moment
        // made `resolve()` succeed instead — invisible during normal `cargo
        // test` runs, but expected to occasionally interleave the other way
        // (observed once under `cargo test --release --lib`, not reproduced
        // in several immediate reruns — exactly the fingerprint of an
        // unlocked, timing-dependent env-var race, not a real regression in
        // the deadline logic itself). `with_cli_path` closes that gap the
        // same way every other test in this file already does.
        let result = with_cli_path(Path::new(&mock_cc()), || poll_signin(&session));
        assert_eq!(result, Ok(terminal(SigninStatus::Timeout)));
    }

    // ---- fail-closed on malformed/empty/garbage seam output -----------

    fn write_stub_script(dir_suffix: &str, body: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "ct-signin-test-{dir_suffix}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let script = dir.join("stub-cc");
        std::fs::write(&script, body).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&script).unwrap().permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&script, perms).unwrap();
        }
        script
    }

    #[test]
    fn garbage_initiate_response_fails_closed_never_pending_with_partial_ceremony() {
        let script = write_stub_script("garbage-initiate", "#!/bin/sh\necho 'not json at all'\n");
        let result = with_cli_path(&script, begin_signin);
        assert_eq!(result, Err(SigninError::MalformedResponse));
        let _ = std::fs::remove_dir_all(script.parent().unwrap());
    }

    #[test]
    fn empty_initiate_response_fails_closed() {
        let script = write_stub_script("empty-initiate", "#!/bin/sh\ntrue\n");
        let result = with_cli_path(&script, begin_signin);
        assert_eq!(result, Err(SigninError::MalformedResponse));
        let _ = std::fs::remove_dir_all(script.parent().unwrap());
    }

    #[test]
    fn malformed_poll_response_fails_closed_never_authorized() {
        let script = write_stub_script("garbage-poll", "#!/bin/sh\necho '{\"nonsense\": true}'\n");
        let session = fresh_session();
        let result = with_cli_path(&script, || poll_signin(&session));
        assert_eq!(result, Err(SigninError::MalformedResponse));
        let _ = std::fs::remove_dir_all(script.parent().unwrap());
    }

    #[test]
    fn unrecognized_status_value_fails_closed_never_authorized() {
        let script = write_stub_script(
            "weird-status",
            "#!/bin/sh\necho '{\"status\":\"quantum-maybe\"}'\n",
        );
        let session = fresh_session();
        let result = with_cli_path(&script, || poll_signin(&session));
        assert_eq!(result, Err(SigninError::MalformedResponse));
        let _ = std::fs::remove_dir_all(script.parent().unwrap());
    }

    #[test]
    fn a_hung_cli_times_out_to_cli_unavailable_never_hangs() {
        let script = write_stub_script("hung-auth", "#!/bin/sh\nsleep 30\necho '{}'\n");
        let session = fresh_session();
        let start = Instant::now();
        // This exercises run_auth's own AUTH_INVOKE_TIMEOUT (15s), not the
        // ceremony's expires_in — bound this test's own patience generously
        // but well under the 30s the stub sleeps.
        let result = with_cli_path(&script, || poll_signin(&session));
        let elapsed = start.elapsed();
        assert_eq!(result, Err(SigninError::CliUnavailable));
        assert!(
            elapsed < Duration::from_secs(20),
            "expected the per-invocation hard timeout to fire well before the child's 30s \
             sleep, took {elapsed:?}"
        );
        let _ = std::fs::remove_dir_all(script.parent().unwrap());
    }

    // ---- the adversarial leaked-field scenario: no secret survives -----

    #[test]
    fn adversarial_leaked_field_never_survives_into_the_returned_signin_state() {
        let session = fresh_session();
        let result = with_scenario("authorized-leaked-field-adversarial", || {
            poll_signin(&session)
        });
        let state = result.expect("the adversarial fixture still reports a real 'authorized'");
        assert_eq!(state.status, SigninStatus::Authorized);
        assert_eq!(state.user_code, None);
        assert_eq!(state.verification_uri, None);

        // The mock deliberately emits `access_token":"FAKE-SYNTHETIC-...` on
        // the wire; prove it never reaches the parsed value at all — not
        // merely "wasn't rendered", but structurally absent from the Rust
        // value this module hands back.
        let debug = format!("{state:?}");
        assert!(!debug.contains("FAKE-SYNTHETIC"));
        assert!(!debug.to_lowercase().contains("access_token"));
        assert!(!debug.to_lowercase().contains("token"));

        let json = serde_json::to_string(&state).expect("SigninState serializes");
        assert!(!json.contains("FAKE-SYNTHETIC"));
        assert!(!json.contains("access_token"));
    }

    // ---- SigninError itself never carries dynamic/secret content -------

    #[test]
    fn signin_error_display_text_is_fixed_plain_language_never_raw_or_dynamic() {
        // Both variants are fieldless (see the type definition) — Display
        // text is therefore always one of exactly two fixed sentences,
        // never interpolated from a raw process/JSON error or a status
        // code. Exercised here for both variants for completeness.
        assert_eq!(
            SigninError::CliUnavailable.to_string(),
            "I couldn't start the sign-in step. Click to try again — it's a fix, not a reset."
        );
        assert_eq!(
            SigninError::MalformedResponse.to_string(),
            "Sign-in didn't respond the way I expected, so I stopped rather than guessing. \
             Please try again."
        );
    }
}
