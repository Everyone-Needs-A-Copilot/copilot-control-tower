/**
 * VoiceOver/ARIA wiring and full keyboard operability for the product-first
 * dropdown, per docs/product-design/04-experience-design/50-ux-design.md §
 * Accessibility (the a11y hard rules) and 60-ui-design.md's VoiceOver note.
 *
 * Status is carried by SHAPE + SENTENCE everywhere (`badges.ts` + `copy.ts`);
 * this module's job is: (1) a live region that announces state changes
 * (a11y rule 3), and (2) keyboard operability of product-row disclosure —
 * expand/collapse (Enter/Space, native `<button>`), plus the Up/Down/Right/
 * Left roving-focus enhancement the design's tree/disclosure pattern calls
 * for, layered on top of ordinary Tab order so nothing here is mouse- or
 * screen-reader-only.
 */

const LIVE_REGION_ID = "ct-live-region";

/** Creates (once) the polite live region status changes are announced through. */
export function ensureLiveRegion(root: HTMLElement): HTMLElement {
  let el = root.querySelector<HTMLElement>(`#${LIVE_REGION_ID}`);
  if (!el) {
    el = document.createElement("div");
    el.id = LIVE_REGION_ID;
    el.setAttribute("role", "status");
    el.setAttribute("aria-live", "polite");
    el.className = "sr-only";
    root.appendChild(el);
  }
  return el;
}

/**
 * Announces `text` via the live region. Clears first so a repeated identical
 * announcement (e.g. re-selecting the same dev fixture) still fires — most
 * assistive tech only speaks on a text *change*.
 */
export function announce(liveRegion: HTMLElement, text: string): void {
  liveRegion.textContent = "";
  // Force a reflow so the subsequent write is treated as a distinct mutation.
  void liveRegion.offsetWidth;
  liveRegion.textContent = text;
}

/**
 * Wires Up/Down/Right/Left across the product list's disclosure buttons and
 * their layer groups. Each product row is a real `<button aria-expanded>`
 * (native semantics: Enter/Space already toggle it and Tab already reaches
 * it — this only *adds* the tree-style arrow-key affordance the design calls
 * for; it never removes the native fallback).
 */
export function attachProductListKeyboard(list: HTMLElement): void {
  const rows = () => Array.from(list.querySelectorAll<HTMLButtonElement>("[data-role='product-row']"));

  // Roving tabindex (ARIA treeview convention, 50-ux-design.md a11y rule 4):
  // the tree is a single Tab stop; arrow keys move focus within it. Whatever
  // row last received focus (by arrow key, click, or Tab-in) becomes the one
  // reachable via Tab; every other row/layer drops out of the Tab sequence.
  list.addEventListener("focusin", (evt) => {
    const target = evt.target as HTMLElement;
    if (!target.dataset.role) return;
    list.querySelectorAll<HTMLElement>("[data-role='product-row'], [data-role='layer-row']").forEach((el) => {
      el.tabIndex = -1;
    });
    target.tabIndex = 0;
  });

  list.addEventListener("keydown", (evt) => {
    const target = evt.target as HTMLElement;
    const all = rows();

    if (target.dataset.role === "product-row") {
      const i = all.indexOf(target as HTMLButtonElement);
      const expanded = target.getAttribute("aria-expanded") === "true";

      switch (evt.key) {
        case "ArrowDown": {
          evt.preventDefault();
          if (expanded) {
            const firstLayer = target
              .closest("[data-role='product-item']")
              ?.querySelector<HTMLElement>("[data-role='layer-row']");
            (firstLayer ?? all[i + 1])?.focus();
          } else {
            all[i + 1]?.focus();
          }
          break;
        }
        case "ArrowUp":
          evt.preventDefault();
          all[i - 1]?.focus();
          break;
        case "ArrowRight":
          if (!expanded) {
            evt.preventDefault();
            target.click();
          }
          break;
        case "ArrowLeft":
          if (expanded) {
            evt.preventDefault();
            target.click();
          }
          break;
      }
      return;
    }

    if (target.dataset.role === "layer-row") {
      const item = target.closest("[data-role='product-item']");
      const layerRows = Array.from(item?.querySelectorAll<HTMLElement>("[data-role='layer-row']") ?? []);
      const j = layerRows.indexOf(target);
      switch (evt.key) {
        case "ArrowDown":
          evt.preventDefault();
          layerRows[j + 1]?.focus();
          break;
        case "ArrowUp":
          evt.preventDefault();
          if (j === 0) {
            item?.querySelector<HTMLButtonElement>("[data-role='product-row']")?.focus();
          } else {
            layerRows[j - 1]?.focus();
          }
          break;
        case "ArrowLeft": {
          evt.preventDefault();
          item?.querySelector<HTMLButtonElement>("[data-role='product-row']")?.focus();
          break;
        }
      }
    }
  });
}
