/**
 * The web UI's view of Rust's typed domain state (`src-tauri/src/model/state.rs`).
 *
 * This mirrors the DTO Rust serializes for `get_state()` / the `state-changed`
 * event — never the raw `cc doctor --json` wire shape. The UI must not be able
 * to reinterpret unparsed CLI output; parsing and fail-closed defaulting happen
 * exclusively in Rust (`model/`), per the parse-never-compute boundary.
 *
 * T7 scope: this is the `RenderState` contract shared with T3 (see the T7 task
 * brief). T3 owns the authoritative Rust struct; this file is the TS mirror.
 * Until T3's real DTO lands, T7 builds to this shape directly from the T2
 * corpus (`src-tauri/fixtures/corpus/*.json`) via `src/dev-fixtures/*.json` —
 * T8 reconciles any drift once the real `get_state()` return type exists.
 */

/** The 10 CLI-emitted status values, mapped 1:1 from `doctor.status` (ADR-M1-001). */
export type CliStatus =
  | "setup-needed"
  | "it-config-incomplete"
  | "healthy"
  | "syncing"
  | "update-available"
  | "needs-attention"
  | "signed-out"
  | "offline"
  | "waiting-for-network"
  | "updating-app";

/** The 11th, APP-OWNED state — never CLI-emitted; chosen only from I/O/schema failure. */
export type CliUnreadableReason =
  | "io_error"
  | "parse_error"
  | "schema_out_of_range"
  | "missing_security_field"
  | "exit_2"
  | "invalid_content";

export type Severity = "pass" | "warn" | "fail";
export type LayerSeverity = Severity | "none";

export type Layer = "foundation" | "org" | "dept" | "personal";

/**
 * The badge SHAPE vocabulary (60-ui-design.md § Status-Glyph Family / § Layer
 * badge palette). Shape is the primary encoder — every value here must be
 * legible with colour fully stripped. `badges.ts` is the only module that
 * interprets this union into a rendered mark.
 *
 * T8: this is the SAME 12-token set as Rust's canonical
 * `render::BADGE_VOCABULARY` (`src-tauri/src/render/mod.rs`) — every token
 * `CliStatus::glyph_badge()`/`render::derive::severity_badge` can produce.
 * `src-tauri/tests/fitness_badge_vocabulary.rs` cross-checks this union and
 * `badges.ts`'s `drawShape` switch against that Rust list on every CI run,
 * so the two sides cannot silently drift apart again.
 */
export type BadgeState =
  | "pass" // up-to-date — green dot (layer/product only, never the tray glyph)
  | "ring" // syncing / updating / repairing in the background
  | "key" // needs sign-in
  | "update" // update-available — info-blue dot
  | "triangle" // needs-attention — amber triangle
  | "wrench" // IT-config-incomplete
  | "clock" // waiting-for-network
  | "cloud-slash" // offline
  | "bang" // CLI-unreadable / Error — the only red, the only "!"
  | "spinner" // updating-app (Control Tower self-update)
  | "hollow" // setup-needed — hollow outline, slow pulse
  | "none"; // no data for this bucket

export interface LayerView {
  layer: Layer;
  severity: LayerSeverity;
  badge_state: BadgeState;
  detail: string | null;
}

export interface ProductView {
  product: string;
  worst_severity: Severity;
  layers: LayerView[];
}

export interface AuthIssue {
  identity: string;
  scope: string;
  state: "expired" | "revoked";
  expires_at: string | null;
}

export interface HeaderView {
  /** Same badge vocabulary as the tray glyph — worst state across all products x layers. */
  glyph_state: BadgeState;
  /** The one honest status sentence, per 70-copy-voice.md. Never fabricated. */
  sentence: string;
}

export type ClientState = "ok" | "cli_unreadable";

/**
 * The shared render contract (T3/T7). The web UI renders this and only this —
 * no computed score, no worst-wins ladder computed in TS, no verdict beyond
 * what's already in the fields below.
 */
export interface RenderState {
  client_state: ClientState;
  cli_unreadable_reason: CliUnreadableReason | null;
  host: string | null;
  status: CliStatus | null;
  offline: boolean;
  header: HeaderView;
  products: ProductView[];
  auth_issues: AuthIssue[];
}

/** T1 IPC seam alias — the DTO crossing `get_state()` / `state-changed` is a `RenderState`. */
export type TrayStateDto = RenderState;

/** Event name Rust emits on `state-changed` (see src-tauri/src/commands.rs). */
export const STATE_CHANGED_EVENT = "state-changed" as const;

/**
 * Settings (M2, S1) — the layer-manifest IPC DTOs. Mirrors
 * `src-tauri/src/settings/dto.rs` field-for-field (plain snake_case on both
 * sides, same convention as `RenderState` above — no camelCase translation
 * layer).
 *
 * S1 froze this shape; `get_settings()` / `save_settings()` (S6) now cross
 * this seam for real, and S8 folded S7's standalone `src/settings-types.ts`
 * copy in here as the single authoritative source once the two could safely
 * be merged (that file's own header explains why it existed separately in
 * the meantime — a deliberate anti-merge-conflict measure, not drift).
 * `repo_url`/`auth_ref` are non-null `string` — Rust always projects a
 * missing value to `""` (`commands::project_row`'s `unwrap_or_default()`),
 * never `null`, so the UI's own "not set up" / "needs sign-in" checks read
 * an empty string, not an absent field.
 */

/**
 * The three tiers Settings can author (D-1-M2). Foundation is the base tier
 * and is never user-authored via Settings, so it has no member here.
 */
export type Tier = "org" | "dept" | "personal";

export interface FieldError {
  /** `null` for a manifest-wide problem not attributable to one layer. */
  layer_id: string | null;
  field: string;
  /**
   * Plain language always — never raw yaml/git/serde text (SOUL "a Git
   * error to a non-technical person").
   */
  message: string;
}

export interface LayerRow {
  id: string;
  product: string;
  tier: Tier;
  repo_url: string;
  /** A REFERENCE only (e.g. "ssh-personal", "anon") — never a credential value (D-4). */
  auth_ref: string;
  rank: number;
  /** `false` on a managed machine for a locked org/dept row (S5's managed gate). */
  editable: boolean;
}

/** The full Settings surface `get_settings()` returns (S6). */
export interface SettingsState {
  /** `true` when a forced/managed-domain ecosystem is present (S5). */
  managed: boolean;
  layers: LayerRow[];
  /** Every current validation problem, plain language. Empty means valid. */
  errors: FieldError[];
}

/**
 * What the UI submits on save (S7 -> S6 -> S4). `rank`/`id`/`auth_ref` are
 * NOT here — they're derived Rust-side (decision-gated on D-1-M2), never
 * sent from the UI, and the assembly step never probes the repo (invariant
 * #1: no network I/O in authoring).
 */
export interface LayerInput {
  product: string;
  tier: Tier;
  repo_url: string;
}

/**
 * First-run wizard (M3, `.copilot/wp/15.md`) — the IPC DTOs `src-tauri/src/
 * wizard/dto.rs` defines (S1). Mirrors that file field-for-field (plain
 * snake_case both sides, same convention as `RenderState`/`SettingsState`
 * above). **S1 defines this shape only** — the real `get_wizard_state()`/
 * `answer_question()`/`start_signin()` commands and the `wizard-phase` event
 * are S6; the managed/unmanaged orchestration that drives the underlying
 * Rust state machine is S4/S5; the real device-flow seam is S3.
 */

/** Managed (MDM-delivered, ~0-question silent first run) vs unmanaged (solo/guided, <=3 questions). */
export type WizardMode = "managed" | "unmanaged";

/**
 * The wire-safe phase tag (`src-tauri/src/wizard/dto.rs`'s `phase_tag`).
 * `"holding"` covers every named holding terminal (IT-config-incomplete /
 * waiting-for-network / a non-Healthy verify result) — `WizardState.error`
 * carries the plain-language reason; there is no separate tag per reason.
 */
export type WizardPhaseTag =
  | "welcome"
  | "detect"
  | "question"
  | "materialize"
  | "verify"
  | "teach"
  | "done"
  | "holding";

/** Product-first (ADR-M3-005): `choose-products` renders the N-product model, never a host-framed step. */
export type WizardStepKind = "choose-products" | "layer-setup" | "sign-in";

/**
 * One checkbox option on the `choose-products` step (ADR-M3-005 product-
 * first). Mirrors the REAL Rust `unmanaged_flow::ProductOption` struct
 * field-for-field (`{id, label, pre_checked}` — confirmed by reading
 * `src-tauri/src/wizard/unmanaged_flow.rs`'s `default_product_catalog()`
 * during this session, after Stream-A's S1/S4/S5/S6 landed mid-session).
 * `pre_checked` is BOTH the initial checked state and the narrow-not-widen
 * ceiling — Bob may uncheck a `pre_checked: true` option, never check a
 * `pre_checked: false` one (an id the ecosystem doesn't grant at all), so an
 * ungranted option renders visible but disabled, never simply absent (the
 * same "show the honest slot, don't hide it" convention `settings.ts` uses
 * for un-editable rows).
 *
 * **Gap closed (S8):** `unmanaged_flow.rs`'s own doc comment on
 * `ProductOption` called for this catalog to be "round-tripped by a
 * dedicated wizard command... alongside" the DTO — `get_wizard_product_catalog`
 * (`GET_WIZARD_PRODUCT_CATALOG_CMD` below) is that command, a thin
 * passthrough to the real `unmanaged_flow::default_product_catalog()`.
 * `wizard-main.ts` fetches this catalog once and populates it onto the
 * `choose-products` step via the `WizardStep.products` extension below —
 * never a second, client-duplicated copy that could drift from the real
 * Rust catalog (the prior hardcoded `PRODUCT_CATALOG` mirror this replaced).
 */
export interface WizardProductOption {
  id: string;
  label: string;
  pre_checked: boolean;
}

/**
 * One repo-URL row on the `layer-setup` step. Confirmed against the real
 * `UnmanagedFlow::set_layers(repo_urls: BTreeMap<String, String>)` — a flat
 * product-id -> repo-URL map, ALWAYS authored at `Tier::Personal` (an
 * unmanaged/solo first run has no org/dept tier to author into, unlike
 * Settings' 3-tier form) — so, unlike `LayerRow`, there is no `tier`/
 * `editable` field here at all: every row in this flow is personal-tier and
 * always editable.
 */
export interface WizardLayerSlot {
  product: string;
  repo_url: string;
}

/**
 * One of the unmanaged flow's <=3 questions. Confirmed against the real
 * `UnmanagedFlow::steps()` (`src-tauri/src/wizard/unmanaged_flow.rs`): the
 * wire shape is EXACTLY `{id, kind, prompt, done}`, fixed order
 * `[choose-products, layer-setup, sign-in]`, with these exact `prompt`
 * strings: "Which copilots do you want set up?" / "Where should we sync
 * your personal layer from?" / "Sign in to keep everything in sync." —
 * `WizardStep.prompt` is always populated in the real flow, so this UI's
 * copy fallbacks (`copy.ts`'s `PRODUCTS_TITLE`/`LAYER_SETUP_TITLE`) are only
 * ever exercised by a dev fixture that leaves `prompt` empty.
 *
 * **Genuine milestone-scope finding (not a UI gap — confirmed by reading the
 * real flow):** Flow 2 Q3 ("company" + "department pick-list",
 * `50-ux-design.md`) is NOT implemented anywhere in the landed S5 Rust flow
 * — `set_layers` takes only a repo-URL map, no company/department. This
 * UI accordingly renders `layer-setup` as repo-URL rows ONLY, matching the
 * real command's argument shape; company/department render nothing because
 * the real flow has nothing there to submit. Flagged for the design/cw
 * track to either descope Q3 from the docs or for a future stream to add it
 * — this UI must not invent a submission the real `wizard_set_layers`
 * command doesn't accept.
 *
 * `products`/`layers` below are an ADDITIVE, optional UI-side extension for
 * the ONE confirmed real gap (the product catalog — see
 * `WizardProductOption`'s doc). `layers` is populated by the UI itself once
 * Q1 answers are known (the real DTO has no server-side notion of "which
 * products need a repo-URL row" either — the client must remember its own
 * Q1 selection and synthesize this list locally before rendering Q2; see
 * `wizard-main.ts`).
 */
export interface WizardStep {
  id: string;
  kind: WizardStepKind;
  prompt: string;
  done: boolean;
  /** `choose-products` only (S7 extension, see above — the confirmed real catalog gap). */
  products?: WizardProductOption[];
  /** `layer-setup` only (S7 extension, see above — client-synthesized from the Q1 answer, not server-supplied). */
  layers?: WizardLayerSlot[];
}

/**
 * The sign-in device-flow terminal states (ADR-M3-001's frozen SHAPE; S3
 * wires the real `cc auth <integration> --json` seam this mirrors).
 */
export type SigninStatus = "idle" | "pending" | "authorized" | "denied" | "expired" | "timeout";

/**
 * The device-flow RENDER data only (invariant #6) — never a token/secret/
 * credential field. `src-tauri/tests/fitness_no_secret_on_wizard_dto.rs`
 * enforces this on the Rust side; there is no code path for a real token to
 * reach this shape at all.
 */
export interface SigninState {
  status: SigninStatus;
  user_code: string | null;
  verification_uri: string | null;
}

/**
 * The full wizard IPC surface (S6's `get_wizard_state()` return type).
 * `complete` is `true` if and only if `phase === "done"` — and `"done"` is
 * reachable, Rust-side, ONLY via a parsed `Healthy` `CliStatus` (ADR-M3-002,
 * the same "icon can't lie" guarantee `RenderState.status` already carries).
 */
export interface WizardState {
  mode: WizardMode;
  phase: WizardPhaseTag;
  /** A NAME, never an ETA/countdown/percentage (ADR-M3-003, Case Law OUT). */
  phase_label: string;
  steps: WizardStep[];
  signin: SigninState | null;
  /**
   * The sign-in ceremony's own poll cadence, in seconds (S8) — how often the
   * UI should call `wizard_poll_signin` while `signin.status === "pending"`.
   * `null` whenever `signin` is `null` or already terminal (nothing left to
   * poll). Deliberately kept off the frozen `SigninState` shape (mirrors
   * `src-tauri/src/wizard/dto.rs`'s `WizardState.signin_interval_secs` doc) —
   * this is polling bookkeeping, **not an ETA**: it must only ever be used as
   * a `setInterval` argument, never rendered as a countdown/"X seconds left"
   * string (`fitness_no_eta_in_wizard.rs`).
   */
  signin_interval_secs: number | null;
  complete: boolean;
  /** Plain language only — never raw yaml/serde/CLI error text. `null` unless `phase === "holding"`. */
  error: string | null;
}

/**
 * The REAL S6 IPC command surface — confirmed by reading the landed
 * `src-tauri/src/commands.rs` during this session (Stream-A's S1/S4/S5/S6
 * landed mid-session; these names replace this file's earlier speculative
 * `answer_question`/`start_signin`/`wizard-phase`-event guess). There is NO
 * event stream — every command is a plain async request/response that
 * returns the fresh `WizardState` directly; the UI re-renders from each
 * command's own return value rather than a `listen()` subscription.
 *
 * - `get_wizard_state` — sync, no args; a snapshot pull.
 * - `get_wizard_product_catalog` — sync, no args; the real `choose-products`
 *   catalog (S8 — a thin passthrough to `unmanaged_flow::
 *   default_product_catalog()`, never a client-duplicated mirror).
 * - `wizard_advance` — async, no args; the one "move the backend forward"
 *   trigger (kicks off the managed silent run OR begins the guided flow;
 *   later, runs the materialize+verify tail once all 3 questions are
 *   answered). Idempotent once the managed flow has already finished.
 * - `wizard_choose_products` — async, `{ products: string[] }` (selected ids).
 * - `wizard_set_layers` — async, `{ inputs: Record<string, string> }`
 *   (product id -> repo URL; always personal-tier, see `WizardLayerSlot`).
 * - `wizard_begin_signin` / `wizard_poll_signin` — async, no args; the UI
 *   polls the latter at the CLI-specified cadence (S8 —
 *   `WizardState.signin_interval_secs`) until the returned `signin.status`
 *   is a terminal value.
 */
export const GET_WIZARD_STATE_CMD = "get_wizard_state" as const;
export const GET_WIZARD_PRODUCT_CATALOG_CMD = "get_wizard_product_catalog" as const;
export const WIZARD_ADVANCE_CMD = "wizard_advance" as const;
export const WIZARD_CHOOSE_PRODUCTS_CMD = "wizard_choose_products" as const;
export const WIZARD_SET_LAYERS_CMD = "wizard_set_layers" as const;
export const WIZARD_BEGIN_SIGNIN_CMD = "wizard_begin_signin" as const;
export const WIZARD_POLL_SIGNIN_CMD = "wizard_poll_signin" as const;

/**
 * M4 S10 — Control Tower's own self-update affordance. This is a DIFFERENT
 * signal from `CliStatus`'s `"update-available"`/`"updating-app"` above:
 * those two are the CLI-parsed, worst-wins verdict about a PRODUCT (Claude
 * Copilot, CLI Copilot, …) needing an update, 1:1 from `doctor.status`
 * (invariant #1, parse-never-compute). `UpdateState` is Control Tower's own
 * binary's self-update TRANSPORT (ADR-M4-004: "M4 must not re-derive
 * [the doctor] verdict; it owns only the transport") — download / verify /
 * stage / promote / rollback of the app itself, driven by the two commands
 * below, which the M4 `me` agent (Stream-D, S4/S5) lands in parallel with
 * this UI task (`.copilot/wp/24.md`'s ADR-M4-004/ADR-M4-002).
 *
 * **Frozen by the S10 task brief** (this UI builds to it before the real
 * Rust DTO exists — same "T7 builds to this shape directly" convention
 * `RenderState`'s header doc used for T3): a later stream reconciles any
 * drift once `src-tauri/src/commands.rs` actually defines
 * `check_for_update`/`apply_update`'s real return type. If Rust lands a
 * differently-shaped `UpdateState`, that reconcile is S11's job, not a
 * silent assumption here.
 */
export type UpdateStatus =
  | "idle"
  | "checking"
  | "up-to-date"
  | "available"
  | "downloading"
  | "verifying"
  | "staging"
  | "ready"
  | "rolled-back"
  | "error";

/**
 * The self-update transport's own render contract. `message` is ALWAYS
 * plain language (never raw signature/heartbeat/watchdog text) — this
 * mirrors `WizardState.error`'s discipline exactly. Rendering must never
 * fabricate a friendlier string when `message` is present; the ONE place a
 * local fallback copy is used is when `message` is `null` (see
 * `render/copy.ts`'s `UPDATE_*` fallbacks).
 */
export interface UpdateState {
  status: UpdateStatus;
  available_version: string | null;
  current_version: string;
  message: string | null;
}

/**
 * `check_for_update` — sync/async request-response (no event stream, same
 * convention as the wizard's command surface above): a snapshot pull, used
 * both for an initial-load check and to poll progress while an update is in
 * flight (`render/update.ts` polls this at a short fixed cadence while
 * `status` is one of checking/downloading/verifying/staging — the S4/S5
 * contract doesn't expose its own polling-interval field the way
 * `WizardState.signin_interval_secs` does, so this UI picks a conservative
 * fixed cadence; flagged for S11 to reconcile against whatever real cadence
 * the backend expects).
 *
 * `apply_update` — kicks off (or advances) the update; returns the
 * resulting `UpdateState` from that single call. `render/update.ts` treats
 * this exactly like `wizard_advance`: idempotent to call again, and a
 * still-in-progress return value is expected to be followed by
 * `check_for_update` polling rather than a second `apply_update` call.
 */
export const CHECK_FOR_UPDATE_CMD = "check_for_update" as const;
export const APPLY_UPDATE_CMD = "apply_update" as const;

/**
 * M5/S2 — the deprovision DTO + render (parse-not-compute). Mirrors
 * `src-tauri/src/deprovision/render.rs`'s `DeprovisionView` field-for-field
 * (plain snake_case both sides, same convention as `RenderState`/
 * `SettingsState` above).
 *
 * **This is a render of a CLI/MDM-PERFORMED deprovision, never something the
 * UI triggers itself.** There is deliberately no
 * `deprovision`/`run_deprovision` command exported here — the app contains
 * ZERO wipe/retain logic (invariant #1), and deprovisioning an org is an
 * IT/managed/leaver action, never a Bob-initiated one (route-by-competence,
 * invariant #5). The trigger/routing surface (IT-routed, auth-revoked ->
 * offer) is a later stream (S6), which will export its own command
 * constant here once it lands — this type exists so that stream, and any
 * IT-facing renderer, has a frozen shape to build against today.
 *
 * `retained_dirty` is the never-destroy reassurance (invariant #3) — render
 * it prominently, always (including when empty: "no dirty personal work was
 * in the way" is itself honest information). `secrets_touched` MUST be `0`;
 * `secrets_alarm` is `true` iff it isn't — an HONEST ALARM, never hidden or
 * normalized away. `removed_count` (`removed.materialized` upstream) must be
 * rendered with NEUTRAL copy only ("N item(s) removed") — its exact count
 * semantics are undefined even upstream (G-M5-4); never editorialize it into
 * "files" or "trees".
 */
export type DeprovisionOutcome = "wiped" | "partial" | "noop" | "unreadable";

/** The APP-OWNED reason a deprovision body could not be trusted — never a value the CLI emits itself. */
export type DeprovisionUnreadableReason =
  | "io_error"
  | "parse_error"
  | "schema_out_of_range"
  | "missing_security_field"
  | "invalid_content";

export interface DeprovisionView {
  outcome: DeprovisionOutcome;
  unreadable_reason: DeprovisionUnreadableReason | null;
  removed_count: number | null;
  removed_clones: string[];
  retained_dirty: string[];
  secrets_touched: number;
  secrets_alarm: boolean;
  sentence: string;
}

/**
 * M6 S5 — the Bob-lane notification surface (`.copilot/wp/37.md` / task 56).
 * Mirrors the shape the router (M6 S2, `routing`) emits for the Bob lane,
 * per the task brief's frozen data contract — built to this shape directly
 * (same "T7/T3 build-to-shape-before-the-real-DTO-lands" convention
 * `RenderState`'s and `UpdateState`'s own header docs use above) ahead of
 * S7's live wiring, which reconciles any drift once the real `routing`
 * module's Rust type lands.
 *
 * **The closed set (SOUL Principle 2 / Alert Machine anti-pattern).** Bob is
 * interrupted about exactly TWO things — his own sign-in and his own dirty
 * working tree — because those are the only non-deferrable decisions only he
 * can make about his own data (invariant #3, invariant #5). Every other
 * event (held-major, policy denial, prune, security auto-suspend) is either
 * auto-acted or IT-routed and structurally has NO prompt arm here — there is
 * deliberately no `"held-major"` / `"policy-denied"` / `"security-approval"`
 * member of `BobPromptKind`, and no `action`/`approve`/`unblock` field
 * anywhere on `BobNotice`. If a future stream is tempted to add one, that is
 * the Alert Machine and must be routed to IT instead, not added here.
 */
export type BobPromptKind = "sign-in" | "dirty-wip";

/**
 * A single, quiet, respectful interruption about Bob's OWN data — the
 * closed set of two (see module doc above). `title` is the notification-
 * register copy (what a real macOS notification would have said — see
 * `render/bob_lane.ts`'s notification-denied-fallback doc); `detail` is the
 * calmer status-line-register context shown once the fallback/popover is
 * already open; `action_label` is the one respectful next step, never an
 * approval of someone else's decision.
 */
export interface BobPrompt {
  kind: BobPromptKind;
  title: string;
  detail: string;
  action_label: string;
}

export type BobNoticeKind = "kept-you-safe" | "kept-your-working-version" | "waiting-on-it";

/**
 * A quiet, non-actionable line Bob has no basis to act on — informational
 * only. Deliberately has no action/dismiss/approve field: per
 * 70-copy-voice.md's Voice Role ("Past-tense for anything already handled.
 * Auto-acted things are reported, not asked"), there is nothing here for Bob
 * to do, and rendering one MUST NOT carry any alarm styling
 * (`render/bob_lane.ts` renders it with the same neutral treatment
 * `render/update.ts`'s rollback toast already established for "Kept your
 * working version."). `"kept-you-safe"`/`"kept-your-working-version"` report
 * something already AUTO-ACTED (past tense); `"waiting-on-it"` (M6/S6, task
 * 57, `src-tauri/src/routing/mod.rs`'s `BobNoticeKind` doc) is the one
 * exception — a held-major update hasn't been acted on at all, this is
 * EscalateIt's own quiet Bob-facing companion render ("an update is waiting
 * on IT — nothing for you to do"), never a prompt, never an approve control.
 */
export interface BobNotice {
  kind: BobNoticeKind;
  message: string;
}

/**
 * The Bob lane's full render contract for one snapshot — the wrapper this UI
 * defines around the router's `BobPrompt`/`BobNotice` shapes above (S2/S7
 * reconcile the real collection shape once the router lands; this is a
 * documented UI-side choice, not an assumption about Rust's wire format).
 * `prompt` is singular by design (the closed set never has two live
 * interruptions at once — 70-copy-voice.md "direct and singular"); `notices`
 * may hold more than one quiet past-tense line. The DEFAULT/EMPTY state
 * (`prompt: null, notices: []`) renders NOTHING — silence-is-success (P1),
 * matching `UpdateState`'s `"idle"` -> `null` precedent in `render/update.ts`.
 *
 * `notifications_denied` is E12/US-B16's fallback signal: when macOS
 * notification permission is denied/unavailable, a live `prompt` must still
 * be reachable via this SAME popover render, with an honest affordance
 * telling Bob why he's seeing it here instead of as a system notification
 * (`render/bob_lane.ts`). It has no bearing on `notices` — those were
 * already dropdown-only, never a live notification, regardless of OS
 * permission state (Flow 7: "A Bob notification is never the sole control on
 * a live exposure").
 */
export interface BobLaneView {
  prompt: BobPrompt | null;
  notices: BobNotice[];
  notifications_denied: boolean;
}

/**
 * `get_bob_lane` — the additive IPC command the M6 S5 task brief names
 * (`.copilot/wp/37.md`: "a `get_bob_lane` / IPC command"). Not yet landed on
 * the Rust side (out of scope for this stream, which owns only `src/` — see
 * the task brief's "Don't touch Rust"); `main.ts` invokes this defensively,
 * the exact same fail-closed-to-silence pattern `CHECK_FOR_UPDATE_CMD` uses
 * in `render/update.ts` (a not-yet-landed command must never break the
 * popover's already-working `RenderState` render, and must never fabricate a
 * prompt/notice that wasn't actually emitted).
 */
export const GET_BOB_LANE_CMD = "get_bob_lane" as const;

/**
 * M6 S2 — the router's ESCALATE-TO-IT lane payload (`src-tauri/src/routing/
 * mod.rs`'s `ItSignal`/`ItSignalKind`, task 53). Mirrors the Rust shape
 * exactly, built to this shape ahead of a future wiring stream reconciling
 * any drift once a live IT-facing surface consumes it (same "build-to-shape"
 * convention `BobPrompt`/`BobNotice`/`RenderState` above already use).
 *
 * **Content-free by construction (invariant #5).** `ItSignalKind` names
 * WHICH content-free safety fact fired — never a personal item name, file
 * path, or ecosystem identifier. `ItSignal` carries exactly these two
 * fields; there is no `identity`/`scope`/`org`/`item` field anywhere on this
 * type, matching the Rust struct's own "content-free by construction, not by
 * convention" doc. `admin_contact: null` means "no IT to escalate to" (an
 * unmanaged/solo machine) — the signal still exists but there is nowhere to
 * deliver it; this NEVER falls back to a Bob-actionable affordance.
 */
export type ItSignalKind =
  | "deprovision_triggered"
  | "deprovision_ambiguous"
  | "auth_revoked_deprovision_offer"
  | "held_major_awaiting_approval"
  | "policy_denial"
  | "security_shadow_auto_suspended"
  | "signature_failure"
  | "persistence_disabled"
  | "notifications_disabled"
  | "bob_item_timed_out"
  | "prune_needs_review"
  | "repair_needs_review"
  | "unrecognized_event";

export interface ItSignal {
  kind: ItSignalKind;
  admin_contact: string | null;
}

/**
 * M6 S4 — the un-dismissable security-banner DTO (`.copilot/wp/37.md` / task
 * 55). Mirrors `src-tauri/src/render/security_banner.rs`'s `SecurityBanner`
 * exactly: two fields, no more, built to this shape ahead of a future live-
 * wiring stream (S6) that reconciles any drift once a real IPC command
 * produces one — the same "build-to-shape" convention `BobPrompt`/
 * `BobNotice`/`ItSignal` above already use.
 *
 * **Re-affirm-only — structurally cannot be dismissed.** There is
 * deliberately no `dismiss`/`clear`/`approve`/`resolved` field anywhere on
 * this type — the ONLY Bob affordance is `reaffirm_label` ("Re-affirm your
 * version"), preserving ownership without ever letting Bob (or this UI) mark
 * the underlying security exposure "resolved" on its own say-so. This is
 * DISTINCT from `BobNotice`'s `"kept-you-safe"` variant above: that quiet
 * mention is deliberately action-free (see `render/copy.ts`'s
 * `BOB_KEPT_YOU_SAFE` doc — it explicitly drops the "Re-affirm your version
 * ▸" affordance because the Bob-lane's closed `BobPromptKind` set forbids a
 * third, security-approval-shaped control there); `SecurityBanner` is the
 * separate, persistent surface that DOES carry it.
 *
 * `null`/absent (never a `SecurityBanner` with `message: ""`) means "no live
 * security-shadow to show" — silence-is-success (P1), the SAME convention
 * `BobLaneView`'s empty state and `UpdateState`'s `"idle"` already establish;
 * this UI never fabricates one as "clear" — only a future live-wiring
 * stream's own parse of the CLI's `changed[]` entries ever produces one.
 */
export interface SecurityBanner {
  message: string;
  reaffirm_label: string;
}

/**
 * `get_security_banner` — the additive IPC command name this stream reserves
 * for S6's live wiring, mirroring `GET_BOB_LANE_CMD`'s identical "not yet
 * landed on the Rust side, invoked defensively" convention (`main.ts`'s
 * `fetchInitialBobLaneState` doc). A missing command must never break the
 * popover's already-working render — it just means no banner shows yet.
 */
export const GET_SECURITY_BANNER_CMD = "get_security_banner" as const;

/**
 * M7 S4 (task 63) — the IT fleet dashboard's render contract
 * (`docs/08-observability/observability.md` §7.1; `60-ui-design.md` § 6
 * Admin / Fleet Dashboard). Mirrors the eventual Rust `FleetHostView`
 * (owner-gated behind G-M7-3, the real collected-fleet source — undefined
 * today) — built to this shape ahead of a live command, same "build-to-
 * shape" convention `BobPrompt`/`ItSignal`/`SecurityBanner` above already
 * use; a future live-wiring stream (S9) reconciles any drift once a real
 * `get_fleet`-shaped command exists.
 *
 * **Per-host, worst-wins — the SAME precedence the tray glyph already
 * uses.** `status`/`badge_state` are one fact about one machine, computed
 * entirely CLI-side; this UI adds no judgment of its own, exactly like
 * `HeaderView.glyph_state` upstream in this same file.
 */
export interface FleetHostView {
  machine_id: string;
  /** One of the ~10 CLI-emitted doctor statuses — the SAME vocabulary `CliStatus` already names. */
  status: CliStatus;
  /** Worst-wins per-host badge — the SAME 12-token `BadgeState` vocabulary the tray glyph uses. */
  badge_state: BadgeState;
  /** This host's row in the safety-escalation feed — content-free, never personal-item-bearing. */
  actionable_items: FleetActionItem[];
}

/**
 * A single actionable IT item — content-free by construction, reusing M6's
 * `ItSignalKind` (`routing::ItSignal`, task 53) rather than inventing a
 * parallel vocabulary. Carries no personal item name, file path, or free
 * text — the same "impossible, not discouraged" standard `ItSignal` itself
 * already holds (see that type's own doc above). This is the M6 EscalateIt
 * lane (held-major / security-shadow-suspend / auth-revoked / policy-denial
 * / …) surfacing on the Admin dashboard, never anything shown to Bob.
 */
export interface FleetActionItem {
  kind: ItSignalKind;
  machine_id: string;
}

/**
 * The whole fleet dashboard's render contract. **The fleet IS the set of
 * hosts** (`docs/08-observability/observability.md` §7.1) — count them,
 * don't score them.
 *
 * **FORBIDDEN, permanently (FF-M7-NOSCORE, SOUL *The Second Pilot* Case
 * Law): no aggregate/blended score field, ever.** A "fleet health 94/100"
 * number is OUT because it implies the app judges health — it renders
 * CLI-parsed per-host facts only. If a future change adds a numeric or
 * percentage field to this type, that IS the violation this milestone
 * exists to prevent; `render/fleet.ts`'s own module doc carries the
 * render-side half of this guard, and this type intentionally has no third
 * field beyond `hosts` to make the temptation structurally harder to act
 * on by accident.
 */
export interface FleetView {
  hosts: FleetHostView[];
}

/**
 * `get_fleet` — the additive IPC command name this stream reserves for a
 * future live-wiring task (S9, mock-fixture-backed collected-fleet source,
 * G-M7-3 owner-gated — the real collector query API is undefined today),
 * mirroring `GET_BOB_LANE_CMD`/`GET_SECURITY_BANNER_CMD`'s identical "not
 * yet landed on the Rust side, invoked defensively" convention. A missing
 * command must never crash the Admin window — it just means the dashboard
 * renders its own empty-fleet state (§7.1's "No machines are reporting
 * yet" line) until that stream lands.
 */
export const GET_FLEET_CMD = "get_fleet" as const;

/**
 * M7 S7 (task 66) — the Admin-mode red/green preflight report
 * (`architecture.md` §8.1 item 5; `docs/08-observability/observability.md`
 * §7.1: "preflight is a one-time, on-demand validation call before
 * rollout... not a continuous signal from the fleet"). Mirrors the Rust
 * `admin::preflight::PreflightReport` — an Admin UI renders this as a plain
 * checklist before pushing a rollout to the fleet.
 *
 * **FORBIDDEN, permanently: no aggregate/readiness score field, ever** —
 * the same discipline `FleetView`'s own doc above holds itself to. This
 * type intentionally carries only `checks`; a future "readiness: 8/10"
 * field on this type IS the violation this stream exists to prevent.
 */
export type PreflightCheckStatus = "pass" | "fail" | "unknown";

/**
 * One check's result. `status: "unknown"` means "not checked/unreachable" —
 * NEVER rendered as green. A check is `"pass"` only if it genuinely,
 * positively passed (the same "never fabricate a pass" discipline
 * `FleetHostView`'s own doc above holds itself to).
 */
export interface PreflightCheckResult {
  check: string;
  status: PreflightCheckStatus;
  detail: string;
}

export interface PreflightReport {
  checks: PreflightCheckResult[];
}
