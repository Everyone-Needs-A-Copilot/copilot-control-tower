//! The Admin-mode red/green preflight (M7/S7, `.copilot/wp/43.md` task 66,
//! `architecture.md` §8.1 item 5): "before rollout, validate end-to-end...
//! A red/green report IT reads before pushing to the fleet."
//!
//! **On-demand, NOT telemetry** (`docs/08-observability/observability.md`
//! §7.1, verbatim: "preflight is a one-time, on-demand validation call
//! before rollout... not a continuous signal from the fleet"). Nothing in
//! this module emits to any telemetry endpoint, schedules a poll, or
//! persists state between calls — [`run_preflight`] is a pure function of
//! `(seed_text, config)` -> a [`PreflightReport`].
//!
//! ## Parse-not-compute (invariant #1, SOUL Case Law)
//!
//! This module renders CHECK RESULTS; it computes NO ecosystem verdict of
//! its own. Every external fact a check needs (does a department repo
//! exist, is the mirror reachable, who signed the policy, is the managed
//! profile complete) is supplied by the caller via [`PreflightConfig`] —
//! this module never shells out to `gh`, never makes an HTTP request, never
//! reads `CFPreferences`. Populating those facts (via `gh repo view`, a
//! real network probe, `mobileconfig::generator::missing_keys`, the
//! two-of-N verifier) is Admin-mode's own orchestration layer's job, out of
//! this task's scope — this crate only renders what it's told.
//!
//! ## Fail-closed: unknown is never pass (the honest-status ethos)
//!
//! Every [`PreflightConfig`] fact defaults to "not checked" (an absent
//! `HashMap` entry, or `None`) — which renders [`CheckStatus::Unknown`],
//! NEVER [`CheckStatus::Pass`]. A check is green only if it genuinely,
//! positively passed. This mirrors the dashboard's own "never fabricate a
//! pass" discipline and `observability.md`'s "absent ⇒ treated as the safe
//! default, never guessed" rule for missing security fields.
//!
//! ## No aggregate score, ever (FF-M7-NOSCORE's sibling)
//!
//! [`PreflightReport`] carries a `Vec<PreflightCheckResult>` and NOTHING
//! else — no numeric readiness score, no percentage, no weighted total. A
//! future "readiness: 8/10" field on this type IS the violation this
//! module exists to prevent — the same standing guard `render::fleet::
//! FleetView`'s own doc holds itself to, applied here to a different
//! surface. It's a checklist, red/green per item, never a blended verdict.

use std::collections::HashMap;

use serde::Serialize;

use super::seed::{self, EcosystemSeed};

const CHECK_SEED_PARSES: &str = "seed_parses";
const CHECK_SEED_WELL_FORMED: &str = "seed_well_formed";
const CHECK_NO_SECRET_IN_SEED: &str = "no_secret_in_seed";
const CHECK_DEPT_REPOS_EXIST: &str = "dept_repos_exist";
const CHECK_POLICY_SIGNED: &str = "policy_signed_by_authorized_signer";
const CHECK_MANAGED_PROFILE_COMPLETE: &str = "managed_profile_complete_for_silent_path";
const CHECK_FOUNDATION_PIN_RESOLVES: &str = "foundation_pin_resolves";
const CHECK_MIRROR_REACHABLE: &str = "mirror_reachable";

/// The full, ordered set of check names [`run_preflight`] always emits
/// exactly one result for — used both to drive the "seed didn't even
/// parse" honest-Unknown fallback below and by this module's own tests to
/// assert nothing is silently skipped.
const ALL_CHECKS: &[&str] = &[
    CHECK_SEED_PARSES,
    CHECK_SEED_WELL_FORMED,
    CHECK_NO_SECRET_IN_SEED,
    CHECK_DEPT_REPOS_EXIST,
    CHECK_POLICY_SIGNED,
    CHECK_MANAGED_PROFILE_COMPLETE,
    CHECK_FOUNDATION_PIN_RESOLVES,
    CHECK_MIRROR_REACHABLE,
];

/// One check's result — pass/fail/unknown, plus a plain-language reason an
/// IT admin reads directly.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CheckStatus {
    Pass,
    Fail,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PreflightCheckResult {
    pub check: String,
    pub status: CheckStatus,
    pub detail: String,
}

/// The whole preflight report. Deliberately JUST a list — see the module
/// doc's "no aggregate score" section.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PreflightReport {
    pub checks: Vec<PreflightCheckResult>,
}

/// External facts this preflight needs but does not itself compute (see the
/// module doc's parse-not-compute section) — every field defaults to "not
/// checked" (fail-closed to [`CheckStatus::Unknown`], never
/// [`CheckStatus::Pass`]).
#[derive(Debug, Clone, Default)]
pub struct PreflightConfig {
    /// Per-department-slug: does the declared repo exist? (`gh repo view`,
    /// `ecosystem-architecture.md` §4.2's own "departments[] is verified to
    /// exist" rule.) A slug with no entry at all means "not checked".
    pub department_repo_exists: HashMap<String, bool>,
    /// The signer key that actually signed the capability policy, if known
    /// — compared against the seed's own `policy_signers` allow-list.
    pub policy_signer: Option<String>,
    /// The managed-profile keys still missing for the silent path (e.g.
    /// the security-sensitive subset of `mobileconfig::generator::
    /// missing_keys(...)`'s own output) — `Some(vec![])` means complete,
    /// `Some(non-empty)` names the gaps, `None` means not checked.
    pub managed_profile_missing_keys: Option<Vec<String>>,
    /// Does the foundation `root_key` pin resolve against the trust-root
    /// verification path? `None` = not checked.
    pub foundation_pin_resolves: Option<bool>,
    /// Is `seed.foundation.mirror` (when declared) reachable? `None` = not
    /// checked. Never consulted when no mirror is declared at all — see
    /// [`check_mirror_reachable`].
    pub mirror_reachable: Option<bool>,
}

fn result(check: &str, status: CheckStatus, detail: impl Into<String>) -> PreflightCheckResult {
    PreflightCheckResult {
        check: check.to_string(),
        status,
        detail: detail.into(),
    }
}

fn check_dept_repos_exist(seed: &EcosystemSeed, config: &PreflightConfig) -> PreflightCheckResult {
    if seed.departments.is_empty() {
        return result(
            CHECK_DEPT_REPOS_EXIST,
            CheckStatus::Pass,
            "no departments declared — nothing to check",
        );
    }
    let mut missing = Vec::new();
    let mut unknown = Vec::new();
    for dept in &seed.departments {
        match config.department_repo_exists.get(&dept.slug) {
            Some(true) => {}
            Some(false) => missing.push(dept.slug.clone()),
            None => unknown.push(dept.slug.clone()),
        }
    }
    if !missing.is_empty() {
        return result(
            CHECK_DEPT_REPOS_EXIST,
            CheckStatus::Fail,
            format!("declared but missing repo(s): {}", missing.join(", ")),
        );
    }
    if !unknown.is_empty() {
        return result(
            CHECK_DEPT_REPOS_EXIST,
            CheckStatus::Unknown,
            format!("not yet checked: {}", unknown.join(", ")),
        );
    }
    result(
        CHECK_DEPT_REPOS_EXIST,
        CheckStatus::Pass,
        "every declared department repo exists",
    )
}

fn check_policy_signed(seed: &EcosystemSeed, config: &PreflightConfig) -> PreflightCheckResult {
    match &config.policy_signer {
        None => result(
            CHECK_POLICY_SIGNED,
            CheckStatus::Unknown,
            "policy signer not yet checked",
        ),
        Some(signer) => {
            if seed.policy_signers.iter().any(|s| s == signer) {
                result(
                    CHECK_POLICY_SIGNED,
                    CheckStatus::Pass,
                    "policy is signed by an authorized signer",
                )
            } else {
                result(
                    CHECK_POLICY_SIGNED,
                    CheckStatus::Fail,
                    "policy is signed by a key not on the seed's policy_signers allow-list",
                )
            }
        }
    }
}

fn check_managed_profile_complete(config: &PreflightConfig) -> PreflightCheckResult {
    match &config.managed_profile_missing_keys {
        None => result(
            CHECK_MANAGED_PROFILE_COMPLETE,
            CheckStatus::Unknown,
            "managed profile completeness not yet checked",
        ),
        Some(missing) if missing.is_empty() => result(
            CHECK_MANAGED_PROFILE_COMPLETE,
            CheckStatus::Pass,
            "managed profile is complete for the silent path",
        ),
        Some(missing) => result(
            CHECK_MANAGED_PROFILE_COMPLETE,
            CheckStatus::Fail,
            format!(
                "missing managed key(s) required for the silent path: {}",
                missing.join(", ")
            ),
        ),
    }
}

fn check_foundation_pin_resolves(config: &PreflightConfig) -> PreflightCheckResult {
    match config.foundation_pin_resolves {
        None => result(
            CHECK_FOUNDATION_PIN_RESOLVES,
            CheckStatus::Unknown,
            "foundation pin resolution not yet checked",
        ),
        Some(true) => result(
            CHECK_FOUNDATION_PIN_RESOLVES,
            CheckStatus::Pass,
            "foundation pin resolves",
        ),
        Some(false) => result(
            CHECK_FOUNDATION_PIN_RESOLVES,
            CheckStatus::Fail,
            "foundation pin does not resolve",
        ),
    }
}

fn check_mirror_reachable(seed: &EcosystemSeed, config: &PreflightConfig) -> PreflightCheckResult {
    if seed.foundation.mirror.is_none() {
        return result(
            CHECK_MIRROR_REACHABLE,
            CheckStatus::Pass,
            "no mirror declared — public github.com used directly, nothing to reach",
        );
    }
    match config.mirror_reachable {
        None => result(
            CHECK_MIRROR_REACHABLE,
            CheckStatus::Unknown,
            "mirror reachability not yet checked",
        ),
        Some(true) => result(
            CHECK_MIRROR_REACHABLE,
            CheckStatus::Pass,
            "mirror is reachable",
        ),
        Some(false) => result(
            CHECK_MIRROR_REACHABLE,
            CheckStatus::Fail,
            "mirror is not reachable",
        ),
    }
}

/// Runs every red/green check over `seed_text` (raw, possibly-invalid
/// `ecosystem.yml` text — this function does its own parse, so a caller
/// never has to pre-parse) + `config`'s externally-supplied facts. Always
/// returns a full [`PreflightReport`] with exactly [`ALL_CHECKS`]'s 8
/// entries — never panics on a malformed seed, since "the seed doesn't even
/// parse" is itself the first check's own honest `Fail` result, not a
/// reason to abort the whole report.
pub fn run_preflight(seed_text: &str, config: &PreflightConfig) -> PreflightReport {
    let mut checks = Vec::new();

    let parsed = match seed::parse(seed_text) {
        Ok(parsed) => {
            checks.push(result(
                CHECK_SEED_PARSES,
                CheckStatus::Pass,
                "parses as valid YAML",
            ));
            Some(parsed)
        }
        Err(e) => {
            checks.push(result(CHECK_SEED_PARSES, CheckStatus::Fail, e.to_string()));
            None
        }
    };

    // Every remaining check needs a parsed seed; if parsing itself failed,
    // every downstream check is honestly Unknown (there is nothing to check
    // against) — never a fabricated Pass, and never a silently-omitted row.
    let seed = match &parsed {
        Some(seed) => seed,
        None => {
            for check in &ALL_CHECKS[1..] {
                checks.push(result(
                    check,
                    CheckStatus::Unknown,
                    "the seed did not parse — cannot be checked",
                ));
            }
            return PreflightReport { checks };
        }
    };

    match seed::validate_shape(seed) {
        Ok(()) => checks.push(result(
            CHECK_SEED_WELL_FORMED,
            CheckStatus::Pass,
            "well-formed: org/host/products/policy_signers present, no duplicate departments, \
             telemetry config consistent",
        )),
        Err(e) => checks.push(result(
            CHECK_SEED_WELL_FORMED,
            CheckStatus::Fail,
            e.to_string(),
        )),
    }

    match seed::validate_no_secrets(seed) {
        Ok(()) => checks.push(result(
            CHECK_NO_SECRET_IN_SEED,
            CheckStatus::Pass,
            "no secret-shaped value found",
        )),
        Err(e) => checks.push(result(
            CHECK_NO_SECRET_IN_SEED,
            CheckStatus::Fail,
            e.to_string(),
        )),
    }

    checks.push(check_dept_repos_exist(seed, config));
    checks.push(check_policy_signed(seed, config));
    checks.push(check_managed_profile_complete(config));
    checks.push(check_foundation_pin_resolves(config));
    checks.push(check_mirror_reachable(seed, config));

    PreflightReport { checks }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::admin::seed::{
        DepartmentSpec, EcosystemSeed, FoundationPin, ProductSpec, TelemetrySpec, Topology,
        ECOSYSTEM_SEED_SCHEMA_VERSION,
    };
    use std::collections::BTreeMap;

    fn good_seed() -> EcosystemSeed {
        let mut products = BTreeMap::new();
        products.insert(
            "claude".to_string(),
            ProductSpec {
                enabled: true,
                foundation: Some("^5.14.0".to_string()),
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
                key_set: vec![],
            },
            auth: "gh-device".to_string(),
            products,
            departments: vec![DepartmentSpec {
                slug: "finance".to_string(),
                renamed_from: vec![],
                lead: "@acme-corp/finance-leads".to_string(),
            }],
            policy_signers: vec![
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIQsecuritysamplekeyonly".to_string(),
            ],
            telemetry: TelemetrySpec::default(),
        }
    }

    fn passing_config() -> PreflightConfig {
        let mut department_repo_exists = HashMap::new();
        department_repo_exists.insert("finance".to_string(), true);
        PreflightConfig {
            department_repo_exists,
            policy_signer: Some(
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIQsecuritysamplekeyonly".to_string(),
            ),
            managed_profile_missing_keys: Some(vec![]),
            foundation_pin_resolves: Some(true),
            mirror_reachable: Some(true),
        }
    }

    // -- a good seed, fully-known config: everything green -----------------

    #[test]
    fn a_good_seed_with_a_fully_known_config_is_all_green() {
        let seed = good_seed();
        let text = seed::generate(&seed).expect("good seed generates");
        let report = run_preflight(&text, &passing_config());

        assert_eq!(report.checks.len(), ALL_CHECKS.len());
        for check in &report.checks {
            assert_eq!(
                check.status,
                CheckStatus::Pass,
                "expected {} to be green, got {:?}: {}",
                check.check,
                check.status,
                check.detail
            );
        }
    }

    // -- a bad seed: missing field -> red -----------------------------------

    #[test]
    fn a_seed_missing_a_required_field_is_red_on_well_formed() {
        let mut seed = good_seed();
        seed.org = String::new();
        // `seed::generate` itself refuses an org-less seed (it's fail-closed
        // by construction), so this test bypasses it via a raw
        // `serde_yaml::to_string` to produce YAML that PARSES but is not
        // well-formed — exactly the "hand-authored, then run through
        // preflight" scenario this check exists to catch.
        let text = serde_yaml::to_string(&seed).expect("serialize");
        let report = run_preflight(&text, &passing_config());

        let seed_parses = find(&report, CHECK_SEED_PARSES);
        assert_eq!(seed_parses.status, CheckStatus::Pass, "still valid YAML");

        let well_formed = find(&report, CHECK_SEED_WELL_FORMED);
        assert_eq!(well_formed.status, CheckStatus::Fail);
        assert!(well_formed.detail.contains("org"));
    }

    #[test]
    fn a_seed_that_is_not_valid_yaml_is_red_on_parse_and_unknown_downstream() {
        let report = run_preflight(": : : not yaml {{{", &passing_config());

        assert_eq!(find(&report, CHECK_SEED_PARSES).status, CheckStatus::Fail);
        for check in &ALL_CHECKS[1..] {
            assert_eq!(
                find(&report, check).status,
                CheckStatus::Unknown,
                "check {check} must be Unknown, never Pass, when the seed didn't even parse"
            );
        }
    }

    // -- unknown/uncheckable -> non-green, never fabricated pass -----------

    #[test]
    fn an_uncheckable_item_is_unknown_never_a_fabricated_pass() {
        let seed = good_seed();
        let text = seed::generate(&seed).expect("good seed generates");
        let report = run_preflight(&text, &PreflightConfig::default());

        assert_eq!(
            find(&report, CHECK_DEPT_REPOS_EXIST).status,
            CheckStatus::Unknown
        );
        assert_eq!(
            find(&report, CHECK_POLICY_SIGNED).status,
            CheckStatus::Unknown
        );
        assert_eq!(
            find(&report, CHECK_MANAGED_PROFILE_COMPLETE).status,
            CheckStatus::Unknown
        );
        assert_eq!(
            find(&report, CHECK_FOUNDATION_PIN_RESOLVES).status,
            CheckStatus::Unknown
        );
        // No mirror was declared in `good_seed()`, so this one IS legitimately
        // green — there's nothing to reach, not "unreachable".
        assert_eq!(
            find(&report, CHECK_MIRROR_REACHABLE).status,
            CheckStatus::Pass
        );
    }

    #[test]
    fn a_declared_mirror_with_no_reachability_fact_is_unknown_not_pass() {
        let mut seed = good_seed();
        seed.foundation.mirror = Some("https://mirror.acme-corp.example/foundation".to_string());
        let text = seed::generate(&seed).expect("generate");
        let config = PreflightConfig::default();
        let report = run_preflight(&text, &config);
        assert_eq!(
            find(&report, CHECK_MIRROR_REACHABLE).status,
            CheckStatus::Unknown
        );
    }

    // -- specific red checks -------------------------------------------------

    #[test]
    fn a_missing_department_repo_is_red() {
        let seed = good_seed();
        let text = seed::generate(&seed).expect("generate");
        let mut config = passing_config();
        config
            .department_repo_exists
            .insert("finance".to_string(), false);
        let report = run_preflight(&text, &config);
        assert_eq!(
            find(&report, CHECK_DEPT_REPOS_EXIST).status,
            CheckStatus::Fail
        );
    }

    #[test]
    fn a_policy_signed_by_an_unauthorized_signer_is_red() {
        let seed = good_seed();
        let text = seed::generate(&seed).expect("generate");
        let mut config = passing_config();
        config.policy_signer = Some("ssh-ed25519 AAAAattackerkeynotonanyallowlist".to_string());
        let report = run_preflight(&text, &config);
        assert_eq!(find(&report, CHECK_POLICY_SIGNED).status, CheckStatus::Fail);
    }

    // -- no-aggregate-score property -----------------------------------------

    #[test]
    fn preflight_report_carries_no_aggregate_score_field() {
        let seed = good_seed();
        let text = seed::generate(&seed).expect("generate");
        let report = run_preflight(&text, &passing_config());

        let value = serde_json::to_value(&report).expect("PreflightReport must serialize");
        let obj = value.as_object().expect("serializes to an object");
        let mut top_level_keys: Vec<&str> = obj.keys().map(String::as_str).collect();
        top_level_keys.sort_unstable();
        assert_eq!(
            top_level_keys,
            vec!["checks"],
            "PreflightReport must carry EXACTLY `checks` — no score/readiness/percentage field, \
             ever (SOUL: a checklist, never a blended verdict)"
        );

        for check_value in value["checks"].as_array().unwrap() {
            let check_obj = check_value.as_object().unwrap();
            let mut keys: Vec<&str> = check_obj.keys().map(String::as_str).collect();
            keys.sort_unstable();
            assert_eq!(keys, vec!["check", "detail", "status"]);
        }
    }

    fn find<'a>(report: &'a PreflightReport, check: &str) -> &'a PreflightCheckResult {
        report
            .checks
            .iter()
            .find(|c| c.check == check)
            .unwrap_or_else(|| panic!("expected a {check:?} check in the report"))
    }
}
