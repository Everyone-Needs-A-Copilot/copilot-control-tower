//! The `SMAppService` seam (M5/S3, `.copilot/wp/30.md` ADR-M5-004,
//! `architecture.md` §3/§8.3, fixes B-H3) — HOW this crate registers/
//! unregisters/queries the ONE signed binary as a launch-at-login item.
//! Mirrors `updater::launch`'s `StagedBundleLauncher` seam shape exactly: a
//! small trait ([`LoginItemService`]), a REAL macOS impl built on
//! `objc2-service-management` (owner-gated — exercising
//! `registerAndReturnError`/`unregisterAndReturnError` for real needs a
//! signed bundle on a real Mac; `cargo test` never calls it), and a fake
//! impl the test suite injects instead.
//!
//! This module owns exactly one thing: HOW to talk to `SMAppService`. The
//! DECISION of whether to register at all (forced `LoginItemManaged`,
//! `super::decide_enablement`) and the Bob-facing status mapping
//! (`super::PersistenceState`) live one level up, in `loginitem::mod` — the
//! same split `updater::launch` (the HOW) vs. `updater::watchdog`/
//! `updater::check` (the DECIDE) already established for M4.

use std::fmt;

/// The status this crate cares about, mirroring `SMAppServiceStatus`
/// (`objc2_service_management::SMAppServiceStatus`) one-to-one so the real
/// macOS backend never needs a lossy translation at the FFI boundary — the
/// Bob-facing collapse into `PersistenceState` happens one level up, in
/// `loginitem::mod`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoginItemStatus {
    /// The login item is registered AND approved — launches at login.
    Enabled,
    /// Registered, but not yet approved (the user hasn't clicked "Allow" in
    /// System Settings > Login Items, or — absent a managed
    /// `com.apple.servicemanagement` payload — nobody has). THIS is the
    /// "background running is off" state (fixes B-H3).
    RequiresApproval,
    /// Was registered once (by this app or a prior install), then
    /// unregistered (e.g. this module's own `unregister`, or an
    /// uninstaller).
    NotRegistered,
    /// Never registered at all.
    NotFound,
}

/// Talking to `SMAppService` failed. Carries only a short, human-readable
/// description (never a raw `NSError`'s full `userInfo`, which could carry
/// arbitrary system-provided text) — logging/telemetry only, never a secret
/// (invariant #6: this whole module never touches credential material in
/// the first place).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoginItemError(pub String);

impl fmt::Display for LoginItemError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "login item error: {}", self.0)
    }
}

impl std::error::Error for LoginItemError {}

/// The seam — trait-based, matching `updater::launch::StagedBundleLauncher`'s
/// and `updater::check::FeedFetcher`'s identical dependency-injection shape.
/// `loginitem::mod`'s own tests inject a fake: no real `SMAppService` call
/// happens anywhere in `cargo test` (owner-gated — needs a signed bundle on
/// a real Mac to observe genuine approval-state transitions).
pub trait LoginItemService {
    /// Registers this app as a launch-at-login item
    /// (`SMAppService.registerAndReturnError`). On an unmanaged Mac this
    /// surfaces the ordinary System Settings consent UI (status becomes
    /// [`LoginItemStatus::RequiresApproval`] until the user approves it); on
    /// a managed fleet where MDM has separately pushed the
    /// `com.apple.servicemanagement` managed login-item payload, the OS
    /// force-approves it instead.
    fn register(&self) -> Result<(), LoginItemError>;

    /// Unregisters this app as a launch-at-login item
    /// (`SMAppService.unregisterAndReturnError`) — used by the signed
    /// uninstaller path (`architecture.md` §7, fixes B-H2) so a deleted app
    /// never orphans a login item.
    fn unregister(&self) -> Result<(), LoginItemError>;

    /// Reads the current approval status (`SMAppService.status`) — a pure
    /// read, never mutates anything.
    fn status(&self) -> LoginItemStatus;
}

/// The production implementation — talks to the REAL
/// `SMAppService.mainAppService()` (the "main app as its own login item"
/// shape Apple's API documents, matching invariant #2's "one signed binary",
/// as opposed to a separate helper-app agent/daemon service, which this app
/// deliberately has none of). **Owner-gated**: exercising this against a
/// genuine signed, launch-services-registered bundle requires a real Mac —
/// `cargo test` never does (mirrors `updater::launch::RealBundleLauncher`'s
/// identical "no positive-path unit test here" caveat). `loginitem::mod`'s
/// own tests inject a fake [`LoginItemService`] instead.
#[cfg(target_os = "macos")]
#[derive(Debug, Default, Clone, Copy)]
pub struct RealSMAppService;

#[cfg(target_os = "macos")]
impl LoginItemService for RealSMAppService {
    fn register(&self) -> Result<(), LoginItemError> {
        use objc2_service_management::SMAppService;

        // SAFETY: `mainAppService()` returns a retained reference to the
        // singleton `SMAppService` describing THIS running app as a login
        // item — Apple's documented call shape for a main-app login item.
        // `registerAndReturnError` only mutates ServiceManagement-owned
        // Objective-C runtime state; no raw pointer from this call is held
        // past this function's scope.
        let service = unsafe { SMAppService::mainAppService() };
        unsafe { service.registerAndReturnError() }
            .map_err(|err| LoginItemError(err.localizedDescription().to_string()))
    }

    fn unregister(&self) -> Result<(), LoginItemError> {
        use objc2_service_management::SMAppService;

        // SAFETY: see `register` above — same singleton, same
        // read-then-mutate call shape Apple's API documents.
        let service = unsafe { SMAppService::mainAppService() };
        unsafe { service.unregisterAndReturnError() }
            .map_err(|err| LoginItemError(err.localizedDescription().to_string()))
    }

    fn status(&self) -> LoginItemStatus {
        use objc2_service_management::{SMAppService, SMAppServiceStatus};

        // SAFETY: `status()` is a pure read ("can be used to check what
        // selection a user has made" — Apple's own doc); no mutation.
        let service = unsafe { SMAppService::mainAppService() };
        match unsafe { service.status() } {
            SMAppServiceStatus::Enabled => LoginItemStatus::Enabled,
            SMAppServiceStatus::RequiresApproval => LoginItemStatus::RequiresApproval,
            SMAppServiceStatus::NotRegistered => LoginItemStatus::NotRegistered,
            // `NotFound` and any status value this binding doesn't yet name
            // both fail closed to `NotFound` rather than guessing.
            _ => LoginItemStatus::NotFound,
        }
    }
}

/// No `SMAppService` off macOS yet (a future Windows re-skin, M9/WS-I, gets
/// its own Task Scheduler-backed login-launch seam per CLAUDE.md's "design
/// every OS-integration edge so Windows is a re-skin" and
/// `windows-parity.md` row 2, "Designed-for") — fails closed to an explicit
/// error / `NotFound` rather than guessing.
#[cfg(not(target_os = "macos"))]
#[derive(Debug, Default, Clone, Copy)]
pub struct RealSMAppService;

#[cfg(not(target_os = "macos"))]
impl LoginItemService for RealSMAppService {
    fn register(&self) -> Result<(), LoginItemError> {
        Err(LoginItemError(
            "SMAppService is macOS-only; no login-item mechanism on this platform yet".to_string(),
        ))
    }

    fn unregister(&self) -> Result<(), LoginItemError> {
        Err(LoginItemError(
            "SMAppService is macOS-only; no login-item mechanism on this platform yet".to_string(),
        ))
    }

    fn status(&self) -> LoginItemStatus {
        LoginItemStatus::NotFound
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Fake, injectable per-test — matches `updater::check`'s `FakeLauncher`
    /// pattern exactly: no real subprocess/`SMAppService` call anywhere
    /// here.
    struct FakeLoginItemService {
        register_result: Result<(), LoginItemError>,
        status: LoginItemStatus,
    }

    impl LoginItemService for FakeLoginItemService {
        fn register(&self) -> Result<(), LoginItemError> {
            self.register_result.clone()
        }
        fn unregister(&self) -> Result<(), LoginItemError> {
            Ok(())
        }
        fn status(&self) -> LoginItemStatus {
            self.status
        }
    }

    #[test]
    fn fake_service_reports_its_configured_status() {
        let fake = FakeLoginItemService {
            register_result: Ok(()),
            status: LoginItemStatus::RequiresApproval,
        };
        assert_eq!(fake.status(), LoginItemStatus::RequiresApproval);
        assert!(fake.register().is_ok());
    }

    #[test]
    fn fake_service_can_report_a_register_failure() {
        let fake = FakeLoginItemService {
            register_result: Err(LoginItemError("simulated denial".to_string())),
            status: LoginItemStatus::NotRegistered,
        };
        let err = fake.register().expect_err("expected a simulated failure");
        assert_eq!(err.0, "simulated denial");
    }

    #[test]
    fn login_item_error_display_never_panics_on_an_empty_message() {
        let err = LoginItemError(String::new());
        assert_eq!(err.to_string(), "login item error: ");
    }

    #[cfg(not(target_os = "macos"))]
    #[test]
    fn off_macos_the_real_service_fails_closed_rather_than_guessing() {
        let real = RealSMAppService;
        assert!(real.register().is_err());
        assert!(real.unregister().is_err());
        assert_eq!(real.status(), LoginItemStatus::NotFound);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn real_smappservice_is_constructible_without_touching_the_os() {
        // Constructing the type itself must never call into
        // `SMAppService` (only `register`/`unregister`/`status` do) — the
        // same "safe to construct, owner-gated to actually use" shape
        // `updater::launch::RealBundleLauncher::default()` already has.
        let _ = RealSMAppService;
    }
}
