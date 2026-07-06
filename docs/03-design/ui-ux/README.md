# UI/UX design track — Product Creation Copilot

This is the visual/interaction design track for Control Tower. **Read this before invoking PCC.**

## Scope: do not re-run discovery

We already did the systems architecture ([`../../01-architecture/architecture.md`](../../01-architecture/architecture.md)) and the engineering PRD ([`../../02-prd/prd.md`](../../02-prd/prd.md)). The hard decisions — process model, status precedence, the wizard's steps, the escalation ladder, the Admin-mode flow — are locked and validated against two adversarial red-teams. **Do not send Product Creation Copilot back through its own Discovery phase to re-derive what the product is.** Its job here is narrower and later-stage: turn an already-decided system into the four concrete surfaces below, and (per `00-overview/soul.md`) help ratify the soul as a side effect of that design conversation, not as a precondition for starting it.

## The four surfaces to design

1. **The menu-bar dropdown + status states** — the icon and its ten states (Setup-needed, IT-config-incomplete, Healthy, Syncing, Update-available, Needs-attention, Signed-out, Offline, Waiting-for-network, Updating-app) and the dropdown actions (Sync now, Repair, What changed, Add a skill, Sign in, Hosts ▸, Preferences, Quit). The top line is always a plain-language sentence naming the failing host, never a blended verdict.
2. **The first-run wizard panels** — Welcome → detect host(s) → choose host → sign in (8-char device-flow code) → company → department → choose products → pull repos → materialize + verify → teach — **including the silent managed path** (a progress bar only, when IT has pushed `DisableWizard=true`).
3. **The Admin-mode setup UI** — the seed generator, the MDM-profile generator, preflight validation (red/green report), and the fleet dashboard (who's healthy, stuck, behind, needs re-auth).
4. **Notifications** — the rare, high-trust Bob-facing alerts (sign-in approve, "commit your dirty work"), scoped tightly per the escalation model so they never become noise.

## Inputs to feed PCC

Point PCC at, in this order: `architecture.md` §2 (status model & menu), §4 (first-run wizard), §8 (Admin mode, MDM & IT enablement), and §9 (the Bob-agency escalation model) — plus the state machine embedded in §2's precedence table and the wizard's step list in §4. These four sections are the entire contract PCC needs; nothing outside them should change the design's substance.

## Outputs wanted

A **Figma file** (screens for all four surfaces, all states) and a **Storybook component library** (the reusable primitives: status icon, dropdown row, wizard panel, progress states, dashboard card). Both land back in this repo under `docs/03-design/ui-ux/` (Figma link + exported specs, Storybook source or a pointer to where it's vendored) so the engineering workstreams in the PRD can implement directly from them.

## Brand

The mark is the **aviator-sunglasses silhouette**, color `#2D294E`, deliberately **template-icon friendly** (renders correctly as a monochrome macOS menu-bar template image across light/dark and all ten status overlays).

## How to invoke

Local path: `/Volumes/Dev/Sites/COPILOT/product-creation-copilot`. Run `claude` in that repo and say "Read quickstart.md and let's begin," then steer it directly at design (not discovery) using the inputs above.
