# UX Design

> **Provenance.** Grounded translation, not fresh invention. Every design decision below traces to a
> user story (`03-requirements/10-user-stories.md`), an all-states / error scenario
> (`03-requirements/20-use-cases-and-scenarios.md`), a struggling moment or moment-that-matters
> (`02-service-design/20-journey-maps.md`, `40-moments-that-matter.md`), or the Soul's Feature Filter
> (`SOUL.md`). Interaction *surfaces and states* are lifted from the engineering design docs
> (`03-design/design-core.md`, `design-integration.md`, `01-architecture/architecture.md` §2/§5/§6/§9);
> their **superseded dual-process / "Aviator" branding is ignored** — only the surfaces and the
> CLI-parseable state model are carried. Genuine unknowns marked `<!-- TODO -->`.
>
> **The product is a macOS menu-bar (tray) app.** There is no page, no window that stays open, no
> scroll. The template's web-IA / responsive vocabulary is therefore re-grounded in tray reality:
> a status glyph, a dropdown popover, a modal wizard, and a rarely-opened Admin window.

---

## Design Principles

*These override generic UX conventions on purpose. The Soul's air-traffic-controller character
(`SOUL.md` §2) inverts several defaults product design usually treats as virtues.*

| # | Principle | The generic convention it overrides | Traces to |
|---|-----------|--------------------------------------|-----------|
| **P1** | **Silence is the success state.** When everything is fine, the icon is a plain solid glyph and the app says *nothing* — no toast, no "all good!", no green celebration. The best message is no message. | "Confirm success; reward the user; keep them engaged." | Soul §6 taste test, §7 tone; MTM-2; Bob emotional arc "oblivious (good)" |
| **P2** | **The icon cannot lie.** Status is a *parse* of fresh `doctor --json`, never a computed guess. There is no code path to render Healthy without a fresh `status: healthy`; missing security fields fail closed to *fail*, never to green. A false-Healthy is the single worst outcome in the product. | "Degrade gracefully / stay useful offline by estimating state." | US-B07, US-O05, US-O06; MTM-2 (rank 1); Soul Principle 1 |
| **P3** | **Never hand Bob a decision he can't judge.** Route by *actor-competence × reversibility*: auto-act on reversible things Bob can't judge, escalate to IT what he can't action, ask Bob *only* about his own data. Proximity to the menu bar is not competence. | "Empower the user; give them control; let them self-serve." | US-B13, US-B15, US-B17; §9 Bob-agency; MTM-3/MTM-4; Soul Principle 2 |
| **P4** | **Every non-Healthy state is honest, distinct, and named.** No blended "needs attention." Each holding state gets its own shape/badge **and** a plain-language sentence that names the failing **product and layer** ("CLI Copilot — department layer needs sign-in"). State is never conveyed by color alone. | "Roll everything up into one severity indicator to reduce clutter." | US-B08, US-B09; E21; MTM-2; a11y bar below |
| **P5** | **As little app as possible.** One glyph, one dropdown, near-zero questions. Every surface added is audit burden; the essential job must survive without it. If a screen isn't load-bearing for provisioning Bob, keeping him healed, or letting IT see the fleet, it does not exist. | "Add a dashboard, a settings hub, a chat, an activity feed." | Soul Principle 3, §4 anti-patterns; ruled-OUT list |
| **P6** | **Design the holding and failure states first.** The happy path (Silent First Light) is one line; the product's quality lives in *IT-config-incomplete*, *Waiting-for-network*, *Signed-out*, schema-mismatch, and the security-shadow. Those are designed before Healthy. | "Design the happy path, then bolt on error handling." | All Critical/High struggling moments; scenario set E1–E22 |

**When principles conflict** (carried from `SOUL.md` §3): **P2 (can't-lie) > P3 (route-by-competence) >
P5 (as-little-app).** An *added honest state* always beats a *smaller* UI, because a false-Healthy is
worse than one more badge. Security-posture-never-weakened sits above all three as a constraint.

---

## Information Architecture

*"If this product were a building, what rooms would it have?" — deliberately almost none. Three
surfaces, ranked by Bob-impact (journey Touchpoints §, Founding Decision 2 "Bob-first").*

### The owner's model — the dropdown is PRODUCT-FIRST (products × layers)

*The dropdown is organized the way the owner reasons about the ecosystem: by **product**, not by host.
This corrects an earlier draft that grouped the menu by host (`Hosts ▸ Claude / Codex / Shared`) — that
was a drift. Claude and Codex are **products**, not hosts, so host-grouping is subsumed into
product-grouping.*

- There are **N products** (the initial set is four — **Knowledge Copilot, CLI Copilot, Claude Copilot,
  Codex Copilot**). **Product is a config-driven attribute**: the UI renders however many products the
  ecosystem declares, never a hardcoded four. Design "for each product," generically.
- **Each product independently has all four layers: foundation → org → department → personal.**
  "Foundation" is a per-product layer, not a shared host — so the old "Shared" bucket disappears; it was
  really each product's foundation layer.
- A **temporary department *project*** appears as an entry under the **department layer** of its product
  (it is scoped state within a tier, not a fifth tier).
- **Worst-wins is preserved and nested, not relaxed** (see the state matrix): the single tray glyph =
  the worst state across **all products × all layers**; a product's health = the worst across **its four
  layers**; a layer's state is its own parse. This is an *added* level of honest attribution, never a
  blend. A product reads "up to date across all 4 layers" **only** when all four parsed
  current + fresh + authed; any missing/unreadable layer holds honestly, never green (P2).

```
Copilot Control Tower
│
├─ SURFACE 1 — Tray icon + status dropdown        ◀── THE HERO (Bob's whole product, 99% of use)
│   ├─ The status glyph            (menu-bar, always visible; the "icon that cannot lie";
│   │                               worst-wins across ALL products × ALL layers — UNCHANGED)
│   └─ The dropdown popover         (opened on click; state-adaptive)
│       ├─ Status sentence          (top line — plain language; names the worst PRODUCT + LAYER)
│       ├─ Primary action           (contextual to the worst item: Sync / Repair / Sign in / Finish setup)
│       ├─ Product list             (one row per product — DATA-DRIVEN, N products, not hardcoded 4)
│       │   ├─ Knowledge Copilot     ─┐  each row: product name
│       │   ├─ CLI Copilot            │  + per-product health badge+text (worst of its 4 layers)
│       │   ├─ Claude Copilot         │  + a short state phrase; expandable ▾ (progressive disclosure)
│       │   └─ Codex Copilot         ─┘
│       │       └─ (expanded) Four-layer status   ◀── which tier is current / behind / repairing
│       │           ├─ Foundation     (badge+text per layer)
│       │           ├─ Org            (badge+text per layer)
│       │           ├─ Department     (badge+text; temporary dept PROJECTS listed here as entries)
│       │           └─ Personal       (badge+text per layer)
│       ├─ Secondary actions        (What changed · Add a skill · Open cheat-sheet)
│       ├─ Preferences…             (schedule, notifications, MDM status, launch-at-login)
│       └─ Quit
│
├─ SURFACE 2 — First-run wizard                    ◀── seen ONCE ("Silent First Light")
│   ├─ Managed silent path          (progress spectator — 0 questions)
│   ├─ Unmanaged guided path         (≤3 questions)
│   ├─ Honest holding screens        (IT-config-incomplete · Waiting-for-network)
│   └─ Teach panel                    (cheat-sheet · add first skill · backup offer)
│
└─ SURFACE 3 — Admin / fleet window                ◀── Earl (IT), not Bob; opened rarely
    ├─ Setup flow                     (seed gen → scaffolding → policy → MDM profile → preflight)
    ├─ Fleet dashboard                (healthy / stuck / behind / needs-auth at a glance)
    ├─ Version-skew panel
    ├─ Govern queue                   (held-majors to approve · time-boxed Bob items · policy log)
    └─ Offboard                       (Deprovisioned=true → soft-then-hard)

Outside the product (referenced, not owned): the MDM push · the IT AdminContact safety channel ·
the browser device-flow sign-in · the org telemetry endpoint.
```

**Navigation model.** There is **no navigation** for Bob — the dropdown is a near-flat menu whose one
depth affordance is the **per-product expand ▾** (each product row discloses its four layers inline, in
place). This is progressive disclosure, not navigation: nothing takes Bob to another screen; a layer
list unfolds beneath the product and folds back. The wizard is linear and mostly auto-advancing. Only
the Admin window has tabbed sections, because Earl is technical and does real work there. This asymmetry
is the Bob-first decision made structural.

> **Miller's-Law tension the product-grouping introduces (flagged).** With N products the list can grow
> past a comfortable glance. Resolution: the **product list is one chunked, visually-grouped section**
> that scrolls internally if it exceeds its cap, so the *top-level* affordances outside it (status
> sentence · primary action · Secondary actions · Preferences · Quit) stay ≤7 and always visible. Layers
> are revealed **one product at a time** (expanding a second product may collapse the first, keeping the
> open set small) — so Bob never faces N × 4 rows at once. The worst-wins glyph + one honest sentence
> mean Bob rarely needs to expand anything: the list is depth on demand, not a wall.

**What the user sees first / what waits.** First glance = the glyph shape + (if not Healthy) one
sentence naming the worst product and layer. Next, without expanding: the **product list** with a health
badge per product — Bob sees *which product* is off. Only if he wants the tier detail does he expand a
product to see *which layer* (foundation / org / department / personal) is behind or repairing.
Everything else — what changed, preferences — waits behind a click. The periphery (the glyph) carries
the whole steady-state signal; the foreground (the dropdown) opens only when Bob decides to look, and
the four-layer detail only when he decides to dig.

**Explicitly no room for** (Soul Feature Filter, ruled OUT): an in-app chat / "ask if my Mac is okay"
surface, an offline health score, a "make it Healthy anyway" override, a Bob-facing approve/unblock
control, a settings panel that re-points the update feed, an activity-feed dashboard for Bob. Their
absence *is* the design.

---

## Task Flows

*Numbered steps, not diagrams. Failure and holding paths are first-class, not appendices.*

### Flow 1 — The Silent First Light (managed Bob, hero happy path) · US-B01, US-B05 · S1 · MTM-1

1. IT has pushed the signed app + a complete `.mobileconfig`. Bob logs in (or double-clicks once).
2. App launches as an Accessory (menu-bar) process; installs login-item + crash-watchdog and persists
   a checkpoint **at this first phase** (so a mid-setup quit resumes headlessly — US-B05/E4).
3. App reads `dev.enac.controltower` from the forced/managed domain and **schema-validates it before
   entering silent mode** (see Flow 3 if it fails).
4. All required keys present + typed → **silent mode**. The wizard shows a single progress view with
   the current phase named ("Setting up Claude…"). **Bob is asked nothing.**
5. Supervisor runs Ring-1 phases via CLI verbs (detect → clone → materialize → verify), streaming
   phase events into the progress bar.
6. On `doctor --json status: healthy`, the glyph transitions **Setup-needed → Healthy**; the wizard
   foregrounds the **teach panel** (cheat-sheet + "add your first skill" + backup offer, US-B06), then
   returns the app to Accessory (menu-bar-only) mode.
- **Questions asked: 0.** Terminal windows shown: 0. Outcome: a working, team-scoped partner and an
  honest Healthy glyph. *(Where it can't reach Healthy honestly, it holds — Flows 3 & 4, never a
  false-Healthy.)*

### Flow 2 — Unmanaged setup (≤3 questions) · US-B02, US-B06 · S2

1. Bob double-clicks on a Mac with no managed profile → **Welcome** → host-detection probe.
2. **Q1 (only if ambiguous):** both hosts or neither found → "Which do you want to set up?" One host →
   auto-selected, no question.
3. **Q2:** Sign in via **GUI device flow** — show the 8-char code + a copy button, open the browser,
   poll `gh auth status`. No terminal. Skipped if a token is already present.
4. **Q3:** Company (suggested from email domain, confirmed) + department (**numbered pick-list** from
   the Teams API, never free-text YAML). Single-team → auto-picked, no question.
5. Products pre-checked from `ecosystem.yml` (Bob may narrow, never widen) → pull repos → materialize +
   verify → **teach panel**.
- **Questions asked: ≤3.** Everything else (OS/arch, prereqs, repo URLs, product set, git identity) is
  derived.

### Flow 3 — Fail-closed: IT-config-incomplete (the anti-false-Healthy path) · US-B03 · E1 · MTM-1

1. Managed profile has a required key **absent** or **malformed** at step 3 of Flow 1.
2. **Absent** → retry across a settling window (absorbs a partial MDM apply). Still absent at window
   end → step 4. **Present-but-invalid** (bad type / unparseable URL) → **immediately** to step 4.
3. Glyph enters **IT-config-incomplete** (outline + **wrench** badge) — *never* Healthy, *never* a
   silent hang.
4. Dropdown top line: plain sentence — "IT setup is incomplete (`<key>`). Nothing you need to do — IT
   has been notified." A content-free `config-incomplete` safety signal reaches the IT `AdminContact`
   channel. No Bob action exists (P3).

### Flow 4 — Offline / seed-not-yet-published: Waiting-for-network · US-B04 · E2, E3

1. First run completes **foundation-only** offline (or before `ecosystem.yml` exists).
2. Glyph enters **Waiting-for-network** (dimmed + **clock** badge) — never Healthy, never a scary error.
3. Dropdown top line: "Set up as far as your network allows — I'll finish your company setup when
   you're back online." "Seed coming" vs "solo user" is distinguished via the managed
   `EcosystemSeedURL` (E3), so a solo user is *not* held forever.
4. On reconnect / seed-appears the supervisor completes company clones automatically — **no
   re-wizard** — and the glyph advances to Healthy.

### Flow 5 — The glance (steady state — the most frequent flow) · US-B07, US-B08 · MTM-2

1. Bob glances at the menu bar between tasks (no click).
2. He reads the **glyph shape** in ~0.5s: solid = fine, badged = a specific thing.
3. If Healthy, he looks away — done. If badged, one click reveals a single plain sentence naming the
   worst **product and layer** and the one action, plus the product list showing which product is off
   (expand for the tier — Flow 6).
- This is the highest-frequency flow in the product and the reason the whole state matrix exists.

### Flow 6 — Take an action from the dropdown · US-B12 · S3

1. Bob clicks the glyph → dropdown opens, top line = current status sentence.
2. The **primary action is contextual** (Fitts's Law: largest, top of body): Healthy → "Sync now";
   Needs-attention → "Repair…"; Signed-out → "Sign in…"; Setup-needed → "Finish setup…".
3. Bob clicks it → the app spawns the matching CLI verb with `--json`; the glyph flips to **Syncing**
   (animated ring) and streams the phase name into the top line. **The menu never mutates state
   itself** — every action is a CLI call.
4. On completion the glyph returns to its parsed state (Healthy or the honest result).

### Flow 7 — The Fix That Acts Itself (security shadow — no Bob decision) · US-B17 · S4 · E8 · MTM-3

1. `update --json` returns a `changed[]` entry with `severity_trailer: security` + `shadowed_by:
   <Bob's stale override>`.
2. Router classifies **reversible + Bob-can't-judge ⇒ AUTO-ACT**: the override is auto-suspended so the
   fixed version wins **immediately**. In parallel a content-free safety signal reaches IT.
3. To Bob — *if and when he ever looks* — the dropdown shows a quiet, **past-tense** line: "Kept you
   safe — a security fix replaced a component you'd overridden. Re-affirm your version ▸." A Bob
   notification is **never** the sole control on a live exposure.
- No prompt, no decision, no badge to clear. The exposure closed by an action, not a hope.

### Flow 8 — The Honest Interruption (asked only about own data) · US-B13 · E22

1. A sync needs a dirty *personal* working tree committed, **or** the one sign-in re-approve expired.
2. Only in these two cases does Bob get a notification (or, if notifications are denied, the popover
   opens — E12/US-B16). The message is direct and singular: "Commit your unsaved personal work, then
   I'll sync" — the app **never** auto-resolves a dirty personal tree (invariant #3).
3. Everything he can't action (held-major, policy conflict, prune he didn't use) does **not** reach him.

### Flow 9 — Admin standup + fleet deploy · US-A01…A07 · S5 · CV-5

1. Earl opens the Admin window → **Seed generator** authors `ecosystem.yml` + opens a PR (no hand-YAML).
2. **Repo & access scaffolding** creates/verifies org + per-dept repos; **declared-repo existence
   check** flags a typo *before* rollout (US-A02).
3. **Capability-policy editor** signs with the security key (distinct from push).
4. **MDM profile generator** emits one pre-filled `.mobileconfig` (managed keys + login-item +
   notifications payloads).
5. **Red/green preflight** validates the whole path (seed parses · dept repos exist · policy signed ·
   profile complete-for-silent · pin resolves · mirror reachable). **Any red blocks deploy** and links
   to the offending item (E.g. a declared-repo 404 caught here, not as a field false-Healthy).
6. All green → Earl uploads one app + one profile to the MDM → the fleet self-provisions (Flow 1 at
   scale) → Earl watches the **fleet dashboard**.

### Flow 10 — Watch, govern, offboard (Admin steady state) · US-A07…A14 · CV-4

1. **Dashboard** shows every machine as healthy / stuck / behind / needs-auth at a glance (rests on
   honest CLI-parsed states — no false-Healthy can appear).
2. **Held-majors** arrive as *actionable* items in the Govern queue (Bob only ever saw "waiting on
   IT"). A Bob-actionable item left un-acted past its deadline **time-boxes** here too (US-A09/E16).
3. **Offboard:** setting `Deprovisioned=true` triggers server-side token revocation + MDM-run
   `deprovision`; **soft phase** quarantines clones for a grace window (a flip-back restores without a
   re-clone), **hard phase** wipes (`secrets_touched == 0`). A dirty personal tree is never wiped.

### Error & edge flows (designed first, mapped to the state they render)

| Edge (scenario) | Renders as | Recovery the user sees |
|---|---|---|
| Schema drift / missing `--json` field (E6, US-O06) | **CLI-unreadable / Error** state | In-app "Versions don't match — click to update" (paired self-update), **never** "run doctor in a terminal" |
| Vendored CLI killed by Gatekeeper (E5) | **CLI-unreadable / Error**, named finding | "Couldn't start the engine — click to reinstall" (`cli-spawnable` finding), not a generic red |
| Notification permission denied (E12, US-B16) | High-severity → **popover opens** as fallback | The dropdown surfaces the item; safety events also re-route to IT |
| Login item toggled off (E13, US-A12) | (Bob) unchanged glyph; (IT) "persistence disabled" | Managed fleets: non-toggleable payload; IT is told, not left guessing a powered-off Mac |
| Bad self-update crash-loops (E14, US-B18) | Nothing, or calm "Kept your working version" | Watchdog discards the bundle; no dead menu bar, no terminal |
| Held/blocked update (E10, E19) | **Update-available** dot; Bob view **informational only** | "An update is waiting on IT." No approve/unblock control exists for Bob |
| Prune of a recently-used tool (E11) | Quiet notification | "A tool you used was removed" — zero-usage prunes stay silent |

---

## Interaction Patterns

### ★ The Status-Icon State Matrix — the product's most important artifact

*Grounded in the CLI-parseable states (architecture §2), in strict precedence order. Every row is a
**parse** of `doctor --json` / `freshness --json` / `update --json`, never a computed guess. The
experiential family (the plain-language grouping a person would use) is given alongside the canonical
CLI state.*

| # | CLI state (canonical) | Family | Parse basis (CLI source) | Icon: **shape/badge** (not color-only) | Dropdown top line (plain language) | Action offered | Notify? | Trace |
|---|----------------------|--------|--------------------------|----------------------------------------|-----------------------------------|----------------|---------|-------|
| 1 | **IT-config-incomplete** | *Holding* | managed profile fails schema-validate | outline **+ wrench** | "IT setup is incomplete (`<key>`). IT has been notified." | none (P3) | IT only | US-B03, E1 |
| 2 | **Signed-out** | *Auth-needed* | `auth[].state ∈ {expired,revoked}` for a required layer | solid **+ key** | "CLI Copilot — department layer needs sign-in. Everything else is up to date." | **Sign in…** (own data) | Bob (own data) | US-B08/B09, E22 |
| 3 | **Needs-attention** | *Needs-you* | `doctor.status == needs-attention` (warn / unhealable fail survived auto-repair) | solid **+ amber triangle** | Names the finding + failing **product and layer** in one sentence | **Repair…** (CLI verb) | only if Bob-actionable | US-B09, US-B10 |
| 4 | **Offline** | *Holding* | `doctor.offline == true` / `update.result == offline` | **dimmed + cloud-slash** | "Using cached content — you're offline." (overlay; restores prior state) | none | no | arch §2; E2 kin |
| 5 | **Waiting-for-network** | *Holding* | first-run foundation-only; company layers pending | **dimmed + clock** | "Finishing your company setup when you're back online." | none | no | US-B04, E2/E3 |
| 6 | **Syncing** | *Working* | an app-scheduled `update`/`repair` in-flight | solid **+ animated ring** | "Syncing… (`<phase>`)" | none (in progress) | no | S3 |
| 7 | **Update-available** | *Holding / Blocked* | `freshness.stale == true` OR `held_for_approval` non-empty | solid **+ dot** | "An update is available" / "An update is waiting on IT." | **What changed?** (never approve, for held) | no | US-B15, E10 |
| 8 | **Healthy** | *Healthy* | `doctor --json status: healthy`, fresh, authed | **solid, no badge** | "Everything's in sync." | Sync now (optional) | **never** | US-B07 |
| — | **Setup-needed** | *Holding* | wizard never completed | **hollow outline**, slow pulse | "Let's set up your copilot." | **Finish setup…** | no | Flow 1/2 |
| — | **CLI-unreadable / Error** | *Error* | exit `2`, schema out of range, or missing security field (fail-closed) | solid **+ bang (!) badge** | "Versions don't match — click to update." | **Update / reinstall** (in-app; no terminal) | no | US-O06, E5/E6 |
| — | **Updating-app** | *Working* | Control Tower self-updating | **spinner** | "Updating Control Tower…" | none | no | arch §2; US-B18 |

**The one rule that governs every row:** *the glyph is only ever a faithful parse of a fresh CLI
`--json` verdict — there is no code path that renders Healthy without a fresh `status: healthy`, and
any missing/unreadable security field fails closed to a non-green honest state, never to green. Colour
is never the sole encoder — every state pairs a distinct **shape/badge** with a **plain-language
sentence** that names the failing **product and layer**.* (P2 + P4; US-B07, US-B09, US-O05, US-O06.)

**Worst-wins, per-product × per-layer attribution (nested, not blended).** The single glyph shows the
*worst* state across **all products × all layers** (precedence column order) — this is **UNCHANGED**.
What changes is the *attribution beneath it*: the top sentence names the worst **product and layer**;
the **product list** gives each product its own health badge (the worst of that product's four layers);
and **expanding a product** attributes down to the tier — foundation / org / department / personal —
showing which layer is current, behind, or repairing in the background. Bob learns a precise fact
("CLI Copilot — department layer needs sign-in"), never a blur (US-B08, E21). Updates are per-product,
per-layer transactional, so a Knowledge-Copilot-success / Codex-Copilot-fail (or an org-success /
personal-fail within one product) leaves a consistent lock at each product-layer.

### Microinteractions (Trigger → Rules → Feedback → Loops)

| Interaction | Trigger | Rules | Feedback | Loops / over time |
|---|---|---|---|---|
| **Status transition** | fresh CLI JSON changes the parsed state | transition **only** from fresh JSON (never inferred); worst-wins across all products × layers rolls up to the glyph, each product's badge rolls up from its four layers | glyph cross-fades shape/badge (~180ms); the affected product row and layer badge update in place; VoiceOver announces the new sentence (product + layer) via live region | Bob learns the shapes; over weeks the badge alone is enough — text becomes confirmation, not discovery |
| **Product row expand ▾** | Bob clicks a product row's disclosure | inline reveal of the four-layer status; opening one product may collapse another (keep the open set small) | layer rows unfold beneath the product (~180ms), each with its own badge + sentence + any dept-project entries; VoiceOver reads product then each layer | rarely needed — the glyph + sentence usually suffice; expansion is depth on demand |
| **Syncing ring** | an `update`/`repair` spawns | one invocation in flight per product-layer; coalesce triggers | thin ring rotates on the glyph; top line streams the product + layer + phase name; the affected product/layer row shows its own ring | most syncs are silent+fast; the ring is a reassurance, not an alarm |
| **Security auto-suspend** | `severity_trailer: security` + stale override | AUTO-ACT (reversible); IT escalated in parallel | *no* live interruption; a quiet past-tense line appears next time the dropdown opens ("Kept you safe") | Bob may re-affirm his override later — ownership preserved |
| **Sign-in device flow** | Signed-out → "Sign in…" | GUI device flow only, never a terminal | 8-char code shown in-window + copy button; browser opens; spinner until `gh auth status` passes | rare by design; the one recurring Bob credential moment |
| **Teach panel reveal** | first successful setup | shows once; re-openable from the menu | wizard foregrounds (Accessory→Regular), then returns to Accessory | re-open from "Open cheat-sheet" any time (US-B06) |

**Error-prevention hierarchy applied** (prefer prevent > suggest > undo > confirm):
- **Constraints:** department is a pick-list, not free text; products can be narrowed, not widened;
  Bob has *no* approve/unblock/force control to misuse (the errors are made impossible, not caught).
- **Suggestions:** company slug pre-suggested; products pre-checked from `ecosystem.yml`.
- **Undo (reversible-by-default):** override auto-suspend is re-affirmable; deprovision is
  soft-then-hard with a grace-window restore; a bad self-update rolls back to the working version.
- **Confirmation (last resort, destructive only):** the *only* confirm Bob ever sees is "commit your
  dirty personal work before I sync" — because that's the one destructive-adjacent action the CLI's
  never-destroy guard routes to him.

### Notification pattern (rare by design)

Notifications fire **only** when Bob is the sole competent actor for a non-deferrable decision about
his own data (P3, §9). Everything else auto-acts or escalates to IT. When macOS notification permission
is denied, high-severity events **fall back to opening the popover** and safety events re-route to IT
(US-B16, E12) — a denied prompt never silently kills the alert tier. Tone is per `SOUL.md` §7: quiet
and past-tense for auto-acted security ("kept you safe"), direct and singular for a Bob-owned action,
reassuring understatement for a rollback ("kept your working version").

### Admin-window patterns (Earl, technical)

The Admin window is the one surface allowed real density (Earl is competent; Hick's/Miller's limits
relax). Patterns: a **red/green preflight** (binary, scannable, any red blocks deploy and deep-links to
the fix); a **fleet table** sortable by health family (healthy / stuck / behind / needs-auth); a
**skew bar** (fraction on current locked SHA); a **govern queue** (held-majors + time-boxed Bob items
+ content-free policy log). No item here is ever also shown to Bob.

---

## Responsive Strategy

*"Responsive" for a tray app is not breakpoints — it's the desktop-tray realities: popover sizing,
multiple displays, menu-bar overflow, light/dark, and the notch. Primary and only device class:
**macOS desktop/laptop** (Windows is a deliberate later re-skin per `CLAUDE.md` Tech — design every
OS-integration edge so the re-skin is mechanical).*

| Dimension | Strategy | Rationale / trace |
|---|---|---|
| **Popover sizing** | Fixed comfortable width (~320pt); height grows to content, caps with internal scroll on the **product list** (N data-driven products) and on the Needs-attention finding list. Anchored to the glyph, arrow pointing up. | Miller's Law — top-level affordances outside the product list stay ≤7; the product list is a chunked section that scrolls internally so N products never push Preferences/Quit off-screen |
| **Multi-display** | The popover opens on the display that owns the menu bar the glyph was clicked on; the wizard (a real window) opens centered on the **active** display, not always the primary. | Bob may dock to an external monitor; the wizard must not appear off-screen |
| **Menu-bar overflow / hidden glyph** | If the glyph is hidden by a crowded menu bar (or a Bartender-style hider), high-severity events that would notify **also** post a system notification, so a hidden glyph never suppresses a real signal. State the glyph as *aspirationally always-visible* but never the *sole* channel for anything critical. | US-B16 logic generalized; the glyph is the primary but not sole channel |
| **Light / dark menu bar** | Ship the glyph as a macOS **template image** (mask, not baked colours) so the system tints it for light/dark automatically; badges (wrench/key/clock/dot/triangle/bang) are drawn as distinct **shapes** so they read in either mode without relying on colour. | P4 no-colour-only; a11y contrast bar below |
| **Notch (menu-bar clipping)** | The glyph lives right-of-notch with system items; the app claims no menu-bar title text (glyph-only) so it survives a narrow notched bar. If macOS hides the glyph under the notch, fall back per the overflow rule. | Modern MacBook reality |
| **Reduced-motion** | Honour `NSWorkspace` reduce-motion: the Syncing ring becomes a static "syncing" glyph state + text; no essential info is motion-only. | a11y; motion is never the sole encoder |
| **Retina / scale** | Glyph + badges as vector/PDF template assets rendered per backing scale; no raster blur at any density. | craft |

---

## Accessibility

*Phase 3 left the a11y bar as a resolved open question; this section **sets it as the product's
standard.** Because the core promise is an honest, glanceable status, accessibility here is not a
nicety — a status a screen-reader user can't read, or one carried by colour alone, breaks the central
guarantee for that user.*

### The standard (stated, not aspirational)

**WCAG 2.1 AA is the floor, plus a menu-bar-specific bar the product treats as non-negotiable:**

1. **No status by colour alone (hard rule).** Every state pairs colour with a **distinct shape/badge**
   (wrench / key / clock / dot / amber-triangle / bang / animated-ring / hollow-outline / solid) **and**
   a plain-language sentence. A monochrome or colour-blind rendering is fully legible. (US-B09, P4.)
2. **VoiceOver labels on the glyph, every product row, every layer, and every dropdown item.** The tray
   item exposes an `NSAccessibility` label that reads the *current status sentence* naming the worst
   product and layer ("CLI Copilot — department layer needs sign-in. Everything else is up to date."),
   not "app icon". **Each product row** has a label naming the product and its rolled-up health
   ("Knowledge Copilot — up to date across all 4 layers", or "Claude Copilot — org layer updating,
   expand for detail"). **Each layer row**, when expanded, has its own label ("Org layer — updating in
   the background"; "Department layer — needs sign-in"), and dept-project entries are named
   individually. Every action row names its action and the CLI effect in plain language ("Repair —
   fixes the finding IT can see"). Badges are described, never left as decoration.
3. **Status changes are announced.** A transition posts an `NSAccessibility` announcement / drives an
   ARIA `role="status"` live region in the web popover, so a screen-reader user hears the new state
   without re-opening the menu. Security auto-suspend announces its quiet past-tense line the same way.
4. **Full keyboard operability — dropdown and wizard.** The dropdown is reachable and fully operable by
   keyboard (open, arrow through rows, **Right/Left or Enter to expand/collapse a product's four-layer
   list**, Enter to invoke an action, Esc to close); the product list is a `tree`/`disclosure` pattern
   so expand state is announced. Documented tab order in the
   wizard is **Welcome → host choice → device-flow code (focus lands on the code, copyable via
   keyboard) → company field → department pick-list → products → progress → teach panel → Done**. No
   step is mouse-only; the device-flow 8-char code is selectable/copyable without a pointer.
5. **Visible focus, always.** Every interactive element has a visible focus ring meeting AA
   non-text-contrast; focus is never trapped except deliberately in the modal wizard (with Esc/Cancel
   escape).
6. **Contrast.** Glyph and badge shapes meet **≥3:1** against *both* the light and the dark menu bar
   (non-text/UI-component contrast, WCAG 1.4.11); all dropdown/wizard body text meets **≥4.5:1**;
   large text ≥3:1. Verified in both appearances, not just one.
7. **Motion is never the sole signal.** The Syncing ring is paired with the "Syncing…" sentence and
   respects reduce-motion; no state is distinguishable only by animation.
8. **Plain language, no jargon.** Per the taste test — a glance answers "is it OK, and do I have to do
   anything?" in one sentence with no YAML, no `copilot` verb names in Bob's line, no blended verdict.
   (Serves cognitive accessibility for the non-technical primary persona, which is the whole point.)

**Who might struggle, and the answer.** The primary persona *is* the accessibility case: Bob is
non-technical, may be colour-blind, may run VoiceOver, may never open the menu. The design answers each
— shape+text not colour, spoken status not just visual, popover-fallback when notifications are denied,
and near-zero required interaction. The Admin window targets the same AA bar; its density is acceptable
because Earl opts into it, but its preflight red/green also carries shape/text, never colour alone.

<!-- TODO: confirm whether the org telemetry / Admin dashboard needs an explicit high-contrast theme
     beyond system light/dark, and whether kiosk/multi-user (arch §11 open decision 3) changes the
     VoiceOver focus model for a shared login. -->

---

## Traceability summary

| Design element | Primary trace |
|---|---|
| Status-icon state matrix (11 states, one governing rule) | US-B07/B08/B09, US-O05/O06; MTM-2 (rank 1); arch §2 |
| Product-first dropdown (glyph → sentence → product list → four-layer expansion) | Owner's model (products × layers); US-B08; E21; P4 |
| Silent managed wizard (0 questions) | US-B01/B05; S1; MTM-1 |
| Unmanaged wizard (≤3 questions) | US-B02; S2 |
| Fail-closed IT-config-incomplete + Waiting-for-network | US-B03/B04; E1/E2/E3; MTM-1 |
| Security auto-suspend, no Bob decision | US-B17; S4/E8; MTM-3 |
| Honest interruption (own data only) | US-B13; E22; §9 |
| No approve/unblock control for Bob | US-B15; E10/E19; Soul Feature Filter (OUT) |
| Admin standup → preflight → deploy | US-A01…A06; S5; CV-5 |
| Fleet dashboard + govern + offboard | US-A07…A14; CV-4; S6 |
| CLI-unreadable / Error, no-terminal recovery | US-O06; E5/E6 |
| A11y standard (no colour-only, VoiceOver, keyboard, contrast) | US-B09; Phase-3 resolved open question |

**Related:** [User Stories](../03-requirements/10-user-stories.md) ·
[Use Cases & Scenarios](../03-requirements/20-use-cases-and-scenarios.md) ·
[Journey Maps](../02-service-design/20-journey-maps.md) ·
[Moments That Matter](../02-service-design/40-moments-that-matter.md) · [SOUL](../../../SOUL.md)
