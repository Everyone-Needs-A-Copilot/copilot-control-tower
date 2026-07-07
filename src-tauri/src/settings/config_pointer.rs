//! Config-pointer write (M2/S2, D-5-M2): points the engine at a manifest by
//! setting `layers.manifest` in the machine config
//! (`~/.claude/cc/config.json`).
//!
//! **The single writer of that file is `cc` itself** (D-5) —
//! `cc config set layers.manifest <path>` performs a dotted-set that
//! preserves every sibling key (`layers.department`, `layers.lock_source`,
//! `paths.*`, ...). This module does **not** replicate that JSON
//! read-modify-write in Rust; it only shells out to the one verb that
//! already does it correctly, through the **same dev-mockable seam**
//! `cli::path::resolve()` uses for `doctor --json` (T4, ADR-M1-003):
//! `CT_CLI_PATH` in a debug/test build, the vendored bundle path in release.
//! A test (or a future dev fixture) points `CT_CLI_PATH` at a stand-in
//! script the same way `cli`'s own tests point it at `fixtures/mock-cc`.
//!
//! The real `cc` isn't vendored into this app yet (WS-D), so in production
//! today `set_manifest_pointer` will honestly return
//! `ConfigPointerError::CliUnavailable` — never a crash, never a false
//! "saved" report. `writer::write_manifest` already wrote the manifest file
//! itself by the time this runs, so a pointer failure here doesn't lose that
//! work — it just means the engine doesn't know where to look yet, which is
//! exactly what the error says.

use std::path::Path;
use std::process::Command;

/// Why `set_manifest_pointer` didn't succeed. Both variants carry a plain-
/// language message — the caller (S6) never needs to inspect a raw
/// `std::io::Error` or a process exit code to explain this to the user.
#[derive(Debug, Clone, PartialEq)]
pub enum ConfigPointerError {
    /// `cli::path::resolve()` couldn't find a usable `cc` binary at all (not
    /// vendored yet in production, or no `CT_CLI_PATH` set in dev). Honest
    /// "the CLI isn't available yet" — not the same failure as the CLI
    /// existing but refusing the write.
    CliUnavailable,
    /// `cc` was found and ran, but exited non-zero, or couldn't be spawned
    /// despite resolving to a path (a TOCTOU race — see `cli::spawn`'s same
    /// caveat).
    CommandFailed { message: String },
}

impl std::fmt::Display for ConfigPointerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigPointerError::CliUnavailable => write!(
                f,
                "The manifest was saved, but the CLI isn't available yet to point the engine at it. \
                 Once it's installed, run `cc config set layers.manifest <path>` yourself, or try again."
            ),
            ConfigPointerError::CommandFailed { message } => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for ConfigPointerError {}

/// Sets `layers.manifest` to `manifest_path` by shelling to
/// `cc config set layers.manifest <path>` (D-5-M2). Called AFTER
/// `writer::write_manifest` succeeds — this function only ever touches the
/// pointer, never the manifest content itself (parse-never-compute: this is
/// configuration input, not resolution).
pub fn set_manifest_pointer(manifest_path: &Path) -> Result<(), ConfigPointerError> {
    let cli_path = crate::cli::path::resolve().map_err(|_| ConfigPointerError::CliUnavailable)?;
    run_config_set(&cli_path, manifest_path)
}

fn run_config_set(cli_path: &Path, manifest_path: &Path) -> Result<(), ConfigPointerError> {
    let output = Command::new(cli_path)
        .arg("config")
        .arg("set")
        .arg("layers.manifest")
        .arg(manifest_path.as_os_str())
        .output();

    match output {
        Ok(result) if result.status.success() => Ok(()),
        Ok(result) => Err(ConfigPointerError::CommandFailed {
            message: format!(
                "The manifest was saved, but the CLI couldn't update where the engine looks for it \
                 (exit code {}). Nothing else changed.",
                result
                    .status
                    .code()
                    .map(|c| c.to_string())
                    .unwrap_or_else(|| "unknown".to_string())
            ),
        }),
        Err(e) => Err(ConfigPointerError::CommandFailed {
            message: format!(
                "The manifest was saved, but the CLI couldn't be started to update where the engine \
                 looks for it: {e}."
            ),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;
    use std::io::Write as _;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir() -> PathBuf {
        let n = DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ct-config-pointer-test-{}-{:?}-{n}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp test dir");
        dir
    }

    /// Writes an executable stand-in for `cc` that logs its full argv to
    /// `invocations.log` next to itself and exits with `exit_code` — the same
    /// role `fixtures/mock-cc` plays for `cli`'s own tests, but local to this
    /// module's tests so S2 doesn't need to extend the shared M1 fixture
    /// (which only implements `doctor`, and is owned by a different task).
    fn write_mock_cc(dir: &Path, exit_code: i32) -> PathBuf {
        let script = dir.join("mock-cc-config-set");
        let mut f = std::fs::File::create(&script).unwrap();
        writeln!(f, "#!/bin/sh").unwrap();
        writeln!(f, "echo \"$@\" >> \"$(dirname \"$0\")/invocations.log\"").unwrap();
        writeln!(f, "exit {exit_code}").unwrap();
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

    #[test]
    fn success_shells_to_cc_config_set_layers_manifest_with_the_path() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = temp_dir();
        let script = write_mock_cc(&dir, 0);
        let manifest_path = dir.join("copilot.layers.yml");

        // SAFETY: serialized by ENV_LOCK, the same lock `cli::path`'s and
        // `cli::mod`'s own tests use for this process-global env var.
        unsafe { std::env::set_var(DEV_OVERRIDE_ENV, &script) };
        let result = set_manifest_pointer(&manifest_path);
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };

        assert_eq!(result, Ok(()));
        let log =
            std::fs::read_to_string(dir.join("invocations.log")).expect("mock cc should have run");
        assert!(
            log.contains("config set layers.manifest"),
            "expected the verb+key in the invocation, got: {log:?}"
        );
        assert!(
            log.contains(&manifest_path.display().to_string()),
            "expected the manifest path in the invocation, got: {log:?}"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn cli_unavailable_is_an_honest_state_never_a_false_success() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK. No override set, and a `cargo test`
        // binary is not a macOS app bundle, so production resolution has
        // nothing vendored — resolve() fails closed to NotVendored, same as
        // `cli::path`'s own equivalent test.
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };
        let result = set_manifest_pointer(Path::new("/tmp/wherever/copilot.layers.yml"));
        assert_eq!(result, Err(ConfigPointerError::CliUnavailable));
    }

    #[test]
    fn a_nonzero_exit_is_surfaced_as_a_command_failure_not_silent_success() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = temp_dir();
        let script = write_mock_cc(&dir, 1);
        let manifest_path = dir.join("copilot.layers.yml");

        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(DEV_OVERRIDE_ENV, &script) };
        let result = set_manifest_pointer(&manifest_path);
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };

        assert!(matches!(
            result,
            Err(ConfigPointerError::CommandFailed { .. })
        ));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn error_messages_are_plain_language() {
        let cli_unavailable = ConfigPointerError::CliUnavailable.to_string();
        let command_failed = ConfigPointerError::CommandFailed {
            message: "The manifest was saved, but the CLI couldn't update where the engine looks for it (exit code 1). Nothing else changed.".to_string(),
        }
        .to_string();

        let banned = [
            "yaml",
            "serde",
            "traceback",
            "panicked",
            "unwrap",
            "Err(",
            "stack trace",
        ];
        for message in [cli_unavailable, command_failed] {
            let lower = message.to_lowercase();
            for term in banned {
                assert!(
                    !lower.contains(&term.to_lowercase()),
                    "message leaks jargon {term:?}: {message}"
                );
            }
        }
    }
}
