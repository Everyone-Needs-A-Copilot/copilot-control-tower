//! Dev-tool (M5/S4, `.copilot/wp/30.md`): regenerates the checked-in golden
//! `.mobileconfig` fixture from the REAL `mobileconfig::generator::generate`
//! pipeline, for a fictional org ("Acme Corp") with fixed UUIDs — so the
//! fixture can never hand-drift from what the generator actually produces.
//! Writes the SAME bytes to two places on purpose:
//!
//! - `src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig` — the
//!   golden fixture `tests/fitness_m5_generator_domain_and_no_secrets.rs`'s
//!   drift check compares against.
//! - `packaging/mobileconfig/sample-acme-corp.mobileconfig` — the
//!   ready-to-upload deliverable artifact IT would actually look at
//!   (`architecture.md` §8.1 item 4). A second test in the same fitness
//!   file asserts these two copies are byte-identical, so they can never
//!   silently drift apart.
//!
//! Run after any change to `mobileconfig::generator`:
//!
//! ```sh
//! cargo run --example gen_mobileconfig_fixture
//! ```

use copilot_control_tower_lib::mobileconfig::generator::{
    generate, ManagedValue, MobileConfigInputs,
};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

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

fn main() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let repo_root = manifest_dir
        .parent()
        .expect("src-tauri has a parent (repo root)");

    let inputs = sample_inputs();
    let xml = generate(&inputs).expect("sample org values must never be secret-shaped");

    let fixtures_dir = manifest_dir.join("fixtures").join("mobileconfig");
    fs::create_dir_all(&fixtures_dir)
        .unwrap_or_else(|e| panic!("create {}: {e}", fixtures_dir.display()));
    let fixtures_path = fixtures_dir.join("sample-acme-corp.mobileconfig");
    fs::write(&fixtures_path, &xml)
        .unwrap_or_else(|e| panic!("write {}: {e}", fixtures_path.display()));

    let packaging_dir = repo_root.join("packaging").join("mobileconfig");
    fs::create_dir_all(&packaging_dir)
        .unwrap_or_else(|e| panic!("create {}: {e}", packaging_dir.display()));
    let packaging_path = packaging_dir.join("sample-acme-corp.mobileconfig");
    fs::write(&packaging_path, &xml)
        .unwrap_or_else(|e| panic!("write {}: {e}", packaging_path.display()));

    println!(
        "wrote {} bytes to:\n  {}\n  {}",
        xml.len(),
        fixtures_path.display(),
        packaging_path.display()
    );
}
