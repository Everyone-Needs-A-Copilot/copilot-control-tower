//! First-run completion + resumability persistence (S2, `.copilot/wp/15.md`
//! §2 S2, ADR-M3-004).
//!
//! **This module persists; it computes nothing new.** It reuses the EXACT
//! M2 `settings::config_pointer` seam and discipline (same module doc, same
//! dev-mockable `CT_CLI_PATH` seam, same honest-degrade shape): two dotted
//! config keys, `wizard.completed` and `wizard.checkpoint`, written and read
//! by shelling to `cc config set <key> <value>` / `cc config get <key>
//! --json` — **never** a Rust JSON read-modify-write of
//! `~/.claude/cc/config.json`. The single writer of that file is `cc` itself
//! (same D-5-M2 rule `config_pointer.rs` already follows); this module only
//! ever calls the one verb that already does the dotted-set/get correctly,
//! through the same `cli::path::resolve()` seam (`CT_CLI_PATH` in
//! debug/test, the vendored bundle path in release — never a bare `cc`/
//! `copilot` name, fitness-guarded by `tests/fitness_no_bare_cli_name.rs`).
//! Because `cc config set` performs a dotted-set that preserves every
//! sibling key, and because this module never opens the config file itself,
//! a wizard checkpoint write structurally cannot clobber `paths.*`,
//! `layers.*`, or any other config a different feature owns (never-destroy,
//! invariant #3) — the same guarantee `config_pointer.rs`'s own doc argues
//! for `layers.manifest`.
//!
//! ## Completion — no false-Healthy, no bypass
//!
//! [`mark_complete`] takes the CURRENT `WizardPhase` and refuses (an honest
//! `Err`, never a silent no-op success) to write `wizard.completed=true`
//! unless that phase is `WizardPhase::Done` — and `Done` is reachable, per
//! `state::transition`'s own exhaustive match, ONLY via a `Verified` event
//! carrying a parsed, trusted `CliStatus` where `is_healthy()` is true
//! (ADR-M3-002). This module computes no verdict of its own (parse-never-
//! compute, invariant #1); it only refuses to persist "complete" for any
//! phase this crate's own state machine hasn't already legally proven
//! Healthy.
//!
//! ## No secret, ever (invariant #6)
//!
//! [`WizardCheckpoint`] carries only the phase-resume tag
//! ([`CheckpointPhase`]) plus the unmanaged flow's collected NON-secret
//! answers (product selection, company, department — plain strings a Bob
//! typed into a form). It has no field for a token/credential/keychain
//! value; S3's sign-in seam writes those straight to the OS keychain via the
//! CLI and never hands this crate anything to persist. See this module's own
//! `no_secret_bearing_field_on_wizard_checkpoint` test (a `syn`-based
//! field-name scan, same technique as
//! `tests/fitness_no_secret_on_wizard_dto.rs`) for the automated guard.
//!
//! ## Resumability — honoring S1's checkpoint design
//!
//! S1's `state.rs` doc names exactly two resumable moments: `Materialize`'s
//! FIRST entry (`phase_name` still empty — Detect/Question is done, nothing
//! destructive has started yet) and any `Holding` terminal (resumed via the
//! already-legal `Holding -> Detect` move on `WizardEvent::HoldingResolved`).
//! [`CheckpointPhase`] names only those two moments — deliberately NOT the
//! full `WizardPhase` (which isn't `Serialize`/`Deserialize` by design, per
//! `state.rs`'s own doc, and a `Holding(VerifyFailed{status})` payload could
//! otherwise leak a raw `CliStatus` into config). [`resume_phase`]
//! reconstructs where a resumed session continues from by DRIVING the real,
//! already-tested `state::transition()` function — never hand-constructing a
//! phase this crate hasn't proven legal:
//! - A `Materialize` checkpoint means "all questions were already answered,
//!   ready to materialize" — resuming re-enters `Materialize` directly
//!   (that phase's first entry IS what was checkpointed).
//! - A `Holding` checkpoint resumes via the one transition
//!   `(Holding(_), HoldingResolved) -> Detect` that already exists in
//!   `state.rs` for exactly this purpose. Every `HoldingReason` transitions
//!   identically on `HoldingResolved`, so which reason it originally was
//!   doesn't change the destination — a placeholder reason drives the same
//!   real table entry a genuine holding resume would.
//!
//! Either way, a mid-setup quit resumes headlessly and never re-asks a
//! question S5 already collected an answer for, and never re-runs
//! `Materialize` from an earlier, already-superseded phase name.

use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;

use serde::{Deserialize, Serialize};

use crate::wizard::state::{self, HoldingReason, WizardEvent, WizardMode, WizardPhase};

/// `cc config set/get wizard.completed <...>` — "has the first-run wizard
/// ever reached `Done`". Never read/written by anything but this module.
const COMPLETED_KEY: &str = "wizard.completed";
/// `cc config set/get wizard.checkpoint <...>` — the JSON-encoded
/// [`WizardCheckpoint`] a resume reads back. Never read/written by anything
/// but this module.
const CHECKPOINT_KEY: &str = "wizard.checkpoint";

/// The literal value [`mark_complete`] writes for [`COMPLETED_KEY`]. Any
/// other stored value (including absent) reads as "not complete" —
/// [`is_first_run`] never treats an unrecognized value as proof of
/// completion (honest degrade, never a false "done").
const COMPLETED_VALUE: &str = "true";

/// Why a persistence read/write didn't succeed. Mirrors
/// `settings::config_pointer::ConfigPointerError`'s shape and honesty
/// discipline exactly (same seam, same failure modes) — plus one variant
/// this module adds for its own completion gate.
#[derive(Debug, Clone, PartialEq)]
pub enum PersistenceError {
    /// `cli::path::resolve()` couldn't find a usable `cc` binary at all —
    /// not vendored yet in production, or no `CT_CLI_PATH` set in dev. An
    /// honest "the CLI isn't available yet", never a crash or a false
    /// "saved"/"loaded".
    CliUnavailable,
    /// `cc` was found and ran, but exited non-zero, produced an unreadable
    /// body, or couldn't be spawned despite resolving to a path.
    CommandFailed { message: String },
    /// [`mark_complete`] was called with a phase other than `Done` — refused
    /// rather than silently no-op-succeeding, so a caller can't accidentally
    /// mark first-run complete before a real `Verified(Healthy)` was ever
    /// reached (no false-Healthy / no bypass — see module doc).
    NotDone,
}

impl std::fmt::Display for PersistenceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PersistenceError::CliUnavailable => write!(
                f,
                "The CLI isn't available yet to save your setup progress. Once it's \
                 installed, this will pick up automatically."
            ),
            PersistenceError::CommandFailed { message } => write!(f, "{message}"),
            PersistenceError::NotDone => write!(
                f,
                "Setup hasn't finished successfully yet, so nothing was marked complete."
            ),
        }
    }
}

impl std::error::Error for PersistenceError {}

/// The two resumable moments S1's state machine names for a checkpoint (see
/// module doc's "Resumability" section). Deliberately NOT the full
/// `WizardPhase` — see that section for why.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CheckpointPhase {
    /// `Materialize`'s first entry — Detect/Question already finished,
    /// nothing destructive has started.
    Materialize,
    /// Any `Holding` terminal — resumed via `HoldingResolved` back to
    /// `Detect`.
    Holding,
}

/// Everything a resume needs to reconstruct where the first-run wizard left
/// off, and NOTHING else. **No secret ever belongs on this struct**
/// (invariant #6) — see module doc and this file's own fitness-style test.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WizardCheckpoint {
    pub mode: WizardMode,
    pub phase: CheckpointPhase,
    /// Non-secret answers ONLY: product selection, company, department —
    /// whatever S5's ≤3-question flow collected before `Materialize`
    /// started. A credential/token never lands here; S3's sign-in seam
    /// hands those straight to the OS keychain via the CLI.
    pub answers: BTreeMap<String, String>,
}

impl WizardCheckpoint {
    /// Builds a checkpoint for `phase`, or `None` if `phase` isn't one of
    /// the two moments S1 designed as checkpointable (see module doc).
    /// `Materialize` only counts at its FIRST entry (`phase_name` still
    /// empty) — a `PhaseNamed` update mid-materialize does NOT re-checkpoint
    /// (the whole point is that the checkpoint captures "ready to
    /// materialize", not any particular sub-step of materializing).
    /// Callers (S4/S5, later) should simply skip persisting when this
    /// returns `None` rather than saving a checkpoint for a moment nothing
    /// is designed to resume from.
    pub fn for_phase(
        mode: WizardMode,
        phase: &WizardPhase,
        answers: BTreeMap<String, String>,
    ) -> Option<Self> {
        let checkpoint_phase = match phase {
            WizardPhase::Materialize { phase_name } if phase_name.is_empty() => {
                CheckpointPhase::Materialize
            }
            WizardPhase::Holding(_) => CheckpointPhase::Holding,
            _ => return None,
        };
        Some(WizardCheckpoint {
            mode,
            phase: checkpoint_phase,
            answers,
        })
    }

    /// Reconstructs the `WizardPhase` a resumed session continues from —
    /// see module doc's "Resumability" section for why each arm is legal.
    /// Always driven through `state::transition()`, never a bare
    /// hand-constructed phase, for the `Holding` case.
    pub fn resume_phase(&self) -> WizardPhase {
        match self.phase {
            CheckpointPhase::Materialize => WizardPhase::Materialize {
                phase_name: String::new(),
            },
            CheckpointPhase::Holding => {
                // The concrete reason doesn't affect the destination (every
                // `HoldingReason` transitions identically on
                // `HoldingResolved`) — a placeholder just drives the same
                // real, already-tested transition table entry.
                let holding = WizardPhase::Holding(HoldingReason::WaitingForNetwork);
                state::transition(&holding, WizardEvent::HoldingResolved).unwrap_or_else(|e| {
                    unreachable!(
                        "Holding -> HoldingResolved is unconditionally legal in \
                         state::transition; got {e:?}"
                    )
                })
            }
        }
    }
}

/// `true` unless `cc config get wizard.completed` reads back exactly
/// [`COMPLETED_VALUE`]. Every other outcome — unset, some other value, or
/// the CLI being unavailable/failing — reads as "still first run", never as
/// "must be complete" (honest degrade; never a false "already set up").
pub fn is_first_run() -> bool {
    !matches!(
        read_config_value(COMPLETED_KEY),
        Ok(Some(value)) if value == COMPLETED_VALUE
    )
}

/// Marks the first run complete — but ONLY for `WizardPhase::Done` (see
/// module doc's "no false-Healthy, no bypass"). Any other phase is refused
/// with [`PersistenceError::NotDone`], never a silent success.
pub fn mark_complete(phase: &WizardPhase) -> Result<(), PersistenceError> {
    if !matches!(phase, WizardPhase::Done) {
        return Err(PersistenceError::NotDone);
    }
    write_config_value(COMPLETED_KEY, COMPLETED_VALUE)
}

/// Persists `checkpoint` as JSON under [`CHECKPOINT_KEY`].
pub fn save_checkpoint(checkpoint: &WizardCheckpoint) -> Result<(), PersistenceError> {
    let json = serde_json::to_string(checkpoint)
        .unwrap_or_else(|e| unreachable!("WizardCheckpoint always serializes: {e}"));
    write_config_value(CHECKPOINT_KEY, &json)
}

/// Reads back whatever [`save_checkpoint`] last wrote, or `None` if nothing
/// has been saved yet, the CLI is unavailable, or the stored value isn't a
/// valid checkpoint (fail closed — a caller never resumes into a phase this
/// function merely guessed at).
pub fn load_checkpoint() -> Option<WizardCheckpoint> {
    match read_config_value(CHECKPOINT_KEY) {
        Ok(Some(value)) => serde_json::from_str(&value).ok(),
        _ => None,
    }
}

/// The convenience the live S4/S5 orchestration actually calls after EVERY
/// phase move (`managed_flow::run`'s and `unmanaged_flow::UnmanagedFlow`'s own
/// call sites): builds a checkpoint via [`WizardCheckpoint::for_phase`] and
/// saves it, or does nothing at all when `phase` isn't one of the two
/// checkpointable moments that function's own doc names — callers never need
/// to branch on the `Option` themselves, and never pay a wasted `cc config
/// set` spawn for a non-checkpointable phase (`for_phase` returns `None`
/// before this function would ever call [`save_checkpoint`]).
///
/// A save failure (CLI unavailable, `cc` exits non-zero, …) is swallowed
/// here, same discipline as `commands::finish_if_done`'s own `mark_complete`
/// call: resumability is a best-effort convenience, never a gate on the
/// wizard flow itself continuing. An unsaved checkpoint just means a future
/// interrupted run restarts instead of resuming — not a wizard failure right
/// now, and never a panic or a silently-corrupted flow.
pub fn checkpoint_phase_if_resumable(
    mode: WizardMode,
    phase: &WizardPhase,
    answers: BTreeMap<String, String>,
) {
    if let Some(checkpoint) = WizardCheckpoint::for_phase(mode, phase, answers) {
        let _ = save_checkpoint(&checkpoint);
    }
}

/// Shells to `cc config set <key> <value>` — the same `Command::new(cli_path)`
/// shape `config_pointer::set_manifest_pointer` uses (never a bare `cc`/
/// `copilot` name; `cli_path` always comes from `cli::path::resolve()`).
fn write_config_value(key: &str, value: &str) -> Result<(), PersistenceError> {
    let cli_path = crate::cli::path::resolve().map_err(|_| PersistenceError::CliUnavailable)?;
    run_config_set(&cli_path, key, value)
}

fn run_config_set(cli_path: &Path, key: &str, value: &str) -> Result<(), PersistenceError> {
    let output = Command::new(cli_path)
        .arg("config")
        .arg("set")
        .arg(key)
        .arg(value)
        .output();

    match output {
        Ok(result) if result.status.success() => Ok(()),
        Ok(result) => Err(PersistenceError::CommandFailed {
            message: format!(
                "Your setup progress couldn't be saved (exit code {}). Nothing else changed.",
                result
                    .status
                    .code()
                    .map(|c| c.to_string())
                    .unwrap_or_else(|| "unknown".to_string())
            ),
        }),
        Err(e) => Err(PersistenceError::CommandFailed {
            message: format!("Your setup progress couldn't be saved: {e}."),
        }),
    }
}

/// Shells to `cc config get <key> --json` and reads back the `{"key":...,
/// "value":...}` body. `Ok(None)` covers every honest "nothing usable"
/// case — unset (`value` is JSON `null`), or a stored value that isn't a
/// plain string (this module never writes anything but a string, so an
/// unrecognized shape is treated as absent rather than trusted) — never a
/// crash on an unexpected body.
fn read_config_value(key: &str) -> Result<Option<String>, PersistenceError> {
    let cli_path = crate::cli::path::resolve().map_err(|_| PersistenceError::CliUnavailable)?;
    run_config_get(&cli_path, key)
}

fn run_config_get(cli_path: &Path, key: &str) -> Result<Option<String>, PersistenceError> {
    let output = Command::new(cli_path)
        .arg("config")
        .arg("get")
        .arg(key)
        .arg("--json")
        .output();

    let result = match output {
        Ok(result) => result,
        Err(e) => {
            return Err(PersistenceError::CommandFailed {
                message: format!("Your setup progress couldn't be read back: {e}."),
            })
        }
    };

    if !result.status.success() {
        return Err(PersistenceError::CommandFailed {
            message: format!(
                "Your setup progress couldn't be read back (exit code {}).",
                result
                    .status
                    .code()
                    .map(|c| c.to_string())
                    .unwrap_or_else(|| "unknown".to_string())
            ),
        });
    }

    let stdout = String::from_utf8_lossy(&result.stdout);
    let parsed: serde_json::Value = match serde_json::from_str(stdout.trim()) {
        Ok(v) => v,
        // An unreadable body from `cc` itself is this function's OWN
        // fail-closed case, distinct from `CliUnavailable` (the CLI ran; its
        // output just wasn't the shape expected) — honest "nothing usable",
        // never a crash.
        Err(_) => return Ok(None),
    };

    Ok(match parsed.get("value") {
        Some(serde_json::Value::String(s)) => Some(s.clone()),
        _ => None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;
    use std::io::Write as _;
    use std::sync::atomic::{AtomicU64, Ordering};

    static DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    /// A fresh, isolated temp directory per call — never the real
    /// `~/.copilot`/`~/.claude`. Every test below points its own mock `cc`
    /// at a config file under here, never at a real path.
    fn temp_dir() -> std::path::PathBuf {
        let n = DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ct-wizard-persistence-test-{}-{:?}-{n}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp test dir");
        dir
    }

    /// A throwaway stand-in `cc` implementing JUST enough of `config get
    /// --json` / `config set` to round-trip a dotted key against a real JSON
    /// file — local to this module's own tests (same pattern
    /// `config_pointer.rs`'s tests use: a private mock, never the shared
    /// `fixtures/mock-cc`, which only implements `doctor`/`auth`). Operates
    /// on `$MOCK_CC_CONFIG_PATH`, a test-only env var this script alone
    /// reads (never part of the real app<->`cc` contract — the real CLI
    /// decides its own `~/.claude/cc/config.json` path itself, with no path
    /// argument passed by this crate either).
    fn write_mock_cc(dir: &Path) -> std::path::PathBuf {
        let script = dir.join("mock-cc-config");
        let mut f = std::fs::File::create(&script).unwrap();
        writeln!(f, "#!/usr/bin/env python3").unwrap();
        writeln!(f, "import json, os, sys").unwrap();
        writeln!(f, "config_path = os.environ['MOCK_CC_CONFIG_PATH']").unwrap();
        writeln!(f, "args = sys.argv[1:]").unwrap();
        writeln!(f, "verb, action = args[0], args[1]").unwrap();
        writeln!(f, "assert verb == 'config'").unwrap();
        writeln!(f, "try:").unwrap();
        writeln!(f, "    with open(config_path) as fh:").unwrap();
        writeln!(f, "        data = json.load(fh)").unwrap();
        writeln!(f, "except Exception:").unwrap();
        writeln!(f, "    data = {{}}").unwrap();
        writeln!(f, "def dotted_get(d, key):").unwrap();
        writeln!(f, "    cur = d").unwrap();
        writeln!(f, "    for part in key.split('.'):").unwrap();
        writeln!(f, "        if isinstance(cur, dict) and part in cur:").unwrap();
        writeln!(f, "            cur = cur[part]").unwrap();
        writeln!(f, "        else:").unwrap();
        writeln!(f, "            return None").unwrap();
        writeln!(f, "    return cur").unwrap();
        writeln!(f, "def dotted_set(d, key, value):").unwrap();
        writeln!(f, "    parts = key.split('.')").unwrap();
        writeln!(f, "    cur = d").unwrap();
        writeln!(f, "    for part in parts[:-1]:").unwrap();
        writeln!(
            f,
            "        if part not in cur or not isinstance(cur[part], dict):"
        )
        .unwrap();
        writeln!(f, "            cur[part] = {{}}").unwrap();
        writeln!(f, "        cur = cur[part]").unwrap();
        writeln!(f, "    cur[parts[-1]] = value").unwrap();
        writeln!(f, "if action == 'get':").unwrap();
        writeln!(f, "    key = args[2]").unwrap();
        writeln!(
            f,
            "    print(json.dumps({{'key': key, 'value': dotted_get(data, key)}}))"
        )
        .unwrap();
        writeln!(f, "elif action == 'set':").unwrap();
        writeln!(f, "    key, value = args[2], args[3]").unwrap();
        writeln!(f, "    dotted_set(data, key, value)").unwrap();
        writeln!(f, "    with open(config_path, 'w') as fh:").unwrap();
        writeln!(f, "        json.dump(data, fh, indent=2)").unwrap();
        writeln!(f, "else:").unwrap();
        writeln!(f, "    sys.exit(2)").unwrap();
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

    /// Sets up `CT_CLI_PATH` + `MOCK_CC_CONFIG_PATH` for the duration of `f`,
    /// serialized on the SAME process-global lock every other CLI-path test
    /// in this crate uses, and always cleans up both env vars afterward
    /// (even on panic, via a guard) so no test run ever leaks state into
    /// another.
    fn with_mock_cc<R>(dir: &Path, f: impl FnOnce() -> R) -> R {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let script = write_mock_cc(dir);
        let config_path = dir.join("config.json");
        // SAFETY: serialized by ENV_LOCK, the same lock every other test in
        // this crate that touches these process-global env vars uses.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, &script);
            std::env::set_var("MOCK_CC_CONFIG_PATH", &config_path);
        }
        let result = f();
        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
        }
        result
    }

    fn sample_answers() -> BTreeMap<String, String> {
        let mut answers = BTreeMap::new();
        answers.insert("products".to_string(), "claude,codex".to_string());
        answers.insert("company".to_string(), "Acme".to_string());
        answers.insert("department".to_string(), "engineering".to_string());
        answers
    }

    #[test]
    fn a_fresh_machine_reads_as_first_run() {
        let dir = temp_dir();
        with_mock_cc(&dir, || {
            assert!(
                is_first_run(),
                "a machine with no wizard.completed key must read as first run"
            );
        });
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn mark_complete_makes_is_first_run_false() {
        let dir = temp_dir();
        with_mock_cc(&dir, || {
            assert!(is_first_run());
            mark_complete(&WizardPhase::Done).expect("marking Done complete should succeed");
            assert!(
                !is_first_run(),
                "after mark_complete(Done), is_first_run() must read false"
            );
        });
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The completion gate (module doc's "no false-Healthy, no bypass"):
    /// `mark_complete` refuses every phase except `Done`, and a refusal
    /// never flips `is_first_run()`.
    #[test]
    fn mark_complete_refuses_every_phase_except_done() {
        let dir = temp_dir();
        with_mock_cc(&dir, || {
            for phase in [
                WizardPhase::Welcome,
                WizardPhase::Detect,
                WizardPhase::Question,
                WizardPhase::Materialize {
                    phase_name: String::new(),
                },
                WizardPhase::Verify,
                WizardPhase::Teach,
                WizardPhase::Holding(HoldingReason::WaitingForNetwork),
            ] {
                let result = mark_complete(&phase);
                assert_eq!(
                    result,
                    Err(PersistenceError::NotDone),
                    "phase {phase:?} must be refused, never silently marked complete"
                );
            }
            assert!(
                is_first_run(),
                "no refused mark_complete call may ever flip is_first_run() to false"
            );
        });
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn saving_then_loading_a_checkpoint_reconstructs_the_same_phase_and_answers() {
        let dir = temp_dir();
        with_mock_cc(&dir, || {
            assert!(load_checkpoint().is_none(), "nothing saved yet");

            let materialize_phase = WizardPhase::Materialize {
                phase_name: String::new(),
            };
            let checkpoint = WizardCheckpoint::for_phase(
                WizardMode::Unmanaged,
                &materialize_phase,
                sample_answers(),
            )
            .expect("Materialize's first entry must be checkpointable");
            save_checkpoint(&checkpoint).expect("save should succeed");

            let loaded = load_checkpoint().expect("checkpoint should load back");
            assert_eq!(loaded, checkpoint);
            assert_eq!(loaded.mode, WizardMode::Unmanaged);
            assert_eq!(loaded.phase, CheckpointPhase::Materialize);
            assert_eq!(
                loaded.answers.get("company").map(String::as_str),
                Some("Acme")
            );
        });
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Never-destroy (invariant #3): a checkpoint write must not disturb any
    /// sibling config key a different feature owns (e.g. `layers.manifest`,
    /// `paths.memory`) — the same guarantee `config_pointer.rs`'s doc
    /// argues for `layers.manifest`, here exercised end to end against a
    /// real (mock) dotted-set.
    #[test]
    fn a_checkpoint_write_preserves_unrelated_config_keys() {
        let dir = temp_dir();
        with_mock_cc(&dir, || {
            // Seed unrelated config through the SAME mock `cc` a real
            // caller would have used, so the file's shape is exactly what a
            // genuine prior `cc config set` would have produced.
            write_config_value("paths.memory", "~/.claude/memory").expect("seed paths.memory");
            write_config_value("layers.manifest", "/foo/copilot.layers.yml")
                .expect("seed layers.manifest");

            let before: serde_json::Value =
                serde_json::from_str(&std::fs::read_to_string(dir.join("config.json")).unwrap())
                    .unwrap();

            let materialize_phase = WizardPhase::Materialize {
                phase_name: String::new(),
            };
            let checkpoint = WizardCheckpoint::for_phase(
                WizardMode::Managed,
                &materialize_phase,
                sample_answers(),
            )
            .unwrap();
            save_checkpoint(&checkpoint).expect("save should succeed");
            mark_complete(&WizardPhase::Done).expect("mark complete should succeed");

            let after: serde_json::Value =
                serde_json::from_str(&std::fs::read_to_string(dir.join("config.json")).unwrap())
                    .unwrap();

            assert_eq!(
                before.get("paths"),
                after.get("paths"),
                "paths.* must be preserved verbatim by a wizard checkpoint write"
            );
            assert_eq!(
                before.get("layers"),
                after.get("layers"),
                "layers.* must be preserved verbatim by a wizard checkpoint write"
            );
            // And the wizard's own keys really did land.
            assert!(after.get("wizard").is_some());
        });
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The full interrupted-then-resumed story: a first run collects
    /// answers, reaches `Materialize`'s first entry (where S1 designed the
    /// checkpoint to live), gets interrupted (simulated by simply not
    /// finishing), and a fresh "process" resumes from exactly that phase
    /// with the same answers — never re-asking Question, never restarting
    /// from Welcome.
    #[test]
    fn an_interrupted_run_resumes_at_materialize_with_its_answers_intact() {
        let dir = temp_dir();
        with_mock_cc(&dir, || {
            // The original run: Welcome -> Detect -> Question -> Materialize.
            let p = state::transition(&WizardPhase::Welcome, WizardEvent::Begin).unwrap();
            let p = state::transition(&p, WizardEvent::DetectedUnmanagedWithQuestions).unwrap();
            assert_eq!(p, WizardPhase::Question);
            let p = state::transition(&p, WizardEvent::QuestionAnswered).unwrap();
            let p = state::transition(&p, WizardEvent::AllQuestionsAnswered).unwrap();
            assert_eq!(
                p,
                WizardPhase::Materialize {
                    phase_name: String::new()
                }
            );

            let checkpoint =
                WizardCheckpoint::for_phase(WizardMode::Unmanaged, &p, sample_answers()).unwrap();
            save_checkpoint(&checkpoint)
                .expect("checkpoint should save at Materialize's first entry");

            // --- simulated relaunch: nothing above is in scope any more ---
            assert!(
                is_first_run(),
                "an interrupted run must not read as complete"
            );
            let resumed = load_checkpoint().expect("checkpoint must survive the relaunch");
            let resumed_phase = resumed.resume_phase();

            assert_eq!(
                resumed_phase,
                WizardPhase::Materialize {
                    phase_name: String::new()
                },
                "resuming a Materialize checkpoint must land back at Materialize, not Welcome/Detect/Question"
            );
            assert_eq!(
                resumed.answers.get("products").map(String::as_str),
                Some("claude,codex"),
                "resuming must never lose the already-collected answers"
            );
        });
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The Holding side of resumability: a run interrupted while holding
    /// resumes via the SAME `HoldingResolved` transition `state.rs` already
    /// defines, landing back at `Detect` — never at Done/Teach, and never
    /// hand-constructed outside `state::transition`.
    #[test]
    fn an_interrupted_holding_run_resumes_via_holding_resolved_back_to_detect() {
        let dir = temp_dir();
        with_mock_cc(&dir, || {
            let holding = WizardPhase::Holding(HoldingReason::WaitingForNetwork);
            let checkpoint =
                WizardCheckpoint::for_phase(WizardMode::Unmanaged, &holding, BTreeMap::new())
                    .expect("a Holding phase must be checkpointable");
            save_checkpoint(&checkpoint).expect("save should succeed");

            let resumed = load_checkpoint().expect("checkpoint must load back");
            assert_eq!(resumed.phase, CheckpointPhase::Holding);
            assert_eq!(resumed.resume_phase(), WizardPhase::Detect);
        });
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Phases S1 never designed as a checkpoint moment (Welcome, Detect,
    /// Question, Verify, Teach, Done) must not silently produce a
    /// checkpoint — `for_phase` returns `None` rather than inventing a
    /// resume point nothing is prepared to use.
    #[test]
    fn only_materialize_first_entry_and_holding_are_checkpointable() {
        for phase in [
            WizardPhase::Welcome,
            WizardPhase::Detect,
            WizardPhase::Question,
            WizardPhase::Verify,
            WizardPhase::Teach,
            WizardPhase::Done,
        ] {
            assert!(
                WizardCheckpoint::for_phase(WizardMode::Unmanaged, &phase, BTreeMap::new())
                    .is_none(),
                "phase {phase:?} must not be checkpointable"
            );
        }

        // A `Materialize` that already has a CLI-supplied phase name (i.e.
        // NOT the first entry) must also refuse — the checkpoint is
        // specifically "ready to materialize", not any later sub-step.
        let mid_materialize = WizardPhase::Materialize {
            phase_name: "Setting up Claude…".to_string(),
        };
        assert!(
            WizardCheckpoint::for_phase(WizardMode::Unmanaged, &mid_materialize, BTreeMap::new())
                .is_none(),
            "a Materialize phase past its first entry must not re-checkpoint"
        );
    }

    #[test]
    fn honest_degrade_when_cli_is_unavailable() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK. No CT_CLI_PATH override at all —
        // a `cargo test` binary is not a macOS app bundle, so production
        // resolution has nothing vendored; resolve() fails closed exactly
        // like `config_pointer`'s own equivalent test.
        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
        }

        assert!(
            is_first_run(),
            "an unreadable CLI must never be read as 'setup already complete'"
        );
        assert!(
            load_checkpoint().is_none(),
            "an unreadable CLI must never fabricate a checkpoint"
        );
        assert_eq!(
            mark_complete(&WizardPhase::Done),
            Err(PersistenceError::CliUnavailable)
        );
        assert!(matches!(
            save_checkpoint(&WizardCheckpoint {
                mode: WizardMode::Unmanaged,
                phase: CheckpointPhase::Materialize,
                answers: BTreeMap::new(),
            }),
            Err(PersistenceError::CliUnavailable)
        ));
    }

    /// A plain-language `Display` — no raw io/serde/process jargon leaks
    /// past `PersistenceError`, mirroring `config_pointer::ConfigPointerError`'s
    /// discipline.
    #[test]
    fn error_messages_are_plain_language() {
        let messages = [
            PersistenceError::CliUnavailable.to_string(),
            PersistenceError::NotDone.to_string(),
            PersistenceError::CommandFailed {
                message:
                    "Your setup progress couldn't be saved (exit code 1). Nothing else changed."
                        .to_string(),
            }
            .to_string(),
        ];
        let banned = ["traceback", "panicked", "unwrap", "Err(", "stack trace"];
        for message in messages {
            let lower = message.to_lowercase();
            for term in banned {
                assert!(
                    !lower.contains(&term.to_lowercase()),
                    "message leaks jargon {term:?}: {message}"
                );
            }
        }
    }

    /// Fitness-style guard (same `syn`-based field-name scan
    /// `tests/fitness_no_secret_on_wizard_dto.rs` uses for the wire DTO,
    /// applied here to `WizardCheckpoint`): no field on this config-persisted
    /// struct may carry a secret-bearing name.
    #[test]
    fn no_secret_bearing_field_on_wizard_checkpoint() {
        const FORBIDDEN_SUBSTRINGS: [&str; 6] = [
            "token",
            "secret",
            "credential",
            "password",
            "keychain",
            "access_key",
        ];

        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("src")
            .join("wizard")
            .join("persistence.rs");
        let raw = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        let parsed = syn::parse_file(&raw)
            .unwrap_or_else(|e| panic!("syn::parse_file failed on {}: {e}", path.display()));

        let mut idents = Vec::new();
        for item in &parsed.items {
            if let syn::Item::Struct(s) = item {
                if s.ident == "WizardCheckpoint" {
                    for field in &s.fields {
                        if let Some(ident) = &field.ident {
                            idents.push(ident.to_string());
                        }
                    }
                }
            }
        }
        assert!(
            !idents.is_empty(),
            "expected to find WizardCheckpoint's fields in {}",
            path.display()
        );

        let offenders: Vec<(String, &'static str)> = idents
            .into_iter()
            .filter_map(|ident| {
                let lower = ident.to_lowercase();
                FORBIDDEN_SUBSTRINGS
                    .into_iter()
                    .find(|needle| lower.contains(needle))
                    .map(|needle| (ident, needle))
            })
            .collect();

        assert!(
            offenders.is_empty(),
            "found a secret-bearing field name on WizardCheckpoint: {offenders:?} — S3's \
             sign-in seam writes the keychain directly and this crate must never persist a \
             token (invariant #6)"
        );
    }
}
