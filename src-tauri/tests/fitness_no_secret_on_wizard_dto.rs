//! M3/S1 fitness function (`.copilot/wp/15.md` §4 fitness function 2,
//! invariant #6): no field on any wizard IPC DTO may carry a
//! token/secret/credential — the sign-in device flow (S3) hands the CLI the
//! keychain write; the app only ever relays `user_code`/`verification_uri`/
//! terminal `status`.
//!
//! A `syn`-based AST walk (dev-dependency only, same tool
//! `tests/fitness_no_fabricated_healthy.rs` uses for its AST detector) over
//! every `struct`/`enum` field declared in `src/wizard/dto.rs` — the ONE file
//! that owns the wizard's wire DTOs (`WizardState`, `WizardStep`,
//! `SigninState`, `SigninStatus`). Scanning the struct/enum *definitions*
//! rather than a serialized JSON instance is deliberately more conservative
//! than a runtime round-trip check: a runtime check can only ever prove "the
//! fields I happened to populate are clean", never "no such field exists at
//! all" — this test proves the latter, and would catch a forbidden field
//! even if no test ever constructed a value that populated it.

use std::fs;
use std::path::Path;

const FORBIDDEN_SUBSTRINGS: [&str; 6] = [
    "token",
    "secret",
    "credential",
    "password",
    "keychain",
    "access_key",
];

fn field_name_is_forbidden(ident: &str) -> Option<&'static str> {
    let lower = ident.to_lowercase();
    FORBIDDEN_SUBSTRINGS
        .into_iter()
        .find(|needle| lower.contains(needle))
}

fn collect_struct_and_enum_field_idents(file: &syn::File) -> Vec<String> {
    let mut idents = Vec::new();
    for item in &file.items {
        match item {
            syn::Item::Struct(s) => {
                for field in &s.fields {
                    if let Some(ident) = &field.ident {
                        idents.push(ident.to_string());
                    }
                }
            }
            syn::Item::Enum(e) => {
                for variant in &e.variants {
                    for field in &variant.fields {
                        if let Some(ident) = &field.ident {
                            idents.push(ident.to_string());
                        }
                    }
                }
            }
            _ => {}
        }
    }
    idents
}

#[test]
fn no_wizard_dto_field_carries_a_secret_bearing_name() {
    let dto_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("wizard")
        .join("dto.rs");
    let raw = fs::read_to_string(&dto_path)
        .unwrap_or_else(|e| panic!("read {}: {e}", dto_path.display()));
    let parsed = syn::parse_file(&raw)
        .unwrap_or_else(|e| panic!("syn::parse_file failed on {}: {e}", dto_path.display()));

    let idents = collect_struct_and_enum_field_idents(&parsed);
    assert!(
        !idents.is_empty(),
        "expected to find at least one struct/enum field in {}",
        dto_path.display()
    );

    let offenders: Vec<(String, &'static str)> = idents
        .into_iter()
        .filter_map(|ident| field_name_is_forbidden(&ident).map(|needle| (ident, needle)))
        .collect();

    assert!(
        offenders.is_empty(),
        "found a secret-bearing field name on a wizard DTO in {}: {offenders:?} — the sign-in \
         seam (S3) may only ever surface user_code/verification_uri/status; the CLI writes the \
         keychain directly and the app must never hold a token (invariant #6)",
        dto_path.display()
    );
}

/// Companion check: the sign-in DTO's field SET is exactly the frozen render
/// shape — `status`, `user_code`, `verification_uri` — no more, no less. A
/// narrower, structural version of the substring scan above: even a field
/// name that dodges every forbidden substring (e.g. a hypothetical `blob` or
/// `payload`) would still be caught here, because this asserts the *closed*
/// set rather than an open deny-list.
#[test]
fn signin_state_has_exactly_the_frozen_render_fields() {
    let dto_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("wizard")
        .join("dto.rs");
    let raw = fs::read_to_string(&dto_path)
        .unwrap_or_else(|e| panic!("read {}: {e}", dto_path.display()));
    let parsed = syn::parse_file(&raw)
        .unwrap_or_else(|e| panic!("syn::parse_file failed on {}: {e}", dto_path.display()));

    let mut found = false;
    for item in &parsed.items {
        if let syn::Item::Struct(s) = item {
            if s.ident == "SigninState" {
                found = true;
                let mut names: Vec<String> = s
                    .fields
                    .iter()
                    .filter_map(|f| f.ident.as_ref().map(|i| i.to_string()))
                    .collect();
                names.sort();
                assert_eq!(
                    names,
                    vec![
                        "status".to_string(),
                        "user_code".to_string(),
                        "verification_uri".to_string(),
                    ],
                    "SigninState's field set drifted from the frozen render shape"
                );
            }
        }
    }
    assert!(found, "expected to find a `SigninState` struct in dto.rs");
}
