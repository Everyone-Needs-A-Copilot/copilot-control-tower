# Copilot Control Tower: Native macOS Interaction Design Spec

Stage 2 of 3 of the native-app redesign (Stage 1 = structure / IA / state
inventory in `control-tower-native-experience-architecture.md`; this = the
**interaction**: flows, navigation, state transitions, focus/keyboard/VoiceOver,
and interaction patterns; Stage 3 = the visual system by uids). Grounded in and
consistent with the **corrected CSE model**: the Stage 1 architecture (surfaces
S1 to S13), `docs/10-reference/copilot-solutioning-ecosystem.md`,
`docs/10-reference/cse-alignment-decisions.md` (D1 to D10),
`docs/03-design/three-role-journeys.md`, `docs/01-architecture/cli-contract.md`
(the `copilot layers` / `layers join` verbs), the closed sets in `src/types.ts`,
`SOUL.md`, and `CLAUDE.md`.

**This is a corrected rewrite.** The prior interaction spec was built on a wrong
domain (a catalog of *products*, and a pervasive MDM/managed-fleet framing). Its
**interaction mechanics are excellent and are reused wholesale**: the
`.accessory` activation-policy spine, the popover-transient-versus-panel-and-sheet-
non-transient rule, the device-flow sheet behavior (no countdown, no token), the
named-phase materialize with no ETA, holding as first-class, the eight-state
coverage, the keyboard/VoiceOver model, Reduce-Motion, and the empty/loading
strategy. The **domain is replaced**: components not products, entitled layers,
department discovery and join (S11), the shared-versus-personal integration split
(S12 vs S5), personal-key multi-machine sync (S13), one install path (no managed
lane, S2b removed), and an Admin mode of Onboarding plus Governance with no MDM
and no fleet-as-center.

This spec is **wireframe-level and implementer-ready**: it describes layout in
words and ASCII, defines every interaction's trigger, rules, and feedback, covers
all eight interactive states, and maps keyboard and VoiceOver traversal. It does
**not** specify pixels, color, or type (Stage 3). Interaction copy is written as
**placeholders in the correct voice**; final microcopy is a separate `cw` concern.

Hard constraints honored throughout: the app **renders, never computes** (every
verdict, every entitlement fact, every seed validation comes from a parsed CLI
field, invariant #1); **role separation is structural** (a user can never reach an
Admin action); **no time estimates, countdowns, or ETAs** of any kind; **no
aggregate health scores**; **no em-dashes** in any copy; **no product/output
catalog**; **no MDM anything**; closed sets from `types.ts` are authoritative and
no state outside them is invented.

---

## 0. Reading guide and design method

Each major flow carries its own **JTBD** statement, and every genuinely novel flow
(no settled macOS precedent to inherit) carries a **Concepts Considered** block
scored against Nielsen's heuristics with a selection rationale. Flows that inherit
a settled Apple pattern (Settings, About, standard sheets, source-list windows)
name the inherited pattern and move to states and keyboard behavior directly, per
Jakob's Law: the user spends most of their time in other macOS apps and should not
have to relearn conventions here.

The eight interactive states committed to for every interactive element:
**default, hover, focus, active, disabled, loading, error, empty**. Where a state
is not applicable, that is stated with a reason rather than omitted.

Voice anchor (SOUL): the air-traffic controller. Spare, factual, unhurried.
Silence is the success signal. Past-tense for anything already handled. Names the
failing component, layer, or host, never a blur. It says "component" and the
copilot names (Knowledge, CLI, Claude, Codex), never "product".

**One vocabulary correction runs through everything.** Where the prior spec (and
the still-landed `ProductView` / `WizardProductOption` DTOs) say "product", the
experience reads **component**: the four CSE tooling copilots (Knowledge / CLI /
Claude / Codex), synced across the four inheritance layers (foundation / org /
department / personal) the user is **entitled** to. The `ProductView.product ->
component` field rename is TA code work (Stage 1 open decision 6); this spec treats
the field as the component view today and every user string names a copilot or
"component", never a built output (Insights, Pipeline, Method never appear).

---

## 1. Global navigation model and window behavior

### 1.1 JTBD

> When something about my Copilot environment might need me, I want to learn the
> truth and reach the one thing I can do about it from the menu bar, so I can get
> back to my work without hunting through windows.

### 1.2 The activation-policy spine (reused unchanged, load-bearing)

Control Tower is an **`NSApplication.ActivationPolicy.accessory`** app: no Dock
icon, no default menu bar of its own, present only as an `NSStatusItem`. This one
choice governs everything below, because an accessory app's windows do not come
forward the way a regular app's do.

Rules that follow from `.accessory`:

- The **popover (S1)** is the home and needs no activation: an `NSPopover` shows
  transiently anchored to the status item and tracks it automatically.
- Any **window** (wizard S2, Settings S3, Admin S4, About S10) and any **standalone
  panel** (steady-state sign-in S5, dirty-work S6) must call
  `NSApp.activate(ignoringOtherApps: true)` **before** `makeKeyAndOrderFront` so it
  reliably comes to the foreground from a background utility. This is a documented
  interaction requirement, not an implementation footnote: without it the window
  can open behind the active app and the user never sees it.
- When the **last** such window closes, the app **returns to pure accessory
  presence** (no lingering menu bar, no Dock icon). It does not `.regular`-promote
  and stay promoted.
- **Temporary promotion window:** while any Control Tower window is key, the app
  may present as `.regular` so it has a real application menu (Quit, Hide, standard
  Edit menu for text fields, Window menu). On the last window close it demotes back
  to `.accessory`. This gives every window a correct menu bar and command-key
  editing without giving the idle app a Dock presence.

### 1.3 Surface-by-surface open / close / modality / focus

The one structural change from the prior spec: **S2b (managed silent first run) is
gone** (D4, no MDM, one install path). Every user reaches the same wizard window.
S11, S12, S13 are added.

| Surface | Container | Opens via | Modality | Dismiss | Focus on open |
|---|---|---|---|---|---|
| S1 Popover | `NSPopover` (transient) | Left-click glyph; wizard/notice may request-show | Modeless, transient | Click-away, Esc, click glyph again, app deactivate | First actionable control, else status sentence |
| S1 Right-click menu | `NSMenu` | Right-click / Ctrl-click glyph | Menu (modal while open) | Select, Esc, click-away | First item |
| S2 Wizard (only path) | Titled `Window`, centered | First run; "Set up" action | **Modeless** window | Its own controls only; Esc does not kill setup | Step title / first control |
| ~~S2b~~ | **Removed (D4)** | n/a | n/a | n/a | n/a |
| S3 Settings | `Settings` scene | `Cmd-,`; "Preferences" action; menu item | Modeless | Close box, `Cmd-w` | Selected tab's first control |
| S4 Admin | Distinct `Window` + sidebar | Capability-gated entry (§5.1) | Modeless | Close box, `Cmd-w` | Sidebar selection |
| S5 Personal sign-in (from wizard) | **Sheet** on wizard window | Wizard "Personal sign-in" step | **Modal to the wizard window only** (app modeless) | Its own Done/Cancel | The copyable code |
| S5 Personal sign-in (steady state) | Standalone **panel** (`NSPanel`, non-transient) | Bob-lane "Sign in" prompt / popover action | Modeless, floating | Its own Done/Cancel; persists on focus loss | The copyable code |
| S6 Dirty-work prompt | `UNNotification` then small **panel** | Router emits `dirty-wip` prompt | Modeless panel | Its own actions; persists | Primary action |
| S7 Conflict chooser (author only) | **Modal sheet** on Admin/author window | Author publish collision | Modal to that window | Choice buttons only | The recommended option |
| S8 Deprovision | User: quiet Bob-lane notice in popover. IT: `DeprovisionView` panel in Admin > Governance | Rendered when CLI reports it | Modeless | Read-only; user notice self-clears on next poll | Notice text |
| S9 Update / rollback | Popover progress line + past-tense notice; never a modal | Rendered from `UpdateState` | Modeless, inline | Inline, no dialog | n/a (no interaction) |
| S10 About | Standard About `Window` | Menu / right-click "About" | Modeless | Close box | n/a |
| **S11 Dept discovery + join** | Wizard step **and** standing Settings panel; popover "Join available" row | Wizard flow; Settings > Components & Layers; popover row | Modeless (never a modal) | Standard controls | The layers list / the "Join" action on a joinable row |
| **S12 Shared integrations** | Read-only region in popover and Settings > Integrations | Rendered when entitled | Modeless, read-only | n/a (read-only) | n/a (no action target) |
| **S13 Personal-key sync** | Settings > Personal Key Sync tab | Settings | Modeless | Standard controls | The enable control / status |

**Why the popover is transient but the two prompt surfaces are panels (reused,
still load-bearing):** a transient `NSPopover` auto-dismisses on focus loss, which
is correct for glanceable status (the user looks, learns, leaves) but **fatal** for
the two flows that require the user to leave the app: device-flow sign-in (leave to
Safari, the code must stay visible) and a dirty-work decision (the user may go
check their files first). Those two get non-transient containers. This is the
single most important window-behavior rule in the product, and it is why S5 and S6
are never hosted in the popover except in the honest notifications-denied fallback
(§4.2, §6.4). **S11 is not one of these:** join is a durable, revisitable surface
(entitlement changes over time), so it lives in Settings and the wizard, and only
its *entry point* (a quiet "Join available" row) appears in the transient popover.

**Modal vs modeless discipline (SOUL "as little app", Nielsen #3 user control):**
almost nothing is app-modal. Only two things block, each its own window not the
app: (a) the personal sign-in **sheet** blocks its own wizard window while a device
flow is live, and (b) the conflict **sheet** blocks its own author window because
returning a choice is the point of opening it. Nothing ever blocks the whole app;
the menu-bar glyph stays live and honest at all times, even while a window is open.
**Department join is deliberately never modal:** it is a standing list the user
returns to, not a blocking decision.

### 1.4 Keyboard access to the menu-bar item (reused unchanged)

macOS does not give third-party `NSStatusItem`s a global activation shortcut, so
the honest interaction design is:

- The status item is **fully keyboard and VoiceOver reachable** via the system
  status-menu region. It exposes `accessibilityLabel` = the current status sentence,
  `accessibilityRole` = button, and an `accessibilityValue` naming the badge (for
  example "needs sign-in", "a department is available to join").
- Activating it (VO-Space, or Return when focused via the status region) shows the
  popover and moves focus into it.
- We do **not** register a private global hotkey (it would be a user-domain
  configurable the security posture avoids, and it collides with user shortcuts).
  Flagged as an open question (§7); default is no.

### 1.5 Multi-window behavior (reused, minus the managed exclusivity note)

- **At most one instance** of each of Settings, Admin, and the wizard.
  Re-triggering "Preferences" when Settings is already open **brings the existing
  window forward and re-activates**, never spawns a second (Nielsen #4).
- Admin and Settings may be open **at the same time** (different authorities); each
  is independent and modeless.
- The **wizard is exclusive on first run**: while it is open, Settings and Admin
  entry points are inert (the machine is not yet set up). After first run the wizard
  container is not reachable again (re-setup and later department joins happen
  through Settings, §4.6, §2.3).
- Standalone panels (steady-state sign-in, dirty-work) **float above** windows
  (`.floating` level) so a live decision is never buried, but they do not steal
  focus from typing in another app until the user chooses to act.

### 1.6 The right-click menu (S1 minimal `NSMenu`, reused)

Fixed, tiny, Hick's-Law-short. Exactly: **About Copilot Control Tower**,
**Preferences...** (`Cmd-,`), a separator, **Quit** (`Cmd-q`). No status, no
actions, no toggles live here; the popover is where status and action live.
**"Open Administration..."** appears here **only** when `admin_capable` is true
(§5.1), and when absent it leaves no gap or disabled row (structural hiding).

---

## 2. The popover (S1): the user's home, on the corrected domain

### 2.1 JTBD

> When I glance at the menu bar, I want one honest sentence about whether my
> copilots are current across the layers I belong to, plus the single next thing I
> can do, so I know in half a second whether I can ignore it.

### 2.2 Layout regions (corrected: components, join-available, two registers)

Fixed-width (approx 360pt) vertically-stacked column of up to six regions. Regions
appear **only when they carry information**; an all-fine machine shows regions 1 and
2 and nothing else. Silence is the design.

```
┌───────────────────────────────────────────────┐
│ REGION 1 - STATUS HEADER                        │
│  [glyph] Status sentence (one line, honest)     │  HeaderView.sentence
│          host name, quiet, secondary            │
├───────────────────────────────────────────────┤
│ REGION 2 - COMPONENT x ENTITLED-LAYER TREE      │
│  ▸ Claude Copilot            [pass dot]         │  ProductView[] (= component view)
│  ▾ CLI Copilot               [key badge]        │
│       foundation             [pass dot]         │  LayerView[] (disclosed)
│       org                    [pass dot]         │
│       department             [pass dot]         │
│       personal               [key badge]        │
│  ▸ Codex Copilot             [pass dot]         │
│  ▸ Knowledge Copilot         [pass dot]         │
├───────────────────────────────────────────────┤
│ REGION 3 - JOIN AVAILABLE (only if entitled &   │
│            not joined)                           │
│  A department is available to join: Sales       │  from copilot layers --json
│                                     [Join]      │
├───────────────────────────────────────────────┤
│ REGION 4 - INTEGRATIONS (two separated registers)│
│  SHARED  (entitled, no sign-in)                 │  S12, read-only
│    Salesforce  · available                      │
│    Workday     · available                      │
│  PERSONAL (your accounts)                       │  S5 register
│    Slack       · needs sign-in       [Sign in]  │
├───────────────────────────────────────────────┤
│ REGION 5 - ACTION ROW (0 to 3 buttons)          │
│  [Sync now] [What changed]                      │
├───────────────────────────────────────────────┤
│ REGION 6 - BOB LANE                              │
│  prompt (1, actionable)  OR  notices (n)        │  BobLaneView
│  [security banner - un-dismissable]             │  SecurityBanner (separate)
└───────────────────────────────────────────────┘
                (footer, borderless)
  Preferences...            Set up...   (context)
```

- **Region 1 status header** renders `HeaderView.sentence` verbatim (never
  reworded, never fabricated) with the worst-wins glyph to its left (same
  `BadgeState` as the tray). Host name below, quiet. **Always present.** If the CLI
  gives no sentence, a neutral parsed default shows, never an invented verdict.
- **Region 2 component tree** renders `products[]` **as the component-currency
  view**: one disclosure row per CSE component (Knowledge / CLI / Claude / Codex),
  each with a worst-wins badge, expanding to its `layers[]` cells (foundation / org
  / department / personal), each with its own `badge_state` and `detail`. **This is
  the corrected core: components across entitled layers, never a product list.** A
  layer the user is **not** entitled to renders as an honest empty / `none` slot
  (shown, not hidden), never a fabricated pass. The prior `DeptProjectView` nested
  sub-group is **removed** (D8): no project ever nests inside a layer.
- **Region 3 Join available** (new, S11): appears only when `copilot layers` reports
  an entitled, not-yet-joined layer. Detailed in §2.5.
- **Region 4 Integrations** (new split, S12 + S5): two visibly separate labeled
  sub-regions that never merge. Detailed in §2.6.
- **Region 5 action row** holds the small closed action set (§2.7), 0 to 3 buttons.
- **Region 6 Bob lane** renders `BobLaneView` plus the separate `SecurityBanner`.

### 2.3 Component tree disclosure interaction (reused mechanics, corrected copy)

**Microinteraction: disclose a component row**
- *Trigger:* click the row's disclosure triangle, click anywhere on the component
  row, Right-arrow when focused, or VO-expand.
- *Rules:* toggles that component's expansion. State is remembered for the session.
  A component with a non-`pass` worst severity is **auto-expanded on first open of a
  session** so the failing layer is visible without a click (Fitts + honesty).
- *Feedback:* triangle rotates 90deg, rows below slide in. Respects Reduce Motion
  (§6.5): cross-fade, no slide.
- *Loops:* a returning user with a fault always lands on it expanded; a healthy
  returning user keeps their collapsed arrangement.

Layer cells are **leaf, read-only** status lines. They never open anything; a layer
carrying an actionable state contributes the corresponding action to Region 5 (a
`key`-badged personal layer is why "Sign in" appears). Clicking a cell does nothing
destructive; it may reveal a truncated `detail` inline (hover/focus shows full
`detail` as a `.help` tooltip and via the VoiceOver value). **A not-entitled layer
cell** shows as a quiet `none` slot with a `detail` such as "You are not in this
layer" (honest slot-showing, never a fake pass, never hidden).

### 2.4 The twelve popover states and what each shows (corrected)

Each state changes Region 1's sentence + glyph, which of Regions 2 to 6 appear, and
which actions are live. Badge tokens are the `BadgeState` closed set; statuses are
`CliStatus` plus the app-owned `cli_unreadable`. The one added shape rule from
Stage 1: **`hollow` (setup-needed) is also the honest shape for an entitled-not-
synced layer when the machine has no joined layers yet.** An entitled-not-synced
department does **not** nag the tray otherwise; it is a quiet Region 3 row.

| State | Glyph | Region 1 sentence (placeholder voice) | Tree | Join row | Actions live | Bob lane |
|---|---|---|---|---|---|---|
| **Healthy** | `none` | "Everything is set up." (calm, no green fill, no check reward) | shown, all `pass` | only if entitled-not-synced | Sync now | empty |
| **setup-needed** | `hollow` | "Let's get you set up." | minimal / hidden | possibly | **Set up** | empty |
| **it-config-incomplete** | `wrench` | "Waiting on setup from your organization." names the layer | shown, offending layer flagged | maybe | Sync now | may carry `waiting-on-it` notice |
| **waiting-for-network** | `clock` | "Waiting for network." | shown, stale-marked | hidden while offline | Sync now (disabled, reason) | empty |
| **offline** | `cloud-slash` | "You're offline." | shown, stale-marked | hidden while offline | Sync now (disabled, reason) | empty |
| **syncing** | `ring` | "Syncing your setup..." (named phase, no ETA) | shown, syncing rows animate `ring` | hidden during sync | none (in progress) | empty |
| **signed-out** | `key` | "Codex needs sign-in; Claude is fine." (names the component) | shown, `key` on the layer | maybe | **Sign in** | `sign-in` prompt |
| **update-available** | `update` | "An update is ready to install." | shown | maybe | Sync now | empty (transport handles it) |
| **needs-attention** | `triangle` | names the failing component and layer and what it needs | shown, offending row expanded | maybe | context (Sign in / Sync now) | possible notice |
| **updating-app** | `spinner` | "Updating Control Tower..." (named phase) | shown | maybe | none | empty |
| **cli-unreadable** | `bang` (only red) | honest bang copy: "I can't read the setup right now, so I won't guess." | **hidden** | **hidden** | Sync now (retry) only | empty; never a fake status |
| **notifications-denied fallback** | (inherits current) | current sentence + honest "shown here because notifications are off" note above a live prompt | shown | as normal | context + re-hosted prompt | the prompt, in-popover |

The **cli-unreadable / `bang`** state is the exact honest-degrade the owner saw. Its
rules are strict: no component tree, no join row (the app cannot vouch for stale
parsed entitlement when the CLI contract is unreadable), no fabricated status, one
plain sentence, retry only. It never shows a raw io/parse/schema string;
`cli_unreadable_reason` selects a plain-language line (§6.3) but the reason token
itself is never surfaced.

### 2.5 Region 3: the "Join available" affordance (new, S11 entry point)

**JTBD:** *When a department I belong to is available but not yet on this machine, I
want to see that plainly and pull it in with one action, so I get its copilots
without asking anyone or touching a terminal.*

- *Source:* the popover renders a Join-available row for each `layers[]` entry from
  `copilot layers --json` where `entitled: true, joined: false`. **Entitlement is
  CLI-computed; the app only renders and passes back the pick** (invariant #1).
- *Presentation:* a quiet, plain affordance, one line naming the layer plus a single
  **Join** button, rendered honestly as `hollow` (setup-needed shape), **never as
  healthy, never as an alarm** (fake-healthy is forbidden; a bright "new!" badge
  would be wrong here). Multiple joinable layers stack as multiple quiet rows.
- *Interaction (microinteraction):*
  - **Trigger:** click **Join** on the row (or VO-activate).
  - **Rules:** fires `copilot layers join <id>`. The row transitions to a **joining**
    state (see states below). The app computes nothing; it renders the returned
    `result`.
  - **Feedback:** the row's label swaps to a quiet inline `ProgressView` + "Joining
    Sales..." (named phase, no ETA), the Join button becomes non-repeatable, and
    Region 1 goes to the `ring` / syncing render while the layer materializes.
  - **Loops:** on `joined`, the row **leaves Region 3** and the layer appears as a
    new department column of currency in Region 2 on the next poll (the reward is the
    component tree filling in, not a toast). On `already-joined` (a race), same
    result silently. On `not-entitled` (entitlement revoked between list and join, a
    normal outcome per the contract, exit 0), the row is replaced by a plain honest
    line ("This department is no longer available to you.") and removed on next poll,
    never a crash. On `error` (exit 1), a plain "Could not join right now. Try again."
    with the Join action restored, never a raw string.
- *Where it also lives:* the same list and the same `layers join` mechanism power the
  standing Settings panel (§4.6). The popover row is the **glanceable entry point**;
  the durable list is in Settings. Both render the identical `layers` payload.
- *Boundary:* Bob only ever sees departments he is **already entitled to**. No admin
  decision, no "request access", no not-entitled-but-visible-to-tempt row leaks in.

**Join row states (all 8):**

| State | Treatment | Behavior |
|---|---|---|
| default | quiet row, layer name + **Join** | click joins |
| hover | system hover on the button | pointer cursor |
| focus | system focus ring on **Join** | Space/Return joins |
| active | pressed state | fires on release |
| disabled | Join disabled with reason while offline / syncing ("Waiting for network") | VO-readable reason |
| loading (joining) | label to "Joining <name>...", inline `ProgressView`, button non-repeatable; Region 1 `ring` | polls until `layers` reports joined |
| error | `not-entitled` -> honest "no longer available" line; `error` -> "Could not join right now. Try again." with Join restored | never raw string |
| empty | the region is **absent entirely** when no entitled-not-synced layer exists (structural, not a disabled shell) | |

### 2.6 Region 4: the two integration registers, structurally separated (new, S12 + S5)

The shared-versus-personal split is the interaction's clearest legibility job. Two
labeled sub-regions that **never merge** and are visibly distinct in structure (not
just color):

**SHARED (S12, entitled, read-only, no sign-in):**
- *What:* org/dept integrations (Salesforce, Workday, Microsoft) the user has by
  **entitlement**: provisioned centrally from the shared secret store when the layer
  was joined (D6). The user **does not authenticate** these.
- *Presentation:* a read-only list, each row = integration name + a quiet
  "available" state marker. **There is no sign-in button, no action of any kind.**
  The label of the region itself says why they are there ("Available because you're
  entitled"). This is the exact opposite register from Personal.
- *Rendering source:* a new shared-integrations read (Stage 1 open decision 4, TA to
  place a DTO, e.g. `copilot integrations --json` distinguishing shared-entitled from
  personal-device-flow). Until it lands, the region renders nothing (defensive
  fail-to-silence, the `get_bob_lane` pattern). The app **renders, never derives**
  entitlement.
- *Honest-degrade:* if a shared integration's secret failed to resolve, the row
  shows an honest "not available right now" state, **never green, never fake-
  healthy**, and (managed to IT) carries no user action (it is not the user's to fix;
  it routes to IT via the existing signal lane, never a new Bob prompt).

**PERSONAL (S5 register, device-flow sign-in, per-person):**
- *What:* the user's **own** accounts (Slack, and any integration that needs his
  personal credential). This is *his* credential, per-person, going to the OS
  keychain via the CLI.
- *Presentation:* `signed-out` rows offer a single **Sign in** action ("Sign in to
  Slack") that opens the steady-state sign-in **panel** (S5, §4.1), never inline in
  the transient popover. Signed-in rows show a quiet "signed in" state with no nag.
  `AuthIssue` expired/revoked rows offer "Sign in again".

The two registers are separated by a labeled divider and distinct grouping so the
user can always tell "just there because I'm entitled" (Shared) from "I signed in
myself" (Personal). Conflating them was a prior-domain error (D7.2); the separation
is **mandatory and structural**, not a visual nicety.

### 2.7 The action set (closed, small, state-driven, corrected)

The only actions that ever appear, and their visibility rule (Hick's Law: never more
than three visible at once):

| Action | Appears when | Effect | Never |
|---|---|---|---|
| **Sync now** | steady state, always available as the manual cadence escape hatch | invokes the CLI sync verb; Region 1 goes to `ring`/syncing | forces, skips verify |
| **What changed** | there is a recent parsed change set to show | opens a small inline change list (past-tense, plain) | shows raw git |
| **Join** | Region 3 has an entitled-not-synced layer | fires `copilot layers join <id>` (§2.5) | invents entitlement |
| **Sign in** | a **personal** integration/layer is `signed-out` (`key`) | opens the steady-state personal sign-in panel (S5) | appears for a shared integration; shows a token |
| **Set up** | state is `setup-needed` (unmanaged, the only case) | opens the wizard (S2) | n/a (no managed machine exists) |
| **Preferences...** | always (footer) | opens Settings (S3) | n/a |

There is deliberately **no** "Repair", "Force", "Fix", or "Make healthy" action
(those would be the app computing), and **no** "Update" button (an available app
update surfaces as a past-tense/present-progress line, S9, not a button the user
must press). **No** "sign in" ever appears on a Shared integration (that register
has no auth affordance by construction).

**Button states (all 8) for a popover action, e.g. "Sync now" (reused):**

| State | Treatment | Behavior |
|---|---|---|
| default | bordered button, enabled | click syncs |
| hover | system hover highlight | pointer cursor |
| focus | system focus ring (never restyled) | Space/Return activates |
| active | pressed system state | fires on release |
| disabled | dimmed, still VO-readable with reason | "Sync now" disabled while offline, `.help` = "Waiting for network" |
| loading | label to a quiet inline `ProgressView` + "Syncing..."; button non-repeatable | Region 1 glyph shows `ring` |
| error | button returns to default; **failure is expressed in Region 1's sentence**, never on the button, never as a raw error | honest-degrade, §6.3 |
| empty | the action is **absent entirely** when its precondition is absent (structural), except the disabled-with-reason offline case | |

### 2.8 Bob lane: prompt vs notice presentation (reused verbatim, closed sets)

The Bob lane renders `BobLaneView`, the emotional heart of "asked only about my own
data". Three visually and interactively distinct registers:

**A `prompt` (actionable, at most one, closed set `sign-in` | `dirty-wip`):**
- A small inset card: `BobPrompt.detail` (calm status-line copy) + a **single**
  primary action labeled `BobPrompt.action_label` (never "Submit" or "OK"; it names
  the act, e.g. "Sign in to Slack", "Review your changes").
- Exactly one affordance. No dismiss/approve/snooze (structurally forbidden by
  `types.ts`: no such field). It clears when the underlying condition clears, on the
  next poll.
- `sign-in` opens the steady-state personal sign-in panel (S5). `dirty-wip` opens the
  dirty-work panel (S6). Neither is handled inline in the transient popover.
- **A new department to join is NOT a Bob prompt.** It is a quiet Region 3 row (§2.5),
  because it is not a non-deferrable decision and `BobPromptKind` has no such member.

**Notices (informational, past-tense, any number, closed set `kept-you-safe` |
`kept-your-working-version` | `waiting-on-it`):**
- Quiet single lines with a neutral leading glyph, **no action, no alarm styling**.
  `BobNotice.message` verbatim.
- `waiting-on-it` is the one non-past-tense notice but is still non-actionable and
  never gains an approve/unblock control (that would be the Alert Machine).

**The security banner (`SecurityBanner`, separate, un-dismissable):**
- Pinned at the bottom of the Bob lane, the most persistent element, with the
  **single** affordance `reaffirm_label` ("Re-affirm your version"). No dismiss, no
  resolve, no approve (none exist on the type). Re-affirm re-invokes the CLI reaffirm
  verb; the banner persists until the CLI stops reporting the shadow.

Any held-major / policy / security / deprovision event routes to IT via `ItSignal`,
**never** a new Bob prompt.

### 2.9 Keyboard and VoiceOver traversal of the popover (reused, extended)

**Tab order (top to bottom, left to right):**
1. Status header (VO-focusable text; announced first by VO as the popover's label).
2. Component tree: each component row is a tab stop; Left/Right collapse/expand;
   Up/Down move between rows and into disclosed layer cells (standard
   `NSOutlineView` / `DisclosureGroup` model).
3. **Join-available rows** (each row's Join button is a tab stop) [new].
4. Integration rows: Shared rows are **read-only, not tab stops** (no action);
   Personal `signed-out` rows expose their Sign-in button as a tab stop [new split].
5. Action row buttons (Sync now, What changed).
6. Bob-lane prompt action (if any).
7. Security-banner re-affirm (if any).
8. Footer: Preferences..., Set up... (if present).

- **Default focus on open:** the first live action if one exists, else the status
  header (VO reads the verdict first regardless, as the container label).
- **Esc** closes the popover (returns focus to the previously active app).
- **VoiceOver labeling:**
  - Container: `accessibilityLabel` = the status sentence; role = group.
  - Glyph: label = state name ("needs sign-in", "offline", "syncing", "error, cannot
    read setup"), never the SF Symbol name.
  - Component row: "Component name, status name" ("CLI Copilot, needs sign-in");
    expanded/collapsed announced; layer cells nested as children "layer name, status
    name, detail". A not-entitled cell announces "layer name, you are not in this
    layer".
  - **Join-available row** [new]: announced as an action, "Sales department, available
    to join, button"; on activation the joining state is a polite live region ("Joining
    Sales").
  - **Integration regions** [new]: two labeled groups. Shared group announces "Shared
    integrations, available because you're entitled" and its rows are read-only values
    ("Salesforce, available"); Personal group announces "Your accounts" and its rows
    carry the Sign-in action ("Slack, needs sign-in, button").
  - Badges: every badge exposes a text label (shape + color are never the sole
    channel); `key` announces "needs sign-in", never "key icon".
  - The Bob-lane prompt is an `accessibilityElement` group announced as an action; the
    security banner announces its persistent nature so a VO user knows it will not clear
    on its own.
  - Live region: Region 1's sentence is a polite live region so a status change while
    the popover is open is announced without stealing focus.

---

## 3. The first-run wizard (S2): one guided path

### 3.1 JTBD

> When this app first lands on my Mac and I am not a technical person, I want to be
> walked to a working setup asking only what I can actually answer, including which
> departments to pull in and which of my own accounts to sign into, so I end up with
> a working partner and never touch a terminal or a file.

### 3.2 Concepts considered (novel flow; evaluate before converging, reused)

**Concept A: Popover-only progressive setup.** Do first run inside the transient
popover, one question at a time. Strong on #8 minimalist, **fatal** on #3 user
control and #5 error prevention because the popover auto-dismisses on focus loss and
setup must send the user to Safari for personal sign-in. **Rejected.**

**Concept B: Full-screen takeover assistant.** Strong #1 visibility, weak #2
match-to-real-world for a background utility (over-dramatizes a small job), weak #7
flexibility, fights macOS convention for a menu-bar app (Jakob violation).
**Rejected: over-weight for a calm subordinate tool; violates "as little app".**

**Concept C: Standard titled window with a persistent roadmap sidebar
(`NavigationSplitView`), mirroring the Apple Setup Assistant pattern the owner
already approved in Publisher Setup.app.** Strong #1 (the sidebar always shows where
you are and what remains), #2 (this is exactly Setup/Migration Assistant), #3 and #7
(Back always available, survives focus loss to Safari), #6 recognition over recall,
#4 consistency (reuses the approved Publisher Setup language). Weakness: slightly
more chrome than "as little app" prefers, but the honesty and control gains dominate,
and it appears once. **Selected.**

Rationale: the only approach that survives the leave-to-Safari sign-in requirement
while keeping the user oriented across **more** steps than before (department join
and personal sign-in are now both first-class), and it inherits the exact native
quality bar the owner loved. The window-for-setup, popover-for-steady-state split is
the wizard's core interaction decision.

### 3.3 One path only (D4: the managed silent lane is gone)

There is **no managed-silent path**. Every user self-installs the signed, notarized
`.dmg` and gets the same guided window on first run. The `WizardMode.managed` arm in
`types.ts` is vestigial (Stage 1 open decision 7); this experience renders only the
one guided window and never branches on mode. Any prior "managed silent" holding
behavior is deleted; there is no silent lane to render.

### 3.4 The window: chrome and the Back/Continue model (reused grammar)

`NavigationSplitView` = fixed non-collapsible roadmap sidebar + single focused
content pane + pinned footer action bar, identical structural grammar to
`publisher-setup-visual-spec.md` (reuse it; do not reinvent). The roadmap now has
**more rows** because the corrected flow adds department join.

```
┌──────────────── Set Up Copilot Control Tower ─────────────────┐
│ ●●●                                                            │
├─────────────────┬──────────────────────────────────────────────┤
│ SIDEBAR (roadmap)│ CONTENT PANE (one step)                     │
│  ✓ Welcome       │   EYEBROW · STEP 4 OF 10                     │
│  ✓ Detect        │   Step title                                │
│  ✓ Choose        │   Intro line (plain)                        │
│  ◉ Your layer    │   ┌── step content region ──────────────┐   │
│  ○ Departments   │   │  controls for this step             │   │
│  ○ Sign in       │   └──────────────────────────────────────┘  │
│  ○ Set up        │                                             │
│  ○ Verify        │   ───────── footer divider ───────────────  │
│  ○ Learn         │   [Back]            status      [Continue]  │
│  ○ Ready         │                                             │
└─────────────────┴──────────────────────────────────────────────┘
```

- **Roadmap maps to `WizardPhaseTag`** (`welcome, detect, question, materialize,
  verify, teach, done`) with the `question` phase expanded into its sub-stages for
  the sidebar. The corrected sub-stages are: **Choose components** (`choose-products`
  DTO), **Your layer** (`layer-setup`), **Departments** (new, S11, backed by the
  `layers` verbs, not `set_layers`), **Sign in** (`sign-in`, personal only).
  `holding` does not add a roadmap row; it renders in the content pane over whatever
  step raised it (§3.6).
- **Back/Continue model:** the footer always carries a trailing **primary** (Continue,
  or the step-specific act) and, from step 2 on, a leading **Back**. Continue is
  `.defaultAction` (Return); **Esc does not map to cancel-setup** (a menu-bar app's
  first run should not be killable by a stray Esc; Esc is inert in the wizard body,
  and cancels only inside the sign-in sheet). Completed roadmap rows are tappable to
  review earlier answers read-only; upcoming rows are disabled. You cannot skip past
  an unanswered required step (constraint-based error prevention, Nielsen #5).
- **No step shows a time estimate.** Progress is "STEP n OF 10" (position, not time)
  plus the named phase; never "about 2 minutes left".

### 3.5 Step-by-step interaction (corrected steps)

**1. Welcome:** Orientation hero. Plain sentence about what Control Tower is and that
it will set up their copilots. One primary **Get Started**; secondary **Quit**. This
step also carries the **one** low-key `admin_capable` opt-in affordance (§5.1, Path
2a) if that path is ratified: a secondary control "I'm setting this up for an
organization", off by default, phrased as a role declaration. No question otherwise.

**2. Detect:** A verify step (detect then result). Content shows a quiet
`ProgressView` + "Checking what's already here..." while the CLI probes, then a
read-only summary of what was found (which components/layers already exist). If the
probe cannot read, it lands on the wizard `holding` render, not a guess. States:
loading (probing), result (found summary), holding (unreadable). Primary
**Continue**; Back to Welcome.

**3. Choose components** (`choose-products`, `WizardStep.products:
WizardProductOption[]`):
- "Which copilots do you want set up?" A checklist of the CSE **components** (Knowledge
  / CLI / Claude / Codex), **never products**. Each `WizardProductOption` renders as a
  checkbox row: `label`, checked = `pre_checked`.
- **Constraint (from types.ts):** a `pre_checked: false` option renders **visible but
  disabled** (the ecosystem does not grant it) with a `.help`/VO reason; the user may
  uncheck a `pre_checked: true` option but can never check a disabled one. Honest slot-
  showing, not hiding.
- Validation: at least one component must remain checked to Continue (Continue disabled
  with an inline reason if all unchecked). Submits via `wizard_choose_products`.
- States: default (list), focus (row), disabled (ungranted rows), error (none checked
  -> Continue disabled + inline line), empty (n/a; catalog always has members; a fetch
  failure lands on holding).

**4. Your layer** (`layer-setup`, `WizardStep.layers: WizardLayerSlot[]`, personal
tier only): One repo-URL row per component the user kept in step 3 (client-synthesized
from the step-3 answer per types.ts). Each row: component name label + a native
`.roundedBorder` text field for the repo URL.
- **Scope note (types.ts):** there is **no** company/department pick-list here. The real
  `wizard_set_layers` accepts only a component-id -> repo-URL map at personal tier. This
  step is the user's **own** personal layer, always personal-tier, always editable.
  **Inheriting an entitled shared department is a separate step (step 5), by design**:
  it uses the `layers join` verbs, not `set_layers`. Do not conflate them.
- Validation: **inline, on-blur and on-submit** (not per keystroke). An empty or
  malformed URL shows a plain-language inline caption in the error slot below that field
  ("This does not look like a repository address"), never a raw parser or git string.
  The field keeps its value on error (never clears). A row may be left blank where the
  CLI signals that component can materialize from a broader tier (the caption says so);
  Stage 1 open decision 5 flags the CLI must signal which. Submits via
  `wizard_set_layers`.
- States: default, focus (field), error (inline caption, danger glyph + text), disabled
  (n/a), loading (n/a until submit), empty (n/a; always at least one row).

**5. Departments** (new step, S11 in the wizard): renders `copilot layers --json` (the
departments the user is entitled to) and lets him join. Detailed as its own surface in
§4.5; the wizard hosts the same list and the same `layers join` mechanism. Distinct from
step 4 (his own repo): this is **inheriting an entitled shared layer**. Skippable
(tertiary "Skip for now", the popover Region 3 will surface joinable departments later),
so it is never a dead end. Primary **Continue**; Back to step 4.

**6. Sign in** (`sign-in`, personal only): opens the **device-flow sheet (S5)** on the
wizard window (§3.5.1). On success the step marks done and Continue advances; the user
may skip with a tertiary "Skip for now" (the Bob lane will prompt later). **Shared
integrations are never a wizard step:** they simply appear connected in S12 because the
joined department provisioned them (D6). This step is the **personal** register only.

**7. Set up / Materialize** (`materialize`): a named-phase progress step, **no ETA**.
Content shows the current `WizardState.phase_label` (e.g. "Setting up Claude Copilot...",
"Bringing in your Sales department...") with an **indeterminate** `ProgressView` and,
optionally, a step-tracker of named sub-phases that light as they complete. No percentage
unless the CLI emits discrete completed phase counts, and even then it renders as "phase
2 of 4 named phases", never a time. On failure -> `holding` (§3.6).

**8. Verify** (`verify`): a verify step whose **only success is Healthy** (types.ts:
`done` is reachable Rust-side only via a parsed `Healthy`). Content: quiet probe, then
either "Everything checks out" (calm, not celebratory) advancing to Learn, or a `holding`
render naming what is not yet Healthy (never a false pass, never fake-healthy of an
entitled-not-synced layer).

**9. Learn / Teach** (`teach`): one calm screen teaching the three things the user will
see later: the menu-bar glyph ("this quiet icon is me; when I have nothing to say I say
nothing"), that they will only be asked about their own sign-ins or their own unsaved
work, and that **new departments they become entitled to will quietly appear as "Join
available"**. No quiz, no gate. Primary **Continue**.

**10. Ready / Done** (`done`): "You're set up." **Done** closes the window; the app
demotes to accessory and lives in the menu bar. Optional one-time pointer to the glyph
location. No celebration toast (Healthy is the absence of signal).

#### 3.5.1 The device-flow sign-in sheet (S5, from the wizard, reused verbatim)

**Microinteraction: personal device flow**
- *Trigger:* the Sign in step, or (steady state) the Bob-lane `sign-in` prompt.
- *Rules / states* (`SigninStatus`: `idle | pending | authorized | denied | expired |
  timeout`; `SigninState` carries only `user_code` + `verification_uri`, never a token):
  - **idle -> begin:** `wizard_begin_signin`; sheet appears.
  - **pending:** the sheet shows, large and selectable, the **`user_code`**, and a
    prominent primary **Open Sign-in Page** button that launches `verification_uri` in
    the default browser ("this leaves the app" semantics). The code **stays visible the
    entire time** the user is in Safari (the sheet is modal to the wizard window and does
    not dismiss on focus loss). The app **polls `wizard_poll_signin` at
    `signin_interval_secs`** cadence. **No countdown, no "expires in N", no
    spinner-with-timer.** A quiet indeterminate "Waiting for you to finish in your
    browser..." line is the only progress signal.
  - **authorized:** a calm "Signed in" and auto-dismiss back to the step, which advances.
    Token went to the OS keychain via the CLI; the app never saw it.
  - **denied:** plain "That sign-in was declined." with **Try again** (restarts) and
    **Cancel**. Not a dead end.
  - **expired / timeout:** plain "That code expired." / "That took too long." each with
    **Get a new code** (re-begins, new `user_code`) and **Cancel**. The interval was
    bookkeeping only; the user is never shown it counting.
- *Feedback:* the code is one-tap copyable (a copy affordance beside it); copying gives a
  brief "Copied" that fades. VoiceOver reads the code grouped and character-by-character
  on request.
- *Dismiss:* Cancel (or Esc, mapped here to cancel-this-sheet only) returns to the step
  with sign-in still pending/skippable; it does not abort the whole wizard.

Steady-state variant: identical states, hosted in the **standalone floating panel** (not
a sheet) so it survives with no wizard window present, reachable from the Bob-lane prompt
or the popover Personal register. Same "code stays visible, no countdown, no token" rules.

### 3.6 Holding (the honest terminal, reused, corrected owner attribution)

`WizardPhaseTag = holding` is **first-class, not an error screen**. It can arise from
Detect, Departments (a join that could not complete), Materialize, or Verify. Content:
- A calm title and the plain `WizardState.error` reason verbatim (guaranteed plain by
  types.ts; never raw yaml/serde/CLI text).
- **Names who owns the fix** where knowable: IT-owned ("Waiting on setup from your
  organization"), network-owned ("Waiting for network"), or entitlement ("This department
  is no longer available to you"). Never blames the user, never says "failed, contact
  support".
- Forward action always present (Nielsen #9): **Try again** (re-runs `wizard_advance` or
  re-fires the join) and, where relevant, **Continue in the menu bar** (close the window
  and let the popover carry the holding state, since the machine may reach Healthy on
  cadence). Holding is never a wall.
- It does **not** advance the roadmap to Done and never fabricates Healthy.

### 3.7 Wizard keyboard / VoiceOver (reused)

- Tab order per step: roadmap is a VO container "Setup progress" with rows announced
  "step n of 10, name, current/completed/not started"; content-pane fields in a
  `FocusState` chain top to bottom; footer Back then Continue.
- On each step change, focus moves to the step **title** (VO announces the new step) then
  to the first control (`@FocusState` / `.accessibilityFocused`).
- Continue = `.defaultAction`; Back = a real button (not cancelAction, since Esc is
  reserved-inert except in the sheet).
- The sign-in sheet traps focus; its code is a `.textSelection(.enabled)` VO-readable
  element; Open Sign-in Page is `.defaultAction` within the sheet.
- Reduce Motion: step transitions cross-fade; the roadmap marker moves without spring; the
  materialize progress stays indeterminate but drops any pulsing.

---

## 4. New and per-surface flows: S11, S12, S13, and S5 to S9

Shared boundary rule (invariant #5, SOUL), applied throughout: the user is asked about
**only** his own personal sign-in (S5), his own dirty personal work (S6), and offered
**only** departments he is already entitled to (S11). Everything else (conflict is
author-only; deprovision and bad updates are auto/IT/transport; shared integrations are
provisioned, not signed-in) is rendered as a past-tense notice, a read-only register, or
lives in Admin. No surface here grants the user a decision about a release, a policy, a
security hold, another person's data, or someone else's entitlement.

### 4.1 S5 Personal sign-in: covered in §3.5.1 and its steady-state panel variant

The Bob-lane `sign-in` prompt's action (and the popover Personal register's "Sign in")
opens the floating panel; on `authorized` the panel closes and the Region-1 `key`/signed-
out state clears on the next poll. This is the **personal** register only; a Shared
integration never routes here (§2.6, §4.4).

### 4.2 S6 Dirty-work prompt (reused verbatim)

**JTBD:** *When my own unsaved work is in the way of a sync, I want to be told calmly and
decide what to do with my work, so nothing I made is ever lost without my say.*

- *Trigger:* router emits a `dirty-wip` `BobPrompt`.
- *Appearance:* first as a `UNNotification` (title = `BobPrompt.title`). Interacting with
  it (or, if notifications are denied, the in-popover re-hosted prompt) opens a **small
  non-transient panel** (not the popover), because the user may leave to inspect files and
  the surface must persist.
- *Content / rules:* `BobPrompt.detail` in plain language, and a **single** respectful
  action `BobPrompt.action_label` (e.g. "Review your changes"). Because the app never
  computes a resolution, this action opens the user's own working location / hands off to
  the CLI's own handling; the app offers no keep/discard verdicts of its own. There is
  exactly one affordance; **no discard-my-work button exists** (never-destroy).
- *Dismiss:* the panel stays until the condition clears (the next poll shows the tree
  clean) or the user closes it; the Bob lane still carries the prompt until resolved (a
  live exposure is never controlled solely by a dismissable notification, types.ts Flow 7).
- *Notifications-denied fallback:* if permission is denied
  (`BobLaneView.notifications_denied`), the prompt is fully reachable in the popover Bob
  lane with an honest "Shown here because notifications are turned off" note; Settings
  surfaces how to turn them on (render-only; the app never silently re-requests).
- *States:* default (prompt shown), focus (action), loading (n/a; the app does not run the
  resolution), error (an honest holding notice if the CLI reports it could not proceed,
  never a raw error), empty (no prompt -> nothing).

### 4.3 S7 Conflict chooser (author only, reused verbatim)

**JTBD:** *When my edit and a teammate's edit to shared content collide, I want to pick
what happens in plain language, so I keep everyone's work without ever learning Git.*

Exists **only for the writable author tier**, reached only from an author publish action
inside the Admin/author window; **Bob never sees it**. The CLI computes the options; the
app renders them and returns the choice.

- *Trigger:* an author publish hits a genuine overlap the CLI could not auto-merge.
- *Container:* a **modal sheet** on the author window (returning a choice is the whole
  point; blocks that window until answered, but not the app).
- *Content / rules:* renders the CLI-computed option set as plain-language choices, **never
  `<<<<<<< HEAD`, never a diff of raw markers**. Options map to the ratified set: **Keep
  yours**, **Keep theirs**, **Keep both** (the always-available no-data-loss floor,
  presented as the safe default and recommended), and **Park and ask an author**
  (escalate). Each option is one plain sentence describing the outcome.
- *Interaction:* radio-style single selection with **Keep both pre-selected**, a
  **Continue** that returns the choice to the CLI, and a **Park** path that escalates
  without choosing. No free-form merge editing (the app computes nothing).
- *Feedback:* on Continue, the CLI applies the choice; the sheet shows a brief calm
  confirmation then closes. On escalate, "Parked for an author to look at" then closes.
- *Dismiss:* only via choosing or parking; no bare close that drops the collision. Esc maps
  to Park (the safe, non-destroying exit), not a silent discard.
- *States:* default (options, Keep-both selected), focus (option), disabled (n/a), loading
  (applying, brief), error (an honest "Could not finish; parked it safely for an author"
  degrade to escalate, never a raw git error), empty (n/a; opens only on a real collision).

### 4.4 S12 Entitled shared-integrations register (new, detailed)

**JTBD:** *When my organization has set up integrations for my department, I want to see
they are just there for me because I belong, without ever being asked to sign in or paste a
key, so I trust that the shared plumbing is handled for me.*

**Concepts considered (novel: the "no-action, read-only, entitled" register has no obvious
macOS precedent because most integration lists are sign-in lists):**
- **A: One merged integration list with a mixed state column** (some rows "signed in", some
  "provisioned"). **Rejected:** it conflates the two registers (the exact D7.2 error); a
  user cannot tell inherited plumbing from his own credential, and a "provisioned" row next
  to a "Sign in" button invites him to try to authenticate something he does not own.
- **B: Hide shared integrations entirely** (they just work; why show them). **Rejected:**
  fails honesty and #1 visibility; when a shared secret fails to resolve, the user has no
  place to see the honest "not available right now", and he cannot understand why a
  capability appeared.
- **C: A distinct, labeled, read-only register visibly separate from Personal, stating "why
  it's here", with no action, and an honest not-available state.** **Selected.** Best on #2
  (matches the real world: entitlement, not login), #6 (recognition: the label tells him),
  #1 (honest visibility including failure), and it makes the shared-versus-personal
  distinction structural, not a color.

**Interaction:**
- *Presentation:* a read-only list in the popover Region 4 Shared sub-region (§2.6) and in
  Settings > Integrations (§4.7). Each row = integration name + a state marker: "available"
  (the healthy case) or "not available right now" (honest-degrade). The **region label
  itself** carries the "why": "Available because you're entitled". **No row has any
  action.**
- *Rendering source:* a shared-integrations read the CLI computes (Stage 1 open decision 4;
  TA to place a DTO, e.g. `copilot integrations --json` distinguishing shared-entitled from
  personal). Rendered defensively (fail-to-silence if the command is not yet landed). The
  app **renders, never derives** the entitlement.
- *Honest-degrade:* a row whose shared secret failed to resolve shows "not available right
  now", **never green, never fake-healthy**. It carries **no user action** (not his to fix)
  and routes to IT via the existing signal lane, never a new Bob prompt or a sign-in
  button.
- *States (all 8):* default (available rows), hover (n/a; no interactive target), focus
  (n/a; read-only, not a tab stop), active (n/a), disabled (n/a; there is no control to
  disable), loading (a skeleton row while the read resolves), error (a row or the whole
  region shows an honest "not available right now" / "couldn't check your shared
  integrations", never fabricated availability), empty (no shared integrations entitled ->
  the region is **absent**, not a blank; the user simply has none).
- *VoiceOver:* the group announces "Shared integrations, available because you're entitled";
  rows are values ("Salesforce, available"), explicitly **not** actions, so a VO user never
  hunts for a button that does not exist.

The single most important interaction fact here is a **negative** one: this register has
**no sign-in affordance, ever**. That absence is the design.

### 4.5 S11 Department discovery + join (new, detailed, load-bearing)

**JTBD:** *When I belong to a department whose copilots are not yet on this machine, I want
to discover it and pull it in with one action, so I get everything my team shares without
asking anyone or editing a file.*

**Concepts considered (novel and load-bearing: the single biggest CSE gap the prior design
descoped):**
- **A: A modal "join a department" dialog** launched from a button. **Rejected:** a modal
  implies a one-time decision; entitlement changes over time, so join must be a **durable,
  revisitable** surface, not a dialog the user dismisses and cannot find again.
- **B: Auto-join every entitled department silently** (no user action). **Rejected:** it
  removes the user's agency over what lands on his machine and could pull large layers
  without consent; and a silent sync gives no honest "this appeared because you're now
  entitled" moment. It also blurs the never-destroy/consent line.
- **C: A standing, revisitable list (in Settings and the wizard) plus a quiet popover "Join
  available" entry point, each rendering the identical `copilot layers --json` and firing
  `copilot layers join <id>`, with join as an explicit per-department action.** **Selected.**
  Best on #1 (honest visibility of what you could join), #3 (user control: he chooses and
  when), #6 (recognition: the list is always there), #7 (flexibility: join now or later).
  It is a render-and-pass-back surface (invariant #1): entitlement is CLI-computed, the app
  renders the list and passes the pick to `layers join`.

**The surface lives in three places, one mechanism:**
1. **Wizard step 5** (§3.5, first run).
2. **Standing Settings panel** (Settings > Components & Layers, §4.6, steady state).
3. **Popover Region 3** quiet "Join available" entry point (§2.5, glanceable).

All three render the identical `layers[]` payload and all three fire `layers join`. The
detailed **interaction, validation, and join states** are in §2.5 (the join microinteraction
and its 8 states) and apply identically here.

**The standing list presentation (wizard step and Settings panel):**
```
Departments you can join
┌─────────────────────────────────────────────────────────┐
│  Sales            Available to join            [Join]     │  entitled:true joined:false
│  Engineering      Joined                       (on this   │  entitled:true joined:true
│                                                 machine)  │
│  Marketing        Not available to you                    │  entitled:false (honest slot)
└─────────────────────────────────────────────────────────┘
```
- **Entitled + not joined** -> "Available to join" + a **Join** action.
- **Entitled + joined** -> "Joined" state, read-only, no action (it is already a column of
  currency in the component tree). Quiet, never a celebratory mark.
- **Not entitled** -> a quiet "Not available to you" honest slot **only where the CLI returns
  such a row**; the app never invents a not-entitled row to tempt him, and never offers a
  "request access" (that would leak an admin decision). Whether not-entitled rows appear at
  all is the CLI's choice via the `layers` payload; the app renders exactly what it returns.
- **`reason?`** from the payload, when present, renders as a plain caption on a row (e.g. why
  a layer is listed but not entitled), never a raw string.

**States (list-level, all 8):**
| State | Treatment |
|---|---|
| default | the list, joinable rows with **Join**, joined rows read-only |
| hover / focus / active | on the per-row **Join** button only (per §2.5) |
| disabled | Join disabled with reason while offline or a sync is in flight |
| loading | first paint: skeleton rows while `copilot layers --json` resolves; per-row joining state per §2.5 |
| error | the whole read failing -> honest "Couldn't check your departments right now. Try again." with a Retry, never fabricated rows; a single join failing -> per §2.5 |
| empty | the CLI returns no layers -> an empty state (§6.2): "No departments are available to you yet." plus a plain line that new departments appear here when you're added to one; never a blank |

**Keyboard / VoiceOver:** the list is a standard list; each row announces "department name,
joined / available to join / not available to you"; the Join button is the only tab stop on a
joinable row; joined and not-available rows are read-only values (not tab stops). The joining
transition is a polite live region ("Joining Sales", then it leaves the list).

### 4.6 S13 Personal-key multi-machine sync (new, detailed, Settings surface)

**JTBD:** *When I work from more than one of my own Macs, I want my own personal keys to
follow me so I stop hand-copying `.env` files between my machines, while staying certain these
keys are mine alone and never shared with anyone.*

This is a **Settings tab** (Settings > Personal Key Sync). It is **not** the shared secret
store (that is entitlement-scoped, D6, and never holds an individual's identity): this is one
person, several machines only they control, syncing credentials that stay theirs alone and
never touch git or shared-store material (credentials-and-boundary §7, D7.3). The **carrier
mechanism is an open design item** (Stage 1 open decision 5); the surface is designed now, and
the interaction renders CLI/CLI-adjacent status, never computing the sync itself.

**Concepts considered (novel: syncing one's own secrets across one's own devices, reconciled
with per-device on-device keys):**
- **A: Automatic, invisible sync with no surface** (keys just appear on machine 2).
  **Rejected:** secrets moving between devices without a visible, honest control violates the
  security-legibility the whole product rests on; the user must be able to see what is
  enrolled and turn it off. Silent secret movement is exactly the kind of thing this product
  makes honest.
- **B: A manual export/import ("copy my keys to a file, import on the other Mac")**.
  **Rejected:** it re-creates the `.env` hand-copying the feature exists to end, and a plaintext
  export is a leak surface.
- **C: An explicit opt-in toggle with a visible roster of the user's own enrolled machines, an
  honest statement of exactly what is and is not synced, and a plain conflict resolution when
  two machines diverge, reconciled with the per-device key model (a device is enrolled by its
  own on-device key, never by moving a private key).** **Selected.** Best on #1 (visible
  status and roster), #3 (user control: enable/disable, per-machine), #2 (matches the real
  model: enroll a device, do not smuggle a key), #5 (a designed conflict path, not a silent
  overwrite).

**Layout:**
```
Personal Key Sync
┌───────────────────────────────────────────────────────────┐
│  ( ●) Sync my personal keys across my own Macs             │  the enable switch
│       Your keys, your machines only. Never shared, never   │  honest scope line
│       in git.                                              │
│                                                            │
│  Your machines                                             │
│    • This Mac (Pablo's MacBook Pro)   Enrolled             │  this device
│    • Pablo's Mac Studio               Enrolled   [Remove]  │  other enrolled device
│    • Pablo's old MacBook Air          Not syncing [Enroll] │  known, not enrolled
│                                                            │
│  What syncs                                                │
│    Your personal integration keys (the accounts you        │  honest what/what-not
│    signed into yourself).                                   │
│  What never syncs                                          │
│    Shared department integrations, your Git push key,       │
│    and anything your organization provides.                 │
└───────────────────────────────────────────────────────────┘
```

**Interactions:**
- **Enable switch (microinteraction):**
  - *Trigger:* toggle the switch on.
  - *Rules:* enrolls **this** device into the user's personal-key sync set (by its own
    on-device key; no private key is ever moved off a device). The app passes the intent to
    the CLI/carrier and renders the returned status; it computes no sync itself.
  - *Feedback:* the switch shows a brief in-progress state, then the roster updates to show
    "This Mac ... Enrolled". No ETA, no percentage.
  - *Loops:* once enabled, subsequent personal sign-ins on any enrolled machine become
    available on the others on the sync cadence, ending hand-copying (the U7 payoff).
- **Per-machine Enroll / Remove:** each known machine row carries at most one action. **Remove**
  is reversible (re-enroll later) and is the safe verb (it stops that machine syncing; it does
  not reach out and wipe already-present keys on a machine this app cannot reach, honest about
  the same accepted residual as D4 offboarding). A confirmation is used **only** for Remove of a
  machine other than "This Mac", and only because it changes another device's future behavior;
  everything else is directly reversible (Error Prevention hierarchy: prefer reversible over
  confirm).
- **Conflict (two machines diverged the same key):** rendered as a plain, honest choice, **never
  a silent last-writer-wins**: "Two of your Macs have a different value for <account>. Which do
  you want to keep?" with the two options named by machine and by *when* they were set (not by
  showing the secret value). This reuses the conflict-chooser grammar (plain options, a safe
  default, no raw material) but for the user's own keys. The secret value is **never displayed**;
  the choice is by machine + recency. Resolution is passed to the carrier; the app renders the
  result.

**States (all 8):**
| State | Treatment |
|---|---|
| default | switch (on/off) + machine roster + what-syncs/what-never |
| hover / focus | standard on the switch, per-row Enroll/Remove, and any conflict choice |
| active | pressed state on those controls |
| disabled | Enroll/Remove disabled with reason while offline ("Waiting for network"); the whole tab disabled with an honest line if the carrier is unavailable |
| loading | enrolling/removing shows a brief in-progress state on that row; first paint skeletons the roster |
| error | a plain "Couldn't change key sync right now. Try again." never a raw carrier/keychain string; a failed enroll leaves the switch honestly off |
| empty | sync off / no other machines known -> an empty state (§6.2): "Turn this on to stop copying keys between your Macs." + the enable switch as the CTA |

**Boundary reassurance is load-bearing copy here:** the "What never syncs" block is not
decoration; it is the structural promise made legible (shared integrations, the Git push key,
org-provided material never travel this path). VoiceOver announces the switch state, each machine
row as "machine name, enrolled / not syncing, and its action", and reads the what-syncs and
what-never blocks as labeled groups.

### 4.7 Settings (S3) tabs, corrected domain

Standard `Settings` scene (`Cmd-,`), tabbed. Inherited Apple Preferences pattern; states and
keyboard are standard, so only the corrected content is called out.

- **General:** surfaces login-item state (does not re-point it); About link.
- **Components & Layers:** the entitled-layer view (one row per component x layer with currency,
  same badge grammar as the popover tree), **plus the standing Department discovery/join panel
  (S11, §4.5)** rendering `copilot layers`. Managed org/dept rows show locked ("Managed by your
  organization", `LayerRow.editable == false`); personal rows are editable. Errors are plain
  language, never raw yaml/serde.
- **Integrations:** the **two separated registers** (mandatory, D7.2): **Shared** (S12, §4.4,
  read-only, entitled, no sign-in) and **Personal** (device-flow sign-in; `AuthIssue`
  expired/revoked rows offer "Sign in again"). The label/structure separation is not optional.
- **Personal Key Sync (S13, §4.6):** the new tab.
- **Advanced:** poll cadence, diagnostics; **no** security-sensitive re-pointing (no
  UpdateFeedURL / mirror / secret-store endpoint control; those are honored only from signed
  inherited org config).
- **Administration** (conditional): present only when `admin_capable` (§5.1); absent, not
  disabled, otherwise.

### 4.8 S9 Update / rollback (reused verbatim)

**JTBD:** *When Control Tower updates itself, I want it to just happen and to keep my working
version if an update goes bad, so I never face a scary update dialog.*

Renders `UpdateState` (`UpdateStatus: idle | checking | up-to-date | available | downloading |
verifying | staging | ready | rolled-back | error`). **Never a modal alert.** All inline in the
popover plus, for the two outcomes the user should notice, a past-tense Bob-lane notice.

- `idle` / `up-to-date`: render **nothing** (silence).
- `checking` / `downloading` / `verifying` / `staging`: a quiet phase line ("Updating Control
  Tower...") with the `spinner` glyph. **Named phase, no ETA, no percentage-as-promise.**
- `available` / `ready`: a calm line; the app installs on its own cadence (crash-only watchdog
  handles the swap). The user is not asked to press "Update now".
- `rolled-back`: the hero. Renders the `kept-your-working-version` notice: "Kept your working
  version." Past-tense, understated, **no action**. The bad update is invisible as a failure.
- `error`: `UpdateState.message` (guaranteed plain) as a quiet line, **never** raw
  signature/watchdog/heartbeat text. Still no modal; the working version was kept, so the framing
  is calm.

Polling: `check_for_update` at a conservative fixed cadence while in-flight (bookkeeping, never
rendered). `apply_update` is idempotent; the UI follows it with polling, never a second apply.

### 4.9 S8 Deprovision (reused, corrected to revocation not MDM wipe)

**JTBD (user side):** *When I leave and my access is revoked, I want to see calmly that my
unsaved personal work was kept and nothing of mine leaked, so I trust the tool even on the way
out.*

Renders `DeprovisionView`; **the app never triggers it**. It is a render of a **GitHub-access-
revocation + shared-secret-store token-rotation** event (D4, **no MDM wipe, no remote device
wipe**; already-synced content on the departed person's disk is not remotely wiped, the accepted
residual). Invariant #1 and #5.

- **User side:** a quiet Bob-lane **notice** (past-tense, non-actionable). Renders
  `DeprovisionView.sentence` and, prominently, `retained_dirty` as the never-destroy reassurance
  ("Your unsaved work was kept: <list>"), **including when empty** ("No unsaved personal work was
  in the way", itself honest information). `removed_count` renders with neutral copy only ("N
  item(s) removed"), never editorialized into "files" or "trees".
- **The `secrets_alarm` case is honest, never hidden:** if `secrets_touched != 0`, the notice
  states plainly that secrets were involved and (where there is IT) that IT has been informed.
  The one deprovision case allowed to read as an alarm, because honesty outranks calm.
- **IT side (Admin > Governance, §5):** the full `DeprovisionView` panel with `outcome` (`wiped |
  partial | noop | unreadable`), `removed_clones`, `retained_dirty`, `secrets_touched` /
  `secrets_alarm`. `unreadable` renders the honest "could not read the deprovision result"
  holding, never a fabricated success.
- *States:* the user notice has default (shown) and empty (nothing); read-only, no action, which
  is correct (the user takes no action on departure; revocation is server-side and he cannot
  reverse it).

---

## 5. Admin mode (S4): Onboarding + Governance, no MDM, no fleet-as-center

### 5.1 The capability gate and the carried-forward open decision (corrected: no MDM grant)

**Admin mode is entered only when `admin_capable` is true**, and when false the entry point is
**absent, not disabled** (exposure itself is the harm). When present, it appears in two places:
the right-click menu ("Open Administration...") and a conditional **Administration** tab in
Settings. Both render off the same `admin_capable` fact.

**The MDM/managed grant path is deleted (D4).** There is no forced/managed-domain key that grants
Admin. `admin_capable` is now a **first-run opt-in on an unmanaged machine** (the only machine
kind that exists). Two affordances are designed so the owner can ratify either without a redesign,
both wired to the single `admin_capable` boolean:

- **Path 2a (recommended): Operator opts in at first run.** The wizard's Welcome step (§3.5)
  carries **one** honest, low-key secondary control: "I'm setting this up for an organization."
  Choosing it sets a local `admin_capable = true` fact. Off by default, phrased as a role
  declaration not a feature unlock, reversible in Settings later. Interaction: a plain
  checkbox/secondary button, no dark-pattern nudging.
- **Path 2b: Always-available.** On any machine `admin_capable` is simply true and the
  Administration tab always exists (the user is their own admin). No first-run affordance; Admin
  is just there in Settings.

**Recommendation to raise at the checkpoint:** Path 2a is more consistent with "route by
competence" and keeps Admin out of a solo user's way until they declare the role, at the cost of
one first-run control. Path 2b is simpler and truer to "an unmanaged user is their own admin" but
exposes the standup tooling to every solo user. **Both are wired to the single `admin_capable`
fact so the choice is one boolean's derivation, not a UI rework.** TA must also carry
`admin_capable` as one explicit fact in the CLI `--json` contract (Stage 1 open decision 1).
Flagged §7.

### 5.2 Admin window navigation model (corrected: two sections, no Fleet center)

One `Window` with a left **navigation sidebar** in **two** sections (Stage 1 §2, D4):
**Onboarding** (do-once standup checklist) and **Governance** (occasional). **There is no Fleet
section as a center of gravity** (the prior three-section sidebar with a Fleet daily-ops center is
removed; the `FleetView`/`FleetHostView` DTOs stay owner-gated and deferred, Stage 1 §3.H).
Standard macOS source-list interaction: single selection drives the detail pane; section headers
are static, not collapsible-to-hidden.

The **Onboarding section header carries the handoff status object**
`{publisher, admin, artifact_ref, next_owner}` as a persistent, read-only banner (rendered, not
computed; belongs in the CLI contract, Stage 1 open decision 2, flagged §7).

```
┌──────────────────── Administration ─────────────────────────────┐
│ HANDOFF: Publisher done · Artifact v1.4.2 · Next: Admin (you)    │
├──────────────────┬───────────────────────────────────────────────┤
│ ONBOARDING       │  DETAIL PANE (selected item)                  │
│  Prerequisites   │                                               │
│  GitHub topology │                                               │
│  Authors & keys  │                                               │
│  Secret store    │                                               │
│  Seed generator  │                                               │
│  Policy signers  │                                               │
│  Preflight       │                                               │
│ GOVERNANCE       │                                               │
│  Deprovision     │                                               │
│  Analytics       │                                               │
│  Secret store    │                                               │
│  config          │                                               │
└──────────────────┴───────────────────────────────────────────────┘
```

**Deleted from the prior Admin sidebar (D4):** Managed keys, MDM profile, MDM upload, and the
entire **Fleet** section (Hosts, Actionable items). The seed generator (§5.4) is reused; the
managed-key collector and MDM flows are dropped. Below are the interaction specs for the key
flows; each renders CLI truth or authors an artifact and opens a PR; none computes ecosystem
verdicts.

### 5.3 Onboarding checklist progression and handoff header (reused)

- The **Onboarding** sidebar items form a do-once progression. Each carries its own
  done/current/upcoming mark (same roadmap grammar as the wizard and Publisher Setup, for
  cross-product consistency, Nielsen #4). Items are individually reachable (an admin may revisit
  any), but the checklist visibly shows what remains.
- The **handoff header** is the persistent orientation object at the top of the Admin window
  whenever Onboarding is active, answering "where is the baton" at every moment. Read-only,
  rendered from the CLI contract. When `next_owner` is the admin, the current onboarding step is
  subtly emphasized.

### 5.4 Seed generator (reused verbatim, the highest-value build)

**JTBD:** *When I must author the ecosystem seed and I will not hand-edit YAML, I want a guided
form that produces a valid seed and opens the PR for me, so I never touch a terminal or a raw
file.*

**Concepts considered:**
- **A: Raw YAML editor with live lint.** Rejected: this is exactly the hand-YAML dead-end the flow
  exists to remove.
- **B: One giant form.** Rejected: Miller/Hick; the seed has many fields (components, depts, pins,
  auth, policy_signers, telemetry); one wall of fields is the utilitarian-form anti-pattern.
- **C: Sectioned, progressively-disclosed form with a live read-only preview and a single
  Validate-then-Open-PR action.** **Selected.** Groups fields into digestible sections
  (Components, Departments, Version pins, Auth references, Policy signers, Telemetry), each a card;
  complexity revealed on demand; a read-only preview shows what will be produced without exposing
  an editable YAML surface.

**Interaction:**
- Sectioned form, native controls, an add/remove-row model for repeated entries (departments,
  components, signers). Inputs are **constrained** (pickers, typed fields, reference-choosers)
  rather than free text wherever the schema allows, so an invalid seed is hard to author (error
  prevention over handling). Note the **Components** section names the four CSE components, never
  products.
- A **live read-only preview** shows the assembled result in plain, structured form (a
  human-readable summary, not raw YAML), proving what will be produced without inviting
  hand-editing.
- **Validate** runs the Rust `admin/seed.rs` validation and renders results inline: each problem
  as a plain-language `FieldError`-style line attached to the offending field (`{layer_id, field,
  message}`, message guaranteed plain), never raw serde. Validation gates the PR action.
- **Open Pull Request** is enabled only when validation passes. It uses the author's **own on-
  device credential** to open the PR (the app does not push directly to a shared tier's protected
  content; it opens a reviewable PR, honoring one-way inheritance). Feedback: a calm "Opened pull
  request <ref>" with a Reveal / Open-in-browser link.
- **States:** default (empty/prefilled sections), focus (field), disabled (Open PR disabled until
  valid; add-row disabled at schema max), loading (validating; opening PR), **error** (inline
  per-field plain messages + a summary count "3 things to fix", each linking to its field),
  **empty** (first author: a helpful empty state per §6.2 explaining what a seed is and a "Start
  from the detected org" prefill CTA).

### 5.5 Central shared secret-store setup (new, replaces the deleted managed-key collector)

**JTBD:** *When I must connect my organization's shared secret store, I want a guided connect-and-
scope flow that never asks me to paste a secret into config, so the store is wired correctly and
access stays gated by GitHub team membership.*

This **replaces** the deleted MDM managed-key collector (§5.2). The store (Infisical / OpenBao,
D6) holds org/department integration keys; access is by GitHub-team membership; the **endpoint is
delivered via inherited org repo config, not MDM** (D4). The endpoint URL is not a secret.

**Interaction:**
- A short guided form: choose the store type (picker), enter the **endpoint URL** (a URL, not a
  secret; validated as a URL, inline, on blur), and **scope access by GitHub team** (a
  team-chooser mapping teams to store scopes). No secret is ever pasted here.
- **The secret-shape refusal is retained as a hard constraint** from the prior managed-key
  collector, because it is the load-bearing safety interaction: **any** field runs a fail-closed
  secret-shape check on input (high-entropy strings, known key prefixes, `BEGIN PRIVATE KEY`,
  etc.); if a value looks like a secret, the field **rejects it inline** with a plain refusal
  ("This looks like a secret. This setting never holds secrets; secrets live in the store itself
  or the keychain.") and **blocks** it from being saved. A constraint (error made impossible), not
  a warning dialog. The rejected value is not stored or echoed to logs.
- Output: the endpoint + scoping become part of the inherited org config the seed/PR carries (the
  app opens a PR, never writes managed config locally). Verification that the store is reachable is
  a Preflight check (§5.7), not asserted here.
- **States:** default (form), focus, disabled (a field not applicable to the chosen store type
  disabled with a reason, honest slot-showing), loading (n/a; local validation is synchronous;
  opening the config PR shows a brief spinner-with-label), **error** (per-field plain message; the
  secret-shape rejection is a distinct, firmer style but still plain-language), **empty** (first
  use: each field explains itself; required fields marked).

### 5.6 Team-grant / entitlement (new, the entitlement spine made a surface)

**JTBD:** *When I stand up a department, I want to grant a team read/write to its repo, because
that grant IS the entitlement, so belonging and access are one thing I set in one place.*

Entitlement **is** GitHub repo access (D3); this surface is where the admin creates/observes the
grant that makes a user entitled to a layer (the same fact `copilot layers` later reports to that
user).

**Interaction:**
- A per-department view: the department's repo, its team, and the **grant** (read = entitled to
  inherit the layer; write = an author). The admin adds a person/team to a grant; the app opens a
  PR / calls the GitHub grant path via the author's own credential (it does not compute access; it
  effects the grant and renders GitHub's truth).
- **The grant is presented as the entitlement in plain language**, not as an abstract permission:
  "People on this team can join the Sales department" (read) and "These people can author the Sales
  layer" (write). This is the legibility that closes the loop with the user's S11 "Available to
  join" row: the admin sees the grant is what lights that row up.
- No secret ever appears here (a grant is repo access, not a credential).
- **States:** default (department grants list), focus (a grant row / the add control), disabled
  (add disabled while a grant call is in flight), loading (applying a grant, spinner-with-label),
  **error** (a plain "Couldn't change access right now. Try again.", never a raw GitHub/API
  string), **empty** (a department with no grants yet: "No one can join this department yet. Grant a
  team read access to let them in." + an add CTA).

### 5.7 Preflight (reused, red/green, owner-named, no aggregate score)

**JTBD:** *Before I hand the org its setup, I want an honest red/green list where every red names
who must fix it, so I never roll out on a broken foundation and always know who to chase.*

Renders `PreflightReport` (`checks: PreflightCheckResult[]`, each `{check, status, detail}`, status
`pass | fail | unknown`).

- **Presentation:** a plain checklist, one row per check, each row = a **shape + color + text**
  status mark (never color alone) + the check name + a one-line `detail`. `pass` = a quiet green dot
  + "Ready". `fail` = a red mark + the plain detail. **`unknown` is rendered distinctly and is NEVER
  green** (a neutral/amber "Not checked" or "Couldn't reach this"; unknown must never read as pass).
- **No aggregate score, ever** (FF-M7-NOSCORE): no "8/10 ready", no percentage, no gauge. The honest
  summary is a **count** of reds and unknowns as plain text ("2 things must be fixed, 1 could not be
  checked"), a fact, not a computed health judgment.
- **Owner attribution:** every `fail` and `unknown` row names its owner (**Publisher / Admin /
  User**) inline, so the admin knows who to route it to.
- **Drill-in / fix:** clicking a red row expands to the plain `detail` and a **fix affordance**
  appropriate to the owner: Admin-owned -> a link to the relevant onboarding step (e.g. "seed does
  not parse" -> jump to Seed generator with the offending field focused); Publisher-owned -> the
  plain instruction + the handoff reference; User-owned -> the plain description. Never a raw error,
  never a dead end.
- **Run model:** on-demand (a "Run preflight" primary), not a continuous signal. Re-run always
  available. While running: a quiet per-check `ProgressView` as each resolves (the list fills in),
  never a global ETA. The checks now cover the corrected spine (repos, teams/entitlement, secret
  store reachable, seed parses, pins resolve, policy signed), **not** MDM/managed-key checks.
- **States:** default (last report or "not run"), loading (checks filling in), **error** (a check
  that itself errored renders `unknown` with an honest reason, never a crash), **empty** (never run:
  an empty state explaining preflight + a Run CTA), disabled (Run disabled while a run is in flight).

### 5.8 Governance: deprovision-by-revocation, analytics, secret-store config

- **Deprovision (S8, §4.9 IT side):** the full `DeprovisionView` panel: a render of GitHub-access
  revocation + secret-store token rotation (no MDM wipe). `retained_dirty` prominent,
  `secrets_touched` must be 0, `secrets_alarm` honest, `unreadable` -> honest holding. The app
  **never triggers** it; it renders the CLI/server-performed event.
- **Analytics opt-in:** off by default; only when the org signs telemetry config. A plain switch +
  a read-only render of what would be sent; no dark pattern.
- **Secret-store config:** a **read-only** render of the inherited org config endpoint (the app does
  not re-point it from user config; honored only from signed inherited org config).

### 5.9 Admin keyboard / VoiceOver (reused)

- Sidebar is a standard source list: Up/Down between items, section headers announced, selection
  drives the detail pane.
- Forms: `FocusState` chains top to bottom; Tab traversal; Return submits the section primary;
  inline errors are announced on the offending field (`accessibilityValue` carries the error message
  so a VO user hears the fix without hunting). The secret-shape refusal (§5.5) is announced firmly.
- Preflight rows: each a VO element announcing "check name, status, owner"; status always in the
  label (never color/shape only).
- The handoff header is a VO container announced on window open ("Handoff status: publisher done,
  next owner you").

---

## 6. Cross-cutting interaction patterns

### 6.1 Loading strategy per surface (decision tree applied, corrected)

The app renders CLI truth, so "loading" is almost always "waiting on a poll", and the honest
default is **never a blank screen and never a fabricated value**.

| Surface | Strategy | Rationale |
|---|---|---|
| Popover first paint | **Skeleton** of the known regions (header line + tree rows placeholder) | layout is known |
| Popover status refresh (open) | **In-place**, no spinner; the sentence updates via live region | avoid flicker |
| Component tree | **Skeleton rows** while first `RenderState` loads | known list shape |
| **Join-available / departments list** | **Skeleton rows** while `copilot layers --json` resolves; per-row joining is an inline named-phase | known list shape; join duration unknown |
| **Shared integrations register** | **Skeleton rows** while the shared read resolves; fail-to-silence if the command is not landed | known list shape |
| **Personal-key sync roster** | **Skeleton rows** while the roster resolves | known list shape |
| Wizard materialize/verify | **Named-phase progress**, indeterminate, streaming log if present | duration unknown; ETA forbidden |
| Personal sign-in pending | **Indeterminate "waiting for you in the browser"**, no timer | duration unknown; countdown forbidden |
| Preflight | **Progressive fill** (rows resolve as checks arrive) | content loads in chunks |
| Seed validation / PR open, grant apply, secret-store PR | **Spinner-with-label** ("Validating...", "Opening pull request...", "Applying access...") | short, discrete, unknown-but-brief |
| Update transport | **Named-phase line**, `spinner` glyph | transport; ETA forbidden |

Never a bare spinner with no label; never a blank white pane; never an optimistic fabricated value
(the app cannot optimistically show Healthy, or a joined layer, or an available shared integration,
since it computes nothing).

### 6.2 Empty states (explanation, benefit, CTA, optional visual) (corrected)

Every data-backed surface has a designed empty state, not a blank:

| Surface | Explanation | Benefit | CTA |
|---|---|---|---|
| Popover Healthy | "Everything is set up." | (the silence is the benefit) | Sync now (available, not urged) |
| **Departments (none entitled)** | "No departments are available to you yet." | new departments appear here when you're added to one | none (honest wait) |
| **Shared integrations (none)** | region is **absent** | (nothing to show is honest) | none |
| **Personal Key Sync (off / no other Macs)** | "Turn this on to stop copying keys between your Macs." | your own keys follow you | the enable switch |
| Seed generator (first author) | "Author the ecosystem seed without touching YAML." | a valid seed + an opened PR, no terminal | "Start from the detected org" |
| Team grant (no grants) | "No one can join this department yet." | granting a team read access lets them in | "Grant a team" |
| Preflight (never run) | "Run preflight before you hand over the setup." | catches blockers before the org does | "Run preflight" |
| Bob lane (nothing) | renders nothing at all | silence is success | none |
| What changed (nothing recent) | "Nothing has changed since you last looked." | reassurance | none |

Empty is never an error; the Bob-lane empty is literally the absence of the region. **The deleted
Fleet empty state is gone** (no Fleet surface).

### 6.3 Honest-degrade and the cli-unreadable "bang" (reused verbatim)

Exactly two failure registers, neither a raw error nor a fake pass:

1. **Honest holding states** (offline, waiting-for-network, it-config-incomplete, wizard `holding`,
   a join that could not complete, a shared integration that could not resolve): calm, named,
   owner-attributed, always with a forward action or a "this will clear on its own" note.
   First-class, not errors.
2. **cli-unreadable / `bang`** (`client_state = cli_unreadable`): the app cannot trust the CLI
   contract. The only red glyph, no component tree, no join row, one plain sentence ("I can't read
   the setup right now, so I won't guess"), retry only. `cli_unreadable_reason` (`io_error |
   parse_error | schema_out_of_range | missing_security_field | exit_2 | invalid_content`) selects a
   plain-language sentence variant but the **reason token is never shown**; the raw string is never
   shown. `missing_security_field` fails **closed** (renders as unreadable/attention, never safe).

The universal rule: **no raw yaml / serde / git / signature / watchdog string ever reaches a user
surface.** Every error field is guaranteed plain by the DTO contract (`FieldError.message`,
`WizardState.error`, `UpdateState.message`, `DeprovisionView.sentence`, the layers-join failure line,
the cli-unreadable variants); the app renders those and only those, never a caught raw exception.

### 6.4 Notifications-denied fallback (reused verbatim)

When `notifications_denied` is true, any surface that would have been a `UNNotification` (the two Bob
prompts) is **re-hosted in the popover Bob lane** with an honest one-line "why here" note, and
Settings surfaces the plain steps to re-enable notifications (render-only guidance; the app never
silently re-prompts the OS). A live exposure is never controlled solely by a notification that may not
fire (types.ts Flow 7).

### 6.5 Reduce Motion (reused verbatim)

The tray glyph has motion states in the badge vocabulary: **`hollow` slow pulse** (setup-needed) and
**`ring` rotation** (syncing), plus the app-self-update `spinner`.

- **With Reduce Motion ON:** pulse and ring rotation are **replaced by a static distinct shape** (the
  `hollow` outline holds steady; the `ring` becomes a static ring mark; the `spinner` a static
  in-progress mark), so the **state stays distinguishable without animation** (shape-first is the
  design; motion was only ever the second channel). No looping motion anywhere.
- Popover disclosure, wizard step transitions, verify reveals, the join-row and enroll-row transitions,
  copy-confirm fades: all **cross-fade only** with Reduce Motion (no slide, no spring scale-in).
- Reduce Transparency: `NSVisualEffectView` materials fall back to opaque system colors automatically.
- **No motion is load-bearing:** every state that animates is fully legible frozen. The glyph must read
  correctly in grayscale, color-blind, and Reduce Motion simultaneously.

### 6.6 Keyboard shortcuts (global list, reused)

| Shortcut | Scope | Action |
|---|---|---|
| `Cmd-,` | any Control Tower window key, or the right-click menu | Open Settings |
| `Cmd-w` | any window | Close that window |
| `Cmd-q` | app (menu) | Quit |
| Return | focused default button | Activate primary (Continue, Open Sign-in Page, Join, Run preflight) |
| Esc | popover / a modal sheet | Close popover / cancel that sheet only (inert in the wizard body) |
| Tab / Shift-Tab | any focusable surface | Standard focus traversal |
| Arrow keys | component tree, sidebars, radio groups, lists | Standard navigation |
| Space | focused control, VO-focused status item | Toggle / activate |

No app-global hotkey to summon the popover (§1.4); flagged §7.

### 6.7 Focus order and focus management (universal, reused)

- Every window/panel/sheet sets an explicit initial focus (named per surface).
- On any step/pane change, focus moves to the new context's title or first control so keyboard and VO
  users are not stranded on a now-hidden element.
- The system focus ring is **never restyled** (it is the signal of nativeness and the a11y contract).
- Modal sheets trap focus; modeless windows/panels do not steal focus from another app until the user
  acts.

### 6.8 VoiceOver labeling approach (universal, reused, extended)

- **Status is always in text**, never conveyed by shape or color alone: every badge, dot, and glyph
  exposes an `accessibilityLabel` that is the state name, and every row announces "name, status name,
  detail".
- **Live regions:** the popover status sentence, the wizard phase label, the join-row joining state,
  the enroll-row state, and the update line are polite live regions so changes are announced without
  stealing focus.
- **Groups:** the roadmap, the Bob lane, the two integration registers, the departments list, the
  key-sync roster, the handoff header, and each form section are accessibility containers with
  descriptive group labels. The **Shared integrations group announces it has no actions** so a VO user
  does not hunt for a sign-in button that does not exist.
- **Never announce SF Symbol names** ("key" is "needs sign-in", "bang" is "error, cannot read setup").
- Copyable values (device code, machine id, artifact ref, handoff block, PR ref) are selectable and
  readable; their copy buttons are labeled by what they copy. **Secret values are never rendered** and
  so never announced (the key-sync conflict names machines and recency, never the value).

---

## 7. Open questions for the design checkpoint

1. **`admin_capable` on the (only) unmanaged machine (owner call).** The MDM grant path is deleted
   (D4). Both remaining affordances are designed and wired to the single `admin_capable` boolean:
   **Path 2a** (first-run opt-in via a low-key "I'm setting this up for an organization" declaration,
   off by default, reversible in Settings) vs **Path 2b** (always-available Administration tab).
   Recommendation: Path 2a. TA must also place `admin_capable` as one explicit fact in the CLI `--json`
   contract.

2. **The handoff object in the CLI contract.** `{publisher, admin, artifact_ref, next_owner}` is
   rendered in the Admin onboarding header and referenced by preflight; it must be a parsed CLI field.
   TA to place it.

3. **`copilot layers` / `layers join` (D7.1) must fold into WS-A at freeze.** The whole S11 surface
   (wizard step, Settings panel, popover Join row) depends on the payload shape
   `{tier, id, name, repo, entitled, joined, reason?}` and the `join` result set
   `{joined | already-joined | not-entitled | error}`. Currently "proposed, not yet in upstream WS-A
   scope".

4. **The shared-integrations read (S12/D7.2) needs a DTO.** Today `types.ts` has `AuthIssue` /
   `SigninState` for the **personal** register only. The Shared register needs its own read (e.g.
   `copilot integrations --json` distinguishing shared-entitled-no-signin from personal-device-flow),
   CLI-computed. The app must render it, not derive it. Until it lands, the Shared region renders
   nothing (defensive).

5. **Personal-key multi-machine sync carrier (S13/D7.3).** The surface is designed (§4.6); the
   transport/carrier is an open design item (`credentials-and-boundary.md` §7) that must reconcile with
   the per-device on-device key model (a device is enrolled by its own key; no private key moves). TA /
   CLI to choose the carrier and the status/conflict read the app renders.

6. **`ProductView.product -> component` field rename (D2)** is TA code work; the experience already
   treats it as the component view and all copy names copilots/components.

7. **`WizardMode.managed` is vestigial (D4).** This experience renders only the one guided window. TA to
   decide whether to retire the `managed` arm or leave it as a dead branch that renders nothing.

8. **Layer-setup blank-row semantics (unchanged).** The spec allows a repo-URL row (wizard step 4) to be
   left blank where a component can materialize from a broader tier. Confirm the CLI signals which
   components may have a blank personal source, so the caption is honest rather than guessed.

9. **A global hotkey to summon the popover?** Deliberately omitted (no user-domain configurable, no
   invented hotkey). Owner to decide; default is no.

10. **"Sync now" while a cadence sync is mid-flight.** Designed as disabled-with-reason during
    `syncing`. Confirm the CLI is safe to invoke a manual sync during cadence, or whether it should
    queue vs no-op.

---

## 8. Implementation implications (handoff to uids and the implementer)

- **Components:** `NSStatusItem` + template glyph with a static/animated variant per `BadgeState` (and a
  Reduce-Motion static variant for `hollow`/`ring`/`spinner`); a transient `NSPopover` with the six
  stacked regions (header, component tree, join-available, two integration registers, action row, Bob
  lane); a `NavigationSplitView` assistant window (shared grammar with Publisher Setup, reuse the roadmap
  sidebar, now 10 roadmap rows); a tabbed `Settings` scene (General, Components & Layers with the S11
  panel, Integrations with the S12/S5 split, Personal Key Sync S13, Advanced, conditional
  Administration); an Admin `Window` with a **two-section** source-list sidebar (Onboarding, Governance)
  + handoff header; non-transient floating `NSPanel`s for steady-state personal sign-in and dirty-work;
  modal sheets for wizard sign-in and the conflict chooser.
- **Data / DTOs:** existing `RenderState`/`HeaderView`/`ProductView`(=component)/`LayerView` (popover),
  `WizardState`/`WizardStep`/`SigninState` (wizard + personal sign-in), `UpdateState` (S9),
  `DeprovisionView` (S8), `BobLaneView`/`BobPrompt`/`BobNotice`/`SecurityBanner` (Bob lane),
  `SettingsState`/`LayerRow`/`LayerInput`/`FieldError` (Settings), `PreflightReport`/
  `PreflightCheckResult` (Admin preflight). **New parsed facts TA must add:** the `copilot layers` /
  `layers join` payloads (S11), the shared-integrations read (S12), the personal-key-sync status/roster/
  conflict read (S13), the `admin_capable` fact, and the handoff object. **Deferred / owner-gated:**
  `FleetView`/`FleetHostView`/`FleetActionItem` (no Fleet surface in Admin now). **Removed:**
  `DeptProjectView`/`LayerView.projects` (D8, no project nests in a layer).
- **Commands:** the existing wizard/update surface; the defensive-invoke pattern (`get_bob_lane`,
  `get_security_banner`) extended to the new reads (layers, shared integrations, key-sync) so a
  not-yet-landed command fails to silence, never fabricates; Admin seed/preflight invoke the existing
  Rust `admin/seed.rs` and `admin/preflight.rs`; the seed/grant/secret-store PRs use the author's own
  on-device credential. No new compute; the app renders and passes back.
- **Validation rules that are interaction-load-bearing:** the secret-shape rejection (§5.5, retained from
  the deleted managed-key collector) is a hard constraint, not a warning; seed validation gates the PR
  action (§5.4); wizard field validation is on-blur/on-submit plain-language inline; `unknown` preflight
  checks are never rendered green; the icon has no path to fabricate Healthy; the Shared integration
  register structurally has no auth affordance; department join renders and passes back a CLI-computed
  entitlement, never derived.
- **The never-render-raw guarantees:** every user-facing error string comes from a DTO field the contract
  guarantees plain; the app never renders a caught raw exception, yaml, serde, git marker, or
  signature/watchdog text; and it never renders a secret value anywhere (the key-sync conflict names
  machines and recency, never the value).

---

*Stage 2 complete, on the corrected CSE domain. Route to uids (Stage 3, visual system) for the six
popover regions, the assistant/Admin windows, the badge-glyph family, the two integration registers'
visual distinction, and the eight-state visual treatments; and to cw for final microcopy of every
placeholder string herein (status sentences, the join-available line, the two integration-register
labels, the personal-key what-syncs/what-never blocks, prompt/notice/holding copy, empty states, the
secret-shape refusal, the bang variants). The interaction contract and all state coverage are defined
here.*
