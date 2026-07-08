/**
 * M6 S4 — the un-dismissable security-banner render (`.copilot/wp/37.md` /
 * task 55). Renders `types.ts`'s `SecurityBanner` DTO — the honest,
 * PAST-TENSE surface for a security fix the router/CLI already auto-acted on
 * (Flow 7, "The Fix That Acts Itself"). Render-only, same discipline
 * `render/update.ts`/`render/bob_lane.ts` already establish: this module
 * computes NO verdict about whether a security shadow happened — it only
 * ever renders the `SecurityBanner` snapshot it's given.
 *
 * **Re-affirm-only, never dismiss (invariant: never a false "all clear").**
 * `buildSecurityBannerSection` renders exactly ONE control — the re-affirm
 * affordance named by `SecurityBanner.reaffirm_label` — and NO dismiss/
 * close/clear button anywhere in the DOM it builds. `types.ts`'s
 * `SecurityBanner` has no `dismiss` field to even wire one to; this module
 * additionally never adds a synthetic close control of its own. The
 * re-affirm action itself is left INERT here (same "no invented flow"
 * convention `render/bob_lane.ts`'s `handlePromptAction` already documents)
 * — wiring it to a real CLI-bound effect is a future live-wiring stream's
 * job (S6), never this render task's.
 */
import * as copy from "./copy";
import { buildActionButton, h } from "./dom";
import type { SecurityBanner } from "../types";

/**
 * Intentionally inert — see the module doc. Wiring a real "re-affirm"
 * effect is S6's job (live router wiring); this task owns render only,
 * same "never invent a flow this task wasn't asked to build" discipline
 * `render/bob_lane.ts`'s `handlePromptAction` already documents.
 */
function handleReaffirm(_banner: SecurityBanner): void {
  // no-op
}

/**
 * Builds the un-dismissable security-banner section for one `SecurityBanner`
 * snapshot. Returns `null` for the empty state (`banner` is `null`/
 * `undefined`) — silence-is-success (P1), the same "idle -> null" precedent
 * `render/update.ts`'s `buildUpdateSection` and `render/bob_lane.ts`'s
 * `buildBobLaneSection` both already establish.
 */
export function buildSecurityBannerSection(banner: SecurityBanner | null | undefined): HTMLElement | null {
  if (!banner) return null;

  const section = h("section", {
    className: "ct-security-banner",
    attrs: { role: "group", "aria-label": banner.message },
  });

  section.appendChild(h("p", { className: "ct-security-banner__message", text: banner.message }));

  const btn = buildActionButton(
    banner.reaffirm_label,
    copy.ACTION_EFFECT[banner.reaffirm_label] ?? "",
    "ct-security-banner__reaffirm",
  );
  btn.addEventListener("click", () => handleReaffirm(banner));
  section.appendChild(btn);

  return section;
}
