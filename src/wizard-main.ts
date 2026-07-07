/**
 * First-run wizard entry point (M3 S7, wired live in S8). Mirrors
 * `main.ts`/`settings-main.ts`'s IPC-seam shape (get-snapshot-on-open,
 * dev-fixture harness outside a Tauri host) — but, UNLIKE those two,
 * `runTauri()` below calls a REAL, already-landed Rust command surface:
 * `get_wizard_state`/`get_wizard_product_catalog`/`wizard_advance`/
 * `wizard_choose_products`/`wizard_set_layers`/`wizard_begin_signin`/
 * `wizard_poll_signin` (`types.ts`'s `*_CMD` constants). There is no event
 * stream — every command returns the fresh `WizardState` directly, so
 * `runTauri()` re-renders from each command's own return value.
 *
 * **The product-catalog gap is closed (S8):** `get_wizard_product_catalog()`
 * is a real command now (a thin passthrough to `unmanaged_flow::
 * default_product_catalog()`) — `runTauri()` fetches it once on startup and
 * threads it through `augment()` below, rather than keeping a second,
 * hardcoded mirror that could silently drift from the real Rust catalog.
 * `lastSelectedProducts` remains this module's own memory of what Bob just
 * checked in Q1 (the real DTO has no server-side notion of "which products
 * need a repo-URL row" — see `types.ts`'s `WizardStep.layers` doc), used
 * only to decide which repo-URL rows Q2 needs; never sent anywhere, never
 * substituted for a server fact.
 */
import { invoke } from "@tauri-apps/api/core";
import { renderWizard, type LayerSetupSubmission, type WizardHandlers } from "./render/wizard";
import { ensureLiveRegion } from "./render/a11y";
import { isTauriHost } from "./tauri-host";
import {
  GET_WIZARD_PRODUCT_CATALOG_CMD,
  GET_WIZARD_STATE_CMD,
  WIZARD_ADVANCE_CMD,
  WIZARD_BEGIN_SIGNIN_CMD,
  WIZARD_CHOOSE_PRODUCTS_CMD,
  WIZARD_POLL_SIGNIN_CMD,
  WIZARD_SET_LAYERS_CMD,
  type WizardProductOption,
  type WizardState,
} from "./types";

const appElOrNull = document.getElementById("app");
if (!appElOrNull) {
  throw new Error("Copilot Control Tower Setup: #app root missing from wizard.html");
}
const appEl: HTMLElement = appElOrNull;

const liveRegion = ensureLiveRegion(document.body);

/**
 * Fallback poll cadence, in milliseconds — used ONLY if the backend somehow
 * omits `signin_interval_secs` (a defensive floor, never the normal path;
 * the real cadence always comes from `WizardState.signin_interval_secs`,
 * S8's contract-gap fix). Never rendered to Bob — consumed solely as a
 * `setInterval` argument (see `types.ts`'s doc on why this isn't an ETA).
 */
const FALLBACK_SIGNIN_POLL_MS = 3000;

/**
 * How often to poll `get_wizard_state` while a managed silent run is in
 * flight (M3 QA follow-up D3 — "the progress spectator never streams live
 * phase data"). `wizard_advance` doesn't resolve until the ENTIRE managed
 * flow reaches its terminal phase (it's one blocking backend call), but the
 * backend now pushes each intermediate phase into the SAME `WizardIpcState`
 * `get_wizard_state` reads from AS IT ADVANCES — so a concurrent poll here
 * observes real progress instead of only the final phase. A fixed cadence,
 * never rendered to Bob, never a countdown/ETA (`ADR-M3-003`) — consumed
 * solely as a `setInterval` argument, same discipline as
 * `FALLBACK_SIGNIN_POLL_MS` above.
 */
const MANAGED_PROGRESS_POLL_MS = 1000;

/** How often to poll `wizard_poll_signin`, honestly derived from the CLI's own ceremony cadence rather than a client-side guess. */
function signinPollIntervalMs(state: WizardState): number {
  return state.signin_interval_secs != null
    ? state.signin_interval_secs * 1000
    : FALLBACK_SIGNIN_POLL_MS;
}

/** Augments a fresh `WizardState` with this module's own UI-side extension fields before rendering — never overwrites anything Rust actually sent. */
function augment(
  state: WizardState,
  lastSelectedProducts: string[] | null,
  productCatalog: WizardProductOption[],
): WizardState {
  const steps = state.steps.map((step) => {
    if (step.kind === "choose-products" && !step.products) {
      return { ...step, products: productCatalog };
    }
    if (step.kind === "layer-setup" && !step.layers && lastSelectedProducts) {
      return {
        ...step,
        layers: lastSelectedProducts.map((product) => ({ product, repo_url: "" })),
      };
    }
    return step;
  });
  return { ...state, steps };
}

async function runTauri(): Promise<void> {
  let lastSelectedProducts: string[] | null = null;
  let signinPollTimer: ReturnType<typeof setInterval> | null = null;
  let managedProgressPollTimer: ReturnType<typeof setInterval> | null = null;
  // Bumped whenever a managed poll cycle starts/stops — guards against a
  // poll tick's `invoke()` call that was ALREADY in flight when
  // `wizard_advance` resolved from rendering a stale intermediate phase
  // *after* the final terminal render (a narrow, honest-but-out-of-order
  // race: `clearInterval` only stops future ticks, not an already-sent
  // request). Never a fabricated state either way — worst case without this
  // guard would be a real PAST phase briefly overwriting the real FINAL one.
  let managedProgressGeneration = 0;

  // Fetched once, up front — the REAL catalog (S8), never a client-side
  // mirror that could drift from `unmanaged_flow::default_product_catalog()`.
  const productCatalog = await invoke<WizardProductOption[]>(GET_WIZARD_PRODUCT_CATALOG_CMD);

  function stopSigninPoll(): void {
    if (signinPollTimer !== null) {
      clearInterval(signinPollTimer);
      signinPollTimer = null;
    }
  }

  function renderCurrent(state: WizardState): void {
    renderWizard(appEl, liveRegion, augment(state, lastSelectedProducts, productCatalog), handlers);
  }

  function startSigninPoll(state: WizardState): void {
    stopSigninPoll();
    signinPollTimer = setInterval(() => {
      void invoke<WizardState>(WIZARD_POLL_SIGNIN_CMD).then((polled) => {
        if (polled.signin && polled.signin.status !== "pending") stopSigninPoll();
        renderCurrent(polled);
      });
    }, signinPollIntervalMs(state));
  }

  function stopManagedProgressPoll(): void {
    managedProgressGeneration += 1;
    if (managedProgressPollTimer !== null) {
      clearInterval(managedProgressPollTimer);
      managedProgressPollTimer = null;
    }
  }

  /**
   * Polls `get_wizard_state` while the managed silent run is in flight (S8/
   * M3 QA follow-up D3 — see `MANAGED_PROGRESS_POLL_MS`'s own doc). Started
   * the moment a managed `wizard_advance` is kicked off; stopped either when
   * that call resolves (the run reached its terminal phase) or the instant a
   * poll itself observes a terminal phase (`done`/`holding`) — whichever
   * happens first, so this never keeps polling past the phase the UI is
   * already showing. Each tick captures the CURRENT generation and only
   * renders if it's still current when its `invoke()` resolves — guards
   * against a tick's request that was already in flight the instant
   * `wizard_advance` itself resolved from briefly re-showing a stale (but
   * real, never fabricated) intermediate phase after the final render.
   */
  function startManagedProgressPoll(): void {
    stopManagedProgressPoll();
    const generation = managedProgressGeneration;
    managedProgressPollTimer = setInterval(() => {
      void invoke<WizardState>(GET_WIZARD_STATE_CMD).then((polled) => {
        if (generation !== managedProgressGeneration) return;
        renderCurrent(polled);
        if (polled.phase === "done" || polled.phase === "holding") stopManagedProgressPoll();
      });
    }, MANAGED_PROGRESS_POLL_MS);
  }

  const handlers: WizardHandlers = {
    onContinueWelcome: () => void invoke<WizardState>(WIZARD_ADVANCE_CMD).then(renderCurrent),
    onContinueProducts: (selectedIds) => {
      lastSelectedProducts = selectedIds;
      void invoke<WizardState>(WIZARD_CHOOSE_PRODUCTS_CMD, { products: selectedIds }).then(renderCurrent);
    },
    onSubmitLayerSetup: (submission: LayerSetupSubmission) =>
      void invoke<WizardState>(WIZARD_SET_LAYERS_CMD, { inputs: submission.repo_urls })
        // All 3 questions may now be answered — `wizard_advance` is the only
        // trigger that actually runs the materialize+verify tail (S6);
        // idempotent/a no-op otherwise, so it's always safe to call.
        .then(() => invoke<WizardState>(WIZARD_ADVANCE_CMD))
        .then(renderCurrent),
    onStartSignin: () =>
      void invoke<WizardState>(WIZARD_BEGIN_SIGNIN_CMD).then((state) => {
        renderCurrent(state);
        startSigninPoll(state);
      }),
    onRetrySignin: () =>
      void invoke<WizardState>(WIZARD_BEGIN_SIGNIN_CMD).then((state) => {
        renderCurrent(state);
        startSigninPoll(state);
      }),
    onDismissTeach: () => void invoke<WizardState>(WIZARD_ADVANCE_CMD).then(renderCurrent),
  };

  const initial = await invoke<WizardState>(GET_WIZARD_STATE_CMD);
  renderCurrent(initial);
  // The managed silent path (Flow 1) asks Bob nothing — drive it forward
  // immediately rather than waiting on a Welcome click that screen never
  // shows (`render/wizard.ts` renders the managed progress spectator for
  // every phase until teach/done/holding). `wizard_advance` doesn't resolve
  // until the WHOLE managed flow reaches its terminal phase, so a concurrent
  // poll (`startManagedProgressPoll`) is what actually surfaces the live
  // phase names in between (M3 QA follow-up D3).
  if (initial.mode === "managed" && initial.phase !== "done" && initial.phase !== "holding") {
    startManagedProgressPoll();
    void invoke<WizardState>(WIZARD_ADVANCE_CMD).then((state) => {
      stopManagedProgressPoll();
      renderCurrent(state);
    });
  }
}

/**
 * DEV-PREVIEW-ONLY mock transitions — exists purely so this session's
 * headless verification can exercise every screen's controls without a live
 * Tauri host (this repo's `vite dev`-only verification constraint). Not a
 * reimplementation of the real wizard state machine (invariant #1) — it only
 * moves the ALREADY-DECLARED `done`/`phase`/`signin` fields forward exactly
 * as far as this screen's own control says, mirroring `settings-main.ts`'s
 * `mockSaveSettings` precedent. Lives entirely inside the tree-shaken DEV
 * branch below — never ships.
 */
function cloneState(state: WizardState): WizardState {
  return JSON.parse(JSON.stringify(state)) as WizardState;
}

const MOCK_CEREMONY = { user_code: "WDJB-MJHT", verification_uri: "https://example.com/device" };

function buildDevHandlers(getState: () => WizardState, render: (s: WizardState) => void): WizardHandlers {
  function currentStep(state: WizardState) {
    return state.steps.find((s) => !s.done);
  }

  return {
    onContinueWelcome: () => {
      const next = cloneState(getState());
      if (next.phase === "welcome") next.phase = "question";
      render(next);
    },
    onContinueProducts: (selectedIds) => {
      const next = cloneState(getState());
      const step = currentStep(next);
      if (step?.kind === "choose-products" && step.products) {
        step.products = step.products.map((p) => ({ ...p, pre_checked: p.pre_checked && selectedIds.includes(p.id) }));
        step.done = true;
      }
      render(next);
    },
    onSubmitLayerSetup: (submission) => {
      const next = cloneState(getState());
      const step = currentStep(next);
      if (step?.kind === "layer-setup" && step.layers) {
        step.layers = step.layers.map((slot) =>
          slot.product in submission.repo_urls ? { ...slot, repo_url: submission.repo_urls[slot.product] } : slot,
        );
        step.done = true;
      }
      render(next);
    },
    onStartSignin: () => {
      const next = cloneState(getState());
      next.signin = { status: "pending", ...MOCK_CEREMONY };
      render(next);
    },
    onRetrySignin: () => {
      const next = cloneState(getState());
      next.signin = { status: "pending", ...MOCK_CEREMONY };
      render(next);
    },
    onDismissTeach: () => {
      const next = cloneState(getState());
      if (next.phase === "teach") {
        next.phase = "done";
        next.complete = true;
      }
      render(next);
    },
  };
}

async function runDevFixtureHarness(): Promise<void> {
  const modules = import.meta.glob<WizardState>("./dev-fixtures/wizard/*.json", {
    eager: true,
    import: "default",
  });

  const fixtures = Object.entries(modules)
    .map(([path, state]) => ({
      name: path.replace("./dev-fixtures/wizard/", "").replace(".json", ""),
      state,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  if (fixtures.length === 0) {
    appEl.textContent = "No wizard dev fixtures found in src/dev-fixtures/wizard/.";
    return;
  }

  const params = new URLSearchParams(window.location.search);
  let index = Math.max(
    0,
    fixtures.findIndex((f) => f.name === params.get("fixture")),
  );

  const harness = document.getElementById("ct-dev-harness");
  let select: HTMLSelectElement | null = null;

  if (harness) {
    harness.className = "ct-dev-harness";
    const label = document.createElement("label");
    label.textContent = "Fixture:";
    label.htmlFor = "ct-fixture-select";
    select = document.createElement("select");
    select.id = "ct-fixture-select";
    fixtures.forEach((f, i) => {
      const opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = f.name;
      select?.appendChild(opt);
    });
    select.addEventListener("change", () => show(Number(select?.value ?? 0)));
    harness.append(label, select);
  }

  let live: WizardState = fixtures[0]?.state;

  function show(i: number): void {
    index = ((i % fixtures.length) + fixtures.length) % fixtures.length;
    const fixture = fixtures[index];
    if (select) select.value = String(index);
    const url = new URL(window.location.href);
    url.searchParams.set("fixture", fixture.name);
    window.history.replaceState(null, "", url);
    live = cloneState(fixture.state);
    render(live);
  }

  function render(state: WizardState): void {
    live = state;
    renderWizard(appEl, liveRegion, state, buildDevHandlers(() => live, render));
  }

  window.addEventListener("keydown", (evt) => {
    if (evt.key === "]") show(index + 1);
    if (evt.key === "[") show(index - 1);
  });

  show(index);
}

async function main(): Promise<void> {
  if (isTauriHost()) {
    await runTauri();
  } else if (import.meta.env.DEV) {
    await runDevFixtureHarness();
  } else {
    console.error("Copilot Control Tower Setup: no Tauri host detected.");
  }
}

main().catch((err: unknown) => {
  console.error("Copilot Control Tower Setup: failed to initialize wizard", err);
});
