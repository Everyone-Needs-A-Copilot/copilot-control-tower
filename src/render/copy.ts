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
import type { BadgeState, CliStatus, DeptProjectView, Layer, LayerView, ProductView } from "../types";

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
