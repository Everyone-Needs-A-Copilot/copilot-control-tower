/**
 * M4 S10 — Control Tower's own self-update affordance: the click-to-update
 * control (`status === "available"`) and the "kept your working version"
 * rollback toast (`status === "rolled-back"`). See `types.ts`'s `UpdateState`
 * doc for why this is a SEPARATE signal from `RenderState.status`'s CLI-
 * parsed `"update-available"`/`"updating-app"` — this module renders the
 * app's own self-update TRANSPORT (ADR-M4-004), not a product verdict.
 *
 * Render-only in spirit, with the ONE exception `popover.ts` already
 * documents for "Sync now" (T8): a trigger, not a computation. Clicking
 * "Update now" invokes `apply_update`; while the transport is mid-flight
 * (checking/downloading/verifying/staging) this module polls
 * `check_for_update` at a short fixed cadence and re-renders ONLY its own
 * subtree — it never re-runs `renderPopover`, never computes a verdict, and
 * never shows a percentage/ETA (Case Law OUT) — only the current phase word.
 *
 * Both Tauri commands are landing in parallel (Stream-D/`me`, S4/S5); every
 * `invoke()` here is defensively wrapped so a not-yet-landed command fails
 * closed to "stop polling, leave the last honest state on screen" rather
 * than crashing the popover or fabricating a result.
 */
import { invoke } from "@tauri-apps/api/core";
import { renderBadge } from "./badges";
import * as copy from "./copy";
import { announce } from "./a11y";
import { buildActionButton, h } from "./dom";
import { isTauriHost } from "../tauri-host";
import { APPLY_UPDATE_CMD, CHECK_FOR_UPDATE_CMD, type BadgeState, type UpdateState, type UpdateStatus } from "../types";

/** The three transport statuses that are "still moving" — poll `check_for_update` while any of these hold. */
const IN_PROGRESS: ReadonlySet<UpdateStatus> = new Set(["checking", "downloading", "verifying", "staging"]);

/**
 * Fixed poll cadence while an update is in flight. The S4/S5 contract has no
 * cadence field of its own (unlike `WizardState.signin_interval_secs`) — a
 * conservative fixed value, flagged in `types.ts` for S11 to reconcile
 * against whatever real cadence the backend prefers.
 */
const POLL_MS = 1500;

/** Badge shape per status — `null` means "no badge" (silence-is-success for the quiet terminal states; no alarm shape for a reassured rollback). */
function badgeFor(status: UpdateStatus): BadgeState | null {
  switch (status) {
    case "checking":
    case "downloading":
    case "verifying":
    case "staging":
      return "spinner";
    case "available":
      return "update";
    case "error":
      return "triangle"; // amber, needs-attention register — NOT "bang" (reserved for CLI-unreadable, the one red)
    case "ready":
    case "up-to-date":
    case "rolled-back":
    case "idle":
    default:
      return null;
  }
}

/**
 * Builds the update section for one `UpdateState` snapshot. Returns `null`
 * for `"idle"` (silence — nothing to show, matching the header glyph's
 * "Healthy renders NO badge" precedent). `liveRegion` receives an
 * announcement on every state transition this module drives itself
 * (a11y rule 3) — the CALLER (`popover.ts`) is still responsible for
 * announcing the initial snapshot via its own `announce()` call, same as
 * every other state it renders.
 */
export function buildUpdateSection(initialState: UpdateState, liveRegion: HTMLElement): HTMLElement | null {
  if (initialState.status === "idle") return null;

  let state = initialState;
  let pollHandle: ReturnType<typeof window.setTimeout> | undefined;

  const section = h("section", {
    className: "ct-update",
    attrs: { role: "group", "aria-label": "Control Tower update" },
  });

  function stopPolling(): void {
    if (pollHandle !== undefined) {
      window.clearTimeout(pollHandle);
      pollHandle = undefined;
    }
  }

  function schedulePoll(): void {
    stopPolling();
    if (!isTauriHost()) return; // dev-fixture harness: static render only, never a fabricated progression
    pollHandle = window.setTimeout(() => {
      void invoke<UpdateState>(CHECK_FOR_UPDATE_CMD)
        .then((next) => applyState(next))
        .catch(() => stopPolling()); // command not landed yet / transient — stop rather than spin forever
    }, POLL_MS);
  }

  function applyState(next: UpdateState): void {
    state = next;
    renderBody();
    announce(liveRegion, copy.updateSectionLabel(state));
    if (IN_PROGRESS.has(state.status)) {
      schedulePoll();
    } else {
      stopPolling();
    }
  }

  function handleUpdateClick(): void {
    if (!isTauriHost()) return; // inert outside a Tauri host, same convention as every other unwired action row
    void invoke<UpdateState>(APPLY_UPDATE_CMD)
      .then((next) => applyState(next))
      .catch(() => {
        // Leave the last-known honest state on screen — never fabricate an outcome.
      });
  }

  function renderBody(): void {
    section.replaceChildren();

    if (state.status === "rolled-back") {
      section.appendChild(buildToast(state));
      return;
    }

    const row = h("div", { className: "ct-update__row" });
    const badge = badgeFor(state.status);
    if (badge) row.appendChild(renderBadge(badge, { animate: true }));

    const text = h("div", { className: "ct-update__text" });
    text.appendChild(h("p", { className: "ct-update__sentence", text: copy.updateSentence(state) }));

    const phase = copy.UPDATE_PHASE_WORD[state.status];
    const version = copy.updateVersionDetail(state);
    const detail = phase ?? version;
    if (detail) text.appendChild(h("p", { className: "ct-update__detail", text: detail }));

    row.appendChild(text);
    section.appendChild(row);

    if (state.status === "available") {
      const btn = buildActionButton(
        copy.CLI_UNREADABLE_ACTION_LABEL, // "Update now" — reused verbatim, same action (`apply_update`), no duplicate string
        copy.ACTION_EFFECT[copy.CLI_UNREADABLE_ACTION_LABEL] ?? "",
        "ct-primary-action",
      );
      btn.addEventListener("click", handleUpdateClick);
      section.appendChild(btn);
    }

    if (state.status === "error" && state.message) {
      // Plain-language backend detail, shown ONLY when it adds information beyond the fallback sentence already rendered above.
      if (state.message !== copy.UPDATE_ERROR_FALLBACK) {
        text.appendChild(h("p", { className: "ct-update__detail", text: state.message }));
      }
    }
  }

  function buildToast(rolledBack: UpdateState): HTMLElement {
    const toast = h("div", {
      className: "ct-update__toast",
      attrs: { role: "status" },
    });
    toast.appendChild(h("p", { className: "ct-update__toast-title", text: copy.UPDATE_ROLLBACK_FALLBACK }));
    const detail = rolledBack.message && rolledBack.message !== copy.UPDATE_ROLLBACK_FALLBACK ? rolledBack.message : null;
    if (detail) toast.appendChild(h("p", { className: "ct-update__toast-detail", text: detail }));
    return toast;
  }

  renderBody();
  if (IN_PROGRESS.has(state.status)) schedulePoll();

  return section;
}
