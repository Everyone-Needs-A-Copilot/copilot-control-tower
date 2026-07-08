//! Managed login-item (M5/S3, `.copilot/wp/30.md` ADR-M5-004,
//! `architecture.md` §3/§8.3, fixes B-H3). See [`smappservice`] for the
//! `SMAppService` seam (the HOW); this module owns the DECIDE (is this
//! machine's login item allowed to be considered "managed and non-toggleable",
//! read forced-domain-only) and the Bob-facing status mapping.
//!
//! ## ADR-M5-004 — the login-item is DISTINCT from the M4 crash-only watchdog
//!
//! **Status:** Accepted (see the M5 architecture WP, `.copilot/wp/30.md`).
//!
//! **Context:** Invariant #2 says ONE signed binary; `launchd`'s LaunchAgent
//! (`packaging/launchd/*.plist`, `updater::watchdog`) is a **crash-only**
//! watchdog — `KeepAlive={SuccessfulExit:false}`, `RunAtLoad=false`, NEVER a
//! bare `KeepAlive=true` — that relaunches THIS process on a non-zero exit
//! and does nothing else. Separately, "always-on" also needs
//! **launch-at-login**: the app should start automatically the next time
//! Bob logs in, which is a completely different trigger (login, not crash)
//! answering a completely different question ("should this start now" vs.
//! "did this die and need resurrecting").
//!
//! **Decision:** `SMAppService` (this module) owns launch-at-login,
//! `launchd`'s `KeepAlive` LaunchAgent owns crash-relaunch. **Two
//! mechanisms, ONE binary, per-`$UID`, NO second resident process** — this
//! module never spawns a process (`SMAppService.register()` only asks the OS
//! to remember "launch this bundle at next login"; it doesn't fork/exec
//! anything itself), and never emits or reads `KeepAlive`/watchdog-plist
//! content (that stays `updater::watchdog`'s job, unchanged by this stream —
//! see `packaging/launchd/com.everyoneneedsacopilot.controltower.plist`'s
//! own comment: "login-launch is `SMAppService`'s job... this plist governs
//! crash-relaunch only"). `tests/fitness_m5_loginitem_not_watchdog.rs`
//! (FF-M5-4) is the standing, regression-proof guard for both halves of that
//! sentence.
//!
//! **Consequences:** Easier — a Bob cannot silently disable "always-on" by
//! toggling ONE lever (the managed login-item payload makes `SMAppService`
//! itself non-toggleable; the crash watchdog is a separate, always-on
//! `launchd` job neither Bob nor a naive uninstall step can reach without
//! `launchctl bootout`). Harder — real `SMAppService` approval-state
//! transitions need a signed bundle + (for the non-toggleable guarantee) a
//! genuinely MDM-enrolled Mac; both are owner-gated (see the module-level
//! "owner-gated" note below).
//!
//! **Alternatives rejected:** folding launch-at-login into the `launchd`
//! LaunchAgent via `RunAtLoad=true` — rejected: that plist is `KeepAlive`'s
//! crash-only job; adding `RunAtLoad=true` to the SAME job conflates "start
//! at login" with "resurrect after crash" in one YES/NO switch an IT admin
//! or Bob can't reason about independently, and would double-launch against
//! `SMAppService` doing the same thing (`fitness_watchdog_plist.rs`'s
//! `run_at_load_is_never_true_login_launch_is_smappservices_job` already
//! guards the watchdog side of this). A second resident process/daemon that
//! watches for login and spawns the app — rejected outright: violates
//! invariant #2 (single process, no daemon).
//!
//! **Fitness FF-M5-4:** this module ([`smappservice`] + this file) never
//! emits `KeepAlive`/watchdog-plist content and never spawns a second
//! resident process (`tests/fitness_m5_loginitem_not_watchdog.rs`).
//!
//! ## Managed, not user-defeatable
//!
//! Login-item enablement reads the forced `LoginItemManaged` key
//! ([`managed::keys::MANAGED_KEYS`], read via [`managed::forced`] — the SOLE
//! forced-domain boundary, never a second reader) rather than a user-facing
//! toggle a Bob could flip off. [`decide_enablement`] folds that forced
//! lookup into a [`LoginItemEnablement`] a caller can act on directly. On an
//! **unmanaged** machine (the key is `Absent`), an ordinary user-level login
//! item is fine — this is not itself a security decision, so the default is
//! "register, let the normal System Settings consent UI run its course",
//! matching `LoginItemManaged`'s own `security_sensitive: false`
//! classification in the frozen registry.
//!
//! ## Owner-gated
//!
//! The real `SMAppService.register()`/`.status()` approval-state transitions
//! (does a managed-payload push genuinely force-approve; does an unmanaged
//! register genuinely prompt) require a signed bundle running on a real Mac
//! (managed, for the non-toggleable half) — neither is exercised by `cargo
//! test`. What IS verified here: the enablement decision logic (pure,
//! dev-seam-driven — see [`decide_enablement`]'s tests) and the status→
//! [`PersistenceState`] mapping (pure, table-driven — see
//! [`persistence_state`]'s tests) via the [`smappservice::LoginItemService`]
//! fake, exactly as `updater::check`'s tests exercise `apply_update` via a
//! fake `StagedBundleLauncher`.

pub mod smappservice;

use crate::managed::forced::{self, ForcedLookup};
use smappservice::{LoginItemService, LoginItemStatus};

/// The name `managed::keys::MANAGED_KEYS` freezes for this key — kept as a
/// named constant here (rather than a bare string literal at each call
/// site) so a future rename shows up as a single-line diff, matching
/// `updater::heartbeat::SELF_TEST_FLAG`'s own precedent for a
/// cross-module-shared string constant.
pub const LOGIN_ITEM_MANAGED_KEY: &str = "LoginItemManaged";

/// The DECISION this module makes about whether/how to register the login
/// item — folded from the forced `LoginItemManaged` lookup. See the module
/// doc's "Managed, not user-defeatable" section.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoginItemEnablement {
    /// `LoginItemManaged` is forced `true`: MDM has separately pushed the
    /// `com.apple.servicemanagement` managed login-item payload (a
    /// DIFFERENT preferences domain this app does not itself read — see
    /// `managed::keys::MANAGED_KEYS`'s own doc for `LoginItemManaged`).
    /// This app still calls `register()` (idempotent — registering an
    /// already-managed-approved item is a no-op from the OS's perspective),
    /// but skips ANY Bob-facing "please enable background running" nag: the
    /// managed payload already forces approval.
    ManagedEnabled,
    /// `LoginItemManaged` is forced `false`: MDM has explicitly said this
    /// fleet does NOT want the login item registered. This app must not
    /// register (and should unregister if already registered) — an explicit
    /// forced-domain fact wins over this app's own default.
    ManagedDisabled,
    /// `LoginItemManaged` is `Absent` (the ordinary case on an unmanaged
    /// personal Mac, or a managed fleet that simply hasn't set this
    /// provisional key yet): register as a normal, user-level login item —
    /// not itself a security decision (`LoginItemManaged`'s
    /// `security_sensitive: false`), so the default is "on", same as any
    /// other always-on desktop app.
    UnmanagedDefault,
}

impl LoginItemEnablement {
    /// `true` for every variant except [`LoginItemEnablement::ManagedDisabled`]
    /// — the one case where an explicit forced-domain fact means "do not
    /// register".
    pub fn should_register(self) -> bool {
        !matches!(self, LoginItemEnablement::ManagedDisabled)
    }

    /// `true` only when MDM has separately force-approved the login item —
    /// the caller (`commands.rs`/tray, when this stream is wired to one) can
    /// use this to skip a "please enable background running" nag even
    /// while `status()` still reads `RequiresApproval` momentarily (e.g.
    /// before the OS has processed the pushed payload).
    pub fn is_mdm_force_approved(self) -> bool {
        matches!(self, LoginItemEnablement::ManagedEnabled)
    }
}

/// Reads the forced `LoginItemManaged` key via [`forced::forced_bool`] (the
/// SOLE forced-domain boundary — S1's `managed::forced`, never a second
/// reader) and folds it into a [`LoginItemEnablement`] decision. Pure
/// decision logic over a [`ForcedLookup`] the caller already resolved one
/// FFI hop away — unit-testable via the dev-seam override
/// (`CT_FORCED_OVERRIDE_LOGINITEMMANAGED`), exactly like every other
/// `managed::forced` consumer's own tests.
pub fn decide_enablement() -> LoginItemEnablement {
    match forced::forced_bool(LOGIN_ITEM_MANAGED_KEY) {
        ForcedLookup::Forced(true) => LoginItemEnablement::ManagedEnabled,
        ForcedLookup::Forced(false) => LoginItemEnablement::ManagedDisabled,
        // An unforced user-domain value is ALWAYS ignored (invariant #4) —
        // `forced_bool` itself already audits this case
        // (`forced::audit_ignored_user_domain_value`); this module adds no
        // second audit line, it simply falls through to the same default an
        // `Absent` lookup gets.
        ForcedLookup::IgnoredUserDomain | ForcedLookup::Absent => {
            LoginItemEnablement::UnmanagedDefault
        }
    }
}

/// The Bob-facing collapse of [`LoginItemStatus`] — what `architecture.md`
/// §3/§8.3 (fixes B-H3) actually wants surfaced: "is background running on
/// or off", not the raw four-way `SMAppService` enum. `commands.rs`/tray
/// (a later wiring step, not this stream) is the eventual consumer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PersistenceState {
    /// Launches at login — the healthy, expected state.
    Active,
    /// Registered but NOT approved — this is exactly B-H3's failure mode:
    /// "Aviator doesn't launch at login... no signal to IT that it
    /// happened". A Bob-facing "background running is off — turn it on"
    /// card belongs here (surfaced by a later wiring step).
    Disabled,
    /// Never registered, or was registered and then explicitly
    /// unregistered. Not itself an error — e.g. immediately after a fresh
    /// install, before this module's own `install` has ever run.
    NotRegistered,
}

/// Maps a raw [`LoginItemStatus`] to the Bob-facing [`PersistenceState`] —
/// pure, table-driven, no OS call. `NotFound` and `NotRegistered` both
/// collapse to [`PersistenceState::NotRegistered`]: from the DETECTION
/// side, "never registered" and "registered then removed" both mean "not
/// currently launching at login", the same distinction B-H3's fix cares
/// about (`RequiresApproval` vs. everything else) — a finer-grained split
/// would be a real product decision (does Bob get a different message for
/// "never set up" vs. "removed"?) this task does not make on its own.
pub fn persistence_state(status: LoginItemStatus) -> PersistenceState {
    match status {
        LoginItemStatus::Enabled => PersistenceState::Active,
        LoginItemStatus::RequiresApproval => PersistenceState::Disabled,
        LoginItemStatus::NotRegistered | LoginItemStatus::NotFound => {
            PersistenceState::NotRegistered
        }
    }
}

/// Installs the login item per [`decide_enablement`]'s decision — a thin,
/// injectable-seam wrapper (never a second copy of the DECIDE logic) around
/// [`LoginItemService::register`]/[`LoginItemService::unregister`]. Returns
/// `Ok(())` for [`LoginItemEnablement::ManagedDisabled`] without calling the
/// service at all if it was never registered in the first place — this
/// function does not itself know whether a PRIOR registration exists; a
/// caller that needs "unregister if currently registered, else no-op" should
/// check [`LoginItemService::status`] first (the same discipline
/// `updater::check::apply_update` uses around its own launcher seam).
pub fn install(service: &dyn LoginItemService) -> Result<(), smappservice::LoginItemError> {
    match decide_enablement() {
        LoginItemEnablement::ManagedDisabled => service.unregister(),
        LoginItemEnablement::ManagedEnabled | LoginItemEnablement::UnmanagedDefault => {
            service.register()
        }
    }
}

/// Unconditionally unregisters the login item — the signed-uninstaller path
/// (`architecture.md` §7, fixes B-H2) calls this directly rather than going
/// through [`install`]'s enablement decision (an uninstall must remove the
/// login item regardless of what the forced domain currently says).
pub fn remove(service: &dyn LoginItemService) -> Result<(), smappservice::LoginItemError> {
    service.unregister()
}

/// Reads the current [`PersistenceState`] via the given service — the thin
/// read-path counterpart to [`install`]/[`remove`].
pub fn current_state(service: &dyn LoginItemService) -> PersistenceState {
    persistence_state(service.status())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::test_env::ENV_LOCK;
    use crate::managed::forced::FORCED_OVERRIDE_ENV_PREFIX;

    fn override_env_name() -> String {
        format!(
            "{FORCED_OVERRIDE_ENV_PREFIX}{}",
            LOGIN_ITEM_MANAGED_KEY.to_ascii_uppercase()
        )
    }

    struct FakeService {
        register_calls: std::cell::Cell<u32>,
        unregister_calls: std::cell::Cell<u32>,
        status: LoginItemStatus,
    }

    impl FakeService {
        fn new(status: LoginItemStatus) -> Self {
            Self {
                register_calls: std::cell::Cell::new(0),
                unregister_calls: std::cell::Cell::new(0),
                status,
            }
        }
    }

    impl LoginItemService for FakeService {
        fn register(&self) -> Result<(), smappservice::LoginItemError> {
            self.register_calls.set(self.register_calls.get() + 1);
            Ok(())
        }
        fn unregister(&self) -> Result<(), smappservice::LoginItemError> {
            self.unregister_calls.set(self.unregister_calls.get() + 1);
            Ok(())
        }
        fn status(&self) -> LoginItemStatus {
            self.status
        }
    }

    // -- decide_enablement (pure, dev-seam-driven) --------------------------

    #[test]
    fn absent_forced_key_is_unmanaged_default() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name();
        unsafe { std::env::remove_var(&env_name) };
        assert_eq!(decide_enablement(), LoginItemEnablement::UnmanagedDefault);
    }

    #[test]
    fn forced_true_is_managed_enabled() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "forced:true") };
        assert_eq!(decide_enablement(), LoginItemEnablement::ManagedEnabled);
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn forced_false_is_managed_disabled() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "forced:false") };
        assert_eq!(decide_enablement(), LoginItemEnablement::ManagedDisabled);
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn a_user_domain_only_value_is_ignored_and_falls_back_to_unmanaged_default() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "user") };
        assert_eq!(
            decide_enablement(),
            LoginItemEnablement::UnmanagedDefault,
            "an unforced (user-domain) LoginItemManaged value must NEVER win — invariant #4"
        );
        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn should_register_is_false_only_for_managed_disabled() {
        assert!(LoginItemEnablement::ManagedEnabled.should_register());
        assert!(LoginItemEnablement::UnmanagedDefault.should_register());
        assert!(!LoginItemEnablement::ManagedDisabled.should_register());
    }

    #[test]
    fn is_mdm_force_approved_is_true_only_for_managed_enabled() {
        assert!(LoginItemEnablement::ManagedEnabled.is_mdm_force_approved());
        assert!(!LoginItemEnablement::UnmanagedDefault.is_mdm_force_approved());
        assert!(!LoginItemEnablement::ManagedDisabled.is_mdm_force_approved());
    }

    // -- persistence_state mapping (pure, table-driven) ----------------------

    #[test]
    fn enabled_status_maps_to_active() {
        assert_eq!(
            persistence_state(LoginItemStatus::Enabled),
            PersistenceState::Active
        );
    }

    #[test]
    fn requires_approval_maps_to_disabled_fixes_b_h3() {
        assert_eq!(
            persistence_state(LoginItemStatus::RequiresApproval),
            PersistenceState::Disabled,
            "RequiresApproval must surface as Disabled — this is exactly B-H3's \
             'background running is off' failure mode"
        );
    }

    #[test]
    fn not_registered_and_not_found_both_map_to_not_registered() {
        assert_eq!(
            persistence_state(LoginItemStatus::NotRegistered),
            PersistenceState::NotRegistered
        );
        assert_eq!(
            persistence_state(LoginItemStatus::NotFound),
            PersistenceState::NotRegistered
        );
    }

    // -- install/remove/current_state via the injected fake seam ------------

    #[test]
    fn install_registers_on_the_unmanaged_default_path() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name();
        unsafe { std::env::remove_var(&env_name) };

        let fake = FakeService::new(LoginItemStatus::NotRegistered);
        install(&fake).expect("install should succeed against the fake");
        assert_eq!(fake.register_calls.get(), 1);
        assert_eq!(fake.unregister_calls.get(), 0);
    }

    #[test]
    fn install_registers_on_the_managed_enabled_path() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "forced:true") };

        let fake = FakeService::new(LoginItemStatus::NotRegistered);
        install(&fake).expect("install should succeed against the fake");
        assert_eq!(fake.register_calls.get(), 1);
        assert_eq!(fake.unregister_calls.get(), 0);

        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn install_unregisters_instead_of_registering_on_the_managed_disabled_path() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "forced:false") };

        let fake = FakeService::new(LoginItemStatus::Enabled);
        install(&fake).expect("install should succeed against the fake");
        assert_eq!(
            fake.register_calls.get(),
            0,
            "a forced LoginItemManaged=false must never call register()"
        );
        assert_eq!(fake.unregister_calls.get(), 1);

        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn remove_always_unregisters_regardless_of_enablement() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let env_name = override_env_name();
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(&env_name, "forced:true") };

        let fake = FakeService::new(LoginItemStatus::Enabled);
        remove(&fake).expect("remove should succeed against the fake");
        assert_eq!(fake.unregister_calls.get(), 1);
        assert_eq!(
            fake.register_calls.get(),
            0,
            "the uninstall path must never register"
        );

        unsafe { std::env::remove_var(&env_name) };
    }

    #[test]
    fn current_state_reads_through_to_the_service_status() {
        let fake = FakeService::new(LoginItemStatus::RequiresApproval);
        assert_eq!(current_state(&fake), PersistenceState::Disabled);
    }
}
