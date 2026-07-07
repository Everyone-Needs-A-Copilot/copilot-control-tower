//! S4 — the managed silent first-run orchestration ("Silent First Light",
//! `.copilot/wp/15.md` §2 S4). On a machine `settings::managed::is_managed()`
//! reports true, drives the wizard's phase machine end to end with **zero**
//! Bob-facing questions: Detect (schema-validate the MDM-delivered layer
//! manifest FIRST) -> Materialize (`cc update`, relayed via the sibling
//! `materialize` seam) -> Verify (a fresh `cc doctor` poll, M1's own parse
//! boundary) -> Teach -> Done (auto-acknowledged — see `support::
//! drive_verify`, shared with `unmanaged_flow`, since a silent flow has no
//! further question to ask once Healthy is confirmed).
//!
//! **Reuses, never reimplements:** `state::transition` (S1) for every phase
//! move, `materialize::run_materialize` (the `cc update` seam) for the one
//! materialize step, `cli::run_doctor` (M1) for the ONE and ONLY source of a
//! trusted `Verified(Healthy)`, and `support::drive_verify` for the
//! Verify->Teach->Done wiring. This file's own, S4-specific job is just the
//! managed profile's schema-validate-FIRST gate (module doc's "critical
//! framing") — nothing here computes health, resolution, or a verdict of its
//! own (invariant #1).
//!
//! **Fail-closed, no ETA (ADR-M3-003).** [`run`]'s settling-window retry is a
//! fixed number of fixed-length internal sleeps — never surfaced to the user
//! as a countdown; this module returns a bare `WizardPhase`, never a display
//! string (`dto::to_wizard_state` stays the one place a phase becomes text).
//!
//! ## Live progress (M3 QA follow-up D3)
//!
//! [`run`] takes an `on_phase` callback invoked with a `&WizardPhase` after
//! EVERY legal transition it drives (Detect, Materialize's first entry, each
//! CLI-supplied phase name during materialize, Verify's terminal Teach/Done/
//! Holding) — never a raw string, never an ETA, the identical `WizardPhase`
//! this function itself computes. `commands::wizard_advance` uses this
//! callback to write the in-progress phase straight into the live,
//! Tauri-managed `WizardIpcState` (a poll-based push, not a Tauri event — see
//! that command's own doc for why), so a concurrent `get_wizard_state` poll
//! from the UI observes real intermediate phases instead of only the final
//! one. Every other caller (this module's own tests, and
//! `advance_wizard_runtime`'s pure/test-facing path) passes a no-op closure
//! and gets the exact prior behavior.
//!
//! ## Resumability (M3 QA follow-up D2)
//!
//! [`run`] also calls `persistence::checkpoint_phase_if_resumable` at the
//! same two S1-designed moments (`Materialize`'s first entry, and any
//! `Holding` terminal) — a checkpoint is saved, but this module's own
//! `WizardIpcState::new()` caller deliberately never LOADS one for managed
//! mode: `run` is a single, idempotent, zero-Bob-input re-derivation of
//! Detect through Verify/Done, so restarting it fresh on relaunch produces
//! the IDENTICAL outcome a "resume" would, with nothing to lose. Saving here
//! anyway keeps the checkpoint's `mode` field honest and future-proofs a
//! later, finer-grained managed resume without this module needing to change
//! again.
//!
//! ## The managed profile IS the layer manifest
//!
//! This crate has no separate "MDM ecosystem.yml" reader — the MDM-delivered
//! ecosystem config materializes, in this app's own model, as the same
//! `copilot.layers.yml` `settings::writer`/`settings::validate` already know
//! how to read and schema-check (M2's own framing: "org/dept layers are
//! produced by `cc derive` from the MDM-delivered ecosystem.yml", and the
//! wizard fixture corpus's `managed_profile_fixture` entries point at the
//! SAME `fixtures/settings/*.yml` files M2's own tests use). [`check_profile`]
//! therefore reuses `settings::writer::read_existing` +
//! `settings::validate::validate_layers` verbatim — never a second, drifting
//! validator — and distinguishes "absent" from "present-but-invalid" by
//! checking `Path::exists` FIRST, before ever calling `read_existing` (whose
//! own contract collapses "not found" into an honest empty manifest that
//! would otherwise be indistinguishable from "the file exists but is
//! empty/broken").

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::wizard::materialize;
use crate::wizard::persistence;
use crate::wizard::state::{WizardEvent, WizardMode, WizardPhase};
use crate::wizard::support::{drive_verify, must_transition};

/// The plain-language `HoldingReason::ItConfigIncomplete.key` this module
/// uses when the profile hasn't landed at all after the settling window —
/// distinct from a real validator field name (e.g. `"auth"`), since there is
/// no field to blame yet.
const PROFILE_ABSENT_KEY: &str = "managed ecosystem profile (not yet delivered)";

/// Tunables for [`run`]'s settling-window retry — see the module doc.
/// Production defaults are generous (a genuine MDM push can lag); tests pass
/// a near-zero interval so the retry loop proves out in milliseconds, never
/// real wall-clock seconds.
#[derive(Debug, Clone)]
pub struct ManagedFlowConfig {
    /// Where the managed profile (this crate's layer manifest) is expected.
    pub profile_path: PathBuf,
    /// How many times [`run`] checks for the profile before giving up and
    /// holding. Always treated as at least 1 (a single check, no retry).
    pub settling_attempts: u32,
    /// How long to sleep between settling-window checks.
    pub settling_interval: Duration,
}

impl ManagedFlowConfig {
    /// Production defaults: a handful of checks a few seconds apart — long
    /// enough to ride out an ordinary MDM push race, short enough that a
    /// genuinely absent profile still holds well under a minute. Never
    /// surfaced to the user as a number (ADR-M3-003) — this is internal
    /// backend pacing only.
    pub fn production(profile_path: PathBuf) -> Self {
        Self {
            profile_path,
            settling_attempts: 5,
            settling_interval: Duration::from_secs(2),
        }
    }
}

/// The outcome of checking the managed profile — see module doc.
#[derive(Debug, Clone, PartialEq, Eq)]
enum ProfileState {
    Valid,
    /// Present, but a real validator problem — carries the offending field
    /// name (plain language, e.g. `"auth"`), never a raw yaml/serde message.
    Invalid(String),
    /// Nothing at `profile_path` at all (yet).
    Absent,
}

fn check_profile(path: &Path) -> ProfileState {
    if !path.exists() {
        return ProfileState::Absent;
    }
    match crate::settings::writer::read_existing(path) {
        Ok(manifest) => {
            match crate::settings::validate::validate_layers(&manifest)
                .into_iter()
                .next()
            {
                Some(e) => ProfileState::Invalid(e.field),
                None => ProfileState::Valid,
            }
        }
        // `read_existing` only errors on a real read/parse problem (a
        // present file it couldn't make sense of) — every bit as "present
        // but invalid" as a validator complaint, from Bob's side of the
        // fence, so it collapses to the same `Invalid` outcome (with a
        // fixed, honest field name — there's no per-field validator result
        // to point at when the file didn't even parse).
        Err(_) => ProfileState::Invalid("manifest".to_string()),
    }
}

/// Checks the profile up to `config.settling_attempts` times, sleeping
/// `config.settling_interval` between checks, and returns the LAST result —
/// `Absent` only survives to the caller if it was STILL absent on the final
/// attempt (module doc's "retry across a settling window, then hold").
fn settle_profile(config: &ManagedFlowConfig) -> ProfileState {
    let attempts = config.settling_attempts.max(1);
    let mut last = ProfileState::Absent;
    for attempt in 0..attempts {
        last = check_profile(&config.profile_path);
        if !matches!(last, ProfileState::Absent) {
            return last;
        }
        if attempt + 1 < attempts {
            std::thread::sleep(config.settling_interval);
        }
    }
    last
}

/// Runs the ~0-question managed silent first-run to its terminal phase —
/// `WizardPhase::Done` (only ever via a fresh `Verified(Healthy)`, per
/// `support::drive_verify`) or one of the honest `Holding` terminals. Meant
/// to be called off the async runtime's worker threads (`spawn_blocking`,
/// S6) — like `materialize::run_materialize` and `cli::run_doctor`, this
/// blocks: it may sleep across the settling window and always spawns at
/// least one child process (`cli::run_doctor`).
///
/// `on_phase` is invoked with every phase this function legally reaches, in
/// order — see the module doc's "Live progress" section. Pass `|_| {}` for
/// the prior, progress-blind behavior (this module's own tests do).
pub fn run(config: &ManagedFlowConfig, mut on_phase: impl FnMut(&WizardPhase)) -> WizardPhase {
    let phase = must_transition(&WizardPhase::Welcome, WizardEvent::Begin); // Detect
    on_phase(&phase);

    let mut phase = match settle_profile(config) {
        ProfileState::Valid => {
            let next = must_transition(&phase, WizardEvent::DetectedManaged); // Materialize
            persistence::checkpoint_phase_if_resumable(WizardMode::Managed, &next, BTreeMap::new());
            on_phase(&next);
            next
        }
        ProfileState::Invalid(key) => {
            let holding = must_transition(&phase, WizardEvent::ManagedProfileInvalid { key });
            persistence::checkpoint_phase_if_resumable(
                WizardMode::Managed,
                &holding,
                BTreeMap::new(),
            );
            on_phase(&holding);
            return holding;
        }
        ProfileState::Absent => {
            let holding = must_transition(
                &phase,
                WizardEvent::ManagedProfileInvalid {
                    key: PROFILE_ABSENT_KEY.to_string(),
                },
            );
            persistence::checkpoint_phase_if_resumable(
                WizardMode::Managed,
                &holding,
                BTreeMap::new(),
            );
            on_phase(&holding);
            return holding;
        }
    };

    // Materialize: relay the CLI's own phase names; its outcome gates
    // NOTHING here (see `materialize`'s own doc) — even a
    // `MaterializeUnavailable`/`DidNotComplete` result proceeds honestly to
    // Verify, which is the one and only place a real verdict is ever
    // decided.
    let _ = materialize::run_materialize(|name| {
        phase = must_transition(&phase, WizardEvent::PhaseNamed(name));
        on_phase(&phase);
    });
    let phase = must_transition(&phase, WizardEvent::MaterializeComplete); // Verify
    on_phase(&phase);

    let render = crate::cli::run_doctor();
    let final_phase = drive_verify(phase, &render);
    persistence::checkpoint_phase_if_resumable(WizardMode::Managed, &final_phase, BTreeMap::new());
    on_phase(&final_phase);
    final_phase
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;
    use crate::wizard::state::HoldingReason;
    use std::io::Write as _;
    use std::sync::atomic::{AtomicU64, Ordering};

    static DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir() -> PathBuf {
        let n = DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ct-managed-flow-test-{}-{:?}-{n}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp test dir");
        dir
    }

    fn fixture_path(rel: &str) -> String {
        format!("{}/fixtures/{rel}", env!("CARGO_MANIFEST_DIR"))
    }

    /// A combined stand-in `cc` that implements just enough of `update
    /// --json` (streams two phase names then `{"done": true}`, exit 0) and
    /// `doctor --json` (cats whatever `$MOCK_DOCTOR_BODY_PATH` points at,
    /// exit 0) for this module's own tests — local to this file, same
    /// "private mock, never the shared `fixtures/mock-cc`" pattern
    /// `persistence.rs`'s and `materialize.rs`'s own tests use, since the
    /// shared `fixtures/mock-cc` doesn't implement `update` at all (S9 is a
    /// separate, qa-owned task).
    fn write_mock_cc(dir: &Path) -> PathBuf {
        let script = dir.join("mock-cc-managed-flow");
        let mut f = std::fs::File::create(&script).unwrap();
        writeln!(f, "#!/bin/sh").unwrap();
        writeln!(f, "verb=\"$1\"").unwrap();
        writeln!(f, "case \"$verb\" in").unwrap();
        writeln!(f, "  update)").unwrap();
        writeln!(f, "    echo '{{\"phase\": \"Setting up Claude…\"}}'").unwrap();
        writeln!(f, "    echo '{{\"phase\": \"Setting up Codex…\"}}'").unwrap();
        writeln!(f, "    echo '{{\"done\": true}}'").unwrap();
        writeln!(f, "    exit 0").unwrap();
        writeln!(f, "    ;;").unwrap();
        writeln!(f, "  doctor)").unwrap();
        writeln!(f, "    cat \"$MOCK_DOCTOR_BODY_PATH\"").unwrap();
        writeln!(f, "    exit 0").unwrap();
        writeln!(f, "    ;;").unwrap();
        writeln!(f, "  *)").unwrap();
        writeln!(f, "    exit 2").unwrap();
        writeln!(f, "    ;;").unwrap();
        writeln!(f, "esac").unwrap();
        drop(f);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&script).unwrap().permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&script, perms).unwrap();
        }
        script
    }

    fn run_with_mock<R>(
        cli_path: Option<&Path>,
        doctor_body_path: Option<&str>,
        f: impl FnOnce() -> R,
    ) -> R {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK — the same shared lock every other
        // CT_CLI_PATH-touching test in this crate uses.
        unsafe {
            match cli_path {
                Some(p) => std::env::set_var(DEV_OVERRIDE_ENV, p),
                None => std::env::remove_var(DEV_OVERRIDE_ENV),
            }
            match doctor_body_path {
                Some(p) => std::env::set_var("MOCK_DOCTOR_BODY_PATH", p),
                None => std::env::remove_var("MOCK_DOCTOR_BODY_PATH"),
            }
        }
        let result = f();
        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_DOCTOR_BODY_PATH");
        }
        result
    }

    fn fast_config(profile_path: PathBuf) -> ManagedFlowConfig {
        ManagedFlowConfig {
            profile_path,
            settling_attempts: 2,
            settling_interval: Duration::from_millis(1),
        }
    }

    #[test]
    fn a_valid_profile_and_a_healthy_doctor_reaches_done() {
        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml");
        std::fs::copy(
            fixture_path("settings/valid-multi-layer.yml"),
            &profile_path,
        )
        .unwrap();
        let mock_cc = write_mock_cc(&dir);
        let healthy = fixture_path("corpus/healthy-clean-fleet.json");

        let phase = run_with_mock(Some(&mock_cc), Some(&healthy), || {
            run(&fast_config(profile_path), |_| {})
        });

        assert_eq!(phase, WizardPhase::Done, "expected Done, got {phase:?}");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_valid_profile_but_a_non_healthy_doctor_holds_never_false_healthy() {
        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml");
        std::fs::copy(
            fixture_path("settings/valid-multi-layer.yml"),
            &profile_path,
        )
        .unwrap();
        let mock_cc = write_mock_cc(&dir);
        let signed_out = fixture_path("corpus/signed-out-claude-personal.json");

        let phase = run_with_mock(Some(&mock_cc), Some(&signed_out), || {
            run(&fast_config(profile_path), |_| {})
        });

        assert_ne!(phase, WizardPhase::Done);
        assert!(
            matches!(
                phase,
                WizardPhase::Holding(HoldingReason::VerifyFailed { .. })
            ),
            "expected Holding(VerifyFailed), got {phase:?}"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_valid_profile_but_waiting_for_network_holds_the_dedicated_reason() {
        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml");
        std::fs::copy(
            fixture_path("settings/valid-multi-layer.yml"),
            &profile_path,
        )
        .unwrap();
        let mock_cc = write_mock_cc(&dir);
        let waiting = fixture_path("corpus/waiting-for-network-startup.json");

        let phase = run_with_mock(Some(&mock_cc), Some(&waiting), || {
            run(&fast_config(profile_path), |_| {})
        });

        assert_eq!(
            phase,
            WizardPhase::Holding(HoldingReason::WaitingForNetwork)
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_present_but_invalid_profile_holds_immediately_never_touching_the_cli() {
        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml");
        std::fs::copy(
            fixture_path("settings/invalid-missing-required-field.yml"),
            &profile_path,
        )
        .unwrap();

        // No CT_CLI_PATH override at all: if this code path ever reached
        // materialize/doctor, `path::resolve()` would fail closed anyway —
        // but the real point of this test is that it must never even TRY,
        // per the module doc's "schema-validate FIRST" framing.
        let phase = run_with_mock(None, None, || run(&fast_config(profile_path), |_| {}));

        match phase {
            WizardPhase::Holding(HoldingReason::ItConfigIncomplete { key }) => {
                assert_eq!(key, "auth", "expected the real missing field name");
            }
            other => panic!("expected Holding(ItConfigIncomplete), got {other:?}"),
        }

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_absent_profile_retries_across_the_settling_window_then_holds() {
        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml"); // never written

        let phase = run_with_mock(None, None, || run(&fast_config(profile_path), |_| {}));

        match phase {
            WizardPhase::Holding(HoldingReason::ItConfigIncomplete { key }) => {
                assert_eq!(key, PROFILE_ABSENT_KEY);
            }
            other => panic!("expected Holding(ItConfigIncomplete), got {other:?}"),
        }

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The four managed outcomes above prove the honest-holding shape; this
    /// one proves the SPECIFIC "materialize (and, in this unavailable-CLI
    /// case, doctor too) never crashes and never fabricates Healthy" claim —
    /// a valid profile but a completely unreachable CLI still ends in an
    /// honest `Holding`, never a panic and never `Done`.
    #[test]
    fn materialize_and_doctor_both_unavailable_holds_engine_unreadable_never_crashes() {
        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml");
        std::fs::copy(
            fixture_path("settings/valid-multi-layer.yml"),
            &profile_path,
        )
        .unwrap();

        let bogus = PathBuf::from("/nonexistent/definitely-not-a-real-cc-binary");
        let phase = run_with_mock(Some(&bogus), None, || {
            run(&fast_config(profile_path), |_| {})
        });

        assert_eq!(
            phase,
            WizardPhase::Holding(HoldingReason::EngineUnreadable),
            "an unreachable CLI must hold honestly, never crash and never fabricate Healthy"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -- M3 QA follow-up D3: live progress streaming ------------------------

    /// `on_phase` must be called with every intermediate phase `run` legally
    /// reaches, in order, ending in `Done` for a healthy run — the mechanism
    /// `commands::wizard_advance` relies on to push live progress into
    /// `WizardIpcState` between IPC calls (see the module doc's "Live
    /// progress" section). Every observed label is a NAME, never an
    /// ETA/countdown/percentage (ADR-M3-003) — checked directly here, not
    /// just by the crate-wide `fitness_no_eta_in_wizard` grep, since these
    /// are freshly streamed values, not static source text.
    #[test]
    fn on_phase_streams_every_intermediate_phase_ending_in_done() {
        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml");
        std::fs::copy(
            fixture_path("settings/valid-multi-layer.yml"),
            &profile_path,
        )
        .unwrap();
        let mock_cc = write_mock_cc(&dir);
        let healthy = fixture_path("corpus/healthy-clean-fleet.json");

        let mut observed: Vec<WizardPhase> = Vec::new();
        let final_phase = run_with_mock(Some(&mock_cc), Some(&healthy), || {
            run(&fast_config(profile_path), |phase| {
                observed.push(phase.clone())
            })
        });

        assert_eq!(final_phase, WizardPhase::Done);
        assert!(
            !observed.is_empty(),
            "on_phase must fire at least once for a real run"
        );
        assert_eq!(
            observed.last(),
            Some(&WizardPhase::Done),
            "the last streamed phase must be the same terminal `run` returns"
        );
        assert_eq!(
            observed.first(),
            Some(&WizardPhase::Detect),
            "the first streamed phase must be Detect, never a fabricated head start"
        );
        assert!(
            observed
                .iter()
                .any(|p| matches!(p, WizardPhase::Materialize { phase_name } if phase_name == "Setting up Claude…")),
            "the CLI-supplied materialize phase names must stream through, observed: {observed:?}"
        );
        assert!(
            observed.contains(&WizardPhase::Verify),
            "Verify must stream before the terminal phase, observed: {observed:?}"
        );

        let banned = ["%", "eta", "seconds left", "minutes left", "estimated"];
        for phase in &observed {
            let label =
                crate::wizard::dto::to_wizard_state(WizardMode::Managed, phase, vec![], None, None)
                    .phase_label
                    .to_lowercase();
            for term in banned {
                assert!(
                    !label.contains(term),
                    "streamed phase {phase:?} rendered an ETA-shaped label: {label:?}"
                );
            }
        }

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -- M3 QA follow-up D2: resumability -----------------------------------

    /// `run` saves a checkpoint at Materialize's first entry and at any
    /// Holding terminal (module doc's "Resumability" section) — proven here
    /// by round-tripping through the real (mock) `cc config set/get`, the
    /// same seam `persistence.rs`'s own tests use.
    #[test]
    fn run_checkpoints_at_materialize_entry_and_at_a_holding_terminal() {
        use crate::cli::test_env::ENV_LOCK;
        use crate::wizard::persistence;
        use std::io::Write as _;

        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml");
        std::fs::copy(
            fixture_path("settings/valid-multi-layer.yml"),
            &profile_path,
        )
        .unwrap();

        // A combined mock implementing `update`/`doctor` (this module's own
        // `write_mock_cc`) AND `config set/get` (persistence's own dotted
        // JSON store), so a single CT_CLI_PATH override serves both seams
        // for the duration of one `run` call.
        let script = dir.join("mock-cc-managed-flow-checkpoint");
        let config_path = dir.join("config.json");
        {
            let mut f = std::fs::File::create(&script).unwrap();
            writeln!(f, "#!/usr/bin/env python3").unwrap();
            writeln!(f, "import json, os, sys").unwrap();
            writeln!(f, "verb = sys.argv[1]").unwrap();
            writeln!(f, "if verb == 'update':").unwrap();
            writeln!(f, "    print('{{\"phase\": \"Setting up Claude…\"}}')").unwrap();
            writeln!(f, "    print('{{\"done\": true}}')").unwrap();
            writeln!(f, "    sys.exit(0)").unwrap();
            writeln!(f, "elif verb == 'doctor':").unwrap();
            writeln!(
                f,
                "    print(open(os.environ['MOCK_DOCTOR_BODY_PATH']).read())"
            )
            .unwrap();
            writeln!(f, "    sys.exit(0)").unwrap();
            writeln!(f, "elif verb == 'config':").unwrap();
            writeln!(f, "    config_path = os.environ['MOCK_CC_CONFIG_PATH']").unwrap();
            writeln!(f, "    try:").unwrap();
            writeln!(f, "        data = json.load(open(config_path))").unwrap();
            writeln!(f, "    except Exception:").unwrap();
            writeln!(f, "        data = {{}}").unwrap();
            writeln!(f, "    action, key = sys.argv[2], sys.argv[3]").unwrap();
            writeln!(f, "    if action == 'set':").unwrap();
            writeln!(f, "        data[key] = sys.argv[4]").unwrap();
            writeln!(f, "        json.dump(data, open(config_path, 'w'))").unwrap();
            writeln!(f, "    elif action == 'get':").unwrap();
            writeln!(
                f,
                "        print(json.dumps({{'key': key, 'value': data.get(key)}}))"
            )
            .unwrap();
            writeln!(f, "    sys.exit(0)").unwrap();
            writeln!(f, "else:").unwrap();
            writeln!(f, "    sys.exit(2)").unwrap();
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&script).unwrap().permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&script, perms).unwrap();
        }
        let healthy = fixture_path("corpus/healthy-clean-fleet.json");

        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK, same shared lock every other
        // CT_CLI_PATH-touching test in this crate uses.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, &script);
            std::env::set_var("MOCK_DOCTOR_BODY_PATH", &healthy);
            std::env::set_var("MOCK_CC_CONFIG_PATH", &config_path);
        }
        let phase = run(&fast_config(profile_path), |_| {});
        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_DOCTOR_BODY_PATH");
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
        }
        drop(_guard);

        assert_eq!(phase, WizardPhase::Done);

        // Re-enter the SAME env to read back what `run` actually persisted —
        // proves a checkpoint really landed (Materialize's first entry, the
        // only checkpointable moment a healthy run passes through).
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, &script);
            std::env::set_var("MOCK_CC_CONFIG_PATH", &config_path);
        }
        let checkpoint = persistence::load_checkpoint();
        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
        }
        drop(_guard);

        let checkpoint =
            checkpoint.expect("run must have saved a checkpoint at Materialize's first entry");
        assert_eq!(
            checkpoint.phase,
            persistence::CheckpointPhase::Materialize,
            "Done itself is never checkpointable, so the last surviving checkpoint from a \
             healthy run must still be the Materialize-entry one"
        );
        assert_eq!(checkpoint.mode, WizardMode::Managed);

        let _ = std::fs::remove_dir_all(&dir);
    }
}
