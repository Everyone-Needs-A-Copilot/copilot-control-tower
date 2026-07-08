//! **FF-M5-6 / FF-M5-7** — the `.mobileconfig` generator (M5/S4,
//! `.copilot/wp/30.md`) must emit the reader's EXACT domain (closing
//! G-M5-1) and must never emit a secret value (invariant #6). Also closes
//! the loop on the checked-in golden fixture: the fixture used for the
//! drift check and the "ready-to-upload" packaging deliverable must stay
//! byte-identical, and both must be `plutil -lint` clean (asserted here at
//! the structural level `cargo test` alone can check — the actual `plutil
//! -lint` shell invocation is run separately, as documented in the S4
//! summary; this test cannot shell out to a macOS-only binary from a
//! portable `cargo test` run).

use copilot_control_tower_lib::managed::keys::{self, ManagedKey};
use copilot_control_tower_lib::mobileconfig::generator::{
    generate, generator_domain, ManagedValue, MobileConfigInputs,
};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("src-tauri has a parent (repo root)")
        .to_path_buf()
}

/// The SAME inputs `examples/gen_mobileconfig_fixture.rs` uses — duplicated
/// here (not imported from the example, since `examples/` binaries aren't
/// importable as a library) so this test can regenerate the expected output
/// independently and compare it byte-for-byte against the checked-in golden
/// fixture, exactly matching `dev_fixtures_in_sync.rs`'s established drift
/// pattern for this crate.
fn sample_inputs() -> MobileConfigInputs {
    let mut values = HashMap::new();
    values.insert("OrgSlug", ManagedValue::Str("acme-corp".to_string()));
    values.insert("Department", ManagedValue::Str("engineering".to_string()));
    values.insert(
        "EcosystemSeedURL",
        ManagedValue::Str("https://ecosystem.acme-corp.example/ecosystem.yml".to_string()),
    );
    values.insert(
        "GitHubHost",
        ManagedValue::Str("github.acme-corp.example".to_string()),
    );
    values.insert("AuthMode", ManagedValue::Str("ssh-work".to_string()));
    values.insert("Host", ManagedValue::Str("managed-fleet".to_string()));
    values.insert(
        "FoundationMirror",
        ManagedValue::Str("https://mirror.acme-corp.example/foundation".to_string()),
    );
    values.insert(
        "UpdateFeedURL",
        ManagedValue::Str("https://updates.acme-corp.example/latest.json".to_string()),
    );
    values.insert("UpdateChannel", ManagedValue::Str("stable".to_string()));
    values.insert("AllowSelfUpdate", ManagedValue::Bool(true));
    values.insert("DisableWizard", ManagedValue::Bool(true));
    values.insert("Deprovisioned", ManagedValue::Bool(false));
    values.insert(
        "AdminContact",
        ManagedValue::Str("it-help@acme-corp.example".to_string()),
    );
    values.insert(
        "SharedSecretStoreURL",
        ManagedValue::Str("https://secrets.acme-corp.example/controltower".to_string()),
    );
    values.insert(
        "SharedSecretStoreTier",
        ManagedValue::Str("org".to_string()),
    );
    values.insert("LoginItemManaged", ManagedValue::Bool(true));

    MobileConfigInputs {
        org_display_name: "Acme Corp".to_string(),
        payload_identifier_prefix: "com.acmecorp.controltower-profile".to_string(),
        values,
        include_login_item_payload: true,
        include_notifications_payload: true,
        root_uuid: "a1b2c3d4-0000-4000-8000-000000000001".to_string(),
        preferences_uuid: "a1b2c3d4-0000-4000-8000-000000000002".to_string(),
        login_item_uuid: "a1b2c3d4-0000-4000-8000-000000000003".to_string(),
        notifications_uuid: "a1b2c3d4-0000-4000-8000-000000000004".to_string(),
    }
}

// -- FF-M5-6: generator_domain == reader domain --------------------------

#[test]
fn generator_domain_equals_the_managed_forced_reader_domain_fitness_ff_m5_6() {
    assert_eq!(
        generator_domain(),
        keys::APPLICATION_ID,
        "the .mobileconfig generator's emitted domain MUST equal managed::forced's reader \
         domain — a mismatch here would mean every generated profile silently writes to a \
         domain the app never reads (G-M5-1)"
    );
}

#[test]
fn generator_domain_never_matches_the_doc_only_stale_domain() {
    assert_ne!(generator_domain(), "dev.enac.controltower");
}

#[test]
fn the_checked_in_golden_fixture_uses_the_readers_exact_domain() {
    let fixture = fs::read_to_string(
        repo_root().join("src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig"),
    )
    .expect("read the golden fixture — run `cargo run --example gen_mobileconfig_fixture`");
    assert!(
        fixture.contains(&format!("<key>{}</key>", keys::APPLICATION_ID)),
        "the golden fixture must carry the reader's exact domain as the mcx_preference_settings key"
    );
    assert!(!fixture.contains("dev.enac.controltower"));
}

// -- FF-M5-7: no secret is ever emitted -----------------------------------

/// The same crude-but-effective scan `managed::keys`'s own
/// `no_entry_carries_anything_that_looks_like_a_literal_secret_value` test
/// uses, applied here to the checked-in golden fixture's REAL emitted bytes
/// — the second, integration-level layer on top of `generator`'s own
/// unit-level `looks_like_a_secret` guard (which runs at generation time,
/// before any XML is written).
#[test]
fn the_checked_in_golden_fixture_carries_no_secret_shaped_material_fitness_ff_m5_7() {
    let fixture = fs::read_to_string(
        repo_root().join("src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig"),
    )
    .expect("read the golden fixture");
    let lower = fixture.to_ascii_lowercase();
    for needle in [
        "sk-",
        "ghp_",
        "-----begin",
        "://user:",
        "aws_secret",
        "akia",
    ] {
        assert!(
            !lower.contains(needle),
            "golden fixture contains a secret-shaped needle {needle:?} — FF-M5-7 violation"
        );
    }
}

#[test]
fn generate_refuses_before_writing_any_xml_when_a_value_is_secret_shaped() {
    let mut inputs = sample_inputs();
    inputs.values.insert(
        "AdminContact",
        ManagedValue::Str("ghp_1234567890abcdefghijklmnopqrstuvwxyz".to_string()),
    );
    let result = generate(&inputs);
    assert!(
        result.is_err(),
        "FF-M5-7: a secret-shaped value must refuse generation, never be silently emitted"
    );
}

#[test]
fn every_managed_key_registry_entry_the_sample_org_did_not_set_is_absent_from_output() {
    // Belt-and-suspenders alongside `generator`'s own
    // `missing_keys`/`generate_iterates_the_frozen_registry...` unit tests:
    // confirms from the OUTSIDE (reading the real golden fixture bytes,
    // not calling the generator directly) that a key with no supplied org
    // value truly never appears, rather than e.g. appearing as an empty
    // string.
    let fixture = fs::read_to_string(
        repo_root().join("src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig"),
    )
    .expect("read the golden fixture");
    let inputs = sample_inputs();
    let set_keys: std::collections::HashSet<&str> = inputs.values.keys().copied().collect();

    let unset: Vec<&ManagedKey> = keys::MANAGED_KEYS
        .iter()
        .filter(|k| !set_keys.contains(k.name))
        .collect();
    assert!(
        !unset.is_empty(),
        "expected the sample org to leave at least one key unset"
    );

    for key in unset {
        assert!(
            !fixture.contains(&format!("<key>{}</key>", key.name)),
            "key {:?} was never supplied a value for the sample org but appears in the \
             generated fixture anyway",
            key.name
        );
    }
}

// -- Golden fixture drift + packaging/fixtures parity ---------------------

#[test]
fn golden_fixture_matches_what_the_real_generator_produces_right_now() {
    let inputs = sample_inputs();
    let expected = generate(&inputs).expect("sample org values must generate cleanly");

    let fixture_path =
        repo_root().join("src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig");
    let actual = fs::read_to_string(&fixture_path).unwrap_or_else(|e| {
        panic!(
            "missing golden fixture {} ({e}) — run `cargo run --example gen_mobileconfig_fixture`",
            fixture_path.display()
        )
    });
    assert_eq!(
        actual, expected,
        "src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig is stale — run \
         `cargo run --example gen_mobileconfig_fixture`"
    );
}

#[test]
fn packaging_deliverable_is_byte_identical_to_the_test_fixture() {
    let fixture_path =
        repo_root().join("src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig");
    let packaging_path = repo_root().join("packaging/mobileconfig/sample-acme-corp.mobileconfig");

    let fixture = fs::read_to_string(&fixture_path).unwrap_or_else(|e| {
        panic!(
            "read {}: {e} — run `cargo run --example gen_mobileconfig_fixture`",
            fixture_path.display()
        )
    });
    let packaging = fs::read_to_string(&packaging_path).unwrap_or_else(|e| {
        panic!(
            "read {}: {e} — run `cargo run --example gen_mobileconfig_fixture`",
            packaging_path.display()
        )
    });
    assert_eq!(
        fixture, packaging,
        "the packaging/mobileconfig/ deliverable and the src-tauri test fixture must stay \
         byte-identical — run `cargo run --example gen_mobileconfig_fixture` to resync"
    );
}

#[test]
fn golden_fixture_is_well_formed_xml_with_a_plist_root() {
    let fixture = fs::read_to_string(
        repo_root().join("src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig"),
    )
    .expect("read the golden fixture");
    assert!(fixture.starts_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"));
    assert!(fixture.contains("<plist version=\"1.0\">"));
    assert!(fixture.trim_end().ends_with("</plist>"));
    // Coarse tag-balance check (cheap, dependency-free — a real
    // `plutil -lint` pass is the authoritative check, run separately as a
    // shell step since `cargo test` must stay portable and this repo
    // otherwise avoids pulling in an XML parser for one artifact shape,
    // matching `fitness_watchdog_plist.rs`'s identical precedent).
    let opens = fixture.matches("<dict>").count();
    let closes = fixture.matches("</dict>").count();
    assert_eq!(opens, closes, "unbalanced <dict>/</dict> tags");
    let array_opens = fixture.matches("<array>").count();
    let array_closes = fixture.matches("</array>").count();
    assert_eq!(
        array_opens, array_closes,
        "unbalanced <array>/</array> tags"
    );
}
