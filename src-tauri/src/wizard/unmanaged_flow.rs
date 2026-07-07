//! S5 — the unmanaged guided first-run (`.copilot/wp/15.md` §2 S5), the
//! ≤3-question path: **ChooseProducts** (product-first, ADR-M3-005 — the
//! HANDOFF fix that REPLACES the host-framed "Claude/Codex/Both" step) ->
//! **LayerSetup** (reuse `settings::authoring` to write the chosen products'
//! personal-tier repo URLs — never-destroy, guard-gated, the SAME pipeline
//! Settings itself uses) -> **SignIn** (S3's device-flow seam) -> Materialize
//! -> Verify -> Teach -> Done (auto-acknowledged, per `support::drive_verify`,
//! shared with `managed_flow`).
//!
//! **A stateful flow, unlike `managed_flow::run`.** The managed silent path
//! has no user interaction, so it runs start-to-finish in one blocking call.
//! This guided path is answered incrementally over several separate IPC
//! round-trips (S6), so [`UnmanagedFlow`] is a small state machine a caller
//! holds (Tauri-managed state) and drives one step-driver method at a time —
//! never a single function that blocks waiting on a human.
//!
//! **≤3 questions, product-first, narrow-not-widen.** [`UnmanagedFlow::begin`]
//! always enters `WizardPhase::Question` (LayerSetup + SignIn are
//! unconditionally required for an unmanaged machine), but auto-answers
//! ChooseProducts with 0 Bob-facing interaction when the supplied catalog
//! offers exactly one product — keeping the guided flow's total at 3
//! questions maximum, 2 in that single-product case.
//! [`UnmanagedFlow::choose_products`] refuses any selected id absent from the
//! catalog entirely (never widens beyond what the ecosystem already grants).
//!
//! **Sign-in's own outcome never gates the phase machine (parse-never-
//! compute).** [`UnmanagedFlow::poll_signin`] advances the flow on ANY
//! terminal status — Authorized, Denied, Expired, or Timeout alike. A failed
//! sign-in still proceeds to Materialize/Verify, where the next real `cc
//! doctor` poll independently reports `signed-out` and holds there on its
//! own honest terms, reusing the EXISTING doctor `signed-out` render (see
//! `fixtures/wizard/README.md`'s "all three failure variants converge on the
//! same render target") — this file never invents a second, wizard-specific
//! severity for a sign-in failure.
//!
//! ## Resumability (M3 QA follow-up D2)
//!
//! [`UnmanagedFlow::poll_signin`] and [`UnmanagedFlow::materialize_and_verify`]
//! both call `persistence::checkpoint_phase_if_resumable` right after a phase
//! change — the SAME two S1-designed moments `managed_flow::run` checkpoints
//! (Materialize's first entry; any `Holding` terminal). Since ALL 3 steps
//! (ChooseProducts/LayerSetup/SignIn) must already be done before this flow
//! can reach EITHER of those moments, [`UnmanagedFlow::resume`] reconstructs
//! both checkpoint variants to the identical "ready to materialize" state —
//! driven through the SAME legal `(Question, AllQuestionsAnswered) ->
//! Materialize` transition `poll_signin` itself uses the first time, never a
//! hand-built phase. `WizardIpcState::new()` (`commands.rs`) is the one
//! caller that loads a checkpoint and calls `resume` — see that function's
//! own doc for why managed mode never does the same.

use std::collections::BTreeMap;
use std::path::PathBuf;

use crate::settings::dto::{LayerInput, Tier};
use crate::wizard::dto::{SigninState, SigninStatus, WizardStep};
use crate::wizard::materialize;
use crate::wizard::persistence::{self, WizardCheckpoint};
use crate::wizard::signin::{self, SigninSession};
use crate::wizard::state::{StepKind, WizardEvent, WizardMode, WizardPhase};
use crate::wizard::support::{drive_verify, must_transition};

/// One product the ecosystem grants Bob a choice over, per ADR-M3-005
/// (product-first, never host-framed) — config-driven, never a hardcoded
/// Claude/Codex/Both toggle. Not part of the frozen `dto::WizardState` wire
/// shape S1 already froze (`WizardStep` stays exactly `{id, kind, prompt,
/// done}`); this is S5's own IPC value, round-tripped by a dedicated wizard
/// command (S6) alongside it.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProductOption {
    pub id: String,
    pub label: String,
    /// Whether the ecosystem already grants this product by default — the
    /// wizard may only NARROW this set (uncheck a pre-checked product),
    /// never WIDEN it to an id absent from the catalog entirely (see
    /// [`UnmanagedFlow::choose_products`]'s own doc).
    pub pre_checked: bool,
}

/// The production default catalog — the initial declared 4-product set
/// (Knowledge/CLI/Claude/Codex; matches `render::derive::KNOWN_PRODUCTS`'s
/// labels and `fixtures/wizard/products.sample.json`'s sample, the SAME
/// ratified product model, not a coincidence). This crate has no real
/// ecosystem.yml reader yet (that integration is later, owner-batched work)
/// — until then this is the honest, documented default every unmanaged
/// first run starts from. [`UnmanagedFlow::begin`] takes the catalog as a
/// parameter, never a hardcoded match, so a test (or a future real catalog)
/// can supply any other `Vec<ProductOption>`, including a single-product one
/// to exercise the 0-question ChooseProducts sub-case.
pub fn default_product_catalog() -> Vec<ProductOption> {
    vec![
        ProductOption {
            id: "knowledge".to_string(),
            label: "Knowledge Copilot".to_string(),
            pre_checked: true,
        },
        ProductOption {
            id: "cli".to_string(),
            label: "CLI Copilot".to_string(),
            pre_checked: true,
        },
        ProductOption {
            id: "claude".to_string(),
            label: "Claude Copilot".to_string(),
            pre_checked: true,
        },
        ProductOption {
            id: "codex".to_string(),
            label: "Codex Copilot".to_string(),
            pre_checked: false,
        },
    ]
}

/// Plain-language, never-raw-jargon errors from a step-driver call — no
/// variant here ever carries a raw io/serde/process/OAuth string; the one
/// variant that CAN wrap external detail (`LayerErrors`) reuses
/// `settings::dto::FieldError`, which is already held to that same
/// discipline (see `settings::validate`'s module doc).
#[derive(Debug, Clone, PartialEq)]
pub enum FlowError {
    /// The step this method belongs to already completed.
    StepAlreadyDone,
    /// A step-driver was called before an earlier required step finished
    /// (e.g. `set_layers` before `choose_products`) — a defensive fail-
    /// closed refusal, never a silent skip-ahead.
    OutOfOrder,
    /// `choose_products` was asked to select a product id the catalog
    /// doesn't even offer — narrow-not-widen (ADR-M3-005).
    ProductNotOffered(String),
    /// The layer-setup write (`settings::authoring` + `settings::writer`)
    /// refused — the SAME plain-language `FieldError`s Settings itself would
    /// show.
    LayerErrors(Vec<crate::settings::dto::FieldError>),
    /// The sign-in seam (S3) couldn't be reached, or returned something this
    /// crate couldn't trust — relayed verbatim (already plain language).
    Signin(signin::SigninError),
}

impl std::fmt::Display for FlowError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FlowError::StepAlreadyDone => write!(f, "That step is already done."),
            FlowError::OutOfOrder => write!(f, "Let's finish the earlier step first."),
            FlowError::ProductNotOffered(id) => write!(
                f,
                "{id} isn't one of the copilots your ecosystem offers, so it can't be added here."
            ),
            FlowError::LayerErrors(errors) => {
                let messages: Vec<&str> = errors.iter().map(|e| e.message.as_str()).collect();
                write!(f, "{}", messages.join(" "))
            }
            FlowError::Signin(e) => write!(f, "{e}"),
        }
    }
}

/// The one non-secret answer this flow's checkpoint carries — Q1's product
/// selection, comma-joined (plain product ids, e.g. `"claude,codex"`, never
/// a repo URL or credential; the repo URLs themselves are already durably on
/// disk via `set_layers`'s own never-destroy write by the time either
/// checkpoint moment is reached, so they don't need to be re-carried here).
const CHECKPOINT_PRODUCTS_KEY: &str = "products";

fn layer_write_error(message: String) -> FlowError {
    FlowError::LayerErrors(vec![crate::settings::dto::FieldError {
        layer_id: None,
        field: "manifest".to_string(),
        message,
    }])
}

/// The ≤3-question guided flow's own state — see module doc.
#[derive(Debug, Clone)]
pub struct UnmanagedFlow {
    phase: WizardPhase,
    catalog: Vec<ProductOption>,
    selected_products: Vec<String>,
    /// `[ChooseProducts, LayerSetup, SignIn]` done-flags, in that fixed
    /// order — the same order `steps()` projects them in.
    steps_done: [bool; 3],
    manifest_path: PathBuf,
    pending_signin: Option<SigninSession>,
    last_signin_state: Option<SigninState>,
}

impl UnmanagedFlow {
    /// Starts the guided first-run: Welcome -> Detect -> Question. Always
    /// `DetectedUnmanagedWithQuestions` (never the state machine's
    /// `DetectedUnmanagedNoQuestions` 0-question sub-case) — LayerSetup and
    /// SignIn are unconditionally required for an unmanaged machine. When
    /// `catalog` offers exactly one product, ChooseProducts auto-selects it
    /// and marks itself done immediately (0 questions for that ONE step),
    /// per the module doc's ≤3-question bound.
    pub fn begin(catalog: Vec<ProductOption>, manifest_path: PathBuf) -> Self {
        let phase = must_transition(&WizardPhase::Welcome, WizardEvent::Begin); // Detect
        let phase = must_transition(&phase, WizardEvent::DetectedUnmanagedWithQuestions); // Question

        let ambiguous = catalog.len() > 1;
        let mut selected_products: Vec<String> = catalog
            .iter()
            .filter(|p| p.pre_checked)
            .map(|p| p.id.clone())
            .collect();
        let mut steps_done = [false, false, false];
        if !ambiguous {
            if selected_products.is_empty() {
                if let Some(first) = catalog.first() {
                    selected_products.push(first.id.clone());
                }
            }
            steps_done[0] = true; // ChooseProducts auto-answered, 0 questions
        }

        Self {
            phase,
            catalog,
            selected_products,
            steps_done,
            manifest_path,
            pending_signin: None,
            last_signin_state: None,
        }
    }

    /// Reconstructs a guided flow from a persisted checkpoint (S2's
    /// `persistence::WizardCheckpoint`) — see the module doc's "Resumability"
    /// section for why both checkpoint variants land at the same "ready to
    /// materialize" state, and why that's driven through the real
    /// `state::transition` table rather than hand-built. `catalog`/
    /// `manifest_path` are supplied fresh by the caller (S6), same as
    /// [`begin`](Self::begin) — a checkpoint never freezes the catalog
    /// itself, only which steps were already answered. Sign-in is never
    /// reconstructed in-flight (no secret, and no ceremony, ever survives a
    /// relaunch — both checkpoint moments only occur after sign-in already
    /// reached a terminal status).
    pub fn resume(
        checkpoint: &WizardCheckpoint,
        catalog: Vec<ProductOption>,
        manifest_path: PathBuf,
    ) -> Self {
        let selected_products = checkpoint
            .answers
            .get(CHECKPOINT_PRODUCTS_KEY)
            .map(|joined| {
                joined
                    .split(',')
                    .filter(|id| !id.is_empty())
                    .map(str::to_string)
                    .collect()
            })
            .unwrap_or_default();

        let mut flow = Self {
            phase: WizardPhase::Question,
            catalog,
            selected_products,
            // Both checkpointable moments (Materialize's first entry, any
            // Holding terminal) are only ever reached after all 3 steps are
            // done — see the module doc.
            steps_done: [true, true, true],
            manifest_path,
            pending_signin: None,
            last_signin_state: None,
        };
        // Legal (Question, AllQuestionsAnswered) -> Materialize — the exact
        // transition `poll_signin` drove the first time; never a hand-built
        // phase.
        flow.advance_question_phase();
        flow
    }

    pub fn phase(&self) -> &WizardPhase {
        &self.phase
    }

    /// How many of the 3 canonical steps still need a real Bob answer — the
    /// ≤3-question bound this flow's own acceptance criterion measures.
    pub fn questions_remaining(&self) -> usize {
        self.steps_done.iter().filter(|d| !**d).count()
    }

    /// The DTO-shaped step list (S1's frozen `WizardStep` — `{id, kind,
    /// prompt, done}`), fixed order `[ChooseProducts, LayerSetup, SignIn]`.
    pub fn steps(&self) -> Vec<WizardStep> {
        vec![
            WizardStep {
                id: "choose-products".to_string(),
                kind: StepKind::ChooseProducts,
                prompt: "Which copilots do you want set up?".to_string(),
                done: self.steps_done[0],
            },
            WizardStep {
                id: "layer-setup".to_string(),
                kind: StepKind::LayerSetup,
                prompt: "Where should we sync your personal layer from?".to_string(),
                done: self.steps_done[1],
            },
            WizardStep {
                id: "sign-in".to_string(),
                kind: StepKind::SignIn,
                prompt: "Sign in to keep everything in sync.".to_string(),
                done: self.steps_done[2],
            },
        ]
    }

    /// The last known sign-in render state (ceremony while pending, terminal
    /// once resolved) — `None` before `begin_signin` has ever been called.
    pub fn signin_state(&self) -> Option<SigninState> {
        self.pending_signin
            .as_ref()
            .map(|s| s.state.clone())
            .or_else(|| self.last_signin_state.clone())
    }

    /// The in-flight ceremony's own poll cadence, in seconds — `None` once
    /// the sign-in step has never started, or has already resolved to a
    /// terminal status (there is nothing left to poll). Surfaced so a caller
    /// (S6's IPC layer) can honestly tell the UI how often to call
    /// `wizard_poll_signin`, instead of the UI guessing a cadence
    /// (`.copilot/wp/15.md` S8's contract-gap fix).
    pub fn signin_interval_secs(&self) -> Option<u64> {
        self.pending_signin.as_ref().map(|s| s.interval_secs())
    }

    /// Q1 (ChooseProducts, product-first — ADR-M3-005): narrow-not-widen —
    /// every id in `selected` must already be present in the catalog handed
    /// to `begin` (an id the ecosystem doesn't offer at all is refused,
    /// never silently dropped and never silently widened in).
    pub fn choose_products(&mut self, selected: Vec<String>) -> Result<(), FlowError> {
        if self.steps_done[0] {
            return Err(FlowError::StepAlreadyDone);
        }
        for id in &selected {
            if !self.catalog.iter().any(|p| &p.id == id) {
                return Err(FlowError::ProductNotOffered(id.clone()));
            }
        }
        self.selected_products = selected;
        self.steps_done[0] = true;
        self.advance_question_phase();
        Ok(())
    }

    /// Q2 (LayerSetup): `repo_urls` maps product id -> repo URL, one entry
    /// per product selected in Q1. Reuses `settings::authoring::
    /// author_manifest` (the SAME guard + S1 validator + never-destroy merge
    /// Settings itself uses) then `settings::writer::write_manifest` (the
    /// SAME atomic, never-destroy writer) — this method invents no manifest
    /// logic of its own; every product is authored at `Tier::Personal` (an
    /// unmanaged/solo first run has no org/dept tier to author into).
    pub fn set_layers(&mut self, repo_urls: BTreeMap<String, String>) -> Result<(), FlowError> {
        if !self.steps_done[0] {
            return Err(FlowError::OutOfOrder);
        }
        if self.steps_done[1] {
            return Err(FlowError::StepAlreadyDone);
        }

        let inputs: Vec<LayerInput> = self
            .selected_products
            .iter()
            .map(|product| LayerInput {
                product: product.clone(),
                tier: Tier::Personal,
                repo_url: repo_urls.get(product).cloned().unwrap_or_default(),
            })
            .collect();

        let existing = crate::settings::writer::read_existing(&self.manifest_path)
            .map_err(|e| layer_write_error(e.to_string()))?;

        let authored = crate::settings::authoring::author_manifest(&inputs, &existing)
            .map_err(FlowError::LayerErrors)?;

        crate::settings::writer::write_manifest(&self.manifest_path, &authored)
            .map_err(|e| layer_write_error(e.to_string()))?;

        self.steps_done[1] = true;
        self.advance_question_phase();
        Ok(())
    }

    /// Q3 (SignIn) — initiate. Returns the render-safe ceremony (`user_code`/
    /// `verification_uri`) a caller (S6) hands straight to the wire; holds
    /// no secret (S3's own discipline, unchanged here).
    pub fn begin_signin(&mut self) -> Result<SigninState, FlowError> {
        if !self.steps_done[1] {
            return Err(FlowError::OutOfOrder);
        }
        let session = signin::begin_signin().map_err(FlowError::Signin)?;
        let state = session.state.clone();
        self.last_signin_state = Some(state.clone());
        self.pending_signin = Some(session);
        Ok(state)
    }

    /// Q3 (SignIn) — poll to terminal. **Any** terminal status (Authorized/
    /// Denied/Expired/Timeout) completes this step and advances the flow —
    /// see the module doc's "sign-in's own outcome never gates the phase
    /// machine".
    pub fn poll_signin(&mut self) -> Result<SigninState, FlowError> {
        let session = self.pending_signin.as_ref().ok_or(FlowError::OutOfOrder)?;
        let state = signin::poll_signin(session).map_err(FlowError::Signin)?;
        self.last_signin_state = Some(state.clone());
        if state.status != SigninStatus::Pending {
            self.steps_done[2] = true;
            self.pending_signin = None;
            self.advance_question_phase();
        }
        Ok(state)
    }

    fn advance_question_phase(&mut self) {
        if matches!(self.phase, WizardPhase::Question) {
            let event = if self.steps_done.iter().all(|d| *d) {
                WizardEvent::AllQuestionsAnswered
            } else {
                WizardEvent::QuestionAnswered
            };
            self.phase = must_transition(&self.phase, event);
            self.checkpoint_if_resumable();
        }
    }

    /// The non-secret answers this flow's checkpoint carries — see
    /// [`CHECKPOINT_PRODUCTS_KEY`]'s own doc.
    fn checkpoint_answers(&self) -> BTreeMap<String, String> {
        let mut answers = BTreeMap::new();
        answers.insert(
            CHECKPOINT_PRODUCTS_KEY.to_string(),
            self.selected_products.join(","),
        );
        answers
    }

    /// Saves a checkpoint for `self.phase` right now, or does nothing at all
    /// if `self.phase` isn't one of the two S1-designed checkpointable
    /// moments (`persistence::checkpoint_phase_if_resumable`'s own contract)
    /// — see the module doc's "Resumability" section for the call sites.
    fn checkpoint_if_resumable(&self) {
        persistence::checkpoint_phase_if_resumable(
            WizardMode::Unmanaged,
            &self.phase,
            self.checkpoint_answers(),
        );
    }

    /// `true` once all 3 steps are done and the phase machine has moved on
    /// to `Materialize` — the signal a caller (S6's `wizard_advance`) uses to
    /// decide whether it's time to run materialize+verify.
    pub fn ready_to_materialize(&self) -> bool {
        matches!(self.phase, WizardPhase::Materialize { .. }) && self.steps_done.iter().all(|d| *d)
    }

    /// Runs the materialize+verify tail exactly once all 3 questions are
    /// answered — the same shape as `managed_flow::run`'s tail (shared via
    /// `support::drive_verify`); a no-op if called before
    /// `ready_to_materialize()`.
    pub fn materialize_and_verify(&mut self) {
        if !self.ready_to_materialize() {
            return;
        }
        let _ = materialize::run_materialize(|name| {
            self.phase = must_transition(&self.phase, WizardEvent::PhaseNamed(name));
        });
        self.phase = must_transition(&self.phase, WizardEvent::MaterializeComplete);

        let render = crate::cli::run_doctor();
        self.phase = drive_verify(self.phase.clone(), &render);
        // Only a Holding outcome is ever checkpointable here (Done/Teach
        // aren't — see `persistence::WizardCheckpoint::for_phase`'s own
        // doc) — an honest holding gets a chance to resume; a genuine
        // Healthy completion needs no checkpoint at all.
        self.checkpoint_if_resumable();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::path::DEV_OVERRIDE_ENV;
    use crate::cli::test_env::ENV_LOCK;
    use std::io::Write as _;
    use std::path::Path;
    use std::sync::atomic::{AtomicU64, Ordering};

    static DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir() -> PathBuf {
        let n = DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ct-unmanaged-flow-test-{}-{:?}-{n}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp test dir");
        dir
    }

    fn manifest_path(dir: &Path) -> PathBuf {
        dir.join("copilot.layers.yml")
    }

    fn mock_cc_auth() -> String {
        format!("{}/fixtures/mock-cc", env!("CARGO_MANIFEST_DIR"))
    }

    fn fixture_path(rel: &str) -> String {
        format!("{}/fixtures/{rel}", env!("CARGO_MANIFEST_DIR"))
    }

    /// A local stand-in `cc` implementing `update --json` (streams two phase
    /// names then `{"done": true}`) and `doctor --json` (cats
    /// `$MOCK_DOCTOR_BODY_PATH`) — see `managed_flow.rs`'s identical helper
    /// for why this is a private, per-module mock rather than the shared
    /// `fixtures/mock-cc` (which doesn't implement `update` at all).
    fn write_mock_cc(dir: &Path) -> PathBuf {
        let script = dir.join("mock-cc-unmanaged-flow");
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

    fn with_env<R>(
        cli_path: Option<&str>,
        auth_scenario: Option<&str>,
        doctor_body: Option<&str>,
        f: impl FnOnce() -> R,
    ) -> R {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK, the shared lock every CT_CLI_PATH-
        // touching test in this crate uses.
        unsafe {
            match cli_path {
                Some(p) => std::env::set_var(DEV_OVERRIDE_ENV, p),
                None => std::env::remove_var(DEV_OVERRIDE_ENV),
            }
            match auth_scenario {
                Some(s) => std::env::set_var("CT_AUTH_SCENARIO", s),
                None => std::env::remove_var("CT_AUTH_SCENARIO"),
            }
            match doctor_body {
                Some(p) => std::env::set_var("MOCK_DOCTOR_BODY_PATH", p),
                None => std::env::remove_var("MOCK_DOCTOR_BODY_PATH"),
            }
        }
        let result = f();
        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("CT_AUTH_SCENARIO");
            std::env::remove_var("MOCK_DOCTOR_BODY_PATH");
        }
        result
    }

    // -- product-first catalog + narrow-not-widen ---------------------------

    #[test]
    fn default_catalog_is_the_four_products_product_first_never_host_framed() {
        let catalog = default_product_catalog();
        let ids: Vec<&str> = catalog.iter().map(|p| p.id.as_str()).collect();
        assert_eq!(ids, vec!["knowledge", "cli", "claude", "codex"]);
        for host_word in ["claude", "codex", "both", "host"] {
            // sanity: labels name PRODUCTS, not a "Claude/Codex/Both" toggle
            assert!(catalog.iter().any(|p| p.id == "claude") || host_word != "claude");
        }
        assert!(catalog.iter().all(|p| !p.label.is_empty()));
    }

    #[test]
    fn ambiguous_catalog_asks_the_choose_products_question() {
        let dir = temp_dir();
        let flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        assert_eq!(flow.phase(), &WizardPhase::Question);
        assert_eq!(flow.questions_remaining(), 3);
        assert!(!flow.steps()[0].done);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn single_product_catalog_auto_answers_choose_products_zero_questions() {
        let dir = temp_dir();
        let single = vec![ProductOption {
            id: "claude".to_string(),
            label: "Claude Copilot".to_string(),
            pre_checked: true,
        }];
        let flow = UnmanagedFlow::begin(single, manifest_path(&dir));
        assert_eq!(
            flow.questions_remaining(),
            2,
            "only LayerSetup + SignIn remain"
        );
        assert!(flow.steps()[0].done, "ChooseProducts must be auto-answered");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn choose_products_refuses_an_id_outside_the_catalog_narrow_not_widen() {
        let dir = temp_dir();
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        let err = flow
            .choose_products(vec!["claude".to_string(), "sql-copilot".to_string()])
            .expect_err("must refuse a product the ecosystem never offered");
        assert_eq!(err, FlowError::ProductNotOffered("sql-copilot".to_string()));
        assert!(
            !flow.steps()[0].done,
            "a refused call must not mark the step done"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn choose_products_accepts_a_narrowed_subset_and_advances_the_question_phase() {
        let dir = temp_dir();
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        flow.choose_products(vec!["claude".to_string(), "codex".to_string()])
            .expect("a subset of the catalog must be accepted");
        assert!(flow.steps()[0].done);
        assert_eq!(flow.phase(), &WizardPhase::Question, "2 steps still remain");
        assert_eq!(flow.questions_remaining(), 2);
        let _ = std::fs::remove_dir_all(&dir);
    }

    // -- out-of-order guards --------------------------------------------

    #[test]
    fn set_layers_before_choose_products_is_refused() {
        let dir = temp_dir();
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        let err = flow
            .set_layers(BTreeMap::new())
            .expect_err("must be out of order");
        assert_eq!(err, FlowError::OutOfOrder);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn begin_signin_before_layer_setup_is_refused() {
        let dir = temp_dir();
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        flow.choose_products(vec!["claude".to_string()]).unwrap();
        let err = flow.begin_signin().expect_err("must be out of order");
        assert_eq!(err, FlowError::OutOfOrder);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn signin_interval_secs_is_none_before_any_signin_attempt() {
        let dir = temp_dir();
        let flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        assert_eq!(flow.signin_interval_secs(), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    // -- LayerSetup writes via settings::authoring, guard-gated -------------

    #[test]
    fn set_layers_writes_the_manifest_via_settings_authoring() {
        let dir = temp_dir();
        let path = manifest_path(&dir);
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), path.clone());
        flow.choose_products(vec!["claude".to_string()]).unwrap();

        let mut repo_urls = BTreeMap::new();
        repo_urls.insert(
            "claude".to_string(),
            "git@github-personal:me/claude-personal.git".to_string(),
        );
        flow.set_layers(repo_urls)
            .expect("a valid repo url must be accepted");

        assert!(flow.steps()[1].done);
        let on_disk = crate::settings::writer::read_existing(&path).unwrap();
        assert_eq!(on_disk.layers.len(), 1);
        assert_eq!(on_disk.layers[0].role.as_deref(), Some("personal"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn set_layers_is_refused_and_never_written_when_the_guard_rejects_a_secret() {
        let dir = temp_dir();
        let path = manifest_path(&dir);
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), path.clone());
        flow.choose_products(vec!["claude".to_string()]).unwrap();

        let mut repo_urls = BTreeMap::new();
        repo_urls.insert(
            "claude".to_string(),
            "https://x:ghp_1234567890ABCDEFabcdef1234567890AB@github.com/me/repo.git".to_string(),
        );
        let err = flow
            .set_layers(repo_urls)
            .expect_err("an embedded credential must be refused");
        match err {
            FlowError::LayerErrors(errors) => {
                assert!(!errors.is_empty());
                for e in &errors {
                    assert!(!e.message.contains("ghp_1234567890ABCDEFabcdef1234567890AB"));
                }
            }
            other => panic!("expected LayerErrors, got {other:?}"),
        }
        assert!(!flow.steps()[1].done);
        assert!(!path.exists(), "a refused write must never touch disk");

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -- SignIn: each CT_AUTH_SCENARIO maps through, never gating the phase --

    #[test]
    fn signin_authorized_completes_the_step_and_advances_to_materialize() {
        let dir = temp_dir();
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        flow.choose_products(vec!["claude".to_string()]).unwrap();
        let mut repo_urls = BTreeMap::new();
        repo_urls.insert(
            "claude".to_string(),
            "git@github-personal:me/claude-personal.git".to_string(),
        );
        flow.set_layers(repo_urls).unwrap();

        with_env(Some(&mock_cc_auth()), Some("authorized"), None, || {
            let ceremony = flow.begin_signin().expect("initiate should succeed");
            assert_eq!(ceremony.status, SigninStatus::Pending);
            assert_eq!(
                flow.signin_interval_secs(),
                Some(5),
                "the ceremony's own poll cadence must be surfaced while pending"
            );
            let terminal = flow.poll_signin().expect("poll should succeed");
            assert_eq!(terminal.status, SigninStatus::Authorized);
            assert_eq!(
                flow.signin_interval_secs(),
                None,
                "no cadence left to poll once the sign-in step has reached a terminal status"
            );
        });

        assert!(flow.steps()[2].done);
        assert!(
            flow.ready_to_materialize(),
            "all 3 steps done must reach Materialize"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn signin_denied_expired_and_timeout_all_still_advance_the_flow() {
        for scenario in ["denied", "expired", "timeout"] {
            let dir = temp_dir();
            let mut flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
            flow.choose_products(vec!["claude".to_string()]).unwrap();
            let mut repo_urls = BTreeMap::new();
            repo_urls.insert(
                "claude".to_string(),
                "git@github-personal:me/claude-personal.git".to_string(),
            );
            flow.set_layers(repo_urls).unwrap();

            with_env(Some(&mock_cc_auth()), Some(scenario), None, || {
                flow.begin_signin().expect("initiate should succeed");
                let terminal = flow.poll_signin().expect("poll should succeed");
                assert_ne!(terminal.status, SigninStatus::Pending);
            });

            assert!(
                flow.steps()[2].done,
                "scenario {scenario} must still complete the SignIn step \
                 (a failed sign-in never blocks the flow — parse-never-compute)"
            );
            assert!(flow.ready_to_materialize());

            let _ = std::fs::remove_dir_all(&dir);
        }
    }

    // -- full ≤3-question happy path: materialize + verify -> Done ---------

    #[test]
    fn the_full_guided_flow_reaches_done_only_via_a_healthy_doctor_poll() {
        let dir = temp_dir();
        let path = manifest_path(&dir);
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), path.clone());

        flow.choose_products(vec!["claude".to_string(), "codex".to_string()])
            .unwrap();
        let mut repo_urls = BTreeMap::new();
        repo_urls.insert(
            "claude".to_string(),
            "git@github-personal:me/claude-personal.git".to_string(),
        );
        repo_urls.insert(
            "codex".to_string(),
            "git@github-personal:me/codex-personal.git".to_string(),
        );
        flow.set_layers(repo_urls).unwrap();

        with_env(Some(&mock_cc_auth()), Some("authorized"), None, || {
            flow.begin_signin().unwrap();
            flow.poll_signin().unwrap();
        });

        assert!(flow.ready_to_materialize());

        let update_mock = write_mock_cc(&dir);
        let healthy = fixture_path("corpus/healthy-clean-fleet.json");
        with_env(
            Some(update_mock.to_str().unwrap()),
            None,
            Some(&healthy),
            || flow.materialize_and_verify(),
        );

        assert_eq!(flow.phase(), &WizardPhase::Done);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_non_healthy_doctor_after_materialize_holds_never_false_done() {
        let dir = temp_dir();
        let path = manifest_path(&dir);
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), path.clone());

        flow.choose_products(vec!["claude".to_string()]).unwrap();
        let mut repo_urls = BTreeMap::new();
        repo_urls.insert(
            "claude".to_string(),
            "git@github-personal:me/claude-personal.git".to_string(),
        );
        flow.set_layers(repo_urls).unwrap();

        with_env(Some(&mock_cc_auth()), Some("denied"), None, || {
            flow.begin_signin().unwrap();
            flow.poll_signin().unwrap();
        });

        let update_mock = write_mock_cc(&dir);
        let signed_out = fixture_path("corpus/signed-out-claude-personal.json");
        with_env(
            Some(update_mock.to_str().unwrap()),
            None,
            Some(&signed_out),
            || flow.materialize_and_verify(),
        );

        assert_ne!(flow.phase(), &WizardPhase::Done);
        assert!(matches!(flow.phase(), WizardPhase::Holding(_)));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn materialize_and_verify_is_a_no_op_before_all_questions_are_answered() {
        let dir = temp_dir();
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        let before = flow.phase().clone();
        flow.materialize_and_verify();
        assert_eq!(flow.phase(), &before, "must not advance before ready");
        let _ = std::fs::remove_dir_all(&dir);
    }

    // -- M3 QA follow-up D2: resumability -------------------------------

    /// A single mock `cc` implementing `auth`/`update`/`doctor` (this
    /// module's own combined shape) AND `config set/get` (persistence's own
    /// dotted JSON store) — everything one end-to-end interrupted-then-
    /// resumed test needs behind ONE `CT_CLI_PATH` override.
    fn write_mock_cc_with_config(dir: &Path) -> PathBuf {
        let script = dir.join("mock-cc-unmanaged-flow-checkpoint");
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
        writeln!(f, "elif verb == 'auth':").unwrap();
        writeln!(
            f,
            "    scenario = os.environ.get('CT_AUTH_SCENARIO', 'authorized')"
        )
        .unwrap();
        writeln!(f, "    if '--poll' in sys.argv:").unwrap();
        writeln!(f, "        print(json.dumps({{'status': scenario}}))").unwrap();
        writeln!(f, "    else:").unwrap();
        writeln!(
            f,
            "        print(json.dumps({{'user_code': 'WDJB-MJHT', 'verification_uri': \
             'https://example.com/device', 'expires_in': 900, 'interval': 5}}))"
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

    /// The full interrupted-then-resumed story for the GUIDED flow: answer
    /// all 3 questions (choose products, write layers, sign in), which
    /// checkpoints at Materialize's first entry (never touching
    /// materialize/doctor yet — simulating a quit right there). A brand new
    /// `UnmanagedFlow::resume` reconstructed from that checkpoint must land
    /// straight at "ready to materialize" with its answers intact, WITHOUT
    /// re-asking ChooseProducts/LayerSetup/SignIn — the exact defect M3 QA
    /// (D2) reported. Finishing `materialize_and_verify` on the resumed flow
    /// must still only reach `Done` via a genuinely healthy doctor poll
    /// (ADR-M3-002 holds under resume too).
    #[test]
    fn an_interrupted_guided_flow_resumes_ready_to_materialize_with_answers_intact() {
        let dir = temp_dir();
        let path = manifest_path(&dir);
        let mock_cc = write_mock_cc_with_config(&dir);
        let config_path = dir.join("cc-config.json");

        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK, the shared lock every CT_CLI_PATH-
        // touching test in this crate uses.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, &mock_cc);
            std::env::set_var("CT_AUTH_SCENARIO", "authorized");
            std::env::set_var("MOCK_CC_CONFIG_PATH", &config_path);
        }

        // --- the original, interrupted run ---
        let mut flow = UnmanagedFlow::begin(default_product_catalog(), path.clone());
        flow.choose_products(vec!["claude".to_string(), "codex".to_string()])
            .unwrap();
        let mut repo_urls = BTreeMap::new();
        repo_urls.insert(
            "claude".to_string(),
            "git@github-personal:me/claude-personal.git".to_string(),
        );
        repo_urls.insert(
            "codex".to_string(),
            "git@github-personal:me/codex-personal.git".to_string(),
        );
        flow.set_layers(repo_urls).unwrap();
        flow.begin_signin().unwrap();
        flow.poll_signin().unwrap(); // completes the 3rd step -> checkpoints at Materialize

        assert!(
            flow.ready_to_materialize(),
            "the original run must have reached Materialize before the simulated quit"
        );

        // --- simulated relaunch: `flow` above is dropped, never consulted again ---
        let checkpoint =
            persistence::load_checkpoint().expect("checkpoint must survive the relaunch");
        assert_eq!(checkpoint.mode, WizardMode::Unmanaged);

        let resumed = UnmanagedFlow::resume(&checkpoint, default_product_catalog(), path.clone());
        assert!(
            resumed.ready_to_materialize(),
            "a resumed flow must land straight at 'ready to materialize', never back at \
             ChooseProducts"
        );
        assert!(
            resumed.steps().iter().all(|s| s.done),
            "no step may be lost by a resume"
        );
        assert_eq!(
            resumed.selected_products,
            vec!["claude".to_string(), "codex".to_string()],
            "the already-answered product selection must survive the resume, never re-asked"
        );

        // The manifest LayerSetup already wrote must also still be there,
        // untouched by the resume (never-destroy) — resume never re-authors it.
        let manifest = crate::settings::writer::read_existing(&path).unwrap();
        assert_eq!(manifest.layers.len(), 2);

        // Finishing on the resumed flow must still only reach Done via a
        // genuinely healthy doctor poll (ADR-M3-002 holds under resume too).
        let healthy = fixture_path("corpus/healthy-clean-fleet.json");
        // SAFETY: serialized by ENV_LOCK (still held via `_guard` above).
        unsafe {
            std::env::set_var("MOCK_DOCTOR_BODY_PATH", &healthy);
        }
        let mut resumed = resumed;
        resumed.materialize_and_verify();
        assert_eq!(resumed.phase(), &WizardPhase::Done);

        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("CT_AUTH_SCENARIO");
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
            std::env::remove_var("MOCK_DOCTOR_BODY_PATH");
        }
        drop(_guard);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A checkpoint saved for a DIFFERENT phase (`materialize_and_verify`
    /// never reached, still mid-Question) must simply not exist yet —
    /// `for_phase` only checkpoints Materialize's first entry and Holding,
    /// never a mid-Question moment (see `persistence.rs`'s own
    /// `only_materialize_first_entry_and_holding_are_checkpointable` test);
    /// this proves the SAME discipline holds when driven through the real,
    /// live `UnmanagedFlow`, not just the pure `WizardCheckpoint::for_phase`
    /// function in isolation.
    #[test]
    fn choosing_products_alone_never_checkpoints_a_mid_question_moment() {
        let dir = temp_dir();
        let mock_cc = write_mock_cc_with_config(&dir);
        let config_path = dir.join("cc-config.json");

        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(DEV_OVERRIDE_ENV, &mock_cc);
            std::env::set_var("MOCK_CC_CONFIG_PATH", &config_path);
        }

        let mut flow = UnmanagedFlow::begin(default_product_catalog(), manifest_path(&dir));
        flow.choose_products(vec!["claude".to_string()]).unwrap();
        assert_eq!(flow.phase(), &WizardPhase::Question, "2 steps still remain");

        assert!(
            persistence::load_checkpoint().is_none(),
            "a mid-Question moment must never checkpoint"
        );

        unsafe {
            std::env::remove_var(DEV_OVERRIDE_ENV);
            std::env::remove_var("MOCK_CC_CONFIG_PATH");
        }
        drop(_guard);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
