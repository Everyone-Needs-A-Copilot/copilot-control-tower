//! Absolute, translocation-safe `cc` path resolution (T4, ADR-M1-003).
//!
//! Resolution order, per the architecture WP:
//! 1. Dev override: `CT_CLI_PATH` env var (compiled-in dev-only flag; never
//!    consulted from a managed/forced MDM domain) — this is how the mock `cc`
//!    fixture stub is injected during development/CI.
//! 2. Release: resolve the vendored CLI relative to the app bundle's resource
//!    dir (via Tauri's resolved resource path, e.g.
//!    `Bundle/Contents/Resources/cc`), then `canonicalize()` to defeat App
//!    Translocation's randomized read-only mount path and symlink games.
//!    **Never** a bare `cc`/`copilot` name — that's the `gh copilot` shim
//!    collision and a $PATH hijack (invariant #4 territory).
//! 3. If neither resolves to an existing, executable, canonicalized absolute
//!    path, resolution fails — the caller (T4's `spawn`) maps that to the
//!    app-owned `CliUnreadable` state, never a fallback to $PATH.
//!
//! ## Release-build safety (the dev/prod boundary)
//!
//! `CT_CLI_PATH` is a **dev-only convenience**, not security-sensitive
//! config (invariant #4 is about the managed/forced MDM domain; this var
//! carries no secret and is never consulted from that domain either way).
//! The distinction that matters here is narrower and stronger: a **shipped
//! release build must not be able to be repointed at an arbitrary CLI at
//! all**, from an env var or anywhere else user-writable. `dev_override`
//! below is behind `#[cfg(debug_assertions)]`, not a runtime `if` — in a
//! `cargo build --release` binary the function (and every `env::var_os` call
//! it would have made) is compiled OUT entirely, not merely skipped at
//! runtime. The production path is bundle-relative and derived from the
//! running binary's own resolved location, never read from config.
//!
//! ## Translocation-safety
//!
//! macOS App Translocation mounts a downloaded, unsigned-for-Gatekeeper `.app`
//! at a randomized read-only path *before* the process starts — `argv[0]` and
//! cwd both reflect that already-relocated mount, which is exactly why
//! neither may be trusted as "the real bundle path" (a relative walk from
//! either can be fooled by whatever placed the bundle there). Instead,
//! `production_path` starts from `std::env::current_exe()` — the OS's own
//! answer for "what is this running process actually", which already
//! reflects the translocated mount — and `canonicalize()`s it to resolve any
//! remaining symlinks, then walks up the **fixed, standard** macOS bundle
//! layout (`Contents/MacOS/<bin>` -> `Contents/Resources/`) to find the
//! vendored CLI. This never touches cwd or a relative `argv[0]` walk.
//!
//! ## WS-D seam (interface-only for M1 — Decision D-3)
//!
//! The real vendoring step (copying a signed `cc` into
//! `Contents/Resources/`) is WS-D, not yet landed. `production_path` computes
//! the *correct* path a vendored CLI would live at and honestly reports
//! `PathError::NotVendored` when nothing is there yet, rather than crashing
//! or silently succeeding on a stray file. `cli::spawn`/`cli::run_doctor` map
//! that to the same `CliUnreadableReason::IoError` ("I couldn't start the
//! engine. Click to reinstall — it's a fix, not a reset.") a genuine spawn
//! failure gets — from the user's perspective, "no CLI vendored yet" and "the
//! CLI won't start" are the same fact.

use std::env;
use std::path::{Path, PathBuf};

/// The dev-only override env var. Documented in `fixtures/README.md` and the
/// M1 architecture WP (§3) — this is how the mock `cc` fixture stub
/// (`fixtures/mock-cc`) is injected during development/CI. See the module
/// doc's "release-build safety" section for why this is safe to name as a
/// public constant even though it's a real override knob: the function that
/// reads it doesn't exist in a release build.
///
/// T9 (QA acceptance gate): gated so a plain, non-test `cargo build
/// --release` compiles this out entirely — its only non-test reader,
/// `dev_override()` below, is itself `#[cfg(debug_assertions)]`-only, so an
/// unqualified release build left the constant dead and `cargo clippy
/// --release --all-targets -- -D warnings` failed on it. `cfg(test)` is
/// included (not just `debug_assertions`) because `cli::mod`'s and this
/// module's own `#[cfg(test)]` test code reference this constant directly
/// (to set/unset `CT_CLI_PATH` around `run_doctor()`/`resolve()` calls), and
/// `cargo clippy --release --all-targets` / `cargo test --release` compile
/// test code under the release profile too (`debug_assertions` false there),
/// which `debug_assertions` alone would not have covered. Either way, a
/// genuine `cargo build --release` (no test target at all) still compiles
/// this out completely — belt-and-suspenders with `dev_override`'s own gate:
/// the literal env-var name string isn't embedded in a shipped release
/// binary at all, not merely unread.
#[cfg(any(debug_assertions, test))]
pub const DEV_OVERRIDE_ENV: &str = "CT_CLI_PATH";

/// The vendored CLI's expected filename inside `Contents/Resources/` once
/// WS-D lands. Kept as a named constant rather than inlined so the one place
/// this crate spells "the vendored binary is called `cc`" is grep-able.
const VENDORED_CLI_NAME: &str = "cc";

/// Why `resolve()` failed to produce a usable, canonicalized absolute path.
/// Every variant maps to the same app-owned `CliUnreadableReason::IoError` at
/// the call site (`cli::run_doctor`) — this type exists so *why* is still
/// distinguishable in logs/diagnostics (stderr-only, never shown to Bob),
/// without multiplying `CliUnreadableReason` variants for a distinction the
/// UI never needs to render differently.
#[derive(Debug)]
pub enum PathError {
    /// Production (release) branch: the bundle has no vendored `cc` yet
    /// (WS-D / Decision D-3 hasn't landed). Distinct from `NotFound` so a
    /// diagnostic can say "not vendored" instead of "corrupt install".
    NotVendored,
    /// A path was named (dev override, or a computed production path) but
    /// nothing executable exists there.
    NotFound(PathBuf),
    /// Resolving the running binary's own location failed (`current_exe()` /
    /// `canonicalize()` returned an I/O error) — should be vanishingly rare,
    /// but fails closed rather than panicking.
    Io(std::io::Error),
}

impl std::fmt::Display for PathError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PathError::NotVendored => {
                write!(
                    f,
                    "no vendored cc found in the app bundle (WS-D not landed)"
                )
            }
            PathError::NotFound(p) => write!(f, "no executable file at {}", p.display()),
            PathError::Io(e) => write!(f, "resolving the CLI path failed: {e}"),
        }
    }
}

/// Resolve the absolute, translocation-safe path to the `cc`/`copilot`
/// binary. Never returns a bare name or a $PATH-relative path — every `Ok`
/// result is an already-`canonicalize()`d absolute path to an existing,
/// executable file. See the module doc for the two-branch resolution order.
pub fn resolve() -> Result<PathBuf, PathError> {
    #[cfg(debug_assertions)]
    {
        if let Some(dev_result) = dev_override() {
            return dev_result;
        }
    }
    production_path()
}

/// The dev-only override branch. `#[cfg(debug_assertions)]`, not a runtime
/// check — see the module doc's "release-build safety" section. Returns
/// `None` when the env var isn't set at all (falls through to the production
/// branch even in a debug build), `Some(Err(..))` when it's set but doesn't
/// resolve to something usable (a misconfigured dev env should fail closed,
/// not silently fall back to a production path that also won't exist).
#[cfg(debug_assertions)]
fn dev_override() -> Option<Result<PathBuf, PathError>> {
    let raw = env::var_os(DEV_OVERRIDE_ENV)?;
    Some(canonicalize_executable(PathBuf::from(raw)))
}

/// The release branch: derive `Contents/Resources/cc` from the running
/// binary's own canonicalized location. See the module doc's
/// "translocation-safety" and "WS-D seam" sections.
fn production_path() -> Result<PathBuf, PathError> {
    let exe = env::current_exe().map_err(PathError::Io)?;
    let exe = exe.canonicalize().map_err(PathError::Io)?;

    // Standard macOS bundle layout: .../Contents/MacOS/<bin> -> .../Contents/Resources/.
    let resources_dir = exe
        .parent() // Contents/MacOS
        .and_then(Path::parent) // Contents
        .map(|contents| contents.join("Resources"));

    let cc_path = match resources_dir {
        Some(dir) => dir.join(VENDORED_CLI_NAME),
        None => return Err(PathError::NotVendored),
    };

    if !cc_path.is_file() {
        // Honest "not vendored yet", not a crash — see the WS-D seam note.
        return Err(PathError::NotVendored);
    }
    canonicalize_executable(cc_path)
}

/// Shared tail of both branches: canonicalize (defeats symlink indirection,
/// same principle as defeating App Translocation) and verify the result is
/// an existing, executable regular file.
fn canonicalize_executable(path: PathBuf) -> Result<PathBuf, PathError> {
    let canonical = path
        .canonicalize()
        .map_err(|_| PathError::NotFound(path.clone()))?;
    if !canonical.is_file() {
        return Err(PathError::NotFound(canonical));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let meta = std::fs::metadata(&canonical).map_err(PathError::Io)?;
        if meta.permissions().mode() & 0o111 == 0 {
            return Err(PathError::NotFound(canonical));
        }
    }
    Ok(canonical)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;

    // `CT_CLI_PATH` is process-global; every test in this module locks the
    // SAME `ENV_LOCK` `spawn`'s and `cli::mod`'s tests use (see
    // `cli::test_env`), so parallel `cargo test` execution can't interleave
    // env-var mutations across any of the three modules. (These tests
    // assume a debug/test build — `cargo test --release` compiles
    // `dev_override` out entirely, per the module doc.)

    fn mock_cc() -> PathBuf {
        PathBuf::from(format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR")))
    }

    #[test]
    fn dev_override_resolves_to_the_canonicalized_mock_cc() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK; no other thread in this process
        // reads/writes CT_CLI_PATH concurrently with this test.
        unsafe { env::set_var(DEV_OVERRIDE_ENV, mock_cc()) };
        let resolved = resolve().expect("dev override should resolve");
        assert!(resolved.is_absolute());
        assert_eq!(resolved, mock_cc().canonicalize().unwrap());
        unsafe { env::remove_var(DEV_OVERRIDE_ENV) };
    }

    #[test]
    fn dev_override_defeats_a_symlink_indirection() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let link_dir = std::env::temp_dir().join(format!(
            "ct-path-test-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&link_dir).unwrap();
        let link = link_dir.join("cc-symlink");
        let _ = std::fs::remove_file(&link);
        #[cfg(unix)]
        std::os::unix::fs::symlink(mock_cc(), &link).unwrap();

        // SAFETY: serialized by ENV_LOCK.
        unsafe { env::set_var(DEV_OVERRIDE_ENV, &link) };
        let resolved = resolve().expect("symlinked dev override should resolve");
        // The symlink's own path is never the answer — resolution must land
        // on the real, canonicalized target (same principle as defeating App
        // Translocation's mount indirection).
        assert_ne!(resolved, link);
        assert_eq!(resolved, mock_cc().canonicalize().unwrap());
        unsafe { env::remove_var(DEV_OVERRIDE_ENV) };

        let _ = std::fs::remove_dir_all(&link_dir);
    }

    #[test]
    fn dev_override_pointing_at_a_missing_file_fails_closed() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            env::set_var(
                DEV_OVERRIDE_ENV,
                "/nonexistent/path/definitely-not-a-real-cc-binary",
            )
        };
        let result = resolve();
        assert!(matches!(result, Err(PathError::NotFound(_))));
        unsafe { env::remove_var(DEV_OVERRIDE_ENV) };
    }

    #[test]
    fn unset_override_falls_through_to_production_and_fails_closed_when_unvendored() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { env::remove_var(DEV_OVERRIDE_ENV) };
        // The `cargo test` binary is not a macOS app bundle, so the
        // production branch has nothing at `Contents/Resources/cc` — it must
        // fail closed to `NotVendored`, never panic and never silently
        // return a bogus path.
        let result = resolve();
        assert!(matches!(result, Err(PathError::NotVendored)));
    }
}
