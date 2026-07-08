//! M9 Stream-J (task 79) — `verify_staple` must be macOS-ONLY (no
//! off-macOS stub compiled anywhere else), and `verify_pre_promote` must
//! be the single production entry point `updater::check`'s only real call
//! site uses — never `verify_staple` directly, off macOS. Source-scan,
//! matching this crate's existing fitness-test style; no Windows
//! toolchain exists on this machine to prove the Windows arm actually
//! runs.

use std::fs;
use std::path::Path;

fn read(relative: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(relative);
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

fn verify_rs() -> String {
    read("src/updater/verify.rs")
}

fn check_rs() -> String {
    read("src/updater/check.rs")
}

/// Strips every `///`/`//!` doc-comment line — several assertions below
/// check for the ABSENCE of a code construct, and this module's own doc
/// comments legitimately quote/discuss those exact constructs (e.g.
/// explaining what the pre-M9 stub used to look like, or what
/// `verify_authenticode` deliberately does NOT do) — a blind substring
/// scan would trip on correct documentation, not a real regression.
fn strip_doc_comments(src: &str) -> String {
    src.lines()
        .filter(|l| {
            let t = l.trim_start();
            !t.starts_with("///") && !t.starts_with("//!")
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// `verify_staple` must carry `#[cfg(target_os = "macos")]` immediately
/// before its definition, and there must be NO second `pub fn
/// verify_staple` definition anywhere in the file (the pre-M9
/// `#[cfg(not(target_os = "macos"))]` sibling stub this task removes).
#[test]
fn verify_staple_is_macos_only_with_no_off_macos_sibling() {
    let src = verify_rs();
    let occurrences: Vec<_> = src.match_indices("pub fn verify_staple(").collect();
    assert_eq!(
        occurrences.len(),
        1,
        "expected exactly one `pub fn verify_staple` definition (the pre-M9 \
         off-macOS stub must be removed, not merely shadowed)"
    );

    let (idx, _) = occurrences[0];
    let preceding = &src[..idx];
    // The line immediately before the fn signature's own doc-comment block
    // ends is where the #[cfg] attribute lives; scan the nearest non-blank,
    // non-doc-comment line above the fn.
    let attr_line = preceding
        .lines()
        .rev()
        .find(|l| !l.trim().is_empty() && !l.trim_start().starts_with("///"))
        .unwrap_or("");
    assert_eq!(
        attr_line.trim(),
        r#"#[cfg(target_os = "macos")]"#,
        "verify_staple must be gated #[cfg(target_os = \"macos\")] with no \
         off-macOS fallback — found {attr_line:?} immediately before it instead"
    );

    assert!(
        !strip_doc_comments(&src).contains(r#"#[cfg(not(target_os = "macos"))]"#),
        "no #[cfg(not(target_os = \"macos\"))] gate should remain as CODE \
         anywhere in verify.rs — the pre-M9 off-macOS verify_staple stub is \
         replaced by verify_pre_promote's own explicit fallback arm, not a \
         second stub under the old gate (doc-comment PROSE mentioning the \
         old gate, e.g. explaining history, is fine and is excluded here)"
    );
}

/// `verify_authenticode` (the Windows pre-promote check) must exist,
/// gated `#[cfg(windows)]`, and must never resolve `signtool` via a bare
/// `PATH` lookup.
#[test]
fn verify_authenticode_exists_and_never_uses_a_bare_signtool_lookup() {
    let src = verify_rs();
    assert!(
        src.contains("pub fn verify_authenticode("),
        "expected a verify_authenticode function (Windows Authenticode \
         pre-promote check, ADR-M9-004)"
    );
    assert!(
        !strip_doc_comments(&src).contains(r#"Command::new("signtool")"#),
        "verify_authenticode must never resolve signtool via a bare PATH \
         lookup in CODE — it must require an absolute path via \
         SIGNTOOL_PATH_ENV (a doc comment merely explaining this rule is \
         fine and is excluded here)"
    );
}

/// `verify_pre_promote` must exist with three cfg arms: macOS (delegates
/// to verify_staple), windows (delegates to verify_authenticode), and a
/// fail-closed fallback for every other target.
#[test]
fn verify_pre_promote_has_all_three_cfg_arms() {
    let src = verify_rs();
    let count = src.matches("pub fn verify_pre_promote(").count();
    assert_eq!(
        count, 3,
        "expected exactly three verify_pre_promote definitions (macOS / \
         windows / fallback cfg arms)"
    );
    assert!(src.contains(r#"#[cfg(target_os = "macos")]"#));
    assert!(src.contains("#[cfg(windows)]"));
    assert!(src.contains(r#"#[cfg(not(any(target_os = "macos", windows)))]"#));
}

/// `updater::check`'s single production call site must use
/// `verify::verify_pre_promote`, never `verify::verify_staple` directly —
/// otherwise the Windows arm this task adds would be dead, uncalled code.
#[test]
fn check_rs_production_call_site_uses_verify_pre_promote_not_verify_staple_directly() {
    let src = check_rs();
    assert!(
        src.contains("verify::verify_pre_promote"),
        "expected updater::check's apply_update_at to call \
         verify::verify_pre_promote — the platform-neutral dispatcher, \
         never verify::verify_staple directly (which would leave the \
         Windows Authenticode path uncalled, dead code)"
    );
    // `verify::verify_staple` may still be MENTIONED in doc comments/prose
    // (explaining what the dispatcher does on macOS), but must never appear
    // as a bare function-call argument to apply_update_with.
    assert!(
        !src.contains("apply_update_with(fetcher.as_ref(), &url, &layout, verify::verify_staple)"),
        "apply_update_with must never be called with verify::verify_staple \
         directly at the production call site"
    );
}
