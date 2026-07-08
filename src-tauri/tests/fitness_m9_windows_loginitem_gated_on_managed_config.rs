//! M9/Stream-E (task 74, ADR-M5-004's Windows counterpart) — the Windows
//! logon-item's `register()` must be GATED on the shared managed-config
//! decision (`crate::loginitem::decide_enablement`), never an unconditional
//! scheduled-task (or Run-key) write. There is no Windows toolchain on this
//! machine, so — same style as `fitness_m9_platform_windows_cfg_gated.rs`
//! and `fitness_m9_windows_cli_path_no_path_env.rs` — this is a cheap,
//! dependency-free source-text scan, run for real on this macOS host.

use std::fs;
use std::path::Path;

fn loginitem_source() -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("platform")
        .join("windows")
        .join("loginitem.rs");
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

/// Extracts the `fn register` method body's source text — from the `fn
/// register` signature up to (but not including) the next `fn ` at the same
/// indentation this crate's own methods use, which in every implementation
/// of this trait in this file is `fn unregister`.
fn register_fn_body(src: &str) -> &str {
    let start = src
        .find("fn register(")
        .expect("expected a `fn register(` in platform/windows/loginitem.rs");
    let after_start = &src[start..];
    let end = after_start
        .find("fn unregister(")
        .expect("expected `fn register` to be followed by `fn unregister` in the same impl block");
    &after_start[..end]
}

/// The core invariant: `register()` must consult the shared enablement
/// decision (`decide_enablement`/`should_register`) BEFORE ever calling the
/// mutating scheduled-task-creation helper (`create_task_from_xml`) — an
/// unconditional call to the latter with no gate at all is exactly the
/// "user-toggle a Bob can defeat... except this one can't even be turned
/// off by a managed `LoginItemManaged=false` fleet fact" regression this
/// test exists to catch.
#[test]
fn register_consults_decide_enablement_before_creating_the_task_fitness_m9() {
    let src = loginitem_source();
    let body = register_fn_body(&src);

    let decide_idx = body.find("decide_enablement").unwrap_or_else(|| {
        panic!(
            "expected platform/windows/loginitem.rs's register() to call \
             crate::loginitem::decide_enablement() — found no reference to `decide_enablement` \
             in its body"
        )
    });
    let should_register_idx = body.find("should_register").unwrap_or_else(|| {
        panic!(
            "expected register() to gate on LoginItemEnablement::should_register() — found no \
             reference to `should_register` in its body"
        )
    });
    let create_task_idx = body.find("create_task_from_xml").unwrap_or_else(|| {
        panic!(
            "expected register() to eventually call super::schtasks::create_task_from_xml — \
             found no reference to `create_task_from_xml` in its body"
        )
    });

    assert!(
        decide_idx < create_task_idx,
        "register() must consult decide_enablement() BEFORE calling create_task_from_xml — the \
         gate must run first, not after (or never)"
    );
    assert!(
        should_register_idx < create_task_idx,
        "register() must check should_register() BEFORE calling create_task_from_xml — the gate \
         must run first, not after (or never)"
    );
}

/// This module must never reimplement forced-domain reading itself (that is
/// Stream-D's `windows::forced`/`PlatformForcedConfig` job) — it must
/// consume the SAME shared `decide_enablement()` function macOS's
/// `loginitem::mod` already uses, never a second, independently-spelled
/// registry/forced-config read inlined into this file.
#[test]
fn loginitem_never_reads_the_registry_forced_policy_key_directly_fitness_m9() {
    let src = loginitem_source();
    // Deliberately checks for actual registry-crate usage (`winreg`/
    // `RegKey`), not the word "Policies" in prose — this file's own module
    // doc legitimately discusses the forced `HKLM\...\Policies` domain by
    // name when explaining WHY it defers to Stream-D rather than
    // reimplementing that read; banning the word itself would ban the
    // explanation along with the code.
    assert!(
        !src.contains("winreg") && !src.contains("RegKey"),
        "platform/windows/loginitem.rs must not reimplement forced-domain/registry reading — it \
         must consume crate::loginitem::decide_enablement() (which itself reuses \
         crate::managed::forced) rather than reading the registry (Stream-D's job) directly"
    );
}

/// `unregister()` must remain unconditional (never gated) — mirrors
/// `loginitem::mod::remove`'s own "the uninstall path must never register,
/// always removes" contract, checked here as a companion assertion so a
/// future edit can't accidentally gate the removal path too and orphan a
/// task on an explicit `ManagedDisabled` -> re-`ManagedEnabled` transition
/// mid-session.
#[test]
fn unregister_is_never_gated_on_decide_enablement_fitness_m9() {
    let src = loginitem_source();
    let start = src
        .find("fn unregister(")
        .expect("expected a `fn unregister(` in platform/windows/loginitem.rs");
    let after_start = &src[start..];
    let end = after_start
        .find("fn status(")
        .expect("expected `fn unregister` to be followed by `fn status` in the same impl block");
    let body = &after_start[..end];
    assert!(
        !body.contains("decide_enablement") && !body.contains("should_register"),
        "unregister() must be unconditional -- it must never consult decide_enablement()/\
         should_register(), matching loginitem::mod::remove's own unconditional contract"
    );
}
