//! The `.mobileconfig` XML plist builder (M5/S4, `.copilot/wp/30.md`,
//! `architecture.md` §8.1 item 4). PURE Rust — no `plist`/XML crate
//! dependency: a Configuration Profile is a small, well-known plist
//! shape and this module hand-rolls it with careful escaping, matching
//! `fitness_watchdog_plist.rs`'s own precedent of a hand-rolled plist scan
//! rather than pulling in a parsing crate for one artifact shape.
//!
//! ## What this emits
//!
//! One `.mobileconfig` (`PayloadType: Configuration`) containing up to three
//! payloads, built from [`MobileConfigInputs`]:
//!
//! 1. **`com.apple.ManagedClient.preferences`** — the forced-domain security
//!    keys, keyed by [`crate::managed::keys::APPLICATION_ID`] (**never** any
//!    other domain string — see [`generator_domain`] and FF-M5-6). Built by
//!    ITERATING [`crate::managed::keys::MANAGED_KEYS`] (never a
//!    hand-maintained second key list) so a future key added to the frozen
//!    registry is automatically a candidate slot here — G-M5-2's whole
//!    point.
//! 2. **`com.apple.servicemanagement`** — the managed login-item payload
//!    (S3's target): force-approves [`crate::managed::keys::APPLICATION_ID`]
//!    as a non-toggleable login item (ADR-M5-004, fixes B-H3).
//! 3. **`com.apple.notificationsettings`** — pre-authorizes the bundle's
//!    notifications so the safety-escalation channel (`architecture.md` §9)
//!    is never silently defeated by a denied permission.
//!
//! ## No secret is ever emitted (FF-M5-7, invariant #6)
//!
//! [`generate`] is fail-closed: every string value supplied in
//! [`MobileConfigInputs::values`] is checked against
//! [`looks_like_a_secret`] BEFORE being written into the XML, and generation
//! is refused (`Err(MobileConfigError::SecretShapedValue)`) if any value
//! looks like a credential/token — this is a real, structural guard, not
//! merely a passive downstream scan (the crate's own registry only ever
//! carries ENDPOINT REFERENCES for `SharedSecretStoreURL`/`SharedSecretStoreTier`
//! — see `managed::keys`'s own doc — so a genuine caller should never trip
//! this in practice; this is the defense-in-depth backstop for the case
//! where an Admin-mode operator fat-fingers a real secret into the wrong
//! field). `tests/fitness_m5_generator_domain_and_no_secrets.rs` closes the
//! loop with a second-layer scan over the checked-in golden fixture output.

use std::collections::HashMap;

use crate::managed::keys::{self, ManagedKey};

/// A single managed-key value an Admin-mode operator supplies for this org's
/// profile — typed per [`crate::managed::keys::KeyKind`] so the generator
/// never has to guess whether a given registry key wants a `<string>` or a
/// `<true/>`/`<false/>` plist value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ManagedValue {
    Str(String),
    Bool(bool),
}

/// Every input the generator needs to produce a ready-to-upload profile for
/// one org. UUIDs are supplied by the caller (Admin mode's own UI/CLI layer
/// owns real UUID generation — out of this task's scope, and deliberately
/// NOT re-implemented here with a fresh dependency) rather than generated
/// inside this pure function, which keeps [`generate`] fully deterministic
/// and golden-fixture-testable without a `uuid` crate.
#[derive(Debug, Clone)]
pub struct MobileConfigInputs {
    /// Human-readable org name, used in `PayloadOrganization`/
    /// `PayloadDisplayName`/`PayloadDescription` — never itself a managed
    /// key, purely cosmetic.
    pub org_display_name: String,
    /// Reverse-DNS-style prefix this org's IT wants their generated
    /// artifacts identified by, e.g. `com.acmecorp.controltower-profile`.
    /// Suffixed per-payload (`.preferences`/`.loginitem`/`.notifications`)
    /// so each `PayloadIdentifier` is unique within the profile.
    pub payload_identifier_prefix: String,
    /// Managed-key values, keyed by the EXACT [`ManagedKey::name`] spelling
    /// from [`crate::managed::keys::MANAGED_KEYS`]. A key with no entry
    /// here is simply omitted from the emitted `mcx_preference_settings`
    /// dict (see [`missing_keys`]) — Admin mode is not required to fill in
    /// every registered key for every org (e.g. `HTTPSProxy` may be
    /// genuinely N/A for an org with no forced proxy).
    pub values: HashMap<&'static str, ManagedValue>,
    pub include_login_item_payload: bool,
    pub include_notifications_payload: bool,
    pub root_uuid: String,
    pub preferences_uuid: String,
    pub login_item_uuid: String,
    pub notifications_uuid: String,
}

/// Generation was refused. Never carries the offending value itself (that
/// would defeat the entire point of the check by echoing the secret into an
/// error message/log) — only the key name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MobileConfigError {
    /// [`looks_like_a_secret`] flagged the value supplied for this key.
    SecretShapedValue(&'static str),
}

impl std::fmt::Display for MobileConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MobileConfigError::SecretShapedValue(key) => write!(
                f,
                "refusing to generate a .mobileconfig: the value supplied for {key:?} looks \
                 like a credential/token, not a config value — a .mobileconfig may only ever \
                 carry references/endpoints/flags, never a secret (invariant #6)"
            ),
        }
    }
}

impl std::error::Error for MobileConfigError {}

/// The domain this generator emits its `com.apple.ManagedClient.preferences`
/// payload under — MUST equal [`crate::managed::forced`]'s reader domain
/// (`crate::managed::keys::APPLICATION_ID`) so they can never drift
/// (FF-M5-6, closing G-M5-1). Deliberately a thin re-export rather than a
/// second copy of the string literal — the exact discipline
/// `managed::keys::APPLICATION_ID`'s own doc asks every consumer to follow.
pub fn generator_domain() -> &'static str {
    keys::APPLICATION_ID
}

/// Every registered key with NO value supplied in `inputs.values` — informational,
/// for an Admin-mode UI to show "these keys are not set for this org" rather
/// than silently omitting them. Never itself part of the emitted XML.
pub fn missing_keys(inputs: &MobileConfigInputs) -> Vec<&'static str> {
    keys::MANAGED_KEYS
        .iter()
        .filter(|k| !inputs.values.contains_key(k.name))
        .map(|k| k.name)
        .collect()
}

/// A crude but effective, evidence-based heuristic scan for secret-shaped
/// string material — deliberately the SAME spirit check
/// `managed::keys`'s own `no_entry_carries_anything_that_looks_like_a_literal_secret_value`
/// test uses, widened to the shapes an Admin operator is most likely to
/// paste by mistake: known token/key prefixes, a URL with embedded
/// `user:pass@` userinfo, a PEM block header, and a JWT-shaped
/// three-base64url-segment string.
pub fn looks_like_a_secret(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();

    let token_prefixes = [
        "sk-",
        "ghp_",
        "gho_",
        "ghu_",
        "ghs_",
        "ghr_",
        "github_pat_",
        "xox",
        "-----begin",
        "aws_secret",
        "akia",
    ];
    if token_prefixes.iter().any(|p| lower.contains(p)) {
        return true;
    }

    // URL with embedded userinfo credentials: scheme://user:pass@host
    if let Some(after_scheme) = lower.split("://").nth(1) {
        if let Some(at_idx) = after_scheme.find('@') {
            if after_scheme[..at_idx].contains(':') {
                return true;
            }
        }
    }

    // JWT-shaped: exactly three base64url segments separated by dots, each
    // long enough that it isn't just an ordinary dotted hostname/version
    // string (e.g. `v1.2.3` must never trip this).
    let parts: Vec<&str> = value.split('.').collect();
    if parts.len() == 3
        && parts.iter().all(|p| {
            p.len() > 10
                && p.chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        })
    {
        return true;
    }

    false
}

fn escape_xml(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            _ => out.push(c),
        }
    }
    out
}

fn write_string_kv(out: &mut String, indent: &str, key: &str, value: &str) {
    out.push_str(indent);
    out.push_str("<key>");
    out.push_str(&escape_xml(key));
    out.push_str("</key>\n");
    out.push_str(indent);
    out.push_str("<string>");
    out.push_str(&escape_xml(value));
    out.push_str("</string>\n");
}

fn write_bool_kv(out: &mut String, indent: &str, key: &str, value: bool) {
    out.push_str(indent);
    out.push_str("<key>");
    out.push_str(&escape_xml(key));
    out.push_str("</key>\n");
    out.push_str(indent);
    out.push_str(if value { "<true/>\n" } else { "<false/>\n" });
}

fn write_integer_kv(out: &mut String, indent: &str, key: &str, value: i64) {
    out.push_str(indent);
    out.push_str("<key>");
    out.push_str(&escape_xml(key));
    out.push_str("</key>\n");
    out.push_str(indent);
    out.push_str("<integer>");
    out.push_str(&value.to_string());
    out.push_str("</integer>\n");
}

/// Validates every string value in `inputs.values` before ANY XML is
/// written — see the module doc's "no secret is ever emitted" section.
fn validate_no_secret_values(inputs: &MobileConfigInputs) -> Result<(), MobileConfigError> {
    // Iterate in registry order (not HashMap order) so a failure is
    // reported deterministically regardless of hashing — cosmetic, but
    // matches this crate's general "deterministic over convenient"
    // discipline for anything touching test/golden-fixture output.
    for key in keys::MANAGED_KEYS {
        if let Some(ManagedValue::Str(value)) = inputs.values.get(key.name) {
            if looks_like_a_secret(value) {
                return Err(MobileConfigError::SecretShapedValue(key.name));
            }
        }
    }
    Ok(())
}

fn managed_key_entry_xml(out: &mut String, key: &ManagedKey, value: &ManagedValue) {
    match value {
        ManagedValue::Str(v) => write_string_kv(out, "              ", key.name, v),
        ManagedValue::Bool(v) => write_bool_kv(out, "              ", key.name, *v),
    }
}

fn preferences_payload_xml(inputs: &MobileConfigInputs) -> String {
    let mut out = String::new();
    out.push_str("    <dict>\n");
    out.push_str("      <key>PayloadContent</key>\n");
    out.push_str("      <dict>\n");
    out.push_str("        <key>");
    out.push_str(&escape_xml(keys::APPLICATION_ID));
    out.push_str("</key>\n");
    out.push_str("        <dict>\n");
    out.push_str("          <key>Forced</key>\n");
    out.push_str("          <array>\n");
    out.push_str("            <dict>\n");
    out.push_str("              <key>mcx_preference_settings</key>\n");
    out.push_str("              <dict>\n");
    for key in keys::MANAGED_KEYS {
        if let Some(value) = inputs.values.get(key.name) {
            managed_key_entry_xml(&mut out, key, value);
        }
    }
    out.push_str("              </dict>\n");
    out.push_str("            </dict>\n");
    out.push_str("          </array>\n");
    out.push_str("        </dict>\n");
    out.push_str("      </dict>\n");
    write_string_kv(
        &mut out,
        "      ",
        "PayloadDescription",
        &format!(
            "Forces {}'s managed/security preferences for {} (invariant #4 — honored only \
             from this forced domain).",
            keys::APPLICATION_ID,
            inputs.org_display_name
        ),
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadDisplayName",
        &format!(
            "{} — Copilot Control Tower Managed Preferences",
            inputs.org_display_name
        ),
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadIdentifier",
        &format!("{}.preferences", inputs.payload_identifier_prefix),
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadOrganization",
        &inputs.org_display_name,
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadType",
        "com.apple.ManagedClient.preferences",
    );
    write_string_kv(&mut out, "      ", "PayloadUUID", &inputs.preferences_uuid);
    write_integer_kv(&mut out, "      ", "PayloadVersion", 1);
    write_bool_kv(&mut out, "      ", "PayloadEnabled", true);
    out.push_str("    </dict>\n");
    out
}

fn login_item_payload_xml(inputs: &MobileConfigInputs) -> String {
    let mut out = String::new();
    out.push_str("    <dict>\n");
    write_string_kv(
        &mut out,
        "      ",
        "PayloadDescription",
        "Force-approves Copilot Control Tower as a non-toggleable managed login item \
         (ADR-M5-004, fixes B-H3) — distinct from the app's own crash-only launchd watchdog.",
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadDisplayName",
        &format!(
            "{} — Copilot Control Tower Managed Login Item",
            inputs.org_display_name
        ),
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadIdentifier",
        &format!("{}.loginitem", inputs.payload_identifier_prefix),
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadOrganization",
        &inputs.org_display_name,
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadType",
        "com.apple.servicemanagement",
    );
    write_string_kv(&mut out, "      ", "PayloadUUID", &inputs.login_item_uuid);
    write_integer_kv(&mut out, "      ", "PayloadVersion", 1);
    write_bool_kv(&mut out, "      ", "PayloadEnabled", true);
    out.push_str("      <key>Rules</key>\n");
    out.push_str("      <array>\n");
    out.push_str("        <dict>\n");
    write_string_kv(&mut out, "          ", "RuleType", "BundleIdentifier");
    write_string_kv(&mut out, "          ", "RuleValue", keys::APPLICATION_ID);
    write_string_kv(
        &mut out,
        "          ",
        "Comment",
        "One signed binary, launch-at-login only (ADR-M5-004) — never the crash-only watchdog.",
    );
    out.push_str("        </dict>\n");
    out.push_str("      </array>\n");
    out.push_str("    </dict>\n");
    out
}

fn notifications_payload_xml(inputs: &MobileConfigInputs) -> String {
    let mut out = String::new();
    out.push_str("    <dict>\n");
    write_string_kv(
        &mut out,
        "      ",
        "PayloadDescription",
        "Pre-authorizes Copilot Control Tower's notifications so the safety-escalation \
         channel (architecture.md §9) is never silently defeated by a denied permission.",
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadDisplayName",
        &format!(
            "{} — Copilot Control Tower Managed Notifications",
            inputs.org_display_name
        ),
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadIdentifier",
        &format!("{}.notifications", inputs.payload_identifier_prefix),
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadOrganization",
        &inputs.org_display_name,
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadType",
        "com.apple.notificationsettings",
    );
    write_string_kv(
        &mut out,
        "      ",
        "PayloadUUID",
        &inputs.notifications_uuid,
    );
    write_integer_kv(&mut out, "      ", "PayloadVersion", 1);
    write_bool_kv(&mut out, "      ", "PayloadEnabled", true);
    out.push_str("      <key>NotificationSettings</key>\n");
    out.push_str("      <array>\n");
    out.push_str("        <dict>\n");
    write_string_kv(
        &mut out,
        "          ",
        "BundleIdentifier",
        keys::APPLICATION_ID,
    );
    write_bool_kv(&mut out, "          ", "NotificationsEnabled", true);
    write_bool_kv(&mut out, "          ", "ShowInNotificationCenter", true);
    write_bool_kv(&mut out, "          ", "ShowInLockScreen", true);
    write_integer_kv(&mut out, "          ", "AlertType", 2);
    out.push_str("        </dict>\n");
    out.push_str("      </array>\n");
    out.push_str("    </dict>\n");
    out
}

/// Generates the full `.mobileconfig` XML plist for `inputs`. Fail-closed:
/// refuses (never emits partial output) if any supplied string value looks
/// like a secret — see [`validate_no_secret_values`]/[`looks_like_a_secret`].
pub fn generate(inputs: &MobileConfigInputs) -> Result<String, MobileConfigError> {
    validate_no_secret_values(inputs)?;

    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    out.push_str(
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \
         \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n",
    );
    out.push_str(&format!(
        "<!-- Copilot Control Tower — generated .mobileconfig for {} \
         (M5/S4, `.copilot/wp/30.md`). Domain: {} — must equal \
         `managed::forced`'s reader domain (FF-M5-6). Carries ONLY \
         references/endpoints/flags, never a secret (invariant #6, FF-M5-7). -->\n",
        escape_xml(&inputs.org_display_name),
        keys::APPLICATION_ID
    ));
    out.push_str("<plist version=\"1.0\">\n");
    out.push_str("<dict>\n");
    write_string_kv(
        &mut out,
        "  ",
        "PayloadDescription",
        &format!(
            "Copilot Control Tower managed configuration for {}.",
            inputs.org_display_name
        ),
    );
    write_string_kv(
        &mut out,
        "  ",
        "PayloadDisplayName",
        &format!("{} — Copilot Control Tower", inputs.org_display_name),
    );
    write_string_kv(
        &mut out,
        "  ",
        "PayloadIdentifier",
        &inputs.payload_identifier_prefix,
    );
    write_string_kv(
        &mut out,
        "  ",
        "PayloadOrganization",
        &inputs.org_display_name,
    );
    // Blocks a LOCAL user from removing the profile from System Settings —
    // the managed keys it carries are, by definition (invariant #4), only
    // ever meant to be honored/removed via MDM, never a local toggle. This
    // does not block an MDM-issued removal command.
    write_bool_kv(&mut out, "  ", "PayloadRemovalDisallowed", true);
    write_string_kv(&mut out, "  ", "PayloadType", "Configuration");
    write_string_kv(&mut out, "  ", "PayloadUUID", &inputs.root_uuid);
    write_integer_kv(&mut out, "  ", "PayloadVersion", 1);

    out.push_str("  <key>PayloadContent</key>\n");
    out.push_str("  <array>\n");
    out.push_str(&preferences_payload_xml(inputs));
    if inputs.include_login_item_payload {
        out.push_str(&login_item_payload_xml(inputs));
    }
    if inputs.include_notifications_payload {
        out.push_str(&notifications_payload_xml(inputs));
    }
    out.push_str("  </array>\n");

    out.push_str("</dict>\n");
    out.push_str("</plist>\n");
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_inputs() -> MobileConfigInputs {
        let mut values = HashMap::new();
        values.insert("OrgSlug", ManagedValue::Str("acme-corp".to_string()));
        values.insert("Department", ManagedValue::Str("engineering".to_string()));
        values.insert(
            "EcosystemSeedURL",
            ManagedValue::Str("https://ecosystem.acme-corp.internal/ecosystem.yml".to_string()),
        );
        values.insert("AllowSelfUpdate", ManagedValue::Bool(true));
        values.insert("DisableWizard", ManagedValue::Bool(true));
        values.insert(
            "AdminContact",
            ManagedValue::Str("it-help@acme-corp.example".to_string()),
        );
        values.insert(
            "SharedSecretStoreURL",
            ManagedValue::Str("https://secrets.acme-corp.internal/controltower".to_string()),
        );
        values.insert(
            "SharedSecretStoreTier",
            ManagedValue::Str("org".to_string()),
        );
        MobileConfigInputs {
            org_display_name: "Acme Corp".to_string(),
            payload_identifier_prefix: "com.acmecorp.controltower-profile".to_string(),
            values,
            include_login_item_payload: true,
            include_notifications_payload: true,
            root_uuid: "11111111-1111-1111-1111-111111111111".to_string(),
            preferences_uuid: "22222222-2222-2222-2222-222222222222".to_string(),
            login_item_uuid: "33333333-3333-3333-3333-333333333333".to_string(),
            notifications_uuid: "44444444-4444-4444-4444-444444444444".to_string(),
        }
    }

    #[test]
    fn generator_domain_matches_the_reader_application_id_fitness_ff_m5_6() {
        assert_eq!(generator_domain(), keys::APPLICATION_ID);
    }

    #[test]
    fn generate_succeeds_for_ordinary_org_values() {
        let inputs = sample_inputs();
        let xml = generate(&inputs).expect("ordinary org values must generate cleanly");
        assert!(xml.starts_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"));
        assert!(xml.contains("<plist version=\"1.0\">"));
        assert!(xml.trim_end().ends_with("</plist>"));
    }

    #[test]
    fn generated_xml_uses_the_readers_exact_domain_as_the_mcx_preferences_key() {
        let inputs = sample_inputs();
        let xml = generate(&inputs).expect("generate");
        assert!(
            xml.contains(&format!("<key>{}</key>", keys::APPLICATION_ID)),
            "the mcx_preference_settings payload must be keyed by the EXACT reader domain"
        );
        assert!(
            !xml.contains("dev.enac.controltower"),
            "the doc-only domain must never leak into generated output (G-M5-1)"
        );
    }

    #[test]
    fn generated_xml_contains_every_supplied_forced_key() {
        let inputs = sample_inputs();
        let xml = generate(&inputs).expect("generate");
        for key_name in inputs.values.keys() {
            assert!(
                xml.contains(&format!("<key>{key_name}</key>")),
                "expected {key_name:?} to appear in the generated mcx_preference_settings dict"
            );
        }
    }

    #[test]
    fn missing_keys_reports_every_registered_key_with_no_supplied_value() {
        let inputs = sample_inputs();
        let missing = missing_keys(&inputs);
        assert!(missing.contains(&"HTTPSProxy"));
        assert!(missing.contains(&"GitHubHost"));
        assert!(
            !missing.contains(&"OrgSlug"),
            "OrgSlug was supplied, must not be reported missing"
        );
    }

    #[test]
    fn generate_iterates_the_frozen_registry_never_a_hand_maintained_second_list() {
        // Regression guard for G-M5-2: every key that DOES have a supplied
        // value ends up in the output, driven purely by iterating
        // `MANAGED_KEYS` — if a future key is appended to the registry with
        // no corresponding branch here, this test (which walks the SAME
        // registry) still passes, because there is no second, independently
        // maintained key list for it to drift from.
        let mut values = HashMap::new();
        for key in keys::MANAGED_KEYS {
            let value = match key.kind {
                keys::KeyKind::String => ManagedValue::Str(format!("test-value-for-{}", key.name)),
                keys::KeyKind::Bool => ManagedValue::Bool(true),
            };
            values.insert(key.name, value);
        }
        let inputs = MobileConfigInputs {
            values,
            ..sample_inputs()
        };
        let xml = generate(&inputs).expect("generate");
        for key in keys::MANAGED_KEYS {
            assert!(
                xml.contains(&format!("<key>{}</key>", key.name)),
                "registry key {:?} was not found in generated output — the generator must \
                 iterate MANAGED_KEYS, never a second hand-maintained list (G-M5-2)",
                key.name
            );
        }
    }

    // -- no-secret guard (FF-M5-7) -------------------------------------------

    #[test]
    fn looks_like_a_secret_flags_known_token_prefixes() {
        assert!(looks_like_a_secret("sk-abcdef1234567890"));
        assert!(looks_like_a_secret("ghp_abcdefghijklmnopqrstuvwxyz012345"));
        assert!(looks_like_a_secret("-----BEGIN PRIVATE KEY-----"));
    }

    #[test]
    fn looks_like_a_secret_flags_a_url_with_embedded_userinfo_credentials() {
        assert!(looks_like_a_secret(
            "https://user:hunter2@secrets.example.com/api"
        ));
    }

    #[test]
    fn looks_like_a_secret_flags_a_jwt_shaped_string() {
        assert!(looks_like_a_secret(
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQljmhYuwWKB"
        ));
    }

    #[test]
    fn looks_like_a_secret_does_not_flag_ordinary_endpoint_references() {
        assert!(!looks_like_a_secret(
            "https://secrets.acme-corp.internal/controltower"
        ));
        assert!(!looks_like_a_secret("acme-corp"));
        assert!(!looks_like_a_secret("it-help@acme-corp.example"));
        assert!(!looks_like_a_secret("org"));
    }

    #[test]
    fn generate_refuses_a_secret_shaped_admincontact_value() {
        let mut inputs = sample_inputs();
        inputs.values.insert(
            "AdminContact",
            ManagedValue::Str("sk-thisisnotarealsecretbutlookslikeone".to_string()),
        );
        let err = generate(&inputs).expect_err("a secret-shaped value must refuse generation");
        assert_eq!(err, MobileConfigError::SecretShapedValue("AdminContact"));
    }

    #[test]
    fn generate_refuses_a_secret_shaped_shared_secret_store_url() {
        let mut inputs = sample_inputs();
        inputs.values.insert(
            "SharedSecretStoreURL",
            ManagedValue::Str("https://admin:supersecret@secrets.acme-corp.internal".to_string()),
        );
        let err = generate(&inputs).expect_err("a credential-embedded URL must refuse generation");
        assert_eq!(
            err,
            MobileConfigError::SecretShapedValue("SharedSecretStoreURL")
        );
    }

    #[test]
    fn mobileconfig_error_display_never_echoes_the_offending_value() {
        let err = MobileConfigError::SecretShapedValue("AdminContact");
        let message = err.to_string();
        assert!(message.contains("AdminContact"));
        assert!(
            !message.to_ascii_lowercase().contains("sk-"),
            "the error message must never echo the offending secret-shaped value itself"
        );
    }

    // -- payload toggles ------------------------------------------------------

    #[test]
    fn omitting_the_login_item_payload_omits_com_apple_servicemanagement() {
        let mut inputs = sample_inputs();
        inputs.include_login_item_payload = false;
        let xml = generate(&inputs).expect("generate");
        assert!(!xml.contains("com.apple.servicemanagement"));
    }

    #[test]
    fn omitting_the_notifications_payload_omits_com_apple_notificationsettings() {
        let mut inputs = sample_inputs();
        inputs.include_notifications_payload = false;
        let xml = generate(&inputs).expect("generate");
        assert!(!xml.contains("com.apple.notificationsettings"));
    }

    #[test]
    fn org_display_name_is_xml_escaped() {
        let mut inputs = sample_inputs();
        inputs.org_display_name = "Acme & <Sons>".to_string();
        let xml = generate(&inputs).expect("generate");
        assert!(xml.contains("Acme &amp; &lt;Sons&gt;"));
        assert!(!xml.contains("Acme & <Sons>"));
    }
}
