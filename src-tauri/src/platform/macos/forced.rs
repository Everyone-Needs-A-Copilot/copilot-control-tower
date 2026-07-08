//! macOS impl of [`PlatformForcedConfig`] — a THIN wrapper over
//! [`crate::managed::forced`]'s free functions (M5/S1, the SOLE
//! `CFPreferences` FFI boundary, `tests/fitness_m5_single_forced_boundary.rs`
//! FF-M5-1). No logic moves here: [`MacForcedConfig`] is a zero-field unit
//! struct whose every method is a one-line delegation to the already-proven
//! function of the same name — see this module's own tests for the
//! behavior-preservation proof (each test drives the SAME dev-seam override
//! `managed::forced`'s own tests use, then asserts the wrapper's answer is
//! identical to calling `managed::forced` directly).

use crate::managed::forced::{self, ForcedLookup};
use crate::platform::PlatformForcedConfig;

/// Zero-field — carries no state of its own; every call reads straight
/// through to `managed::forced`'s module-level functions.
#[derive(Debug, Default, Clone, Copy)]
pub struct MacForcedConfig;

impl PlatformForcedConfig for MacForcedConfig {
    fn key_is_forced(&self, key: &str) -> bool {
        forced::key_is_forced(key)
    }

    fn forced_string(&self, key: &str) -> ForcedLookup<String> {
        forced::forced_string(key)
    }

    fn forced_bool(&self, key: &str) -> ForcedLookup<bool> {
        forced::forced_bool(key)
    }

    fn resolve_string(&self, key: &str, default: &str) -> String {
        forced::resolve_string(key, default)
    }

    fn resolve_bool(&self, key: &str, default: bool) -> bool {
        forced::resolve_bool(key, default)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;

    fn set_override(key: &str, value: &str) {
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK, same discipline every other
        // dev-seam test in this crate already uses.
        unsafe { std::env::set_var(&env_name, value) };
    }

    fn clear_override(key: &str) {
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn wrapper_key_is_forced_matches_the_wrapped_function_forced_case() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let key = "PlatformWrapperForcedTestKey";
        set_override(key, "forced:true");

        let wrapper = MacForcedConfig;
        let via_wrapper = wrapper.key_is_forced(key);
        let via_direct = forced::key_is_forced(key);

        clear_override(key);
        assert!(via_wrapper);
        assert_eq!(
            via_wrapper, via_direct,
            "the wrapper must never diverge from managed::forced"
        );
    }

    #[test]
    fn wrapper_forced_string_matches_the_wrapped_function_ignored_user_domain_case() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let key = "PlatformWrapperUserDomainTestKey";
        set_override(key, "user");

        let wrapper = MacForcedConfig;
        let via_wrapper = wrapper.forced_string(key);
        let via_direct = forced::forced_string(key);

        clear_override(key);
        assert_eq!(via_wrapper, ForcedLookup::IgnoredUserDomain);
        assert_eq!(via_wrapper, via_direct);
    }

    #[test]
    fn wrapper_forced_bool_matches_the_wrapped_function_absent_case() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let key = "PlatformWrapperAbsentTestKey";
        set_override(key, "absent");

        let wrapper = MacForcedConfig;
        let via_wrapper = wrapper.forced_bool(key);
        let via_direct = forced::forced_bool(key);

        clear_override(key);
        assert_eq!(via_wrapper, ForcedLookup::Absent);
        assert_eq!(via_wrapper, via_direct);
    }

    #[test]
    fn wrapper_resolve_string_matches_the_wrapped_function() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let key = "PlatformWrapperResolveStringTestKey";
        set_override(key, "forced:https://mirror.internal.example/latest.json");

        let wrapper = MacForcedConfig;
        let via_wrapper = wrapper.resolve_string(key, "default-value");
        let via_direct = forced::resolve_string(key, "default-value");

        clear_override(key);
        assert_eq!(via_wrapper, "https://mirror.internal.example/latest.json");
        assert_eq!(via_wrapper, via_direct);
    }

    #[test]
    fn wrapper_resolve_bool_matches_the_wrapped_function_default_fallback() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let key = "PlatformWrapperResolveBoolAbsentTestKey";
        clear_override(key);

        let wrapper = MacForcedConfig;
        let via_wrapper = wrapper.resolve_bool(key, true);
        let via_direct = forced::resolve_bool(key, true);

        assert!(via_wrapper);
        assert_eq!(via_wrapper, via_direct);
    }
}
