# Design Challenge Brief

> **Provenance.** Synthesis, not fresh invention. This brief is the design mandate for Phase 6, drawn
> straight from the completed front end: `SOUL.md` (principles, IS/IS-NOT, Feature Filter, quality bar,
> anti-patterns), `04-experience-design/50-ux-design.md` (surfaces, the status-state matrix, the a11y
> bar), `04-experience-design/60-ui-design.md` (the **Air-Traffic Instrument** visual direction, tokens,
> glyph family — the design-system basis), `04-experience-design/70-copy-voice.md` (voice, banned
> language), `02-service-design/40-moments-that-matter.md` (the trust moments the concepts must nail),
> `03-requirements/10-user-stories.md` (P0 scope), and `00-overview/00-vision.md`. Genuine unknowns are
> marked `<!-- TODO -->`.
>
> **Deliberate deviation from the template's default.** The PCC template calls for **five** concepts per
> critical view. This product's design space is *heavily constrained by the Soul on purpose* — no
> color-only status, no alarm, no celebration, no computed score, silence-is-success, native-not-branded.
> Five "genuinely different answers" would force at least two of them to violate a Soul invariant to be
> distinct, which is a trap. This brief therefore runs **three** named concept directions that all honor
> the guardrails and compete on *interpretation within them* (§5). This is a scoped, documented override,
> not a shortcut.

---

## 1. Brief Overview

### 1.1 Purpose

This document is the design mandate for the prototype phase of **Copilot Control Tower** (the settled
product name, shown to the end user — see §8.3). Before any prototype is built, the critical views, creative direction, and
evaluation criteria are defined and agreed. The approved direction becomes the minimum lovable bar.

This is not wireframing. It is a constrained concept competition (three directions) followed by a working
prototype. The wireframe-level truth already exists — the status-state matrix, the two wizard paths, the
copy for every state. What Phase 6 resolves is **visual and interaction interpretation**: which reading of
Air-Traffic Instrument best makes an honest status legible in half a second.

### 1.2 Primary Audience

| Role | Responsibility |
|------|----------------|
| Lead Designer | Leads concept production; owns design approvals; enforces the Soul Feature Filter as a design gate |
| UI/UX Designers | Produce the three distinct concept directions across the four critical views |
| Product Owner (Pablo) | Reviews, reacts, approves; gates the design-to-prototype transition |

### 1.3 Process Position

```
[Phase 1-4 complete: vision, service design, requirements, experience design; SOUL DRAFT v0.1]
      |
      v
[Design Challenge Brief — this document]  <-- YOU ARE HERE
      |
      v
[Product owner reviews and agrees with brief]
      |
      v
[Concept production: 3 named directions x 4 critical views]
      |
      v
[Product owner reacts; direction converges; runners-up grafted]
      |
      v
[Phase 6: Working coded prototype (token-driven, Tauri web-UI stack) — see §8]
      |
      v
[Prototype approved — Design Complete Checkpoint cleared -> SOUL ratified to v1.0]
```

**Design Complete Checkpoint** is the Stop-the-Line gate for design. No prototype is built until this
brief is agreed. Clearing it is also the trigger to ratify `SOUL.md` from DRAFT v0.1 to v1.0 (Soul §10).

---

## 2. Critical Views

### 2.1 What Is a Critical View

A critical view is a screen or phase within Control Tower that is:

- Directly tied to a Moment that Matters (`40-moments-that-matter.md`);
- A primary product differentiator — something that makes Control Tower distinct from "a GUI over a CLI";
- The view a user meets at a decision point that determines whether the product earns trust or gets
  abandoned.

For this product the trust decision is nearly always the same one: *can I believe what the glyph is
telling me, in half a second, without being technical?* The critical views are the surfaces where that
question is answered — or betrayed.

### 2.2 Critical View Summary

| CV | View | Type | Primary user | Trust moment |
|----|------|------|--------------|--------------|
| **CV1** | The status-glyph state set — "the icon that cannot lie" | Component family (menu-bar) | Bob | MTM-2 (rank 1) |
| **CV2** | The status dropdown / popover across its key states | Screen (popover) | Bob | MTM-2, MTM-3, MTM-4 |
| **CV3** | The first-run setup wizard (silent managed + unmanaged) | Phase (windowed) | Bob | MTM-1 |
| **CV4** | The Admin / fleet dashboard (hosts x status) | Screen (window) | Raj (IT) | MTM-4, MTM-5, closes the observability gap |

Four critical views. Bob owns three of them (Founding Decision 2, Bob-first); Raj owns one, and it is
first-class because it is the enabler that makes a silently-working Bob possible at fleet scale.

### 2.3 Critical View Definitions

---

**CV1 — The status-glyph state set ("the icon that cannot lie")**

| Attribute | Detail |
|-----------|--------|
| Screens | The menu-bar glyph across **all 11 states** of the status matrix (`50-ux-design.md` ★matrix): Healthy, Setup-needed, IT-config-incomplete, Signed-out, Needs-attention, Offline, Waiting-for-network, Syncing, Update-available, CLI-unreadable/Error, Updating-app. |
| Phase | Steady state — the highest-frequency flow in the product (Flow 5, the glance). |
| Primary user | Bob, glancing between tasks, no click. |
| Why critical | MTM-2, ranked the #1 moment: a false-Healthy is the single worst outcome in the whole product. The glyph *is* Bob's product 99% of the time. It ships as a macOS **template image** — a monochrome mask the system tints — so **shape must carry state before color does**. |
| Design imperative | Each state is one honest mark = base (aviator-sunglasses silhouette) + a distinct **badge shape** (primary encoder) + a secondary tint. Must read in **grayscale** and in **both** light/dark menu bars. Healthy is the *quietest* mark — the brightest, most-saturated pixel in the menu bar is never Healthy. Worst-wins across two hosts. |
| Constraint | No color-only status (hard rule). No computed/blended severity blob. No green on the glyph. ≥3:1 glyph/badge contrast in both appearances. VoiceOver label = the current status sentence, never "app icon". Reduce-motion: the only motion (Syncing ring, Setup-needed pulse) must be redundant with shape+text. |

---

**CV2 — The status dropdown / popover across its key states**

| Attribute | Detail |
|-----------|--------|
| Screens | The 320pt system popover in its load-bearing states: **Healthy** ("Everything's in sync."), **Signed-out** ("Codex needs sign-in. Claude is fine." + Sign in…), **Needs-attention** (names the finding + Repair…), **IT-config-incomplete** (wrench, no action), **Waiting-for-network** (clock, no action), **Update-available / held** ("An update is waiting on IT.", *What changed?* only), **Security auto-suspend** (quiet past-tense "Kept you safe…"), plus the Hosts ▸ submenu. |
| Phase | On click, from any glyph state (Flows 6, 7, 8). |
| Primary user | Bob, when he decides to look. |
| Why critical | This is where "names the failing host" becomes a sentence and where the routing-by-competence discipline is made visible or betrayed. It is the surface most tempted toward *The Alert Machine* (a badge to clear, an approve button) and must refuse it. Copy is fixed by `70-copy-voice.md` §A — concepts render it, they do not rewrite it. |
| Design imperative | Top line is always the status sentence, always the heaviest text (the one Semibold in the body). One contextual, singular primary action (Fitts's Law: largest, high). Everything else waits behind it. Per-host attribution in the sentence + Hosts ▸. |
| Constraint | **No approve/unblock control ever renders for Bob** (US-B15, Soul: OUT). No badge-count-to-clear. No celebration on Healthy — flat, no green, no checkmark, no toast. Held update shows a *sentence*, offers only "What changed?", never a button that acts. Full keyboard operability; visible focus; live-region announce on state change. |

---

**CV3 — The first-run setup wizard (silent managed + unmanaged)**

| Attribute | Detail |
|-----------|--------|
| Screens | A real ~520x420pt window in two modes: (a) **silent managed path** — a single centered progress spectator view, phase name streaming ("Setting up Claude…"), **zero questions, zero buttons**; (b) **unmanaged guided path** — linear, ≤3 questions, with the **device-flow code** as the one hero moment (8-char SF Mono code + copy) and a **numbered department pick-list**; plus (c) the **honest holding screens** (IT-config-incomplete, Waiting-for-network) and (d) the **teach panel** shown once on success. |
| Phase | Seen once — "the Silent First Light" (Flows 1-4). |
| Primary user | Bob, day one, with a learned expectation that IT software means a support ticket. |
| Why critical | MTM-1: the first ninety seconds decide whether the ecosystem is adoptable by a non-technical person at all. The silent path's design job is to be *calm and boring* — a spectator view, not a form. The holding screens are where fail-closed honesty (never a false-Healthy, never a hang) becomes visible. |
| Design imperative | The holding/failure screens get **more** design attention than the happy path (P6). The device-flow code is legible and keyboard-copyable. Holding screens reuse the **same badge shape** as the glyph, large, so Bob learns the mark once. Completion is "You're set up." — understated, no confetti. |
| Constraint | No time estimates, ever (use phase names). No terminal, ever. Department is a pick-list, never free-text. Products can be narrowed, never widened. Documented keyboard tab order (`50-ux-design.md` a11y §4). Zero jargon in Bob's register (banned-language list). |

---

**CV4 — The Admin / fleet dashboard (hosts x status)**

| Attribute | Detail |
|-----------|--------|
| Screens | The one dense surface — a resizable window (min 900x600pt): the **fleet table** (rows = machines, sortable by health family: healthy / stuck / behind / needs-auth), the **red/green preflight** checklist, the **version-skew bar** ("83% on current SHA"), and the **govern queue** (held-majors + time-boxed Bob items + content-free policy log). |
| Phase | Admin steady state + standup (Flows 9-10). |
| Primary user | Raj (IT), technical, opts into the density; never Bob. |
| Why critical | Closes the ecosystem's named observability gap — "IT literally cannot tell a healthy Mac from a bricked one." It carries MTM-4 (held-major routes to the right desk) and rests entirely on honest CLI-parsed states, so **no false-Healthy can appear here either**. It is the surface most tempted toward *The Second Pilot* (a computed "health score"). |
| Design imperative | Density is *earned* (Hick's/Miller's limits relax for Raj), but the tone is identical to Bob's: still shape+color+text, still no gamification, still no computed score. The status cell renders the **same badge family** as the tray glyph + a status dot + a plain-language cell. Preflight verdict carried by ✓/✕ *shape*, not color. |
| Constraint | **No "fleet health 94/100" score, no trophy rings, no sparkline flourish** — a number that looks computed-by-us implies the app judges health (*The Second Pilot*). Any red preflight item blocks deploy and deep-links to the fix. No item shown here is ever also shown to Bob. a11y AA applies to Raj too — the ✓/✕ shape survives grayscale. |

---

## 3. Creative Direction

### 3.1 Philosophy

**Named direction (fixed, from `60-ui-design.md`): Air-Traffic Instrument — calm native utility, color
as a scalpel.** The product *is* an air-traffic controller (Soul §2); the interface is the instrument
panel in that tower. **Monochrome by default, legible under a half-second glance, color used only where
it carries a fact.** The whole aesthetic is *silence you can trust* — when everything is fine, the panel
is a plain solid mark and nothing draws the eye. The interface earns trust the way the product does: by
**subtraction**.

**Two reference points, and how they apply:**

- **macOS system menu extras (Wi-Fi, Battery, Sound)** — the gold standard for native, monochrome,
  template-glyph-first, silent-when-fine. This is exactly the register Control Tower lives in. We *add*
  the one thing they lack: a per-state badge vocabulary (wrench / key / clock / dot / triangle / bang)
  that names *which* thing, never a generic dot.
- **An air-traffic control strip board** — legible facts, precedence-ordered, worst-wins, no decoration,
  no reassurance the controller can't back up. This is the metaphor the three concept directions
  interpret differently (§5).

The five commitments from `60-ui-design.md` are not up for debate; they are the floor every concept
stands on: monochrome-first/color-as-scalpel; native-not-branded-native; silence-is-the-success-state;
honest-holding-states-designed-first; motion-is-confirmation-never-attention.

### 3.2 The Quality Bar

From Soul §6, verbatim in intent: **"If the tray has to explain itself, it failed."** A glance answers
"is it OK, and do I have to do anything?" in **half a second**, in one plain sentence that names the
failing host — no jargon, no blended verdict, no reassurance it can't back up. When everything is fine,
it is silent. **Silence you can trust is the whole aesthetic.**

"Functionally complete" is not the bar. The bar is: an enterprise security team can accept this as *safer
than a human running `copilot update` by hand*, and a non-technical person never once had to be technical.
Concretely, a winning concept must make **CV1 legible in grayscale in both appearances** and must make
**Healthy the quietest thing on screen**. If Healthy is eye-catching, the concept has failed the bar
regardless of how polished it is.

### 3.3 Anti-Examples

The one-liner (from `60-ui-design.md` Anti-Direction): **not a flashy consumer AI app, not a gamified
dashboard, not alarm-red-everywhere.** An interface that decorates, celebrates, or grabs attention is a
*trust regression* here. Reject on sight:

| Anti-pattern | Why it betrays this product |
|---|---|
| Purple/indigo→pink gradient, glow, "AI shimmer" | The AI-slop signature. Performs an intelligence the app deliberately doesn't have (*The Copilot of the Copilot*). |
| A big green Healthy / celebratory checkmark / "All good! 🎉" toast | Violates silence-is-success. Healthy is the *absence* of signal, never a reward. |
| Alarm-red everything, badge counts to "clear," pulsing dashboards | *The Alert Machine.* Red is reserved for the one genuine error (CLI-unreadable). A sea of red trains Bob to ignore the alert that matters. |
| A gamified fleet dashboard — health scores, trophy rings, sparkline flourish | Implies the app *computes* a score (*The Second Pilot*). It renders CLI facts only. |
| A settings-heavy, tab-rich consumer chrome for Bob | *As little app as possible.* Bob's surface is one glyph + one flat menu. Chrome is audit burden. |
| A dark "hacker terminal" aesthetic (neon-on-black, monospace body) | The whole point is that Bob never sees a terminal. Terminal aesthetics re-import the wall the product removes. |

**Anti-references to study and avoid:** any AI-product landing aesthetic (gradient hero, shimmer);
Datadog-style score-ring observability dashboards; iStat Menus at its densest (decorated, graph-heavy).

### 3.4 Tone and Texture

| Quality | What It Means in Practice |
|---------|--------------------------|
| **Calm** | No alarm words, no fake urgency, no red-alert theatre — even at a real failure. Failure is a plain sentence + one next step, not a siren. |
| **Honest** | Never "All good" when it can't prove it. Offline / mid-setup / unreadable render as *named holding states*, never a fabricated green. |
| **Spare** | One idea per surface. The status sentence is the only heavy text in the popover; everything else is Regular. Weight is hierarchy, not decoration. |
| **Native** | SF Pro, system materials/vibrancy, system radii and focus rings. It looks like it *shipped with macOS*, not a web app in a Mac costume. |
| **Quiet-when-fine** | Healthy is the plainest mark; silence is the success signal; the eye is drawn only when there is something true to say. |
| **Understated success** | "You're set up." not "Congratulations!". Understatement *is* the brand. |

---

## 4. Design System Basis

### 4.1 Foundation

The basis is the **Air-Traffic Instrument** token set already defined in `60-ui-design.md`. Concepts
**extend and interpret** it; they do not reinvent it. The tokens are the shared vocabulary:

- **Color** — macOS-aligned neutrals (`--surface-popover` = the AppKit material, not a flat fill;
  `--text-primary/secondary/tertiary`); `--brand-indigo #2D294E` (dark variant `#B4AEE8`); and the
  **status semantics** where *shape is the first encoder, color the second* — Healthy is the only green
  and never on the glyph; red (`#C5221F`) is the only error color and appears nowhere else.
- **Type** — SF Pro (Text + Display); SF Mono *only* for machine tokens a human must read/copy
  (device-flow code, SHAs, config keys). Weight = hierarchy. No third family, no web font.
- **Space** — base-4 scale (`2·4·8·12·16·20·24`); `--popover-width 320pt`; `--menu-row-height 28pt`
  (clears WCAG 2.5.8 AA 24px — a pointer+keyboard app, not touch); `--admin-window` min 900x600.
- **Radius / elevation / motion** — match the system; the popover's shape and shadow are AppKit's, not
  redrawn; motion is calm (`--motion-calm 180ms` cross-fade, `--motion-ring 1.2s` steady) and always
  redundant with shape+text under reduce-motion.

**Reference products to study** (directional, not templates): macOS system menu extras; Tailscale
menu-bar app; Little Snitch (instrument legibility); Linear (Admin density/restraint only); Time
Machine / Backblaze (honest, past-tense status, no celebration).

### 4.2 The Mark

The glyph is the **aviator-sunglasses silhouette**, brand `#2D294E`, ratified as template-friendly. It is
adopted as the *mark* — and is the **menu-bar tray glyph** Bob sees; the dead **"Aviator" codename** is
**retired and never a product name** on any surface (settled, §8.3), decoupled from the mark, which
survives. Concepts must treat the silhouette as a monochrome template mask first — if it doesn't read tinted-by-the-system at
menu-bar size in grayscale, the mark treatment fails.

### 4.3 Component Rules

```
[Design need arises]
      |
      v
[Token/component exists in the Air-Traffic Instrument set?]
  YES: Use it.
  NO:  Propose a new token/component -> product owner approves -> it is added to the set.
       (New status colors especially require the contrast matrix, §6.2.)
```

---

## 5. Concept Competition Rules

### 5.1 Deliverable

For each of the four critical views, the design team produces **three distinct concept directions** —
not three variations of one idea, but three coherent readings of Air-Traffic Instrument, each expressed
consistently across all four CVs.

| Type | CVs | Directions per CV | Total artifacts |
|------|-----|-------------------|-----------------|
| Critical views | CV1–CV4 | 3 | 12 |

**Why three, not the template's five** (see the deviation note at the top): the Soul's guardrails
(no color-only, no alarm, no celebration, no computed score, silence-is-success) intentionally collapse
the space of *honest* answers. A fourth or fifth concept could only be distinct by breaking a guardrail,
which fails pre-screening (§7.3) on arrival. Three real interpretations beat five where two are
straw-men.

### 5.2 The Three Directions (named, so we can argue without pointing at screenshots)

All three are **calm, honest, minimal, monochrome-first, no color-only status, no alarm, no computed
score.** They compete on interpretation, not on violating the Soul. Each must be carried consistently
through all four CVs.

**Direction A — "Native Instrument"** *(trust through disappearance)*
The most subtractive reading. The app dissolves into macOS: the glyph sits in the exact register of
Wi-Fi/Battery; badges are drawn at system weight; the popover is a near-native menu with the lightest
possible custom structure; the Admin window is a plain, Linear-restrained table. The bet: Bob trusts it
*because it is indistinguishable from the OS itself* — no product personality, no chrome to audit. Risk
to test: does maximal subtraction leave the badge vocabulary legible enough, or does it under-teach the
states?

**Direction B — "Named Signal"** *(trust through legibility)*
The state *vocabulary* is the hero. The wrench/key/clock/dot/triangle become a deliberately learnable
iconographic system, drawn a touch more distinctly than the OS would; the status sentence gets clear
typographic primacy; the wizard's holding screens visually echo the glyph badge at large size so Bob
learns each mark once and recognizes it forever. The bet: Bob trusts it because he *learns to read the
panel* — the badge alone eventually suffices, text becomes confirmation. Risk to test: does the stronger
badge treatment tip from "legible" toward "decorated"?

**Direction C — "Strip Board"** *(trust through honest fact-density)*
Leans hardest on the air-traffic metaphor. Per-host attribution and the fleet become a controller's
flight-strip register — aligned fact rows, worst-wins made spatial, monochrome with color as a scalpel.
Most distinct on CV4 (the dashboard reads as a strip board) and on CV2's Hosts ▸ detail. The bet: Bob
and Raj trust it because every fact is *present, aligned, and un-blended* — nothing is summarized into a
blur. Risk to test: does density fight the half-second-glance bar on CV1/CV2, where Bob wants one
sentence, not a board?

### 5.3 What "Distinct" Means

A direction is distinct from the others if it differs in at least two of these dimensions. The
directions above are engineered to differ primarily in **information hierarchy**, **typographic
system**, and **how far each leans on the metaphor** — *not* in color expression or motion philosophy,
which the Soul fixes for all three.

| Dimension | In-bounds contrast across the three | Fixed by the Soul (NOT a competition axis) |
|-----------|-------------------------------------|--------------------------------------------|
| Information hierarchy | Sentence-first (B) vs. glyph-first/minimal (A) vs. fact-rows (C) | — |
| Typographic system | System-default weight (A) vs. sentence-primacy (B) vs. aligned register (C) | — |
| Interaction model | Near-native menu (A) vs. taught progressive reveal (B) vs. scannable board (C) | — |
| Metaphor lean | Invisible (A) vs. learnable icon-language (B) vs. literal strip board (C) | — |
| Color expression | — | Monochrome-first, color-as-scalpel, Healthy = only green, red = only error |
| Motion philosophy | — | Calm cross-fade; motion is confirmation, never attention; reduce-motion redundant |

"We made the badge a different color" is not distinct. "We reorganized how per-host truth is
spatialized" (A's sentence vs. C's rows) is distinct.

### 5.4 Philosophy Descriptor Naming

Each concept is already named for its philosophy — **Native Instrument, Named Signal, Strip Board** —
answering "what is this concept's relationship to the user and to information?" (disappearance /
legibility / fact-density). Never present a concept without its descriptor. Invalid names ("Concept A,"
"Blue version," "Modern," "Clean") are not permitted.

### 5.5 Prototype Fidelity

Concepts must be:

- **Visually complete** — colors, type, spacing, badge shapes, and both light/dark renders are defined,
  not placeholder. Because color is fixed by tokens, "complete" here especially means the **badge shapes
  and the grayscale render** are resolved.
- **State-representative** — CV1 shows all 11 glyph states; CV2 shows the load-bearing popover states
  (§2.3); CV3 shows both wizard paths + holding screens + teach panel; CV4 shows table + preflight +
  skew + govern queue. The primary interaction pattern must be visible even if every micro-state is not.
- **Coded, light-interactive** — since the target UI is a tiny web UI inside Tauri, concepts are built
  as token-driven HTML/CSS (see §8), which makes light/dark, grayscale, and reduce-motion *testable*,
  not just asserted. Full production behavior is not required at this stage.

---

## 6. Constraints and Guardrails

### 6.1 Vision & Soul Alignment

Every concept must survive the Soul Feature Filter (§5) *as a visual decision*, and must be consistent
with the vision's AI philosophy — which here is a **design** guardrail, not only an engineering one.

| Vision / Soul principle | Design implication (binding) |
|-------------------------|------------------------------|
| **Parse, never compute** (invariant #1) | The UI may only render CLI truth. No visual may imply the app computed a verdict: **no health score, no blended severity gauge, no "confidence" meter, no trend line the app authored.** A number that looks computed-by-us is a *false-Healthy waiting to happen*. |
| **Single process / as little app as possible** (invariants #2, Principle 3) | Bob's surface is one glyph + one flat menu + a once-seen wizard. No settings hub, no activity feed, no dashboard-for-Bob, no chat. Chrome is audit burden; if a screen isn't load-bearing for provisioning Bob, keeping him healed, or letting IT see the fleet, it does not exist. |
| **The icon cannot lie / fail-closed** (P2, MTM-2) | Healthy has no visual path without a fresh CLI `status: healthy`. Missing/unreadable → a *named* honest state, never green. Healthy must be the quietest mark on screen. |
| **Route by competence** (P3, MTM-3/4) | **No Bob-facing approve/unblock/force control may be drawn** — the affordance must not exist to be misused. Held update = a sentence + "What changed?", never a button that acts. |
| **Security posture never weakened** (invariant #4) | No visual affordance for `--force` / `--skip-verify` / "make it Healthy anyway" / "unstick it" — the *words and buttons* for a bypass must not exist. |
| **Pure OSS, no monetization** (Founding Decision 1) | No "upgrade," "premium," "enterprise tier," or paywall surface anywhere. |

### 6.2 Accessibility

WCAG 2.1 AA is the floor, plus a menu-bar-specific bar the product treats as non-negotiable
(`50-ux-design.md` a11y §1–8). This bar is a **pre-screening gate**, not a finishing polish.

| Requirement | Applies to |
|-------------|------------|
| **No status by color alone** (hard rule) — every state pairs a distinct shape/badge + a plain-language sentence; the render is fully legible in grayscale | CV1, CV2, CV4 |
| Glyph/badge/UI-component contrast **≥3:1** in *both* light and dark; body text **≥4.5:1**; large text ≥3:1 | All CVs, both appearances |
| VoiceOver label on the glyph = the **current status sentence** ("Codex needs sign-in; Claude is fine"), never "app icon"; every menu row names its action + plain-language effect; badges described | CV1, CV2 |
| Status changes **announced** via live region / `NSAccessibility` announcement | CV1, CV2 |
| Full keyboard operability (open, arrow, Enter, Esc); documented wizard tab order; device-flow code keyboard-copyable | CV2, CV3 |
| Visible focus ring meeting AA non-text contrast on every interactive element | CV2, CV3, CV4 |
| Motion never the sole signal — Syncing ring / Setup pulse redundant with shape+text; honors reduce-motion | CV1, CV2 |
| Target size **24px (WCAG 2.5.8 AA)** — 28pt rows clear it; the AAA 44px touch heuristic does **not** apply to this pointer+keyboard desktop class | CV2, CV4 |

<!-- TODO: confirm whether the Admin dashboard needs an explicit high-contrast theme beyond system
light/dark, and whether kiosk/multi-user login changes the VoiceOver focus model (carried from
50-ux-design.md a11y TODO). -->
<!-- TODO: run the full contrast matrix (every status color x both surfaces x text-vs-UI thresholds) and
record measured ratios before implementation sign-off; the 60-ui-design.md values are design-target,
spot-checked not exhaustive. -->

### 6.3 Technology Constraints

- **Stack:** Tauri v2, Rust core + a **tiny** web UI — no heavy framework (`CLAUDE.md` Tech). The glyph
  ships as a macOS **template image**; light + dark are both first-class (not a theme toggle).
- **macOS-first**; design every OS-integration edge (glyph tinting, popover material, notch/overflow,
  multi-display) so Windows is a mechanical re-skin later, never designed-against now.
- No concept may assume a capability outside documented scope: **no in-app resolution/health/signature/
  wipe logic** (it lives in the CLI), no second scheduler, no daemon, no `KeepAlive=true`.
- The design token set is evolving; a new token/component (especially any new status color) must be
  agreed and contrast-verified before use.

---

## 7. Evaluation Criteria

### 7.1 The Primary Standard

**The half-second glance, honestly.** A winning concept lets Bob answer "is it OK, and do I have to do
anything?" in half a second, in grayscale, in both appearances — and makes Healthy the quietest thing on
screen. Everything else is secondary to that. A beautiful concept that makes Healthy eye-catching, or
that needs color to be read, loses to a plainer one that doesn't.

### 7.2 Evaluation Dimensions

| Dimension | What it means for this product |
|-----------|--------------------------------|
| **Glance legibility** | CV1 reads in <0.5s, in grayscale, in both light/dark. Healthy is the quietest mark. (MTM-2) |
| **Cannot-lie fidelity** | No visual implies a computed verdict/score/gauge; no path renders Healthy without proof; fail-closed states are *named*, not generic red. (MTM-2, *The Second Pilot*) |
| **Honest-state-first craft** | The holding/error/wizard-failure states are designed *better* than Healthy — the product's quality lives there. (P6) |
| **Names-the-host clarity** | Per-host attribution reads as a fact ("Codex… Claude is fine"), never a blur. (MTM-2, US-B08) |
| **Right-actor discipline** | No Bob-facing approve/unblock/force affordance is drawn; held items are informational. (MTM-3/4, P3) |
| **Native restraint** | Looks shipped-with-macOS; passes every anti-example (§3.3); no consumer-AI or gamified tells. |
| **A11y bar met** | §6.2 satisfied *in the concept*, not deferred — grayscale-legible, contrast-passing, VoiceOver-sentence-ready. |
| **Soul alignment** | Survives the Feature Filter as a visual artifact; no Alert-Machine / Second-Pilot / Copilot-of-the-Copilot tells. |

### 7.3 Pre-Screening (before the product owner sees a concept)

| Criterion | Pass | Fail (instant reject) |
|-----------|------|------------------------|
| Anti-example check | Would never appear in a consumer-AI app or gamified dashboard | Gradient/shimmer, trophy rings, celebratory Healthy, alarm-red-everywhere |
| Cannot-lie check | Healthy has no path without proof; nothing implies a computed score | A health gauge, a blended severity blob, a green glyph |
| Color-independence | Fully legible in grayscale | State distinguishable only by color |
| Right-actor check | No Bob approve/unblock/force control drawn | A "clear this" / "approve" / "unstick" button for Bob |
| Distinctness | A genuinely different reading (hierarchy/type/metaphor) | A recolor of another direction |
| Contrast | ≥3:1 glyph/UI, ≥4.5:1 text achievable in this treatment, both appearances | Requires a contrast compromise to work |

### 7.4 Decision Outcomes

| Outcome | Meaning | Next step |
|---------|---------|-----------|
| **Direction approved** | One direction (or a clear graft — e.g. B's badge system on A's chrome) gives a clear design direction | Proceed to Phase 6 prototype |
| **Direction narrowed** | The owner names what works and what doesn't across the three | Refine + a second round; **graft the best ideas from runners-up** into the lead (e.g. C's strip-board Hosts ▸ into B) |
| **Re-brief required** | All three miss the brief fundamentally | Re-align and start a new round |

**Runners-up are not discarded.** The expected outcome is a *graft*: pick the lead direction, then pull
the strongest single moves from the other two (Named Signal's learnable badges, Strip Board's honest
fleet register) into it. Document each graft against the criterion it improves.

---

## 8. Prototype Output

### 8.1 Chosen Format

**Selected: a working coded prototype — token-driven HTML/CSS/JS in the Tauri web-UI stack** (a small
"living tokens" gallery: the glyph family in a menu-bar mockup, the popover states, both wizard paths,
and the Admin dashboard).

**Reason.** For a token-driven native tray app, the qualities that decide the winner are *exactly the
ones a static Figma frame cannot prove*:

- **Light + dark + template tinting.** The glyph is a macOS template image tinted by the system; a coded
  prototype using `prefers-color-scheme` shows the real both-appearances behavior, not two hand-painted
  frames that might disagree with reality.
- **Grayscale legibility.** A CSS `filter: grayscale(1)` toggle turns the hard a11y rule ("no color-only
  status") from an assertion into a *test* anyone can run on the spot.
- **Reduce-motion redundancy.** `prefers-reduced-motion` proves the Syncing ring / Setup pulse degrade
  to shape+text, which a static export cannot demonstrate.
- **Tokens port directly to build.** The prototype's tokens *are* the design system the Tauri UI ships —
  no translation step, no drift between "the Figma" and "the code." This honors *as little app as
  possible*: the prototype is the spec.
- **Native materials.** System vibrancy/popover material and focus rings can be approximated far more
  honestly in the shipping web stack than in a drawing tool.

Figma may still be used for early *exploration* of badge shapes, but the **evaluated** artifact is the
coded prototype, because the evaluation criteria (§7) are behavioral (glance, grayscale, motion,
both-appearances) and only the coded form can be judged against them.

### 8.2 Design Complete Checkpoint

Before the prototype begins:

- [ ] Product owner has reviewed and confirmed the four critical views
- [ ] Product owner has confirmed the Air-Traffic Instrument direction + the three named concept directions
- [ ] Product owner has confirmed the evaluation criteria (glance-first, cannot-lie, honest-state-first)
- [ ] Prototype output format (coded, token-driven) is agreed
- [ ] Open decisions (§8.3) are acknowledged as tracked, not blocking
- [ ] Any adjustments are incorporated into this brief

### 8.3 Open Decisions to Record (surface, do NOT resolve here)

1. **Product name / brand — SETTLED (locked by owner).** The product name is **"Copilot Control Tower"**
   (short **"Control Tower"**) and it **is shown to the end user** — Bob sees it in the setup-wizard
   header, the dropdown/popover header, and About. It is **not** name-light. Both prior open questions
   are now resolved: (a) the aviator-sunglasses **mark survives** the codename retirement and is
   **decoupled** from it — it is the menu-bar tray glyph Bob sees, so CV1's mark treatment stands as-is,
   no replacement glyph needed; and (b) **Bob does see the product name**, in the chrome
   (wizard/header/About), while status *sentences* stay about his work. **"Aviator" is a dead
   engineering-only codename** that must never appear as a product name on any user surface (banned in
   `70-copy-voice.md`).
2. **High-contrast theme + kiosk/multi-user a11y** — see the §6.2 TODO.
3. **Full contrast matrix** — see the §6.2 TODO; required before implementation sign-off.

---

## 9. Reference Documents

| Document | Purpose |
|----------|---------|
| `SOUL.md` | Principles, IS/IS-NOT, Feature Filter, quality bar, anti-patterns — the brief's guardrails |
| `00-overview/00-vision.md` | Product vision, AI philosophy, acceptance criteria, the open name decision |
| `02-service-design/40-moments-that-matter.md` | The trust moments the concepts must nail (MTM-1…5) |
| `03-requirements/10-user-stories.md` | P0 scope the prototype must cover; the ruled-OUT list |
| `04-experience-design/50-ux-design.md` | Surfaces, the ★status-state matrix, the a11y bar |
| `04-experience-design/60-ui-design.md` | Air-Traffic Instrument direction, tokens, glyph family — the design-system basis |
| `04-experience-design/70-copy-voice.md` | Voice, banned language, the exact copy for every state |

**Related:** [SOUL](../../../SOUL.md) · [Vision](../00-overview/00-vision.md) ·
[UX Design](../04-experience-design/50-ux-design.md) · [UI Design](../04-experience-design/60-ui-design.md) ·
[Copy & Voice](../04-experience-design/70-copy-voice.md) ·
[Moments That Matter](../02-service-design/40-moments-that-matter.md) ·
[User Stories](../03-requirements/10-user-stories.md)
</content>
</invoke>
