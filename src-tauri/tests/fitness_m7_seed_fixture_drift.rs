//! Fixture-drift guard (M7/S6, `.copilot/wp/43.md` task 65): the checked-in
//! golden `fixtures/seed/sample-acme-corp.ecosystem.yml` must always be
//! byte-identical to what `admin::seed::generate` produces for the SAME
//! sample inputs `examples/gen_seed_fixture.rs` uses — mirroring
//! `tests/fitness_m5_generator_domain_and_no_secrets.rs`'s own drift-check
//! pattern for the `.mobileconfig` golden fixture. A future edit to
//! `admin::seed` that silently changes the emitted shape without
//! regenerating the fixture (`cargo run --example gen_seed_fixture`) fails
//! this test rather than shipping an out-of-sync example artifact.

use copilot_control_tower_lib::admin::seed::{
    generate, DepartmentSpec, EcosystemSeed, FoundationPin, ProductSpec, TelemetrySpec, Topology,
    ECOSYSTEM_SEED_SCHEMA_VERSION,
};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("src-tauri has a parent (repo root)")
        .to_path_buf()
}

/// The SAME inputs `examples/gen_seed_fixture.rs` uses — duplicated here
/// (not imported from the example, since `examples/` binaries aren't
/// importable as a library) so this test can regenerate the expected
/// output independently and compare it byte-for-byte against the checked-in
/// golden fixture.
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

#[test]
fn checked_in_golden_seed_fixture_matches_the_real_generator_byte_for_byte() {
    let expected = generate(&sample_seed()).expect("sample seed must generate cleanly");

    let fixture_path = repo_root()
        .join("src-tauri")
        .join("fixtures")
        .join("seed")
        .join("sample-acme-corp.ecosystem.yml");
    let actual = std::fs::read_to_string(&fixture_path).unwrap_or_else(|e| {
        panic!(
            "read {}: {e} — run `cargo run --example gen_seed_fixture`",
            fixture_path.display()
        )
    });

    assert_eq!(
        actual, expected,
        "the checked-in fixture has drifted from admin::seed::generate's real output — \
         regenerate it with `cargo run --example gen_seed_fixture`"
    );
}

#[test]
fn golden_fixture_parses_back_to_the_exact_sample_seed() {
    let fixture_path = repo_root()
        .join("src-tauri")
        .join("fixtures")
        .join("seed")
        .join("sample-acme-corp.ecosystem.yml");
    let text = std::fs::read_to_string(&fixture_path)
        .unwrap_or_else(|e| panic!("read {}: {e}", fixture_path.display()));

    let parsed = copilot_control_tower_lib::admin::seed::parse(&text)
        .expect("checked-in fixture must parse as a valid ecosystem.yml seed");
    assert_eq!(parsed, sample_seed());
}
