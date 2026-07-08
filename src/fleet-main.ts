/**
 * Fleet dashboard entry point (M7 S4, task 63). Mirrors `settings-main.ts`'s
 * IPC-seam shape exactly (get-snapshot-on-open, dev-fixture harness outside
 * a Tauri host) — `runTauri()` below defensively invokes `get_fleet`
 * (`types.ts`'s `GET_FLEET_CMD`), not yet landed on the Rust side (G-M7-3,
 * the real collected-fleet source, is owner infra; a future live-wiring
 * task, S9, lands the real command backed by mock fixtures first). A
 * missing command must never crash this window — it just means the
 * dashboard renders its own empty-fleet state until that command exists,
 * the SAME fail-closed-to-silence convention `main.ts`'s
 * `fetchInitialBobLaneState`/`fetchInitialSecurityBanner` already establish.
 * `runDevFixtureHarness()` is the `vite dev`-only fallback (tree-shaken out
 * of a production build, same as `main.ts`'s/`settings-main.ts`'s harness).
 */
import { invoke } from "@tauri-apps/api/core";
import { buildFleetDashboard } from "./render/fleet";
import { ensureLiveRegion, announce } from "./render/a11y";
import { isTauriHost } from "./tauri-host";
import { GET_FLEET_CMD, type FleetView } from "./types";

const appElOrNull = document.getElementById("app");
if (!appElOrNull) {
  throw new Error("Copilot Control Tower Fleet: #app root missing from fleet.html");
}
const appEl: HTMLElement = appElOrNull;

const liveRegion = ensureLiveRegion(document.body);

const EMPTY_FLEET: FleetView = { hosts: [] };

/**
 * Best-effort fetch of `get_fleet` — not yet landed on the Rust side (see
 * module doc). Same fail-closed-to-silence convention `main.ts`'s
 * `fetchInitialBobLaneState` already establishes: a missing command must
 * never break this window, and must never fabricate fleet data that wasn't
 * actually collected — it just means the dashboard renders the empty-fleet
 * state until a real command exists.
 */
async function fetchFleet(): Promise<FleetView> {
  try {
    return await invoke<FleetView>(GET_FLEET_CMD);
  } catch {
    return EMPTY_FLEET;
  }
}

async function runTauri(): Promise<void> {
  const view = await fetchFleet();
  buildFleetDashboard(appEl, view);
}

/**
 * Dev-only: switch between hand-built `FleetView` fixtures
 * (`src/dev-fixtures/fleet/*.json` — all-healthy / mixed-worst-wins /
 * actionable-items / empty / single-host), same convention
 * `settings-main.ts`'s `runDevFixtureHarness` already establishes. Tree-
 * shaken out of a release build (`import.meta.env.DEV` is statically
 * stripped by Vite).
 */
async function runDevFixtureHarness(): Promise<void> {
  const modules = import.meta.glob<FleetView>("./dev-fixtures/fleet/*.json", {
    eager: true,
    import: "default",
  });

  const fixtures = Object.entries(modules)
    .map(([path, state]) => ({
      name: path.replace("./dev-fixtures/fleet/", "").replace(".json", ""),
      state,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  if (fixtures.length === 0) {
    appEl.textContent = "No Fleet dev fixtures found in src/dev-fixtures/fleet/.";
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
    buildFleetDashboard(appEl, fixture.state);
    announce(liveRegion, `Fleet fixture: ${fixture.name}, ${fixture.state.hosts.length} host(s).`);
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
    console.error("Copilot Control Tower Fleet: no Tauri host detected.");
  }
}

main().catch((err: unknown) => {
  console.error("Copilot Control Tower Fleet: failed to initialize", err);
});
