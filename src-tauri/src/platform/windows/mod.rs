//! Windows platform impls — PRE-CREATED shared surfaces only (M9/Stream-B,
//! task 71, `.copilot/wp/52.md`). This file's ENTIRE job is to declare every
//! `pub mod` line ONCE, so six parallel Windows streams (C–H) never collide
//! by each trying to add the FIRST line here — every stub file below is
//! otherwise untouched by Stream-B beyond "compiles, is cfg-gated out of the
//! macOS build, implements the trait/surface with `todo!()` bodies".
//!
//! **No Windows toolchain exists on this machine** — nothing under this
//! module has ever been compiled or run; `#[cfg(windows)]` gates it out of
//! every build here, at BOTH this declaration site (`platform/mod.rs`'s
//! `#[cfg(windows)] pub mod windows;`) and, belt-and-suspenders, via each
//! individual file's own `#![cfg(windows)]` inner attribute below.
//! `tests/fitness_m9_platform_windows_cfg_gated.rs` is the standing,
//! regression-proof guard neither gate is ever silently dropped.
//!
//! ## Ownership table — the exact file each Windows stream fills in
//!
//! | Module | Trait/surface it implements | Owning stream | Task | Consumes [`schtasks`]? |
//! |---|---|---|---|---|
//! | [`forced`] | `platform::PlatformForcedConfig` | Stream-D | 73 | no |
//! | [`loginitem`] | `platform::PlatformLoginItem` | Stream-E | 74 | **yes, read-only** |
//! | [`watchdog`] | `platform::PlatformWatchdogSignal` | Stream-C | 72 | **yes, read-only** |
//! | [`tray`] | `platform::tray_art` surface (`composite`) | Stream-F | 75 | no |
//! | [`secret_store`] | `platform::PlatformSecretStore` | Stream-G | 76 | no |
//! | [`cli_path`] | `platform::cli_path` surface (`resolve`) | Stream-H | 77 | no |
//! | [`schtasks`] | shared Task Scheduler helper | **Stream-B (this task)** | 71 | — |
//!
//! [`schtasks`] is authored by Stream-B and is READ-ONLY to every other
//! stream — Stream-C's crash-restart task and Stream-E's logon-trigger task
//! are two DIFFERENT scheduled tasks that both import an XML template
//! through the same `create_task_from_xml`/`delete_task`/`query_task_exists`
//! helper, so their two `schtasks /Create` call shapes can never silently
//! drift apart. Neither stream may edit `schtasks.rs` itself; a stream
//! needing a new helper function coordinates with Stream-B rather than
//! forking the file.

#![cfg(windows)]

pub mod cli_path;
pub mod forced;
pub mod loginitem;
pub mod schtasks;
pub mod secret_store;
pub mod tray;
pub mod watchdog;
