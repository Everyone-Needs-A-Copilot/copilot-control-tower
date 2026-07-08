//! macOS impl of [`PlatformLoginItem`] — a THIN wrapper over
//! [`crate::loginitem::smappservice::LoginItemService`] (M5/S3, ADR-M5-004).
//! No logic moves here: [`MacLoginItem`] is generic over any
//! `LoginItemService` impl and simply forwards each call — production code
//! wraps [`crate::loginitem::smappservice::RealSMAppService`]
//! ([`MacLoginItem::production`]); this module's own tests wrap the SAME
//! kind of fake `loginitem::mod`'s tests already inject, so delegation is
//! proven without ever touching a real `SMAppService` call (owner-gated,
//! exactly like `RealSMAppService` itself — see that module's own doc).

use crate::loginitem::smappservice::{
    LoginItemError, LoginItemService, LoginItemStatus, RealSMAppService,
};
use crate::platform::PlatformLoginItem;

/// Generic over any [`LoginItemService`] so this wrapper is unit-testable
/// against a fake, exactly like the trait it wraps. Defaults its type
/// parameter to [`RealSMAppService`] so ordinary production call sites don't
/// need to name the generic explicitly.
#[derive(Debug, Default, Clone, Copy)]
pub struct MacLoginItem<S: LoginItemService = RealSMAppService>(S);

impl MacLoginItem<RealSMAppService> {
    /// The production constructor — wraps the real `SMAppService` seam.
    pub fn production() -> Self {
        Self(RealSMAppService)
    }
}

impl<S: LoginItemService> MacLoginItem<S> {
    /// Test-only: wrap an injected fake directly, mirroring
    /// `loginitem::mod`'s own `install`/`remove`/`current_state` functions,
    /// which already take `&dyn LoginItemService` for the identical reason.
    #[cfg(test)]
    pub(crate) fn wrapping(service: S) -> Self {
        Self(service)
    }
}

impl<S: LoginItemService> PlatformLoginItem for MacLoginItem<S> {
    fn register(&self) -> Result<(), LoginItemError> {
        self.0.register()
    }

    fn unregister(&self) -> Result<(), LoginItemError> {
        self.0.unregister()
    }

    fn status(&self) -> LoginItemStatus {
        self.0.status()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The exact same fake shape `loginitem::mod`'s own tests use — kept as
    /// a local, private copy (this crate's established convention: each
    /// module's test suite owns its own fake rather than sharing a
    /// `pub(crate)` test double across module boundaries).
    struct FakeLoginItemService {
        register_calls: std::cell::Cell<u32>,
        unregister_calls: std::cell::Cell<u32>,
        status: LoginItemStatus,
    }

    impl FakeLoginItemService {
        fn new(status: LoginItemStatus) -> Self {
            Self {
                register_calls: std::cell::Cell::new(0),
                unregister_calls: std::cell::Cell::new(0),
                status,
            }
        }
    }

    impl LoginItemService for FakeLoginItemService {
        fn register(&self) -> Result<(), LoginItemError> {
            self.register_calls.set(self.register_calls.get() + 1);
            Ok(())
        }
        fn unregister(&self) -> Result<(), LoginItemError> {
            self.unregister_calls.set(self.unregister_calls.get() + 1);
            Ok(())
        }
        fn status(&self) -> LoginItemStatus {
            self.status
        }
    }

    #[test]
    fn register_delegates_straight_through_to_the_wrapped_service() {
        let fake = FakeLoginItemService::new(LoginItemStatus::NotRegistered);
        let wrapper = MacLoginItem::wrapping(fake);

        assert!(PlatformLoginItem::register(&wrapper).is_ok());
        assert_eq!(wrapper.0.register_calls.get(), 1);
        assert_eq!(wrapper.0.unregister_calls.get(), 0);
    }

    #[test]
    fn unregister_delegates_straight_through_to_the_wrapped_service() {
        let fake = FakeLoginItemService::new(LoginItemStatus::Enabled);
        let wrapper = MacLoginItem::wrapping(fake);

        assert!(PlatformLoginItem::unregister(&wrapper).is_ok());
        assert_eq!(wrapper.0.unregister_calls.get(), 1);
        assert_eq!(wrapper.0.register_calls.get(), 0);
    }

    #[test]
    fn status_reads_through_unchanged() {
        let fake = FakeLoginItemService::new(LoginItemStatus::RequiresApproval);
        let wrapper = MacLoginItem::wrapping(fake);

        assert_eq!(
            PlatformLoginItem::status(&wrapper),
            LoginItemStatus::RequiresApproval
        );
    }

    #[test]
    fn a_register_failure_surfaces_unchanged_through_the_wrapper() {
        struct FailingService;
        impl LoginItemService for FailingService {
            fn register(&self) -> Result<(), LoginItemError> {
                Err(LoginItemError("simulated denial".to_string()))
            }
            fn unregister(&self) -> Result<(), LoginItemError> {
                Ok(())
            }
            fn status(&self) -> LoginItemStatus {
                LoginItemStatus::NotFound
            }
        }
        let wrapper = MacLoginItem::wrapping(FailingService);
        let err = PlatformLoginItem::register(&wrapper).expect_err("expected the simulated denial");
        assert_eq!(err.0, "simulated denial");
    }

    #[test]
    fn production_constructs_without_touching_the_os() {
        // Constructing the type itself must never call into `SMAppService`
        // (only register/unregister/status do) — the same "safe to
        // construct, owner-gated to actually use" shape
        // `RealSMAppService`'s own test already establishes.
        let _ = MacLoginItem::production();
    }
}
