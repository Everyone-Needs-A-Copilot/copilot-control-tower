//! macOS impl of [`PlatformWatchdogSignal`] — a THIN wrapper over
//! [`crate::updater::watchdog::HeartbeatSource`] (M4/S1-S2), the SAME
//! liveness-proof seam `updater::startup`/`updater::selftest` already drive
//! via `updater::heartbeat::FileHeartbeatSource`. No logic moves here:
//! [`MacWatchdogSignal`] is generic over any `HeartbeatSource` and forwards
//! `observe` unchanged; production code wraps `FileHeartbeatSource`
//! ([`MacWatchdogSignal::production`]) rooted at the SAME
//! `updater::heartbeat::default_heartbeat_root()` every other macOS caller
//! already uses — never a second, independently-derived layout root.

use crate::platform::PlatformWatchdogSignal;
use crate::updater::heartbeat::{default_heartbeat_root, FileHeartbeatSource};
use crate::updater::watchdog::{HeartbeatOutcome, HeartbeatSource};
use std::path::Path;
use std::time::Duration;

/// Generic over any [`HeartbeatSource`] so this wrapper is unit-testable
/// against a fake, exactly like the trait it wraps. Defaults to
/// [`FileHeartbeatSource`] so ordinary production call sites don't need to
/// name the generic explicitly.
#[derive(Debug, Clone)]
pub struct MacWatchdogSignal<H: HeartbeatSource = FileHeartbeatSource>(H);

impl MacWatchdogSignal<FileHeartbeatSource> {
    /// The production constructor. Returns `None` only when
    /// `default_heartbeat_root()` itself would (`$HOME` unset) — the same
    /// "never guess a fallback location" discipline that function's own doc
    /// establishes.
    pub fn production(expected_app_version: impl Into<String>) -> Option<Self> {
        let layout_root = default_heartbeat_root()?;
        Some(Self(FileHeartbeatSource {
            layout_root,
            expected_app_version: expected_app_version.into(),
        }))
    }
}

impl<H: HeartbeatSource> MacWatchdogSignal<H> {
    /// Test-only: wrap an injected fake directly.
    #[cfg(test)]
    pub(crate) fn wrapping(source: H) -> Self {
        Self(source)
    }
}

impl<H: HeartbeatSource> PlatformWatchdogSignal for MacWatchdogSignal<H> {
    fn observe(&self, staged: &Path, timeout: Duration) -> HeartbeatOutcome {
        self.0.observe(staged, timeout)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FixedHeartbeat(HeartbeatOutcome);
    impl HeartbeatSource for FixedHeartbeat {
        fn observe(&self, _staged: &Path, _timeout: Duration) -> HeartbeatOutcome {
            self.0
        }
    }

    #[test]
    fn observe_delegates_straight_through_on_alive() {
        let wrapper = MacWatchdogSignal::wrapping(FixedHeartbeat(HeartbeatOutcome::Alive));
        assert_eq!(
            PlatformWatchdogSignal::observe(
                &wrapper,
                Path::new("/tmp/staged"),
                Duration::from_secs(1)
            ),
            HeartbeatOutcome::Alive
        );
    }

    #[test]
    fn observe_delegates_straight_through_on_timeout() {
        let wrapper = MacWatchdogSignal::wrapping(FixedHeartbeat(HeartbeatOutcome::Timeout));
        assert_eq!(
            PlatformWatchdogSignal::observe(
                &wrapper,
                Path::new("/tmp/staged"),
                Duration::from_millis(10)
            ),
            HeartbeatOutcome::Timeout
        );
    }

    #[test]
    fn observe_delegates_straight_through_on_malformed() {
        let wrapper = MacWatchdogSignal::wrapping(FixedHeartbeat(HeartbeatOutcome::Malformed));
        assert_eq!(
            PlatformWatchdogSignal::observe(
                &wrapper,
                Path::new("/tmp/staged"),
                Duration::from_millis(10)
            ),
            HeartbeatOutcome::Malformed
        );
    }

    #[test]
    fn production_uses_the_same_default_heartbeat_root_or_none_when_home_is_unset() {
        // Mirrors the exact contract `default_heartbeat_root()` itself
        // documents — this wrapper adds no second fallback rule.
        let direct = default_heartbeat_root();
        let via_wrapper = MacWatchdogSignal::production("9.9.9");
        assert_eq!(direct.is_some(), via_wrapper.is_some());
    }
}
