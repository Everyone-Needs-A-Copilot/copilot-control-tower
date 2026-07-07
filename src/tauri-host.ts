/**
 * Shared "are we actually inside the Tauri webview host?" check (T8).
 *
 * Both the IPC bootstrap (`main.ts`) and any UI affordance that invokes a
 * Tauri command (e.g. the "Sync now" primary action, `render/popover.ts`)
 * need this same guard: under plain `vite dev` in a browser there is no
 * `get_state`/`refresh_now` command and no `state-changed` event to wire to,
 * so a real `invoke()` call would just throw. One shared predicate keeps
 * that guard from drifting into two slightly different checks.
 */
export function isTauriHost(): boolean {
  return "__TAURI_INTERNALS__" in window || "__TAURI__" in window;
}
