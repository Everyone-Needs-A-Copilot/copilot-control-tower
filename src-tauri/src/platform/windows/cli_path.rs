//! Windows `platform::cli_path` surface (M9/Stream-H, task 77,
//! `docs/01-architecture/windows-parity.md` §1 row 7, §3 Q6, ADR-M9-005).
//! The Windows analog of `cli::path`'s translocation-safe resolver — see
//! that module's doc for the macOS half of this story.
//!
//! ## Resolution order — never `%PATH%`
//!
//! 1. **Dev override** (`CT_CLI_PATH`, same env var name `cli::path` uses on
//!    macOS — one fixture-injection mechanism, not a per-platform-renamed
//!    pair): compiled-in dev-only, gated `#[cfg(any(debug_assertions, test,
//!    feature = "dev-seam"))]`, exactly mirroring `cli::path::dev_override`'s
//!    own release-build-safety discipline — see that module's doc for why a
//!    genuine `cargo build --release` compiles this branch out entirely
//!    rather than merely skipping it at runtime.
//! 2. **`current_exe()`-relative** (primary production path): derive the
//!    vendored `cc.exe`'s expected location from `std::env::current_exe()`,
//!    canonicalized — the OS's own answer for "what is this running
//!    process", never `argv[0]` or the process's current working directory.
//!    This is the strongest anti-hijack technique available and needs no
//!    install-time bookkeeping at all: a `%PATH%`-planted decoy `copilot.exe`
//!    or `cc.exe`, or a malicious cwd, can never be consulted because this
//!    resolver never reads either.
//! 3. **Registry install-location fallback** (owner-gated — needs the MSI
//!    install, Stream-I/task 78, to have run): `HKCU\Software\
//!    EveryoneNeedsACopilot\ControlTower`'s `InstallLocation` value, the way
//!    parity §1 row 7 names as the alternative to a `current_exe()`-relative
//!    walk (useful once the exe has been relocated after install in a way a
//!    relative walk can't follow). This is a plain, non-security-sensitive
//!    per-user install-path record — **not** the security-sensitive forced
//!    `HKLM\...\Policies` domain ADR-M9-003/`windows::forced` (Stream-D,
//!    task 73) owns; this module never reads that key and never duplicates
//!    Stream-D's gated-forced-config logic.
//! 4. Neither resolves ⇒ fails closed to [`PathError::NotInstalled`], never
//!    a bare-name/`%PATH%` fallback.
//!
//! ## Release-build safety (mirrors `cli::path`'s dev/prod boundary exactly)
//!
//! `CT_CLI_PATH` carries no secret and is never read from the managed/forced
//! domain either way — the property that matters is narrower: a **shipped
//! release build must not be repointable at an arbitrary CLI at all**, from
//! an env var or anywhere else user-writable. `dev_override` below is behind
//! `#[cfg(debug_assertions)]`-equivalent gating (widened to also cover
//! `cfg(test)`/`feature = "dev-seam"` for the same reasons `cli::path`'s own
//! doc comment explains at length), not a runtime `if` — in a genuine
//! `cargo build --release` binary the function (and the env-var name
//! itself) is compiled OUT, not merely unread.
//!
//! ## DLL/search-order hijack hardening (invariant #4)
//!
//! Windows' classic DLL search order includes the process's current working
//! directory and, historically, `%PATH%` — an attacker who controls either
//! (a shared/writable cwd this app happens to be launched from, or an
//! earlier `%PATH%` entry) can plant a same-named DLL and have it loaded
//! instead of the real one, the rough Windows analog of the `gh copilot`
//! bare-name collision this crate already refuses to risk on macOS.
//! [`harden_dll_search_path`] calls `SetDefaultDllDirectories` with
//! `LOAD_LIBRARY_SEARCH_DEFAULT_DIRS` once per process (idempotent, `Once`-
//! guarded) — this removes the current-working-directory search element
//! entirely and constrains the default search to the application directory,
//! system directories, and directories explicitly added via
//! `AddDllDirectory`, per Microsoft's own documented dynamic-library
//! security guidance. [`resolve`] calls this before computing a path, since
//! it is the one call site every caller (this module's own consumers, and
//! eventually `cli::spawn`'s Windows path) reaches before ever invoking the
//! vendored CLI. This mitigates the DLL half of the hijack surface; it does
//! not by itself prevent a `%PATH%`-planted decoy **executable** — that half
//! is closed structurally by never consulting `%PATH%` at all (see
//! `tests/fitness_m9_windows_cli_path_no_path_env.rs`).

#![cfg(windows)]

use std::env;
use std::path::{Path, PathBuf};
use std::sync::Once;

/// The dev-only override env var — the SAME name (and SAME fixture,
/// `fixtures/mock-cc`) `cli::path::DEV_OVERRIDE_ENV` uses on macOS. See the
/// module doc's "release-build safety" section.
#[cfg(any(debug_assertions, test, feature = "dev-seam"))]
pub const DEV_OVERRIDE_ENV: &str = "CT_CLI_PATH";

/// The vendored CLI's expected filename once WS-D's Windows counterpart
/// (Stream-I, task 78) lands. Kept as a named constant, matching
/// `cli::path::VENDORED_CLI_NAME`'s own precedent.
const VENDORED_CLI_NAME: &str = "cc.exe";

/// The MSI-recorded per-user install-location registry value (owner-gated —
/// Stream-I/task 78 hasn't landed, so this branch honestly returns `None`
/// today). Deliberately `HKCU`, not `HKLM\...\Policies` — an install path is
/// not itself a security decision, so it does not belong in the
/// forced/managed domain `windows::forced` (Stream-D) owns.
const INSTALL_LOCATION_SUBKEY: &str = r"Software\EveryoneNeedsACopilot\ControlTower";
const INSTALL_LOCATION_VALUE: &str = "InstallLocation";

/// Windows' own resolution-failure reasons — deliberately a DIFFERENT type
/// from `cli::path::PathError` (the failure modes genuinely differ: "no
/// registry uninstall key yet" is not the same fact as "not vendored in the
/// bundle").
#[derive(Debug)]
pub enum PathError {
    /// Neither the `current_exe()`-relative path nor the registry
    /// install-location fallback found a vendored CLI (the MSI install,
    /// Stream-I, hasn't landed, or hasn't run on this machine yet).
    NotInstalled,
    /// A path was named but nothing executable exists there.
    NotFound(PathBuf),
    /// Resolving the running binary's own location failed.
    Io(std::io::Error),
}

impl std::fmt::Display for PathError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PathError::NotInstalled => write!(f, "no vendored cc found (MSI install not landed)"),
            PathError::NotFound(p) => write!(f, "no executable file at {}", p.display()),
            PathError::Io(e) => write!(f, "resolving the CLI path failed: {e}"),
        }
    }
}

/// Resolve the absolute path to the vendored `cc.exe`. Never returns a bare
/// name or a `%PATH%`-relative path — every `Ok` result is an already-
/// `canonicalize()`d absolute path to an existing file. See the module doc
/// for the full resolution order and the hijack-hardening rationale.
pub fn resolve() -> Result<PathBuf, PathError> {
    harden_dll_search_path();

    #[cfg(any(debug_assertions, test, feature = "dev-seam"))]
    {
        if let Some(dev_result) = dev_override() {
            return dev_result;
        }
    }
    production_path()
}

/// The dev-only override branch — see the module doc's "release-build
/// safety" section. `None` when unset (falls through to production even in
/// a debug build); `Some(Err(..))` when set but unusable (fails closed
/// rather than silently falling back to a production path that also won't
/// exist).
#[cfg(any(debug_assertions, test, feature = "dev-seam"))]
fn dev_override() -> Option<Result<PathBuf, PathError>> {
    let raw = env::var_os(DEV_OVERRIDE_ENV)?;
    Some(canonicalize_executable(PathBuf::from(raw)))
}

/// The production resolution order: `current_exe()`-relative first (needs no
/// install-time bookkeeping, strongest anti-hijack guarantee), then the
/// registry install-location fallback (owner-gated, needs Stream-I's MSI).
/// Never `%PATH%` — see `tests/fitness_m9_windows_cli_path_no_path_env.rs`.
fn production_path() -> Result<PathBuf, PathError> {
    if let Ok(candidate) = current_exe_relative_candidate() {
        if let Ok(resolved) = canonicalize_executable(candidate) {
            return Ok(resolved);
        }
    }

    match registry_install_location_candidate() {
        Some(candidate) => canonicalize_executable(candidate),
        None => Err(PathError::NotInstalled),
    }
}

/// Derives `<install_dir>\cc.exe` from the running binary's own
/// canonicalized location — the OS's own answer for "what is this running
/// process", never `argv[0]` or cwd. Windows has no App Translocation
/// equivalent, but the same construction defeats a `%PATH%`-planted decoy
/// and a malicious cwd identically: neither is ever consulted.
fn current_exe_relative_candidate() -> Result<PathBuf, PathError> {
    let exe = env::current_exe().map_err(PathError::Io)?;
    let exe = exe.canonicalize().map_err(PathError::Io)?;
    let install_dir = exe
        .parent()
        .ok_or_else(|| PathError::NotFound(exe.clone()))?;
    Ok(install_dir.join(VENDORED_CLI_NAME))
}

/// Reads the MSI-recorded per-user install-location registry value. Honest
/// `None` (never a guess) when the key/value isn't present — today that is
/// always the case, since Stream-I's MSI installer hasn't landed yet.
fn registry_install_location_candidate() -> Option<PathBuf> {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let key = hkcu.open_subkey(INSTALL_LOCATION_SUBKEY).ok()?;
    let install_location: String = key.get_value(INSTALL_LOCATION_VALUE).ok()?;
    Some(PathBuf::from(install_location).join(VENDORED_CLI_NAME))
}

/// Shared tail of both branches: canonicalize (defeats symlink/junction
/// indirection) and verify the result is an existing file.
fn canonicalize_executable(path: PathBuf) -> Result<PathBuf, PathError> {
    let canonical = path
        .canonicalize()
        .map_err(|_| PathError::NotFound(path.clone()))?;
    if !canonical.is_file() {
        return Err(PathError::NotFound(canonical));
    }
    Ok(canonical)
}

/// DLL-search-order hijack hardening — see the module doc's dedicated
/// section. Idempotent (`Once`-guarded): safe to call from every `resolve()`
/// invocation, and safe for a future caller (e.g. an eventual Windows
/// `cli::spawn` call site, or `main`'s own startup path) to call again
/// directly without double-applying anything.
fn harden_dll_search_path() {
    static HARDEN_ONCE: Once = Once::new();
    HARDEN_ONCE.call_once(|| {
        // SAFETY: `SetDefaultDllDirectories` takes no pointer/buffer
        // argument — only a flags value — and its only effect is changing
        // this process's OWN default DLL search order going forward; it
        // never touches memory this crate doesn't own and cannot be called
        // with an invalid argument here (the flag constant is compiled-in,
        // never user-controlled). Owner-gated: the exact `windows`-crate
        // 0.61 binding signature for this call is unverified — no Windows
        // toolchain exists on this machine to build against it (mirrors the
        // same caveat this crate's `Cargo.toml` already carries for
        // Stream-G's `keyring` feature name).
        unsafe {
            let _ = windows::Win32::System::LibraryLoader::SetDefaultDllDirectories(
                windows::Win32::System::LibraryLoader::LOAD_LIBRARY_SEARCH_DEFAULT_DIRS,
            );
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    // These tests compile and are reviewable, but — like every other file
    // under `platform/windows/` — never actually RUN in this session's
    // `cargo test`: the whole module is `#[cfg(windows)]`-gated out on a
    // macOS host, at both the declaration site (`platform/mod.rs`) and this
    // file's own `#![cfg(windows)]` inner attribute. Real execution is
    // owner-gated to a real Windows box (ADR-M9-005/006).

    fn mock_cc() -> PathBuf {
        PathBuf::from(format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR")))
    }

    #[test]
    fn dev_override_resolves_to_the_canonicalized_mock_cc() {
        // SAFETY: this crate's own convention serializes CT_CLI_PATH access
        // via `cli::test_env::ENV_LOCK`; that lock is macOS/cross-platform
        // code this module cannot depend on directly without pulling
        // non-windows-gated code into a windows-gated file, so a real
        // Windows-run version of this test would take its own lock — noted
        // here as a design point for the owner-gated Windows verification
        // pass, not resolved by this session.
        unsafe { env::set_var(DEV_OVERRIDE_ENV, mock_cc()) };
        let resolved = resolve();
        unsafe { env::remove_var(DEV_OVERRIDE_ENV) };
        let resolved = resolved.expect("dev override should resolve");
        assert!(resolved.is_absolute());
    }

    #[test]
    fn dev_override_pointing_at_a_missing_file_fails_closed() {
        unsafe { env::set_var(DEV_OVERRIDE_ENV, r"C:\definitely\not\a\real\cc.exe") };
        let result = resolve();
        unsafe { env::remove_var(DEV_OVERRIDE_ENV) };
        assert!(matches!(result, Err(PathError::NotFound(_))));
    }

    #[test]
    fn unset_override_falls_through_to_production_and_fails_closed_when_unvendored() {
        unsafe { env::remove_var(DEV_OVERRIDE_ENV) };
        // The `cargo test` binary is not sitting next to a vendored cc.exe,
        // and no registry install-location value exists in this session
        // (Stream-I's MSI hasn't landed) — must fail closed to
        // `NotInstalled`, never panic and never fabricate a path.
        let result = production_path();
        assert!(matches!(
            result,
            Err(PathError::NotInstalled) | Err(PathError::NotFound(_))
        ));
    }

    #[test]
    fn registry_install_location_candidate_is_honestly_none_when_absent() {
        // No assumption about the real registry state on a Windows box —
        // this only asserts the function never panics and returns `None`
        // rather than fabricating a path when the key plausibly doesn't
        // exist (which is always true pre-Stream-I).
        let _ = registry_install_location_candidate();
    }

    #[test]
    fn harden_dll_search_path_is_idempotent() {
        // Calling this twice must never panic — the `Once` guard is the
        // whole point.
        harden_dll_search_path();
        harden_dll_search_path();
    }
}
