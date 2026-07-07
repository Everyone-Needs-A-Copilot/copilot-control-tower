//! Managed-vs-unmanaged gate (M2/S5, `.copilot/wp/5.md` ADR-M2-004, D-2-M2).
//!
//! **The critical framing (WP §0):** on a managed machine, `org`/`dept`
//! layers are produced by `cc derive` from the MDM-delivered `ecosystem.yml`
//! — Settings must never fight or overwrite that. Settings-writes-repo-URLs
//! is the unmanaged/solo/author path; at most the `personal` row stays
//! editable on a managed machine.
//!
//! ## Detection — invariant #4: forced/managed domain ONLY
//!
//! [`is_managed`] answers "is this machine under an MDM-delivered managed
//! ecosystem config" by checking whether a KNOWN managed-only key is
//! **forced** in this app's macOS preferences domain
//! (`CFPreferencesAppValueIsForced`) — never merely "does this key have a
//! value" (an ordinary user default, e.g. from `defaults write` at the user
//! level, is NOT forced and must NOT read as managed). [`MANAGED_INDICATOR_KEYS`]
//! deliberately reuses two names already on `settings::guard`'s
//! forced/managed-domain-only deny-list (`EcosystemSeedURL`,
//! `DisableWizard`) rather than inventing a third managed-detection key —
//! "what counts as managed" and "what Settings may never write" stay the
//! same vocabulary.
//!
//! ## The dev-mockable seam
//!
//! [`MANAGED_OVERRIDE_ENV`] (`CT_MANAGED_OVERRIDE=1`/`0`) lets a debug/test
//! build simulate managed=true/false without a real `.mobileconfig` push —
//! the SAME `#[cfg(any(debug_assertions, test))]`-gated pattern as
//! `cli::path::DEV_OVERRIDE_ENV` (`CT_CLI_PATH`): the constant, and the only
//! code path that reads it, are compiled OUT of a release binary entirely,
//! not merely unread at runtime (see that module's doc for the full
//! release-build-safety argument, which applies identically here). A shipped
//! build can therefore never be told "you are/aren't managed" by an
//! environment variable — only the real forced domain can ever answer that
//! question in production, matching invariant #4's "honored ONLY from the
//! forced/managed domain" to the letter (an env var read from user-writable
//! process state is exactly the kind of "not the forced domain" source
//! invariant #4 forbids for a shipped build).
//!
//! ## Batched for owner verification
//!
//! The real `CFPreferencesAppValueIsForced` behavior under a genuinely
//! pushed `.mobileconfig` on an MDM-enrolled Mac cannot be exercised by
//! `cargo test` — there is no forced domain on a plain dev machine. This is
//! explicitly flagged in `.copilot/wp/5.md` §4 as needing a managed Mac to
//! confirm; owner verification is the only way to close that gap. What IS
//! verified by this crate's tests: the FFI call shape compiles and runs
//! (`real_is_managed` is exercised against genuinely UNFORCED keys on this
//! dev machine and must return `false`, proving the binding itself works
//! end to end here) and the override seam's on/off behavior.

use super::dto::{LayerInput, LayerRow, Tier};
use super::validate::FieldError;

/// The macOS application-preferences domain this app's managed keys would be
/// forced under — matches `tauri.conf.json`'s `identifier`.
const APPLICATION_ID: &str = "com.everyoneneedsacopilot.controltower";

/// Any ONE of these being forced in [`APPLICATION_ID`]'s domain means this
/// machine has an MDM-delivered managed ecosystem. See the module doc for
/// why these particular two names.
const MANAGED_INDICATOR_KEYS: &[&str] = &["EcosystemSeedURL", "DisableWizard"];

/// Dev/test-only override env var — see the module doc's "dev-mockable
/// seam" section. Not present at all in a release build (no `#[cfg(test)]`
/// needed here the way `cli::path::DEV_OVERRIDE_ENV` needs it, since this
/// module's own tests call `dev_override()` directly rather than round-
/// tripping through `std::env`+the public constant the way `cli::path`'s
/// do — but the reader function itself, `dev_override`, is still gated
/// identically for defense in depth).
#[cfg(any(debug_assertions, test))]
pub const MANAGED_OVERRIDE_ENV: &str = "CT_MANAGED_OVERRIDE";

/// `true` when this machine is under a forced/managed-domain ecosystem
/// config (D-2-M2). See the module doc for the dev-only override seam and
/// what's batched for owner verification.
pub fn is_managed() -> bool {
    #[cfg(any(debug_assertions, test))]
    {
        if let Some(over) = dev_override() {
            return over;
        }
    }
    real_is_managed()
}

#[cfg(any(debug_assertions, test))]
fn dev_override() -> Option<bool> {
    match std::env::var(MANAGED_OVERRIDE_ENV) {
        Ok(v) if v == "1" => Some(true),
        Ok(v) if v == "0" => Some(false),
        _ => None,
    }
}

#[cfg(target_os = "macos")]
fn real_is_managed() -> bool {
    MANAGED_INDICATOR_KEYS.iter().any(|key| key_is_forced(key))
}

/// No forced-domain concept off macOS yet (a future Windows re-skin, M9/
/// WS-I, gets its own boundary shim per CLAUDE.md's "design every OS-
/// integration edge so Windows is a re-skin") — fails closed to "not
/// managed" rather than guessing, matching the honest-never-guess discipline
/// this crate uses elsewhere (e.g. `commands::initial_render_state`).
#[cfg(not(target_os = "macos"))]
fn real_is_managed() -> bool {
    false
}

#[cfg(target_os = "macos")]
fn key_is_forced(key: &str) -> bool {
    use core_foundation::base::TCFType;
    use core_foundation::string::CFString;
    use core_foundation_sys::preferences::CFPreferencesAppValueIsForced;

    let cf_key = CFString::new(key);
    let cf_app_id = CFString::new(APPLICATION_ID);
    // SAFETY: both `CFString`s are kept alive for the duration of this call
    // (they aren't dropped until this function returns), and
    // `CFPreferencesAppValueIsForced` only reads them — this is the standard
    // core-foundation-sys FFI call shape (pass a borrowed `CFStringRef` via
    // `as_concrete_TypeRef()`, never transfer ownership across the FFI
    // boundary).
    let forced = unsafe {
        CFPreferencesAppValueIsForced(
            cf_key.as_concrete_TypeRef(),
            cf_app_id.as_concrete_TypeRef(),
        )
    };
    forced != 0
}

/// Applies the managed gate to already-projected [`LayerRow`]s
/// (`commands::get_settings`): on a managed machine, every `org`/`dept` row
/// becomes `editable: false` — `personal` always stays editable regardless
/// (Settings-writes-repo-URLs is at most the personal-tier row on a managed
/// machine, per the WP's "critical framing"). A no-op when `managed` is
/// `false`.
pub fn apply_gate(rows: &mut [LayerRow], managed: bool) {
    if !managed {
        return;
    }
    for row in rows.iter_mut() {
        if row.tier != Tier::Personal {
            row.editable = false;
        }
    }
}

/// Refuses any `inputs` entry that targets a locked (managed, non-personal)
/// tier — called BEFORE authoring/writing (`commands::save_settings`). A
/// save containing an `org`/`dept` edit on a managed machine fails closed
/// with a plain-language [`FieldError`] rather than silently accepting or
/// silently dropping just that one edit (no silent partial success). Looks
/// up each refused input's REAL current row id from `current_rows` (the same
/// projection `get_settings` already returned) so the error attaches to the
/// row the UI actually rendered; a slot with no row yet falls back to the
/// `<tier>-<product>` id convention `authoring::author_manifest` would have
/// used, so the error still has a stable, predictable id even then.
pub fn refuse_locked_writes(
    inputs: &[LayerInput],
    current_rows: &[LayerRow],
    managed: bool,
) -> Vec<FieldError> {
    if !managed {
        return Vec::new();
    }
    inputs
        .iter()
        .filter(|input| input.tier != Tier::Personal)
        .map(|input| {
            let layer_id = current_rows
                .iter()
                .find(|row| row.product == input.product && row.tier == input.tier)
                .map(|row| row.id.clone())
                .unwrap_or_else(|| format!("{}-{}", input.tier.wire(), input.product));
            FieldError {
                layer_id: Some(layer_id),
                field: "repo_url".to_string(),
                message: "This layer is managed by your organization. Settings can only change \
                          your personal layer here — talk to your IT admin about org/department \
                          repositories."
                    .to_string(),
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    // The SAME shared lock `cli::path`'s/`cli::spawn`'s/`cli::mod`'s tests
    // use for `CT_CLI_PATH` (see `cli::test_env`) — reused here (rather than
    // a second, module-local lock) because `commands::tests` ALSO mutates
    // `CT_MANAGED_OVERRIDE` alongside `CT_CLI_PATH` in its own save_settings
    // integration tests; every process-global-env-var-touching test in this
    // crate must serialize on the ONE lock, or two different locks would
    // fail to prevent exactly the interleaving race they each exist to
    // prevent.
    use crate::cli::test_env::ENV_LOCK;

    fn row(product: &str, tier: Tier, editable: bool) -> LayerRow {
        LayerRow {
            id: format!("{}-{}", tier.wire(), product),
            product: product.to_string(),
            tier,
            repo_url: "git@github.com:acme/repo.git".to_string(),
            auth_ref: "github".to_string(),
            rank: 10,
            editable,
        }
    }

    fn input(product: &str, tier: Tier) -> LayerInput {
        LayerInput {
            product: product.to_string(),
            tier,
            repo_url: "git@github.com:acme/repo.git".to_string(),
        }
    }

    // -- dev override seam ---------------------------------------------

    #[test]
    fn override_1_reports_managed() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "1") };
        assert!(is_managed());
        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
    }

    #[test]
    fn override_0_reports_unmanaged() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "0") };
        assert!(!is_managed());
        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
    }

    #[test]
    fn unset_override_falls_through_to_the_real_forced_domain_check() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK. No `.mobileconfig` is pushed on
        // this dev machine, so the real check must honestly report
        // unmanaged — proves the FFI binding itself runs end to end without
        // panicking, even though the true forced-domain behavior needs a
        // managed Mac to confirm (see the module doc).
        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
        assert!(!is_managed());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn an_unforced_key_on_this_dev_machine_is_reported_as_not_forced() {
        assert!(!key_is_forced("EcosystemSeedURL"));
        assert!(!key_is_forced("DisableWizard"));
        assert!(!key_is_forced("SomeKeyThatDoesNotExistAtAll"));
    }

    // -- apply_gate -------------------------------------------------------

    #[test]
    fn unmanaged_leaves_every_row_editable() {
        let mut rows = vec![
            row("claude", Tier::Org, true),
            row("claude", Tier::Personal, true),
        ];
        apply_gate(&mut rows, false);
        assert!(rows.iter().all(|r| r.editable));
    }

    #[test]
    fn managed_locks_org_and_dept_but_never_personal() {
        let mut rows = vec![
            row("claude", Tier::Org, true),
            row("claude", Tier::Dept, true),
            row("claude", Tier::Personal, true),
        ];
        apply_gate(&mut rows, true);
        assert!(!rows[0].editable, "org must be locked when managed");
        assert!(!rows[1].editable, "dept must be locked when managed");
        assert!(rows[2].editable, "personal must always stay editable");
    }

    // -- refuse_locked_writes ----------------------------------------------

    #[test]
    fn unmanaged_refuses_nothing() {
        let inputs = vec![input("claude", Tier::Org)];
        let errors = refuse_locked_writes(&inputs, &[], false);
        assert!(errors.is_empty());
    }

    #[test]
    fn managed_refuses_org_and_dept_but_not_personal() {
        let inputs = vec![
            input("claude", Tier::Org),
            input("claude", Tier::Dept),
            input("claude", Tier::Personal),
        ];
        let errors = refuse_locked_writes(&inputs, &[], true);
        assert_eq!(errors.len(), 2, "only org+dept must be refused: {errors:?}");
        assert!(errors
            .iter()
            .all(|e| e.message.contains("managed by your organization")));
    }

    #[test]
    fn a_refusal_attaches_to_the_rows_real_existing_id_when_one_exists() {
        let existing_rows = vec![LayerRow {
            id: "org-acme".to_string(), // a hand-authored id, NOT the "<tier>-<product>" convention
            product: "claude".to_string(),
            tier: Tier::Org,
            repo_url: "git@github-work:acme/claude-org.git".to_string(),
            auth_ref: "ssh-work".to_string(),
            rank: 30,
            editable: false,
        }];
        let inputs = vec![input("claude", Tier::Org)];
        let errors = refuse_locked_writes(&inputs, &existing_rows, true);
        assert_eq!(errors.len(), 1);
        assert_eq!(
            errors[0].layer_id.as_deref(),
            Some("org-acme"),
            "must attach to the REAL row id so the UI's error binding (by row.id) finds it"
        );
    }

    #[test]
    fn a_refusal_falls_back_to_the_tier_product_convention_id_when_no_row_exists_yet() {
        let inputs = vec![input("codex", Tier::Dept)];
        let errors = refuse_locked_writes(&inputs, &[], true);
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].layer_id.as_deref(), Some("dept-codex"));
    }

    #[test]
    fn refusal_message_never_leaks_raw_git_or_yaml_jargon() {
        let inputs = vec![input("claude", Tier::Org)];
        let errors = refuse_locked_writes(&inputs, &[], true);
        let lower = errors[0].message.to_lowercase();
        for banned in ["yaml", "serde", "traceback", "panicked", "err("] {
            assert!(
                !lower.contains(banned),
                "leaked jargon: {}",
                errors[0].message
            );
        }
    }
}
