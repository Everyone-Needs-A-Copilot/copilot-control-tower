# Design Challenge Brief

<!--
FACILITATION GUIDE — Lead Designer
====================================
The design challenge brief defines what will be prototyped during the
Critical Views phase. This is the bridge between design documentation
and the prototype output.

PREREQUISITE: ALL Phase 1-4 documents must be completed before
this brief is written. The brief synthesizes everything into
actionable design direction.

This document is synthesized from all prior documents. The product
owner must review and agree with the brief before prototype work begins
(Design Complete Checkpoint).

CONVERSATION FLOW:
1. Define the critical views that need to be prototyped
2. Define what a "Critical View" is (and what it is not)
3. Establish creative direction (drawing from UI Design doc)
4. Define the concept competition format (5 concepts per CV)
5. Define philosophy descriptor naming requirements
6. Set constraints and evaluation criteria
7. Confirm the prototype output format (Figma, spec, Storybook, Next.js)

QUESTIONS TO ASK:

## Round 1: Critical Views
- "Based on everything we've designed, what are the critical
  views that need to be prototyped?"
- "Which views represent the core experience?"
- "Which views test the riskiest design decisions?"
- "For {{PRODUCT_NAME}}, candidates might include the primary dashboard,
  the core workflow view, any AI output surface, and any configuration view"

## Round 2: What Is a Critical View
- "A critical view is not just any screen — it is a screen that is:
    1. Directly tied to a Moment that Matters
    2. A primary product differentiator
    3. The view a user encounters at a decision point that determines
       whether the product earns trust or gets abandoned"
- "For each candidate view: Is it tied to a Moment that Matters?
  Is it a differentiator? Is it a trust decision point?"
- "Which candidate views fail this test and should be deprioritized?"

## Round 3: Creative Direction
- "What's the creative direction for these prototypes?"
- Pull from 60-ui-design.md: visual direction, design tokens, anti-direction.
- "What is the anti-example — the thing this must never look like?"
- "Are there specific design risks to test in the prototypes?"
- "What does 'good design' mean for this product? What's the quality bar?"

## Round 4: Concept Competition Format
- "For each critical view, the design team will produce FIVE distinct
  visual concepts."
- "This is not five variations of the same idea. It is five genuinely
  different answers to the question 'what could this view be?'"
- "A concept is distinct if it differs in at least two dimensions:
    - Layout paradigm (card grid vs. single-column vs. split pane)
    - Information hierarchy (what is shown first, what is hidden)
    - Interaction model (tap-and-reveal vs. always-visible vs. progressive disclosure)
    - Typographic system (display-driven vs. data-table-driven vs. conversational)
    - Color expression (high-contrast dark vs. light and airy vs. warm and editorial)
    - Motion philosophy (instant vs. deliberate animation vs. ambient feedback)"
- "'We made the button a different color' is not a distinct concept.
  'We redesigned the information architecture' is a distinct concept."

## Round 5: Philosophy Descriptor Naming
- "Each concept must be named with a short descriptor that communicates
  its design philosophy."
- "Names like 'Minimal Presence,' 'Editorial Intelligence,' 'Dark Focus,'
  or 'Structured Clarity' help you discuss concepts without pointing at screenshots."
- "The name should answer: 'What is this concept's relationship to the
  user and to information?'"
- "Name them before presenting. Never show concepts without names."

## Round 6: Constraints
- "What technical constraints must the prototypes respect?"
- "What must be functional in the prototypes vs. placeholder?"
- "What data should the prototypes use — real or representative?"
- "What devices must prototypes work on?"
- "What accessibility requirements apply from day one?"

## Round 7: Evaluation Criteria
- "How will you evaluate the prototypes?"
- "What does 'good' mean for each view?"
- "What would be an instant rejection?"
- "What matters most: visual quality, interaction quality, or
  information architecture?"

## Round 8: Prototype Output
- "Now that the brief is complete, what output format will you use?"
- "See 06-prototype/README.md for options: Figma, Design Spec, Storybook, Next.js."
- "Which format best fits your situation and goals?"

SYNTHESIS:
This document becomes the mandate for Phase 6 (Prototype).
It must be specific enough to guide the prototype output without
further clarification. It includes: critical view definitions,
creative direction, concept competition rules, naming requirements,
constraints, and evaluation criteria.
-->

> **Status — rebuilt from evidence 2026-08-02. Describes Copilot Control Tower v0.4.0** (build 19, app commit `86b84c5`, release commit `453d15f`, notarized arm64 DMG embedding the pinned helper `cc 2.2.0`). Product status is **DOGFOODING** — live on exactly one organization (ENAC), sixteen of sixteen layers applied live, not offered to outside organizations, not generally available. **This document synthesizes a realized design.** It is not a speculative brief for work not yet begun.

## 0. Read this first — this brief's job has changed

In the normal Product Creation Copilot sequence this document is written **before** a prototype exists, to direct prototype work. That is not the situation here, and pretending otherwise would make this brief the first lie in a package rebuilt specifically to stop the documentation lying.

**The product already ships.** Eight version lines, seven retained signed releases, a live sixteen-of-sixteen ecosystem apply on a real organization. The "prototype phase" this brief was originally meant to direct **already happened, and it happened differently than planned**: the app was hand-built in native SwiftUI/AppKit on a separate design track, and its design of record is the native triad in [`docs/03-design/`](../../03-design/) — the [experience architecture](../../03-design/control-tower-native-experience-architecture.md), the [interaction spec](../../03-design/control-tower-interaction-spec.md), and the [visual system](../../03-design/control-tower-visual-system.md) — plus the [copy deck](../../03-design/control-tower-copy-deck.md). No Figma file and no Storybook library was ever the delivery mechanism, and the earlier version of this brief's mandate (which included an MDM-profile generator and a silent managed install lane) describes machinery that was explicitly rejected rather than built. That divergence is recorded across this rebuild as **gap G-3**.

So this document does two things instead of one:

1. **It synthesizes the realized design.** For each critical view it states what that view must accomplish and how the shipped design accomplishes it, with file-and-line evidence, so a future session can pick the product up without re-deriving it from roughly 22,650 lines of Swift.
2. **It becomes the standing gate for change.** Every critical view named here is load-bearing and in production. The brief's forward job is no longer "go design this" — it is **"here is how you judge whether a proposed change to any of these is right."** That is §7, and it is the part with teeth.

Everything a design challenge would normally *discover*, this product *has*. What it does not have is proof that its own rules are enforced, a second machine, and an outside user. Those are §9.

---

## 1. Brief Overview

### 1.1 Purpose

This document is the design synthesis and change gate for **Copilot Control Tower** at v0.4.0. It names the surfaces that carry the product's promise, records the creative direction as realized rather than as intended, states the constraints that are not negotiable, and defines how any proposed change to a critical view is judged.

The minimum lovable bar is not aspirational here. It is the bar the shipping app already clears on most of these surfaces, and the specific places where it does not are named in §9 rather than smoothed away.

### 1.2 Primary Audience

Written in this order of weight, per the ratified audience decision (`SOUL.md` §9 #17):

| Role | Responsibility |
|------|----------------|
| **The owner's future self / any later session** | Pick this product up without re-deriving it. This is the heaviest reader. Every claim carries evidence so the next session can trust it rather than re-check it |
| **Buyers and non-technical evaluators** | Understand what this thing looks like, why it looks restrained on purpose, and what it does for a person who cannot use a terminal |
| **Organizations weighing adoption** | See from the design language alone that this is infrastructure that stays out of the way, not another dashboard competing for attention |

**Deliberately not an audience:** open-source contributors submitting patches, and developers receiving an engineering handoff.

### 1.3 Process Position

```
[Phases 1-4 rebuilt from evidence: vision, research, service design, requirements, experience design]
      |
      v
[Design Challenge Brief — this document]  <-- YOU ARE HERE (synthesis of a realized design)
      |
      +---> backward: Phase 6's output already exists — the shipping native app plus the design triad (gap G-3)
      |
      +---> forward: any proposed change to a critical view enters at §7 and must survive the SOUL v2.0 Feature Filter
```

The original **Design Complete Checkpoint** — "no prototype is built until this brief is agreed" — is spent. It is replaced by a **Change Gate**: no change to a critical view ships until it has passed §7, and no change that fails a SOUL gate ships at all, regardless of how good it looks.

---

## 2. Critical Views

### 2.1 What Is a Critical View

A critical view is a surface that is:

- **Directly tied to a Moment that Matters** — one of the nine documented in [`40-moments-that-matter.md`](../02-service-design/40-moments-that-matter.md), every one of which is drawn from something that actually happened to this product.
- **A primary differentiator** — something that makes Control Tower distinct from the alternatives, which are a runbook and a terminal.
- **A trust decision point** — the place where a person decides, in seconds and without help, whether this tool is careful or broken.

For this product there is a fourth test that outranks the other three, because the essence is democratization and the mechanism is honesty: **a critical view is a surface where the product could lie.** Every view below is a place where a false green, a fabricated claim, an unbacked account, or a leaked internal token would end the relationship. That is why these are the ones that matter, and it is why the evaluation criteria in §7 are mostly about honesty rather than about aesthetics.

### 2.2 Critical View Summary

| CV | View | Type | Phase | Moment |
|----|------|------|-------|--------|
| CV1 | The tray at rest — the glyph and its twelve badges | Screen (persistent) | Steady state, forever | MTM-2 |
| CV2 | The popover — six regions and one prompt lane | Screen | Steady state, daily | MTM-2, MTM-5, MTM-6 |
| CV3 | The account of what just happened — Set up, and Verify | Phase (wizard 8–9) | First run, the one irreversible act | MTM-1 |
| CV4 | The stop that is not a failure — the Holding family, H4 in particular | Screen family (7 variants) | Reachable from wizard stages 5, 6, 7 | MTM-3 |
| CV5 | The roster reveal — What you're getting, Departments, **Your connections**, Your projects | Phase (wizard 4–7) | First run, the only pull beat | MTM-4 |
| CV6 | The project drill-in and its handoffs | Screen | Later, by the person's own choice | MTM-9 |
| CV7 | Settings — "Your setup" | Screen | The returning person's home | MTM-2 |
| CV8 | Admin — Review setup, Organization setup, Setup check | Phase (3 of 16 surfaces) | Org standup, do-once | MTM-7 |

**Reconciliation with the requirements package.** [`10-user-stories.md` §Critical View Coverage](../03-requirements/10-user-stories.md) names seven critical views and maps each to its stories. CV1–CV6 and CV8 are those seven. **CV7 (Settings) is added here** because it is the returning person's only whole-topology view — four copilots by four tiers, sixteen pieces of evidence, none of them ever fabricated — and because it is the second-densest concentration of the live jargon leaks recorded in §9. A surface that shows the whole promise at once is a surface where the whole promise can fail at once.

**Candidates that fail the test and are deliberately not critical views:** the Analytics governance surface (a toggle with no emitter behind it — telemetry is a ratified non-goal), the right-click menu (a habit shortcut to actions that live elsewhere), the About window, and every retired-tree surface with no Swift caller — the fleet dashboard, the MDM profile generator, the deprovision panel, the resolve view, the in-app updater, and the conflict chooser whose verb is formally deferred under ADR-008.

### 2.3 Critical View Definitions

---

**CV1 — The tray at rest: the glyph and its twelve badges**

| Attribute | Detail |
|-----------|--------|
| Screens | `NSStatusItem` at `variableLength`; the aviator template glyph at 16pt; an optional 9pt SF Symbol badge composited at the bottom-trailing corner of the button (`x = button.width − 9 − 1, y = 1`) |
| Phase | Steady state. The only surface that operates when nothing is happening |
| Primary user | Bob — the change-averse non-technical consumer |
| Why critical | **MTM-2, "the day nothing happens."** The product's whole promise is about what happens when nothing is happening. This is also the only touchpoint that can destroy the relationship in a single frame: a quiet icon over a broken machine is the **false green**, and it has already happened — through v0.2.3 a GitHub repository or a hidden mirror counted as an installed layer, so a person could see a green Personal result with no visible folder anywhere on their disk (fixed in 0.2.4, ADR-005) |
| Design imperative | Answer *"is it OK, and do I have to do anything?"* in half a second, in one plain sentence that names the failing component — and say **nothing at all** when everything is fine |
| Constraint | Silence is the success state, drawn as silence. Shape before colour. The token set is closed. No animation on the badge at all |

**How the shipped design accomplishes it.** `BadgeState.none` returns `nil` (`native/models.swift:58`) and `StatusBarController.applyBadge` returns before creating any subview (`native/control-tower-tray.swift:2600-2617`), so a healthy machine draws the bare silhouette and nothing else — there is no code path that can render a reward. The twelve tokens each map to an SF Symbol with a unique silhouette *before* they map to a system colour (`native/models.swift:40-71`), and the collision check holds: the two "!" states are a filled **triangle** and a filled **circle**, and the three transport-ish states are **two circular arrows**, a **down-arrow in a circle**, and a **box with a down-arrow**. Strip every colour and all twelve remain distinguishable. The glyph is loaded as a template image at 16pt (`AviatorGlyph.load(targetHeight: 16)`, `native/models.swift:359-395`), so macOS discards the asset's brand navy and renders the correct menu-bar foreground in light bars, dark bars, and while the item is open — and the loader deliberately has **no substitute-symbol fallback**, returning a blank template rather than letting a missing asset silently replace the product's settled identity. Status is re-derived by re-running the real pipeline on a single 300-second timer plus on launch and on every popover open (`:2536,2584-2590`); it is never remembered. The accessibility label is the current status **sentence**, never the symbol name (`:2597`). The badge does not animate — no pulse, no rotation — which is stricter than the original visual system called for, and means every state is legible frozen, in grayscale, by design rather than by fallback.

**Where it is still weak.** The `update` and `spinner` tokens are defined in the vocabulary but no shipped path selects them; `native/render-state.swift` collapses update-available and updating-app onto `ring` and flags it in its own comment as a frozen-plan decision to revisit.

---

**CV2 — The popover: six regions and one prompt lane**

| Attribute | Detail |
|-----------|--------|
| Screens | A transient `NSPopover`, fixed **360pt** wide, content-sized, on a real `NSVisualEffectView` with `material = .popover`, `blendingMode = .behindWindow` (`native/control-tower-tray.swift:1265-1280,1462-1506`). Six vertically stacked regions, each `.padding(.horizontal, 12)` and separated by a `Divider()` |
| Phase | Steady state. The day-to-day home |
| Primary user | Bob |
| Why critical | It is where routing-by-competence becomes visible, where the **one-prompt-at-a-time** rule is enforced, and where a person learns what "your copilots" actually means. It is also where an offer must never look like a fault |
| Design imperative | A region renders **only when it carries information**. A healthy machine shows Regions 1 and 2 and nothing else |
| Constraint | No "Update" button, ever — updates install themselves. No discard control in the unsaved-changes prompt. Colour never carries a state alone |

**How the shipped design accomplishes it.** Region 1 is the one honest sentence with the machine name beneath it, carrying `.accessibilityAddTraits(.updatesFrequently)` so a change announces politely without stealing focus; while a sync is in flight the sentence and the glyph swap together to `Bringing everything up to date…` and `ring`. Region 2 (`YOUR COPILOTS`) renders one row per component over a **fixed four-column grid of `LayerDot`s**, so an absent layer keeps its own slot rather than silently collapsing the row — passing draws a quiet 6pt tertiary dot and explicitly *not* the colourful `pass` mark, because that would be the green-checkmark reward the copy rules forbid (`:1308-1311`), and a layer with no checker at all draws a `circle` in `.quaternaryLabelColor` whose tooltip reads `You're not in this one` (`:1315-1358`). Layer names render in plain words — `Core setup`, `Your organization`, `Your department`, `This Mac` (`:1319-1323`). Region 3 (`AVAILABLE TO JOIN`) exists only when something is joinable and never badges the menu bar, because an offer is not a fault. Region 4 keeps two registers permanently separated: `SHARED WITH YOUR TEAM`, subtitled `Ready for you. Nothing to sign into.`, carries **no rows with controls, ever** — the absence of a sign-in affordance *is* the design — while `YOUR ACCOUNTS` carries the GitHub row with its real state. Region 5's `Sync now` disables while syncing or offline with a `.caption` reading `Waiting for the network.` beneath it. Region 6 carries **at most one prompt, then any number of notices**, and the unsaved-changes prompt has exactly one affordance and **no discard control anywhere in it** — never-destroy expressed as a missing button (`:1692-1710`).

**Where it is still weak.** The worst live jargon leak in the product sits inside Region 2: `native/control-tower-tray.swift:1375` renders each component's detail as `foundation: pass · org: warn · department: … · personal: …`, printing raw layer identifiers and the CLI's raw severity enum on the most-read region of the most-read surface — a few dozen lines *after* the ratified plain-label table in the same file. The accessibility label at `:1387` leaks the same raw severity token to VoiceOver. And `:1533-1536` renders the raw machine hostname where the copy deck specified `This Mac`.

---

**CV3 — The account of what just happened: Set up (stage 8), and Verify (stage 9)**

| Attribute | Detail |
|-----------|--------|
| Screens | Wizard stage 8, `Setting up your copilots` — one honest count line, one main row, a `What this includes` disclosure over six plain-named stages, one row per chosen project, six row states with six shapes and six sentences. Wizard stage 9, `Making sure everything's current` → `Your copilots are ready`, or the honest-incomplete screen |
| Phase | First run. **The one irreversible act, and its account** |
| Primary user | Bob (and the owner, on the live run) |
| Why critical | **MTM-1, ranked first: existential and already realised.** On 2026-07-31 the first live apply told the owner setup stopped *"before changing anything"* when two Personal GitHub repositories had already been created and seeded. What a person concludes from that is not "there is a bug" — it is *"this thing tells me what it wants me to hear,"* and there is no route back |
| Design imperative | Never claim less than it did, and never claim more. `Nothing changed` is legal **only** against an empty ledger |
| Constraint | No percentage, no countdown, no ETA. The denominator never moves mid-run. A `notStarted` row has no branch that can reach a spinner |

**How the shipped design accomplishes it.** All deterministic preflight — including the nine-state git-history classifier — runs before the first irreversible write, so a blocked row produces **zero** mutations rather than a partial set of repositories. A run-scoped completed-actions ledger threads through every exit path including the failing ones (ADR-006), the apply asserts `HEAD == target` as a postcondition, and *already at target* and *fast-forwarded* report as distinct outcomes rather than collapsing into one. A **held** item (a protective non-write) never shares fatal treatment with a **blocked** one (an active refusal). The progress line reads `N of M outcomes reported` and its own documentation states that the numerator counts terminal reports, not elapsed time and not only successes; timer-paced fake progress was removed and the defect is named in code (`native/wizard.swift:352-359`). The six row states carry six distinct shapes and six distinct sentences (`:5604-5669`), including the reconciliation state `Setup didn't say what happened here.` for any row the run never mentioned — an honest answer to a question the app cannot otherwise answer. Verify re-runs the same health pipeline against the result and **refuses to be talked into congratulating**: when the completion rule does not pass, the finish action is unreachable and the honest-incomplete screen renders instead — `SETUP ISN'T FINISHED` / `Here's where that leaves you` / `Nothing yet. Setup stopped before anything was put in place.` / `Nothing you already had was changed, moved, or removed.` There is no hedged middle wording.

**Where it is still weak.** Two jargon leaks land at the most celebratory moment in the product: the verify roster caption renders `Ready · foundation: pass · organization: pass …` (`native/wizard.swift:5868-5875`) and the progress line reads `Checking this Mac and its inherited layers…` (`:5868`) — two banned terms in five words, on a first-run screen, to a person who has just been told they do not need to be technical.

---

**CV4 — The stop that is not a failure: the Holding family, H4 in particular**

| Attribute | Detail |
|-----------|--------|
| Screens | Seven named variants (H1, H2, H3, H4, H5 with its H5b sibling, H6, H7), rendered **inline over the stage they came from**, never adding a sidebar row, never a dead end. `HoldingVariant` at `native/wizard.swift:465-510`; copy at `:694-870` |
| Phase | Reachable from wizard stages 5, 6 and 7 |
| Primary user | Bob |
| Why critical | **MTM-3**, and the most *frequent* of the three P0 moments. In the real live run's first read-only plan pass, **nine of sixteen rows classified as review** — six of the seven already-present repositories, three of them purely because of untracked scratch files. The most common real outcome of a first setup is a screen full of holds. Misread once, it ends the relationship |
| Design imperative | The variant is chosen by **who owns the fix**, never by what went wrong. Two failures with identical technical causes land on different screens when different people own them |
| Constraint | H4 is forbidden from being orange and forbidden from the words *paused, stopped, couldn't, problem, error*. A CLI string is never a headline |

**How the shipped design accomplishes it.** `HoldingVariant` carries the routing rule in its own code comment — "chosen by WHO OWNS THE FIX, never by what went wrong": H1 whoever installs software, H2 and H3 nobody (retry), H4 the person (a decision, not a fix), H5 nobody (wait), H6 the organization, H7 the person (a real fix they can complete here). Each variant carries an eyebrow tint (`:481-489`) and a `BadgeState` drawn from the closed tray vocabulary (`:500-510`), so a Holding screen and the menu-bar glyph agree on shape. **H4 is the design's whole argument:** eyebrow `ONE THING TO DECIDE`, title `Something here is already yours`, tinted `.systemBlue` and never orange, a card headed **What I left alone**, the caption **Nothing was changed, moved, or removed**, a primary action reading **Keep what I have**, and a confirmation state reading **Kept as it is**. It is a success with a question attached, and the screen says so. H6 is the only variant whose primary is not a retry, because retrying cannot change the outcome — the forward action is to leave, and it says so, since a retry button that cannot change anything teaches people that buttons are decorative. Every variant has at least two exits and one of them works offline and with a broken helper. A raw machine sentence is framed verbatim under **What setup found:** only when the CLI wrote it for a person, and otherwise goes only into a collapsed **Details for support** block addressed to whoever looks after the Mac — where any line the app does not genuinely have is **omitted rather than filled with "unknown."** Accessibility focus moves to the title when a Holding screen appears, scoped to Holding on purpose. From the second consecutive identical hold onward the screen acknowledges itself: `Still the same. Nothing changed.`

**Evidence this is the right design.** The exact string `An existing GitHub SSH alias is user-managed; setup did not replace it` reached a real screen, and H4 is the answer that was written for it.

---

**CV5 — The roster reveal: What you're getting, Departments, Your connections, Your projects**

| Attribute | Detail |
|-----------|--------|
| Screens | Wizard stages 4–7: `Here's what you're getting` · `Departments you can join` · **`Your connections`** · `Where do you keep your projects?` |
| Phase | First run, four steps, **one emotional beat** |
| Primary user | Bob |
| Why critical | **MTM-4.** This is the only moment in the entire journey that generates *desire* rather than managing anxiety. Everything else in the product is trust maintenance; this is the pull |
| Design imperative | *"I did not know I was allowed to have this."* Entitlement is rendered as a list, never negotiated as a favour |
| Constraint | No internal vocabulary reaches this surface. An unrecognized state groups as **not available**, never as ready |

**How the shipped design accomplishes it.** Stage 4's design is the deliberate absence of a choice: `Everyone on your team gets all of this. There's nothing to pick.` The three standard copilots are listed as confirmations rather than options, and the single optional checkbox — *I also use Codex* — is framed as a personal preference rather than a configuration. Stage 5 shows only departments the person is **already entitled to**, each with one of five states in words and a `Join` button on the joinable ones, so no administrative decision leaks into their screen; its empty state is an honest wait rather than an error: `No departments are available to you yet. When someone adds you to one, it'll show up here.` Stage 7 triages the person's own projects into five CLI-authored categories, and selection is by checkbox rather than immediate action, because at that point in the flow the copilots a project would copy from do not exist on the Mac yet.

**Stage 6, `Your connections`, is new in v0.4.0 and is the clearest single demonstration of invariant #1 anywhere in the product.** Before this release the step had nothing to show — an empty state where the organization's declared services should have been, at the exact moment a person is deciding whether this is worth it. The bridge renders the organization's full roster grouped into **Ready to use** and **Available to connect**, naming in plain language exactly which credentials are missing from the shared store and **never a value**; anything unverifiable is grouped under the CLI's own honest explanation. The intro states the boundary out loud: these are *"the connections Control Tower can prove are ready for you."* The whole computation is CLI-side end to end — `cc connections --json` shells `copilot --json layers` and presence-checks each service's hinted secret names against the organization's shared store — and Control Tower filters purely on the CLI-computed `secret_state` (`ready` | `needs-connect` | `no-store`). It never inspects a secret value, and an unrecognized future state groups with the no-store rows so it still gets an honest explanation rather than being silently dropped or shown as ready. A helper too old to answer at all degrades to the same empty state plus a quiet `Update to see your organization's connections.` This is the model for every borderline capability in the product: it renders something the CLI already computed and verified, and adds zero judgment of its own.

---

**CV6 — The project drill-in and its handoffs**

| Attribute | Detail |
|-----------|--------|
| Screens | The per-project detail reached from the popover's projects drill-in and from the wizard's Your projects step; five CLI-authored categories with per-category routes |
| Phase | Later, and by the person's own choice |
| Primary user | Bob, with the project's actual owner as a second actor |
| Why critical | **MTM-9.** It is the second reason to open the app, and it is the difference between a dead end and a door. *"Owner will review" without a prepared route, prompt, or verification step is not a service outcome* |
| Design imperative | Offer the safe bounded part directly with a clear statement of what will be added, preserved and left unchanged; hand the unsafe part to whoever owns it as an **actionable package**, not a suggestion |
| Constraint | Project-specific customization is a **visible positive fact**, never a blocker. Readiness is evaluated per assistant |

**How the shipped design accomplishes it.** The three-row **Will add / Will preserve / Will not change** panel precedes every project write, so preservation is stated in the interface *before* the action rather than buried in a log after it. A project that can finish automatically gets `Finish safely`, and nothing is written until it is pressed. A project needing judgment gets a CLI-generated prompt that names what to preserve, what is prohibited, the bounded allowed actions, the verification command, and the stop conditions requiring an owner decision — and `Run in Codex` / `Run in Claude Code` open a **real, visible Terminal session** at that project with it, with a `Bring Terminal forward` control while it is out there. On return the app **re-inspects both Claude and Codex itself and does not trust the external assistant's report** — which is also the product's single best accessibility hint. `Needs the project owner` offers a prepared copyable handoff and changes nothing. `Couldn't confirm` shows exactly what could not be proven, offers a read-only diagnostic session and `Check again`. Undo is offered on an automatically set-up project for exactly as long as the helper can still prove that what it added is untouched; when it cannot, **there is no control at all, never a disabled one with no explanation**, and the row's caption carries the reason. The app resolves each assistant to an absolute executable before launching, because Finder and Terminal do not share a `PATH` — a defect that shipped once and is now a rule.

---

**CV7 — Settings: "Your setup"**

| Attribute | Detail |
|-----------|--------|
| Screens | One scrolling window (min 760 × 650, ideal 820 × 760, position remembered): a header plus three cards — `Your copilots`, `Your connections`, `Your projects` |
| Phase | The returning person's home |
| Primary user | Bob, weeks or months in |
| Why critical | It is the **only surface that shows the whole promise at once**: four copilots by four tiers, sixteen pieces of evidence, none of them ever fabricated. A surface that shows the whole promise at once is a surface where the whole promise can fail at once |
| Design imperative | **Deliberately read-only.** Opening Settings never applies anything; every change routes back out to the flow that owns it |
| Constraint | The state word is **always printed** — colour is redundant with it, never a substitute for it. A layer with no evidence says `Not connected`, `Not joined` or `Could not check`, and none of those is ever rendered as ready |

**How the shipped design accomplishes it.** The header states either `Your ecosystem is ready` or `Your Copilot setup is incomplete`, and when incomplete offers `Finish Copilot Setup`, which reopens the setup window after a fresh check rather than replaying Welcome or resetting anything. The `Your copilots` card is four expandable disclosure rows, each opening onto its Foundation, Organization, Department and Personal rows with a mark, a state word, and the CLI's own plain explanation — the four-by-four grid is the load-bearing idea of the screen. The could-not-check treatment is a titled failure block with a plain reassurance — `Nothing was changed, and Control Tower will not call the ecosystem ready without that report.` — plus a `Try again` button, never a fabricated value and never a zero rendered as a fact. Loading states name what is being checked rather than drawing a skeleton that implies a shape the data may not have. `Open project aftercare…` and the per-category rows reopen the setup window directly on that category, so recovery **re-navigates rather than re-implements** and inherits the destination's honesty for free.

**Where it is still weak.** Four of the seventeen recorded jargon leaks concentrate here — `Checking every Copilot repository and layer…`, the repository-root cards including the Git-internal word *checkout*, `separate evidence-backed layers`, and `ecosystem` used cold where Admin earns the same word by teaching it first. Settings also carries the **second badge vocabulary** (see §9). And the shipped shape — one scrolling window — diverges from the visual system of record's six-tab Settings scene; the shipped shape is simpler and matches the person's actual mental model, so the record is the stale side, but it is an unreconciled divergence rather than a decision.

---

**CV8 — Admin: Review setup, Organization setup, Setup check**

| Attribute | Detail |
|-----------|--------|
| Screens | Three of the Admin app's sixteen surfaces: `Review setup` (the plan, before anything is created), `Organization setup` (the run), `Setup check` (the read-only read-back) |
| Phase | Org standup, do-once, plus governance afterwards |
| Primary user | Earl — the IT / admin operator |
| Why critical | **MTM-7.** Earl's whole credibility lives in two screens: what he authorized, and what he can hand over. It is also **the largest untested assumption in the product** — Admin has stood up a real sixteen-layer organization end to end, run by the person who wrote it, on his own organization. No third-party operator has ever touched it |
| Design imperative | Before anything is created he can see exactly what will be reused, created, downloaded, initialized, connected, synchronized and verified — **by name and by destination**. Afterwards, what he hands over is a report, not a recollection |
| Constraint | Every existence and idempotency decision is made by a deterministic engine using check-then-act — GET before every POST, PATCH or PUT — **never by a model and never by the UI**. No fleet dashboard, no MDM surface, no health gauge |

**How the shipped design accomplishes it.** The run is a named list of real things filling in place — the same rows, in the same order, with the same names he just read on the review screen, so he is watching the list he approved. There is a count only while the run is alive, a bar only above seven rows and only as the visual twin of that count, and **no percentage anywhere**. The seven run-row states carry seven distinct shapes, and `refused` having its own shape is load-bearing: *"setup stopped here on purpose, nothing after this was changed"* is a different fact from *"this failed,"* and the visual system refuses to blur them. When a run goes silent it says `No answer yet.`, **stops animating entirely**, and offers `Keep waiting` and `See what's really on GitHub` — because the truth path is a read-only check, never a guess, and a dead run must never look like a slow one. The preflight header shows a plain count (`2 must be fixed, 1 could not be checked`), never a score, and an owner chip attributes every row to whoever actually owns fixing it. The register is a **teaching** register rather than an engineering one: Orientation explains the inheritance model in one paragraph of plain English before asking for anything, and the whole surface substitutes **"spaces"** for repositories — the single clearest piece of linguistic discipline in the product, and the one the User face has not yet inherited.

---

## 3. Creative Direction — as realized

### 3.1 Philosophy

**Named direction of record: "Quiet Instrument," in the two-app family "Native Calm."**

Quiet Instrument is the visual character of a first-party Apple system utility that lives in the menu bar and speaks like an air-traffic-control panel: monochrome and silent by default, precise when it has something to say, never decorative. Depth comes from real macOS materials — menu-bar vibrancy, sidebar material, popover blur — and from honest hierarchy, never from drop shadows or fields of colour. The single sentence the whole aesthetic serves is **silence you can trust**: the brightest, most saturated thing on screen is only ever the one thing that is actually wrong, and when nothing is wrong there is nothing to see. This is not minimalism as a style preference. It is the visual expression of the core promise, which is that a non-technical person can trust the icon without interpreting it.

**Native Calm** is the family. Its sibling register is **"Setup Assistant Calm"** — the do-once, windowed assistant character established by `Publisher Setup.app` and reused verbatim by Control Tower's wizard, Settings and Admin windows: the same `NavigationSplitView` roadmap sidebar, the same card, field and button patterns, the same type scale, the same motion. Quiet Instrument is what Control Tower adds on top for its always-on face. A person who set up a publisher machine and then opens Control Tower should feel the same hand made both.

**Two reference points, and how they apply.** The first is **macOS's own menu-bar extras** — Wi-Fi, Battery, Time Machine: a monochrome template glyph at roughly 16pt that changes *shape* rather than colour to say something, and says nothing most of the time. That is not an influence; it is the model, taken whole. The second is **an air-traffic-control panel**, the governing metaphor from `SOUL.md` §2: the brightest mark on the panel is always the truest problem. What is deliberately *not* taken from it is the density — a real ATC panel shows everything at once, and this product shows only what is currently true and structurally omits the rest.

**The mode is Controlled, against the platform, not Innovative against a blank page.** The substrate *is* the design system: `NSColor` semantic colours, `NSVisualEffectView` materials, SF Pro through SwiftUI's semantic `Font` styles, SF Symbols, unmodified native control styles. The code proves the commitment rather than asserting it — across all nine files in `native/` there are **zero `.shadow(` calls, zero `repeatForever` animations, zero `.tint(` or `.accentColor(` overrides, zero `preferredColorScheme` overrides, and exactly one literal hex colour anywhere** (`#2D294E`, and it appears only inside a documentation comment). Every button uses one of the four native styles. Light appearance, dark appearance, Increase Contrast and the user's chosen accent colour are all handled by the system because nothing overrides them. The craft is not in inventing a look; it is in restraint, hierarchy, honest status, and the refusal to draw anything that is not true.

**The five commitments, and the concrete move each one made:**

| Commitment | The shipped move |
|---|---|
| Shape encodes state; colour is only ever the second channel | Twelve badge tokens, twelve unique silhouettes, then a system colour. Strip all colour and all twelve remain distinguishable by shape plus their status word |
| Silence is the success state, drawn as silence | `BadgeState.none` returns `nil`; the tray draws no badge, no pip, no green, no checkmark; the popover's glyph view draws an empty `ZStack` |
| Native, not branded-native | System semantic colours only; a real popover material; `.listStyle(.sidebar)` for both roadmap sidebars; unmodified controls. It should look like it shipped with macOS, which is a trust signal for an always-on background agent in a way a distinctive brand skin actively is not |
| Holding states get more design attention than the happy path | Six setup-row shapes, seven Admin run-row shapes, a Holding family with its own eyebrow tints. The happy path is a plain row with a quiet dot |
| No fabricated progress, ever | The one continuous motion in the product is an indeterminate spinner that **carries the name of what it is waiting on** and no position. No percentage, no ETA, no countdown, no progress bar anywhere |

**The mark, and the ratified brand rule.** The Control Tower illustration is the **logo** — the app icon and the wizard welcome hero, rendered full-colour and never tinted. The aviator sunglasses glyph is the **menu-bar mark, always**, loaded as a template image so the system discards its brand navy and renders the correct foreground. **The two marks never trade places**, and both call sites that could draw a brand image in a window carry the owner directive in code: the popover header draws none, and the wizard roadmap sidebar draws none, because at menu-bar scale the full-colour illustration collapses into an unreadable coloured blob. Brand navy `#2D294E` is **not a UI colour** — it survives only as a fill inside one SVG, thrown away at runtime by the template flag. There is no navy bar, no navy banner, no navy card, no navy button. Primary actions use `.controlAccentColor`, the *user's* accent, never the brand colour.

**The chromatic vocabulary is five colours and there is no sixth.** Counted across `native/`: `.systemRed` 35 uses, `.systemGreen` 28, `.controlAccentColor` 21, `.systemOrange` 13, `.systemBlue` 8. Green means verified-and-current at row level only — never the tray, never a fill, never a banner. Neutral gray **dominates the ramp by design**, because most non-healthy states are not emergencies: they are invitations, or somebody else's job, or transient. Blue means *there is a thing here you personally can do*. Orange is the single amber and is deliberately also the colour of *unknown*, so an unverified check can never be mistaken for a pass. Red is the honest hard failure and the honest hard refusal — in the tray it is unique to `bang`, *"I won't guess."*

### 3.2 The Quality Bar

**Done means an enterprise security team can audit the always-on agent and accept it as safer than a human running `copilot update` by hand — and a non-technical person never once had to be technical.** "Working" is a running tray; "done" is a trustworthy one.

**The taste test, as the owner states it:** *if the tray has to explain itself, it failed.* A glance answers "is it OK, and do I have to do anything?" in half a second, in one plain sentence that names the failing component — no jargon, no blended verdict, no reassurance it cannot back. When everything is fine, it is silent. **Silence you can trust is the whole aesthetic.**

The four failure modes that define the bar by their absence: a **false green** (the icon quiet over a drifted machine), an **unbacked claim** (a screen stating what happened with no ledger, postcondition or re-run behind it), a **blended status** ("needs attention" that never says *which*), and a **jargon leak** (an internal token reaching a person's screen or their screen reader — which is live right now, and is exactly what an unenforced rule looks like after seven releases).

### 3.3 Anti-Examples

**Named anti-direction: "The Alert Machine."** The health-score dashboard that mistakes activity for information. Its visual signature is precise: a gauge or ring or score that aggregates truth into a number, a badge that exists so the person can clear it, a coloured banner that celebrates, a notification for every event regardless of whether the reader can act on it. Its close cousin is **The Second Pilot** — the app computing a verdict it has no right to compute — whose visual tell is any surface rendering a state the CLI did not report.

Why this specific anti-direction and not a generic "avoid clutter": **every alert a non-technical person cannot act on burns down the credibility of the one that matters.** A dashboard that is always slightly amber trains people to ignore amber. A green checkmark on a layer that was never actually verified is not a flourish, it is a false claim. The visual language has to make the honest state **easier to draw** than the flattering one.

| Rejected on sight | Why it betrays this product |
|---|---|
| Health scores, rings, gauges, sparklines, percentages | They aggregate away the one fact the person needs. The Admin preflight header shows a plain count, never a score |
| A green checkmark or celebratory state for "everything is fine" | Healthy is drawn as the *absence* of a mark. Silence is the reward |
| Any state rendered green that was not actually verified | An entitled-but-not-synced layer is a neutral hollow ring, never green and never an alarm. An unknown check is orange with the words "Not checked" — never green |
| ETAs, countdowns, percentage bars, fabricated phase pacing | The prior implementation paced fake phases with `Task.sleep` *after* the real call had already returned. That defect is named in code and the replacement is a named-subject indeterminate spinner |
| A purple or indigo-to-pink gradient, glow, or "AI shimmer" | The AI-slop signature. It performs an intelligence the app deliberately does not have — it is the tower, not the pilot. Also structurally impossible here: no gradient exists in the codebase |
| A filled navy or purple header bar, coloured popover header, navy card | Owner-sourced hard constraint. The brand colour exists only as a template tint the system immediately discards |
| Drop shadows used as decoration | Zero `.shadow(` calls exist. Every shadow in the product is drawn by the system because the thing casting it is a real popover, panel or sheet. Depth is material and layering, not paint |
| Raw technical strings on a user surface | No YAML, no git conflict markers, no serde errors, no stage identifiers, no SF Symbol names in VoiceOver labels |
| A chat box in the menu bar | The Copilot of the Copilot. A model-driven surface contradicts parse-never-compute by definition |
| Em-dashes in user-facing copy | A standing copy constraint carried through the whole design record |

### 3.4 Tone and Texture

| Quality | What It Means in Practice |
|---------|--------------------------|
| **A witness under oath** | It reports what it saw, states plainly what it could not see, and never fills the gap: `"I can't read the setup right now, so I won't guess."` |
| **Cause, then consequence, joined by "so"** | The signature connective. The reason first, the safe action second: `"Your setup is already being updated by something else, so I stepped back rather than get in the way."` |
| **Every limit paired with a preservation guarantee** | `"Nothing was changed, moved, or removed."` Never-destroy is not only an architectural property; it is a **sentence pattern** |
| **First person for its own acts, second person for the person's things** | `"I found something that belongs to you, so I left it alone."` The subject of a failure sentence is the app, never the user |
| **Names the specific copilot, never a blur** | `"Codex Copilot needs you to sign in. Everything else is fine."` A blended verdict is a design failure |
| **Understated to the point of near-silence** | The strongest celebratory word in the entire product is **"Ready."** Zero emoji, zero exclamation marks on success, no confetti, no "Congratulations" |
| **Names a role, not an org chart** | `"whoever looks after your Mac"` works for a five-person company and a five-thousand-person one |
| **Warm at the courtesy stop, never alarmed** | H4 is blue, never orange, and never uses the words *paused, stopped, problem, error* |
| **The one sanctioned emotional peak** | `"You have the tools. Now go change the world!"` — the owner's own words, on the Done screen, and nowhere else |

---

## 4. Design System Basis

### 4.1 Foundation

**The design system is macOS itself.** There is no bespoke token layer, no custom hex ramp, no restyled button, no restyled focus ring. Tokens in this product are **roles mapped onto system values**: `content.primary` → `.labelColor`, `surface.card` → `.controlBackgroundColor`, `accent` → `.controlAccentColor`, and so on. That is what makes light mode, dark mode, Increase Contrast and the user's accent free rather than a maintenance burden, and it is what will keep contrast holding through OS revisions.

**The reference product to study is `Publisher Setup.app`**, the sibling in this ecosystem. Its tokens, roadmap-sidebar grammar, card patterns, type scale and motion are reused wholesale so the two apps read as one design team's work. Control Tower extends the family with the menu-bar instrument register that Publisher Setup does not have.

**What the product authors itself, and only this:** the twelve-token badge vocabulary, the aviator template glyph, the card grammar's specific radii (10 for the standard card, 12 for the largest Settings container, 6–8 for chips and nested blocks, all `.continuous`), the nested-card opacity ladder that signals recession by reducing fill opacity rather than stacking shadows, and the one authored fill in the product — the current roadmap pill at `.controlAccentColor` 12% opacity, which is 12% precisely so it reads as a highlight and not as selected-row chrome.

### 4.2 Component Rules

```
[Design need arises]
      |
      v
[Does a native macOS control or an existing family pattern cover it?]
  YES: Use it unmodified. Do not restyle rounding, focus rings, or control heights
  NO:  Does it need a NEW STATE, or only a new arrangement?
         NEW ARRANGEMENT: compose from the card / row / disclosure grammar already in use
         NEW STATE:       it must be added to the relevant CLOSED vocabulary,
                          at that vocabulary's own definition site — never improvised at a call site
              |
              v
       [Owner approves the vocabulary addition, and the shape-in-grayscale
        collision check is re-run before it ships]
```

**The closed-vocabulary rule is the load-bearing one.** The product deliberately uses several small, closed, exhaustive state sets rather than one large severity scale — twelve badge tokens, ten helper statuses, six unreadable reasons, seven Holding variants, six setup-row states, seven Admin run-row states, five project categories, five Settings tier states, three join-row states. Each is total over its own domain, which is what stops a screen from ever having an undefined state. A new state cannot be invented where it is drawn; it has to be added to the set. **That is what keeps the menu bar honest.**

---

## 5. Concept Competition Rules — retrofitted

### 5.1 What happened to the original mandate

The template's mandate — five distinct visual concepts per critical view, produced before anything is built — is **spent**. It was never executed as written (gap G-3): the app was hand-built in native Swift against the three-document design of record, and the earlier version of this brief specified deliverables (a Figma file, a Storybook library, an MDM-profile generator, a silent managed install lane) that were explicitly rejected rather than produced. Recording that plainly is the point of this rebuild.

**What carries forward is the discipline, re-scoped to change.** A single concept is a dictation, not a design — and that is exactly as true for a change to a shipped surface as it was for a blank one.

### 5.2 The rule that now applies

Any proposed change to a critical view must arrive as **at least three genuinely distinct alternatives, one of which is always "change nothing, and state why the current design is still right."** The do-nothing option is mandatory because in this product the burden of proof runs the other way: the surfaces above were shaped by real incidents, and the default answer to a proposed change is no.

A concept is distinct from another if it differs in **at least two** of: information hierarchy (what is shown first, what is hidden, what is never shown), interaction model (drill-in vs. always-visible vs. progressive disclosure), routing (who the surface is addressed to and who owns the fix), state vocabulary (which closed set it draws from and whether it needs a new member), or exit design (how a person leaves, and whether the exit works offline and with a broken helper). "We changed the colour" is not a concept. "We re-routed this screen to a different actor" is.

**Colour expression and motion philosophy are deliberately removed as distinctness dimensions.** They are settled by the platform and by the anti-direction: five system accents, shape before colour, no looping motion. A concept that differentiates itself on colour or motion has differentiated itself on the two axes this product has already closed.

### 5.3 Philosophy Descriptor Naming

Every alternative is named before it is shown, with a short descriptor that communicates its relationship to the person and to information — so a decision can be argued verbally without pointing at screenshots. **The existing direction's name is "Quiet Instrument," and the rejected one is "The Alert Machine."** Those two names have already done more work in this product than any screenshot, which is the argument for the rule.

Valid: "Quiet Instrument," "Setup Assistant Calm," "Structured Clarity," "Ambient Confidence." Invalid: "Concept A," "Blue version," "Modern," "Clean."

### 5.4 Fidelity

Because the product ships, the honest fidelity target for a proposed change is **whichever is cheaper to falsify**: a written state table plus copy, or a build. A concept that cannot state its full state table — including its unknown, offline, and could-not-check states — is not ready to be shown, no matter how it looks. In this product the states nobody wants to draw *are* the design.

---

## 6. Constraints and Guardrails

### 6.1 The six invariants (from `CLAUDE.md`)

These are the spine. They are not design preferences and they are not tradeable.

| # | Invariant | Design implication |
|---|---|---|
| 1 | **Parse, never compute** | No surface may render a state the CLI did not report. If a view needs a verdict, the verdict is a CLI field, not an app calculation. The v0.4.0 connections roster is the model |
| 2 | **Single process** | One signed binary is tray, supervisor and scheduler. No daemon, no in-app fallback loop. `launchd` is a crash-only watchdog and `KeepAlive` is never `true` |
| 3 | **Never-destroy** | Every visible working tree is human-owned. Preservation is stated in the interface *before* an action, not logged after it. The missing discard button in the popover prompt is this invariant made visual |
| 4 | **Security posture is inherited and enforced, never weakened** | No `--force`, no `--skip-verify`, no "make it healthy anyway." No surface may exist whose purpose is to lower the bar. Trust roots are compiled-in code, not configuration |
| 5 | **Route by actor-competence × reversibility, not by event-class** | The Holding family's variant selection *is* this invariant, rendered |
| 6 | **One-way inheritance; secrets never travel in it** | No surface renders a secret value at any time. Sync is pull-only and downward; any upward publication is separate and human-invoked |

### 6.2 The SOUL v2.0 gates

`SOUL.md` §5 is the decision instrument, and its **six gates run in order** on any proposed change. A change must pass **all six**. They are ordered cheapest-to-evaluate first, so most bad ideas die in the first two.

| Gate | The question | Failure verdict |
|---|---|---|
| **1 — Compute** | Does this require the app to compute ecosystem state: resolve, score, verify, merge, prune, or wipe? | Yes → it belongs in the CLI. **Stop** |
| **2 — Proof** | At the moment this makes a claim, what evidence backs it — and what does it say when that evidence is missing? | Assumes, defaults optimistically, estimates, or celebrates a state it cannot re-prove → **redesign or reject** |
| **3 — Spine** | Does this serve a non-technical person getting and keeping a technical person's superpowers, without technical skill, without their attention, and without their personal work being touched? | Merely useful → **useful is not essential. Drop it** |
| **4 — Plain-Words** | Could someone who does not know what a layer, a rank, a manifest or a repository is read this and act correctly, unaided? | No → **rewrite it or cut it.** Applies to every string, tooltip and accessibility label |
| **5 — Right-Actor** | Is every prompt routed to the sole competent actor for a reversible-or-owned decision, and does it keep the person's interrupt count near zero? | No → **redesign the routing or reject** |
| **6 — Anti-Pattern** | Does this drift toward any of the ten named anti-patterns, or add audit surface the essential job survives without? | Yes → **reject, or redesign until it doesn't** |

**Priority order when principles conflict — settled, do not relitigate:** Say-only-what-you-can-prove **>** Parse-never-compute **>** Plain-words-or-nothing **>** Route-by-competence × reversibility **>** As-little-app. Above all five sits the inviolable, non-tradeable constraint **security-posture-never-weakened**.

The order is not theoretical. On 2026-07-31 the app faithfully rendered a CLI claim that was false: parse-never-compute was satisfied and the person was still lied to. When faithful rendering would carry an unproven claim, the answer is never for the app to compute a correction — it is to **refuse to render the claim as a claim**, and fix the proof upstream.

### 6.3 Platform, distribution and technology

- **macOS-only, and Windows is formally out of scope** — not deferred. The shipping app is native SwiftUI/AppKit, which is macOS-specific by construction. The Windows work that exists lives entirely inside the retired Rust tree and has never once been run on Windows.
- **One signed binary per face.** Roughly 22,650 lines of Swift compiled by `swiftc` from an **explicit source list, never a glob**, so a file cannot silently join a build. The User build is structurally unable to reach Admin: the entry point lives inside a compile-time guard and the User build's source list excludes the Admin files. Hiding is not sufficient when the exposure itself is the harm.
- **Developer ID distribution, not the Mac App Store.** The sandbox forbids spawning the CLI the whole product exists to render.
- **The CLI is invoked by absolute, translocation-safe path**, resolved from the bundle first and never from `$PATH`.
- **Control Tower renders but never computes.** The versioned JSON contract is the entire safety boundary: the schema gate decodes only `schema_version` before trusting any other field, requires an **exact major match per verb** (`onboard` requires major 2; every other verb major 1), and **fails closed** on a missing security field. The compatibility pin ships in every release directory, and at v0.4.0 it is unchanged — `cc 2.2.0` falls inside the existing `2.0.0 – <3.0.0` window, schema `1.0 – 2.0`.
- **Userland only.** Per-user everything, no admin rights, no privileged helper, no writable shared state. arm64 only today.
- **One person builds, signs and releases this.** "As little app as possible" is a survival principle here, not an aesthetic.

### 6.4 Accessibility

**Target: WCAG 2.1 AA, expressed through the macOS accessibility APIs** — VoiceOver, Full Keyboard Access, Reduce Motion, Reduce Transparency, Increase Contrast and Dynamic Type, not ARIA.

| Requirement | Applies to | How it holds today |
|---|---|---|
| Status never carried by colour alone | Every CV | Twelve tray silhouettes, six setup-row shapes, seven Admin run-row shapes, and every row additionally **prints its status word** |
| Contrast | Every CV | Inherited, not tuned: every text colour is a system semantic label on a system background or material, so AA holds in light, dark and Increase Contrast automatically. **No measured audit exists** — see §9 |
| Keyboard navigability | All windowed CVs | Every control is a standard system control, so Tab traversal, arrow-key list navigation and the system focus ring are inherited. The primary action on every step is the default action, so Return advances. Tab order is the framework default and has never been explicitly walked — see §9 |
| Focus indicators | Every CV | System focus rings, never restyled |
| VoiceOver labels name states, never symbols | Every CV | Roughly 163 explicit accessibility annotations; decorative marks are `.accessibilityHidden(true)` so a shape is never read twice. **Two labels still fall back to a raw enum value** — see §9 |
| Reduce Motion | CV3, CV5 | Branched explicitly on the wizard step transition, which becomes a short cross-fade. The tray badge does not animate at all, which is stricter than the spec |
| Dynamic Type | Every CV | Semantic `Font` styles only, with `.fixedSize(horizontal: false, vertical: true)` on every sentence that must survive the largest sizes. Text wraps; the one honest line never truncates |
| Disabled controls state their reason | Every CV | The reason renders as **visible caption text as well as help text**, on the explicit rule that a hint you can only find by hovering is not a hint |

**The accessibility requirement that outranks every API detail:** the person this app is built for is, by design, not technical. A screen that requires someone to know what a manifest is has failed them just as completely as an unlabelled button fails a VoiceOver user. The two requirements point the same direction, which is why one set of rules serves both.

---

## 7. Evaluation Criteria — how to judge a proposed change

### 7.1 The Primary Standard

**Would this change make it easier or harder for the product to say something it cannot prove?**

That is the whole standard, and it is deliberately not a standard about beauty. Everything else in this product is negotiable in some direction; the honesty floor is not. Bob is detail-oriented and change-averse, so one false green loses him permanently — and an always-on agent that can lie about state is worse than no agent, because it converts an honest unknown into a confident error.

The corollary, which is where most well-meaning changes die: **an added honest state is worth its surface.** As-little-app is the constant background pressure and the tie-breaker, but it never overrides honesty. A false green is the one outcome worse than more UI.

### 7.2 The gate ladder

A proposed change to any critical view runs this ladder **in order**, and it stops at the first failure.

1. **The six SOUL gates (§6.2), in order.** Cheapest first. Most changes that should not happen die at Gate 1 or Gate 2.
2. **The moment test for the specific view (§7.3).** Does the change make that view better or worse at the one thing that view exists to do?
3. **The closed-vocabulary check.** Does it need a new state? If so, is it being added at the vocabulary's definition site rather than improvised at a call site, and does the grayscale collision check still hold?
4. **The exit check.** Does every path out of the changed surface still work **offline and with a broken helper**? Every Holding variant has two exits and one of them must survive both conditions.
5. **The full state table.** Can the change state its unknown, offline, and could-not-check states? If those are unwritten, the change is not ready to be shown.
6. **The invariant check (§6.1).** Which of the six does it touch, and does it survive contact.

### 7.3 The moment test, per view

Each critical view exists to carry one moment. This is the question you ask of a change to that view — and it is the question today's design already answers.

| CV | Moment | The question a change must answer better than today's design does |
|---|---|---|
| **CV1** Tray at rest | MTM-2 | Does a glance still answer *"is it OK, and do I have to do anything?"* in half a second — and is silence still the only success state, with no path that can fabricate one? |
| **CV2** Popover | MTM-2 / MTM-6 | Does a region still render **only** when it carries information, is the interrupt count still trending toward zero, and is every offer still visibly an offer rather than a fault? |
| **CV3** Set up / Verify | MTM-1 | Can the screen still be checked against the ledger line by line — and is `Nothing changed` still legal **only** against an empty one? |
| **CV4** Holding | MTM-3 | Can a person tell in two seconds, unaided, whether something is **wrong** or whether something **of theirs was recognised and left alone**? Is the variant still chosen by who owns the fix rather than by what went wrong? |
| **CV5** Roster reveal | MTM-4 | Does it still produce *"I did not know I was allowed to have this"* rather than *"here is what you must not break"* — and does an unrecognized state still group as **not available**, never as ready? |
| **CV6** Project drill-in | MTM-9 | Is the safe part still bounded and stated before it happens, and does the unsafe part still leave as an **actionable package** rather than as "the owner will review"? |
| **CV7** Settings | MTM-2 | Are all sixteen pieces of evidence still un-fabricated, with the state word always printed — and is the window still **read-only**, changing nothing by being opened? |
| **CV8** Admin | MTM-7 | Can the operator still **defend the plan he authorized**, and is what he hands over still a report rather than a recollection? |

### 7.4 Instant rejections

No discussion required. Each of these is a named anti-pattern, a ratified non-goal, or a line in the sand.

- A **computed** anything: a health score, an offline verdict, an inline signature check, a resolution, an aggregate number that implies the app judged something.
- A **celebratory state** for healthy — fill, checkmark, confetti, toast. Healthy is the absence of a mark.
- A **percentage, countdown, or time estimate** anywhere. Name the phase.
- **Colour as the only carrier** of a state, or a new badge that shares a silhouette with an existing one.
- A **raw internal token** in any string, tooltip or accessibility label: layer id, severity raw value, rank, manifest field, stage identifier, exit code.
- **Raw Git or VCS output** shown to a non-technical person, or an instruction to resolve something in Git without the delegation fork every handoff sheet already offers.
- A **bypass**: `--force`, `--skip-verify`, "make it healthy anyway," a power-user mode, `KeepAlive=true`.
- **Security-sensitive configuration read from user preferences** — an update feed, a mirror, a trust setting.
- A **chat surface** or any model-driven judgment inside the app.
- An **unactionable interrupt**: notifying someone about a prune, a policy denial, or a held major they cannot action — or letting them approve one to clear a badge.
- Anything that makes a **personal → shared** crossing possible by discipline rather than impossible by construction.
- A **paid tier, hosted service, enterprise SKU, or closed component**. Openness *is* the security guarantee.
- **MDM in any capacity**, a fleet view, a telemetry emitter, or a Windows surface.

### 7.5 What matters most

**Information architecture and honesty first; interaction quality second; visual quality third.** That ordering is unusual and it is deliberate. The visual layer is inherited from the platform and is therefore *already* good and *already* accessible — the risk there is close to zero. The risk lives entirely in what a surface claims, who it is addressed to, and which states it forgot to draw. A beautiful screen that renders an unprovable claim is a worse outcome for this product than a plain one that says *"I can't read this, so I won't guess."*

### 7.6 Decision outcomes

| Outcome | What it means | Next step |
|---------|--------------|-----------|
| **Change approved** | Passes all six gates, improves its view's moment, and its full state table is written | Implement; add its state to the relevant closed vocabulary if needed; record the decision here or in the design triad |
| **Change narrowed** | The intent is right, the shape is wrong — usually the routing, or the missing states | Produce a second round with the do-nothing option restated |
| **Change rejected** | Fails a gate, or the do-nothing option is simply better | Record the rejection **and the gate it failed**, so the same idea does not return unexamined. Case law is how this product stays small |

---

## 8. The realized output

### 8.1 Actual format

**Selected: a design specification, hand-built directly into native Swift.** Not Figma, not Storybook, not a Next.js prototype.

**Why this is the honest record.** The design of record is four documents — the [experience architecture](../../03-design/control-tower-native-experience-architecture.md) (structure, IA, complete state inventory), the [interaction spec](../../03-design/control-tower-interaction-spec.md), the [visual system](../../03-design/control-tower-visual-system.md), and the [copy deck](../../03-design/control-tower-copy-deck.md) — and the artifact is the shipping app itself. For a macOS menu-bar utility built in Controlled Mode against the platform, this is the correct format rather than a compromise: a Figma frame cannot express a template image inverting with the menu bar, a real popover material under Reduce Transparency, or a badge that must remain legible in grayscale at 9pt. Those are the properties that carry this product's promise, and they are only checkable in the running app.

The trade this format makes is real and is named in §9: **there is no captured visual proof** of light versus dark at the largest Dynamic Type sizes, and no measured contrast audit. A Figma or Storybook artifact would have made those cheap. They are open items, not a reason to retro-fit a format the product did not use.

### 8.2 Design Complete Checkpoint — retrospective

The original checkpoint gated a prototype that has already shipped. Recorded here as a retrospective, honestly:

- [x] The critical view list is confirmed and traceable — CV1–CV6 and CV8 match [`10-user-stories.md` §Critical View Coverage](../03-requirements/10-user-stories.md); CV7 is added and its rationale stated.
- [x] The creative direction is accurate — **Quiet Instrument** in the **Native Calm** family, anti-direction **The Alert Machine**, every claim traced to shipped code or to the visual system of record.
- [x] The evaluation criteria are stated and tied to the SOUL v2.0 Feature Filter and to the moments that matter.
- [x] The output format is recorded as what it actually was, with gap G-3 named rather than hidden.
- [ ] **The primary persona has never touched the product.** No non-technical person has completed the journey unaided. Everything designed for Bob is high-quality design against an **unvalidated model**. This box cannot be ticked by a document.

---

## 9. What remains — named open items

Every item below is real, open, and **deliberately not fixed in this pass**. They are recorded because a brief that claimed a bar the product does not meet would itself be the Comfortable Lie. None of them is a task list with an order beyond the two the owner has already sequenced.

**Sequenced by the owner, in this order because the second is irreversible:**

1. **The V-5 cold-laptop proof.** A second machine, starting with an empty keychain, must onboard, clone both mirrors, and resolve every service with **no hand-copied secret and no `.env`**. Until it passes, "a new machine can join unaided" is a design intent, not a demonstrated fact. It is the single most informative outstanding test in the product.
2. **The publicize step.** Scrubbing and publicizing the two private foundation repositories. Deliberately last: it is irreversible, high blast radius, and gated on the credential rotation the recorded history exposure requires. Not to be attempted out of order.

**Named gaps in enforcement:**

3. **G-1 — the invariants are stated but not enforced.** All **forty `fitness_*.rs` tests scan `src-tauri/src/**`**, the retired Rust tree; they cannot see a single line of the shipping Swift, and the CI job that runs them is disabled behind `vars.RELEASE_CI_ENABLED`. The consequence for this brief specifically: **ten of fifty-three acceptance criteria have automated verification that gates every release, eighteen have a harness that runs on demand without gating a release, one rests on live-run evidence, and twenty-four rest on code review and manual inspection alone.** Zero are verified by the fitness suite. The six invariants are architectural commitments upheld by design, review and the shell release gates — **not** automatically-enforced properties of the shipping binary. Porting the suite to scan `native/*.swift` and re-enabling the job is the open item.
4. **G-2 — invariant #2's watchdog is not implemented.** The crash-only `launchd` watchdog (`KeepAlive={SuccessfulExit:false}`) exists only in the retired Rust tree. The packaging assets and a fitness test for the plist exist; the shipping Swift app does not install or manage it. The invariant stands as the design position; the absence is the current state.
5. **G-3 — Phase 6 never happened as written.** Recorded in §0 and §8.1. The tracker at [`TODO-DESIGN-PACKAGE.md`](../TODO-DESIGN-PACKAGE.md) still points a resumer at a Figma/Storybook/Next.js prototype phase that did not occur; Phase 6's real output is the shipping native app plus the design triad.

**Live defects on critical views:**

6. **The jargon leak at `native/control-tower-tray.swift:1375`.** Each component's detail line in the popover's `YOUR COPILOTS` region renders `foundation: pass · org: warn · department: … · personal: …` — raw layer identifiers plus the CLI's raw severity enum — on the most-read region of the most-read surface, and it does so a few dozen lines *after* the ratified plain-label table in the same file. The accessibility label at `:1387` leaks the same raw token to VoiceOver, so a screen-reader user hears *"Claude Copilot, warn."* This is a **live violation of the product's own essence**, and it is the concrete evidence for what G-1 costs: a rule with no gate, after seven releases. Sixteen further leaks are catalogued with file and line, each with a recommended replacement, in [`70-copy-voice.md`](../04-experience-design/70-copy-voice.md).
7. **The unbundled logo forces an SF Symbol fallback.** `ControlTowerGlyph` resolves `assets/brand/control-tower-logo.svg` **relative to the working directory only** — it has no `Bundle.main` lookup, unlike `AviatorGlyph` — and `scripts/build-user.command` copies only `aviator-glyph.svg` into `Contents/Resources`. In a shipped `.app` the loader therefore reaches its last-resort **`building.2`** SF Symbol, so the wizard welcome hero in CV5's opening beat may be a generic building glyph rather than the product's own logo. This is a real gap between the ratified brand rule and the packaged artifact. <!-- TODO: confirm on a running 0.4.0 install whether the welcome hero draws the illustration or the building.2 fallback -->
8. **Two divergent badge vocabularies.** The tray and popover share the closed twelve-token set; **Settings maintains its own five-value set** (`UserSettingsTierKind`: ready / needsSetup / needsAttention / notJoined / couldNotCheck) with its own symbols. They agree in spirit and never contradict each other, but they are two separately maintained vocabularies — and they already diverge on colour: `needsSetup` is `.systemBlue` in Settings and `.secondaryLabelColor` in the tray for the same `wrench.adjustable` symbol. The Settings reading is arguably correct, because in Settings the person *is* being invited to act and that is exactly what blue means in this ramp — which is precisely why it should be a deliberate decision rather than an accident. Open question: unify the two, or document the split as intentional on the grounds that a roomier surface can carry a fuller vocabulary.
9. **No rollback instruction shipped in v0.4.0.** Every release from 0.2.1 through 0.3.2 carries an explicit `### Rollback` paragraph naming the prior signed DMG under the immutable-tag rule. **The 0.4.0 changelog entry has no Rollback section.** Anxiety #1 — *"what if it breaks and I can't get back?"* — is answered by a standing practice, and this is the first release in the series that does not answer it in writing.
10. **No contrast audit exists.** The app uses system semantic colours throughout, which follow Apple's own contrast behaviour and respond to Increase Contrast, so AA is correct by construction. But **no measured 4.5:1 audit of the actual rendered pairs is recorded anywhere in the repository** — in particular small `.caption` and `.caption2` text over the translucent popover material. Related and equally uncaptured: no light-versus-dark visual proof at the largest Dynamic Type sizes, and no explicit keyboard-only pass confirming Tab order, which is the framework default rather than a designed order and is least obvious in the popover once Region 6 carries a prompt.

**Standing honesty about validation, restated because it bounds everything above:**

11. **No non-technical person has completed the journey.** No second writer has authored. Admin has been run **once, by the person who wrote it, on his own organization**. Every claim about Bob and every claim about Earl in this brief is high-quality design against a model that has not yet been tested by the people it was designed for.

---

## 10. Reference Documents

| Document | Purpose |
|----------|---------|
| [`SOUL.md`](../../../SOUL.md) | **RATIFIED v2.0.** The decision instrument: the essence, five principles, ten anti-patterns, the six-gate Feature Filter, the quality bar and its stated gaps. Governs this brief |
| [`CLAUDE.md`](../../../CLAUDE.md) | The six invariants — the product's spine |
| [`00-overview/00-vision.md`](../00-overview/00-vision.md) | Product vision, forces map, AI philosophy, capabilities, regression triggers |
| [`00-overview/10-scope-and-non-goals.md`](../00-overview/10-scope-and-non-goals.md) | Scope boundaries, non-goals with rationale, anti-features, integration boundaries |
| [`00-overview/20-success-metrics.md`](../00-overview/20-success-metrics.md) | Outcome metrics, and the honest statement of what is not measurable without an emitter |
| [`02-service-design/40-moments-that-matter.md`](../02-service-design/40-moments-that-matter.md) | The nine moments, ranked. The anchor for which views are critical |
| [`02-service-design/20-journey-maps.md`](../02-service-design/20-journey-maps.md) | Bob's twelve stages with their loops, Earl's and Pablo's journeys, the emotional arc |
| [`02-service-design/30-jtbd.md`](../02-service-design/30-jtbd.md) | Jobs to be done across all three personas |
| [`02-service-design/10-service-blueprint.md`](../02-service-design/10-service-blueprint.md) | Frontstage, backstage, the transitions, and the eight failure points |
| [`03-requirements/10-user-stories.md`](../03-requirements/10-user-stories.md) | 35 stories with shipped status, plus the seven-view Critical View Coverage table this brief extends |
| [`03-requirements/30-acceptance-criteria.md`](../03-requirements/30-acceptance-criteria.md) | 53 criteria and the four verification classes — the source of the ten / eighteen / one / twenty-four split |
| [`04-experience-design/50-ux-design.md`](../04-experience-design/50-ux-design.md) | The twelve UX principles, information architecture, seven task flows, the closed state vocabularies |
| [`04-experience-design/60-ui-design.md`](../04-experience-design/60-ui-design.md) | **Quiet Instrument**, the anti-direction, tokens as shipped, component patterns, the eight recorded deviations |
| [`04-experience-design/70-copy-voice.md`](../04-experience-design/70-copy-voice.md) | The voice, verbatim shipped strings with file and line, the banned-language stop list, and the seventeen catalogued jargon leaks |
| [`03-design/control-tower-native-experience-architecture.md`](../../03-design/control-tower-native-experience-architecture.md) | Design of record, stage 1: structure, IA, complete state inventory |
| [`03-design/control-tower-interaction-spec.md`](../../03-design/control-tower-interaction-spec.md) | Design of record, stage 2: interaction |
| [`03-design/control-tower-visual-system.md`](../../03-design/control-tower-visual-system.md) | Design of record, stage 3: colour, material, type, iconography, spacing, motion |
| [`03-design/control-tower-copy-deck.md`](../../03-design/control-tower-copy-deck.md) | The ratified copy specification the code was built from |
| [`01-architecture/cli-contract.md`](../../01-architecture/cli-contract.md) | The verb and schema seam the whole product renders |
