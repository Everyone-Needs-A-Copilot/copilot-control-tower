//! The `--self-test` process entrypoint (M4 gap-closure, S11): wires
//! `heartbeat::{SELF_TEST_FLAG, run_self_test}` into `main.rs`'s actual
//! argv/exit path — the piece `heartbeat.rs`'s own doc named as
//! "Stream-D's S6/S11 … not a re-derivation of this file format" and that,
//! until this module, nothing in this crate actually called.
//!
//! `main.rs` checks [`requested`] BEFORE calling
//! `copilot_control_tower_lib::run()` at all — a bundle launched with
//! `--self-test` never starts the tray/webview/doctor-timer machinery, it
//! just proves it can boot this far, writes the heartbeat, and exits
//! (invariant #2: still a transient, non-resident invocation of the SAME
//! signed binary, never a second process kind — the crash-only watchdog
//! stays `launchd`, this is not it).
//!
//! ## What the smoke check proves today
//!
//! [`production_smoke_check`] is intentionally minimal: reaching this
//! function at all already proves the binary loaded, linked, and started
//! executing Rust code without crashing — exactly the failure mode
//! ADR-M4-002 cares about (a staged bundle that's corrupt, missing a
//! dependency, or otherwise can't even start). A deeper check (e.g.
//! constructing a real `tauri::Builder` far enough to confirm the webview
//! itself initializes) is a natural follow-up once a caller has a concrete
//! reason to need it, not a speculative abstraction added here.

use std::path::PathBuf;

use super::heartbeat::{self, SELF_TEST_FLAG};

/// True when `args` (typically `std::env::args().collect::<Vec<_>>()`)
/// requests self-test mode — `main.rs`'s only reader.
pub fn requested(args: &[String]) -> bool {
    args.iter().any(|arg| arg == SELF_TEST_FLAG)
}

/// The production entry point — `main.rs` calls this INSTEAD of
/// `copilot_control_tower_lib::run()` when [`requested`] is true, then exits
/// the process with the returned code (0 on a passing self-test, 1
/// otherwise — fail-closed: an unwritable heartbeat root also exits 1,
/// never masquerading as success). Uses the real `heartbeat::
/// default_heartbeat_root()` — the SAME layout root
/// `updater::check::confirm_staged_bundle_boots`'s `FileHeartbeatSource`
/// polls via `updater::check::default_layout_root()` (`heartbeat.rs`'s own
/// doc: "the SAME directory `StagedLayout`'s `root` already denotes") — and
/// this crate's own `CARGO_PKG_VERSION`, so the heartbeat this writes is the
/// exact one the OLD process's `observe()` is waiting for.
pub fn run() -> i32 {
    run_with(heartbeat::default_heartbeat_root(), production_smoke_check)
}

/// The testable core — `layout_root`/`smoke_check` are explicit parameters
/// so tests exercise the real `heartbeat::run_self_test` protocol against a
/// scratch directory instead of `$HOME/Library/Application Support/…`.
pub(crate) fn run_with(layout_root: Option<PathBuf>, smoke_check: impl FnOnce() -> bool) -> i32 {
    let Some(root) = layout_root else {
        // No `$HOME` at all — can't even locate the heartbeat file to prove
        // liveness. Fail closed: exit non-zero, never claim success without
        // having written anything (mirrors `heartbeat::write_heartbeat`'s own
        // "no parent directory" refusal).
        return 1;
    };
    let path = heartbeat::heartbeat_path(&root);
    match heartbeat::run_self_test(&path, env!("CARGO_PKG_VERSION"), smoke_check) {
        Ok(()) => 0,
        Err(_) => 1,
    }
}

fn production_smoke_check() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn scratch_dir(name: &str) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("ct-selftest-test-{name}-{pid}-{n}"));
        std::fs::create_dir_all(&dir).expect("create scratch dir");
        dir
    }

    #[test]
    fn requested_is_true_only_when_the_exact_flag_is_present() {
        assert!(requested(&["ct".to_string(), SELF_TEST_FLAG.to_string()]));
        assert!(!requested(&["ct".to_string()]));
        assert!(!requested(&["ct".to_string(), "--self-tests".to_string()]));
        assert!(!requested(&[]));
    }

    #[test]
    fn run_with_writes_a_self_test_ok_heartbeat_on_a_passing_smoke_check_and_exits_zero() {
        let root = scratch_dir("ok");
        let code = run_with(Some(root.clone()), || true);
        assert_eq!(code, 0);

        let hb = heartbeat::read_heartbeat(&heartbeat::heartbeat_path(&root))
            .expect("heartbeat should have been written");
        assert_eq!(hb.phase, heartbeat::HeartbeatPhase::SelfTestOk);
        assert_eq!(hb.app_version, env!("CARGO_PKG_VERSION"));

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn run_with_leaves_started_not_ok_and_exits_nonzero_on_a_failing_smoke_check() {
        let root = scratch_dir("fail");
        let code = run_with(Some(root.clone()), || false);
        assert_eq!(code, 1);

        let hb = heartbeat::read_heartbeat(&heartbeat::heartbeat_path(&root))
            .expect("heartbeat should still have been written (SelfTestStarted)");
        assert_eq!(hb.phase, heartbeat::HeartbeatPhase::SelfTestStarted);

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn run_with_fails_closed_when_no_layout_root_is_available() {
        assert_eq!(run_with(None, || true), 1);
    }
}
