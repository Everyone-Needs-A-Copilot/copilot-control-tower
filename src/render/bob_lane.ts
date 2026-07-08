/**
 * M6 S5 — the Bob-lane notification surface (`.copilot/wp/37.md` / task 56):
 * the visible half of "Bob's notification count trends toward zero" (SOUL
 * Principle 2). Renders ONLY what the router (M6 S2) emits for the closed
 * two-member `BobPrompt` set (his sign-in, his dirty WIP) plus quiet,
 * past-tense `BobNotice` lines for auto-acted safety events — see
 * `types.ts`'s `BobLaneView` doc for the full contract and the anti-Alert-
 * Machine boundary this module must never cross.
 *
 * Render-only, same discipline `render/update.ts` established: this module
 * computes NO verdict about whether Bob should be interrupted — that
 * decision already happened in the router. It only ever *renders* the
 * `BobLaneView` snapshot it's given, and (like `update.ts`'s "Update now"
 * button) triggers a real CLI-bound action for the one wired case
 * (`get_bob_lane`'s not-yet-landed action commands are intentionally left
 * INERT here — see `handlePromptAction` below — never a fabricated effect).
 *
 * **Notification-denied fallback (E12/US-B16).** When macOS notification
 * permission is denied, the real system-notification delivery never fires
 * (that transport is owner-gated, outside this repo's reach). What this
 * module guarantees is that the SAME `prompt` is still reachable the moment
 * Bob opens the popover — this section renders unconditionally whenever
 * `prompt` is non-null, regardless of `notifications_denied` — and, only
 * when `notifications_denied` is true, adds one honest line explaining why
 * he's seeing it here instead of as a system notification. The fallback is
 * never a separate code path from the normal render; it's the SAME render,
 * with one extra sentence.
 */
import * as copy from "./copy";
import { buildActionButton, h } from "./dom";
import type { BobLaneView, BobNotice, BobPrompt } from "../types";

/**
 * Every action label this module currently knows how to WIRE to a real
 * effect. None exist yet (S7 wires the router's live commands) — this stays
 * an explicit empty allow-list rather than a bare `false`, so the day a real
 * command lands, the diff that adds it is obvious and reviewable, same
 * "never invent a flow this task wasn't asked to build" discipline
 * `popover.ts`'s `buildPrimaryActionButton` doc already documents for every
 * label besides "Sync now".
 */
function handlePromptAction(_prompt: BobPrompt): void {
  // Intentionally inert. Wiring a real "Sign in…" / "Show me…" effect here
  // is S7's job (live router action commands); this task owns render only.
}

function buildPromptSection(prompt: BobPrompt, notificationsDenied: boolean): HTMLElement {
  const section = h("section", {
    className: "ct-bob-prompt",
    attrs: {
      role: "group",
      "aria-label": copy.bobPromptLabel(prompt),
      "data-bob-prompt-kind": prompt.kind,
    },
  });

  if (notificationsDenied) {
    section.appendChild(
      h("p", { className: "ct-bob-prompt__fallback-note", text: copy.BOB_NOTIFICATIONS_DENIED_NOTE }),
    );
  }

  section.appendChild(h("p", { className: "ct-bob-prompt__title", text: prompt.title }));
  section.appendChild(h("p", { className: "ct-bob-prompt__detail", text: prompt.detail }));

  const btn = buildActionButton(prompt.action_label, copy.ACTION_EFFECT[prompt.action_label] ?? "", "ct-bob-prompt__action");
  btn.addEventListener("click", () => handlePromptAction(prompt));
  section.appendChild(btn);

  return section;
}

function buildNoticeRow(notice: BobNotice): HTMLElement {
  // Deliberately the SAME neutral, un-alarmed treatment `render/update.ts`'s
  // rollback toast uses for "Kept your working version." — no button, no
  // dismiss, no colour/border implying urgency (a11y + Voice: past-tense
  // things already handled are reported, never alarmed over).
  return h("p", {
    className: "ct-bob-notice",
    text: notice.message,
    attrs: { role: "status", "aria-label": copy.bobNoticeLabel(notice) },
  });
}

/**
 * Builds the Bob-lane section for one `BobLaneView` snapshot. Returns `null`
 * for the empty/default state (`prompt: null, notices: []`) — silence is the
 * success state (P1), the exact same "idle -> null" precedent
 * `render/update.ts`'s `buildUpdateSection` already established for
 * `UpdateState`.
 *
 * Render-only — does NOT announce anything itself (unlike `announce`'s use
 * elsewhere), matching `buildUpdateSection`'s own documented split: the
 * CALLER (`popover.ts`) decides the single announcement for the whole
 * initial render (and prioritizes a Bob prompt over the general status
 * sentence when one is present, via `copy.bobLaneAnnouncement`) so a screen
 * reader is never fed two competing announcements in the same paint.
 */
export function buildBobLaneSection(state: BobLaneView): HTMLElement | null {
  if (!state.prompt && state.notices.length === 0) return null;

  const wrap = h("div", { className: "ct-bob-lane" });

  if (state.prompt) {
    wrap.appendChild(buildPromptSection(state.prompt, state.notifications_denied));
  }

  state.notices.forEach((notice) => {
    wrap.appendChild(buildNoticeRow(notice));
  });

  return wrap;
}
