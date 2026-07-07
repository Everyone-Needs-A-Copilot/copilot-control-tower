//! The CLI-spawn boundary (T4).
//!
//! Everything that touches the `copilot`/`cc` binary lives here, and only
//! here — `path` resolves *where* it is (never a bare name, never $PATH,
//! translocation-safe), `spawn` resolves *how* it is invoked (timeout,
//! stdout/stderr capture, exit-code interpretation). No other module may
//! construct a `std::process::Command` for the CLI (grep-denied at CI, see
//! `tests/fitness_no_bare_cli_name.rs`).
//!
//! This module does I/O + exit-code classification ONLY — it never
//! interprets ecosystem health. `run_doctor` below is pure plumbing: resolve
//! -> spawn -> classify -> hand any real body to T3's `parse_doctor_body` ->
//! map the result to the DTO T5/T6/T7 render. No health/resolution logic
//! belongs in this module (invariant #1).

pub mod path;
pub mod spawn;

/// Test-only support shared across `cli::path`, `cli::spawn`, and this
/// module's own tests: `CT_CLI_PATH`/`CT_FIXTURE` are process-global env
/// vars, and `cargo test` runs tests in parallel by default, so every test
/// anywhere in this crate that touches either var must serialize on the
/// SAME lock — a per-module `Mutex` would only prevent races within that one
/// module, not across `path`'s, `spawn`'s, and this module's test suites
/// running concurrently.
#[cfg(test)]
pub(crate) mod test_env {
    use std::sync::Mutex;

    pub(crate) static ENV_LOCK: Mutex<()> = Mutex::new(());
}

use crate::model::state::{parse_doctor_body, CliUnreadableReason, ParseOutcome};
use crate::render::derive::{derive_render_state, RenderState};

/// The single entry point T5's doctor timer (and any other caller, e.g. a
/// future manual "refresh now" action) calls. Resolves the CLI path, spawns
/// `doctor --json`, classifies the exit code, hands any real body to T3's
/// parse boundary, and maps the outcome to the render-ready DTO — never a
/// fabricated `Healthy` and never a second verdict computed here.
///
/// Path-resolution failure (not vendored yet / missing / not executable) and
/// a genuine spawn failure are collapsed to the same
/// `CliUnreadableReason::IoError` — from the user's perspective "no CLI to
/// run" and "the CLI won't start" are the same fact ("I couldn't start the
/// engine. Click to reinstall — it's a fix, not a reset.").
pub fn run_doctor() -> RenderState {
    let outcome = match path::resolve() {
        Ok(cli_path) => spawn::doctor(&cli_path),
        Err(_) => spawn::DoctorRunOutcome::Unreadable(CliUnreadableReason::IoError),
    };

    let parse_outcome = match outcome {
        spawn::DoctorRunOutcome::Body(body) => parse_doctor_body(&body),
        spawn::DoctorRunOutcome::Unreadable(reason) => ParseOutcome::Unreadable(reason),
    };

    derive_render_state(&parse_outcome)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::state::CliStatus;
    use crate::render::derive::ClientState;

    fn mock_cc() -> String {
        format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR"))
    }

    fn run_doctor_with(cli_path: Option<&str>, fixture: Option<&str>) -> RenderState {
        // `CT_CLI_PATH`/`CT_FIXTURE` are process-global — serialize on the
        // lock shared with `path`'s and `spawn`'s own tests (see
        // `test_env`), not a lock local to this module.
        let _guard = super::test_env::ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            match cli_path {
                Some(p) => std::env::set_var(path::DEV_OVERRIDE_ENV, p),
                None => std::env::remove_var(path::DEV_OVERRIDE_ENV),
            }
            match fixture {
                Some(f) => std::env::set_var("CT_FIXTURE", f),
                None => std::env::remove_var("CT_FIXTURE"),
            }
        }
        let result = run_doctor();
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::remove_var(path::DEV_OVERRIDE_ENV);
            std::env::remove_var("CT_FIXTURE");
        }
        result
    }

    #[test]
    fn healthy_fixture_renders_a_healthy_ok_state() {
        let rs = run_doctor_with(Some(&mock_cc()), Some("healthy-clean-fleet"));
        assert_eq!(rs.client_state, ClientState::Ok);
        assert_eq!(rs.status, Some(CliStatus::Healthy));
        assert_eq!(rs.cli_unreadable_reason, None);
    }

    #[test]
    fn severity_fail_fixture_renders_the_fail_not_cli_unreadable() {
        // mock-cc exits 1 for this fixture (it has a `fail` checker) — the
        // fail must render as its real status, not as CliUnreadable.
        let rs = run_doctor_with(Some(&mock_cc()), Some("needs-attention-codex-dept-fail"));
        assert_eq!(rs.client_state, ClientState::Ok);
        assert_eq!(rs.status, Some(CliStatus::NeedsAttention));
    }

    #[test]
    fn exit_2_fixture_renders_cli_unreadable_exit_2() {
        let rs = run_doctor_with(Some(&mock_cc()), Some("exit-2"));
        assert_eq!(rs.client_state, ClientState::CliUnreadable);
        assert_eq!(rs.cli_unreadable_reason, Some(CliUnreadableReason::Exit2));
        assert_eq!(rs.status, None);
    }

    #[test]
    fn poisoned_body_on_exit_0_still_renders_cli_unreadable() {
        // checker-missing-severity: mock-cc exits 0 (no `fail` checker), but
        // the body is missing a required security field — must fail closed
        // on CONTENT, not lean on the "successful" exit code.
        let rs = run_doctor_with(Some(&mock_cc()), Some("checker-missing-severity"));
        assert_eq!(rs.client_state, ClientState::CliUnreadable);
        assert_eq!(
            rs.cli_unreadable_reason,
            Some(CliUnreadableReason::MissingSecurityField)
        );
    }

    #[test]
    fn missing_cli_path_renders_cli_unreadable_io_error() {
        let rs = run_doctor_with(
            Some("/nonexistent/definitely-not-a-real-cc-binary"),
            Some("healthy-clean-fleet"),
        );
        assert_eq!(rs.client_state, ClientState::CliUnreadable);
        assert_eq!(rs.cli_unreadable_reason, Some(CliUnreadableReason::IoError));
    }

    #[test]
    fn unvendored_production_path_renders_cli_unreadable_io_error() {
        // No CT_CLI_PATH override at all: the `cargo test` binary is not a
        // macOS app bundle, so `path::resolve()`'s production branch fails
        // closed to `NotVendored`, which `run_doctor` maps to the same
        // "couldn't start the engine" IoError reason.
        let rs = run_doctor_with(None, None);
        assert_eq!(rs.client_state, ClientState::CliUnreadable);
        assert_eq!(rs.cli_unreadable_reason, Some(CliUnreadableReason::IoError));
    }
}
