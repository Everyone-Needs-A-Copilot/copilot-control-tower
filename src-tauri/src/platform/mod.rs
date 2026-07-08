//! The light platform-abstraction module (M9/Stream-B, task 71,
//! `.copilot/wp/52.md` ADR-M9-001, memory `m9-windows-reskin-decisions`,
//! `docs/01-architecture/windows-parity.md`).
//!
//! ## Why light, not big-bang (ADR-M9-001)
//!
//! This crate already used a "neutral DECIDE + thin `#[cfg(target_os =
//! "macos")]` HOW seam" pattern before this module existed —
//! `managed::forced::real_key_is_forced`'s `#[cfg(not(target_os = "macos"))]`
//! fail-closed stub even anticipated M9 explicitly in its own doc comment. A
//! dynamic-dispatch trait rewrite of the whole crate would risk proven-green
//! macOS code for uncertain benefit and can't be verified against a real
//! Windows box from this machine anyway (no Windows toolchain here — see
//! `docs/01-architecture/windows-parity.md`'s own STATUS line). The decision
//! this module makes concrete: **traits only where a mock is genuinely
//! needed** — the four seams below already have (or gain here) an
//! injectable, unit-testable shape — **cfg-selected `pub use` aliasing
//! everywhere else** (tray art, CLI path — both deterministic pure functions
//! with no runtime branching a mock would ever need to intercept).
//!
//! ## The four platform traits
//!
//! | Trait | Wraps (macOS, THIN — move no logic) | Windows stub (Stream) |
//! |---|---|---|
//! | [`PlatformForcedConfig`] | [`crate::managed::forced`]'s free functions (`managed/forced.rs`) | [`windows::forced`] (Stream-D, task 73) |
//! | [`PlatformLoginItem`] | [`crate::loginitem::smappservice::LoginItemService`] (`loginitem/smappservice.rs`) | [`windows::loginitem`] (Stream-E, task 74) |
//! | [`PlatformWatchdogSignal`] | [`crate::updater::watchdog::HeartbeatSource`] via `updater::heartbeat::FileHeartbeatSource` (`updater/watchdog.rs`) | [`windows::watchdog`] (Stream-C, task 72) |
//! | [`PlatformSecretStore`] | [`crate::managed::secret_store::secret_store_endpoint`] (an ENDPOINT REFERENCE only, never a secret value — see that module's own doc) | [`windows::secret_store`] (Stream-G, task 76) |
//!
//! Every macOS impl below lives in [`macos`] and is a THIN wrapper —
//! construction-time delegation only, no re-derived decision logic — over
//! the already-proven module named in the table above. This is a pure
//! refactor: every one of those modules' own existing public functions,
//! types, and tests are UNCHANGED by this module's existence.
//!
//! ## The two cfg-aliased surfaces (no trait, no mock needed)
//!
//! [`tray_art`] and [`cli_path`] are `pub use` aliases, not traits — both
//! wrap a deterministic pure function (`render::glyph::composite`,
//! `cli::path::resolve`) with no OS-conditional runtime behavior a test
//! would ever need to swap out; the Windows re-skin needs its OWN
//! implementation of each (different pixel format / registry-based
//! resolution), not a mockable seam into the SAME one. See [`windows::tray`]
//! (Stream-F, task 75) and [`windows::cli_path`] (Stream-H, task 77).
//!
//! "Packaging" (the third cfg-aliasing candidate ADR-M9-001 names) has no
//! existing Rust module to alias yet — `packaging/launchd/*.plist` is static
//! config, not code — so it is deliberately NOT scaffolded here; Stream-I
//! (task 78, integration phase) owns the Windows packaging surface
//! (`packaging/wix/`) once all six parallel seams below have landed.
//!
//! ## Windows: pre-created shared surfaces only (this task's other half)
//!
//! [`windows`] pre-creates every `pub mod` line + a per-seam stub file so
//! Stream-B is the ONLY stream that ever touches `platform/windows/mod.rs`
//! (and `Cargo.toml`'s `cfg(windows)` dependency block) — six parallel
//! streams (C–H) each fill in exactly ONE stub file, plus the SHARED
//! `windows::schtasks` helper (authored here, consumed READ-ONLY by
//! Stream-C and Stream-E). See `windows`'s own module doc for the full
//! ownership table. Every symbol under `windows::` is compiled out of a
//! macOS build entirely (`#[cfg(windows)]` at BOTH the declaration site
//! below and, belt-and-suspenders, inside each file itself) — there is no
//! Windows toolchain on this machine, so none of it has ever been compiled
//! or run; `tests/fitness_m9_platform_windows_cfg_gated.rs` is the standing,
//! regression-proof guard that this stays true.

#[cfg(target_os = "macos")]
pub mod macos;

#[cfg(windows)]
pub mod windows;

use crate::loginitem::smappservice::{LoginItemError, LoginItemStatus};
use crate::managed::forced::ForcedLookup;
use crate::managed::secret_store::SecretStoreRef;
use crate::updater::watchdog::HeartbeatOutcome;
use std::path::Path;
use std::time::Duration;

/// The forced/managed-config-domain seam — macOS's `CFPreferencesAppValueIsForced`
/// / `CFPreferencesCopyAppValue` (`managed::forced`, the SOLE FFI boundary,
/// unchanged by this module), Windows' gated `HKLM\...\Policies` read
/// (ADR-M9-003, `windows::forced`, Stream-D). Reuses [`ForcedLookup`] as-is —
/// it is already a platform-neutral three-way decision type (`Forced` /
/// `IgnoredUserDomain` / `Absent`), not something either platform's impl
/// redefines.
pub trait PlatformForcedConfig {
    /// `true` iff `key` is genuinely forced in this platform's managed
    /// domain, regardless of the value's type/content.
    fn key_is_forced(&self, key: &str) -> bool;
    /// The forced-domain-only string reader — see [`ForcedLookup`].
    fn forced_string(&self, key: &str) -> ForcedLookup<String>;
    /// The forced-domain-only boolean reader, built on [`Self::forced_string`].
    fn forced_bool(&self, key: &str) -> ForcedLookup<bool>;
    /// Folds a [`Self::forced_string`] lookup + compiled-in default into the
    /// value every caller actually uses (auditing, never honoring, an
    /// ignored user-domain value).
    fn resolve_string(&self, key: &str, default: &str) -> String;
    /// The boolean counterpart to [`Self::resolve_string`].
    fn resolve_bool(&self, key: &str, default: bool) -> bool;
}

/// The launch-at-login seam — macOS's `SMAppService`
/// (`loginitem::smappservice::LoginItemService`, ADR-M5-004), Windows' logon-
/// trigger scheduled task / `HKCU\...\Run` fallback (`windows::loginitem`,
/// Stream-E). Mirrors `LoginItemService`'s exact shape (reusing its
/// [`LoginItemStatus`]/[`LoginItemError`] types, never redefining them) so
/// every existing macOS impl/fake of that trait can back this one with pure
/// delegation.
pub trait PlatformLoginItem {
    fn register(&self) -> Result<(), LoginItemError>;
    fn unregister(&self) -> Result<(), LoginItemError>;
    fn status(&self) -> LoginItemStatus;
}

/// The crash-only watchdog's liveness-proof seam — the SAME
/// `updater::watchdog::HeartbeatSource`/[`HeartbeatOutcome`] shape M4 already
/// built and unit-tests fully platform-neutrally (a heartbeat FILE, not an
/// OS-specific IPC primitive). What genuinely differs per platform is the OS
/// mechanism that RE-LAUNCHES the app on a crash in the first place
/// (`launchd`'s `KeepAlive` LaunchAgent vs. Task Scheduler's
/// failure-triggered restart, ADR-M9-002) — that's packaging/config, not
/// this trait. This seam exists so Windows' watchdog (`windows::watchdog`,
/// Stream-C) can be constructed and unit-tested against the SAME
/// promote/rollback decision logic (`updater::watchdog::decide`) without
/// duplicating it.
pub trait PlatformWatchdogSignal {
    fn observe(&self, staged: &Path, timeout: Duration) -> HeartbeatOutcome;
}

/// The shared secret-store **endpoint reference** seam (never a secret
/// value — see `managed::secret_store`'s own doc for why). macOS reads it
/// from the SAME forced-domain boundary every other managed key uses;
/// Windows' real per-secret storage backend (Credential Manager/DPAPI via
/// the `keyring` crate, `windows::secret_store`, Stream-G) is a DIFFERENT,
/// lower-level concern this app itself never touches directly (the CLI
/// resolves the actual secret VALUE — `credentials-and-boundary.md` §1.6.4).
/// This trait covers only the ENDPOINT-REFERENCE half this app owns.
pub trait PlatformSecretStore {
    fn secret_store_endpoint(&self) -> Option<SecretStoreRef>;
}

// ---------------------------------------------------------------------------
// cfg-selected pub-use aliasing (no trait — see the module doc).
// ---------------------------------------------------------------------------

/// The tray glyph/badge compositor. macOS: `render::glyph` (template-image
/// alpha silhouette, `render::glyph::composite`). Windows: `windows::tray`
/// (explicit light/dark ICO variants — Windows has no template-image
/// tinting, ADR/parity §1 row 6, Stream-F). Both sides expose the SAME
/// `composite(glyph_state: &str) -> tauri::image::Image<'static>` shape —
/// callers (`tray.rs`) go through this alias rather than naming either
/// concrete module directly, so `tray.rs` itself never needs a `#[cfg]`.
#[cfg(target_os = "macos")]
pub use crate::render::glyph as tray_art;
#[cfg(windows)]
pub use windows::tray as tray_art;

/// The absolute, translocation/hijack-safe CLI path resolver. macOS:
/// `cli::path` (App Translocation-safe, `Contents/Resources/cc`). Windows:
/// `windows::cli_path` (install-path/registry-based, never `%PATH%` —
/// parity §1 row 7, Stream-H). Both sides expose a `resolve() ->
/// Result<PathBuf, _>` shape; each platform's own error type is distinct
/// (the failure MODES genuinely differ — "not vendored in the bundle" vs.
/// "no registry uninstall key yet" are not the same fact), so this alias
/// does not attempt to unify the error type, only the module surface.
#[cfg(target_os = "macos")]
pub use crate::cli::path as cli_path;
#[cfg(windows)]
pub use windows::cli_path;
