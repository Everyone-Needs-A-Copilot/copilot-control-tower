/**
 * Settings entry point (M2 S7/S8). Mirrors `main.ts`'s IPC-seam shape exactly
 * (get-snapshot-on-open, dev-fixture harness outside a Tauri host, same
 * pattern T8 used for `get_state()`/`refresh_now`). `runTauri()` below calls
 * the real `get_settings()`/`save_settings()` commands (S6, landed) — live,
 * not inert — whenever this page is running inside the Tauri host;
 * `runDevFixtureHarness()` is the `vite dev`-only fallback (tree-shaken out
 * of a production build, same as `main.ts`'s harness).
 */
import { invoke } from "@tauri-apps/api/core";
import { renderSettings, announceSettingsResult } from "./render/settings";
import { ensureLiveRegion } from "./render/a11y";
import { isTauriHost } from "./tauri-host";
import type { LayerInput, SettingsState } from "./types";

const appElOrNull = document.getElementById("app");
if (!appElOrNull) {
  throw new Error("Copilot Control Tower Settings: #app root missing from settings.html");
}
const appEl: HTMLElement = appElOrNull;

const liveRegion = ensureLiveRegion(document.body);

async function runTauri(): Promise<void> {
  const initial = await invoke<SettingsState>("get_settings");

  function renderCurrent(state: SettingsState): void {
    renderSettings(appEl, state, (inputs: LayerInput[]) => {
      void handleSave(inputs);
    });
  }

  async function handleSave(inputs: LayerInput[]): Promise<void> {
    const result = await invoke<SettingsState>("save_settings", { inputs });
    renderCurrent(result);
    announceSettingsResult(liveRegion, result);
  }

  renderCurrent(initial);
}

/**
 * Dev-only: switch between hand-built `SettingsState` fixtures
 * (`src/dev-fixtures/settings/*.json` — clean / errors / managed / empty),
 * same convention as `main.ts`'s RenderState harness (T7). Tree-shaken out
 * of a release build (`import.meta.env.DEV` is statically stripped by Vite).
 *
 * `onSave` here is a DEV-PREVIEW-ONLY mock: it does simple client-side
 * format checks so the Save round trip is demonstrable headlessly without a
 * live `save_settings` command. This mock never ships — it lives entirely
 * inside the DEV-only branch — and it is NOT the product's validation (that
 * stays exclusively server-side per invariant #1; see the mock's own doc
 * comment below).
 */
async function runDevFixtureHarness(): Promise<void> {
  const modules = import.meta.glob<SettingsState>("./dev-fixtures/settings/*.json", {
    eager: true,
    import: "default",
  });

  const fixtures = Object.entries(modules)
    .map(([path, state]) => ({
      name: path.replace("./dev-fixtures/settings/", "").replace(".json", ""),
      state,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  if (fixtures.length === 0) {
    appEl.textContent = "No Settings dev fixtures found in src/dev-fixtures/settings/.";
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
    render(fixture.state);
  }

  function render(state: SettingsState): void {
    renderSettings(appEl, state, (inputs) => {
      const result = mockSaveSettings(state, inputs);
      render(result);
      announceSettingsResult(liveRegion, result);
    });
  }

  window.addEventListener("keydown", (evt) => {
    if (evt.key === "]") show(index + 1);
    if (evt.key === "[") show(index - 1);
  });

  show(index);
}

/**
 * DEV-PREVIEW-ONLY mock of `save_settings` — exists purely so this session's
 * headless verification can exercise the Save round trip without a live
 * Rust command (S6 not yet landed). Deliberately shallow: it is NOT a
 * reimplementation of the real engine's `validate_layers` (that would
 * violate invariant #1 parse-never-compute even as a mock); it only
 * recognizes the two most obvious honest-copy cases the S7 task brief names
 * verbatim (an empty field, an embedded credential) so the UI's error
 * rendering path is visibly exercised. Everything else is treated as
 * accepted. Lives entirely inside the tree-shaken DEV branch — never ships.
 */
function mockSaveSettings(state: SettingsState, inputs: LayerInput[]): SettingsState {
  const layers = state.layers.map((l) => ({ ...l }));
  const errors: SettingsState["errors"] = [];

  for (const input of inputs) {
    let row = layers.find((l) => l.product === input.product && l.tier === input.tier);
    if (!row) {
      row = {
        id: `${input.tier}-${input.product}`,
        product: input.product,
        tier: input.tier,
        repo_url: "",
        auth_ref: "",
        rank: layers.length + 1,
        editable: true,
      };
      layers.push(row);
    }
    row.repo_url = input.repo_url;

    if (!input.repo_url.trim()) {
      errors.push({ layer_id: row.id, field: "repo_url", message: "This field can't be empty." });
    } else if (/:\/\/[^/]*:[^/]*@/.test(input.repo_url)) {
      errors.push({
        layer_id: row.id,
        field: "repo_url",
        message: "This URL contains a username and password. Remove them — credentials aren't stored here.",
      });
    }
  }

  return { managed: state.managed, layers, errors };
}

async function main(): Promise<void> {
  if (isTauriHost()) {
    await runTauri();
  } else if (import.meta.env.DEV) {
    await runDevFixtureHarness();
  } else {
    console.error("Copilot Control Tower Settings: no Tauri host detected.");
  }
}

main().catch((err: unknown) => {
  console.error("Copilot Control Tower Settings: failed to initialize", err);
});
