//! The FROZEN managed-key registry (M5/S1, `.copilot/wp/30.md` ADR-M5-001,
//! architecture.md §8.3, credentials-and-boundary.md §1.6.2).
//!
//! This is the single source of truth for "what managed/forced key names
//! does this app know about" — shared, by construction, between the reader
//! (this module + [`super::forced`]) and the eventual `.mobileconfig`
//! generator (S4, Admin mode). Freezing this list here — rather than letting
//! each reader hand-spell its own key strings, as `settings::managed` and
//! `updater::trust` each did before this milestone — is what makes
//! "generator and reader can never disagree on a key name" (G-M5-2) a
//! structural fact instead of a code-review discipline: S4 asserts
//! `generator_domain == reader_domain` (below) and can iterate
//! [`MANAGED_KEYS`] instead of maintaining a second, independently-typed
//! list that could silently drift from this one.
//!
//! ## The domain (G-M5-1 — flagged, not silently resolved)
//!
//! [`APPLICATION_ID`] is `com.everyoneneedsacopilot.controltower` — the
//! REAL, CODE-authoritative macOS application-preferences domain, matching
//! `tauri.conf.json`'s `identifier` (verified directly, not assumed) and the
//! constant `settings::managed`/`updater::trust` each already hard-coded
//! independently before this refactor. Several docs (`architecture.md` §8.3,
//! `windows-parity.md`, `docs/06-deployment/README.md`,
//! `docs/product-design/**`) instead say `dev.enac.controltower` — that is a
//! **documentation** value, not what any shipped code has ever read or
//! written. This module is deliberately the one place that states, in code,
//! which of the two is authoritative: **the code domain wins** (an app can
//! only ever honor the domain it actually asks `CFPreferencesCopyAppValue`
//! for), and the doc mismatch is flagged here for owner doc-reconciliation
//! rather than silently "fixed" by picking a domain a security review has no
//! standing to invent. Do not use `dev.enac.controltower` anywhere in code.
//!
//! ## Where each key's {security_sensitive, forced_only} classification came
//! from (evidence, not a guess)
//!
//! - The 9 keys architecture.md §8.3 names explicitly in its "Security-sensitive
//!   keys are honored ONLY from the managed (forced) domain" sentence
//!   (`UpdateFeedURL`, `FoundationMirror`, `EcosystemSeedURL`, `HTTPSProxy`,
//!   `GitHubHost`, `AuthMode`, `AllowSelfUpdate`, `Deprovisioned`,
//!   `AdminContact`) are `security_sensitive: true` here — direct textual
//!   citation, not inference.
//! - `UpdateChannel` is `security_sensitive: true` on `settings::guard`'s own
//!   explicit say-so (`src/settings/guard.rs` `DENIED_KEYS`'s inline comment:
//!   "exactly as security-sensitive as its two siblings" — i.e.
//!   `UpdateFeedURL`/`AllowSelfUpdate`).
//! - `DisableWizard`, `OrgSlug`, `Department`, `Host` are NOT named in
//!   architecture.md §8.3's "security-sensitive" sentence, but
//!   `settings::guard::DENIED_KEYS` (verified by reading that file) refuses
//!   ALL of them from Settings writes identically to the 9 above — the
//!   shipped code's actual enforcement is broader than the doc's prose. This
//!   registry marks `forced_only: true` for all of them (matching the
//!   stronger, already-shipped bar) but keeps `security_sensitive` split:
//!   `DisableWizard` is marked `true` (a forced-domain override of it can
//!   suppress the wizard's own fail-closed validation path — a real
//!   security-relevant behavior-suppression lever, not just a provisioning
//!   convenience; see red-team B-H4); `OrgSlug`/`Department`/`Host` stay
//!   `false` (organizational-identity fields `cc derive` consumes — wrong
//!   values misroute provisioning but are not themselves an RCE/exfiltration
//!   lever the way a repointed update feed or proxy is). This split is a
//!   judgment call made explicit here, not asserted as an owner-ratified
//!   fact — flagged in the S1 summary for confirmation.
//! - `SharedSecretStoreURL`/`SharedSecretStoreTier` are `security_sensitive:
//!   true` per `credentials-and-boundary.md` §1.6.2 step 6 ("Deliver the
//!   store's URL/config via the MDM-managed domain only... never a value in
//!   git, never a user-editable config file") — these carry an ENDPOINT
//!   REFERENCE only, never a secret value (§1.6.4: "the store is a
//!   resolution-time API the CLI calls, not a channel content flows
//!   through"); this module never reads or exposes a secret through them.
//! - `LoginItemManaged` is **provisional** — see its own doc comment below.
//! - `TelemetryEnabled`/`TelemetryEndpoint` are `security_sensitive: true`
//!   per M7/S2 (task 61, ADR-M7-003, FF-M7-OPTIN): an unauthenticated write
//!   to either key is a real security lever (silently turning on analytics
//!   telemetry, or redirecting it to an attacker-controlled collector) —
//!   this pair is the documented INTERIM carrier for `telemetry::optin`'s
//!   `TelemetryCarrier` seam pending G-M7-1's owner ratification of the
//!   FINAL carrier (the org's signed `ecosystem.yml`, surfaced via a future
//!   CLI `--json` field this app cannot itself verify the signature of, per
//!   invariant #1). See `telemetry::optin`'s module doc for the full
//!   carrier-divergence writeup.
//!
//! ## A real, evidence-based gap this freeze surfaces (flagged, not fixed
//! here — out of this task's file scope)
//!
//! `settings::guard::DENIED_KEYS` (verified: `src/settings/guard.rs`,
//! `grep -n "sharedsecretstore\|loginitemmanaged" src/settings/guard.rs`
//! returns nothing) does **not yet** deny-list `SharedSecretStoreURL`,
//! `SharedSecretStoreTier`, or `LoginItemManaged` — so today, nothing stops
//! an author from hand-writing one of those three key names into
//! `copilot.layers.yml`'s `extra` mapping and having never-destroy preserve
//! it as an ordinary unrecognized field. This is not a vulnerability this
//! task introduces (this task only adds a *reader*, and the reader is
//! forced-domain-only by construction — see [`super::forced`]), but it is a
//! real drift between the write-side guard and this newly-frozen read-side
//! registry. `guard.rs` is outside this task's owned file list
//! (`settings/guard.rs` is M2/S3 territory); flagged for a follow-up edit to
//! `DENIED_KEYS` rather than silently worked around here.

/// The macOS application-preferences domain every managed/forced key in
/// [`MANAGED_KEYS`] is read from. THE single authoritative copy — see the
/// module doc's "the domain (G-M5-1)" section. `settings::managed` and
/// `updater::trust` each used to hard-code their own copy of this exact
/// string; both now reference this constant instead (their own local
/// `APPLICATION_ID` consts are removed as part of this consolidation).
pub const APPLICATION_ID: &str = "com.everyoneneedsacopilot.controltower";

/// The plist/CFPreferences value shape a given key is expected to carry —
/// used only to document intent and to pick which of
/// [`super::forced::forced_string`]/[`super::forced::forced_bool`] a
/// consumer should call; this crate does not (yet) enforce type-mismatch at
/// the FFI layer (`super::forced`'s module doc names this as a known,
/// pre-existing limitation carried over from M4, not introduced here).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyKind {
    /// A `CFString`-typed preference value.
    String,
    /// A boolean preference value, read via [`super::forced::forced_bool`]'s
    /// canonical string-spelling parse (`"false"`/`"0"`/`"no"`, case
    /// insensitive, means `false`; anything else forced means `true`).
    Bool,
}

/// One frozen entry in the managed-key registry. Every field here is
/// evidence-backed (see the module doc) — nothing is invented to fill out
/// the shape.
#[derive(Debug, Clone, Copy)]
pub struct ManagedKey {
    /// The exact `CFPreferences` key name — passed byte-for-byte to
    /// [`super::forced::forced_string`]/[`super::forced::forced_bool`]/
    /// [`super::forced::key_is_forced`]. Case-sensitive; matches the literal
    /// spelling `architecture.md` §8.3 and `settings::guard::DENIED_KEYS`
    /// use (`DENIED_KEYS` itself lowercases before comparing, but the
    /// CFPreferences key name on disk/in a `.mobileconfig` is written in
    /// this exact case).
    pub name: &'static str,
    /// The expected value shape (see [`KeyKind`]).
    pub kind: KeyKind,
    /// `true` when a forced-domain-only-but-wrong-or-attacker-controlled
    /// value for this key is itself a security lever (RCE, credential
    /// misdirection, safety-signal suppression, secret-store misdirection)
    /// — see the module doc's evidence section for how each key was
    /// classified.
    pub security_sensitive: bool,
    /// `true` when this key must NEVER be honored from a value written to
    /// the ordinary user-writable preferences domain — i.e. every entry
    /// currently in this registry (invariant #4: "security posture is
    /// inherited and enforced, never weakened"). Kept as an explicit field
    /// (not simply "always true, so why bother") because it is exactly the
    /// fact [`super::forced::resolve_string`]/[`super::forced::resolve_bool`]
    /// enforce structurally for every key regardless of this flag — FF-M5-5
    /// asserts every entry here is `forced_only: true` (see this module's
    /// tests), and a future non-security, purely-cosmetic managed key that
    /// legitimately wanted user-domain fallback would be the one place this
    /// field would ever read `false`. No such key exists today.
    pub forced_only: bool,
    /// One-line purpose, for the S4 `.mobileconfig` generator's own
    /// human-readable payload comments and for anyone auditing this
    /// registry without cross-referencing every source doc.
    pub purpose: &'static str,
}

/// The frozen registry — every managed/forced key this app's Rust code
/// knows the name of. Append-only in spirit: a future milestone adding a
/// new managed key adds a new entry here, never renames or removes an
/// existing one (a rename would silently orphan any already-deployed
/// `.mobileconfig` payload using the old name).
pub const MANAGED_KEYS: &[ManagedKey] = &[
    ManagedKey {
        name: "OrgSlug",
        kind: KeyKind::String,
        security_sensitive: false,
        forced_only: true,
        purpose: "Organization identifier `cc derive` uses to materialize org/dept layers on a managed machine.",
    },
    ManagedKey {
        name: "Department",
        kind: KeyKind::String,
        security_sensitive: false,
        forced_only: true,
        purpose: "Department identifier `cc derive` uses to materialize the dept layer on a managed machine.",
    },
    ManagedKey {
        name: "EcosystemSeedURL",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "Where `cc derive` fetches the org's `ecosystem.yml` seed from — a repointed value is a supply-chain lever. Also one of `settings::managed`'s two managed-detection indicator keys.",
    },
    ManagedKey {
        name: "GitHubHost",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "GitHub Enterprise host override for self-hosted GitHub deployments — a repointed value can redirect git operations to an attacker-controlled host.",
    },
    ManagedKey {
        name: "AuthMode",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "Selects the git auth identity class (ssh-personal/ssh-work/anon/gh-app:<slug>) for a managed/kiosk machine.",
    },
    ManagedKey {
        name: "Host",
        kind: KeyKind::String,
        security_sensitive: false,
        forced_only: true,
        purpose: "Machine-class/host identifier pre-seeded for provisioning (kiosk vs. personal machine framing).",
    },
    ManagedKey {
        name: "FoundationMirror",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "Alternate foundation-tier mirror URL — a repointed value is a supply-chain MITM lever identical in shape to `UpdateFeedURL`.",
    },
    ManagedKey {
        name: "HTTPSProxy",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "Forced HTTPS proxy for all ecosystem/update network traffic — a repointed value is a MITM lever.",
    },
    ManagedKey {
        name: "UpdateFeedURL",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "Where the self-updater fetches the signed `latest.json` manifest from (`updater::trust::update_feed_url`, FF-M4-4).",
    },
    ManagedKey {
        name: "UpdateChannel",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "Release channel pin (`stable`/`beta`/`pinned:<version>`) for self-update (`updater::trust::update_channel`, FF-M4-4).",
    },
    ManagedKey {
        name: "AllowSelfUpdate",
        kind: KeyKind::Bool,
        security_sensitive: true,
        forced_only: true,
        purpose: "Whether this machine self-updates at all (`updater::trust::allow_self_update`, FF-M4-4); `false` is only ever a forced-domain fact, never a user choice.",
    },
    ManagedKey {
        name: "DisableWizard",
        kind: KeyKind::Bool,
        security_sensitive: true,
        forced_only: true,
        purpose: "Runs the onboarding wizard silently instead of interactively. Security-relevant: a forced-domain override of this gates whether the wizard's own fail-closed schema validation surfaces to Bob at all (red-team B-H4). Also one of `settings::managed`'s two managed-detection indicator keys.",
    },
    ManagedKey {
        name: "Deprovisioned",
        kind: KeyKind::Bool,
        security_sensitive: true,
        forced_only: true,
        purpose: "Explicit MDM-triggered wipe signal (S6, ADR-M5-002/003) — only an explicit `true` (never mere profile removal) triggers a deprovision render/action.",
    },
    ManagedKey {
        name: "AdminContact",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "Mandatory IT safety-escalation endpoint (architecture.md §9) — forced-domain-only so a local user cannot redirect safety signals to themselves.",
    },
    ManagedKey {
        name: "SharedSecretStoreURL",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "ENDPOINT REFERENCE ONLY (never a secret) for the tier-scoped managed shared secret store (S5, credentials-and-boundary.md §1.6.2 step 6). Absent means the shared-store rung of the credential-resolution ladder is treated as absent, never guessed.",
    },
    ManagedKey {
        name: "SharedSecretStoreTier",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "Which tier project/namespace this machine's members are scoped to in the shared secret store (S5, credentials-and-boundary.md §1.6.2 step 3).",
    },
    ManagedKey {
        name: "LoginItemManaged",
        kind: KeyKind::Bool,
        security_sensitive: false,
        forced_only: true,
        purpose: "PROVISIONAL, pending S3 confirmation of the exact key name/semantics: this app's OWN forced-domain marker announcing that MDM has separately pushed the `com.apple.servicemanagement` managed login-item payload (a DIFFERENT preferences domain this app does not itself read), so the app can skip nagging Bob to enable background running manually (ADR-M5-004).",
    },
    ManagedKey {
        name: "TelemetryEnabled",
        kind: KeyKind::Bool,
        security_sensitive: true,
        forced_only: true,
        purpose: "M7/S2 (task 61, ADR-M7-003, FF-M7-OPTIN) INTERIM analytics opt-in flag — forced-domain-only so a local, non-admin write can never silently turn on analytics telemetry for a machine the org never opted in (analytics is off-by-default, opt-in-only, invariant per SOUL). G-M7-1 (memory `m7-observability-admin-decisions`): the canonical carrier for this decision is the org's SIGNED `ecosystem.yml`, surfaced only via a future CLI `--json` field (this app cannot itself verify a signature — parse, never compute); no such field exists yet, so this forced-domain key is the documented INTERIM carrier behind `telemetry::optin`'s `TelemetryCarrier` seam, not the final owner-ratified answer.",
    },
    ManagedKey {
        name: "TelemetryEndpoint",
        kind: KeyKind::String,
        security_sensitive: true,
        forced_only: true,
        purpose: "M7/S2 (task 61, ADR-M7-003, FF-M7-OPTIN) INTERIM analytics collector endpoint — an ENDPOINT REFERENCE ONLY (owner infra, G-M7-3), never a secret, same shape as `SharedSecretStoreURL`. Forced-domain-only so analytics can never be silently redirected to an attacker-controlled collector by a user-domain write; absent means the analytics gate resolves to Disabled, never a guessed default (`observability.md` §6). Same G-M7-1 interim-carrier caveat as `TelemetryEnabled` above.",
    },
];

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn application_id_matches_the_tauri_bundle_identifier() {
        // Cross-checked by reading `src-tauri/tauri.conf.json`'s
        // `"identifier"` field directly (not assumed) at the time this
        // registry was authored — this test pins the string so a future
        // accidental edit to either file is caught immediately rather than
        // silently reintroducing G-M5-1's exact failure mode one file later.
        assert_eq!(APPLICATION_ID, "com.everyoneneedsacopilot.controltower");
        assert!(
            !APPLICATION_ID.contains("dev.enac"),
            "the doc-only domain must never leak into the code-authoritative constant (G-M5-1)"
        );
    }

    #[test]
    fn every_key_name_is_unique() {
        let mut seen = HashSet::new();
        for key in MANAGED_KEYS {
            assert!(
                seen.insert(key.name),
                "duplicate managed key name in the frozen registry: {}",
                key.name
            );
        }
    }

    #[test]
    fn every_key_name_is_non_empty_and_has_no_whitespace() {
        for key in MANAGED_KEYS {
            assert!(!key.name.is_empty());
            assert!(
                !key.name.contains(char::is_whitespace),
                "key name {:?} contains whitespace — not a valid CFPreferences key",
                key.name
            );
        }
    }

    #[test]
    fn every_key_has_a_non_empty_purpose() {
        for key in MANAGED_KEYS {
            assert!(
                !key.purpose.trim().is_empty(),
                "key {:?} has an empty purpose",
                key.name
            );
        }
    }

    /// FF-M5-5 (registry half): every key in this frozen registry is
    /// `forced_only: true` — see [`ManagedKey::forced_only`]'s doc for why
    /// this is currently an unconditional fact, not merely a common case.
    /// `super::forced`'s own tests close the other half (the resolve
    /// functions themselves never honor an `IgnoredUserDomain` value).
    #[test]
    fn every_registered_key_is_forced_only_fitness_ff_m5_5() {
        let non_forced_only: Vec<&str> = MANAGED_KEYS
            .iter()
            .filter(|k| !k.forced_only)
            .map(|k| k.name)
            .collect();
        assert!(
            non_forced_only.is_empty(),
            "every key in the frozen managed-key registry must be forced_only \
             (invariant #4) — found non-forced_only entries: {non_forced_only:?}"
        );
    }

    /// Confirms the specific, evidence-cited set of `security_sensitive`
    /// keys matches architecture.md §8.3's explicit sentence plus the two
    /// documented extensions (`UpdateChannel`, `DisableWizard`) — a
    /// regression guard so a future edit can't silently narrow or widen this
    /// set without a reviewer noticing the test name/assertion.
    #[test]
    fn security_sensitive_set_matches_the_cited_evidence() {
        let mut sensitive: Vec<&str> = MANAGED_KEYS
            .iter()
            .filter(|k| k.security_sensitive)
            .map(|k| k.name)
            .collect();
        sensitive.sort_unstable();

        let mut expected = vec![
            "AdminContact",
            "AllowSelfUpdate",
            "AuthMode",
            "Deprovisioned",
            "DisableWizard",
            "EcosystemSeedURL",
            "FoundationMirror",
            "GitHubHost",
            "HTTPSProxy",
            "SharedSecretStoreTier",
            "SharedSecretStoreURL",
            "TelemetryEnabled",
            "TelemetryEndpoint",
            "UpdateChannel",
            "UpdateFeedURL",
        ];
        expected.sort_unstable();

        assert_eq!(sensitive, expected);
    }

    /// No secret material ever appears as a `purpose` string or a `name` —
    /// this registry carries key NAMES and documentation only, never a
    /// value (invariant #6 / FF-M5-7). A crude but effective check: no entry
    /// looks like it embeds a URL with credentials, a token shape, or the
    /// word "secret" attached to anything but the word "Store" (i.e. we
    /// document THAT a secret store reference exists, never a secret
    /// itself).
    #[test]
    fn no_entry_carries_anything_that_looks_like_a_literal_secret_value() {
        for key in MANAGED_KEYS {
            let purpose_lower = key.purpose.to_ascii_lowercase();
            assert!(
                !purpose_lower.contains("sk-") && !purpose_lower.contains("://user:"),
                "key {:?}'s purpose string looks like it embeds a literal secret/credential: {}",
                key.name,
                key.purpose
            );
        }
    }
}
