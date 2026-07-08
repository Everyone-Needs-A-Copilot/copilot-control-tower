/**
 * M7 S4 (task 63) — the IT fleet dashboard render (Admin-facing, the "Fleet
 * dashboard" item in `50-ux-design.md`'s SURFACE 3 / `60-ui-design.md` § 6).
 * Renders `types.ts`'s `FleetView` — a per-host worst-wins status table plus
 * a content-free actionable-items feed — and nothing else. Render-only, the
 * SAME discipline `render/bob_lane.ts`/`render/security_banner.ts` already
 * establish: this module computes NO verdict about a host's health; it only
 * ever renders the `FleetHostView`/`FleetActionItem` snapshot it's given.
 *
 * **HYPOTHESIS surface (Founding Decision #9, SOUL.md § 9).** No real IT
 * operator has ever touched a fleet dashboard — `buildFleetDashboard` always
 * renders a visible, non-dismissable stamp saying so (`FLEET_HYPOTHESIS_
 * STAMP` below). This is not a temporary banner to be removed once "shipped"
 * — it stays until a real operator has actually used this surface.
 *
 * **FORBIDDEN, permanently (FF-M7-NOSCORE) — the whole point of this file.**
 * No aggregate/blended fleet-health score, percentage, "/100", trophy ring,
 * or sparkline flourish anywhere in this module, now or in any future edit.
 * `types.ts`'s `FleetView` has no field to carry one; this module adds none
 * of its own. A fleet is the SET of hosts (`view.hosts.length`, a plain
 * count, is the only fleet-wide number this module ever renders) — never a
 * judgment blended across them. Per-host status is worst-wins, the SAME
 * precedence the tray glyph already uses (`badges.ts`'s `BadgeState`
 * vocabulary, reused verbatim here — never a second badge vocabulary for
 * Earl). Status is carried by SHAPE + plain-language text, never colour
 * alone (a11y hard rule — applies to Earl exactly as it applies to Bob).
 *
 * **Actionable-items feed is content-free by construction.** Each
 * `FleetActionItem` carries only `kind` (M6's `ItSignalKind`) + `machine_id`
 * — this module renders exactly those two facts and never a free-text
 * detail or personal item name, because the type it renders has no field to
 * carry one (see `types.ts`'s own doc).
 */
import { renderBadge, BADGE_SHAPE_NAME } from "./badges";
import { h } from "./dom";
import type { FleetActionItem, FleetHostView, FleetView, ItSignalKind } from "../types";

/**
 * PLACEHOLDER (net-new, not yet in `70-copy-voice.md` — flag for a cw pass).
 * The Admin-surface HYPOTHESIS stamp (Founding Decision #9). Plain, factual,
 * never alarmist — same register the rest of the product's copy uses; this
 * is a scope disclosure, not a warning.
 */
export const FLEET_HYPOTHESIS_STAMP =
  "This fleet dashboard is an early, untested design — no real IT operator has used it yet.";

/** Verbatim from `70-copy-voice.md` § Empty States — "Fleet dashboard, no machines yet (IT)". */
export const FLEET_EMPTY_STATE =
  "No machines are reporting yet. Once you push the app and profile, they'll self-provision and appear here.";

/** PLACEHOLDER — net-new Admin chrome; no exact row exists for these labels in `70-copy-voice.md`. */
export const FLEET_TABLE_TITLE = "Fleet";
export const FLEET_COLUMN_MACHINE = "Machine";
export const FLEET_COLUMN_STATUS = "Status";
export const FLEET_ACTIONABLE_TITLE = "Actionable items";
/** PLACEHOLDER — shown only when `hosts.length > 0` but no host has any actionable item. */
export const FLEET_ACTIONABLE_EMPTY = "Nothing waiting on IT right now.";

/**
 * Per-host status label, ADAPTED from `70-copy-voice.md` § A's "IT/Admin-
 * facing line" column. Those templates assume per-event `<product>`/
 * `<layer>`/`<n>`/`<key>`/`<ts>` fields `FleetHostView` doesn't carry (this
 * contract is per-HOST worst-wins, not per-finding) — generalized here by
 * dropping the fields this DTO doesn't have. Rows that already read
 * correctly generalized are kept verbatim; the rest are flagged PLACEHOLDER
 * for a cw pass once the real per-host fields (if any) are decided.
 */
export const FLEET_STATUS_LABEL: Record<FleetHostView["status"], string> = {
  healthy: "Healthy — every product on the current version across all layers, signed in.",
  syncing: "Sync in progress.", // PLACEHOLDER — source line names <product>/<layer>/<phase>
  "signed-out": "Needs sign-in — awaiting device-flow sign-in.", // PLACEHOLDER — source line names <user>
  "needs-attention": "Needs a repair — auto-repair failed.", // PLACEHOLDER — source line names <finding-id>
  "update-available": "Update available.", // PLACEHOLDER — source line names <product>/<layer>/<n>
  "it-config-incomplete":
    "Config incomplete — a required key is missing or malformed. Escalated to AdminContact.", // adapted, dropped <key>
  "waiting-for-network": "Foundation-only complete — company layers pending network.", // adapted, dropped seed
  offline: "Offline — rendering cached state.", // adapted, dropped last-sync timestamp
  "setup-needed": "Wizard not completed.", // adapted from "Wizard not completed on <machine>." — machine is the row itself
  "updating-app": "Self-update staging; watchdog gating on liveness heartbeat.", // verbatim
};

/**
 * PLACEHOLDER (all rows) — content-free per-kind labels for the actionable-
 * items feed. Adapted from `70-copy-voice.md` § C (Escalation-to-IT
 * messages) and `observability.md` § 2.1's safety-channel category table,
 * generalized to drop the free-text/finding-specific fields `ItSignalKind`
 * itself never carries (content-free by construction) — a cw pass should
 * confirm final wording. The switch below is exhaustive over `ItSignalKind`
 * on purpose: a future 14th variant fails to compile here rather than
 * silently falling back to a blank label.
 */
export function fleetActionItemLabel(kind: ItSignalKind): string {
  switch (kind) {
    case "held_major_awaiting_approval":
      return "A major update is waiting on your approval.";
    case "security_shadow_auto_suspended":
      return "Kept this machine safe — a security fix replaced an overridden component.";
    case "auth_revoked_deprovision_offer":
      return "Access revoked — deprovision offer available.";
    case "policy_denial":
      return "Blocked by policy — needs your review.";
    case "persistence_disabled":
      return "Startup was turned off — this Mac may stop staying up to date.";
    case "notifications_disabled":
      return "Notifications are off — safety alerts may not reach this user.";
    case "bob_item_timed_out":
      return "A reminder to the user went unanswered — now with you.";
    case "prune_needs_review":
      return "A removal Bob couldn't judge on his own — needs your review.";
    case "repair_needs_review":
      return "A repair needs your review.";
    case "unrecognized_event":
      return "An unrecognized event — held for your review rather than guessed at.";
    case "deprovision_triggered":
      return "Deprovision triggered.";
    case "deprovision_ambiguous":
      return "Deprovision — ambiguous, needs your review.";
    case "signature_failure":
      return "Signature verification failed.";
  }
}

/** VoiceOver label for one fleet row — names the machine + its status in words, never "row 3". */
function fleetRowLabel(host: FleetHostView): string {
  return `${host.machine_id}: ${FLEET_STATUS_LABEL[host.status]}`;
}

function buildFleetRow(host: FleetHostView): HTMLTableRowElement {
  const row = h("tr", {
    className: "ct-fleet-row",
    attrs: {
      role: "row",
      tabindex: "-1",
      "data-role": "fleet-row",
      "data-machine-id": host.machine_id,
      "aria-label": fleetRowLabel(host),
    },
  });

  const machineCell = h("td", { className: "ct-fleet-row__machine", attrs: { role: "cell" } });
  machineCell.appendChild(h("span", { className: "ct-fleet-row__machine-id", text: host.machine_id }));
  row.appendChild(machineCell);

  const statusCell = h("td", { className: "ct-fleet-row__status", attrs: { role: "cell" } });
  const statusWrap = h("span", { className: "ct-fleet-row__status-wrap" });
  statusWrap.appendChild(renderBadge(host.badge_state));
  statusWrap.appendChild(
    h("span", { className: "ct-fleet-row__status-text", text: FLEET_STATUS_LABEL[host.status] }),
  );
  statusCell.appendChild(statusWrap);
  row.appendChild(statusCell);

  return row;
}

/**
 * Roving-tabindex keyboard nav across fleet rows (Up/Down/Home/End), the
 * SAME pattern `render/a11y.ts`'s `attachProductListKeyboard` already
 * establishes for the popover's product list — kept local to this module
 * rather than added there, since this task owns `render/fleet.ts` only.
 * Native Tab order still reaches the table (the first row is always a Tab
 * stop); arrow keys are an ADDITIVE enhancement, never a replacement.
 */
function attachFleetTableKeyboard(tbody: HTMLElement): void {
  const rows = () => Array.from(tbody.querySelectorAll<HTMLElement>("[data-role='fleet-row']"));

  tbody.addEventListener("focusin", (evt) => {
    const target = evt.target as HTMLElement;
    if (target.dataset.role !== "fleet-row") return;
    rows().forEach((r) => {
      r.tabIndex = -1;
    });
    target.tabIndex = 0;
  });

  tbody.addEventListener("keydown", (evt) => {
    const target = evt.target as HTMLElement;
    if (target.dataset.role !== "fleet-row") return;
    const all = rows();
    const i = all.indexOf(target);

    switch (evt.key) {
      case "ArrowDown":
        evt.preventDefault();
        all[i + 1]?.focus();
        break;
      case "ArrowUp":
        evt.preventDefault();
        all[i - 1]?.focus();
        break;
      case "Home":
        evt.preventDefault();
        all[0]?.focus();
        break;
      case "End":
        evt.preventDefault();
        all[all.length - 1]?.focus();
        break;
    }
  });

  const first = rows()[0];
  if (first) first.tabIndex = 0;
}

function buildFleetTable(hosts: FleetHostView[]): HTMLElement {
  const section = h("section", {
    className: "ct-fleet-table-section",
    attrs: { "aria-labelledby": "ct-fleet-table-title" },
  });
  section.appendChild(h("h2", { className: "ct-fleet-title", text: FLEET_TABLE_TITLE, attrs: { id: "ct-fleet-table-title" } }));

  if (hosts.length === 0) {
    section.appendChild(h("p", { className: "ct-fleet-empty", text: FLEET_EMPTY_STATE, attrs: { role: "status" } }));
    return section;
  }

  const table = h("table", {
    className: "ct-fleet-table",
    attrs: { role: "table", "aria-label": FLEET_TABLE_TITLE },
  });

  const thead = h("thead", {});
  const headRow = h("tr", { attrs: { role: "row" } });
  headRow.appendChild(h("th", { text: FLEET_COLUMN_MACHINE, attrs: { role: "columnheader", scope: "col" } }));
  headRow.appendChild(h("th", { text: FLEET_COLUMN_STATUS, attrs: { role: "columnheader", scope: "col" } }));
  thead.appendChild(headRow);
  table.appendChild(thead);

  const tbody = h("tbody", { attrs: { role: "rowgroup" } });
  hosts.forEach((host) => tbody.appendChild(buildFleetRow(host)));
  table.appendChild(tbody);

  section.appendChild(table);
  attachFleetTableKeyboard(tbody);

  return section;
}

function buildActionableItemRow(item: FleetActionItem): HTMLElement {
  return h("li", {
    className: "ct-fleet-action-item",
    attrs: { "data-kind": item.kind, "data-machine-id": item.machine_id },
    text: `${item.machine_id} — ${fleetActionItemLabel(item.kind)}`,
  });
}

/**
 * The safety-escalation feed (`observability.md` § 7.1) — a separate,
 * always-visible list sourced only from the M6 EscalateIt lane, flattened
 * across every host. Nothing rendered here is ever also shown to Bob (the
 * Govern-queue rule) — this module has no code path that could, since it
 * never receives Bob-facing state at all.
 */
function buildActionableFeed(hosts: FleetHostView[]): HTMLElement {
  const section = h("section", {
    className: "ct-fleet-feed-section",
    attrs: { "aria-labelledby": "ct-fleet-feed-title" },
  });
  section.appendChild(
    h("h2", { className: "ct-fleet-title", text: FLEET_ACTIONABLE_TITLE, attrs: { id: "ct-fleet-feed-title" } }),
  );

  const items = hosts.flatMap((host) => host.actionable_items);

  if (items.length === 0) {
    section.appendChild(h("p", { className: "ct-fleet-feed-empty", text: FLEET_ACTIONABLE_EMPTY, attrs: { role: "status" } }));
    return section;
  }

  const list = h("ul", { className: "ct-fleet-feed", attrs: { role: "list", "aria-label": FLEET_ACTIONABLE_TITLE } });
  items.forEach((item) => list.appendChild(buildActionableItemRow(item)));
  section.appendChild(list);

  return section;
}

/**
 * Builds the whole fleet dashboard into `root` (clearing any previous
 * render first, same replace-in-place convention `render/settings.ts`/
 * `render/wizard.ts` use). Returns nothing — this module is a pure DOM
 * builder, same shape as every other `render/*.ts` module.
 */
export function buildFleetDashboard(root: HTMLElement, view: FleetView): void {
  root.innerHTML = "";

  root.appendChild(
    h("p", { className: "ct-fleet-hypothesis-stamp", text: FLEET_HYPOTHESIS_STAMP, attrs: { role: "note" } }),
  );

  root.appendChild(buildFleetTable(view.hosts));
  root.appendChild(buildActionableFeed(view.hosts));
}

/** Re-exported so a headless verification pass can assert the shape family without duplicating it. */
export { BADGE_SHAPE_NAME };
