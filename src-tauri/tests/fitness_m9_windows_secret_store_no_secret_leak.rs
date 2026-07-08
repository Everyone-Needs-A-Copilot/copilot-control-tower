//! M9/Stream-G fitness function (task 76, invariant #6): the Windows
//! secret-store module is a reference reader, never a resolver — the
//! Windows sibling of `tests/fitness_m5_secretstore_reference_only.rs`.
//! Same cheap, dependency-free text-scan style (no call-graph analysis, no
//! live registry, no real Credential Manager) — runs on macOS, scanning
//! `src/platform/windows/secret_store.rs`'s **production** source only
//! (`#[cfg(test)]` blocks stripped, comments stripped).

use std::fs;
use std::path::{Path, PathBuf};

fn secret_store_rs_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("platform")
        .join("windows")
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
/// identical logic to `fitness_m5_secretstore_reference_only.rs`'s own
/// helper (duplicated per this crate's "each fitness check owns its own
/// copy" convention).
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
    let raw = fs::read_to_string(secret_store_rs_path())
        .unwrap_or_else(|e| panic!("read {}: {e}", secret_store_rs_path().display()));
    strip_cfg_test_blocks(&strip_comments(&raw))
}

/// No field named `secret`, `token`, `password`, or `value` (case
/// insensitive, as a struct-field-declaration shape `<name>:`) appears
/// anywhere in this module's production source — this file reuses
/// `SecretStoreRef` (`url` + `tier`) rather than declaring its own DTO;
/// this assertion guards against a future edit introducing a second,
/// looser-shaped struct here.
#[test]
fn windows_secret_store_declares_no_secret_value_field_fitness_m9() {
    let src = production_source();
    let lower = src.to_ascii_lowercase();
    for forbidden in ["secret:", "token:", "password:", "value:"] {
        assert!(
            !lower.contains(forbidden),
            "src/platform/windows/secret_store.rs's production source contains {forbidden:?} — \
             this module must carry an endpoint REFERENCE only (url + tier), never a secret \
             value (invariant #6)"
        );
    }
}

/// This module reuses `managed::secret_store::SecretStoreRef` rather than
/// declaring a second, independently-shaped DTO — a positive assertion so a
/// future accidental `pub struct SecretStoreRef` redefinition here (which
/// would silently fork the type) is caught immediately.
#[test]
fn windows_secret_store_reuses_the_shared_dto_fitness_m9() {
    let src = production_source();
    assert!(
        !src.contains("pub struct SecretStoreRef"),
        "src/platform/windows/secret_store.rs must reuse managed::secret_store::SecretStoreRef, \
         never declare its own — found a second struct definition"
    );
    assert!(
        src.contains("SecretStoreRef"),
        "expected this module to reference the shared SecretStoreRef type at all"
    );
}

/// This module never calls a keychain/Credential-Manager API and never
/// caches/resolves a secret VALUE — resolving a secret value is the CLI's
/// job (`credentials-and-boundary.md` §3: Control Tower's row reads "No
/// role"), never this app's, on any platform. Same needle set as
/// `fitness_m5_secretstore_reference_only.rs`'s macOS-side check, plus the
/// Windows-specific Credential Manager/DPAPI API names.
#[test]
fn windows_secret_store_never_calls_a_credential_manager_api_fitness_m9() {
    let src = production_source();
    for needle in [
        "keyring::",
        "CredWrite",
        "CredRead",
        "CredDelete",
        "CryptProtectData",
        "CryptUnprotectData",
        "find-generic-password",
    ] {
        assert!(
            !src.contains(needle),
            "src/platform/windows/secret_store.rs unexpectedly references {needle:?} — this \
             module is a reference reader, never a Credential Manager/DPAPI resolver (this \
             app's own scope, per platform::PlatformSecretStore's own doc and \
             credentials-and-boundary.md §3 — see this file's own module doc for the full \
             evidence trail)"
        );
    }
}

/// This module never performs an HTTP/network fetch of its own — same
/// discipline as the macOS module it ports (`managed::secret_store`).
#[test]
fn windows_secret_store_never_performs_an_http_fetch_fitness_m9() {
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
            "src/platform/windows/secret_store.rs unexpectedly references {needle:?} — this \
             module is a forced-domain reference reader, never an HTTP client"
        );
    }
}

/// This module reads through `super::forced` (Stream-D's ADR-M9-003 gated
/// reader) rather than re-implementing its own registry/enrollment logic —
/// a positive assertion that the two Windows streams' work is actually
/// wired together, not merely coexisting in the same directory.
#[test]
fn windows_secret_store_reads_through_the_forced_module_fitness_m9() {
    let src = production_source();
    assert!(
        src.contains("super::forced::forced_string") || src.contains("forced::forced_string"),
        "expected src/platform/windows/secret_store.rs to read the endpoint reference through \
         super::forced (Stream-D's HKLM + enrollment-gated reader), not a second, independent \
         registry read"
    );
}
