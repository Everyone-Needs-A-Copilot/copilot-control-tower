//! The Admin-mode `ecosystem.yml` seed generator (M7/S6, `.copilot/wp/43.md`
//! task 65, `architecture.md` §8.1 item 1: "Seed generator — authors the org
//! `ecosystem.yml`... No hand-written YAML"). Mirrors `mobileconfig::
//! generator`'s own shape: typed, structured Admin input -> a fail-closed
//! no-secret scan -> emitted text (YAML here, XML there).
//!
//! ## Where this seed shape came from (G-M7-7 — flagged, not code-frozen)
//!
//! See `admin`'s own module doc for the full provenance note. In short: the
//! fields below are a direct, evidence-based transcription of
//! `docs/10-reference/ecosystem-architecture.md` §4.2's worked YAML example
//! plus `docs/08-observability/observability.md` §6's `telemetry` block —
//! NOT an invented shape, but also not (yet) a shape any real `cc` code
//! parses today. Generate to this documented shape; do not treat it as an
//! owner-ratified contract.
//!
//! ## This module computes no ecosystem verdict (SOUL Case Law, invariant #1)
//!
//! [`generate`]/[`validate_shape`]/[`validate_no_secrets`] check only "is
//! this seed well-formed and secret-free" — never anything about whether
//! the org/departments/keys are REAL (that is `cc derive`'s job, and
//! `preflight`'s own job for the externally-verifiable facts, via
//! caller-supplied [`super::preflight::PreflightConfig`] facts, never a
//! network call this crate makes itself).
//!
//! ## No secret ever enters the seed (invariant #6, FF-M5-7's sibling)
//!
//! [`generate`] reuses [`crate::mobileconfig::generator::looks_like_a_secret`]
//! — the SAME fail-closed heuristic scan the M5 `.mobileconfig` generator
//! uses — rather than a second, independently-drifting copy. Every string
//! value reachable from an [`EcosystemSeed`] is scanned before any YAML is
//! emitted; a secret-shaped value refuses generation. This is a
//! defense-in-depth backstop (the seed's own `root_key`/`key_set`/
//! `policy_signers` are meant to carry PUBLIC keys only — a private key
//! accidentally pasted in is exactly the shape this catches), not the sole
//! guarantee that a real secret never enters `ecosystem.yml` — that is a
//! human-review + git-push-boundary discipline, same as every other
//! never-a-secret-in-git artifact this crate emits.

use std::collections::{BTreeMap, HashSet};

use serde::{Deserialize, Serialize};

use crate::mobileconfig::generator::looks_like_a_secret;

/// The `ecosystem.yml` schema version this generator emits — pinned so a
/// future breaking shape change is a visible diff to this constant, not a
/// silent drift (mirrors `telemetry::schema::FLEET_EVENT_SCHEMA_VERSION`'s
/// own "one named constant" discipline).
pub const ECOSYSTEM_SEED_SCHEMA_VERSION: u32 = 1;

/// The whole seed document — see the module doc for shape provenance.
/// Field order here IS the emitted YAML's field order (serde_yaml serializes
/// a named struct in declaration order, never alphabetically) — chosen to
/// match `ecosystem-architecture.md` §4.2's own worked example top to
/// bottom, so a human diffing generated output against that doc sees the
/// same shape.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EcosystemSeed {
    pub version: u32,
    pub org: String,
    /// `github.com`, or a GHES hostname (`architecture-fixes A-C5`).
    pub host: String,
    pub api_base: String,
    pub ssh_host: String,
    pub foundation: FoundationPin,
    /// `gh-device | ssh-work | gh-app:<slug>` — an auth MODE reference,
    /// never a credential value (the same discipline
    /// `settings::manifest::Layer::auth` already holds for the layer
    /// manifest's own `auth` field).
    pub auth: String,
    /// Keyed by product name (e.g. `claude`, `knowledge`, `cli`) — a
    /// `BTreeMap` rather than a `Vec<(String, ProductSpec)>` so the emitted
    /// YAML is deterministically (alphabetically) ordered regardless of the
    /// order an Admin-mode caller happened to insert products in.
    pub products: BTreeMap<String, ProductSpec>,
    #[serde(default)]
    pub departments: Vec<DepartmentSpec>,
    /// The security-team signer allow-list ("policy authority != push
    /// authority", `ecosystem-architecture.md` §4.2/§7) — PUBLIC keys only.
    pub policy_signers: Vec<String>,
    /// The analytics opt-in carrier (`observability.md` §6, G-M7-1) — OFF by
    /// default; see [`TelemetrySpec`]'s own doc.
    #[serde(default)]
    pub telemetry: TelemetrySpec,
}

/// `foundation:` — the pinned trust root + optional mirror
/// (`ecosystem-architecture.md` §4.2).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FoundationPin {
    pub owner: String,
    /// Self-hosted mirror URL if public `github.com` is firewalled
    /// (fixes A-C5). `None` means "use public github.com directly".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mirror: Option<String>,
    /// A PINNED, PUBLIC trust-root key (e.g. `ssh-ed25519 AAAA...`) — never
    /// a private key. [`validate_no_secrets`] still scans this defensively
    /// (see the module doc), but an ordinary public key never trips it.
    pub root_key: String,
    /// Dual-sign rollover set (`ecosystem-architecture.md` §4.2's
    /// `key_set`) — old + new PUBLIC keys during a rotation window.
    #[serde(default)]
    pub key_set: Vec<String>,
}

/// Whether a product's department content lives in a separate repo or a
/// subfolder of the org repo (`ecosystem-architecture.md` §4.2).
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "lowercase")]
pub enum Topology {
    /// The DEFAULT for every product — department content is confidential
    /// business data, and the repo is GitHub's only read boundary (direct
    /// citation of the doc's own comment on this field).
    #[default]
    Separate,
    /// A narrow, explicit opt-in reserved for genuinely non-confidential
    /// departmental content.
    Subfolder,
}

/// One entry in `products:` — keyed by product name in [`EcosystemSeed`].
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProductSpec {
    pub enabled: bool,
    /// A semver range (e.g. `^5.14.0`) the foundation tier is pinned to —
    /// only meaningful while `enabled`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub foundation: Option<String>,
    #[serde(default)]
    pub topology: Topology,
}

/// One entry in `departments:` (`ecosystem-architecture.md` §4.2).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DepartmentSpec {
    pub slug: String,
    /// Rename aliases — lets a department rename reconcile instead of
    /// 404-ing (fixes A-H10, B-M2).
    #[serde(default)]
    pub renamed_from: Vec<String>,
    pub lead: String,
}

/// The analytics-telemetry opt-in carrier (`observability.md` §6/§7.1's
/// G-M7-1 field). **OFF by default** (`Default` derives `enabled: false,
/// endpoint: None`) — matching the doc's "fail-closed on absence" rule: no
/// `telemetry.enabled: true` + `telemetry.endpoint` in a signed
/// `ecosystem.yml` means zero analytics bytes ever leave a fleet machine.
/// This generator never sets `enabled: true` unless the Admin-mode caller
/// explicitly constructs one that way — there is no default-on path.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct TelemetrySpec {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub endpoint: Option<String>,
}

/// Generation/validation was refused. Never carries the offending secret
/// value itself (mirrors `MobileConfigError`'s own discipline) — only a
/// field-path description or a plain-language shape problem.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SeedError {
    /// [`looks_like_a_secret`] flagged the value at this field path.
    SecretShapedValue(String),
    MissingOrg,
    MissingHost,
    /// At least one product must be declared, even if disabled.
    NoProductsDeclared,
    /// The capability policy needs at least one authorized signer key.
    NoPolicySigners,
    /// `telemetry.enabled: true` with no `telemetry.endpoint` set — the
    /// doc's own opt-in contract requires both together, never a dangling
    /// flag (mirrors `observability.md` §6's "fail-closed on absence" rule
    /// applied at generation time instead of only at read time).
    TelemetryEnabledWithoutEndpoint,
    DuplicateDepartmentSlug(String),
}

impl std::fmt::Display for SeedError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SeedError::SecretShapedValue(field) => write!(
                f,
                "refusing to generate this ecosystem.yml seed: the value at {field:?} looks \
                 like a credential/token, not a config value — a seed may only ever carry \
                 references/public keys/flags, never a secret (invariant #6)"
            ),
            SeedError::MissingOrg => write!(
                f,
                "this seed has no `org` — every ecosystem.yml needs an organization slug"
            ),
            SeedError::MissingHost => write!(
                f,
                "this seed has no `host` — every ecosystem.yml needs a GitHub host \
                 (github.com, or a GHES hostname)"
            ),
            SeedError::NoProductsDeclared => write!(
                f,
                "this seed declares no products — at least one product must be listed, \
                 even if disabled"
            ),
            SeedError::NoPolicySigners => write!(
                f,
                "this seed has no `policy_signers` — the capability policy needs at least \
                 one authorized signer key"
            ),
            SeedError::TelemetryEnabledWithoutEndpoint => write!(
                f,
                "this seed sets `telemetry.enabled: true` but no `telemetry.endpoint` — both \
                 are required together, or leave telemetry off"
            ),
            SeedError::DuplicateDepartmentSlug(slug) => write!(
                f,
                "department slug {slug:?} is declared more than once — every department slug \
                 must be unique"
            ),
        }
    }
}

impl std::error::Error for SeedError {}

/// Structural well-formedness, independent of the secret scan — "is this
/// seed shaped correctly" (never "is it real"; see the module doc). Reused
/// by [`validate`] and by `preflight::run_preflight`'s own `seed_well_formed`
/// check, so both surfaces apply the identical rule set.
pub fn validate_shape(seed: &EcosystemSeed) -> Result<(), SeedError> {
    if seed.org.trim().is_empty() {
        return Err(SeedError::MissingOrg);
    }
    if seed.host.trim().is_empty() {
        return Err(SeedError::MissingHost);
    }
    if seed.products.is_empty() {
        return Err(SeedError::NoProductsDeclared);
    }
    if seed.policy_signers.is_empty() {
        return Err(SeedError::NoPolicySigners);
    }
    if seed.telemetry.enabled && seed.telemetry.endpoint.is_none() {
        return Err(SeedError::TelemetryEnabledWithoutEndpoint);
    }
    let mut seen_slugs = HashSet::new();
    for dept in &seed.departments {
        if !seen_slugs.insert(dept.slug.clone()) {
            return Err(SeedError::DuplicateDepartmentSlug(dept.slug.clone()));
        }
    }
    Ok(())
}

/// Every string value reachable from `seed` that could carry a secret,
/// scanned via the SAME [`looks_like_a_secret`] heuristic
/// `mobileconfig::generator` uses — see the module doc's "no secret ever
/// enters the seed" section. Reused by [`validate`] and by
/// `preflight::run_preflight`'s own `no_secret_in_seed` check.
pub fn validate_no_secrets(seed: &EcosystemSeed) -> Result<(), SeedError> {
    let mut fields: Vec<(String, &str)> = vec![
        ("org".to_string(), seed.org.as_str()),
        ("host".to_string(), seed.host.as_str()),
        ("api_base".to_string(), seed.api_base.as_str()),
        ("ssh_host".to_string(), seed.ssh_host.as_str()),
        ("auth".to_string(), seed.auth.as_str()),
        (
            "foundation.owner".to_string(),
            seed.foundation.owner.as_str(),
        ),
        (
            "foundation.root_key".to_string(),
            seed.foundation.root_key.as_str(),
        ),
    ];
    if let Some(mirror) = &seed.foundation.mirror {
        fields.push(("foundation.mirror".to_string(), mirror.as_str()));
    }
    for (i, key) in seed.foundation.key_set.iter().enumerate() {
        fields.push((format!("foundation.key_set[{i}]"), key.as_str()));
    }
    for (i, signer) in seed.policy_signers.iter().enumerate() {
        fields.push((format!("policy_signers[{i}]"), signer.as_str()));
    }
    for (name, spec) in &seed.products {
        if let Some(foundation) = &spec.foundation {
            fields.push((format!("products.{name}.foundation"), foundation.as_str()));
        }
    }
    for dept in &seed.departments {
        fields.push((
            format!("departments.{}.slug", dept.slug),
            dept.slug.as_str(),
        ));
        fields.push((
            format!("departments.{}.lead", dept.slug),
            dept.lead.as_str(),
        ));
        for (i, alias) in dept.renamed_from.iter().enumerate() {
            fields.push((
                format!("departments.{}.renamed_from[{i}]", dept.slug),
                alias.as_str(),
            ));
        }
    }
    if let Some(endpoint) = &seed.telemetry.endpoint {
        fields.push(("telemetry.endpoint".to_string(), endpoint.as_str()));
    }

    for (path, value) in fields {
        if looks_like_a_secret(value) {
            return Err(SeedError::SecretShapedValue(path));
        }
    }
    Ok(())
}

/// Runs both [`validate_shape`] and [`validate_no_secrets`] — the full
/// gate [`generate`] applies before emitting anything.
pub fn validate(seed: &EcosystemSeed) -> Result<(), SeedError> {
    validate_shape(seed)?;
    validate_no_secrets(seed)
}

/// Generates the `ecosystem.yml` text for `seed`. Fail-closed: refuses
/// (never emits partial output) if [`validate`] finds any well-formedness
/// problem OR a secret-shaped value.
pub fn generate(seed: &EcosystemSeed) -> Result<String, SeedError> {
    validate(seed)?;
    // `serde_yaml::to_string` over an already-validated, plain-data struct
    // (no NaN floats, no non-string map keys) has no real failure mode this
    // crate needs to model as its own SeedError variant — `expect` here
    // documents that expectation rather than silently swallowing a
    // hypothetical serializer bug.
    Ok(serde_yaml::to_string(seed).expect("a validated EcosystemSeed always serializes to YAML"))
}

/// A seed that failed to parse as YAML at all — mirrors
/// `settings::manifest::ManifestParseError`'s own "plain language before
/// parser detail" framing.
#[derive(Debug, Clone, PartialEq)]
pub struct SeedParseError {
    pub message: String,
}

impl std::fmt::Display for SeedParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for SeedParseError {}

/// Parses `ecosystem.yml` text into the typed model. Does NOT run
/// [`validate`] — call that next (mirrors `settings::manifest::
/// parse_manifest`'s own parse/validate split); `preflight::run_preflight`
/// calls both in sequence as two distinct checks.
pub fn parse(text: &str) -> Result<EcosystemSeed, SeedParseError> {
    serde_yaml::from_str(text).map_err(|e| SeedParseError {
        message: format!(
            "This ecosystem.yml seed isn't valid YAML, so it can't be read: {e}. Check for a \
             missing colon, dash, or indentation."
        ),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
                root_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIQfoundationsamplekeyonly"
                    .to_string(),
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

    // -- generation happy path -------------------------------------------

    #[test]
    fn generate_succeeds_for_a_well_formed_seed() {
        let seed = sample_seed();
        let yaml = generate(&seed).expect("well-formed seed must generate cleanly");
        assert!(yaml.contains("org: acme-corp"));
        assert!(yaml.contains("policy_signers"));
    }

    #[test]
    fn generated_yaml_round_trips_back_to_an_identical_seed() {
        let seed = sample_seed();
        let yaml = generate(&seed).expect("generate");
        let reparsed = parse(&yaml).expect("generated YAML must parse");
        assert_eq!(seed, reparsed, "round trip must be lossless");
    }

    #[test]
    fn telemetry_is_off_by_default_unless_explicitly_set() {
        let seed = sample_seed();
        assert!(!seed.telemetry.enabled);
        assert_eq!(seed.telemetry.endpoint, None);
        let yaml = generate(&seed).expect("generate");
        let reparsed = parse(&yaml).expect("parse");
        assert!(!reparsed.telemetry.enabled);
    }

    #[test]
    fn telemetry_can_be_explicitly_opted_in_with_both_fields_set() {
        let mut seed = sample_seed();
        seed.telemetry = TelemetrySpec {
            enabled: true,
            endpoint: Some("https://telemetry.acme-corp.example/collect".to_string()),
        };
        let yaml = generate(&seed).expect("explicit opt-in with both fields must generate");
        assert!(yaml.contains("enabled: true"));
    }

    // -- structural validation --------------------------------------------

    #[test]
    fn missing_org_is_refused() {
        let mut seed = sample_seed();
        seed.org = String::new();
        assert_eq!(validate_shape(&seed), Err(SeedError::MissingOrg));
        assert_eq!(generate(&seed), Err(SeedError::MissingOrg));
    }

    #[test]
    fn missing_host_is_refused() {
        let mut seed = sample_seed();
        seed.host = "   ".to_string();
        assert_eq!(validate_shape(&seed), Err(SeedError::MissingHost));
    }

    #[test]
    fn no_products_declared_is_refused() {
        let mut seed = sample_seed();
        seed.products.clear();
        assert_eq!(validate_shape(&seed), Err(SeedError::NoProductsDeclared));
    }

    #[test]
    fn no_policy_signers_is_refused() {
        let mut seed = sample_seed();
        seed.policy_signers.clear();
        assert_eq!(validate_shape(&seed), Err(SeedError::NoPolicySigners));
    }

    #[test]
    fn telemetry_enabled_without_endpoint_is_refused() {
        let mut seed = sample_seed();
        seed.telemetry = TelemetrySpec {
            enabled: true,
            endpoint: None,
        };
        assert_eq!(
            validate_shape(&seed),
            Err(SeedError::TelemetryEnabledWithoutEndpoint)
        );
    }

    #[test]
    fn duplicate_department_slug_is_refused() {
        let mut seed = sample_seed();
        seed.departments.push(DepartmentSpec {
            slug: "finance".to_string(),
            renamed_from: vec![],
            lead: "@acme-corp/someone-else".to_string(),
        });
        assert_eq!(
            validate_shape(&seed),
            Err(SeedError::DuplicateDepartmentSlug("finance".to_string()))
        );
    }

    // -- no-secret guard (reusing mobileconfig::generator::looks_like_a_secret) --

    #[test]
    fn generate_refuses_a_secret_shaped_org_value() {
        let mut seed = sample_seed();
        seed.org = "sk-thisisnotarealsecretbutlookslikeone".to_string();
        let err = generate(&seed).expect_err("a secret-shaped org value must refuse generation");
        assert_eq!(err, SeedError::SecretShapedValue("org".to_string()));
    }

    #[test]
    fn generate_refuses_a_secret_shaped_foundation_mirror() {
        let mut seed = sample_seed();
        seed.foundation.mirror =
            Some("https://admin:supersecret@mirror.acme-corp.example".to_string());
        let err =
            generate(&seed).expect_err("a credential-embedded mirror URL must refuse generation");
        assert_eq!(
            err,
            SeedError::SecretShapedValue("foundation.mirror".to_string())
        );
    }

    #[test]
    fn generate_refuses_a_secret_shaped_policy_signer() {
        let mut seed = sample_seed();
        seed.policy_signers = vec!["ghp_abcdefghijklmnopqrstuvwxyz012345".to_string()];
        let err = generate(&seed).expect_err("a token-shaped policy signer must refuse generation");
        assert_eq!(
            err,
            SeedError::SecretShapedValue("policy_signers[0]".to_string())
        );
    }

    #[test]
    fn generate_refuses_a_secret_shaped_telemetry_endpoint() {
        let mut seed = sample_seed();
        seed.telemetry = TelemetrySpec {
            enabled: true,
            endpoint: Some("https://user:hunter2@telemetry.acme-corp.example/collect".to_string()),
        };
        let err = generate(&seed)
            .expect_err("a credential-embedded telemetry endpoint must refuse generation");
        assert_eq!(
            err,
            SeedError::SecretShapedValue("telemetry.endpoint".to_string())
        );
    }

    #[test]
    fn generate_refuses_a_secret_shaped_department_lead() {
        let mut seed = sample_seed();
        seed.departments[0].lead = "-----BEGIN PRIVATE KEY-----".to_string();
        let err =
            generate(&seed).expect_err("a PEM-shaped department lead value must refuse generation");
        assert_eq!(
            err,
            SeedError::SecretShapedValue("departments.finance.lead".to_string())
        );
    }

    #[test]
    fn ordinary_public_keys_never_trip_the_secret_scan() {
        // The whole point of root_key/key_set/policy_signers: these ARE
        // public keys, by design, and must never be refused.
        let seed = sample_seed();
        assert!(validate_no_secrets(&seed).is_ok());
    }

    #[test]
    fn seed_error_display_never_echoes_the_offending_value() {
        let err = SeedError::SecretShapedValue("org".to_string());
        let message = err.to_string();
        assert!(message.contains("org"));
        assert!(
            !message.to_ascii_lowercase().contains("sk-"),
            "the error message must never echo the offending secret-shaped value itself"
        );
    }

    // -- parse error framing ----------------------------------------------

    #[test]
    fn not_yaml_at_all_is_a_plain_language_parse_error() {
        let err = parse(": : : not yaml {{{").unwrap_err();
        assert!(
            err.message.contains("isn't valid YAML"),
            "message should lead with plain language, got: {}",
            err.message
        );
    }

    // -- topology default ---------------------------------------------------

    #[test]
    fn topology_defaults_to_separate() {
        assert_eq!(Topology::default(), Topology::Separate);
    }
}
