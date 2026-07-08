/**
 * Tiny shared DOM-builder helper. Extracted out of `popover.ts` (M1) so
 * `settings.ts` (M2 S7) doesn't duplicate it — "never duplicate component
 * logic" (atomic-design anti-generic rule). No framework: this is the whole
 * abstraction the product uses over `document.createElement`.
 */
export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  opts: { className?: string; text?: string; attrs?: Record<string, string> } = {},
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (opts.className) el.className = opts.className;
  if (opts.text !== undefined) el.textContent = opts.text;
  if (opts.attrs) {
    for (const [k, v] of Object.entries(opts.attrs)) el.setAttribute(k, v);
  }
  return el;
}

/**
 * The one action-button shape the whole app uses: a real `<button>` (never a
 * `div`/`span` click target), its plain-language effect folded into the
 * accessible name (a11y rule 2, 70-copy-voice.md "VoiceOver — every action
 * row names its action + plain-language effect"). Extracted out of
 * `popover.ts` (M1) so `render/update.ts` (M4 S10) doesn't duplicate it —
 * same "never duplicate component logic" rule that moved `h()` here.
 */
export function buildActionButton(label: string, effect: string, className: string): HTMLButtonElement {
  const btn = h("button", { className, text: label });
  btn.type = "button";
  btn.setAttribute("aria-label", effect ? `${label} — ${effect}` : label);
  return btn;
}
