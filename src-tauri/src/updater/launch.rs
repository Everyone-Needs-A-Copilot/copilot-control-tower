//! The staged-bundle self-test launcher seam (M4 gap-closure — this crate's
//! own `.copilot/wp/24.md` S11 follow-up, wiring `updater::check::
//! apply_update` to `updater::watchdog::run_self_test` +
//! `updater::heartbeat::FileHeartbeatSource` rather than reimplementing any
//! of that decide/promote/rollback logic). See
//! `updater::check::confirm_staged_bundle_boots`'s own doc for how this seam
//! is used end to end.
//!
//! `apply_update` needs to prove a freshly-staged bundle actually boots
//! BEFORE reporting `Ready` (ADR-M4-002): it launches the staged bundle's
//! own binary with `heartbeat::SELF_TEST_FLAG`, then lets
//! `watchdog::run_self_test` (already landed, never re-implemented here)
//! watch for the heartbeat file that launched process writes and
//! promote/roll back accordingly. This module owns exactly one thing: HOW to
//! launch that staged binary — never the decide/promote/rollback decision
//! itself.

use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use super::heartbeat::SELF_TEST_FLAG;

/// The launch seam — trait-based, matching `check::FeedFetcher`'s and
/// `watchdog::HeartbeatSource`'s identical dependency-injection shape, so
/// `apply_update`'s own tests inject a fake launcher: no real
/// subprocess/bundle in `cargo test`.
pub trait StagedBundleLauncher {
    /// Launches the staged bundle at `staged_dir` with `--self-test`, as a
    /// detached background process — never waits for it to exit. A healthy
    /// self-test keeps that process running as the (about-to-be-promoted)
    /// app; `watchdog::run_self_test`'s own heartbeat poll is what decides
    /// when to stop waiting, never this process's exit status.
    fn launch_self_test(&self, staged_dir: &Path) -> io::Result<()>;
}

/// Where the staged bundle's own executable lives, given `staged_dir` — the
/// same fixed macOS bundle layout `cli::path::production_path` already walks
/// in the OTHER direction (`Contents/MacOS/<bin>` <- `Contents/Resources/`):
/// here, `staged_dir` IS expected to be a `.app` bundle root once the real
/// updater artifact (a full signed `.app`, not today's placeholder raw bytes
/// — see `check::stage`'s own doc) is unpacked into it.
fn staged_binary_path(staged_dir: &Path, bin_name: &str) -> PathBuf {
    staged_dir.join("Contents").join("MacOS").join(bin_name)
}

/// The production launcher — spawns the REAL staged binary. **Owner-gated**:
/// exercising this against a genuine staged `.app` requires the real
/// signed/notarized artifact (D-3, still owner-gated per
/// `m4-distribution-decisions`) — `cargo test` never constructs a real
/// macOS bundle to launch, so this impl has no positive-path unit test here
/// (mirrors `verify::verify_staple`'s identical "the fail-closed path is
/// tested for real; the positive path needs a real cert" caveat).
/// `apply_update`'s own tests inject a fake `StagedBundleLauncher` instead
/// (`updater::check`'s test module).
pub struct RealBundleLauncher {
    /// This crate's own bundle executable name — defaults to `Cargo.toml`'s
    /// package name via [`Default`], matching Tauri's own default
    /// bundle-binary-name convention (no `mainBinaryName` override is set in
    /// `tauri.conf.json`).
    pub bin_name: String,
}

impl Default for RealBundleLauncher {
    fn default() -> Self {
        Self {
            bin_name: env!("CARGO_PKG_NAME").to_string(),
        }
    }
}

impl StagedBundleLauncher for RealBundleLauncher {
    fn launch_self_test(&self, staged_dir: &Path) -> io::Result<()> {
        let binary = staged_binary_path(staged_dir, &self.bin_name);
        Command::new(&binary)
            .arg(SELF_TEST_FLAG)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn staged_binary_path_uses_the_standard_macos_bundle_layout() {
        let staged = Path::new("/tmp/some-staged-dir");
        let path = staged_binary_path(staged, "copilot-control-tower");
        assert_eq!(
            path,
            Path::new("/tmp/some-staged-dir/Contents/MacOS/copilot-control-tower")
        );
    }

    #[test]
    fn real_bundle_launcher_default_uses_this_crates_own_package_name() {
        let launcher = RealBundleLauncher::default();
        assert_eq!(launcher.bin_name, env!("CARGO_PKG_NAME"));
    }

    #[test]
    fn launching_a_nonexistent_staged_binary_fails_closed_rather_than_panicking() {
        // No real subprocess ever starts here — `Command::spawn()` fails at
        // the fork/exec step because nothing exists at this path, exactly
        // the same "fails, never panics" shape `cli::spawn::doctor`'s own
        // "couldn't even start the process" arm documents.
        let launcher = RealBundleLauncher::default();
        let staged = std::env::temp_dir().join("ct-launch-test-definitely-not-a-real-bundle-root");
        let result = launcher.launch_self_test(&staged);
        assert!(
            result.is_err(),
            "spawning a nonexistent staged binary must fail, not panic"
        );
    }
}
