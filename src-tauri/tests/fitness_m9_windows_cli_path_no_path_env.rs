//! M9/Stream-H (task 77, `docs/01-architecture/windows-parity.md` §1 row 7,
//! §3 Q6) — the Windows CLI path resolver must NEVER resolve the vendored
//! `cc.exe` via a `%PATH%` lookup (the Windows analog of the `gh copilot`
//! bare-name collision `cli::path` already refuses to risk on macOS). There
//! is no Windows toolchain on this machine, so — same style as
//! `fitness_m9_platform_windows_cfg_gated.rs` and the M5 fitness tests
//! before it — the only verification possible here is a cheap,
//! dependency-free source-text scan of the checked-in file, run for real on
//! this macOS host (this test genuinely executes and genuinely fails on a
//! regression, unlike anything inside `cli_path.rs` itself, which is
//! `#[cfg(windows)]`-gated out of every build on this machine).

use std::fs;
use std::path::Path;

fn cli_path_source() -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("platform")
        .join("windows")
        .join("cli_path.rs");
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

/// Denylist of substrings that would indicate an env-var read of `PATH`
/// (any casing — Windows env var lookups are case-insensitive) used to
/// locate the CLI. Deliberately checks `var(`/`var_os(` call shapes rather
/// than a bare `"PATH"` substring, since the module's own doc/comments are
/// expected to mention `%PATH%` freely in prose.
const FORBIDDEN_PATH_ENV_READS: &[&str] = &[
    "var(\"PATH\")",
    "var(\"Path\")",
    "var(\"path\")",
    "var_os(\"PATH\")",
    "var_os(\"Path\")",
    "var_os(\"path\")",
];

#[test]
fn cli_path_never_reads_the_path_env_var_fitness_m9() {
    let src = cli_path_source();
    let offenders: Vec<&str> = FORBIDDEN_PATH_ENV_READS
        .iter()
        .copied()
        .filter(|needle| src.contains(needle))
        .collect();
    assert!(
        offenders.is_empty(),
        "platform/windows/cli_path.rs must never read the PATH env var to locate the CLI — \
         found forbidden pattern(s): {offenders:?}"
    );
}

/// The resolver must never spawn a process itself — resolution and
/// invocation are deliberately separate concerns (`cli::mod`'s own doc: "no
/// other module may construct a `std::process::Command` for the CLI").
/// Belt-and-suspenders: even if this module never grows a spawn call, a
/// `Command::new` call built from a bare, non-absolute name would itself be
/// exactly the hijack surface this file exists to close.
#[test]
fn cli_path_never_constructs_a_process_command_fitness_m9() {
    let src = cli_path_source();
    assert!(
        !src.contains("Command::new"),
        "platform/windows/cli_path.rs resolves a PATH ONLY -- it must never itself construct a \
         std::process::Command (that is cli::spawn's job, and only ever against the already- \
         resolved absolute path)"
    );
}

/// The dev-only override must stay behind the SAME release-build-safety
/// gate `cli::path`'s own `DEV_OVERRIDE_ENV`/`dev_override` use — a bare,
/// ungated env-var read would mean a shipped release build could be
/// repointed at an arbitrary CLI.
#[test]
fn cli_path_dev_override_stays_gated_behind_debug_assertions_test_or_dev_seam_fitness_m9() {
    let src = cli_path_source();
    let idx = src
        .find("pub const DEV_OVERRIDE_ENV")
        .expect("expected a DEV_OVERRIDE_ENV constant in platform/windows/cli_path.rs");
    let preceding = &src[..idx];
    let last_line = preceding.lines().last().unwrap_or("");
    assert!(
        last_line.contains("debug_assertions") && last_line.contains("dev-seam"),
        "expected DEV_OVERRIDE_ENV to be gated `#[cfg(any(debug_assertions, test, feature = \
         \"dev-seam\"))]` (mirroring cli::path's own release-build-safety discipline) — found \
         {last_line:?} instead"
    );
}

/// Sanity: the file this test scans actually exists at the expected path
/// (a typo'd path above would otherwise make every assertion vacuously
/// pass).
#[test]
fn the_scanned_file_is_not_accidentally_empty_fitness_m9() {
    let src = cli_path_source();
    assert!(
        src.len() > 500,
        "platform/windows/cli_path.rs looks suspiciously short ({} bytes) — this test may be \
         scanning the wrong file",
        src.len()
    );
}
