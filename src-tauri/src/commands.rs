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
/// real I/O/schema failure — `cli_unreadable_reason: None` is only reachable
/// from here, never from `model::state::parse_doctor_body`, which always
/// picks a concrete reason). Deliberately NOT `ClientState::Ok` / any
/// `CliStatus` — this function does not go through the parse boundary at all
/// (there is no CLI body yet to parse), so it must not fabricate one; it is
/// an honest "haven't checked yet", never Healthy, never a guessed status.
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
