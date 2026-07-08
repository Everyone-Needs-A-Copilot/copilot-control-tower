//! M5/S5 fitness function (`.copilot/wp/30.md` task 48,
//! `credentials-and-boundary.md` §1.6.4, invariant #6): the managed
//! secret-store endpoint reader is a **reference reader, not a resolver**.
//!
//! Same cheap, dependency-free text-scan style every other fitness test in
//! this crate already uses (`fitness_m5_single_forced_boundary.rs`,
//! `fitness_m5_no_wipe_logic.rs`) — no call-graph analysis, no live network,
//! no real keychain.
//!
//! Two things this test asserts, both against
//! `src/managed/secret_store.rs`'s **production** source only
//! (`#[cfg(test)]` blocks stripped, matching `fitness_m5_no_wipe_logic.rs`'s
//! precedent, so a test fixture literal string can never trip these checks):
//!
//! 1. **No secret-VALUE field.** [`SecretStoreRef`] declares exactly two
//!    fields (`url`, `tier`) — never a field named `secret`, `token`,
//!    `password`, or `value`. A source-scan (not a `Debug`-format check,
//!    which only proves ONE instance's fields, not the type's declared
//!    shape) is the authoritative half of this guarantee; the unit-level
//!    `Debug`-format check lives alongside the module's own tests.
//! 2. **Reference reader, not a resolver.** This module never calls a
//!    keychain API (no `Security.framework`/`security_framework`/`keyring`/
//!    `SecItem*`) and never performs an HTTP/network fetch (no `reqwest`/
//!    `ureq`/raw socket call) — resolving a secret VALUE from the store at
//!    `requires_secret` time is the CLI's job
//!    (`credentials-and-boundary.md` §3), never this app's.

use std::fs;
use std::path::{Path, PathBuf};

fn secret_store_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("managed")
        .join("secret_store.rs")
}

/// Strips `//...` line comments and `/* ... */` block comments — identical
/// approach to every other fitness test in this crate.
fn strip_comments(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let bytes = src.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'/') {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
        } else if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'*') {
            i += 2;
            while i < bytes.len() && !(bytes[i] == b'*' && bytes.get(i + 1) == Some(&b'/')) {
                i += 1;
            }
            i += 2;
        } else {
            out.push(bytes[i] as char);
            i += 1;
        }
    }
    out
}

/// Removes every `#[cfg(test)] ... { ... }` item's body (brace-matched) —
/// identical logic to `fitness_m5_single_forced_boundary.rs`'s
/// `strip_cfg_test_blocks` (duplicated per this crate's "each fitness check
/// owns its own copy" convention). Needed so this module's own adversarial
/// test names/literals (which legitimately mention "secret"/"password"/
/// "token" as forbidden-needle strings, and "keyring"-shaped assertions)
/// never trip this test.
fn strip_cfg_test_blocks(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let marker = "#[cfg(test)]";
    let mut rest = src;
    while let Some(idx) = rest.find(marker) {
        out.push_str(&rest[..idx]);
        let after_marker = &rest[idx + marker.len()..];
        let brace_start = match after_marker.find('{') {
            Some(b) => b,
            None => {
                out.push_str(marker);
                rest = after_marker;
                continue;
            }
        };
        let body = &after_marker[brace_start..];
        let mut depth = 0i32;
        let mut end = None;
        for (pos, ch) in body.char_indices() {
            match ch {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        end = Some(pos + 1);
                        break;
                    }
                }
                _ => {}
            }
        }
        let end = end.unwrap_or(body.len());
        rest = &body[end..];
    }
    out.push_str(rest);
    out
}

fn production_source() -> String {
    let raw = fs::read_to_string(secret_store_path())
        .unwrap_or_else(|e| panic!("read {}: {e}", secret_store_path().display()));
    strip_cfg_test_blocks(&strip_comments(&raw))
}

/// **Invariant #6.** No field named `secret`, `token`, `password`, or
/// `value` (case-insensitive, as a struct-field-declaration shape
/// `<name>:`) appears anywhere in the module's production source — the DTO
/// this reader returns can only ever carry a reference (`url`, `tier`),
/// never a value.
#[test]
fn secret_store_module_declares_no_secret_value_field() {
    let src = production_source();
    let lower = src.to_ascii_lowercase();

    for forbidden in ["secret:", "token:", "password:", "value:"] {
        assert!(
            !lower.contains(forbidden),
            "src/managed/secret_store.rs's production source contains {forbidden:?} — this \
             module must carry an endpoint REFERENCE only (url + tier), never a secret value \
             (invariant #6)"
        );
    }
}

/// The DTO's declared field set is exactly `{url, tier}` — a positive
/// assertion (not just "no forbidden field") so a future field addition of
/// any OTHER shape still forces a deliberate re-read of this test.
#[test]
fn secret_store_ref_declares_exactly_url_and_tier() {
    let src = production_source();
    assert!(
        src.contains("pub struct SecretStoreRef"),
        "expected a SecretStoreRef struct in src/managed/secret_store.rs"
    );
    assert!(src.contains("pub url: String"));
    assert!(src.contains("pub tier: String"));
}

/// This module never calls a keychain API — resolving/caching a secret
/// VALUE (as opposed to reading an endpoint reference) is never this app's
/// job (`credentials-and-boundary.md` §3).
#[test]
fn secret_store_module_never_calls_a_keychain_api() {
    let src = production_source();
    for needle in [
        "Security.framework",
        "security_framework",
        "SecItem",
        "keyring::",
        "find-generic-password",
    ] {
        assert!(
            !src.contains(needle),
            "src/managed/secret_store.rs unexpectedly references {needle:?} — this module is a \
             reference reader, never a keychain resolver"
        );
    }
}

/// This module never performs an HTTP/network fetch of its own — the CLI
/// owns the scoped, authenticated API read at `requires_secret` resolution
/// time (`credentials-and-boundary.md` §3); Control Tower "holds no store
/// credential itself" and, by extension, never dials the store.
#[test]
fn secret_store_module_never_performs_an_http_fetch() {
    let src = production_source();
    for needle in [
        "reqwest",
        "ureq::",
        "TcpStream",
        "std::net::",
        ".get(",
        ".post(",
    ] {
        assert!(
            !src.contains(needle),
            "src/managed/secret_store.rs unexpectedly references {needle:?} — this module is a \
             forced-domain reference reader, never an HTTP client"
        );
    }
}
