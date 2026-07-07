/**
 * First-run wizard screen (M3 S7, `.copilot/wp/15.md` §2 S7). Vanilla-TS, no
 * framework, driven entirely by a `WizardState` snapshot — render-only, same
 * discipline as `popover.ts`/`settings.ts` (invariant #1 parse-never-compute:
 * this module renders phases/steps/sign-in status Rust already decided, it
 * never computes a verdict, never guesses at progress, never fabricates a
 * "done").
 *
 * Screen selection is driven by `state.mode` + `state.phase` only:
 *   - `mode: "managed"` (until `teach`/`done`/`holding`) → the silent progress
 *     spectator (Flow 1) — 0 questions, ever.
 *   - `mode: "unmanaged"`, `phase: "welcome"` → the Welcome screen (Flow 2 step 1).
 *   - `phase: "question"` → whichever `steps[]` entry is first `done: false`,
 *     rendered by its `kind`. **Step ORDER is entirely data-driven** — this
 *     module never hardcodes "products before layer-setup before sign-in";
 *     it renders steps in whatever order `state.steps` lists them, which is
 *     how the task brief's ChooseProducts → LayerSetup → SignIn ordering is
 *     expressed without hardcoding it (parse-never-compute applied to flow
 *     order, not just to state).
 *   - `phase` ∈ {detect, materialize, verify} → the same progress spectator
 *     (B2: "Progress — reuse B1 phase lines").
 *   - `phase: "teach"` or `"done"` → the same quiet completion panel (B3) —
 *     the design doesn't distinguish them visually; `done`/`complete` only
 *     matters for whether the app is about to close the window, which this
 *     render module has no say in.
 *   - `phase: "holding"` → one honest holding screen. `WizardPhaseTag`'s
 *     `"holding"` deliberately carries no reason sub-tag (IT-config-incomplete
 *     / waiting-for-network / a non-Healthy verify result are all the same
 *     tag) — `WizardState.error` IS the already-honest plain-language
 *     sentence, rendered verbatim as the screen's top line, never
 *     re-categorized by a keyword guess (that would be a small compute this
 *     module has no business doing).
 *
 * A11y: full keyboard operability (native controls throughout — checkbox,
 * radio, readonly input, button — no custom widget re-invents a native one);
 * the device-flow code is a `readonly` text `<input>` so Cmd+A/Cmd+C copy it
 * without any custom selection JS, and it receives focus when its screen
 * first renders (a11y §4's documented tab order: "focus lands on the code").
 * Every screen's heading is the one thing announced to the live region on a
 * fixture switch, mirroring `popover.ts`'s `announce(liveRegion, ...)` pattern.
 */
import { renderBadge } from "./badges";
import * as copy from "./copy";
import { announce } from "./a11y";
import { h } from "./dom";
import type { WizardLayerSlot, WizardProductOption, WizardState, WizardStep } from "../types";

/** Mirrors the real `wizard_set_layers` command's argument shape exactly (product id -> repo URL, always personal-tier). */
export interface LayerSetupSubmission {
  repo_urls: Record<string, string>;
}

/**
 * Every UI-triggered effect this screen can ask the host to perform. All
 * optional — the dev-fixture harness wires every one of them (mutating its
 * local fixture copy, mirroring `settings-main.ts`'s `mockSaveSettings`
 * precedent); a real `runTauri()` host wires them to the S6 IPC surface
 * (`answer_question`/`start_signin`) once it lands (S8).
 */
export interface WizardHandlers {
  onContinueWelcome?: () => void;
  onContinueProducts?: (selectedIds: string[]) => void;
  onSubmitLayerSetup?: (submission: LayerSetupSubmission) => void;
  onStartSignin?: () => void;
  onRetrySignin?: () => void;
  onDismissTeach?: () => void;
}

function findCurrentStep(state: WizardState): WizardStep | undefined {
  return state.steps.find((s) => !s.done);
}

function buildHeader(): HTMLElement {
  const header = h("header", { className: "ct-wizard__header" });
  header.appendChild(h("p", { className: "ct-wizard__brand", text: copy.WIZARD_WINDOW_TITLE }));
  return header;
}

function buildLargeBadge(shape: Parameters<typeof renderBadge>[0], animate: boolean): HTMLElement {
  const wrap = h("div", { className: "ct-wizard__badge-lg" });
  wrap.appendChild(renderBadge(shape, { animate }));
  return wrap;
}

function buildWelcome(handlers: WizardHandlers): HTMLElement {
  const body = h("div", { className: "ct-wizard__body", attrs: { role: "group", "aria-label": copy.WELCOME_TITLE } });
  body.appendChild(h("h1", { className: "ct-wizard__title", text: copy.WELCOME_TITLE }));
  body.appendChild(h("p", { className: "ct-wizard__subhead", text: copy.WELCOME_BODY }));
  const btn = h("button", { className: "ct-primary-action", text: copy.WELCOME_CONTINUE_LABEL });
  btn.type = "button";
  btn.addEventListener("click", () => handlers.onContinueWelcome?.());
  body.appendChild(btn);
  return body;
}

/** B1/B2 — the shared progress spectator. No percentage, no ETA (ADR-M3-003) — an indeterminate activity bar only. */
function buildProgress(state: WizardState): HTMLElement {
  const body = h("div", { className: "ct-wizard__body ct-wizard__progress", attrs: { role: "status" } });
  body.appendChild(buildLargeBadge("ring", true));
  body.appendChild(h("h1", { className: "ct-wizard__title", text: state.phase_label }));
  if (state.mode === "managed") {
    body.appendChild(h("p", { className: "ct-wizard__subhead", text: copy.PROGRESS_SUBHEAD_MANAGED }));
  }
  const track = h("div", { className: "ct-wizard__progress-track", attrs: { "aria-hidden": "true" } });
  track.appendChild(h("div", { className: "ct-wizard__progress-fill" }));
  body.appendChild(track);
  return body;
}

function buildTeachDone(handlers: WizardHandlers): HTMLElement {
  const body = h("div", { className: "ct-wizard__body", attrs: { role: "group", "aria-label": copy.TEACH_TITLE } });
  body.appendChild(h("h1", { className: "ct-wizard__title", text: copy.TEACH_TITLE }));
  body.appendChild(h("p", { className: "ct-wizard__subhead", text: copy.TEACH_BODY }));

  const actions = h("div", { className: "ct-wizard__teach-actions" });
  [copy.TEACH_ACTION_CHEATSHEET, copy.TEACH_ACTION_ADD_SKILL].forEach((label) => {
    const btn = h("button", { className: "ct-wizard__secondary-action", text: label });
    btn.type = "button";
    actions.appendChild(btn);
  });
  body.appendChild(actions);

  const backup = h("div", { className: "ct-wizard__teach-backup" });
  backup.appendChild(h("p", { className: "ct-wizard__note", text: copy.TEACH_BACKUP_BODY }));
  const backupBtn = h("button", { className: "ct-wizard__secondary-action", text: copy.TEACH_ACTION_BACKUP });
  backupBtn.type = "button";
  backup.appendChild(backupBtn);
  body.appendChild(backup);

  const dismiss = h("button", { className: "ct-primary-action", text: copy.TEACH_DISMISS });
  dismiss.type = "button";
  dismiss.addEventListener("click", () => handlers.onDismissTeach?.());
  body.appendChild(dismiss);

  return body;
}

/** B4 — one honest holding screen. `state.error` is rendered verbatim as the top line; see module doc for why no reason sub-tag is inferred. */
function buildHolding(state: WizardState): HTMLElement {
  const body = h("div", { className: "ct-wizard__body", attrs: { role: "status" } });
  body.appendChild(buildLargeBadge("hollow", true));
  body.appendChild(h("h1", { className: "ct-wizard__title", text: state.error ?? copy.HOLDING_TITLE_GENERIC }));
  return body;
}

function buildProductRow(product: WizardProductOption, onToggle: (id: string, checked: boolean) => void): HTMLElement {
  const row = h("label", { className: "ct-wizard__checkbox-row" });
  if (!product.pre_checked) row.classList.add("ct-wizard__checkbox-row--disabled");

  const input = h("input", {
    attrs: {
      type: "checkbox",
      "aria-label": product.label,
    },
  });
  // pre_checked doubles as the narrow-not-widen ceiling (ADR-M3-005,
  // confirmed against `unmanaged_flow::ProductOption`): Bob may uncheck a
  // granted product, never check one the ecosystem didn't already grant.
  input.checked = product.pre_checked;
  input.disabled = !product.pre_checked;
  input.addEventListener("change", () => onToggle(product.id, input.checked));

  row.appendChild(input);
  row.appendChild(h("span", { className: "ct-wizard__checkbox-label", text: product.label }));
  if (!product.pre_checked) {
    row.appendChild(h("span", { className: "ct-wizard__checkbox-note", text: copy.SETTINGS_NOT_SET_UP }));
  }
  return row;
}

function buildChooseProducts(step: WizardStep, handlers: WizardHandlers): HTMLElement {
  const options = step.products ?? [];
  const selected = new Set(options.filter((p) => p.pre_checked).map((p) => p.id));

  const body = h("div", { className: "ct-wizard__body" });
  body.appendChild(h("h1", { className: "ct-wizard__title", text: step.prompt || copy.PRODUCTS_TITLE }));
  body.appendChild(h("p", { className: "ct-wizard__subhead", text: copy.PRODUCTS_BODY }));

  const fieldset = h("fieldset", { className: "ct-wizard__fieldset" });
  fieldset.appendChild(h("legend", { className: "ct-wizard__legend", text: copy.SECTION_PRODUCTS }));
  options.forEach((p) => {
    fieldset.appendChild(
      buildProductRow(p, (id, checked) => {
        if (checked) selected.add(id);
        else selected.delete(id);
      }),
    );
  });
  body.appendChild(fieldset);

  const btn = h("button", { className: "ct-primary-action", text: copy.CONTINUE_LABEL });
  btn.type = "button";
  btn.addEventListener("click", () => handlers.onContinueProducts?.(Array.from(selected)));
  body.appendChild(btn);

  return body;
}

function buildLayerRow(slot: WizardLayerSlot, index: number): { el: HTMLElement; input: HTMLInputElement } {
  const fieldId = `ct-wizard-layer-${index}`;
  const row = h("div", { className: "ct-wizard__row" });
  const line = h("div", { className: "ct-wizard__row-line" });
  // Always personal-tier in this flow (confirmed against
  // `UnmanagedFlow::set_layers` — see `WizardLayerSlot`'s doc), so the row
  // label is just the product name, not a product+layer pair.
  const label = h("label", {
    className: "ct-wizard__row-label",
    text: copy.PRODUCT_LABEL[slot.product] ?? slot.product,
    attrs: { for: fieldId },
  });
  const input = h("input", {
    className: "ct-wizard__row-input",
    attrs: {
      type: "text",
      id: fieldId,
      value: slot.repo_url,
      placeholder: copy.SETTINGS_ROW_PLACEHOLDER,
      autocomplete: "off",
      spellcheck: "false",
    },
  });
  line.append(label, input);
  row.appendChild(line);
  return { el: row, input };
}

function buildLayerSetup(step: WizardStep, handlers: WizardHandlers): HTMLElement {
  const body = h("div", { className: "ct-wizard__body" });
  body.appendChild(h("h1", { className: "ct-wizard__title", text: step.prompt || copy.LAYER_SETUP_TITLE }));

  const rowInputs: { product: string; input: HTMLInputElement }[] = [];

  const layers = step.layers ?? [];
  if (layers.length > 0) {
    const fieldset = h("fieldset", { className: "ct-wizard__fieldset" });
    fieldset.appendChild(h("legend", { className: "ct-wizard__legend", text: copy.LAYER_SETUP_REPOS_LEGEND }));
    layers.forEach((slot, i) => {
      const { el, input } = buildLayerRow(slot, i);
      fieldset.appendChild(el);
      rowInputs.push({ product: slot.product, input });
    });
    body.appendChild(fieldset);
  }

  const btn = h("button", { className: "ct-primary-action", text: copy.CONTINUE_LABEL });
  btn.type = "button";
  btn.addEventListener("click", () => {
    const repoUrls: Record<string, string> = {};
    rowInputs.forEach((r) => {
      const value = r.input.value.trim();
      if (value.length > 0) repoUrls[r.product] = value;
    });
    handlers.onSubmitLayerSetup?.({ repo_urls: repoUrls });
  });
  body.appendChild(btn);

  return body;
}

function buildSignInCode(userCode: string): HTMLInputElement {
  const input = h("input", {
    className: "ct-wizard__code",
    attrs: {
      type: "text",
      value: userCode,
      readonly: "true",
      "aria-readonly": "true",
      "aria-label": "Device sign-in code",
    },
  });
  return input;
}

function buildSignIn(state: WizardState, step: WizardStep, handlers: WizardHandlers, liveRegion: HTMLElement): HTMLElement {
  const signin = state.signin;
  const body = h("div", { className: "ct-wizard__body" });
  body.appendChild(h("h1", { className: "ct-wizard__title", text: step.prompt || copy.SIGNIN_TITLE }));

  if (!signin || signin.status === "idle") {
    body.appendChild(h("p", { className: "ct-wizard__subhead", text: copy.SIGNIN_HELPER }));
    const btn = h("button", { className: "ct-primary-action", text: copy.SIGNIN_START_LABEL });
    btn.type = "button";
    btn.addEventListener("click", () => handlers.onStartSignin?.());
    body.appendChild(btn);
    return body;
  }

  if (signin.status === "denied" || signin.status === "expired" || signin.status === "timeout") {
    body.appendChild(buildLargeBadge("key", false));
    body.appendChild(h("p", { className: "ct-wizard__subhead", text: copy.SIGNIN_FAILURE[signin.status] }));
    const retry = h("button", { className: "ct-primary-action", text: copy.SIGNIN_RETRY_LABEL });
    retry.type = "button";
    retry.addEventListener("click", () => handlers.onRetrySignin?.());
    body.appendChild(retry);
    return body;
  }

  if (signin.status === "authorized") {
    body.appendChild(h("p", { className: "ct-wizard__subhead", text: copy.SIGNIN_SUCCESS }));
    return body;
  }

  // "pending" — the spinner state, not a failure.
  body.appendChild(h("p", { className: "ct-wizard__subhead", text: copy.SIGNIN_BODY }));

  const codeRow = h("div", { className: "ct-wizard__code-row" });
  const codeInput = buildSignInCode(signin.user_code ?? "");
  const copyBtn = h("button", { className: "ct-wizard__secondary-action", text: copy.SIGNIN_COPY_LABEL });
  copyBtn.type = "button";
  copyBtn.addEventListener("click", () => {
    codeInput.select();
    void navigator.clipboard
      ?.writeText(codeInput.value)
      .then(() => announce(liveRegion, copy.SIGNIN_COPIED_ANNOUNCEMENT))
      .catch(() => {
        /* clipboard permission unavailable — the value is still selected for a manual Cmd+C */
      });
  });
  codeRow.append(codeInput, copyBtn);
  body.appendChild(codeRow);

  if (signin.verification_uri) {
    const openBtn = h("a", {
      className: "ct-wizard__secondary-action",
      text: copy.SIGNIN_OPEN_BROWSER_LABEL,
      attrs: { href: signin.verification_uri, target: "_blank", rel: "noreferrer noopener" },
    });
    body.appendChild(openBtn);
  }

  body.appendChild(buildLargeBadge("ring", true));
  body.appendChild(h("p", { className: "ct-wizard__note", text: copy.SIGNIN_WAITING }));
  body.appendChild(h("p", { className: "ct-wizard__note", text: copy.SIGNIN_HELPER }));

  // a11y §4: focus lands on the device-flow code, keyboard-copyable (Cmd+A/Cmd+C on a readonly input).
  queueMicrotask(() => {
    codeInput.focus();
    codeInput.select();
  });

  return body;
}

function buildQuestion(state: WizardState, handlers: WizardHandlers, liveRegion: HTMLElement): HTMLElement {
  const step = findCurrentStep(state);
  if (!step) return buildProgress(state);
  switch (step.kind) {
    case "choose-products":
      return buildChooseProducts(step, handlers);
    case "layer-setup":
      return buildLayerSetup(step, handlers);
    case "sign-in":
      return buildSignIn(state, step, handlers, liveRegion);
  }
}

function screenAnnouncement(state: WizardState): string {
  if (state.phase === "holding") return state.error ?? copy.HOLDING_TITLE_GENERIC;
  if (state.phase === "teach" || state.phase === "done") return copy.TEACH_TITLE;
  if (state.mode === "managed" && state.phase !== "welcome") return state.phase_label;
  if (state.phase === "question") {
    const step = findCurrentStep(state);
    return step?.prompt || state.phase_label;
  }
  return state.phase_label;
}

/**
 * Renders the whole wizard into `container` from a `WizardState` snapshot.
 * `liveRegion` receives the current screen's heading (a11y rule 3, same
 * convention `popover.ts`/`settings.ts` use).
 */
export function renderWizard(
  container: HTMLElement,
  liveRegion: HTMLElement,
  state: WizardState,
  handlers: WizardHandlers,
): void {
  container.replaceChildren();

  const shell = h("div", { className: "ct-wizard" });
  shell.appendChild(buildHeader());

  if (state.phase === "holding") {
    shell.appendChild(buildHolding(state));
  } else if (state.phase === "teach" || state.phase === "done") {
    shell.appendChild(buildTeachDone(handlers));
  } else if (state.mode === "managed") {
    shell.appendChild(buildProgress(state));
  } else if (state.phase === "welcome") {
    shell.appendChild(buildWelcome(handlers));
  } else if (state.phase === "question") {
    shell.appendChild(buildQuestion(state, handlers, liveRegion));
  } else {
    shell.appendChild(buildProgress(state));
  }

  container.appendChild(shell);
  announce(liveRegion, screenAnnouncement(state));
}
