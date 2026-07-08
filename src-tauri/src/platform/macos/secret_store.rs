//! macOS impl of [`PlatformSecretStore`] — a THIN wrapper over
//! [`crate::managed::secret_store::secret_store_endpoint`] (M5/S5). No logic
//! moves here: [`MacSecretStore`] is a zero-field unit struct whose one
//! method is a direct call-through. See `managed::secret_store`'s own doc
//! for why this is an ENDPOINT REFERENCE only, never a secret value — this
//! wrapper carries that same guarantee forward unchanged.

use crate::managed::secret_store::{self, SecretStoreRef};
use crate::platform::PlatformSecretStore;

/// Zero-field — carries no state of its own; every call reads straight
/// through to `managed::secret_store::secret_store_endpoint`.
#[derive(Debug, Default, Clone, Copy)]
pub struct MacSecretStore;

impl PlatformSecretStore for MacSecretStore {
    fn secret_store_endpoint(&self) -> Option<SecretStoreRef> {
        secret_store::secret_store_endpoint()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;

    fn set_override(key: &str, value: &str) {
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, value) };
    }

    fn clear_override(key: &str) {
        let env_name = format!("{FORCED_OVERRIDE_ENV_PREFIX}{}", key.to_ascii_uppercase());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn wrapper_matches_the_wrapped_function_when_a_genuine_endpoint_is_forced() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_override(
            "SharedSecretStoreURL",
            "forced:https://secrets.acme-corp.internal",
        );
        set_override("SharedSecretStoreTier", "forced:engineering");

        let wrapper = MacSecretStore;
        let via_wrapper = wrapper.secret_store_endpoint();
        let via_direct = secret_store::secret_store_endpoint();

        clear_override("SharedSecretStoreURL");
        clear_override("SharedSecretStoreTier");

        assert_eq!(
            via_wrapper,
            Some(SecretStoreRef {
                url: "https://secrets.acme-corp.internal".to_string(),
                tier: "engineering".to_string(),
            })
        );
        assert_eq!(via_wrapper, via_direct, "the wrapper must never diverge");
    }

    #[test]
    fn wrapper_matches_the_wrapped_function_when_absent() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set_override("SharedSecretStoreURL", "absent");
        set_override("SharedSecretStoreTier", "absent");

        let wrapper = MacSecretStore;
        let via_wrapper = wrapper.secret_store_endpoint();

        clear_override("SharedSecretStoreURL");
        clear_override("SharedSecretStoreTier");

        assert_eq!(via_wrapper, None);
    }
}
