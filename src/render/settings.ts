/**
 * Settings screen — product-first repo-URL authoring form (M2 S7,
 * `.copilot/wp/5.md` ADR-M2-004: the unmanaged/solo/author surface, reached
 * behind Bob's separately-designed Preferences). Vanilla-TS, no framework,
 * consumes only `SettingsState` and only ever *renders* it — no validation
 * logic ships here (invariant #1 parse-never-compute; validity is entirely
 * `FieldError.message`, plain-language, from the DTO).
 *
 * Fixed 4 products x 3 authorable tiers (org/dept/personal — Settings never
 * authors `foundation`) are always rendered as a slot, whether or not a
 * `LayerRow` exists for that slot yet: an unfilled slot is the honest
 * "Not set up yet" state, not a hidden/absent one. This doubles as the
 * empty/first-time state (zero `LayerRow`s -> every slot renders empty) and
 * keeps the layout stable as rows get filled in one at a time.
 */
import { renderBadge } from "./badges";
import * as copy from "./copy";
import { announce } from "./a11y";
import { h } from "./dom";
import type { FieldError, LayerInput, LayerRow, SettingsState, Tier } from "../types";

/**
 * Product grouping order. `LayerRow.product` is config-driven in the engine
 * (`docs/reference/four-tier-topology.md`: "knowledge|cli|claude|codex + more"),
 * but the S7 task brief scopes this UI to the 4 named products explicitly
 * ("per product (Knowledge / CLI / Claude / Codex)"); this fixed order is a
 * deliberate scope boundary, not a claim that the engine can't carry more.
 * Local to this module (S8): nothing outside `settings.ts` needs it, so it
 * isn't part of the shared `types.ts` DTO mirror.
 */
const PRODUCT_ORDER = ["knowledge", "cli", "claude", "codex"] as const;

/** Fixed render order for the three Settings-authorable tiers (`Tier`, `types.ts`). */
const TIER_ORDER: Tier[] = ["org", "dept", "personal"];

function rowFieldId(product: string, tier: Tier): string {
  return `settings-${product}-${tier}`;
}

function findRow(layers: LayerRow[], product: string, tier: Tier): LayerRow | undefined {
  return layers.find((l) => l.product === product && l.tier === tier);
}

/** Every problem not attributable to one row (`layer_id === null`) — a manifest-wide banner. */
function manifestErrors(errors: FieldError[]): FieldError[] {
  return errors.filter((e) => e.layer_id === null);
}

/** First error attributed to this row's layer id, if any (a row only ever has one editable field: `repo_url`). */
function findError(errors: FieldError[], layerId: string | undefined): FieldError | undefined {
  if (!layerId) return undefined;
  return errors.find((e) => e.layer_id === layerId);
}

/**
 * Whether a slot accepts input right now. An EXISTING row's own `editable`
 * flag wins (Rust-decided — the managed gate, D-2-M2). A slot with no row
 * yet is a fresh, never-authored layer: personal is always creatable; org/
 * dept are only creatable when the machine is unmanaged (mirrors D-2-M2's
 * "only personal editable on a managed machine" for the not-yet-existing
 * case too — a managed machine's org/dept manifest comes from `cc derive`,
 * never a pasted URL, whether or not a row already exists).
 */
function isRowEditable(row: LayerRow | undefined, tier: Tier, managed: boolean): boolean {
  if (row) return row.editable;
  if (tier === "personal") return true;
  return !managed;
}

function buildInput(opts: {
  fieldId: string;
  value: string;
  editable: boolean;
  ariaLabel: string;
  describedBy: string[];
  invalid: boolean;
}): HTMLInputElement {
  const attrs: Record<string, string> = {
    type: "text",
    id: opts.fieldId,
    name: opts.fieldId,
    value: opts.value,
    placeholder: copy.SETTINGS_ROW_PLACEHOLDER,
    autocomplete: "off",
    spellcheck: "false",
    "aria-label": opts.ariaLabel,
  };
  if (!opts.editable) {
    // `readonly`, not `disabled` — stays focusable and announced by AT
    // (a11y rule: never remove a control from the accessibility tree just
    // to lock it; the honest "Managed by your IT admin" note explains why).
    attrs.readonly = "true";
    attrs["aria-readonly"] = "true";
  }
  if (opts.invalid) attrs["aria-invalid"] = "true";
  if (opts.describedBy.length > 0) attrs["aria-describedby"] = opts.describedBy.join(" ");
  return h("input", { className: "ct-settings-row__input", attrs });
}

function buildRow(product: string, tier: Tier, state: SettingsState): HTMLElement {
  const row = findRow(state.layers, product, tier);
  const editable = isRowEditable(row, tier, state.managed);
  const managedLocked = !editable && state.managed;
  const value = row?.repo_url ?? "";
  // Honest reading of "needs sign-in": a row that HAS a repo URL but no auth
  // reference yet. A slot with no URL at all is "not set up", a distinct
  // state. `auth_ref`/`repo_url` are non-null `string`s on the wire (S6/S8);
  // Rust projects a missing value to `""`, never `null`, so an empty string
  // IS the "not configured" sentinel for both fields.
  const needsSignIn = Boolean(row?.repo_url) && !row?.auth_ref;
  const error = findError(state.errors, row?.id);
  const fieldId = rowFieldId(product, tier);
  const errorId = `${fieldId}-error`;
  const noteId = `${fieldId}-note`;

  const describedBy: string[] = [];
  if (error) describedBy.push(errorId);
  if (managedLocked || needsSignIn || (!value && editable)) describedBy.push(noteId);

  const ariaLabel = copy.settingsRowLabel({
    product,
    tier,
    editable,
    managed: state.managed,
    hasValue: Boolean(value),
    needsSignIn,
    errorMessage: error?.message ?? null,
  });

  const wrap = h("div", { className: "ct-settings-row" });
  wrap.dataset.tier = tier;
  wrap.dataset.product = product;

  const line = h("div", { className: "ct-settings-row__line" });
  const label = h("label", {
    className: "ct-settings-row__label",
    text: copy.LAYER_LABEL[tier],
    attrs: { for: fieldId },
  });
  const input = buildInput({ fieldId, value, editable, ariaLabel, describedBy, invalid: Boolean(error) });
  line.append(label, input);
  wrap.appendChild(line);

  if (managedLocked) {
    wrap.appendChild(h("p", { className: "ct-settings-row__note", text: copy.SETTINGS_MANAGED_NOTE, attrs: { id: noteId } }));
  } else if (needsSignIn) {
    const note = h("p", { className: "ct-settings-row__note ct-settings-row__note--signin", attrs: { id: noteId } });
    note.appendChild(renderBadge("key"));
    note.appendChild(document.createTextNode(` ${copy.SETTINGS_NEEDS_SIGN_IN}`));
    wrap.appendChild(note);
  } else if (!value && editable) {
    wrap.appendChild(
      h("p", { className: "ct-settings-row__note ct-settings-row__note--empty", text: copy.SETTINGS_NOT_SET_UP, attrs: { id: noteId } }),
    );
  }

  if (error) {
    wrap.appendChild(
      h("p", { className: "ct-settings-row__error", text: error.message, attrs: { id: errorId, role: "alert" } }),
    );
  }

  return wrap;
}

function buildProductGroup(product: string, state: SettingsState): HTMLElement {
  const fieldset = h("fieldset", { className: "ct-settings-group" });
  fieldset.appendChild(
    h("legend", { className: "ct-settings-group__legend", text: copy.PRODUCT_LABEL[product] ?? product }),
  );
  TIER_ORDER.forEach((tier) => fieldset.appendChild(buildRow(product, tier, state)));
  return fieldset;
}

/** Reads the CURRENT (possibly user-edited) value of every editable slot from the live form. */
function collectEditableInputs(form: HTMLFormElement, state: SettingsState): LayerInput[] {
  const inputs: LayerInput[] = [];
  PRODUCT_ORDER.forEach((product) => {
    TIER_ORDER.forEach((tier) => {
      const row = findRow(state.layers, product, tier);
      if (!isRowEditable(row, tier, state.managed)) return;
      const field = form.querySelector<HTMLInputElement>(`#${CSS.escape(rowFieldId(product, tier))}`);
      const repoUrl = field?.value.trim() ?? "";
      if (!repoUrl) return; // nothing pasted for this slot — don't submit an empty write
      inputs.push({ product, tier, repo_url: repoUrl });
    });
  });
  return inputs;
}

/**
 * A problem not attributable to any one row — e.g. the manifest couldn't be
 * read at all, or the config pointer failed to update after a save
 * (`commands::save_settings_at`'s `home_dir_unavailable_error` / the
 * `"manifest"`/`"pointer"` field errors). Rendered as a single honest,
 * plain-language banner (`FieldError.message` verbatim — never a raw git/
 * yaml/io string, invariant #1) rather than silently dropped, which is what
 * would happen if this screen only ever looked at per-row errors.
 */
function buildManifestErrorBanner(errors: FieldError[]): HTMLElement {
  const banner = h("div", { className: "ct-settings-banner", attrs: { role: "alert" } });
  banner.appendChild(renderBadge("bang"));
  const messages = h("div", { className: "ct-settings-banner__messages" });
  errors.forEach((e) => messages.appendChild(h("p", { className: "ct-settings-banner__message", text: e.message })));
  banner.appendChild(messages);
  return banner;
}

/**
 * Renders the Settings form into `container` from a `SettingsState` snapshot.
 * `onSave` receives exactly the `LayerInput[]` the `save_settings` IPC
 * command's contract expects (S6) — this module never decides validity, only
 * collects what the user typed.
 */
export function renderSettings(
  container: HTMLElement,
  state: SettingsState,
  onSave: (inputs: LayerInput[]) => void,
): void {
  container.replaceChildren();

  const header = h("header", { className: "ct-settings-header" });
  header.appendChild(h("h1", { className: "ct-settings-title", text: copy.SETTINGS_TITLE }));
  container.appendChild(header);

  const manifestLevelErrors = manifestErrors(state.errors);
  if (manifestLevelErrors.length > 0) {
    container.appendChild(buildManifestErrorBanner(manifestLevelErrors));
  }

  // A manifest that failed to read (a banner above) is a DIFFERENT honest
  // state from "nothing configured yet" — showing both would read as a
  // contradiction ("here's an error" + "paste a URL to get started").
  if (state.layers.length === 0 && manifestLevelErrors.length === 0) {
    container.appendChild(h("p", { className: "ct-settings-empty", text: copy.SETTINGS_EMPTY_STATE }));
  }

  const form = h("form", { className: "ct-settings-form", attrs: { "aria-label": copy.SETTINGS_TITLE } });
  PRODUCT_ORDER.forEach((product) => form.appendChild(buildProductGroup(product, state)));

  const saveBtn = h("button", { className: "ct-primary-action ct-settings-save", text: copy.SETTINGS_SAVE_LABEL });
  saveBtn.type = "submit";
  form.appendChild(saveBtn);

  form.addEventListener("submit", (evt) => {
    evt.preventDefault();
    onSave(collectEditableInputs(form, state));
  });

  container.appendChild(form);
}

/**
 * Explicit post-action announce (a11y rule 3), separate from `renderSettings`
 * itself so an initial `get_settings()` load stays silent (P1 "silence is
 * the success state") — only call this after a `save_settings` round trip.
 */
export function announceSettingsResult(liveRegion: HTMLElement, state: SettingsState): void {
  if (state.errors.length > 0) {
    announce(liveRegion, copy.settingsErrorsAnnouncement(state.errors.length));
  } else {
    announce(liveRegion, copy.SETTINGS_SAVED_ANNOUNCEMENT);
  }
}
