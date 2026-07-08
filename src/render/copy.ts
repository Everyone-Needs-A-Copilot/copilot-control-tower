/**
 * User-facing strings, sourced verbatim (in intent) from
 * docs/product-design/04-experience-design/70-copy-voice.md — the single
 * source of truth for every word in the product. No copy is authored ad hoc
 * in components; every string here traces to a row in that document.
 *
 * `RenderState.header.sentence` is already the fully-formed top-line string
 * (the CLI/Rust side owns filling in `{Product}`/`{Layer}`); this module only
 * supplies the copy the *UI itself* is responsible for constructing —
 * per-row VoiceOver labels (a11y rule 2, 70-copy-voice.md "VoiceOver"), the
 * contextual primary-action label, and static chrome strings (section
 * label, action effects) — from the same templates, never paraphrased.
 */
import type {
  BadgeState,
  BobLaneView,
  BobNotice,
  BobPrompt,
  CliStatus,
  DeptProjectView,
  Layer,
  LayerView,
  ProductView,
  UpdateState,
  UpdateStatus,
} from "../types";

/**
 * The badge shown on a product's COLLAPSED row — "worst of that product's
 * four layers" (60-ui-design.md § 2a). This is a display pick among already
 * -classified layer badges, never a new verdict (ADR-M1-002 stays in Rust;
 * this only chooses which existing mark to surface one level up).
 */
export function productDisplayBadge(product: ProductView): BadgeState {
  if (product.worst_severity === "pass") return "pass";
  const bad = worstLayer(product.layers);
  return bad?.badge_state ?? "pass";
}

/** Product name is shown in the dropdown header chrome, per 70-copy-voice.md "Product name — RESOLVED". */
export const APP_NAME = "Copilot Control Tower";

export const SECTION_PRODUCTS = "PRODUCTS";

/** 50-ux-design.md Information Architecture — secondary rows below the product list. */
export const SECONDARY_ROWS = ["What changed…", "Add a skill…"] as const;
export const PREFERENCES_LABEL = "Preferences…";
export const QUIT_LABEL = "Quit";

export const LAYER_LABEL: Record<Layer, string> = {
  foundation: "Foundation",
  org: "Org",
  dept: "Department",
  personal: "Personal",
};

/** 70-copy-voice.md § A — Bob top line per state (fallback only; `header.sentence` from the DTO wins). */
export const HEADER_FALLBACK_SENTENCE: Record<CliStatus, string> = {
  healthy: "Everything's in sync across all your copilots.",
  syncing: "Syncing…",
  "signed-out": "Signed out. Sign in to keep everything in sync.",
  "needs-attention": "Something needs a repair.",
  "update-available": "An update is available.",
  "it-config-incomplete": "Your IT setup isn't finished yet. Nothing for you to do — IT has been told.",
  "waiting-for-network": "I've set up as far as your network allows. I'll finish your company setup when you're back online.",
  offline: "You're offline — showing your last synced setup.",
  "setup-needed": "Let's set up your copilot.",
  "updating-app": "Updating Control Tower…",
};

export const CLI_UNREADABLE_SENTENCE: Record<string, string> = {
  io_error: "I couldn't start the engine. Click to reinstall — it's a fix, not a reset.",
  parse_error: "Versions don't match — click to update. I won't guess when I can't read this safely.",
  schema_out_of_range: "Versions don't match — click to update.",
  missing_security_field: "Versions don't match — click to update. I won't guess when I can't read this safely.",
  exit_2: "I couldn't start the engine. Click to reinstall — it's a fix, not a reset.",
  invalid_content: "Versions don't match — click to update. I won't guess when I can't read this safely.",
};
export const CLI_UNREADABLE_FALLBACK =
  "Versions don't match — click to update. I won't guess when I can't read this safely.";

/** 70-copy-voice.md § A — primary action label, contextual to the worst item. `null` = no action offered. */
export const PRIMARY_ACTION_LABEL: Record<CliStatus, string | null> = {
  healthy: "Sync now",
  syncing: null,
  "signed-out": "Sign in…",
  "needs-attention": "Repair…",
  "update-available": "What changed?",
  "it-config-incomplete": null,
  "waiting-for-network": null,
  offline: null,
  "setup-needed": "Finish setup…",
  "updating-app": null,
};
export const CLI_UNREADABLE_ACTION_LABEL = "Update now";

/** Plain-language effect of each action, read alongside its label (a11y rule 2). */
export const ACTION_EFFECT: Record<string, string> = {
  "Sync now": "Checks for updates right now.",
  "Sign in…": "Opens your browser to sign in.",
  "Repair…": "Fixes the finding IT can see. No terminal needed.",
  "What changed?": "Shows what changed. This is informational only.",
  "Finish setup…": "Continues your one-time setup.",
  "Update now": "Updates Control Tower in place.",
  // M6 S5 — Bob-lane prompt actions. "Sign in…" reuses the row above (the
  // SAME action, `types.ts`'s `BobPrompt` doc); "Show me…" is the dirty-WIP
  // prompt's disclosure-only action (see `copy.ts`'s `BOB_DIRTY_WIP_ACTION_LABEL` doc — non-destructive, never an auto-commit).
  "Show me…": "Shows which files still need saving or committing.",
  // M6 S4 — the un-dismissable security banner's ONE affordance
  // (`render/security_banner.ts`, `types.ts`'s `SecurityBanner`). Never an
  // "approve"/"clear" effect — re-affirming only ever re-asserts Bob's own
  // prior override going forward, it never marks the auto-suspend "undone".
  "Re-affirm your version": "Re-applies your overridden version going forward.",
};

/** 70-copy-voice.md § A — secondary note under the header, per state. */
export const SECONDARY_NOTE: Partial<Record<CliStatus, string>> = {
  syncing: "This won't interrupt what you're doing.",
  offline: "This restores on its own when you reconnect.",
  "it-config-incomplete": undefined,
  "waiting-for-network": undefined,
};

/** Layer-state phrase fragment used inside row labels, keyed by the badge shape. */
function stateWords(badgeState: BadgeState, detail: string | null): string {
  switch (badgeState) {
    case "pass":
      return "up to date";
    case "key":
      return "needs sign-in";
    case "triangle":
    // `render::derive::severity_badge`'s M1 floor (ADR-M1-002) reuses
    // "bang" for a checker-severity `fail` at the layer/product bucket
    // level — a WORSE case than `triangle` (`warn`), not a distinct one; no
    // richer per-layer status exists yet to say more (Decision D-1), so it
    // shares the same actionable phrase rather than falling to the generic
    // "no data" default, which would be actively misleading here (a `fail`
    // is the opposite of "no data").
    case "bang":
      return "needs a repair";
    case "ring":
      return detail?.toLowerCase().includes("repair")
        ? "repairing in the background"
        : "updating in the background";
    case "update":
      return "an update is available";
    case "wrench":
      return "IT setup is incomplete";
    case "clock":
      return "waiting for network";
    case "cloud-slash":
      return "showing cached state — offline";
    case "spinner":
      return "updating in the background";
    case "hollow":
      return "not set up yet";
    case "none":
    default:
      return "no data";
  }
}

function layerStateWords(layer: LayerView): string {
  return stateWords(layer.badge_state, layer.detail);
}

/** The text shown in a layer/project row's detail slot — the CLI's own detail if present, else the honest fallback phrase. */
export function layerDetailText(layer: LayerView | DeptProjectView): string {
  return layer.detail ?? stateWords(layer.badge_state, null);
}

/** The one layer (if any) that isn't quietly fine — used to attribute a product's collapsed-row label. */
function worstLayer(layers: LayerView[]): LayerView | undefined {
  const rank: Record<string, number> = { fail: 3, warn: 2, none: 1, pass: 0 };
  return layers
    .filter((l) => l.badge_state !== "pass" && l.badge_state !== "none")
    .sort((a, b) => (rank[b.severity] ?? 0) - (rank[a.severity] ?? 0))[0];
}

/**
 * VoiceOver / visible label for a collapsed or expanded product row.
 * "Knowledge Copilot — up to date across all 4 layers" /
 * "Claude Copilot — org layer updating, expand for detail" (70-copy-voice.md § A).
 */
export function productRowLabel(product: ProductView, expanded: boolean): string {
  if (product.worst_severity === "pass") {
    return `${product.product} — up to date across all 4 layers.`;
  }
  const bad = worstLayer(product.layers);
  if (!bad) {
    return `${product.product} — up to date across all 4 layers.`;
  }
  const base = `${product.product} — ${LAYER_LABEL[bad.layer]} layer ${layerStateWords(bad)}`;
  return expanded ? `${base}.` : `${base}, expand for detail.`;
}

/** Terse word for the collapsed row's trailing phrase — mirrors the 60-ui-design.md mock ("department: sign-in"). */
function shortStateWord(badgeState: BadgeState): string {
  switch (badgeState) {
    case "pass":
      return "up to date";
    case "key":
      return "sign-in";
    case "triangle":
    // Same reasoning as `stateWords`'s "bang" arm: a checker-severity
    // `fail` bucket badge, not the CLI-unreadable header state — must not
    // fall to the "no data" default.
    case "bang":
      return "repair";
    case "ring":
      return "updating…";
    case "update":
      return "update available";
    case "wrench":
      return "IT setup incomplete";
    case "clock":
      return "waiting for network";
    case "cloud-slash":
      return "cached (offline)";
    case "spinner":
      return "updating…";
    case "hollow":
      return "not set up";
    case "none":
    default:
      return "no data";
  }
}

/** Short trailing state phrase shown on the collapsed row (right-aligned), e.g. "department: sign-in". */
export function productRowPhrase(product: ProductView): string {
  if (product.worst_severity === "pass") return "up to date";
  const bad = worstLayer(product.layers);
  if (!bad) return "up to date";
  return `${LAYER_LABEL[bad.layer].toLowerCase()}: ${shortStateWord(bad.badge_state)}`;
}

/** "Org layer — updating in the background" / "Department layer — needs sign-in" (70-copy-voice.md). */
export function layerRowLabel(layer: LayerView): string {
  return `${LAYER_LABEL[layer.layer]} layer — ${layerStateWords(layer)}.`;
}

/** "{ProjectName} (a department project) needs a repair." */
export function deptProjectLabel(project: DeptProjectView): string {
  return `${project.name} (a department project) — ${stateWords(project.badge_state, project.detail)}.`;
}

/** Inline layer/project action label, only rendered when that row is the actionable one. */
export function layerActionLabel(row: { badge_state: BadgeState }): string | null {
  if (row.badge_state === "key") return "Sign in…";
  // "bang" here is a checker-severity `fail` bucket badge (worse than
  // `triangle`'s `warn`), not the CLI-unreadable header state — it needs
  // the same inline repair action, not none at all.
  if (row.badge_state === "triangle" || row.badge_state === "bang") return "Repair…";
  return null;
}

/**
 * M2 S7 — Settings screen copy.
 *
 * Genuine design-doc gap (flagged, not invented silently): 50-ux-design.md
 * and 60-ui-design.md do not design a repo-URL-authoring Settings screen —
 * 60-ui-design.md explicitly names "a settings panel that re-points the
 * update feed" as a ruled-OUT anti-pattern for Bob's surface (line 74/129).
 * This is the DIFFERENT unmanaged/solo/author surface `.copilot/wp/5.md`
 * ADR-M2-004 defines, reached behind Bob's (separately-designed) Preferences.
 * The strings below follow 70-copy-voice.md's voice rules (short, one idea
 * per sentence, honest, no invented jargon, no raw git/yaml/io text ever)
 * and reuse existing approved phrases (`LAYER_LABEL`, "needs sign-in",
 * "Sign in…") wherever the vocabulary already exists, but are NOT sourced
 * from an existing row in 70-copy-voice.md for the net-new Settings-specific
 * strings — those are marked placeholder pending a design pass. Two strings
 * are verbatim from the S7 task brief itself (marked below).
 */
export const SETTINGS_TITLE = "Settings";
/** Task brief, verbatim ("Render this honestly ('Managed by your IT admin')"). */
export const SETTINGS_MANAGED_NOTE = "Managed by your IT admin.";
/** Reuses the existing `stateWords()` "needs sign-in" phrase — task brief, verbatim intent. */
export const SETTINGS_NEEDS_SIGN_IN = "Needs sign-in";
export const SETTINGS_SAVE_LABEL = "Save changes";
export const SETTINGS_SAVED_ANNOUNCEMENT = "Settings saved.";
export const SETTINGS_NOT_SET_UP = "Not set up yet.";
export const SETTINGS_ROW_PLACEHOLDER = "git@github.com:org/repo.git";
export const SETTINGS_EMPTY_STATE =
  "No layers configured yet. Paste a repository URL below to get started.";
export const SETTINGS_BACK_LABEL = "Back";

export function settingsErrorsAnnouncement(count: number): string {
  return `${count} problem${count === 1 ? "" : "s"} found. Fix the highlighted fields and save again.`;
}

/** Display name per product slug — same "{Product} Copilot" convention the dev-fixtures already use. */
export const PRODUCT_LABEL: Record<string, string> = {
  knowledge: "Knowledge Copilot",
  cli: "CLI Copilot",
  claude: "Claude Copilot",
  codex: "Codex Copilot",
};

/** VoiceOver / visible label for one Settings row, per its current honest state. */
export function settingsRowLabel(opts: {
  product: string;
  tier: Layer;
  editable: boolean;
  managed: boolean;
  hasValue: boolean;
  needsSignIn: boolean;
  errorMessage: string | null;
}): string {
  const productName = PRODUCT_LABEL[opts.product] ?? opts.product;
  const base = `${productName} — ${LAYER_LABEL[opts.tier]} repository URL`;
  if (opts.errorMessage) return `${base}. ${opts.errorMessage}`;
  if (!opts.editable && opts.managed) return `${base}, ${SETTINGS_MANAGED_NOTE.toLowerCase()}`;
  if (opts.needsSignIn) return `${base}, ${SETTINGS_NEEDS_SIGN_IN.toLowerCase()}.`;
  if (!opts.hasValue) return `${base}, ${SETTINGS_NOT_SET_UP.toLowerCase()}`;
  return `${base}.`;
}

/**
 * M3 S7 — First-run wizard copy, sourced verbatim from
 * `docs/product-design/04-experience-design/70-copy-voice.md` § B (the setup
 * wizard) wherever a row exists there. A few strings are genuinely net-new —
 * the wizard's product-first host step, the per-outcome device-flow failure
 * lines, and generic step-navigation chrome ("Continue") have no row in
 * 70-copy-voice.md yet (ADR-M3-005 retired the host-framed Q1 copy the doc
 * still shows; the sign-in failure copy was never authored beyond the
 * dropdown's generic Signed-out line). Each is marked **PLACEHOLDER** below —
 * flagged for a copywriter pass, exactly like `SETTINGS_*`'s precedent above,
 * never silently invented as if it were an approved string.
 */

/** B1/B2 header chrome — the product name shown in the wizard window (70-copy-voice.md "Product name — RESOLVED"). */
export const WIZARD_WINDOW_TITLE = APP_NAME;

/** B2 Welcome (unmanaged only — managed skips straight to the silent progress spectator, Flow 1). */
export const WELCOME_TITLE = "Welcome to Copilot Control Tower. Let's set up your copilot.";
export const WELCOME_BODY = "A few quick questions, then it runs itself. No terminal, no setup files.";
/** PLACEHOLDER — 70-copy-voice.md doesn't give an explicit Welcome CTA label. */
export const WELCOME_CONTINUE_LABEL = "Continue";

/** B1 — the silent managed spectator's subhead; B2 reuses these same phase lines for the unmanaged progress view. */
export const PROGRESS_SUBHEAD_MANAGED = "Setting up your copilot. This is automatic — you don't need to do anything.";
export const PROGRESS_RESUME_AFTER_QUIT = "Picking up where we left off.";

/** B3 — teach panel (shown once after first success, US-B06). */
export const TEACH_TITLE = "You're set up.";
export const TEACH_BODY = "Your copilot is ready and will keep itself up to date. Here's the one-page cheat-sheet to get started.";
export const TEACH_ACTION_CHEATSHEET = "Open cheat-sheet";
export const TEACH_ACTION_ADD_SKILL = "Add your first skill";
export const TEACH_ACTION_BACKUP = "Turn on backup";
export const TEACH_BACKUP_BODY = "Want a backup of your setup? It's optional and takes one click.";
export const TEACH_DISMISS = "Done";

/** B4 — honest holding screens inside the wizard. Rendered generically (WizardPhaseTag's "holding" carries no reason sub-tag; `WizardState.error` IS the honest sentence) — titles below are picked ONLY as a display heading over Rust's own plain-language `error` text, never a computed substitute for it. */
export const HOLDING_TITLE_IT_CONFIG = "We're waiting on IT";
export const HOLDING_BODY_IT_CONFIG_FALLBACK =
  "Your setup isn't finished because IT hasn't sent one piece yet. There's nothing for you to do — IT has been told automatically.";
export const HOLDING_TITLE_NETWORK = "You're offline";
export const HOLDING_BODY_NETWORK_FALLBACK =
  "I've set up as far as your network allows. I'll finish your company setup on its own when you reconnect.";
/** Generic fallback heading when neither IT-config nor network keywords are present in `error` (still just a heading over Rust's own honest sentence). */
export const HOLDING_TITLE_GENERIC = "Not finished yet";

/** B2 Q2 — device-flow sign-in step. */
export const SIGNIN_TITLE = "Sign in to continue.";
export const SIGNIN_BODY = "We opened your browser. Enter this code there:";
export const SIGNIN_WAITING = "Waiting for you to finish in the browser…";
export const SIGNIN_HELPER = "This is the sign-in for your AI host — the same account your company uses.";
export const SIGNIN_COPY_LABEL = "Copy";
export const SIGNIN_COPIED_ANNOUNCEMENT = "Code copied.";
/** PLACEHOLDER — an explicit "open browser" affordance beyond the automatic open the copy already narrates. */
export const SIGNIN_OPEN_BROWSER_LABEL = "Open browser";
export const SIGNIN_START_LABEL = "Sign in…";
/** Adapted from 70-copy-voice.md § D's "Signed in." opener — PLACEHOLDER (D's full sentence names a specific product/layer; the wizard's host sign-in is generic). */
export const SIGNIN_SUCCESS = "Signed in.";
/** PLACEHOLDER — no row in 70-copy-voice.md covers the wizard's own denied/expired/timeout copy (only the steady-state dropdown's generic Signed-out line exists); flagged for a cw pass. */
export const SIGNIN_RETRY_LABEL = "Try again";
export const SIGNIN_FAILURE: Record<"denied" | "expired" | "timeout", string> = {
  denied: "You didn't finish signing in.",
  expired: "That code expired before you finished. Let's get you a new one.",
  timeout: "That took longer than expected. Let's try again.",
};

/**
 * B2 Q3 ("company" + "department pick-list") — CONFIRMED OUT OF SCOPE this
 * milestone: reading the real `UnmanagedFlow::set_layers` (`src-tauri/src/
 * wizard/unmanaged_flow.rs`) during this session shows it accepts only a
 * repo-URL map, nothing else — no company/department field exists anywhere
 * in the landed S5 flow. No copy is defined for it here; `types.ts`'s
 * `WizardStep` doc explains the finding in full and flags it for the
 * design/cw track rather than this UI inventing a submission the real
 * command can't accept.
 */

/** PLACEHOLDER — ADR-M3-005 retires 70-copy-voice.md's host-framed Q1 title ("Which one do you want to set up?"); no product-first replacement title has been authored yet. Only ever shown as a fallback — the real `WizardStep.prompt` ("Which copilots do you want set up?", confirmed against `unmanaged_flow.rs`) is used preferentially. */
export const PRODUCTS_TITLE = "Choose your copilots";
/** B2 "Products step (narrow-only)" — the one line that DOES already exist and still applies verbatim. */
export const PRODUCTS_BODY = "These come with your team's setup. Uncheck anything you don't want.";
/** PLACEHOLDER — fallback only; the real `WizardStep.prompt` ("Where should we sync your personal layer from?", confirmed against `unmanaged_flow.rs`) is used preferentially. */
export const LAYER_SETUP_TITLE = "Set up your team";
/** PLACEHOLDER — a fieldset legend for the repo-URL rows, kept distinct from `SETTINGS_TITLE` (the unrelated Settings *window*'s title) so the two surfaces don't read as the same screen. */
export const LAYER_SETUP_REPOS_LEGEND = "Repositories";
/** PLACEHOLDER — generic step-navigation chrome the design docs don't give an explicit label for. */
export const CONTINUE_LABEL = "Continue";

/**
 * M4 S10 — Control Tower's own self-update affordance (`UpdateState`,
 * `render/update.ts`). Distinct from the `CliStatus` "update-available"/
 * "updating-app" rows above, which describe a PRODUCT's update, not Control
 * Tower's own binary (see `types.ts`'s `UpdateState` doc for the full
 * boundary). Every VERBATIM row is cited; every net-new string below is
 * marked PLACEHOLDER (same convention as `SETTINGS_*`/wizard's `PLACEHOLDER`
 * strings above) — flagged for a cw pass, never silently invented as if
 * approved.
 */

/** Verbatim, 70-copy-voice.md § "Loading & Processing" → "App self-update". Doubles as the in-progress header for downloading/verifying/staging (no separate mock exists per phase). */
export const UPDATE_HEADER = "Updating Control Tower…";
/** PLACEHOLDER — no row exists for the pre-click "is one available" check; built from the same present-tense-progress register as "Checking your Mac…". */
export const UPDATE_CHECKING = "Checking for updates…";
/** PLACEHOLDER phase words — reassuring/brief/honest-about-phase per the Loading & Processing rule, never a percentage/ETA (Case Law OUT). */
export const UPDATE_PHASE_WORD: Partial<Record<UpdateStatus, string>> = {
  downloading: "Downloading…",
  verifying: "Verifying…",
  staging: "Staging…",
};
/** PLACEHOLDER — reuses the existing "an update is available" vocabulary (`stateWords`'s "update" case) but names Control Tower explicitly, since this is the app's OWN update, not a product's. */
export const UPDATE_AVAILABLE_SENTENCE = "An update is available for Control Tower.";
/** PLACEHOLDER — quiet/factual per the "no celebratory update" invariant (SOUL "silence beats a toast; a toast beats a celebration"). Never "🎉"/"All set!". */
export const UPDATE_READY_SENTENCE = "Updated.";
/** PLACEHOLDER — mirrors the Empty States "Version-skew, all on current SHA" register ("Every machine is on the current version."), scoped to Bob's own machine. */
export const UPDATE_UP_TO_DATE_SENTENCE = "Control Tower is up to date.";
/** Verbatim, 70-copy-voice.md § "Success States" → "Rollback protected them". THE load-bearing string this task exists to ship — never paraphrased at render time. */
export const UPDATE_ROLLBACK_FALLBACK = "Kept your working version.";
/** PLACEHOLDER — plain-language fallback ONLY for a `null` backend `message`; the real `message` (Rust's `WizardState.error` discipline) always wins when present. Mirrors the "never blame, never a code" Errors microcopy structure. */
export const UPDATE_ERROR_FALLBACK = "I couldn't check for updates right now.";
/** PLACEHOLDER — version-line detail, e.g. "Now on 1.3.0." / "1.3.0 available." */
export function updateVersionDetail(state: UpdateState): string | null {
  if (state.status === "ready" && state.available_version) return `Now on ${state.available_version}.`;
  if (state.status === "available" && state.available_version) return `${state.available_version} available.`;
  return null;
}

/** The one honest top-line sentence for a given `UpdateState` — never fabricates beyond what `status`/`message` prove. */
export function updateSentence(state: UpdateState): string {
  switch (state.status) {
    case "checking":
      return UPDATE_CHECKING;
    case "available":
      return UPDATE_AVAILABLE_SENTENCE;
    case "downloading":
    case "verifying":
    case "staging":
      return UPDATE_HEADER;
    case "ready":
      return UPDATE_READY_SENTENCE;
    case "up-to-date":
      return UPDATE_UP_TO_DATE_SENTENCE;
    case "rolled-back":
      // Always the canonical reassuring line — the load-bearing string this
      // task ships — never the raw backend `message` (that's shown as
      // supplementary detail by `buildToast`, `render/update.ts`).
      return UPDATE_ROLLBACK_FALLBACK;
    case "error":
      return state.message ?? UPDATE_ERROR_FALLBACK;
    case "idle":
    default:
      return "";
  }
}

/** VoiceOver label for the whole update section — the sentence plus, where relevant, the version detail (a11y rule 2). */
export function updateSectionLabel(state: UpdateState): string {
  const detail = updateVersionDetail(state);
  const sentence = updateSentence(state);
  return detail ? `${sentence} ${detail}` : sentence;
}

/**
 * M6 S5 — the Bob-lane notification surface (`render/bob_lane.ts`, `types.ts`'s
 * `BobPrompt`/`BobNotice`/`BobLaneView`). Strings are sourced VERBATIM from
 * 70-copy-voice.md § D (auth/re-login), § E (the commit-your-work
 * interruption), § F (the "kept you safe" line) and the Errors/Success-States
 * microcopy tables — no paraphrasing, per that document's own provenance
 * rule. Net-new strings (nothing in the deck covers the notification-denied
 * fallback affordance, or a Bob-facing CTA for the dirty-WIP prompt beyond
 * the notification text itself) are marked PLACEHOLDER, same convention as
 * `SETTINGS_*`/wizard's `PLACEHOLDER` strings above — flagged for a cw pass,
 * never silently invented as if approved.
 */

/**
 * § D — "Notification (only if his to act)": the literal text a real macOS
 * notification would carry for the sign-in prompt. This Bob-lane surface
 * reuses this EXACT string as the prompt's `title` because the fallback path
 * (E12/US-B16) renders in the popover in place of that same notification —
 * Bob should read the identical sentence either way, never a re-paraphrased
 * "in-app version."
 */
export const BOB_SIGNIN_NOTIFICATION =
  "CLI Copilot needs you to sign in again for its department layer — it's a quick browser step.";
/** § A "Signed-out" row — reused as the prompt's calmer `detail` line, naming which layer and reassuring the rest is fine. */
export const BOB_SIGNIN_DETAIL = "CLI Copilot — department layer needs sign-in. Everything else is up to date.";
/** § A "Signed-out" row's Primary action label — reused verbatim; the SAME action, not a duplicate string. */
export const BOB_SIGNIN_ACTION_LABEL = "Sign in…";

/** § E — the ONLY confirmation Bob ever sees; used verbatim as the dirty-WIP prompt's `title`. */
export const BOB_DIRTY_WIP_NOTIFICATION = "You have unsaved personal work. Save or commit it, then I'll sync.";
/** § E "Why (helper)" — verbatim, reused as the prompt's `detail`. */
export const BOB_DIRTY_WIP_DETAIL = "I never touch your own files without you.";
/**
 * PLACEHOLDER — no CTA button is designed anywhere in 70-copy-voice.md for
 * this prompt (only the notification text + helper exist; the app never
 * auto-resolves a dirty personal tree, invariant #3, so there is no
 * "commit for me" action to offer). This is a pure, non-destructive
 * disclosure affordance (reveal which files, so Bob can go handle it in his
 * own tools) — left INERT in `render/bob_lane.ts`, same "no invented flow"
 * convention `popover.ts` already uses for every unwired action label.
 */
export const BOB_DIRTY_WIP_ACTION_LABEL = "Show me…";

/**
 * § F — the security auto-suspend line, Bob's dropdown-only copy. Deliberately
 * DROPS the source deck's trailing "Re-affirm your version ▸" affordance:
 * `BobNotice` (this task's frozen data contract) has no action field by
 * design — the closed-set principle (SOUL Principle 2) restricts Bob's only
 * two ACTIONABLE prompts to his own sign-in and his own dirty WIP; a
 * re-affirm control on an auto-acted security event would be exactly the
 * "security-approval control" this task's Scope explicitly forbids adding.
 * Flagged here (not silently trimmed) for design/cw reconciliation against
 * the source deck's link.
 */
export const BOB_KEPT_YOU_SAFE = "Kept you safe — a security fix replaced a component you'd overridden.";
/** Errors microcopy table, "Bad self-update (E14)" Bob row — verbatim. */
export const BOB_KEPT_YOUR_WORKING_VERSION =
  "Kept your working version — an update didn't start cleanly, so I rolled it back. Nothing broke.";

/** PLACEHOLDER — the honest notification-denied-fallback affordance (E12/US-B16); no exact string exists in 70-copy-voice.md for this specific line. Short, factual, no alarm. */
export const BOB_NOTIFICATIONS_DENIED_NOTE = "Notifications are off — showing this here instead.";

/** VoiceOver label for the Bob-lane prompt — title + detail read as one announcement, same pattern `updateSectionLabel` uses. */
export function bobPromptLabel(prompt: BobPrompt): string {
  return `${prompt.title} ${prompt.detail}`.trim();
}

/** VoiceOver label for one quiet past-tense notice — informational, so the label is just its own message (no action to describe, a11y rule 2's "plain-language effect" clause doesn't apply when there is none). */
export function bobNoticeLabel(notice: BobNotice): string {
  return notice.message;
}

/** The one honest announcement for a `BobLaneView` snapshot, passed to the shared live region exactly like `announce(liveRegion, state.header.sentence)` elsewhere. `null` when there is nothing to say (silence-is-success). */
export function bobLaneAnnouncement(state: BobLaneView): string | null {
  if (state.prompt) return bobPromptLabel(state.prompt);
  if (state.notices.length > 0) return state.notices.map(bobNoticeLabel).join(" ");
  return null;
}
