//! Dev-tool (M7/S6, `.copilot/wp/43.md` task 65): regenerates the checked-in
//! golden `ecosystem.yml` seed fixture from the REAL `admin::seed::generate`
//! pipeline, for a fictional org ("Acme Corp") — mirrors
//! `gen_mobileconfig_fixture.rs`'s own precedent so the fixture can never
//! hand-drift from what the generator actually produces.
//!
//! Run after any change to `admin::seed`:
//!
//! ```sh
//! cargo run --example gen_seed_fixture
//! ```

use copilot_control_tower_lib::admin::seed::{
    generate, DepartmentSpec, EcosystemSeed, FoundationPin, ProductSpec, TelemetrySpec, Topology,
    ECOSYSTEM_SEED_SCHEMA_VERSION,
};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

/// The SAME sample values `tests/fitness_m7_seed_fixture_drift.rs` uses —
/// duplicated there (not imported from this example, since `examples/`
/// binaries aren't importable as a library) so that test can regenerate the
/// expected output independently and compare it byte-for-byte against the
/// checked-in golden fixture below.
fn sample_seed() -> EcosystemSeed {
    let mut products = BTreeMap::new();
    products.insert(
        "claude".to_string(),
        ProductSpec {
            enabled: true,
            foundation: Some("^5.14.0".to_string()),
            topology: Topology::Separate,
        },
    );
    products.insert(
        "knowledge".to_string(),
        ProductSpec {
            enabled: true,
            foundation: Some("^2.3.0".to_string()),
            topology: Topology::Separate,
        },
    );
    products.insert(
        "cli".to_string(),
        ProductSpec {
            enabled: false,
            foundation: None,
            topology: Topology::Separate,
        },
    );

    EcosystemSeed {
        version: ECOSYSTEM_SEED_SCHEMA_VERSION,
        org: "acme-corp".to_string(),
        host: "github.com".to_string(),
        api_base: "https://api.github.com".to_string(),
        ssh_host: "github.com".to_string(),
        foundation: FoundationPin {
            owner: "Everyone-Needs-A-Copilot".to_string(),
            mirror: None,
            root_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIQfoundationsamplekeyonly".to_string(),
            key_set: vec![
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIQfoundationsamplekeyonly".to_string(),
            ],
        },
        auth: "gh-device".to_string(),
        products,
        departments: vec![
            DepartmentSpec {
                slug: "finance".to_string(),
                renamed_from: vec![],
                lead: "@acme-corp/finance-leads".to_string(),
            },
            DepartmentSpec {
                slug: "engineering".to_string(),
                renamed_from: vec!["fin-eng".to_string()],
                lead: "@acme-corp/eng-leads".to_string(),
            },
        ],
        policy_signers: vec![
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIQsecuritysamplekeyonly".to_string(),
        ],
        telemetry: TelemetrySpec::default(),
    }
}

fn main() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));

    let seed = sample_seed();
    let yaml = generate(&seed).expect("sample org values must never be secret-shaped");

    let fixtures_dir = manifest_dir.join("fixtures").join("seed");
    fs::create_dir_all(&fixtures_dir)
        .unwrap_or_else(|e| panic!("create {}: {e}", fixtures_dir.display()));
    let fixtures_path = fixtures_dir.join("sample-acme-corp.ecosystem.yml");
    fs::write(&fixtures_path, &yaml)
        .unwrap_or_else(|e| panic!("write {}: {e}", fixtures_path.display()));

    println!(
        "wrote {} bytes to:\n  {}",
        yaml.len(),
        fixtures_path.display()
    );
}
