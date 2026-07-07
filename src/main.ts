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
import { STATE_CHANGED_EVENT, type RenderState } from "./types";
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

async function runTauri(): Promise<void> {
  const initial = await invoke<RenderState>("get_state");
  renderPopover(appEl, liveRegion, initial);

  await listen<RenderState>(STATE_CHANGED_EVENT, (event) => {
    renderPopover(appEl, liveRegion, event.payload);
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

  function show(i: number): void {
    index = ((i % fixtures.length) + fixtures.length) % fixtures.length;
    const fixture = fixtures[index];
    if (select) select.value = String(index);
    const url = new URL(window.location.href);
    url.searchParams.set("fixture", fixture.name);
    window.history.replaceState(null, "", url);
    renderPopover(appEl, liveRegion, fixture.state);
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
