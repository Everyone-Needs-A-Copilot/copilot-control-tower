//! The Rust <-> web-UI seam (T5).
//!
//! Two members from the original architecture WP: a `#[tauri::command]` the
//! popover calls once on open (`get_state`), and an event Rust pushes when a
//! fresh doctor parse changes state (`state-changed`, emitted from
//! `timer::poll_once`). A third command, `refresh_now`, is the manual "sync
//! now" escape hatch — it does not bypass anything, it just triggers the
//! SAME poll path (`timer::poll_once`) immediately instead of waiting for the
//! next tick.
//!
//! A fourth command, `hide_popover` (T9 D2 follow-up), lets the web UI ask
//! Rust to dismiss the popover on Esc or focus-loss/click-outside — the two
//! conventional menu-bar-popover dismissal gestures the tray's own
//! left-click toggle can't see, since those originate in the webview, not
//! from a native tray event. It delegates to `tray::hide_popover_window`,
//! the SAME function the tray's own click-toggle uses to hide this window,
//! so there is never a second, drifting "closed" implementation.
//!
//! The DTO crossing this seam is always the **typed domain state**
//! (`render::derive::RenderState`), never the raw wire JSON — the web UI must
//! never be able to reinterpret unparsed CLI output. See `model/state.rs`
//! and `render/derive.rs`.
//!
//! This module also owns the managed-state container (`DoctorState`): the
//! single source of truth `get_state` reads from and `timer::poll_once`
//! writes to. There is exactly one instance, `.manage()`d once in `lib.rs`'s
//! `.setup()` — no second copy of "the current state" exists anywhere in the
//! process (invariant #2's single-process discipline applies to state, not
//! just to not spawning a second binary).
//!
//! **Settings IPC (M2/S6):** `get_settings`/`save_settings`/
//! `open_settings_window`, at the bottom of this file, are the same seam
//! shape as `get_state`/`refresh_now` above — a typed DTO
//! (`settings::dto::SettingsState`) crossing the boundary, never raw wire
//! YAML — but for the layer-manifest surface instead of the doctor surface.
//! `save_settings` is the one place this crate wires S1-S5 together into a
//! single flow: author (S4, which itself calls S3's guard and S1's
//! validator) -> write (S2) -> point (S2) -> re-poll (reusing T5's
//! `timer::poll_once`, S5). See that function's doc for the exact ordering
//! and honesty-on-partial-failure contract.

use crate::model::state::{CliUnreadableReason, ParseOutcome};
use crate::render::derive::{derive_render_state, ClientState, HeaderView, RenderState};
use crate::settings;
use crate::settings::dto::{FieldError, LayerInput, LayerRow, SettingsState, Tier};
use crate::settings::manifest::{Layer, LayerManifest};
use crate::wizard;
use crate::wizard::state::{WizardMode, WizardPhase};
use crate::wizard::unmanaged_flow::{self, UnmanagedFlow};
use std::collections::BTreeMap;
use std::sync::Mutex;
use tauri::{AppHandle, Manager, State};

/// Event name Rust emits whenever a fresh doctor parse lands, whether or not
/// the state actually changed (the popover's cross-fade + a11y live region
/// key off a consistent "a poll just completed" signal — see `timer.rs`).
/// Mirrors `src/types.ts`'s `STATE_CHANGED_EVENT` constant.
pub const STATE_CHANGED_EVENT: &str = "state-changed";

/// The one instance of "what does the tray currently show", managed by
/// Tauri (`app.manage(..)` in `lib.rs`). `render` is a plain `std::sync::
/// Mutex` (short, synchronous critical section: read-clone or overwrite,
/// never held across an `.await`); `poll_lock` is the async mutex the doctor
/// timer and `refresh_now` both acquire around the actual `cli::run_doctor`
/// call, so at most one doctor poll is ever in flight at a time (T5's
/// "one-in-flight" requirement) — a concurrent trigger simply waits its turn
/// rather than stacking a second concurrent spawn.
pub struct DoctorState {
    render: Mutex<RenderState>,
    pub(crate) poll_lock: tauri::async_runtime::Mutex<()>,
}

impl DoctorState {
    pub fn new(initial: RenderState) -> Self {
        Self {
            render: Mutex::new(initial),
            poll_lock: tauri::async_runtime::Mutex::new(()),
        }
    }

    pub fn snapshot(&self) -> RenderState {
        self.render
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    pub fn replace(&self, fresh: RenderState) {
        *self.render.lock().unwrap_or_else(|e| e.into_inner()) = fresh;
    }
}

/// The honest bootstrap state held before the app's first doctor poll
/// returns: `client_state: CliUnreadable` with NO reason (distinct from any
/// real I/O/schema failure — `cli_unreadable_reason: None` is reachable only
/// from here and from `circuit_breaker_render_state` below, never from
/// `model::state::parse_doctor_body`, which always picks a concrete reason).
/// Deliberately NOT `ClientState::Ok` / any `CliStatus` — this function does
/// not go through the parse boundary at all (there is no CLI body yet to
/// parse), so it must not fabricate one; it is an honest "haven't checked
/// yet", never Healthy, never a guessed status.
pub fn initial_render_state() -> RenderState {
    RenderState {
        client_state: ClientState::CliUnreadable,
        cli_unreadable_reason: None,
        host: None,
        status: None,
        offline: false,
        header: HeaderView {
            glyph_state: "hollow".to_string(),
            sentence: "Checking your setup…".to_string(),
        },
        products: Vec::new(),
        auth_issues: Vec::new(),
    }
}

/// The honest degraded state shown when `updater::circuit_breaker`'s
/// launch-failure breaker trips (ADR-M4-001, D1 gap-closure):
/// `client_state: CliUnreadable` with no reason, same as
/// `initial_render_state` above and for the same reason — this state is not
/// derived from a CLI parse at all (no doctor poll has happened, or ever
/// will, this launch), so it must not fabricate a `CliStatus`/
/// `CliUnreadableReason` pulled from that unrelated domain. Distinguished
/// from the bootstrap state only by its glyph/sentence: `"bang"` (the one
/// red glyph, matching the CLI-unreadable io_error/exit_2 sentence's own
/// severity) and an honest, ETA-free "reinstalling should fix it" sentence —
/// never a false Healthy, per invariant #4/CLAUDE.md "the tray icon still
/// cannot lie".
pub fn circuit_breaker_render_state() -> RenderState {
    RenderState {
        client_state: ClientState::CliUnreadable,
        cli_unreadable_reason: None,
        host: None,
        status: None,
        offline: false,
        header: HeaderView {
            glyph_state: "bang".to_string(),
            sentence: "Control Tower keeps failing to start. Reinstalling should fix it."
                .to_string(),
        },
        products: Vec::new(),
        auth_issues: Vec::new(),
    }
}

/// Snapshot pull — the popover calls this once on open. Always returns
/// whatever the last successful (or fail-closed) doctor parse produced,
/// never recomputed here.
#[tauri::command]
pub fn get_state(state: State<'_, DoctorState>) -> RenderState {
    state.snapshot()
}

/// The manual "sync now" escape hatch. Triggers the SAME poll path the timer
/// uses (`timer::poll_once`) immediately; does not bypass the one-in-flight
/// guard, the CLI-spawn boundary, or the parse boundary — it is a trigger,
/// not a shortcut.
#[tauri::command]
pub async fn refresh_now(app: AppHandle) {
    crate::timer::poll_once(&app).await;
}

/// D2 (T9 follow-up): dismisses the popover — the web UI's Esc-keydown and
/// focus-loss/blur listeners (`src/main.ts`) both invoke this. A thin
/// passthrough to `tray::hide_popover_window`; this command owns no window
/// logic of its own (single-process invariant: exactly one place hides this
/// window, reachable from either the native tray click or this IPC seam).
#[tauri::command]
pub fn hide_popover(app: AppHandle) {
    crate::tray::hide_popover_window(&app);
}

/// Shared by `timer.rs`'s exceptional "the poll task itself failed to run"
/// path (e.g. `spawn_blocking` join error) — collapses to the same
/// `CliUnreadableReason::IoError` a genuine spawn failure gets, via the SAME
/// `derive_render_state` pipeline every other outcome goes through (never a
/// hand-built `RenderState` pretending to be a real verdict).
pub(crate) fn unreadable_io_error() -> RenderState {
    derive_render_state(&ParseOutcome::Unreadable(CliUnreadableReason::IoError))
}

// ---------------------------------------------------------------------------
// Settings IPC (M2/S6)
// ---------------------------------------------------------------------------

/// The Settings window's label, per `tauri.conf.json`'s `app.windows` (mirrors
/// `tray.rs`'s `POPOVER_LABEL` convention for the popover window).
const SETTINGS_WINDOW_LABEL: &str = "settings";

/// Reads whatever manifest is currently on disk (or an honest empty one on
/// first run — `settings::writer::read_existing`'s own contract) and
/// projects it into the [`SettingsState`] shape the web UI renders.
/// `errors` here are the manifest's OWN validation problems (S1) — never a
/// raw parse/io message; a manifest that fails to even parse becomes a
/// single manifest-wide [`FieldError`] with an empty `layers` list (the
/// honest "we can't show you anything from this file" state, not a crash).
#[tauri::command]
pub fn get_settings() -> SettingsState {
    get_settings_at(settings::writer::default_manifest_path())
}

/// The real logic behind [`get_settings`], factored out so it's directly
/// unit-testable against a temp-dir path — never the real `~/.copilot` (the
/// `#[tauri::command]` wrapper above is the only caller that passes the real
/// [`settings::writer::default_manifest_path`]).
pub(crate) fn get_settings_at(path: Option<std::path::PathBuf>) -> SettingsState {
    let managed = settings::managed::is_managed();
    let Some(path) = path else {
        return SettingsState {
            managed,
            layers: Vec::new(),
            errors: vec![home_dir_unavailable_error()],
        };
    };

    match settings::writer::read_existing(&path) {
        Ok(manifest) => {
            let mut layers = project_rows(&manifest);
            settings::managed::apply_gate(&mut layers, managed);
            // `validate_layers` on an empty-layers manifest produces EXACTLY
            // one error ("no layers declared") — the correct fail-closed
            // answer for a WRITE, but not something `get_settings` should
            // surface as an "error" banner: a first-run (no file yet) or a
            // hand-emptied manifest is the ordinary "nothing configured
            // yet" state, which the web UI already renders as its own
            // dedicated empty-state message (`SETTINGS_EMPTY_STATE`). Any
            // OTHER validation problem on a non-empty manifest is still
            // surfaced honestly.
            let errors = if manifest.layers.is_empty() {
                Vec::new()
            } else {
                settings::validate::validate_layers(&manifest)
            };
            SettingsState {
                managed,
                layers,
                errors,
            }
        }
        Err(e) => SettingsState {
            managed,
            layers: Vec::new(),
            errors: vec![FieldError {
                layer_id: None,
                field: "manifest".to_string(),
                message: e.to_string(),
            }],
        },
    }
}

/// The save flow: author (S4) -> guard (S3, inside S4) -> write (S2) ->
/// pointer (S2) -> re-poll (S5, reusing T5's `timer::poll_once`). Every step
/// after the managed-gate check is fail-closed and honest: a problem at any
/// point returns a [`SettingsState`] whose `errors` describe exactly what
/// went wrong (plain language, never a raw git/yaml/io message) and whose
/// `layers` reflect whatever is ACTUALLY on disk right now — never a
/// fabricated "saved" state when the write didn't happen, and never silence
/// about a partial success (e.g. the manifest wrote but the pointer didn't).
///
/// An empty `inputs` (the web UI's `collectEditableInputs` only ever submits
/// slots the user actually typed something into) is treated as a pure no-op
/// — it returns the current [`get_settings`] snapshot without touching the
/// guard/writer/pointer/re-poll pipeline at all, so opening Settings and
/// clicking Save without changing anything can never manufacture a
/// misleading "no layers declared" error on an otherwise-fine first-run
/// manifest.
#[tauri::command]
pub async fn save_settings(app: AppHandle, inputs: Vec<LayerInput>) -> SettingsState {
    save_settings_at(
        inputs,
        settings::writer::default_manifest_path(),
        || async {
            crate::timer::poll_once(&app).await;
        },
    )
    .await
}

/// The real logic behind [`save_settings`], factored out so it's directly
/// unit-testable against a temp-dir path with a MOCK re-poll trigger — never
/// a live `AppHandle`/`DoctorState`/tray (the `#[tauri::command]` wrapper
/// above is the only caller that passes the real
/// `settings::writer::default_manifest_path()` and the real
/// `timer::poll_once`). `repoll` is called AT MOST once, exactly where the
/// real command calls `timer::poll_once` — a test can assert it fired (or
/// didn't) via a counter closure without needing a Tauri runtime at all.
pub(crate) async fn save_settings_at<F, Fut>(
    inputs: Vec<LayerInput>,
    path: Option<std::path::PathBuf>,
    repoll: F,
) -> SettingsState
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = ()>,
{
    if inputs.is_empty() {
        return get_settings_at(path);
    }

    let managed = settings::managed::is_managed();
    let Some(path) = path else {
        return SettingsState {
            managed,
            layers: Vec::new(),
            errors: vec![home_dir_unavailable_error()],
        };
    };

    let existing = match settings::writer::read_existing(&path) {
        Ok(manifest) => manifest,
        Err(e) => {
            // Can't safely author/merge onto content we can't even read —
            // never-destroy means never guessing at what's already there.
            return SettingsState {
                managed,
                layers: Vec::new(),
                errors: vec![FieldError {
                    layer_id: None,
                    field: "manifest".to_string(),
                    message: e.to_string(),
                }],
            };
        }
    };

    let mut current_layers = project_rows(&existing);
    settings::managed::apply_gate(&mut current_layers, managed);

    let lock_errors = settings::managed::refuse_locked_writes(&inputs, &current_layers, managed);
    if !lock_errors.is_empty() {
        return SettingsState {
            managed,
            layers: current_layers,
            errors: lock_errors,
        };
    }

    let authored = match settings::authoring::author_manifest(&inputs, &existing) {
        Ok(manifest) => manifest,
        Err(errors) => {
            return SettingsState {
                managed,
                layers: current_layers,
                errors,
            }
        }
    };

    if let Err(e) = settings::writer::write_manifest(&path, &authored) {
        return SettingsState {
            managed,
            layers: current_layers,
            errors: vec![FieldError {
                layer_id: None,
                field: "manifest".to_string(),
                message: e.to_string(),
            }],
        };
    }

    // The manifest is safely on disk by this point — a pointer failure below
    // doesn't lose that work (see `config_pointer`'s own doc); it's surfaced
    // as an honest error alongside whatever DID get written, never silently
    // swallowed and never reported as a full success.
    let pointer_error = settings::config_pointer::set_manifest_pointer(&path)
        .err()
        .map(|e| FieldError {
            layer_id: None,
            field: "pointer".to_string(),
            message: e.to_string(),
        });

    // Re-poll ONLY on a fully successful save (manifest + pointer both
    // landed) — reuses the SAME poll path the timer/`refresh_now` use (T5),
    // never a second poll implementation. A pointer failure means `cc`
    // doesn't yet know where to look, so re-polling here would just re-fetch
    // the SAME stale config and could read as a false "synced" signal.
    if pointer_error.is_none() {
        repoll().await;
    }

    // Re-read from disk for the response — the response must reflect what's
    // ACTUALLY there, not what this function assumes it just wrote. On the
    // vanishingly rare chance the re-read itself fails right after a
    // successful write (a transient race, not a validation problem —
    // `write_manifest` already proved this exact merge is valid), fall back
    // to recomputing the SAME merge locally rather than claiming an empty
    // manifest, which would misleadingly imply nothing is configured.
    let fresh_manifest = settings::writer::read_existing(&path)
        .unwrap_or_else(|_| settings::writer::merge_by_id(existing.clone(), &authored).0);
    let mut fresh_layers = project_rows(&fresh_manifest);
    settings::managed::apply_gate(&mut fresh_layers, managed);

    SettingsState {
        managed,
        layers: fresh_layers,
        errors: pointer_error.into_iter().collect(),
    }
}

/// Opens (or re-focuses) the Settings window — the popover's "Preferences…"
/// row invokes this (`src/render/popover.ts`). A thin passthrough, same
/// "defensive no-op if the window is somehow absent" discipline as
/// `tray::toggle_popover`; this command owns no window-lifecycle logic
/// beyond show+focus (the window itself is declared once in
/// `tauri.conf.json`, `visible: false`, exactly like the popover).
#[tauri::command]
pub fn open_settings_window(app: AppHandle) {
    if let Some(window) = app.get_webview_window(SETTINGS_WINDOW_LABEL) {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

/// `default_manifest_path()` returns `None` only when `$HOME` isn't set at
/// all — vanishingly rare, but must fail closed with a plain-language
/// message rather than panicking or silently guessing a fallback location.
fn home_dir_unavailable_error() -> FieldError {
    FieldError {
        layer_id: None,
        field: "manifest".to_string(),
        message: "Couldn't figure out where to save your settings — your home folder isn't set. \
                  This is unusual; if it keeps happening, contact support."
            .to_string(),
    }
}

/// Projects every `org`/`dept`/`personal` layer in `manifest` into a
/// [`LayerRow`] (`editable` always starts `true` here — the managed gate,
/// `settings::managed::apply_gate`, is applied by the caller afterward, so
/// there is exactly one place that ever flips it). A layer whose `role`
/// isn't one of the three Settings-authorable tiers (most commonly
/// `"foundation"`, which Settings never authors — see `dto::Tier`'s doc) is
/// silently excluded, not an error: it's simply not part of the Settings
/// surface, the same way an unrecognized top-level YAML key is preserved by
/// the writer but never rendered as a row.
fn project_rows(manifest: &LayerManifest) -> Vec<LayerRow> {
    manifest.layers.iter().filter_map(project_row).collect()
}

fn project_row(layer: &Layer) -> Option<LayerRow> {
    let tier = tier_from_role(layer.role.as_deref()?)?;
    Some(LayerRow {
        id: layer.id.clone().unwrap_or_default(),
        product: layer.product.clone().unwrap_or_default(),
        tier,
        repo_url: layer
            .source
            .as_ref()
            .and_then(|s| s.repo.clone())
            .unwrap_or_default(),
        auth_ref: layer.auth.clone().unwrap_or_default(),
        rank: layer
            .rank
            .as_ref()
            .and_then(settings::validate::rank_as_i64)
            .unwrap_or_default(),
        editable: true,
    })
}

/// The reverse of `settings::authoring::tier_role` (private to that module)
/// — maps a manifest `role` string back to the DTO's [`Tier`]. Deliberately
/// narrower than the manifest's open `role` vocabulary (`"foundation"` and
/// any unrecognized role map to `None`, not a guessed tier): Settings only
/// ever renders the three tiers it can author.
fn tier_from_role(role: &str) -> Option<Tier> {
    match role {
        "personal" => Some(Tier::Personal),
        "department" => Some(Tier::Dept),
        "org" => Some(Tier::Org),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_state_is_never_healthy_and_carries_no_reason() {
        let s = initial_render_state();
        assert_eq!(s.client_state, ClientState::CliUnreadable);
        assert_eq!(s.cli_unreadable_reason, None);
        assert_eq!(s.status, None);
        assert_ne!(
            s.header.glyph_state, "none",
            "bootstrap state must never render the Healthy glyph"
        );
    }

    #[test]
    fn doctor_state_round_trips_through_replace_and_snapshot() {
        let ds = DoctorState::new(initial_render_state());
        let fresh = unreadable_io_error();
        ds.replace(fresh.clone());
        let got = ds.snapshot();
        assert_eq!(got.client_state, fresh.client_state);
        assert_eq!(got.cli_unreadable_reason, fresh.cli_unreadable_reason);
    }
}

/// M2/S6: `get_settings_at`/`save_settings_at` integration tests. Every test
/// here uses an isolated temp-dir manifest path (NEVER the real
/// `~/.copilot`), the `CT_MANAGED_OVERRIDE` seam (`settings::managed`) to
/// pin managed/unmanaged deterministically regardless of this machine's real
/// forced-domain state, and the SAME `CT_CLI_PATH` mock-`cc` seam
/// `settings::config_pointer`'s own tests use (never a real `cc` process).
/// `save_settings_at`'s `repoll` parameter is a plain counter closure here —
/// no live `AppHandle`/`DoctorState`/tray anywhere in this module, matching
/// the "cargo test only, no GUI" constraint.
#[cfg(test)]
mod settings_ipc_tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;
    use crate::settings::dto::{LayerInput, Tier};
    use crate::settings::managed::MANAGED_OVERRIDE_ENV;
    use std::io::Write as _;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
    use std::sync::Arc;

    static DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    /// A fresh, isolated temp dir per call, holding a NOT-YET-EXISTING
    /// `copilot.layers.yml` path — never the real `~/.copilot`, same
    /// discipline `settings::writer`'s own tests use.
    fn temp_manifest_path() -> PathBuf {
        let n = DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ct-settings-ipc-test-{}-{:?}-{n}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp test dir");
        dir.join("copilot.layers.yml")
    }

    /// Same mock-`cc` shape `settings::config_pointer`'s own tests use — an
    /// executable stand-in that logs its argv and exits with `exit_code`.
    fn write_mock_cc(dir: &Path, exit_code: i32) -> PathBuf {
        let script = dir.join("mock-cc-settings-ipc");
        let mut f = std::fs::File::create(&script).unwrap();
        writeln!(f, "#!/bin/sh").unwrap();
        writeln!(f, "echo \"$@\" >> \"$(dirname \"$0\")/invocations.log\"").unwrap();
        writeln!(f, "exit {exit_code}").unwrap();
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

    fn input(product: &str, tier: Tier, repo_url: &str) -> LayerInput {
        LayerInput {
            product: product.to_string(),
            tier,
            repo_url: repo_url.to_string(),
        }
    }

    /// Runs `save_settings_at` synchronously for a test — the ONLY await
    /// point in that function is the injected `repoll` future, which every
    /// test here resolves immediately (a plain counter bump), so
    /// `tauri::async_runtime::block_on`'s lazily-initialized default runtime
    /// (no live Tauri app required) is enough to drive it to completion.
    fn run_save(
        inputs: Vec<LayerInput>,
        path: Option<PathBuf>,
        repoll_count: &Arc<AtomicUsize>,
    ) -> SettingsState {
        let counter = Arc::clone(repoll_count);
        tauri::async_runtime::block_on(save_settings_at(inputs, path, move || {
            let counter = Arc::clone(&counter);
            async move {
                counter.fetch_add(1, Ordering::SeqCst);
            }
        }))
    }

    const FIXTURE_YAML: &str = r#"
version: 1
layers:
  - id: personal-pablo
    role: personal
    product: claude
    rank: 10
    source:
      repo: git@github-personal:pablo/claude-personal.git
    auth: ssh-personal
    activation: always
  - id: org-acme
    role: org
    product: claude
    rank: 30
    source:
      repo: git@github-work:acme/claude-org.git
    auth: ssh-work
    activation: always
"#;

    // -- get_settings_at ----------------------------------------------------

    #[test]
    fn first_run_no_manifest_returns_an_honest_empty_state() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "0") };

        let path = temp_manifest_path(); // never written to
        let state = get_settings_at(Some(path.clone()));

        assert!(!state.managed);
        assert!(state.layers.is_empty());
        assert!(
            state.errors.is_empty(),
            "first run must be an honest empty state, not an error: {:?}",
            state.errors
        );

        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn get_settings_maps_an_existing_manifest_with_correct_editable_flags() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "1") };

        let path = temp_manifest_path();
        std::fs::write(&path, FIXTURE_YAML).unwrap();

        let state = get_settings_at(Some(path.clone()));
        assert!(state.managed);
        assert!(
            state.errors.is_empty(),
            "fixture is valid: {:?}",
            state.errors
        );
        assert_eq!(state.layers.len(), 2);

        let personal = state
            .layers
            .iter()
            .find(|l| l.tier == Tier::Personal)
            .unwrap();
        assert!(
            personal.editable,
            "personal must always stay editable, even managed"
        );
        let org = state.layers.iter().find(|l| l.tier == Tier::Org).unwrap();
        assert!(!org.editable, "org must be locked on a managed machine");

        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn a_manifest_that_fails_to_parse_is_an_honest_error_not_a_crash() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "0") };

        let path = temp_manifest_path();
        std::fs::write(&path, ": : : not yaml {{{").unwrap();

        let state = get_settings_at(Some(path.clone()));
        assert!(state.layers.is_empty());
        assert!(!state.errors.is_empty());
        assert!(!state.errors[0].message.to_lowercase().contains("panicked"));

        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    // -- save_settings_at ----------------------------------------------------

    #[test]
    fn a_clean_save_writes_sets_the_pointer_and_triggers_exactly_one_repoll() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "0") };

        let path = temp_manifest_path();
        let dir = path.parent().unwrap().to_path_buf();
        let mock_cc = write_mock_cc(&dir, 0);
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(DEV_OVERRIDE_ENV, &mock_cc) };

        let repoll_count = Arc::new(AtomicUsize::new(0));
        let inputs = vec![input(
            "claude",
            Tier::Personal,
            "git@github-personal:me/claude-personal.git",
        )];
        let state = run_save(inputs, Some(path.clone()), &repoll_count);

        assert!(
            state.errors.is_empty(),
            "clean save must have no errors: {:?}",
            state.errors
        );
        assert_eq!(state.layers.len(), 1);
        assert_eq!(
            repoll_count.load(Ordering::SeqCst),
            1,
            "must re-poll exactly once"
        );

        let on_disk = std::fs::read_to_string(&path).expect("manifest must have been written");
        let manifest = crate::settings::manifest::parse_manifest(&on_disk).unwrap();
        assert_eq!(manifest.layers.len(), 1);

        let pointer_log = std::fs::read_to_string(dir.join("invocations.log"))
            .expect("the pointer-set mock cc should have run");
        assert!(pointer_log.contains("config set layers.manifest"));
        assert!(pointer_log.contains(&path.display().to_string()));

        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var(MANAGED_OVERRIDE_ENV);
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_empty_inputs_save_is_a_no_op_and_never_repolls() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "0") };
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };

        let path = temp_manifest_path(); // first run — nothing on disk
        let repoll_count = Arc::new(AtomicUsize::new(0));

        let state = run_save(Vec::new(), Some(path.clone()), &repoll_count);

        assert!(
            state.errors.is_empty(),
            "an empty-inputs save must never manufacture an error: {:?}",
            state.errors
        );
        assert!(state.layers.is_empty());
        assert_eq!(
            repoll_count.load(Ordering::SeqCst),
            0,
            "a no-op save must never re-poll"
        );
        assert!(!path.exists(), "a no-op save must never write a file");

        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn a_managed_write_to_an_org_layer_is_refused_and_never_repolls() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "1") };
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };

        let path = temp_manifest_path();
        std::fs::write(&path, FIXTURE_YAML).unwrap();
        let repoll_count = Arc::new(AtomicUsize::new(0));

        let inputs = vec![input(
            "claude",
            Tier::Org,
            "git@github-work:acme/renamed-org.git",
        )];
        let state = run_save(inputs, Some(path.clone()), &repoll_count);

        assert!(
            !state.errors.is_empty(),
            "a managed org edit must be refused"
        );
        assert!(state
            .errors
            .iter()
            .any(|e| e.message.contains("managed by your organization")));
        assert_eq!(
            repoll_count.load(Ordering::SeqCst),
            0,
            "a refused save must never re-poll"
        );

        let on_disk = std::fs::read_to_string(&path).unwrap();
        assert_eq!(
            on_disk, FIXTURE_YAML,
            "a refused save must never touch the on-disk manifest"
        );

        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn a_managed_write_to_the_personal_layer_is_allowed() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "1") };
        let path = temp_manifest_path();
        let dir = path.parent().unwrap().to_path_buf();
        let mock_cc = write_mock_cc(&dir, 0);
        unsafe { std::env::set_var(DEV_OVERRIDE_ENV, &mock_cc) };

        let repoll_count = Arc::new(AtomicUsize::new(0));
        let inputs = vec![input(
            "claude",
            Tier::Personal,
            "git@github-personal:me/claude-personal.git",
        )];
        let state = run_save(inputs, Some(path.clone()), &repoll_count);

        assert!(
            state.errors.is_empty(),
            "personal must stay writable even when managed: {:?}",
            state.errors
        );
        assert_eq!(repoll_count.load(Ordering::SeqCst), 1);

        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var(MANAGED_OVERRIDE_ENV);
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_pointer_failure_still_reports_the_written_manifest_and_skips_the_repoll() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK. No CT_CLI_PATH override at all —
        // in a `cargo test` binary (not a macOS app bundle) this fails
        // closed to CliUnavailable, exactly like `config_pointer`'s own
        // `cli_unavailable_is_an_honest_state_never_a_false_success` test.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "0") };
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };

        let path = temp_manifest_path();
        let repoll_count = Arc::new(AtomicUsize::new(0));
        let inputs = vec![input(
            "claude",
            Tier::Personal,
            "git@github-personal:me/claude-personal.git",
        )];
        let state = run_save(inputs, Some(path.clone()), &repoll_count);

        // The manifest write itself succeeded (no CLI needed for that) —
        // never a false "fully saved" story, but never a lost write either.
        assert!(
            path.exists(),
            "the manifest write must not be lost by a pointer failure"
        );
        assert_eq!(
            state.layers.len(),
            1,
            "the successfully-written layer must still be reported"
        );
        assert!(
            state.errors.iter().any(|e| e.field == "pointer"),
            "a pointer failure must be surfaced honestly: {:?}",
            state.errors
        );
        assert_eq!(
            repoll_count.load(Ordering::SeqCst),
            0,
            "must not re-poll when the pointer didn't move"
        );

        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn a_secret_bearing_input_is_refused_and_never_written_or_repolled() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(MANAGED_OVERRIDE_ENV, "0") };
        unsafe { std::env::remove_var(DEV_OVERRIDE_ENV) };

        let path = temp_manifest_path();
        let repoll_count = Arc::new(AtomicUsize::new(0));
        let inputs = vec![input(
            "claude",
            Tier::Personal,
            "https://x:ghp_1234567890ABCDEFabcdef1234567890AB@github.com/me/repo.git",
        )];
        let state = run_save(inputs, Some(path.clone()), &repoll_count);

        assert!(!state.errors.is_empty());
        for e in &state.errors {
            assert!(!e.message.contains("ghp_1234567890ABCDEFabcdef1234567890AB"));
        }
        assert!(!path.exists(), "a refused save must never write anything");
        assert_eq!(repoll_count.load(Ordering::SeqCst), 0);

        unsafe { std::env::remove_var(MANAGED_OVERRIDE_ENV) };
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    // -- project_rows / tier_from_role --------------------------------------

    #[test]
    fn a_foundation_layer_is_never_projected_as_a_settings_row() {
        let manifest = crate::settings::manifest::parse_manifest(
            r#"
version: 1
layers:
  - id: foundation
    role: foundation
    product: claude
    rank: 40
    source:
      repo: https://github.com/Everyone-Needs-A-Copilot/claude-copilot.git
    auth: anon
    activation: always
"#,
        )
        .unwrap();
        let rows = project_rows(&manifest);
        assert!(
            rows.is_empty(),
            "Settings never authors/renders the foundation tier"
        );
    }

    #[test]
    fn tier_from_role_matches_the_manifest_vocabulary_exactly() {
        assert_eq!(tier_from_role("personal"), Some(Tier::Personal));
        assert_eq!(tier_from_role("department"), Some(Tier::Dept));
        assert_eq!(tier_from_role("org"), Some(Tier::Org));
        assert_eq!(tier_from_role("foundation"), None);
        assert_eq!(
            tier_from_role("dept"),
            None,
            "the manifest spells it \"department\", not \"dept\""
        );
    }
}

// ---------------------------------------------------------------------------
// Wizard IPC (M3/S6, `.copilot/wp/15.md`)
// ---------------------------------------------------------------------------
//
// Combines S4 (managed silent orchestration), S5 (unmanaged guided
// orchestration), and S6 (this IPC surface + window) into the one seam a
// wizard window (S7) drives. Same DTO discipline as `get_state`/
// `get_settings` above: the web UI only ever sees `wizard::dto::WizardState`
// (S1's frozen shape), never a raw internal enum, never a secret (S3's own
// discipline, unchanged by this seam).
//
// **Done-only-from-doctor (ADR-M3-002), enforced structurally, not by this
// file's care:** neither `managed_flow::run` nor `unmanaged_flow::
// materialize_and_verify` can produce `WizardPhase::Done` except via
// `support::drive_verify`'s `Verified(Healthy)` guard (see those modules'
// own tests) — this file only ever relays whatever phase they legally
// reached, and only calls `wizard::persistence::mark_complete` when that
// phase is genuinely `Done`.

/// The wizard window's label, per `tauri.conf.json`'s `app.windows` (mirrors
/// `SETTINGS_WINDOW_LABEL`'s convention).
const WIZARD_WINDOW_LABEL: &str = "wizard";

/// The wizard's own internal orchestration state — mirrors `DoctorState`'s
/// "one instance, `.manage()`d once" discipline (invariant #2). Unlike
/// `DoctorState` (a periodic background poll), the wizard only ever advances
/// on an explicit IPC call, so a plain `std::sync::Mutex` with short,
/// synchronous critical sections is enough here too — the occasionally slow,
/// process-spawning flow work (`managed_flow::run`, `materialize_and_verify`,
/// the sign-in seam) always happens OUTSIDE the lock, on a `spawn_blocking`
/// thread, exactly like `timer::poll_once` does for the doctor seam.
#[derive(Debug, Clone)]
enum WizardRuntime {
    /// Nothing has run yet. `mode` is already known — `settings::managed::
    /// is_managed()` is a cheap, synchronous forced-domain check, not real
    /// I/O — but neither the silent managed run nor the guided flow's first
    /// step has started.
    NotStarted { mode: WizardMode },
    /// The managed silent flow's terminal phase, once `managed_flow::run`
    /// has executed — that function itself runs Detect through
    /// Verify/Teach/Done in one blocking call, so there is nothing
    /// "in progress" to represent between IPC calls.
    Managed(WizardPhase),
    /// The guided flow's own live, incrementally-driven state machine (S5).
    /// Boxed: `UnmanagedFlow` is far larger than `WizardRuntime`'s other two
    /// variants (it carries the product catalog, selected products, the
    /// manifest path, and an in-flight sign-in session), and clippy's
    /// `large_enum_variant` is right that leaving it unboxed would make
    /// every `WizardRuntime` — including the common `NotStarted`/`Managed`
    /// cases — pay that size on the stack.
    Unmanaged(Box<UnmanagedFlow>),
}

impl WizardRuntime {
    fn phase(&self) -> Option<&WizardPhase> {
        match self {
            WizardRuntime::NotStarted { .. } => None,
            WizardRuntime::Managed(phase) => Some(phase),
            WizardRuntime::Unmanaged(flow) => Some(flow.phase()),
        }
    }
}

pub struct WizardIpcState {
    inner: Mutex<WizardRuntime>,
}

impl WizardIpcState {
    pub fn new() -> Self {
        let mode = if settings::managed::is_managed() {
            WizardMode::Managed
        } else {
            WizardMode::Unmanaged
        };
        Self {
            inner: Mutex::new(Self::initial_runtime(mode)),
        }
    }

    /// The `WizardRuntime` a fresh `WizardIpcState` starts from — `NotStarted`
    /// unless an interrupted UNMANAGED first run left a resumable checkpoint
    /// behind (S2/ADR-M3-004, M3 QA follow-up D2). `is_first_run()` gates
    /// this the same honest-degrade way it gates `lib.rs`'s auto-open: a
    /// checkpoint is only ever consulted while the wizard genuinely hasn't
    /// reached `Done` yet.
    ///
    /// **Managed mode always starts `NotStarted`, regardless of any
    /// checkpoint.** `managed_flow::run` re-derives Detect through
    /// Verify/Done in one idempotent call with zero Bob-facing questions to
    /// lose — restarting it fresh on relaunch produces the IDENTICAL outcome
    /// a "resume" would, since there is nothing to reconstruct. (Managed
    /// still SAVES a checkpoint at the same two moments, for parity and
    /// forward-compatibility — see `managed_flow`'s own doc — it just never
    /// loads one here; loading one WOULD be wrong today, since
    /// `advance_wizard_runtime`'s managed arm treats any already-`Managed`
    /// runtime as a finished terminal, never re-driving it.)
    ///
    /// A checkpoint whose OWN recorded `mode` doesn't match the machine's
    /// CURRENT `is_managed()` read (e.g. the MDM domain changed since the
    /// checkpoint was saved) is never trusted — this always re-derives mode
    /// fresh, never from stale persisted state.
    fn initial_runtime(mode: WizardMode) -> WizardRuntime {
        if mode == WizardMode::Unmanaged && wizard::persistence::is_first_run() {
            if let Some(checkpoint) = wizard::persistence::load_checkpoint() {
                if checkpoint.mode == WizardMode::Unmanaged {
                    let catalog = unmanaged_flow::default_product_catalog();
                    let flow = UnmanagedFlow::resume(&checkpoint, catalog, wizard_manifest_path());
                    return WizardRuntime::Unmanaged(Box::new(flow));
                }
            }
        }
        WizardRuntime::NotStarted { mode }
    }

    fn snapshot(&self) -> WizardRuntime {
        self.inner.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    fn replace(&self, fresh: WizardRuntime) {
        *self.inner.lock().unwrap_or_else(|e| e.into_inner()) = fresh;
    }
}

impl Default for WizardIpcState {
    fn default() -> Self {
        Self::new()
    }
}

/// Where the managed profile / the guided flow's authored layers live —
/// reuses the SAME default path Settings itself writes to
/// (`settings::writer::default_manifest_path`), never a second, drifting
/// notion of "the manifest". `None` only when `$HOME` isn't set at all
/// (vanishingly rare); falls back to a relative path rather than panicking,
/// matching `get_settings_at`'s own honest-degrade discipline elsewhere in
/// this file.
fn wizard_manifest_path() -> std::path::PathBuf {
    settings::writer::default_manifest_path()
        .unwrap_or_else(|| std::path::PathBuf::from("copilot.layers.yml"))
}

/// `WizardRuntime` -> the wire DTO (S1's `dto::to_wizard_state`, the ONE
/// place a phase becomes display text) — a presentation-only projection,
/// never a second decision about mode/phase.
fn project_wizard_runtime(rt: &WizardRuntime) -> wizard::dto::WizardState {
    match rt {
        WizardRuntime::NotStarted { mode } => {
            wizard::dto::to_wizard_state(*mode, &WizardPhase::Welcome, Vec::new(), None, None)
        }
        WizardRuntime::Managed(phase) => {
            wizard::dto::to_wizard_state(WizardMode::Managed, phase, Vec::new(), None, None)
        }
        WizardRuntime::Unmanaged(flow) => wizard::dto::to_wizard_state(
            WizardMode::Unmanaged,
            flow.phase(),
            flow.steps(),
            flow.signin_state(),
            flow.signin_interval_secs(),
        ),
    }
}

/// The product-first catalog (ADR-M3-005) the `choose-products` step offers
/// — a thin passthrough to `unmanaged_flow::default_product_catalog()`
/// (S5), never a second, client-duplicated copy. Reconciles the gap
/// `wizard-main.ts` previously bridged with its own hardcoded
/// `PRODUCT_CATALOG` mirror (`.copilot/wp/15.md` S8): that hardcoded list
/// could silently drift from the real Rust catalog; this command makes the
/// UI fetch the actual one instead. Synchronous, no I/O (S5's catalog is a
/// static in-memory `Vec`, not a real `ecosystem.yml` read yet — see that
/// function's own doc), so this stays a plain (non-async, non-blocking)
/// command, same discipline as `get_wizard_state`.
#[tauri::command]
pub fn get_wizard_product_catalog() -> Vec<unmanaged_flow::ProductOption> {
    unmanaged_flow::default_product_catalog()
}

/// Snapshot pull — the wizard window calls this once on open (and again
/// after any step-driver command, though each of those already returns the
/// fresh state itself). Never mutates; always reflects whatever the last
/// `wizard_advance`/step-driver call produced.
#[tauri::command]
pub fn get_wizard_state(state: State<'_, WizardIpcState>) -> wizard::dto::WizardState {
    project_wizard_runtime(&state.snapshot())
}

/// First-run gating (S6): whether the wizard has ever reached `Done` —
/// `lib.rs`'s `.setup()` uses this to decide whether to auto-open the
/// wizard window on launch. A thin passthrough to `wizard::persistence::
/// is_first_run` (S2) — this command invents no completion logic of its
/// own.
#[tauri::command]
pub fn is_first_run() -> bool {
    wizard::persistence::is_first_run()
}

/// The one-call "move the backend forward" trigger: from `NotStarted`, kicks
/// off the managed silent run (S4) or begins the guided flow (S5); from
/// `Unmanaged` with all 3 questions answered, runs the materialize+verify
/// tail; otherwise a no-op (there's nothing further to do without another
/// step-driver call first). Always does its process-spawning/blocking work
/// OFF the async runtime's worker threads (`spawn_blocking`, mirroring
/// `timer::poll_once`'s own discipline) and — on `Done` — marks first-run
/// complete and triggers the SAME `timer::poll_once` re-poll path
/// `save_settings` uses, never a second poll implementation.
///
/// **Live managed progress (M3 QA follow-up D3).** The managed silent run
/// (`NotStarted { mode: Managed }`) is the one case this command doesn't just
/// hand off to [`advance_wizard_runtime`] and await: it calls
/// [`run_managed_flow_with_live_progress`] instead, which pushes each
/// intermediate phase `managed_flow::run` reaches straight into THIS SAME
/// `WizardIpcState` while the blocking call is still in flight — a
/// poll-based push, not a Tauri event. `wizard-main.ts` starts polling
/// `get_wizard_state` on a fixed cadence the moment it kicks off a managed
/// advance, so those concurrent polls observe the live phase name instead of
/// only the final one. This deliberately does NOT widen
/// `capabilities/wizard.json` with `core:event:allow-listen` (a real,
/// considered choice, not an oversight — see that file's own doc, which
/// still correctly says "no live push event"): reusing the ALREADY-granted
/// `get_wizard_state` poll and the existing `WizardIpcState` Mutex is the
/// lower-risk mechanism given this window's current no-event-capability
/// architecture, at the cost of a fixed poll cadence rather than a push.
#[tauri::command]
pub async fn wizard_advance(
    app: AppHandle,
    state: State<'_, WizardIpcState>,
) -> Result<wizard::dto::WizardState, String> {
    let before = state.snapshot();

    let advanced = if matches!(
        before,
        WizardRuntime::NotStarted {
            mode: WizardMode::Managed
        }
    ) {
        run_managed_flow_with_live_progress(app.clone())
            .await
            .unwrap_or(before)
    } else {
        let moved = before.clone();
        match tauri::async_runtime::spawn_blocking(move || advance_wizard_runtime(moved)).await {
            Ok(rt) => rt,
            // The blocking task itself panicked — not a flow failure, but still
            // "nothing new to report this round". Falls back to the UNCHANGED
            // prior snapshot rather than guessing at progress (never a
            // fabricated advance, mirroring `timer::poll_once`'s own "the poll
            // task itself failed to run" precedent).
            Err(_) => before,
        }
    };
    state.replace(advanced.clone());
    finish_if_done(&app, &advanced).await;
    Ok(project_wizard_runtime(&advanced))
}

/// Runs `managed_flow::run` off the async runtime's worker threads
/// (`spawn_blocking`, same discipline as [`advance_wizard_runtime`]'s own
/// call), pushing every intermediate phase into `app`'s managed
/// `WizardIpcState` AS IT ARRIVES — not just the final one — so a concurrent
/// `get_wizard_state` poll from the UI observes live progress (see
/// `wizard_advance`'s own doc for the mechanism/risk tradeoff). `None` only
/// if the blocking task itself panicked (caller falls back to the unchanged
/// prior snapshot, same as `wizard_advance`'s other branch).
async fn run_managed_flow_with_live_progress(app: AppHandle) -> Option<WizardRuntime> {
    let config = crate::wizard::managed_flow::ManagedFlowConfig::production(wizard_manifest_path());
    tauri::async_runtime::spawn_blocking(move || {
        let final_phase = crate::wizard::managed_flow::run(&config, |phase| {
            if let Some(wizard_state) = app.try_state::<WizardIpcState>() {
                wizard_state.replace(WizardRuntime::Managed(phase.clone()));
            }
        });
        WizardRuntime::Managed(final_phase)
    })
    .await
    .ok()
}

/// The actual blocking logic behind [`wizard_advance`], factored out so it's
/// directly unit-testable without a Tauri runtime — never called with a live
/// `AppHandle` itself (the `#[tauri::command]` wrapper above is the only
/// caller wired to a real app).
fn advance_wizard_runtime(rt: WizardRuntime) -> WizardRuntime {
    match rt {
        WizardRuntime::NotStarted {
            mode: WizardMode::Managed,
        } => {
            let config =
                crate::wizard::managed_flow::ManagedFlowConfig::production(wizard_manifest_path());
            // `|_| {}`: this pure/test-facing path has no live `WizardIpcState`
            // to push progress into — `wizard_advance` (the real command) uses
            // `run_managed_flow_with_live_progress` instead, which supplies a
            // real callback. See that function's own doc.
            WizardRuntime::Managed(crate::wizard::managed_flow::run(&config, |_| {}))
        }
        WizardRuntime::NotStarted {
            mode: WizardMode::Unmanaged,
        } => {
            let catalog = unmanaged_flow::default_product_catalog();
            WizardRuntime::Unmanaged(Box::new(UnmanagedFlow::begin(
                catalog,
                wizard_manifest_path(),
            )))
        }
        // The managed flow already ran start-to-finish in one call — a
        // second `wizard_advance` is an idempotent no-op, never a re-run
        // (never-destroy: nothing left to redo).
        managed @ WizardRuntime::Managed(_) => managed,
        WizardRuntime::Unmanaged(mut flow) => {
            // A no-op unless all 3 questions are answered AND the phase
            // machine has already moved on to `Materialize` (see
            // `UnmanagedFlow::ready_to_materialize`'s own doc).
            flow.materialize_and_verify();
            WizardRuntime::Unmanaged(flow)
        }
    }
}

/// Marks first-run complete + triggers the standard doctor re-poll — ONLY
/// when `rt`'s phase is genuinely `WizardPhase::Done` (which, per
/// `support::drive_verify`'s guard, is only ever reachable via a fresh
/// `Verified(Healthy)` — see `managed_flow`'s and `unmanaged_flow`'s own
/// tests). `mark_complete`'s own `NotDone` refusal (S2) is a second,
/// independent backstop against ever persisting "complete" for anything
/// else, so this check is defense in depth, not the only guard.
async fn finish_if_done(app: &AppHandle, rt: &WizardRuntime) {
    if let Some(WizardPhase::Done) = rt.phase() {
        let _ = wizard::persistence::mark_complete(&WizardPhase::Done);
        crate::timer::poll_once(app).await;
    }
}

/// Q1 (ChooseProducts, S5, ADR-M3-005) — a no-op-fast `Mutex` round-trip, no
/// blocking process work, so this stays a plain (non-`spawn_blocking`)
/// `async fn`, matching `save_settings`'s own precedent for synchronous,
/// fast Rust-side work.
#[tauri::command]
pub async fn wizard_choose_products(
    state: State<'_, WizardIpcState>,
    products: Vec<String>,
) -> Result<wizard::dto::WizardState, String> {
    let mut current = state.snapshot();
    let result = match &mut current {
        WizardRuntime::Unmanaged(flow) => flow.choose_products(products),
        _ => Err(unmanaged_flow::FlowError::OutOfOrder),
    };
    state.replace(current.clone());
    result.map_err(|e| e.to_string())?;
    Ok(project_wizard_runtime(&current))
}

/// Q2 (LayerSetup, S5) — reuses `settings::authoring`/`settings::writer`
/// (guard-gated, never-destroy) via `UnmanagedFlow::set_layers`; fast local
/// filesystem I/O only (no process spawn), so — like `save_settings` — this
/// stays a plain `async fn` rather than `spawn_blocking`.
#[tauri::command]
pub async fn wizard_set_layers(
    state: State<'_, WizardIpcState>,
    inputs: BTreeMap<String, String>,
) -> Result<wizard::dto::WizardState, String> {
    let mut current = state.snapshot();
    let result = match &mut current {
        WizardRuntime::Unmanaged(flow) => flow.set_layers(inputs),
        _ => Err(unmanaged_flow::FlowError::OutOfOrder),
    };
    state.replace(current.clone());
    result.map_err(|e| e.to_string())?;
    Ok(project_wizard_runtime(&current))
}

/// Q3 (SignIn, S5) — initiate. Spawns `cc auth --json` (S3), which can block
/// briefly on the CLI's own hard timeout — always off the async runtime's
/// worker threads (`spawn_blocking`), same discipline as `wizard_advance`.
#[tauri::command]
pub async fn wizard_begin_signin(
    state: State<'_, WizardIpcState>,
) -> Result<wizard::dto::WizardState, String> {
    let before = state.snapshot();
    let moved = before.clone();
    let (result, advanced) = match tauri::async_runtime::spawn_blocking(move || {
        let mut rt = moved;
        let result = match &mut rt {
            WizardRuntime::Unmanaged(flow) => flow.begin_signin().map(|_| ()),
            _ => Err(unmanaged_flow::FlowError::OutOfOrder),
        };
        (result, rt)
    })
    .await
    {
        Ok(pair) => pair,
        Err(_) => (Err(unmanaged_flow::FlowError::OutOfOrder), before),
    };
    state.replace(advanced.clone());
    result.map_err(|e| e.to_string())?;
    Ok(project_wizard_runtime(&advanced))
}

/// Q3 (SignIn, S5) — poll to terminal. Can block for a while (the ceremony's
/// own `expires_in` window) — always off the async runtime's worker threads,
/// same discipline as [`wizard_begin_signin`]. Any terminal status
/// (Authorized/Denied/Expired/Timeout) completes the step and advances the
/// flow — sign-in's own outcome never gates the wizard phase machine (see
/// `UnmanagedFlow::poll_signin`'s own doc).
#[tauri::command]
pub async fn wizard_poll_signin(
    state: State<'_, WizardIpcState>,
) -> Result<wizard::dto::WizardState, String> {
    let before = state.snapshot();
    let moved = before.clone();
    let (result, advanced) = match tauri::async_runtime::spawn_blocking(move || {
        let mut rt = moved;
        let result = match &mut rt {
            WizardRuntime::Unmanaged(flow) => flow.poll_signin().map(|_| ()),
            _ => Err(unmanaged_flow::FlowError::OutOfOrder),
        };
        (result, rt)
    })
    .await
    {
        Ok(pair) => pair,
        Err(_) => (Err(unmanaged_flow::FlowError::OutOfOrder), before),
    };
    state.replace(advanced.clone());
    result.map_err(|e| e.to_string())?;
    Ok(project_wizard_runtime(&advanced))
}

/// Opens (or re-focuses) the wizard window — same "defensive no-op if the
/// window is somehow absent" discipline as `open_settings_window`. Switches
/// the app to `Regular` activation policy (Dock icon + Cmd-Tab entry) for
/// the duration of setup — a first-run wizard is a foreground task, unlike
/// the Accessory-only tray/popover — `lib.rs`'s window-event listener flips
/// it back to `Accessory` when this window closes (B-L1/C5).
#[tauri::command]
pub fn open_wizard_window(app: AppHandle) {
    if let Some(window) = app.get_webview_window(WIZARD_WINDOW_LABEL) {
        #[cfg(target_os = "macos")]
        let _ = app.set_activation_policy(tauri::ActivationPolicy::Regular);
        let _ = window.show();
        let _ = window.set_focus();
    }
}

// ---------------------------------------------------------------------------
// Self-update IPC (M4/S4-S5, `.copilot/wp/24.md`)
// ---------------------------------------------------------------------------

/// Checks for a Control Tower self-update — a thin `spawn_blocking` wrapper
/// around `updater::check::check_for_update()`, the pure (well, network/
/// filesystem-touching but stateless) transport function. `spawn_blocking`
/// (not a direct `await`) matters here: `check_for_update()`'s production
/// `HttpFetcher` uses `reqwest::blocking`, which panics if invoked from
/// inside an already-running async runtime — the SAME reason `cli::spawn`'s
/// doctor invocation runs on its own thread rather than as a `tokio::
/// process::Command`. A `spawn_blocking` join failure (extremely rare —
/// the closure itself doesn't panic under any normal input) falls back to
/// the same honest `Error` shape a genuine fetch failure produces, never a
/// silently-stale snapshot.
#[tauri::command]
pub async fn check_for_update() -> crate::updater::dto::UpdateState {
    tauri::async_runtime::spawn_blocking(crate::updater::check::check_for_update)
        .await
        .unwrap_or_else(|_| update_spawn_join_error_state())
}

/// Applies a Control Tower self-update — same `spawn_blocking` shape as
/// [`check_for_update`], wrapping `updater::check::apply_update()` (fetch,
/// verify, stage into `updater::watchdog::StagedLayout`, offline-staple-gate
/// — see that function's own doc). `apply_update()` itself now also
/// completes the promote-or-rollback DECISION synchronously (M4 gap-closure,
/// S11): it launches the staged bundle's own `--self-test` process and hands
/// the observed heartbeat to `updater::watchdog::run_self_test` (already
/// landed, never re-implemented in this command) — so the `UpdateState` this
/// command returns is a direct, unedited pass-through of that real decision
/// (`Ready` on promote, `RolledBack` on rollback), never a second,
/// app-computed verdict about whether the staged bundle is trustworthy
/// (invariant #1).
#[tauri::command]
pub async fn apply_update() -> crate::updater::dto::UpdateState {
    tauri::async_runtime::spawn_blocking(crate::updater::check::apply_update)
        .await
        .unwrap_or_else(|_| update_spawn_join_error_state())
}

/// Shared by both self-update commands' exceptional "the blocking task
/// itself failed to run" path — mirrors `unreadable_io_error`'s identical
/// role for the doctor poll task.
fn update_spawn_join_error_state() -> crate::updater::dto::UpdateState {
    crate::updater::dto::UpdateState {
        status: crate::updater::dto::UpdateStatus::Error,
        available_version: None,
        current_version: env!("CARGO_PKG_VERSION").to_string(),
        message: Some("Something went wrong checking for updates — try again later.".to_string()),
    }
}

#[cfg(test)]
mod update_ipc_tests {
    use super::*;
    use crate::updater::check::test_env::ENV_LOCK;
    use crate::updater::dto::UpdateStatus;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn scratch_dir(name: &str) -> std::path::PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("ct-update-ipc-test-{name}-{pid}-{n}"));
        std::fs::create_dir_all(&dir).expect("create scratch dir");
        dir
    }

    fn fixtures_dir() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("fixtures")
            .join("updater")
    }

    /// Points `CT_UPDATE_FEED` at a fresh directory carrying a copy of the
    /// SAME dev-signed fixture pair `updater::check`'s own tests use, so the
    /// REAL `check_for_update()`/`apply_update()` IPC commands (not the
    /// `_with`-suffixed testable cores) can be exercised end to end, over
    /// this crate's real async command surface, with zero real network.
    fn seed_feed_dir(dir: &std::path::Path) {
        std::fs::copy(
            fixtures_dir().join("valid-manifest.json"),
            dir.join("latest.json"),
        )
        .unwrap();
        std::fs::copy(
            fixtures_dir().join("valid-manifest.json.minisig"),
            dir.join("latest.json.minisig"),
        )
        .unwrap();
        std::fs::copy(
            fixtures_dir().join("artifact.bin"),
            dir.join("artifact.bin"),
        )
        .unwrap();
    }

    /// The self-update IPC commands take no `State`/`AppHandle` — same
    /// shape `save_settings_at`'s own test helper documents:
    /// `tauri::async_runtime::block_on`'s lazily-initialized default
    /// runtime is enough to drive them, no live Tauri app required.
    #[test]
    fn check_for_update_command_reports_available_via_the_dev_feed_override() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let feed_dir = scratch_dir("check-cmd");
        seed_feed_dir(&feed_dir);

        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::set_var(crate::updater::check::DEV_FEED_OVERRIDE_ENV, &feed_dir) };
        let state = tauri::async_runtime::block_on(check_for_update());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(crate::updater::check::DEV_FEED_OVERRIDE_ENV) };

        assert_eq!(state.status, UpdateStatus::Available);
        assert_eq!(state.available_version.as_deref(), Some("9.9.9"));
        assert_eq!(state.current_version, env!("CARGO_PKG_VERSION"));

        std::fs::remove_dir_all(&feed_dir).ok();
    }

    #[test]
    fn check_for_update_command_reports_error_when_the_feed_is_unreachable() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(
                crate::updater::check::DEV_FEED_OVERRIDE_ENV,
                "/nonexistent/definitely-not-a-real-feed-dir",
            )
        };
        let state = tauri::async_runtime::block_on(check_for_update());
        // SAFETY: serialized by ENV_LOCK.
        unsafe { std::env::remove_var(crate::updater::check::DEV_FEED_OVERRIDE_ENV) };

        assert_eq!(state.status, UpdateStatus::Error);
        assert!(state.message.is_some());
    }

    // NOTE: `apply_update()` (the bare, zero-argument production command) is
    // deliberately NOT exercised here — it stages into `updater::check::
    // default_layout_root()`, which resolves to the REAL `$HOME/Library/
    // Application Support/…` on whatever machine runs `cargo test`, and this
    // crate's convention (`settings::writer`'s and `updater::heartbeat`'s own
    // `default_*_path`/`default_*_root` tests) is to only ever assert the
    // STRUCTURE of a real production path, never actually write through it.
    // The full fetch -> verify -> stage -> fail-closed-staple pipeline this
    // command wraps IS exercised end to end, via the real `verify::
    // verify_staple` and a real `CT_UPDATE_FEED` override, by `updater::
    // check`'s own `apply_update_via_the_dev_feed_override_fails_closed_
    // on_the_real_offline_staple_check` test — which injects an explicit
    // scratch `StagedLayout` root via `apply_update_at` instead. This
    // command is a thin, identically-shaped `spawn_blocking` wrapper around
    // `updater::check::apply_update` — the SAME wrapper shape `check_for_
    // update`'s own command tests above already prove works.

    #[test]
    fn update_spawn_join_error_state_carries_a_plain_message_and_the_real_current_version() {
        let state = update_spawn_join_error_state();
        assert_eq!(state.status, UpdateStatus::Error);
        assert_eq!(state.current_version, env!("CARGO_PKG_VERSION"));
        assert!(state.message.is_some());
    }
}

#[cfg(test)]
mod wizard_ipc_tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;
    use crate::wizard::state::HoldingReason;
    use std::io::Write as _;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, Ordering};

    static DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir() -> PathBuf {
        let n = DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ct-wizard-ipc-test-{}-{:?}-{n}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp test dir");
        dir
    }

    fn fixture_path(rel: &str) -> String {
        format!("{}/fixtures/{rel}", env!("CARGO_MANIFEST_DIR"))
    }

    fn write_mock_cc(dir: &Path) -> PathBuf {
        let script = dir.join("mock-cc-wizard-ipc");
        let mut f = std::fs::File::create(&script).unwrap();
        writeln!(f, "#!/bin/sh").unwrap();
        writeln!(f, "verb=\"$1\"").unwrap();
        writeln!(f, "case \"$verb\" in").unwrap();
        writeln!(f, "  update)").unwrap();
        writeln!(f, "    echo '{{\"phase\": \"Setting up Claude…\"}}'").unwrap();
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

    /// A mock `cc` implementing JUST `config set/get --json` (persistence's
    /// own dotted JSON store) — same shape `wizard::persistence`'s and
    /// `wizard::managed_flow`'s own checkpoint tests use, needed here to
    /// drive `WizardIpcState::initial_runtime`'s resume path end to end
    /// through the real `persistence::is_first_run`/`load_checkpoint` calls.
    fn write_mock_cc_config(dir: &Path) -> PathBuf {
        let script = dir.join("mock-cc-wizard-ipc-config");
        let mut f = std::fs::File::create(&script).unwrap();
        writeln!(f, "#!/usr/bin/env python3").unwrap();
        writeln!(f, "import json, os, sys").unwrap();
        writeln!(f, "config_path = os.environ['MOCK_CC_CONFIG_PATH']").unwrap();
        writeln!(f, "try:").unwrap();
        writeln!(f, "    data = json.load(open(config_path))").unwrap();
        writeln!(f, "except Exception:").unwrap();
        writeln!(f, "    data = {{}}").unwrap();
        writeln!(f, "action, key = sys.argv[2], sys.argv[3]").unwrap();
        writeln!(f, "if action == 'set':").unwrap();
        writeln!(f, "    data[key] = sys.argv[4]").unwrap();
        writeln!(f, "    json.dump(data, open(config_path, 'w'))").unwrap();
        writeln!(f, "elif action == 'get':").unwrap();
        writeln!(
            f,
            "    print(json.dumps({{'key': key, 'value': data.get(key)}}))"
        )
        .unwrap();
        writeln!(f, "sys.exit(0)").unwrap();
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

    fn with_env<R>(cli_path: Option<&Path>, doctor_body: Option<&str>, f: impl FnOnce() -> R) -> R {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            match cli_path {
                Some(p) => std::env::set_var(DEV_OVERRIDE_ENV, p),
                None => std::env::remove_var(DEV_OVERRIDE_ENV),
            }
            match doctor_body {
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

    #[test]
    fn not_started_projects_to_welcome_never_fabricating_progress() {
        let rt = WizardRuntime::NotStarted {
            mode: WizardMode::Unmanaged,
        };
        let dto = project_wizard_runtime(&rt);
        assert_eq!(dto.phase, "welcome");
        assert!(!dto.complete);
        assert_eq!(dto.mode, WizardMode::Unmanaged);
    }

    #[test]
    fn advance_from_not_started_managed_runs_the_managed_flow_to_a_terminal_phase() {
        let dir = temp_dir();
        let profile_path = dir.join("copilot.layers.yml");
        std::fs::copy(
            fixture_path("settings/valid-multi-layer.yml"),
            &profile_path,
        )
        .unwrap();
        let mock_cc = write_mock_cc(&dir);
        let healthy = fixture_path("corpus/healthy-clean-fleet.json");

        // `advance_wizard_runtime` reads the manifest path from
        // `wizard_manifest_path()` (HOME-derived), not a test-injected path —
        // this test only exercises `managed_flow::run` directly through the
        // SAME dispatcher `wizard_advance` uses, confirming the dispatch
        // itself (not a second copy of managed_flow's own already-tested
        // profile/materialize/verify logic).
        let config =
            crate::wizard::managed_flow::ManagedFlowConfig::production(profile_path.clone());
        let phase = with_env(Some(&mock_cc), Some(&healthy), || {
            crate::wizard::managed_flow::run(&config, |_| {})
        });
        let advanced = advance_wizard_runtime(WizardRuntime::Managed(phase));
        assert!(matches!(
            advanced,
            WizardRuntime::Managed(WizardPhase::Done)
        ));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn advance_from_not_started_unmanaged_begins_the_guided_flow_at_question() {
        let advanced = advance_wizard_runtime(WizardRuntime::NotStarted {
            mode: WizardMode::Unmanaged,
        });
        match advanced {
            WizardRuntime::Unmanaged(flow) => {
                assert_eq!(flow.phase(), &WizardPhase::Question);
                assert!(flow.questions_remaining() <= 3);
            }
            other => panic!("expected Unmanaged, got a variant that isn't it: {other:?}"),
        }
    }

    #[test]
    fn advance_is_a_no_op_on_an_already_terminal_managed_run() {
        let terminal =
            WizardRuntime::Managed(WizardPhase::Holding(HoldingReason::WaitingForNetwork));
        let advanced = advance_wizard_runtime(terminal.clone());
        assert!(matches!(
            advanced,
            WizardRuntime::Managed(WizardPhase::Holding(HoldingReason::WaitingForNetwork))
        ));
    }

    #[test]
    fn choose_products_out_of_order_before_the_guided_flow_exists_is_refused() {
        let state = WizardIpcState::new();
        // Force unmanaged so the assertion is deterministic regardless of
        // this dev machine's real forced-domain state.
        state.replace(WizardRuntime::NotStarted {
            mode: WizardMode::Unmanaged,
        });
        let mut current = state.snapshot();
        let result = match &mut current {
            WizardRuntime::Unmanaged(flow) => flow.choose_products(vec!["claude".to_string()]),
            _ => Err(unmanaged_flow::FlowError::OutOfOrder),
        };
        assert_eq!(result, Err(unmanaged_flow::FlowError::OutOfOrder));
    }

    #[test]
    fn wizard_ipc_state_round_trips_through_replace_and_snapshot() {
        let state = WizardIpcState::new();
        state.replace(WizardRuntime::Managed(WizardPhase::Done));
        let dto = project_wizard_runtime(&state.snapshot());
        assert_eq!(dto.phase, "done");
        assert!(dto.complete);
    }

    #[test]
    fn get_wizard_product_catalog_returns_the_real_unmanaged_flow_catalog() {
        // A thin passthrough — proves this command doesn't invent a second,
        // client-facing catalog that could drift from `unmanaged_flow::
        // default_product_catalog()` (the same catalog `UnmanagedFlow::begin`
        // itself is seeded with in `advance_wizard_runtime`).
        let catalog = get_wizard_product_catalog();
        assert_eq!(catalog, unmanaged_flow::default_product_catalog());
    }

    // -- M3 QA follow-up D2: WizardIpcState::initial_runtime resume ---------

    #[test]
    fn initial_runtime_resumes_an_unmanaged_materialize_checkpoint_never_restarting_at_choose_products(
    ) {
        let dir = temp_dir();
        let mock_cc = write_mock_cc_config(&dir);
        let config_path = dir.join("cc-config.json");

        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, &mock_cc);
            std::env::set_var("MOCK_CC_CONFIG_PATH", &config_path);
        }

        // Simulate a prior, interrupted session that had already answered
        // all 3 questions and checkpointed right at Materialize's first
        // entry.
        let mut answers = std::collections::BTreeMap::new();
        answers.insert("products".to_string(), "claude,codex".to_string());
        let checkpoint = crate::wizard::persistence::WizardCheckpoint::for_phase(
            WizardMode::Unmanaged,
            &crate::wizard::state::WizardPhase::Materialize {
                phase_name: String::new(),
            },
            answers,
        )
        .expect("Materialize's first entry must be checkpointable");
        crate::wizard::persistence::save_checkpoint(&checkpoint).expect("save should succeed");

        let runtime = WizardIpcState::initial_runtime(WizardMode::Unmanaged);

        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
        }
        drop(_guard);

        match runtime {
            WizardRuntime::Unmanaged(flow) => {
                assert!(
                    flow.ready_to_materialize(),
                    "a resumed session must land ready to materialize, never back at \
                     ChooseProducts/NotStarted"
                );
                assert!(flow.steps().iter().all(|s| s.done));
            }
            other => panic!("expected a resumed Unmanaged runtime, got {other:?}"),
        }

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn initial_runtime_ignores_a_checkpoint_for_managed_mode_always_starting_not_started() {
        let dir = temp_dir();
        let mock_cc = write_mock_cc_config(&dir);
        let config_path = dir.join("cc-config.json");

        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, &mock_cc);
            std::env::set_var("MOCK_CC_CONFIG_PATH", &config_path);
        }

        // Even a checkpoint recorded as Managed must never seed a resumed
        // Managed runtime — see `initial_runtime`'s own doc for why.
        let checkpoint = crate::wizard::persistence::WizardCheckpoint::for_phase(
            WizardMode::Managed,
            &crate::wizard::state::WizardPhase::Holding(HoldingReason::WaitingForNetwork),
            std::collections::BTreeMap::new(),
        )
        .expect("Holding must be checkpointable");
        crate::wizard::persistence::save_checkpoint(&checkpoint).expect("save should succeed");

        let runtime = WizardIpcState::initial_runtime(WizardMode::Managed);

        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
        }
        drop(_guard);

        assert!(
            matches!(
                runtime,
                WizardRuntime::NotStarted {
                    mode: WizardMode::Managed
                }
            ),
            "managed mode must always start NotStarted, regardless of any checkpoint"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn initial_runtime_ignores_a_stale_mode_mismatched_checkpoint() {
        let dir = temp_dir();
        let mock_cc = write_mock_cc_config(&dir);
        let config_path = dir.join("cc-config.json");

        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, &mock_cc);
            std::env::set_var("MOCK_CC_CONFIG_PATH", &config_path);
        }

        // A checkpoint saved while the machine WAS managed, now read back on
        // a machine that currently reads unmanaged — never trusted over the
        // fresh mode.
        let checkpoint = crate::wizard::persistence::WizardCheckpoint::for_phase(
            WizardMode::Managed,
            &crate::wizard::state::WizardPhase::Materialize {
                phase_name: String::new(),
            },
            std::collections::BTreeMap::new(),
        )
        .expect("Materialize must be checkpointable");
        crate::wizard::persistence::save_checkpoint(&checkpoint).expect("save should succeed");

        let runtime = WizardIpcState::initial_runtime(WizardMode::Unmanaged);

        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
        }
        drop(_guard);

        assert!(
            matches!(
                runtime,
                WizardRuntime::NotStarted {
                    mode: WizardMode::Unmanaged
                }
            ),
            "a checkpoint recorded under a different mode must never be trusted"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }
}
