//! macOS platform impls (M9/Stream-B, task 71, ADR-M9-001) — THIN wrappers
//! only. Every struct here delegates 100% of its behavior to an
//! already-existing, already-tested module; none of them add new decision
//! logic. See `platform`'s own module doc for the wrap-table.

pub mod forced;
pub mod login_item;
pub mod secret_store;
pub mod watchdog;

pub use forced::MacForcedConfig;
pub use login_item::MacLoginItem;
pub use secret_store::MacSecretStore;
pub use watchdog::MacWatchdogSignal;
