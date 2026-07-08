//! The SOLE audited `CFPreferences` FFI boundary in this crate (M5/S1,
//! `.copilot/wp/30.md` ADR-M5-001, invariant #4). Before this milestone, two
//! independent, hand-rolled copies of this exact FFI call shape existed:
//! `settings::managed::key_is_forced` (M2) and `updater::trust::real_lookup`
//! (M4). A third copy — for the new S3/S5/S6 keys — would have meant the
//! single most security-critical surface in the app (invariant #4: "security
//! posture is inherited and enforced, never weakened... honored only from
//! the forced/managed domain") was triplicated and un-auditable as a whole.
//! This module is the fix: `CFPreferencesAppValueIsForced` and
//! `CFPreferencesCopyAppValue` appear HERE and nowhere else in
//! `src-tauri/src` (enforced by `tests/fitness_m5_single_forced_boundary.rs`,
//! FF-M5-1). `settings::managed` and `updater::trust` now DELEGATE to this
//! module instead of each carrying their own FFI call — their own public
//! behavior and existing tests are unchanged by this refactor.
//!
//! ## The three-way decision (never a plain `Option`)
//!
//! [`ForcedLookup`] distinguishes THREE outcomes, not two, because "does
//! this key have a value" is the wrong question — invariant #4 asks "is this
//! key **forced**":
//!
//! - [`ForcedLookup::Forced`] — `CFPreferencesAppValueIsForced` is true. This
//!   is the ONLY case whose value may ever be honored.
//! - [`ForcedLookup::IgnoredUserDomain`] — a value exists (an ordinary
//!   `defaults write` at the user level) but is NOT forced. This is the
//!   Convenience-Backdoor shape invariant #4 forbids — the SOUL anti-pattern
//!   of "a setting that's supposed to be locked down but has a plausible
//!   looking escape hatch." It is always ignored, and the attempt is logged
//!   as a tamper event via [`audit_ignored_user_domain_value`] (the existing
//!   interim `eprintln!`-based facility `model::state::audit_invalid_content`
//!   already established — no secret, no user-controlled value, key name
//!   only).
//! - [`ForcedLookup::Absent`] — no value at all, forced or otherwise. The
//!   ordinary, silent, "nothing configured" case.
//!
//! [`resolve_string`]/[`resolve_bool`] fold this three-way outcome plus a
//! compiled-in default into the final value every caller actually uses,
//! auditing the `IgnoredUserDomain` case on the way. Splitting the pure
//! fold (easily unit-testable without a managed Mac — construct a
//! [`ForcedLookup`] directly, as this module's own tests and
//! `updater::trust`'s tests already did before this refactor) from the
//! OS-touching lookup itself (`real_key_is_forced`/`real_forced_string`,
//! gated `#[cfg(target_os = "macos")]`) is the same split
//! `settings::managed::apply_gate`/`is_managed` and
//! `updater::trust`'s old `resolve`/`real_lookup` each already used
//! independently — now shared, not reinvented a third time.
//!
//! ## Two entry points, deliberately not one
//!
//! [`key_is_forced`] answers "is ANY value forced for this key at all" with
//! a single `CFPreferencesAppValueIsForced` call and nothing else — this is
//! `settings::managed::is_managed`'s exact original shape (a managed
//! INDICATOR key like `DisableWizard`/`EcosystemSeedURL` may be forced as a
//! non-string plist type; casting its value to a `CFString` just to check
//! forced-ness would risk misreading a differently-typed value). It never
//! calls `CFPreferencesCopyAppValue`.
//!
//! [`forced_string`]/[`forced_bool`] additionally read the VALUE (via
//! `CFPreferencesCopyAppValue`) for keys this crate actually needs to
//! interpret (`UpdateFeedURL`, `AllowSelfUpdate`, …) — this is
//! `updater::trust::real_lookup`'s exact original shape, carried over.
//! `CFPreferencesCopyAppValue` returns a `CFTypeRef` whose ACTUAL underlying
//! type depends on how the `.mobileconfig`/managed profile declared it (a
//! boolean-typed managed key is delivered as a `CFBoolean`, not a
//! `CFString`).
//!
//! **M5/S5 fix (previously a flagged, evidence-based residual gap):** S1's
//! original version of this module — like the M4 code it replaced —
//! unconditionally cast the returned pointer to `CFStringRef` regardless of
//! its actual runtime type; a non-string-typed forced value could have been
//! misread as string data (garbage in the best case, undefined behavior in
//! the worst). `real_forced_string` now calls `CFGetTypeID` on the returned
//! value and compares it against `CFStringGetTypeID()` **before** ever
//! casting; a value of any other CF type is released (never leaked) and
//! reported as [`ForcedLookup::Absent`] — never guessed, never
//! reinterpreted. See `real_forced_string`'s own inline comment for the
//! exact check, and `tests::a_wrong_typed_forced_value_is_never_misread_as_a_string`
//! for the regression test (constructed via the dev-seam override, since a
//! genuine wrong-typed managed value needs a real `.mobileconfig`, which
//! this crate's tests cannot push).
//!
//! ## The dev-mockable seam
//!
//! `CT_FORCED_OVERRIDE_<KEY>` (env var, per-key) lets a debug/test build
//! simulate `forced:<value>` / `user` / `absent` for any registry key
//! without a real `.mobileconfig` push — generalizing
//! `settings::managed`'s original `CT_MANAGED_OVERRIDE` (which stays exactly
//! where it is, unchanged: it overrides the higher-level "is this machine
//! managed at all" business decision, a different concern from this
//! module's raw per-key FFI seam). Gated `#[cfg(any(debug_assertions, test,
//! feature = "dev-seam"))]` — the SAME widened gate `cli::path::DEV_OVERRIDE_ENV`
//! uses (see that module's doc for the full release-build-safety argument:
//! `debug_assertions` alone leaves a `cargo test --release`/external
//! integration-test build with the seam silently missing, and `feature =
//! "dev-seam"` closes that gap via the `[dev-dependencies]` self-dependency
//! in `Cargo.toml` without ever reaching a genuine `cargo build --release`
//! artifact). A shipped release binary therefore has NEITHER the constant
//! NOR the function compiled in at all — not merely unread at runtime.
//!
//! ## Batched for owner verification
//!
//! The real `CFPreferencesAppValueIsForced`/`CFPreferencesCopyAppValue`
//! behavior under a genuinely pushed `.mobileconfig` on an MDM-enrolled Mac
//! cannot be exercised by `cargo test` — there is no forced domain on a
//! plain dev machine. What IS verified here: the FFI call shape compiles and
//! runs (`real_key_is_forced`/`real_forced_string` are exercised against
//! genuinely unforced keys on this dev machine and must report
//! `false`/`Absent`), the override seam's behavior, and the pure
//! `resolve_string`/`resolve_bool` decision logic for all three
//! [`ForcedLookup`] variants.

use std::fmt;

use super::keys::APPLICATION_ID;

/// The three-way outcome of asking "what does the managed-preferences
/// domain say about this key" — see the module doc. Never constructed
/// directly outside this module (and the dev-seam override, gated
/// identically) — every caller gets it from [`forced_string`]/[`forced_bool`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ForcedLookup<T> {
    /// `CFPreferencesAppValueIsForced` is true for this key. The ONLY
    /// variant whose value may ever be honored.
    Forced(T),
    /// A value exists in the (user-writable) domain but is NOT forced.
    /// Always ignored; always logged as a tamper event.
    IgnoredUserDomain,
    /// No value at all, forced or otherwise.
    Absent,
}

impl<T> ForcedLookup<T> {
    /// `true` only for [`ForcedLookup::Forced`] — used by FF-M5-5's tests to
    /// assert a registry key's resolved value can only ever trace back to a
    /// genuinely forced lookup.
    pub fn is_forced(&self) -> bool {
        matches!(self, ForcedLookup::Forced(_))
    }
}

// ---------------------------------------------------------------------------
// The dev-mockable per-key override seam
// ---------------------------------------------------------------------------

/// Env-var name prefix for the dev/test-only per-key override — see the
/// module doc's "dev-mockable seam" section. `CT_FORCED_OVERRIDE_UPDATEFEEDURL`
/// (key name upper-cased) is checked before ever touching real
/// `CFPreferences`. Recognized values: `forced:<value>` ->
/// [`ForcedLookup::Forced`], `user` -> [`ForcedLookup::IgnoredUserDomain`],
/// `absent` -> [`ForcedLookup::Absent`]. An unset or unrecognized value falls
/// through to the real lookup rather than silently misbehaving.
#[cfg(any(debug_assertions, test, feature = "dev-seam"))]
pub const FORCED_OVERRIDE_ENV_PREFIX: &str = "CT_FORCED_OVERRIDE_";

#[cfg(any(debug_assertions, test, feature = "dev-seam"))]
fn dev_override_string(key: &str) -> Option<ForcedLookup<String>> {
    let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
    let raw = std::env::var(env_name).ok()?;
    if let Some(value) = raw.strip_prefix("forced:") {
        Some(ForcedLookup::Forced(value.to_string()))
    } else if raw == "user" {
        Some(ForcedLookup::IgnoredUserDomain)
    } else if raw == "absent" {
        Some(ForcedLookup::Absent)
    } else {
        None
    }
}

// ---------------------------------------------------------------------------
// key_is_forced — forced-ness only, no value read (settings::managed's shape)
// ---------------------------------------------------------------------------

/// `true` iff `key` is forced in [`APPLICATION_ID`]'s domain
/// (`CFPreferencesAppValueIsForced`), regardless of the value's type or
/// content. Never reads the value itself — see the module doc for why this
/// is kept as its own entry point rather than folded into
/// [`forced_string`].
pub fn key_is_forced(key: &str) -> bool {
    #[cfg(any(debug_assertions, test, feature = "dev-seam"))]
    {
        if let Some(over) = dev_override_string(key) {
            return over.is_forced();
        }
    }
    real_key_is_forced(key)
}

#[cfg(target_os = "macos")]
fn real_key_is_forced(key: &str) -> bool {
    use core_foundation::base::TCFType;
    use core_foundation::string::CFString;
    use core_foundation_sys::preferences::CFPreferencesAppValueIsForced;

    let cf_key = CFString::new(key);
    let cf_app_id = CFString::new(APPLICATION_ID);
    // SAFETY: both `CFString`s are kept alive for the duration of this call
    // (neither is dropped until this function returns), and
    // `CFPreferencesAppValueIsForced` only reads them — the standard
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

/// No forced-domain concept off macOS yet (a future Windows re-skin, M9/
/// WS-I, gets its own boundary shim per CLAUDE.md's "design every OS-
/// integration edge so Windows is a re-skin") — fails closed to "not forced"
/// rather than guessing.
#[cfg(not(target_os = "macos"))]
fn real_key_is_forced(_key: &str) -> bool {
    false
}

// ---------------------------------------------------------------------------
// forced_string / forced_bool — forced-ness AND value (updater::trust's shape)
// ---------------------------------------------------------------------------

/// The forced-domain-only string reader. Returns [`ForcedLookup::Absent`]
/// whenever `CFPreferencesCopyAppValue` returns nothing, REGARDLESS of
/// whether the key is forced (matches the exact pre-existing behavior of
/// `updater::trust::real_lookup`, carried over unchanged by this refactor —
/// see the module doc's "two entry points" section for the known residual
/// type-cast limitation this inherits).
pub fn forced_string(key: &str) -> ForcedLookup<String> {
    #[cfg(any(debug_assertions, test, feature = "dev-seam"))]
    {
        if let Some(over) = dev_override_string(key) {
            return over;
        }
    }
    real_forced_string(key)
}

/// The forced-domain-only boolean reader, built on [`forced_string`]. Parse
/// rule (matches `updater::trust::allow_self_update`'s pre-existing,
/// availability-safe interpretation exactly): `"false"`/`"0"`/`"no"`
/// (case-insensitive) means `false`; any other forced string means `true`.
/// **This "ambiguous forced value defaults to `true`" direction is only
/// correct for an availability toggle** (`AllowSelfUpdate`'s own doc
/// explains why: "the safe failure mode for an availability toggle is 'keep
/// updating'"). A caller needing the OPPOSITE fail-safe direction for a
/// different key (e.g. `Deprovisioned` — an ambiguous forced value should
/// almost certainly NOT trigger a wipe) must not blindly reuse this
/// function; it should read [`forced_string`] directly and apply its own,
/// key-appropriate interpretation, exactly as `updater::trust` already does
/// for its three keys.
pub fn forced_bool(key: &str) -> ForcedLookup<bool> {
    match forced_string(key) {
        ForcedLookup::Forced(value) => ForcedLookup::Forced(!matches!(
            value.to_ascii_lowercase().as_str(),
            "false" | "0" | "no"
        )),
        ForcedLookup::IgnoredUserDomain => ForcedLookup::IgnoredUserDomain,
        ForcedLookup::Absent => ForcedLookup::Absent,
    }
}

#[cfg(target_os = "macos")]
fn real_forced_string(key: &str) -> ForcedLookup<String> {
    use core_foundation::base::{CFType, TCFType};
    use core_foundation::string::{CFString, CFStringRef};
    use core_foundation_sys::base::CFGetTypeID;
    use core_foundation_sys::preferences::{
        CFPreferencesAppValueIsForced, CFPreferencesCopyAppValue,
    };
    use core_foundation_sys::string::CFStringGetTypeID;

    let cf_key = CFString::new(key);
    let cf_app_id = CFString::new(APPLICATION_ID);

    // SAFETY: both `CFString`s outlive both FFI calls below (neither is
    // dropped until this function returns); `CFPreferencesAppValueIsForced`
    // only reads them.
    let forced = unsafe {
        CFPreferencesAppValueIsForced(
            cf_key.as_concrete_TypeRef(),
            cf_app_id.as_concrete_TypeRef(),
        )
    } != 0;

    // SAFETY: `CFPreferencesCopyAppValue` returns a `CFTypeRef` we OWN (the
    // "Copy" in its name is Core Foundation's own ownership convention) or
    // null if absent; wrapping it immediately in an `Option`-checked raw
    // pointer and only ever calling `CFString::wrap_under_create_rule` on a
    // confirmed-non-null, confirmed-CFString-typed value avoids both a leak
    // and a type-confused cast (see the type-check below, M5/S5 fix).
    let raw_value = unsafe {
        CFPreferencesCopyAppValue(
            cf_key.as_concrete_TypeRef(),
            cf_app_id.as_concrete_TypeRef(),
        )
    };

    if raw_value.is_null() {
        return ForcedLookup::Absent;
    }

    // **M5/S5 fix (flagged in S1's module doc as a real, evidence-based
    // residual gap):** `CFPreferencesCopyAppValue` returns a `CFTypeRef`
    // whose ACTUAL runtime type depends entirely on how the
    // `.mobileconfig`/managed profile declared the value — a boolean- or
    // number-typed managed key (e.g. `AllowSelfUpdate` mistyped by an IT
    // admin, or a genuinely non-string key like `Deprovisioned`) is
    // delivered as a `CFBoolean`/`CFNumber`, NOT a `CFString`. Casting the
    // raw pointer straight to `CFStringRef` regardless of its real type (the
    // pre-fix behavior) risked misreading a differently-typed CF object as
    // string data — garbage in the best case, a crash in the worst. Verify
    // the CFTypeID BEFORE ever casting; a non-string value is treated as
    // `Absent` (never guessed, never garbage) rather than blindly
    // reinterpreted.
    //
    // SAFETY: `raw_value` is confirmed non-null immediately above;
    // `CFGetTypeID` only reads the object's runtime type tag.
    if unsafe { CFGetTypeID(raw_value) } != unsafe { CFStringGetTypeID() } {
        // SAFETY: `raw_value` is non-null and was returned under the
        // "create" rule (we own one retain) — wrapping it in the untyped
        // `CFType` and letting it drop releases that retain correctly,
        // without ever reinterpreting its bytes as a `CFString`.
        drop(unsafe { CFType::wrap_under_create_rule(raw_value) });
        return ForcedLookup::Absent;
    }

    // SAFETY: `raw_value` is non-null, was returned under the "create" rule
    // (we own one retain), and is now CONFIRMED `CFString`-typed by the
    // check above — `wrap_under_create_rule` takes ownership without an
    // extra retain, matching Core Foundation's memory contract.
    let cf_string: CFString = unsafe { TCFType::wrap_under_create_rule(raw_value as CFStringRef) };
    let value = cf_string.to_string();

    if forced {
        ForcedLookup::Forced(value)
    } else {
        ForcedLookup::IgnoredUserDomain
    }
}

/// No forced-domain concept off macOS yet — fails closed to `Absent`
/// (compiled-in default), never guesses.
#[cfg(not(target_os = "macos"))]
fn real_forced_string(_key: &str) -> ForcedLookup<String> {
    ForcedLookup::Absent
}

// ---------------------------------------------------------------------------
// resolve_string / resolve_bool — fold ForcedLookup + default into a value
// ---------------------------------------------------------------------------

/// Given a key and a compiled-in default, returns the value every caller
/// actually uses: the forced value if forced, the default otherwise —
/// auditing (never honoring) a user-domain-only value along the way. This is
/// the generic form of `updater::trust`'s old private `resolve()` helper,
/// now shared by every consumer of this module rather than reimplemented
/// per-reader.
pub fn resolve_string(key: &str, default: &str) -> String {
    match forced_string(key) {
        ForcedLookup::Forced(value) => value,
        ForcedLookup::IgnoredUserDomain => {
            audit_ignored_user_domain_value(key);
            default.to_string()
        }
        ForcedLookup::Absent => default.to_string(),
    }
}

/// The boolean counterpart to [`resolve_string`], built on [`forced_bool`] —
/// see [`forced_bool`]'s doc for the "ambiguous forced value means `true`"
/// caveat before reusing this for a new key.
pub fn resolve_bool(key: &str, default: bool) -> bool {
    match forced_bool(key) {
        ForcedLookup::Forced(value) => value,
        ForcedLookup::IgnoredUserDomain => {
            audit_ignored_user_domain_value(key);
            default
        }
        ForcedLookup::Absent => default,
    }
}

/// Emits the tamper-event audit line via `eprintln!` — the same interim
/// facility `model::state::audit_invalid_content` uses (no logging/tracing
/// crate exists in this crate yet). Carries the **key name only** — never a
/// value read from the (untrusted, user-writable) domain, matching
/// `settings::guard`'s "never echoes a secret" discipline extended to
/// "never echoes an untrusted override attempt" here. Public (not
/// `pub(crate)`) so a caller with its own key-specific resolution logic
/// (e.g. a future key needing a non-`String`/non-`bool` shape) can still
/// emit the SAME audit line rather than inventing a second wording.
pub fn audit_ignored_user_domain_value(key: &str) {
    eprintln!(
        "[copilot-control-tower] audit: a user-domain (non-forced) value for \"{key}\" was \
         ignored in favor of the compiled-in default — this key is honored ONLY from the \
         managed/forced MDM domain (invariant #4). See managed::forced."
    );
}

impl<T: fmt::Debug> fmt::Display for ForcedLookup<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self:?}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;

    // -- pure resolve_string/resolve_bool decision logic (no managed Mac
    //    needed — REQUIRED per `.copilot/wp/30.md`) -----------------------

    #[test]
    fn resolve_string_absent_falls_back_to_default() {
        assert_eq!(
            resolve_string(
                "SomeKeyThatIsNeverForcedOrSetOnThisDevBox_Xyz",
                "default-value"
            ),
            "default-value"
        );
    }

    #[test]
    fn resolve_string_honors_a_dev_seam_forced_value() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let key = "TestForcedStringKey";
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(
                &env_name,
                "forced:https://mirror.internal.example/latest.json",
            )
        };
        assert_eq!(
            resolve_string(key, "default-value"),
            "https://mirror.internal.example/latest.json"
        );
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn resolve_string_ignores_a_dev_seam_user_domain_value() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let key = "TestIgnoredStringKey";
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "user") };
        assert_eq!(
            resolve_string(key, "default-value"),
            "default-value",
            "an unforced (user-domain) value must NEVER win over the compiled-in default"
        );
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn resolve_bool_forced_false_variants_all_resolve_false() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        for v in ["false", "False", "FALSE", "0", "no", "No"] {
            let key = "TestBoolKey";
            let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
            // SAFETY: serialized by ENV_LOCK.
            unsafe { std::env::set_var(&env_name, format!("forced:{v}")) };
            assert!(!resolve_bool(key, true), "{v:?} must resolve to false");
            unsafe { std::env::remove_var(&env_name) };
        }
    }

    #[test]
    fn resolve_bool_ignored_user_domain_falls_back_to_default() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let key = "TestBoolIgnoredKey";
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "user") };
        assert!(resolve_bool(key, true));
        assert!(!resolve_bool(key, false));
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn resolve_bool_absent_falls_back_to_default() {
        assert!(resolve_bool(
            "SomeBoolKeyThatIsNeverForcedOrSetOnThisDevBox_Xyz",
            true
        ));
        assert!(!resolve_bool(
            "SomeBoolKeyThatIsNeverForcedOrSetOnThisDevBox_Xyz",
            false
        ));
    }

    #[test]
    fn is_forced_only_true_for_the_forced_variant() {
        assert!(ForcedLookup::Forced("x".to_string()).is_forced());
        assert!(!ForcedLookup::<String>::IgnoredUserDomain.is_forced());
        assert!(!ForcedLookup::<String>::Absent.is_forced());
    }

    // -- real, OS-touching sanity checks: this dev machine carries no
    //    `.mobileconfig`, so every key must genuinely come back
    //    unforced/absent — proves the FFI binding itself compiles and runs
    //    end to end, even though the true forced-domain behavior needs a
    //    managed Mac to confirm (owner-gated). ----------------------------

    #[cfg(target_os = "macos")]
    #[test]
    fn on_this_unmanaged_dev_machine_no_registry_key_is_forced() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        for key in crate::managed::keys::MANAGED_KEYS {
            assert!(
                !real_key_is_forced(key.name),
                "key {:?} must not be forced on an unmanaged dev machine",
                key.name
            );
            assert_eq!(
                real_forced_string(key.name),
                ForcedLookup::Absent,
                "key {:?} must come back Absent on an unmanaged dev machine",
                key.name
            );
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn key_is_forced_matches_real_key_is_forced_when_no_override_is_set() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        assert!(!key_is_forced("EcosystemSeedURL"));
        assert!(!key_is_forced("SomeKeyThatDoesNotExistAtAll"));
    }

    /// **M5/S5 regression test for the `forced_string` cast fix.** The
    /// dev-seam override (used by every OTHER test in this module) always
    /// hands back a `String`-shaped `ForcedLookup` directly — it never
    /// exercises `real_forced_string`'s actual `CFPreferencesCopyAppValue`
    /// call or the new type check, so it cannot regression-test this fix by
    /// itself. This test instead writes a genuinely non-string
    /// (`CFBoolean`) value into this app's own real preferences domain
    /// (the ordinary user-writable one — no managed Mac/`.mobileconfig`
    /// needed, exactly the same domain `on_this_unmanaged_dev_machine_no_registry_key_is_forced`
    /// already touches read-only) for a throwaway test-only key, then calls
    /// `real_forced_string` on it directly. Before the fix this would have
    /// blindly cast the `CFBoolean`'s pointer to `CFStringRef` and read
    /// whatever bytes happened to be there; after the fix, a type mismatch
    /// is caught before any cast and reported as `Absent` — never garbage,
    /// never a crash.
    #[cfg(target_os = "macos")]
    #[test]
    fn a_wrong_typed_forced_value_is_never_misread_as_a_string() {
        use core_foundation::base::TCFType;
        use core_foundation::boolean::CFBoolean;
        use core_foundation::string::CFString;
        use core_foundation_sys::preferences::{
            CFPreferencesAppSynchronize, CFPreferencesSetAppValue,
        };

        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let test_key = "CTForcedFixWrongTypedTestKey";
        let cf_key = CFString::new(test_key);
        let cf_app_id = CFString::new(APPLICATION_ID);
        let cf_bool = CFBoolean::from(true);

        // SAFETY: writes a `CFBoolean` into the ordinary user-writable
        // preferences domain (the same domain every other value in this
        // test suite is confirmed absent from) for a throwaway,
        // uniquely-named test key; all three `CFString`/`CFBoolean` values
        // outlive the call.
        unsafe {
            CFPreferencesSetAppValue(
                cf_key.as_concrete_TypeRef(),
                cf_bool.as_concrete_TypeRef().cast(),
                cf_app_id.as_concrete_TypeRef(),
            );
            CFPreferencesAppSynchronize(cf_app_id.as_concrete_TypeRef());
        }

        let result = real_forced_string(test_key);

        // Clean up immediately, before any assertion, so a failing
        // assertion never leaves a stray preference behind for the next
        // test run.
        // SAFETY: same call shape as above; a null value REMOVES the key
        // (Core Foundation's documented `CFPreferencesSetAppValue` removal
        // convention).
        unsafe {
            CFPreferencesSetAppValue(
                cf_key.as_concrete_TypeRef(),
                std::ptr::null(),
                cf_app_id.as_concrete_TypeRef(),
            );
            CFPreferencesAppSynchronize(cf_app_id.as_concrete_TypeRef());
        }

        assert_eq!(
            result,
            ForcedLookup::Absent,
            "a non-string (CFBoolean) forced-domain value must never be misread as a string — \
             it must come back Absent, never a garbage/reinterpreted string"
        );
    }
}
