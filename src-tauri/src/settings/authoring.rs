//! Manifest-authoring policy (M2/S4, DECISION-GATED on D-1-M2 —
//! `.copilot/wp/5.md` ADR-M2-001, S4 task brief).
//!
//! **No `cc` verb authors `copilot.layers.yml` from a pasted URL today**
//! (the WP's "verb path", recommended but not yet landed). This module is
//! the **fallback path**: it assembles a full, valid layer from a
//! [`dto::LayerInput`] using the **fixed, published** tier→role/rank table
//! below — never a user-entered rank, never a computed resolution
//! precedence, and never a network probe of the pasted repo (invariant #1
//! stays intact: this module emits the published tier order as data; the
//! `cc` resolver is what actually *acts* on it).
//!
//! ## What this module does NOT decide
//!
//! - **`rank`** is read off [`TIER_RANK_BASE`], a constant every reader can
//!   see — not invented per-call. (Personal wins over department wins over
//!   org wins over foundation, exactly `four-tier-topology.md` §4's example
//!   table: `personal: 10, department: 20, org: 30, foundation: 40` — this
//!   module only ever authors `org`/`dept`/`personal`, per [`dto::Tier`], so
//!   `foundation`'s rank never appears here.) Because `settings::validate`
//!   requires ranks to be **globally unique** across the *whole* manifest
//!   (mirroring `manifest.py`, not scoped per product), and a tier can carry
//!   one layer per product (the 4×4 model), each tier's published base is
//!   treated as a **10-wide band** (`base..base+9`) rather than a single
//!   number — see [`assign_free_rank`]. This is still "the published tier
//!   order", not a resolution computation: the band's *order* (personal <
//!   dept < org) is what the constant encodes, and nothing in this module
//!   ever reorders it.
//! - **`auth`** is never provisioned, never probed, never derived from the
//!   URL scheme — D-4-M2 reserves that to a real sign-in flow. A brand-new
//!   layer gets [`DEFAULT_AUTH_REF`], a placeholder *reference* (never a
//!   credential), so the manifest is structurally valid; an existing
//!   layer's already-configured `auth` is always preserved verbatim rather
//!   than clobbered by the placeholder on a repo-URL-only edit.
//!
//! ## Merge-by-id, guard, then validate — in that order
//!
//! [`author_manifest`] looks up each input's `(role, product)` slot against
//! `existing` FIRST (`find_existing_slot`): a slot that's already an
//! authored/hand-authored layer keeps its `id`/`rank`/`auth`/`activation`/
//! `unit` — an edit never reassigns identity or precedence out from under
//! itself. Only a genuinely new slot gets a fresh `<tier>-<product>` id and
//! a freshly assigned rank.
//!
//! Before returning, this module builds the FULL merged view (`existing`
//! plus the authored diff, via the SAME `writer::merge_by_id` the real write
//! path uses — never a second, drifting merge) and runs
//! `guard::scan_for_secrets`, `guard::enforce_write_allowlist`, and
//! `validate::validate_layers` against that whole document, per
//! `settings::guard`'s own doc ("the merged result, not just the incoming
//! edit"). Every problem found — this module's own per-field checks, a
//! guard refusal, and every validator error — is collected into one
//! `Vec<FieldError>`, never a fail-fast single error, so a Settings form can
//! show every problem in one pass.
//!
//! On success, [`author_manifest`] returns ONLY the authored diff (the
//! layers derived from `inputs`), matching `writer::write_manifest`'s own
//! `incoming` contract — the caller (S6) hands this straight to
//! `writer::write_manifest`, which re-reads `path` and re-merges/re-
//! validates for real at write time (a harmless, deliberate defense-in-depth
//! duplicate, not redundant plumbing: `existing` here is a snapshot, and the
//! on-disk file could in principle have moved between this call and the
//! actual write).

use std::collections::HashSet;

use super::dto::{LayerInput, Tier};
use super::guard;
use super::manifest::{Layer, LayerManifest, Source};
use super::validate::{rank_as_i64, validate_layers, FieldError};
use super::writer::merge_by_id;

/// Personal wins over department wins over org (foundation is never
/// authored via Settings — see the module doc). Matches
/// `four-tier-topology.md` §4's published example table exactly.
fn tier_rank_base(tier: Tier) -> i64 {
    match tier {
        Tier::Personal => 10,
        Tier::Dept => 20,
        Tier::Org => 30,
    }
}

/// How wide a tier's rank band is (`base..base+RANK_BAND_WIDTH`) — enough
/// room for well more than today's four known products
/// (`knowledge`/`cli`/`claude`/`codex`) at one tier without colliding with
/// the next tier's base, while still leaving the *next* tier's base
/// reachable as the gap-of-10 the published table uses.
const RANK_BAND_WIDTH: i64 = 10;

/// A brand-new layer's placeholder auth REFERENCE (never a credential —
/// D-4-M2). An existing layer's already-configured `auth` is always
/// preserved instead of being overwritten with this default (see
/// `find_existing_slot`'s callers below).
const DEFAULT_AUTH_REF: &str = "github";

const DEFAULT_ACTIVATION: &str = "always";

/// The manifest `role` vocabulary this module writes (`four-tier-topology.md`
/// §4) — deliberately NOT the same spelling as `Tier::wire()`'s `"dept"`
/// wire tag (the manifest spells it out in full, `"department"`).
fn tier_role(tier: Tier) -> &'static str {
    match tier {
        Tier::Personal => "personal",
        Tier::Dept => "department",
        Tier::Org => "org",
    }
}

/// Assembles a full valid [`Layer`] for each [`LayerInput`], merges the
/// result onto `existing` by id, and runs the guard + S1's validator against
/// the WHOLE merged document before ever returning success. See the module
/// doc for the full contract.
pub fn author_manifest(
    inputs: &[LayerInput],
    existing: &LayerManifest,
) -> Result<LayerManifest, Vec<FieldError>> {
    let mut errors: Vec<FieldError> = Vec::new();
    let mut authored: Vec<Layer> = Vec::new();

    // Ranks already spoken for on disk — a freshly-assigned rank must never
    // collide with one of these, whether or not it follows this module's own
    // band convention (a hand-authored manifest may use any integer).
    let mut taken_ranks: HashSet<i64> = existing
        .layers
        .iter()
        .filter_map(|l| l.rank.as_ref().and_then(rank_as_i64))
        .collect();

    for input in inputs {
        let label = format!("{}-{}", input.tier.wire(), input.product);
        let role = tier_role(input.tier);
        let repo_url = input.repo_url.trim();

        if repo_url.is_empty() {
            errors.push(FieldError {
                layer_id: Some(label),
                field: "repo_url".to_string(),
                message: "This field can't be empty.".to_string(),
            });
            continue;
        }
        if !looks_like_repo_url(repo_url) {
            errors.push(FieldError {
                layer_id: Some(label),
                field: "repo_url".to_string(),
                message: "That doesn't look like a repository URL. Try something like \
                          git@github.com:org/repo.git or https://github.com/org/repo.git."
                    .to_string(),
            });
            continue;
        }

        let existing_slot = find_existing_slot(existing, role, &input.product);

        let id = existing_slot
            .and_then(|l| l.id.clone())
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| label.clone());

        let rank = match existing_slot.and_then(|l| l.rank.as_ref().and_then(rank_as_i64)) {
            Some(r) => r,
            None => match assign_free_rank(input.tier, &taken_ranks) {
                Some(r) => r,
                None => {
                    errors.push(FieldError {
                        layer_id: Some(label),
                        field: "rank".to_string(),
                        message: "There's no room left to add another layer at this tier. \
                                  Remove or consolidate an existing layer first."
                            .to_string(),
                    });
                    continue;
                }
            },
        };
        taken_ranks.insert(rank);

        let auth = existing_slot
            .and_then(|l| l.auth.clone())
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_AUTH_REF.to_string());

        let activation = existing_slot
            .and_then(|l| l.activation.clone())
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_ACTIVATION.to_string());

        let unit = existing_slot.and_then(|l| l.unit.clone());
        let existing_source = existing_slot.and_then(|l| l.source.as_ref());
        let source_ref = existing_source.and_then(|s| s.r#ref.clone());
        let source_path = existing_source.and_then(|s| s.path.clone());
        let source_extra = existing_source.map(|s| s.extra.clone()).unwrap_or_default();
        let extra = existing_slot.map(|l| l.extra.clone()).unwrap_or_default();

        authored.push(Layer {
            id: Some(id),
            role: Some(role.to_string()),
            rank: Some(serde_yaml::Value::Number(rank.into())),
            product: Some(input.product.clone()),
            unit,
            source: Some(Source {
                repo: Some(repo_url.to_string()),
                r#ref: source_ref,
                path: source_path,
                extra: source_extra,
            }),
            auth: Some(auth),
            activation: Some(activation),
            extra,
        });
    }

    let incoming = LayerManifest {
        version: None,
        layers: authored,
        extra: Default::default(),
    };

    // The whole-document pass, per `guard`'s own doc: run every check
    // against the MERGED result, never just the incoming diff.
    let merged = merge_by_id(existing.clone(), &incoming).0;

    if let Err(e) = guard::scan_for_secrets(&merged) {
        errors.push(e.into());
    }
    if let Err(e) = guard::enforce_write_allowlist(&merged) {
        errors.push(e.into());
    }
    errors.extend(validate_layers(&merged));

    if !errors.is_empty() {
        return Err(errors);
    }

    Ok(incoming)
}

/// The existing layer occupying this `(role, product)` slot, if any — the
/// never-destroy identity/rank/auth/activation source of truth for an EDIT
/// (a brand-new slot has none, so the caller assigns fresh values).
fn find_existing_slot<'a>(
    existing: &'a LayerManifest,
    role: &str,
    product: &str,
) -> Option<&'a Layer> {
    existing
        .layers
        .iter()
        .find(|l| l.role.as_deref() == Some(role) && l.product.as_deref() == Some(product))
}

/// The lowest rank in `tier`'s band (`tier_rank_base(tier)..+RANK_BAND_WIDTH`)
/// not already in `taken` — `None` only if the band is exhausted (far beyond
/// today's four known products; see [`RANK_BAND_WIDTH`]'s doc).
fn assign_free_rank(tier: Tier, taken: &HashSet<i64>) -> Option<i64> {
    let base = tier_rank_base(tier);
    (0..RANK_BAND_WIDTH)
        .map(|offset| base + offset)
        .find(|candidate| !taken.contains(candidate))
}

/// A cheap, purely-syntactic (NO network I/O, NO probing the repo — invariant
/// #1 / the "no-network-in-authoring" fitness function) sanity check that
/// `value` is SHAPED like a repo URL: either `scheme://...` (`https://`,
/// `ssh://`, ...) or the `user@host:path` SSH shorthand
/// (`git@github.com:org/repo.git`, `git@github-personal:me/repo.git`).
/// Deliberately permissive beyond that — this is a friendly first-pass
/// sanity check, not a URL grammar validator; the CLI/resolver remains the
/// final authority on whether the repo is actually reachable.
fn looks_like_repo_url(value: &str) -> bool {
    if let Some(scheme_end) = value.find("://") {
        let scheme = &value[..scheme_end];
        let has_scheme = scheme_end > 0
            && scheme
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '-' || c == '.');
        let has_authority = value.len() > scheme_end + 3;
        return has_scheme && has_authority;
    }
    if let Some(at) = value.find('@') {
        let after_at = &value[at + 1..];
        if let Some(colon) = after_at.find(':') {
            let host = &after_at[..colon];
            let path = &after_at[colon + 1..];
            return !host.is_empty() && !host.contains('/') && !path.is_empty();
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::manifest::parse_manifest;

    fn fixture_manifest(name: &str) -> LayerManifest {
        let path = format!("{}/fixtures/settings/{name}", env!("CARGO_MANIFEST_DIR"));
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        parse_manifest(&text).unwrap_or_else(|e| panic!("parse {path}: {e}"))
    }

    fn input(product: &str, tier: Tier, repo_url: &str) -> LayerInput {
        LayerInput {
            product: product.to_string(),
            tier,
            repo_url: repo_url.to_string(),
        }
    }

    // -- happy path: tier-ordered ranks + a placeholder auth reference -----

    #[test]
    fn a_brand_new_personal_layer_gets_the_published_rank_and_a_reference_auth() {
        let existing = LayerManifest::default();
        let inputs = vec![input(
            "claude",
            Tier::Personal,
            "git@github-personal:me/claude-personal.git",
        )];

        let result = author_manifest(&inputs, &existing).expect("should author cleanly");
        assert_eq!(result.layers.len(), 1);
        let layer = &result.layers[0];
        assert_eq!(layer.id.as_deref(), Some("personal-claude"));
        assert_eq!(layer.role.as_deref(), Some("personal"));
        assert_eq!(layer.rank, Some(serde_yaml::Value::Number(10.into())));
        assert_eq!(layer.auth.as_deref(), Some("github"));
        assert_ne!(
            layer.auth.as_deref(),
            None,
            "auth is never blank — S1's validator requires it non-empty"
        );
        assert_eq!(layer.activation.as_deref(), Some("always"));
    }

    #[test]
    fn multiple_products_at_the_same_tier_get_distinct_ranks_in_the_tiers_band() {
        let existing = LayerManifest::default();
        let inputs = vec![
            input(
                "knowledge",
                Tier::Personal,
                "git@github-personal:me/knowledge.git",
            ),
            input("cli", Tier::Personal, "git@github-personal:me/cli.git"),
            input(
                "claude",
                Tier::Personal,
                "git@github-personal:me/claude.git",
            ),
            input("codex", Tier::Personal, "git@github-personal:me/codex.git"),
        ];

        let result = author_manifest(&inputs, &existing).expect("should author cleanly");
        let mut ranks: Vec<i64> = result
            .layers
            .iter()
            .map(|l| l.rank.as_ref().and_then(rank_as_i64).unwrap())
            .collect();
        ranks.sort_unstable();
        assert_eq!(
            ranks,
            vec![10, 11, 12, 13],
            "ranks must be unique and stay in personal's band"
        );
        // The merged (validated) result must actually pass S1's validator —
        // proves the whole batch is genuinely non-colliding, not just this
        // module's own bookkeeping.
        assert!(validate_layers(&LayerManifest {
            version: None,
            layers: result.layers.clone(),
            extra: Default::default(),
        })
        .is_empty());
    }

    #[test]
    fn tier_order_is_the_published_table_not_user_entered() {
        let existing = LayerManifest::default();
        let inputs = vec![
            input(
                "claude",
                Tier::Personal,
                "git@github-personal:me/claude.git",
            ),
            input("claude", Tier::Dept, "git@github-work:acme/claude-dept.git"),
            input("claude", Tier::Org, "git@github-work:acme/claude-org.git"),
        ];
        let result = author_manifest(&inputs, &existing).expect("should author cleanly");
        let rank_of = |tier: &str| {
            result
                .layers
                .iter()
                .find(|l| l.role.as_deref() == Some(tier))
                .and_then(|l| l.rank.as_ref().and_then(rank_as_i64))
                .unwrap()
        };
        assert!(rank_of("personal") < rank_of("department"));
        assert!(rank_of("department") < rank_of("org"));
    }

    // -- never-destroy: editing an existing slot keeps its identity --------

    #[test]
    fn editing_an_existing_slot_reuses_its_id_rank_and_auth() {
        let existing = fixture_manifest("valid-multi-layer.yml");
        let original = existing
            .layers
            .iter()
            .find(|l| l.id.as_deref() == Some("personal-pablo"))
            .expect("fixture has personal-pablo");
        let original_rank = original.rank.clone();
        let original_auth = original.auth.clone();

        let inputs = vec![input(
            "claude", // matches the fixture's personal layer's product
            Tier::Personal,
            "git@github-personal:pablitoalejo/renamed-repo.git",
        )];

        let result = author_manifest(&inputs, &existing).expect("should author cleanly");
        assert_eq!(result.layers.len(), 1);
        let layer = &result.layers[0];
        assert_eq!(
            layer.id.as_deref(),
            Some("personal-pablo"),
            "id must be reused, not regenerated"
        );
        assert_eq!(
            layer.rank, original_rank,
            "rank must be reused, not reassigned"
        );
        assert_eq!(
            layer.auth, original_auth,
            "an existing auth reference must be preserved"
        );
        assert_eq!(
            layer.source.as_ref().and_then(|s| s.repo.as_deref()),
            Some("git@github-personal:pablitoalejo/renamed-repo.git")
        );
    }

    // -- friendly, plain-language field errors ------------------------------

    #[test]
    fn an_empty_repo_url_is_a_plain_language_field_error() {
        let existing = LayerManifest::default();
        let inputs = vec![input("claude", Tier::Personal, "   ")];
        let errors = author_manifest(&inputs, &existing).expect_err("must refuse");
        assert!(errors
            .iter()
            .any(|e| e.field == "repo_url" && e.message == "This field can't be empty."));
    }

    #[test]
    fn a_malformed_repo_url_is_a_plain_language_field_error_never_a_raw_parse_error() {
        let existing = LayerManifest::default();
        let inputs = vec![input("claude", Tier::Personal, "not-a-repo")];
        let errors = author_manifest(&inputs, &existing).expect_err("must refuse");
        let err = errors.iter().find(|e| e.field == "repo_url").unwrap();
        assert!(err.message.contains("doesn't look like a repository URL"));
        let lower = err.message.to_lowercase();
        for banned in ["yaml", "serde", "panicked", "traceback", "err("] {
            assert!(!lower.contains(banned), "leaked jargon: {}", err.message);
        }
    }

    #[test]
    fn multiple_bad_inputs_collect_every_error_not_just_the_first() {
        // An `existing` manifest that already has a valid layer, so the ONLY
        // errors possible are the two field-level problems below (not also
        // a manifest-wide "no layers at all" complaint, which would be a
        // separate, correct-but-unrelated fact about this particular empty
        // starting manifest rather than about "did we collect every
        // problem").
        let existing = fixture_manifest("valid-multi-layer.yml");
        let inputs = vec![
            input("claude", Tier::Personal, ""), // collides with the fixture's own personal-pablo/claude slot, but the empty check runs first and short-circuits before any collision would matter
            input("codex", Tier::Personal, "not-a-repo"),
        ];
        let errors = author_manifest(&inputs, &existing).expect_err("must refuse");
        assert!(
            errors
                .iter()
                .any(|e| e.field == "repo_url" && e.message == "This field can't be empty."),
            "missing the empty-field error: {errors:?}"
        );
        assert!(
            errors.iter().any(|e| e.field == "repo_url"
                && e.message.contains("doesn't look like a repository URL")),
            "missing the malformed-url error: {errors:?}"
        );
        assert_eq!(
            errors.len(),
            2,
            "no extra/unrelated errors expected: {errors:?}"
        );
    }

    // -- guard wiring: a secret must never reach the returned manifest ------

    #[test]
    fn a_secret_looking_auth_cannot_be_smuggled_in_via_an_existing_slot() {
        // Even though authoring never lets the UI set `auth` directly, the
        // guard must still run on the MERGED result — an existing
        // hand-authored secret-looking value elsewhere in the file must
        // still block the save (defense in depth), not just the freshly
        // authored fields.
        let existing = fixture_manifest("secret-looking-auth.yml");
        let inputs = vec![input(
            "codex",
            Tier::Personal,
            "git@github-personal:me/codex.git",
        )];
        let errors = author_manifest(&inputs, &existing).expect_err("must refuse");
        assert!(errors
            .iter()
            .any(|e| e.field == "auth" || e.message.contains("Credentials must never")));
    }

    #[test]
    fn an_embedded_credential_in_a_freshly_pasted_repo_url_is_refused_by_the_guard() {
        let existing = LayerManifest::default();
        let inputs = vec![input(
            "claude",
            Tier::Personal,
            "https://x:ghp_1234567890ABCDEFabcdef1234567890AB@github.com/me/repo.git",
        )];
        let errors = author_manifest(&inputs, &existing).expect_err("must refuse");
        assert!(errors.iter().any(|e| e.field == "source.repo"));
        for e in &errors {
            assert!(
                !e.message.contains("ghp_1234567890ABCDEFabcdef1234567890AB"),
                "must never echo the secret value: {}",
                e.message
            );
        }
    }

    #[test]
    fn a_disallowed_key_hiding_in_an_existing_hand_authored_file_still_blocks_the_save() {
        let existing = fixture_manifest("secret-sensitive-key-injection.yml");
        let inputs = vec![input(
            "codex",
            Tier::Personal,
            "git@github-personal:me/codex.git",
        )];
        let errors = author_manifest(&inputs, &existing).expect_err("must refuse");
        assert!(!errors.is_empty());
    }

    // -- no network I/O (fitness) -------------------------------------------

    #[test]
    fn looks_like_repo_url_accepts_both_known_shapes() {
        assert!(looks_like_repo_url("git@github.com:org/repo.git"));
        assert!(looks_like_repo_url("git@github-personal:me/repo.git"));
        assert!(looks_like_repo_url("https://github.com/org/repo.git"));
        assert!(looks_like_repo_url("ssh://git@github.com/org/repo.git"));
        assert!(!looks_like_repo_url("not-a-repo"));
        assert!(!looks_like_repo_url(""));
        assert!(!looks_like_repo_url("://missing-scheme"));
    }
}
