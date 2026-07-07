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
