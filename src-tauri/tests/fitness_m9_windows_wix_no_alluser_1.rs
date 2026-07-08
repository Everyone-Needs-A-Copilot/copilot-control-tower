//! M9 Stream-I (task 78) — the per-user MSI invariant, standing guard.
//! `docs/01-architecture/windows-parity.md` §1 rows 10/11, ADR-M9-005:
//! this repo's Windows MSI must NEVER be a per-machine
//! (`ALLUSERS="1"`) install — that is the exact admin-required
//! anti-pattern the task exists to avoid (invariant #3's admin-free
//! constraint). Same cheap, dependency-free text-scan style every other
//! fitness test in this crate already uses (e.g.
//! `fitness_m9_windows_watchdog_no_periodic_trigger.rs`'s scan of the
//! Task Scheduler XML template) — no real WiX compile, no Windows
//! toolchain exists on this machine to run one.

use std::fs;
use std::path::{Path, PathBuf};

fn main_wxs_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("packaging")
        .join("windows")
        .join("wix")
        .join("main.wxs")
}

#[test]
fn main_wxs_exists() {
    assert!(
        main_wxs_path().exists(),
        "expected packaging/windows/wix/main.wxs to exist"
    );
}

#[test]
fn main_wxs_never_sets_alluser_1() {
    let src = fs::read_to_string(main_wxs_path()).expect("read main.wxs");
    assert!(
        !src.contains(r#"Id="ALLUSERS" Value="1""#),
        "main.wxs must NEVER set ALLUSERS=\"1\" — that is the per-machine, \
         admin-required anti-pattern this task exists to avoid (invariant #3)"
    );
}

#[test]
fn main_wxs_declares_per_user_install_scope() {
    let src = fs::read_to_string(main_wxs_path()).expect("read main.wxs");
    assert!(
        src.contains(r#"InstallScope="perUser""#),
        "main.wxs must declare InstallScope=\"perUser\" on <Package> — the \
         positive half of the per-user invariant, not just the absence of \
         ALLUSERS=1"
    );
    assert!(
        src.contains(r#"Id="ALLUSERS" Value="""#),
        "main.wxs must set an EMPTY ALLUSERS property (never omit it entirely \
         and never set it to \"1\") — this is what actually suppresses the \
         per-machine default"
    );
}

#[test]
fn main_wxs_never_writes_to_hklm() {
    // Per-user components must be keyed off HKCU only — a component keyed
    // to HKLM would either fail (no admin token) or silently defeat the
    // per-user install's own scope. This installer must also never write
    // to the IT/MDM-managed forced-config domain
    // (`HKLM\Software\Policies\ENAC\ControlTower`) — that hive is
    // read-only to this app in every direction (ADR-M9-003).
    //
    // The check is for the actual XML attribute (`Root="HKLM"`), not the
    // bare word "HKLM" — this file's own top-of-file `<!-- -->` doc
    // comment correctly NAMES HKLM while explaining why the installer
    // never touches it, and a substring-only check would trip on that
    // correct documentation rather than a real regression.
    let src = fs::read_to_string(main_wxs_path()).expect("read main.wxs");
    assert!(
        !src.contains(r#"Root="HKLM""#),
        "main.wxs must never key a component off Root=\"HKLM\" — a per-user \
         MSI writes only to HKCU; HKLM\\...\\Policies is IT/MDM-managed and \
         outside this installer's write authority in either direction"
    );
}

#[test]
fn main_wxs_wires_the_uninstall_cleanup_custom_action_only_on_a_genuine_uninstall() {
    let src = fs::read_to_string(main_wxs_path()).expect("read main.wxs");
    assert!(
        src.contains("RunUninstallCleanup"),
        "main.wxs must wire the never-orphan uninstall custom action"
    );
    assert!(
        src.contains(r#"REMOVE="ALL""#) && src.contains("UPGRADINGPRODUCTCODE"),
        "the uninstall cleanup custom action must be gated on a genuine \
         uninstall (REMOVE=\"ALL\" AND NOT UPGRADINGPRODUCTCODE) — an \
         in-place upgrade must never tear down the scheduled tasks it is \
         about to immediately re-register"
    );
}

/// The companion standalone custom-action source this template's
/// `<Binary>` embeds (see that file's own doc for what it removes vs.
/// retains) must exist alongside the template.
#[test]
fn uninstall_customaction_source_exists() {
    let path = main_wxs_path()
        .parent()
        .expect("main.wxs has a parent dir")
        .join("uninstall-customaction.rs");
    assert!(
        path.exists(),
        "expected packaging/windows/wix/uninstall-customaction.rs to exist \
         alongside main.wxs"
    );
}
