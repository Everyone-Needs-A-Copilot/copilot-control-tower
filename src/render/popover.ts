/**
 * Popover entry point. Product-first list + inline four-layer expansion,
 * driven entirely by `RenderState`. Render-only: this module never computes
 * a verdict — it renders `header.sentence`, `worst_severity`, `severity`, and
 * `badge_state` exactly as given, and only ever *picks which already-decided
 * mark to show* (e.g. a product's collapsed badge = its worst layer's
 * already-decided badge — a display choice, not a new verdict, ADR-M1-002).
 *
 * Renders N products (config-driven, not hardcoded), each expandable to its
 * layers in fixed order (foundation / org / department / personal).
 *
 * The one exception to "render-only" (T8): the "Sync now" primary action
 * invokes the `refresh_now` Tauri command. That is a trigger, not a
 * computation — it asks Rust to run the SAME poll path the timer uses and
 * push a fresh `state-changed` event; this module never decides the result.
 */
import { invoke } from "@tauri-apps/api/core";
import { renderBadge } from "./badges";
import * as copy from "./copy";
import { announce, attachProductListKeyboard } from "./a11y";
import { h } from "./dom";
import { isTauriHost } from "../tauri-host";
import type { DeptProjectView, LayerView, ProductView, RenderState } from "../types";

function divider(): HTMLElement {
  return h("hr", { className: "ct-sep" });
}

function slug(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
}

function buildActionButton(label: string, effect: string, className: string): HTMLButtonElement {
  const btn = h("button", { className, text: label });
  btn.type = "button";
  btn.setAttribute("aria-label", effect ? `${label} — ${effect}` : label);
  return btn;
}

function primaryAction(state: RenderState): { label: string; effect: string } | null {
  if (!state.status) return null;
  const label = copy.PRIMARY_ACTION_LABEL[state.status];
  if (!label) return null;
  return { label, effect: copy.ACTION_EFFECT[label] ?? "" };
}

/**
 * T8: the top-line primary action button. "Sync now" is the one label this
 * task wires to a real effect (`refresh_now` — the manual escape hatch onto
 * the SAME poll path the timer uses, see `src-tauri/src/commands.rs`); it
 * does not compute or fabricate anything, it only triggers a fresh parse.
 * Every other label (Sign in…/Repair…/What changed?/Finish setup…) is a
 * real, T7-built control with no wired effect yet — left inert rather than
 * inventing a flow this task wasn't asked to build.
 */
function buildPrimaryActionButton(action: { label: string; effect: string }): HTMLButtonElement {
  const btn = buildActionButton(action.label, action.effect, "ct-primary-action");
  if (action.label === "Sync now" && isTauriHost()) {
    btn.addEventListener("click", () => {
      void invoke("refresh_now");
    });
  }
  return btn;
}

function buildHeader(state: RenderState): HTMLElement {
  const header = h("header", { className: "ct-header" });

  // Healthy renders NO badge on the header glyph — the plain mark, per P1
  // "silence is the success state." Every other state pairs a shape here.
  if (state.header.glyph_state !== "none") {
    const glyphWrap = h("div", { className: "ct-header__glyph" });
    glyphWrap.appendChild(renderBadge(state.header.glyph_state, { animate: true }));
    header.appendChild(glyphWrap);
  }

  const textWrap = h("div", { className: "ct-header__text" });
  const sentence = h("p", { className: "ct-header__sentence", text: state.header.sentence });
  sentence.id = "ct-status-sentence";
  textWrap.appendChild(sentence);

  const note = state.status ? copy.SECONDARY_NOTE[state.status] : undefined;
  if (note) textWrap.appendChild(h("p", { className: "ct-header__note", text: note }));

  header.appendChild(textWrap);
  return header;
}

function buildUnreadable(state: RenderState): HTMLElement {
  const wrap = h("div", { className: "ct-unreadable", attrs: { role: "group", "aria-label": "Error" } });
  const badgeWrap = h("div", { className: "ct-unreadable__badge" });
  badgeWrap.appendChild(renderBadge("bang"));
  wrap.appendChild(badgeWrap);
  wrap.appendChild(h("p", { className: "ct-header__sentence", text: state.header.sentence }));

  const reinstallReasons = new Set(["io_error", "exit_2"]);
  const label =
    state.cli_unreadable_reason && reinstallReasons.has(state.cli_unreadable_reason)
      ? "Reinstall"
      : copy.CLI_UNREADABLE_ACTION_LABEL;
  const effect = copy.ACTION_EFFECT[label] ?? copy.ACTION_EFFECT["Update now"];
  wrap.appendChild(buildActionButton(label, effect, "ct-primary-action"));
  return wrap;
}

function buildProjectRow(project: DeptProjectView): HTMLElement {
  const row = h("div", {
    className: "ct-project-row",
    attrs: { role: "treeitem", "aria-level": "3", "aria-label": copy.deptProjectLabel(project) },
  });
  row.tabIndex = -1;
  row.appendChild(renderBadge(project.badge_state));
  row.appendChild(h("span", { className: "ct-project-label", text: `${project.name} (project)` }));
  row.appendChild(h("span", { className: "ct-project-detail", text: copy.layerDetailText(project) }));
  return row;
}

function buildLayerRow(layer: LayerView): HTMLElement {
  // Outer wrapper is a plain block so a dept project list (if any) stacks
  // BELOW the layer's own flex line, rather than fighting it for width.
  const wrap = h("div", { className: "ct-layer-item" });

  const row = h("div", {
    className: "ct-layer-row",
    attrs: { role: "treeitem", "aria-level": "2", "aria-label": copy.layerRowLabel(layer) },
  });
  row.dataset.role = "layer-row";
  row.tabIndex = -1;

  row.appendChild(renderBadge(layer.badge_state, { animate: true }));
  row.appendChild(h("span", { className: "ct-layer-label", text: copy.LAYER_LABEL[layer.layer] }));
  row.appendChild(h("span", { className: "ct-layer-detail", text: copy.layerDetailText(layer) }));

  const actionLabel = copy.layerActionLabel(layer);
  if (actionLabel) {
    row.appendChild(buildActionButton(actionLabel, copy.ACTION_EFFECT[actionLabel] ?? "", "ct-layer-action"));
  }
  wrap.appendChild(row);

  if (layer.projects && layer.projects.length > 0) {
    const projects = h("div", { className: "ct-projects", attrs: { role: "group" } });
    layer.projects.forEach((p) => projects.appendChild(buildProjectRow(p)));
    wrap.appendChild(projects);
  }

  return wrap;
}

function buildProductItem(product: ProductView, isFirst: boolean): HTMLElement {
  const item = h("div", { className: "ct-product-item", attrs: { role: "none", "data-role": "product-item" } });
  const layersId = `ct-layers-${slug(product.product)}`;

  const row = h("button", { className: "ct-product-row" });
  row.type = "button";
  row.dataset.role = "product-row";
  row.setAttribute("role", "treeitem");
  row.setAttribute("aria-level", "1");
  row.setAttribute("aria-expanded", "false");
  row.setAttribute("aria-controls", layersId);
  row.setAttribute("aria-label", copy.productRowLabel(product, false));
  row.tabIndex = isFirst ? 0 : -1;

  const badge = renderBadge(copy.productDisplayBadge(product), { animate: true });
  const name = h("span", { className: "ct-product-name", text: product.product });
  const phrase = h("span", { className: "ct-product-phrase", text: copy.productRowPhrase(product) });
  const chevron = h("span", { className: "ct-chevron", text: "▸", attrs: { "aria-hidden": "true" } });
  row.append(badge, name, phrase, chevron);

  const layers = h("div", { className: "ct-layers", attrs: { role: "group", id: layersId } });
  layers.hidden = true;
  product.layers.forEach((layer) => layers.appendChild(buildLayerRow(layer)));

  row.addEventListener("click", () => {
    const expanded = row.getAttribute("aria-expanded") === "true";
    row.setAttribute("aria-expanded", String(!expanded));
    row.setAttribute("aria-label", copy.productRowLabel(product, !expanded));
    chevron.textContent = expanded ? "▸" : "▾";
    layers.hidden = expanded;
  });

  item.append(row, layers);
  return item;
}

function buildProductSection(products: ProductView[]): HTMLElement {
  const section = h("section", { attrs: { "aria-labelledby": "ct-products-label" } });
  section.appendChild(h("h2", { className: "ct-section-label", text: copy.SECTION_PRODUCTS, attrs: { id: "ct-products-label" } }));

  const tree = h("div", { className: "ct-tree", attrs: { role: "tree", "aria-label": "Products" } });
  products.forEach((p, i) => tree.appendChild(buildProductItem(p, i === 0)));
  section.appendChild(tree);

  attachProductListKeyboard(tree);
  return section;
}

function buildSecondaryRows(): HTMLElement {
  const nav = h("nav", { className: "ct-secondary", attrs: { "aria-label": "More" } });
  copy.SECONDARY_ROWS.forEach((label) => {
    const btn = h("button", { className: "ct-row", text: label });
    btn.type = "button";
    nav.appendChild(btn);
  });
  return nav;
}

/**
 * M2 S7/S8: "Preferences…" is the one footer row wired to a real effect —
 * opening Settings (the unmanaged/solo/author repo-URL surface,
 * `.copilot/wp/5.md` ADR-M2-004), reached from the popover's footer per the
 * task brief ("wire a way to open it — e.g. from the popover's secondary/
 * footer area"). In a Tauri host this invokes the real Rust-side
 * `open_settings_window` command (S6, landed) to show/focus the dedicated
 * Settings *window*; outside a Tauri host (plain `vite dev`, this repo's
 * headless-verification path) it navigates to `settings.html` directly,
 * since that's the only host this session can drive. "Quit" stays inert —
 * out of this task's scope.
 */
function buildFooter(): HTMLElement {
  const nav = h("nav", { className: "ct-footer", attrs: { "aria-label": "Application" } });
  const prefs = h("button", { className: "ct-row", text: copy.PREFERENCES_LABEL });
  prefs.type = "button";
  prefs.addEventListener("click", () => {
    if (isTauriHost()) {
      void invoke("open_settings_window");
    } else {
      window.location.href = "./settings.html";
    }
  });
  const quit = h("button", { className: "ct-row ct-row--destructive", text: copy.QUIT_LABEL });
  quit.type = "button";
  nav.append(prefs, quit);
  return nav;
}

/**
 * Renders the whole popover into `container` from a `RenderState` snapshot.
 * `liveRegion` receives the announced status sentence (a11y rule 3).
 */
export function renderPopover(container: HTMLElement, liveRegion: HTMLElement, state: RenderState): void {
  container.replaceChildren();

  if (state.client_state === "cli_unreadable") {
    container.appendChild(buildUnreadable(state));
    announce(liveRegion, state.header.sentence);
    return;
  }

  container.appendChild(buildHeader(state));

  const action = primaryAction(state);
  if (action) container.appendChild(buildPrimaryActionButton(action));

  container.appendChild(divider());

  if (state.products.length > 0) {
    container.appendChild(buildProductSection(state.products));
    container.appendChild(divider());
  }

  container.appendChild(buildSecondaryRows());
  container.appendChild(divider());
  container.appendChild(buildFooter());

  announce(liveRegion, state.header.sentence);
}
