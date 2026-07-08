//! M9 Stream-I (task 78) — the standalone WiX uninstall custom action
//! (`packaging/windows/wix/uninstall-customaction.rs`) hardcodes its own
//! copies of the two Task Scheduler task names (it cannot depend on the
//! `src-tauri` library crate — see that file's own "Standalone" doc
//! section for why). This is the drift guard: both copies must stay
//! byte-identical to `platform::windows::watchdog::WATCHDOG_TASK_NAME` and
//! `platform::windows::loginitem::LOGON_TASK_NAME` — a source-scan, not a
//! call-graph check, matching this crate's existing fitness-test style
//! (e.g. `fitness_m5_loginitem_not_watchdog.rs`).

use std::fs;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .canonicalize()
        .expect("repo root must exist")
}

fn read(relative: &str) -> String {
    let path = repo_root().join(relative);
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

#[test]
fn uninstall_customaction_watchdog_task_name_matches_watchdog_rs() {
    let watchdog_src = read("src-tauri/src/platform/windows/watchdog.rs");
    let uninstall_src = read("packaging/windows/wix/uninstall-customaction.rs");

    // Pull the literal string value out of `watchdog.rs`'s own const —
    // a plain substring find, not a parser, matching every other fitness
    // test's cheap-and-cheerful style in this crate.
    let needle = "pub const WATCHDOG_TASK_NAME: &str = r\"";
    let start = watchdog_src
        .find(needle)
        .expect("expected WATCHDOG_TASK_NAME const in watchdog.rs")
        + needle.len();
    let end = watchdog_src[start..]
        .find('"')
        .expect("expected a closing quote after WATCHDOG_TASK_NAME's value");
    let watchdog_task_name = &watchdog_src[start..start + end];

    assert!(
        uninstall_src.contains(watchdog_task_name),
        "packaging/windows/wix/uninstall-customaction.rs's WATCHDOG_TASK_NAME \
         literal must match platform::windows::watchdog::WATCHDOG_TASK_NAME \
         exactly ({watchdog_task_name:?}) — the standalone uninstall binary \
         duplicates, and must stay byte-identical to, that task name"
    );
}

#[test]
fn uninstall_customaction_logon_task_name_matches_loginitem_rs() {
    let loginitem_src = read("src-tauri/src/platform/windows/loginitem.rs");
    let uninstall_src = read("packaging/windows/wix/uninstall-customaction.rs");

    let needle = "pub const LOGON_TASK_NAME: &str = \"";
    let start = loginitem_src
        .find(needle)
        .expect("expected LOGON_TASK_NAME const in loginitem.rs")
        + needle.len();
    let end = loginitem_src[start..]
        .find('"')
        .expect("expected a closing quote after LOGON_TASK_NAME's value");
    // loginitem.rs spells this as a plain (non-raw) string literal, so its
    // source text escapes the backslash (`\\`) — decode that ONE escape
    // (the only one this value ever needs) before comparing against
    // uninstall-customaction.rs's raw-string (`r"..."`) spelling of the
    // same value, which carries a literal single backslash. Comparing
    // decoded VALUES, not raw source bytes, is the correct check here —
    // the two files are allowed to spell the same string differently.
    let logon_task_name = loginitem_src[start..start + end].replace("\\\\", "\\");

    assert!(
        uninstall_src.contains(&logon_task_name),
        "packaging/windows/wix/uninstall-customaction.rs's LOGON_TASK_NAME \
         literal must match platform::windows::loginitem::LOGON_TASK_NAME's \
         decoded value exactly ({logon_task_name:?}) — the standalone \
         uninstall binary duplicates, and must stay byte-identical (in \
         value) to, that task name"
    );
}

#[test]
fn uninstall_customaction_never_calls_a_registry_or_credential_manager_api() {
    // Standing regression guard for this stream's own honest finding: the
    // uninstall binary must never fabricate a Credential Manager (or
    // registry) cleanup CALL — Stream-G's ratified scope means there is
    // nothing real for Control Tower to have written to Credential
    // Manager in the first place (see uninstall-customaction.rs's own
    // module doc), and HKLM is IT/MDM-managed, outside this app's write
    // authority in either direction. This checks for actual API-shaped
    // identifiers, not the bare word "HKLM" — the module doc legitimately
    // NAMES HKLM/Credential-Manager while explaining why this binary does
    // not touch them, and a substring-only check would trip on its own
    // correct documentation.
    let uninstall_src = read("packaging/windows/wix/uninstall-customaction.rs");
    for forbidden in [
        "RegOpenKey",
        "RegDeleteKey",
        "RegSetValue",
        "winreg",
        "CredentialManager",
        "CredWrite",
        "CredDelete",
        "keyring",
        "vaultcli",
        "wincred",
    ] {
        assert!(
            !uninstall_src.contains(forbidden),
            "the uninstall custom action must never call {forbidden} — \
             Control Tower itself never writes to Credential Manager \
             (Stream-G's ratified endpoint-reference-only scope) and never \
             writes to the registry beyond what WiX's own component removal \
             already handles, so there is nothing real for this binary to \
             clean up via either API"
        );
    }
}
