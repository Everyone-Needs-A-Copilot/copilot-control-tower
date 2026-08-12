# Fleet-dashboard operator guide

> **UNVALIDATED HYPOTHESIS (Founding Decision #9, `SOUL.md` §9 item 9).** This
> guide describes **Admin mode's** fleet dashboard — no real IT operator has
> touched it. Designed-to, not validated-by-use.

> **Status up front: the frontend renders fixtures; there is no live
> backend yet.** The fleet dashboard is `tc task get 63` (M7-S4) — as of this
> writing, `src/render/fleet.ts` + `src/fleet.html` +
> `src/dev-fixtures/fleet/*.json` (empty/all-healthy/mixed-worst-wins/
> single-host/actionable-items fixtures) exist and render the `FleetView`/
> `FleetHostView`/`FleetActionItem` shapes described below — but there is
> **no** Rust `get_fleet` Tauri command (`src/types.ts` only *reserves* the
> name, `GET_FLEET_CMD`) and no `src-tauri/src/render/fleet.rs` wiring real
> collected fleet events into it. Everything below is accurate to what the
> frontend renders **today, against fixtures** — it is not yet wired to a
> real fleet. See `../06-deployment/README.md`'s
> "what's real vs. designed" table for the same caveat applied across all of
> Admin mode, and re-check `git status`/`tc task list --prd 7` before trusting
> this days later — M7 is landing piece by piece as this guide is written.

**The HYPOTHESIS stamp is already enforced in the landed frontend code, not
just in this doc.** `src/render/fleet.ts`'s own module doc names a
`FLEET_HYPOTHESIS_STAMP` constant that `buildFleetDashboard` always renders,
non-dismissably, and says explicitly it "is not a temporary banner to be
removed once 'shipped' — it stays until a real operator has actually used
this surface." That is the correct, load-bearing behavior; this guide's own
banner above is the doc-side mirror of the same discipline, not a
duplicate invention.

## The one thing to know before anything else

**There is no fleet-health score.** No 0–100 number, no trophy ring, no
sparkline. `observability.md` §7.1 says it explicitly: *"Never a computed
'fleet health 94/100' score, trophy ring, or sparkline flourish — a number
that reads as computed-by-the-app implies a judgment the app never makes"*
(`SOUL.md`, *The Second Pilot*, Case Law). If a future build of this
dashboard ever shows you a single blended number for the whole fleet, that
is a defect against this design, not a feature to rely on. The one
percentage this dashboard is designed to show — the version-skew bar,
"83% on current SHA" — is an **honest fraction** (a count of machines on the
current SHA over total machines), never a gauge or a judgment.

## What you'll actually read: per-host worst-wins

The dashboard renders **facts, and computes no verdict of its own** — the
same invariant #1 discipline the tray icon already holds for a single
machine, applied per-row here.

**The design (`observability.md` §7.1) names four fleet states** — Healthy,
Stuck, Behind, Needs re-auth — each mapped to a specific `sync`/`auth`/
`version_skew`/safety-event condition, by worst-wins precedence (the same
precedence the tray glyph already uses):

| State | Sourced from | What the row shows |
|---|---|---|
| **Healthy** | `sync.status == healthy`, no open safety events | The quietest row: a plain dot + "In sync" — no emphasis (silence-is-success, same as the tray). |
| **Stuck** | `sync.status == needs-attention` with an unhealable `fail`, or an unresolved `policy-conflict`/`blocked` safety event | Amber badge + a plain-language cell naming the failing checker/host — never a bare color alone. |
| **Behind** | `version_skew.behind_by` non-null, or `held_for_approval` non-empty | Dot badge; feeds the aggregate version-skew fraction. |
| **Needs re-auth** | `auth[].state ∈ {expired, revoked}` for a required layer, or an open `auth-revoked`/`sig-fail` safety event | Key badge; a revoked-state row links directly into the safety-escalation feed below, not just the table. |

**What the landed frontend actually carries, today, is a step simpler — flag,
not a defect.** `src/types.ts`'s `FleetHostView` (as shipped) does not carry
a distinct 4-value fleet-state field at all: it carries the CLI's own
`status: CliStatus` (the same ~10-value doctor status the tray already uses)
plus `badge_state: BadgeState` directly, computed CLI-side and passed through
unchanged — no fleet-specific Healthy/Stuck/Behind/Needs-re-auth enum exists
in code. This is consistent with the *spirit* of §7.1 (still per-host,
still worst-wins, still zero app-side judgment) but is a narrower shape than
the four-named-state table above documents; whether a future pass collapses
`CliStatus`/`BadgeState` into the four named states, or whether §7.1's table
should instead be read as illustrative framing rather than a literal field
requirement, is unresolved — flagged for whoever wires S9's live command,
not fixed here.

**Badges reuse the same 12-token vocabulary the tray already uses** —
`render::BADGE_VOCABULARY` in `src-tauri/src/render/mod.rs` (`pass`, `ring`,
`key`, `update`, `triangle`, `wrench`, `clock`, `cloud-slash`, `bang`,
`spinner`, `hollow`, `none`) — shape + color + a plain-language cell, legible
in grayscale, never color alone. `render/fleet.ts`'s own module doc confirms
this is deliberate: "the SAME badge vocabulary... never a second badge
vocabulary for Earl." An operator reading the fleet table sees the same
visual language a Bob sees on his own tray, just aggregated into rows.

## The safety-escalation feed (a separate, always-visible list)

Sourced **only** from the safety channel (`observability.md` §3) — never
from the health/analytics side. Each row is `category` + `layer`/`identity`
(when present) + `occurred_at` + `escalation_deadline`. This is the wire
realization of "IT notified is never a no-op" (`architecture.md` §9): every
item here is the same class of event the Bob-agency router's **Escalate-to-
IT** lane produces (held-major-awaiting-approval, security-shadow-auto-
suspended, auth-revoked, policy-denial) — actionable, content-free, no
free-text `detail` string ever appears here.

**What it will never show you:** a personal-layer item name, a file path, a
prompt/completion, or anything from the analytics channel. The safety and
analytics channels are structurally separate (`observability.md` §1) — this
feed is the safety side only.

## What this dashboard is not

- **Not a continuous telemetry read of preflight.** Preflight
  (`../06-deployment/standup-runbook.md` step 2) is a one-time, on-demand
  red/green check run before rollout — it is a related Admin-mode surface,
  not part of this dashboard's own wire format (`observability.md` §7.1 says
  this explicitly).
- **Not visible to ENAC.** Per `architecture.md` §9 and `SOUL.md`'s pure-OSS
  founding decision (*The Ledger That Learns to Bill*), there is no
  ENAC-side version of this dashboard — analytics flows to your org's own
  collector, safety escalations to your own `AdminContact`, and ENAC
  receives zero bytes from any deployed fleet.
- **Not a hosted or paid tier.** Nothing about this dashboard, the telemetry
  it will render, or Admin mode generally is (or will ever be) a paid SKU or
  hosted service — pure OSS, free forever (`SOUL.md` §9 item 1).

## Prerequisites once this exists

The dashboard renders **collected fleet events** — where those come from
(an org's own collector query API) is itself an open, owner-gated item
(G-M7-3, `../06-deployment/README.md`'s owner-gated table item 8) not yet
defined. It also depends on the opt-in analytics gate
(`../06-deployment/standup-runbook.md` step 6) for the health/usage half, and
the mandatory `AdminContact` safety channel (step 5) for the
escalation-feed half — an org with neither configured will have nothing for
this dashboard to show beyond an empty state, which is the correct,
honest rendering of "nothing has been collected," never a fabricated
"all healthy."

## Cross-references

- [`observability.md`](observability.md) §7 — the canonical dashboard spec
  this guide translates into operator language.
- `../06-deployment/standup-runbook.md`
  — where enabling the two feeds this dashboard reads fits in the standup
  sequence.
- `../06-deployment/README.md` — the
  shipped-vs-designed table this guide's status banner points back to.
