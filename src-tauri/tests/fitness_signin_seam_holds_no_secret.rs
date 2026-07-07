//! M3/S3 fitness function (`.copilot/wp/15.md` §2 S3, invariant #6): the
//! sign-in device-flow seam (`src/wizard/signin.rs`) — including its own
//! intermediate wire-parsing types, not just the DTOs `dto.rs` already
//! guards (`tests/fitness_no_secret_on_wizard_dto.rs`) — must never carry a
//! field or variable shaped like a token/secret/credential, and a real
//! `authorized` outcome must never carry a secret payload into the app.
//!
//! Two layers, matching the sibling DTO fitness test's own two-layer
//! approach:
//! 1. A `syn`-based AST walk over every `struct`/`enum` declared in
//!    `signin.rs` (including its private wire-parsing structs
//!    `CeremonyWire`/`PollWire` and its `SigninError`) — proving no such
//!    field exists AT ALL, not merely that no test happened to populate one.
//! 2. A live, end-to-end run of `begin_signin`/`poll_signin` against the
//!    deliberately-poisoned `authorized-leaked-field-adversarial` mock-cc
//!    scenario (`fixtures/wizard/README.md`'s documented negative-test
//!    fixture) — proving the one field the mock ever emits that looks like a
//!    secret (`access_token`) is dropped by the parser and never reaches the
//!    returned `SigninState`, in the value, its `Debug` text, or its
//!    serialized JSON.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use copilot_control_tower_lib::wizard::dto::SigninStatus;
use copilot_control_tower_lib::wizard::signin::{begin_signin, poll_signin, SigninError};

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

fn signin_rs_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("wizard")
        .join("signin.rs")
}

fn parse_signin_rs() -> syn::File {
    let raw = fs::read_to_string(signin_rs_path())
        .unwrap_or_else(|e| panic!("read {}: {e}", signin_rs_path().display()));
    syn::parse_file(&raw).unwrap_or_else(|e| {
        panic!(
            "syn::parse_file failed on {}: {e}",
            signin_rs_path().display()
        )
    })
}

/// Every field on every struct/enum declared anywhere in `signin.rs` —
/// `SigninSession`, `CeremonyWire`, `PollWire`, `SigninError`'s variants
/// (none have fields, but this collects them generically rather than
/// special-casing that), plus anything added here later. Scanning
/// definitions (not a runtime instance) proves absence, not just "the
/// fields this test happened to populate were clean" — same discipline as
/// `tests/fitness_no_secret_on_wizard_dto.rs`.
fn collect_struct_and_enum_field_idents(file: &syn::File) -> Vec<(String, String)> {
    let mut idents = Vec::new();
    for item in &file.items {
        match item {
            syn::Item::Struct(s) => {
                for field in &s.fields {
                    if let Some(ident) = &field.ident {
                        idents.push((s.ident.to_string(), ident.to_string()));
                    }
                }
            }
            syn::Item::Enum(e) => {
                for variant in &e.variants {
                    for field in &variant.fields {
                        if let Some(ident) = &field.ident {
                            idents.push((
                                format!("{}::{}", e.ident, variant.ident),
                                ident.to_string(),
                            ));
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
fn no_signin_seam_type_has_a_secret_bearing_field_name() {
    let parsed = parse_signin_rs();
    let idents = collect_struct_and_enum_field_idents(&parsed);
    assert!(
        !idents.is_empty(),
        "expected to find at least one struct/enum field in {}",
        signin_rs_path().display()
    );

    let offenders: Vec<(String, String, &'static str)> = idents
        .into_iter()
        .filter_map(|(owner, ident)| {
            field_name_is_forbidden(&ident).map(|needle| (owner, ident, needle))
        })
        .collect();

    assert!(
        offenders.is_empty(),
        "found a secret-bearing field name in the sign-in seam ({}): {offenders:?} — the CLI \
         writes the keychain directly (invariant #6); this file's ceremony/poll parsing and \
         session bookkeeping may only ever carry user_code/verification_uri/status/expires_in/\
         interval, never a token",
        signin_rs_path().display()
    );
}

/// `SigninError` specifically must stay fieldless — a narrower, structural
/// companion to the substring scan above: even a hypothetical field named
/// something that dodges every forbidden substring (e.g. `detail` or
/// `raw`) would still risk carrying a raw process/JSON string a secret
/// could hide inside. Fieldless variants make that categorically
/// impossible, not just unlikely.
#[test]
fn signin_error_variants_are_fieldless() {
    let parsed = parse_signin_rs();
    let mut found = false;
    for item in &parsed.items {
        if let syn::Item::Enum(e) = item {
            if e.ident == "SigninError" {
                found = true;
                for variant in &e.variants {
                    assert!(
                        matches!(variant.fields, syn::Fields::Unit),
                        "SigninError::{} carries data — every variant must stay fieldless so \
                         no dynamic/raw/secret content can ever be attached to a sign-in error",
                        variant.ident
                    );
                }
            }
        }
    }
    assert!(found, "expected to find a `SigninError` enum in signin.rs");
}

/// Companion check: `CeremonyWire`'s field SET is exactly the frozen
/// ceremony shape — `user_code`, `verification_uri`, `expires_in`,
/// `interval` — no more, no less, so a future edit can't quietly widen what
/// this module is willing to deserialize from the CLI.
#[test]
fn ceremony_wire_has_exactly_the_frozen_fields() {
    let parsed = parse_signin_rs();
    let mut found = false;
    for item in &parsed.items {
        if let syn::Item::Struct(s) = item {
            if s.ident == "CeremonyWire" {
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
                        "expires_in".to_string(),
                        "interval".to_string(),
                        "user_code".to_string(),
                        "verification_uri".to_string(),
                    ],
                    "CeremonyWire's field set drifted from the frozen device-flow SHAPE"
                );
            }
        }
    }
    assert!(
        found,
        "expected to find a `CeremonyWire` struct in signin.rs"
    );
}

/// `PollWire` must read ONLY `status` — this is the structural half of "an
/// unexpected wire field is dropped, never captured": if this struct ever
/// grew a second field, that field WOULD start being captured into a Rust
/// value, which is exactly the mechanism the adversarial live test below
/// depends on staying closed.
#[test]
fn poll_wire_reads_only_status() {
    let parsed = parse_signin_rs();
    let mut found = false;
    for item in &parsed.items {
        if let syn::Item::Struct(s) = item {
            if s.ident == "PollWire" {
                found = true;
                let names: Vec<String> = s
                    .fields
                    .iter()
                    .filter_map(|f| f.ident.as_ref().map(|i| i.to_string()))
                    .collect();
                assert_eq!(
                    names,
                    vec!["status".to_string()],
                    "PollWire must read exactly {{status}} — any additional field would start \
                     capturing wire data this seam has no business holding"
                );
            }
        }
    }
    assert!(found, "expected to find a `PollWire` struct in signin.rs");
}

// ---------------------------------------------------------------------
// Live proof: the adversarial fixture's leaked field never survives.
// ---------------------------------------------------------------------

static ENV_LOCK: Mutex<()> = Mutex::new(());

fn mock_cc() -> String {
    format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR"))
}

/// Drives the REAL public seam end-to-end, from an external crate (this
/// test binary links against `copilot_control_tower_lib` only — no
/// crate-internal access): initiate against the ordinary `authorized`
/// scenario to get a genuine `SigninSession`, then poll against the
/// deliberately-poisoned `authorized-leaked-field-adversarial` scenario
/// (`fixtures/wizard/README.md`) — an otherwise-normal `authorized` response
/// plus an extra `access_token":"FAKE-SYNTHETIC-NOT-A-REAL-TOKEN..."` field
/// the real CLI would never emit. Asserts the leaked field never reaches
/// the returned `SigninState` — not in its typed fields, not in its `Debug`
/// text, not in its serialized JSON — proving the no-secret guarantee holds
/// at the actual public API boundary, not merely inside signin.rs's own
/// in-crate tests.
#[test]
fn adversarial_leaked_field_never_survives_the_public_seam_end_to_end() {
    let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    // SAFETY: serialized by ENV_LOCK; this is the only test in this binary
    // touching these env vars, and this binary is its own OS process
    // (a separate `tests/*.rs` integration test file), so it cannot race
    // with the lib's own test binary's use of the same var names.
    unsafe {
        std::env::set_var("CT_CLI_PATH", mock_cc());
        std::env::set_var("CT_AUTH_SCENARIO", "authorized");
    }
    let session = begin_signin().expect("initiate should succeed against the mock seam");
    // SAFETY: serialized by ENV_LOCK.
    unsafe { std::env::set_var("CT_AUTH_SCENARIO", "authorized-leaked-field-adversarial") };
    let result = poll_signin(&session);
    // SAFETY: serialized by ENV_LOCK.
    unsafe {
        std::env::remove_var("CT_CLI_PATH");
        std::env::remove_var("CT_AUTH_SCENARIO");
    }

    let state = result.expect("the adversarial fixture still reports a real 'authorized'");
    assert_eq!(state.status, SigninStatus::Authorized);
    assert_eq!(state.user_code, None);
    assert_eq!(state.verification_uri, None);

    let debug = format!("{state:?}");
    assert!(
        !debug.contains("FAKE-SYNTHETIC"),
        "the adversarial fixture's synthetic token leaked into SigninState's Debug output: \
         {debug}"
    );
    assert!(!debug.to_lowercase().contains("access_token"));
    assert!(!debug.to_lowercase().contains("token"));

    let json = serde_json::to_string(&state).expect("SigninState serializes");
    assert!(!json.contains("FAKE-SYNTHETIC"));
    assert!(!json.contains("access_token"));
}

/// The public `SigninError` surface itself is usable/matchable from an
/// external crate without any crate-internal access — every variant a
/// caller must handle is public and (per the fieldless test above)
/// carries no data, which is part of the "no secret hides behind an
/// inaccessible type" guarantee.
#[test]
fn signin_error_variants_are_public_and_matchable_from_outside_the_crate() {
    let a = SigninError::CliUnavailable;
    let b = SigninError::MalformedResponse;
    assert_ne!(a, b);
    assert_eq!(a.to_string(), a.to_string());
}
