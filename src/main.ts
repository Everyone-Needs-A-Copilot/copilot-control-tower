/**
 * Popover entry point. Render-only: no state machine, no process spawning, no
 * verdict computation — all of that lives in Rust (see src-tauri/src/model/
 * and src-tauri/src/render/). This file's job is the IPC seam:
 *
 *   1. pull a snapshot via the `get_state` Tauri command on open, and
 *   2. subscribe to the `state-changed` event Rust pushes on a fresh parse.
 *
 * Dev-fixture harness (T7 scope): when this document is not running inside a
 * Tauri host (i.e. plain `vite dev` in a browser), there is no `get_state`
 * command and no doctor timer to push `state-changed`. In that case — and
 * ONLY in that case — this module renders from `src/dev-fixtures/*.json`
 * instead, with a small fixture switcher so every `RenderState` is visually
 * verifiable without the Rust core. The switcher is dev-only dead code in a
 * release build: `import.meta.env.DEV` is statically replaced by Vite, so
 * the whole branch (and the fixture JSON) is tree-shaken out of `dist/`.
 *
 * T8: this seam is wired to the real `get_state()`/`state-changed` IPC
 * surface T5 built (`src-tauri/src/commands.rs`) — `runTauri()` below is the
 * live path; `runDevFixtureHarness()` only ever runs outside a Tauri host.
 */
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  CHECK_FOR_UPDATE_CMD,
  GET_BOB_LANE_CMD,
  GET_SECURITY_BANNER_CMD,
  STATE_CHANGED_EVENT,
  type BobLaneView,
  type RenderState,
  type SecurityBanner,
  type UpdateState,
} from "./types";
import { renderPopover } from "./render/popover";
import { ensureLiveRegion } from "./render/a11y";
import { isTauriHost } from "./tauri-host";

const appElOrNull = document.getElementById("app");
if (!appElOrNull) {
  throw new Error("Copilot Control Tower: #app root missing from index.html");
}
/** Non-null once past the guard above; named separately so closures below don't lose the narrowing. */
const appEl: HTMLElement = appElOrNull;

const liveRegion = ensureLiveRegion(document.body);

/**
 * M4 S10: Control Tower's OWN self-update state, held separately from
 * `RenderState` because `state-changed` (the doctor timer's push) never
 * carries it — this module re-renders the popover on every doctor push, so
 * the last-fetched `UpdateState` is kept here and re-passed each time rather
 * than being lost on the next `state-changed` event.
 */
let latestUpdateState: UpdateState | null = null;

/**
 * M6 S5: the Bob-lane snapshot, held separately for the same reason
 * `latestUpdateState` is — `state-changed` (the doctor timer's push) never
 * carries it, so the last-fetched value is re-passed on every re-render
 * rather than lost.
 */
let latestBobLaneState: BobLaneView | null = null;

/**
 * M6 S4: the un-dismissable security-banner snapshot, held separately for
 * the same reason `latestBobLaneState` is — `state-changed` never carries
 * it, so the last-fetched value is re-passed on every re-render rather than
 * lost.
 */
let latestSecurityBanner: SecurityBanner | null = null;

/**
 * Best-effort initial fetch of `check_for_update` (S4/S5, landing in
 * parallel — see `types.ts`'s `UpdateState` doc). Defensively wrapped: a
 * not-yet-landed command must never break the popover's real, already-
 * working `RenderState` render — it just means no update section shows yet
 * (honest silence, never a fabricated status).
 */
async function fetchInitialUpdateState(): Promise<UpdateState | null> {
  try {
    return await invoke<UpdateState>(CHECK_FOR_UPDATE_CMD);
  } catch {
    return null;
  }
}

/**
 * M6 S5: best-effort initial fetch of `get_bob_lane` — not yet landed on the
 * Rust side (S7 wires the real router output; see `types.ts`'s
 * `GET_BOB_LANE_CMD` doc). Same fail-closed-to-silence convention as
 * `fetchInitialUpdateState` above: a missing command must never break the
 * popover, and must never fabricate a prompt/notice that wasn't actually
 * emitted — it just means the Bob lane stays silent (P1) until S7 lands.
 */
async function fetchInitialBobLaneState(): Promise<BobLaneView | null> {
  try {
    return await invoke<BobLaneView>(GET_BOB_LANE_CMD);
  } catch {
    return null;
  }
}

/**
 * M6 S4: best-effort initial fetch of `get_security_banner` — not yet
 * landed on the Rust side (S6 wires the real router/update-parse output;
 * see `types.ts`'s `GET_SECURITY_BANNER_CMD` doc). Same fail-closed-to-
 * silence convention as `fetchInitialBobLaneState` above: a missing command
 * must never break the popover, and must never fabricate a banner that
 * wasn't actually emitted — it just means the security banner stays silent
 * (P1) until S6 lands.
 */
async function fetchInitialSecurityBanner(): Promise<SecurityBanner | null> {
  try {
    return await invoke<SecurityBanner>(GET_SECURITY_BANNER_CMD);
  } catch {
    return null;
  }
}

async function runTauri(): Promise<void> {
  const initial = await invoke<RenderState>("get_state");
  latestUpdateState = await fetchInitialUpdateState();
  latestBobLaneState = await fetchInitialBobLaneState();
  latestSecurityBanner = await fetchInitialSecurityBanner();
  renderPopover(appEl, liveRegion, initial, latestUpdateState, latestBobLaneState, latestSecurityBanner);

  await listen<RenderState>(STATE_CHANGED_EVENT, (event) => {
    renderPopover(appEl, liveRegion, event.payload, latestUpdateState, latestBobLaneState, latestSecurityBanner);
  });

  await wireDismissal();
}

/**
 * D2 (T9 follow-up): the two conventional menu-bar-popover dismissal
 * gestures — Esc, and losing focus by clicking outside the popover. Both
 * invoke the SAME `hide_popover` Rust command (src-tauri/src/commands.rs),
 * which is itself the same hide path the tray's own left-click toggle uses
 * (src-tauri/src/tray.rs's `hide_popover_window`) — never a second,
 * JS-only notion of "closed", and never a re-implementation of window
 * show/hide logic here (this module only ever asks Rust to hide; opening
 * stays exclusively the tray click handler's job).
 *
 * `onFocusChanged` is `@tauri-apps/api/window`'s wrapper over the window's
 * own `tauri://focus`/`tauri://blur` events (verified against the
 * installed 2.11.x `@tauri-apps/api`) — it rides the SAME
 * `core:event:allow-listen` permission the `state-changed` subscription
 * above already uses, so no additional capability grant is needed for it,
 * only for the new `hide_popover` command itself.
 */
async function wireDismissal(): Promise<void> {
  window.addEventListener("keydown", (evt: KeyboardEvent) => {
    if (evt.key === "Escape") {
      void invoke("hide_popover");
    }
  });

  await getCurrentWindow().onFocusChanged(({ payload: focused }) => {
    if (!focused) {
      void invoke("hide_popover");
    }
  });
}

/** Dev-only: every corpus/RenderState state, switchable via a <select>, `?fixture=`, or `[`/`]`. */
async function runDevFixtureHarness(): Promise<void> {
  const modules = import.meta.glob<RenderState>("./dev-fixtures/*.json", {
    eager: true,
    import: "default",
  });

  const fixtures = Object.entries(modules)
    .map(([path, state]) => ({
      name: path.replace("./dev-fixtures/", "").replace(".json", ""),
      state,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  if (fixtures.length === 0) {
    appEl.textContent =
      "No dev fixtures found in src/dev-fixtures/. Run T2/T3, or add one manually (see T7 task brief).";
    return;
  }

  // M4 S10: a SECOND, independent switcher for `UpdateState` fixtures
  // (`./dev-fixtures/update/*.json` — a subdirectory, so the glob above
  // never picks these up). Independent from the `RenderState` fixture above
  // so any combination is reachable headlessly — this is the dimension the
  // S10 verification renders every state of, not the products/layers one.
  const updateModules = import.meta.glob<UpdateState>("./dev-fixtures/update/*.json", {
    eager: true,
    import: "default",
  });
  const updateFixtures: Array<{ name: string; state: UpdateState | null }> = [
    { name: "(none)", state: null },
    ...Object.entries(updateModules)
      .map(([path, state]) => ({
        name: path.replace("./dev-fixtures/update/", "").replace(".json", ""),
        state,
      }))
      .sort((a, b) => a.name.localeCompare(b.name)),
  ];

  // M6 S5: a THIRD, independent switcher for `BobLaneView` fixtures
  // (`./dev-fixtures/bob-lane/*.json`) — same rationale as the update
  // switcher above: every Bob-lane fixture must be reachable in ANY
  // combination with a base `RenderState`/`UpdateState` fixture for headless
  // verification. "(none)" maps to `null`, which `renderPopover` already
  // treats as "render nothing extra" (silence-is-success).
  const bobModules = import.meta.glob<BobLaneView>("./dev-fixtures/bob-lane/*.json", {
    eager: true,
    import: "default",
  });
  const bobFixtures: Array<{ name: string; state: BobLaneView | null }> = [
    { name: "(none)", state: null },
    ...Object.entries(bobModules)
      .map(([path, state]) => ({
        name: path.replace("./dev-fixtures/bob-lane/", "").replace(".json", ""),
        state,
      }))
      .sort((a, b) => a.name.localeCompare(b.name)),
  ];

  // M6 S4: a FOURTH, independent switcher for `SecurityBanner` fixtures
  // (`./dev-fixtures/security-banner/*.json`) — same rationale as the
  // update/Bob-lane switchers above. "(none)" maps to `null` — the
  // silence-is-success empty state `renderPopover` already treats as
  // "render nothing extra".
  const securityBannerModules = import.meta.glob<SecurityBanner>("./dev-fixtures/security-banner/*.json", {
    eager: true,
    import: "default",
  });
  const securityBannerFixtures: Array<{ name: string; state: SecurityBanner | null }> = [
    { name: "(none)", state: null },
    ...Object.entries(securityBannerModules)
      .map(([path, state]) => ({
        name: path.replace("./dev-fixtures/security-banner/", "").replace(".json", ""),
        state,
      }))
      .sort((a, b) => a.name.localeCompare(b.name)),
  ];

  const params = new URLSearchParams(window.location.search);
  let index = Math.max(
    0,
    fixtures.findIndex((f) => f.name === params.get("fixture")),
  );
  let updateIndex = Math.max(
    0,
    updateFixtures.findIndex((f) => f.name === params.get("update")),
  );
  let bobIndex = Math.max(
    0,
    bobFixtures.findIndex((f) => f.name === params.get("bob")),
  );
  let securityBannerIndex = Math.max(
    0,
    securityBannerFixtures.findIndex((f) => f.name === params.get("security-banner")),
  );

  const harness = document.getElementById("ct-dev-harness");
  let select: HTMLSelectElement | null = null;
  let updateSelect: HTMLSelectElement | null = null;
  let bobSelect: HTMLSelectElement | null = null;
  let securityBannerSelect: HTMLSelectElement | null = null;

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

    const updateLabel = document.createElement("label");
    updateLabel.textContent = "Update:";
    updateLabel.htmlFor = "ct-update-fixture-select";
    updateSelect = document.createElement("select");
    updateSelect.id = "ct-update-fixture-select";
    updateFixtures.forEach((f, i) => {
      const opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = f.name;
      updateSelect?.appendChild(opt);
    });
    updateSelect.addEventListener("change", () => showUpdate(Number(updateSelect?.value ?? 0)));

    const bobLabel = document.createElement("label");
    bobLabel.textContent = "Bob lane:";
    bobLabel.htmlFor = "ct-bob-fixture-select";
    bobSelect = document.createElement("select");
    bobSelect.id = "ct-bob-fixture-select";
    bobFixtures.forEach((f, i) => {
      const opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = f.name;
      bobSelect?.appendChild(opt);
    });
    bobSelect.addEventListener("change", () => showBob(Number(bobSelect?.value ?? 0)));

    const securityBannerLabel = document.createElement("label");
    securityBannerLabel.textContent = "Security banner:";
    securityBannerLabel.htmlFor = "ct-security-banner-fixture-select";
    securityBannerSelect = document.createElement("select");
    securityBannerSelect.id = "ct-security-banner-fixture-select";
    securityBannerFixtures.forEach((f, i) => {
      const opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = f.name;
      securityBannerSelect?.appendChild(opt);
    });
    securityBannerSelect.addEventListener("change", () =>
      showSecurityBanner(Number(securityBannerSelect?.value ?? 0)),
    );

    harness.append(
      label,
      select,
      updateLabel,
      updateSelect,
      bobLabel,
      bobSelect,
      securityBannerLabel,
      securityBannerSelect,
    );
  }

  function render(): void {
    const fixture = fixtures[index];
    renderPopover(
      appEl,
      liveRegion,
      fixture.state,
      updateFixtures[updateIndex]?.state ?? null,
      bobFixtures[bobIndex]?.state ?? null,
      securityBannerFixtures[securityBannerIndex]?.state ?? null,
    );
  }

  function show(i: number): void {
    index = ((i % fixtures.length) + fixtures.length) % fixtures.length;
    const fixture = fixtures[index];
    if (select) select.value = String(index);
    const url = new URL(window.location.href);
    url.searchParams.set("fixture", fixture.name);
    window.history.replaceState(null, "", url);
    render();
  }

  function showUpdate(i: number): void {
    updateIndex = ((i % updateFixtures.length) + updateFixtures.length) % updateFixtures.length;
    const fixture = updateFixtures[updateIndex];
    if (updateSelect) updateSelect.value = String(updateIndex);
    const url = new URL(window.location.href);
    url.searchParams.set("update", fixture.name);
    window.history.replaceState(null, "", url);
    render();
  }

  function showBob(i: number): void {
    bobIndex = ((i % bobFixtures.length) + bobFixtures.length) % bobFixtures.length;
    const fixture = bobFixtures[bobIndex];
    if (bobSelect) bobSelect.value = String(bobIndex);
    const url = new URL(window.location.href);
    url.searchParams.set("bob", fixture.name);
    window.history.replaceState(null, "", url);
    render();
  }

  function showSecurityBanner(i: number): void {
    securityBannerIndex =
      ((i % securityBannerFixtures.length) + securityBannerFixtures.length) % securityBannerFixtures.length;
    const fixture = securityBannerFixtures[securityBannerIndex];
    if (securityBannerSelect) securityBannerSelect.value = String(securityBannerIndex);
    const url = new URL(window.location.href);
    url.searchParams.set("security-banner", fixture.name);
    window.history.replaceState(null, "", url);
    render();
  }

  window.addEventListener("keydown", (evt) => {
    if (evt.key === "]") show(index + 1);
    if (evt.key === "[") show(index - 1);
    if (evt.key === "}") showUpdate(updateIndex + 1);
    if (evt.key === "{") showUpdate(updateIndex - 1);
    if (evt.key === ")") showBob(bobIndex + 1);
    if (evt.key === "(") showBob(bobIndex - 1);
    if (evt.key === ">") showSecurityBanner(securityBannerIndex + 1);
    if (evt.key === "<") showSecurityBanner(securityBannerIndex - 1);
  });

  show(index);
}

async function main(): Promise<void> {
  if (isTauriHost()) {
    await runTauri();
  } else if (import.meta.env.DEV) {
    await runDevFixtureHarness();
  } else {
    // Production build, no Tauri host: nothing honest to render. Never
    // fabricate a status — leave the surface empty rather than guess.
    console.error("Copilot Control Tower: no Tauri host detected.");
  }
}

main().catch((err: unknown) => {
  // Surface, don't swallow. A real CliUnreadable render (bad JSON, exit 2,
  // schema out of range) is Rust's job via the DTO — this catch is only for
  // the IPC seam itself failing to wire up.
  console.error("Copilot Control Tower: failed to initialize popover", err);
});
