# Admin Experience: Interaction Design

|  |  |
|---|---|
| **Stage** | Interaction design (uxd) for the redesigned **Admin mode**. Turns the owner-approved service blueprint (`admin-experience-service-design.md` §5, the 16-surface inventory) into wireframe-level layouts, fully enumerated interaction states, mockup annotation pairs, and keyboard/VoiceOver notes. **Design doc only.** No Swift, no HTML; the HTML mockup walkthrough is built from this spec in the next stage by uid. |
| **Deliverable** | One document: layouts + states + annotations + accessibility for all 16 app surfaces, plus the new sidebar IA, the novel pieces at double depth (the Orientation ecosystem explainer, the live harness-aware plan card, the Integrations lifecycle preview + registry mock, the Review baton pass, the blind Handed-off state, the Setup-check drift note), the Journey B education-only shape, and a flow map. **Worked example throughout:** `acme-co`, a **Codex** shop, with departments **Accounting** and **Sales**. |
| **Persona** | **Earl**, a technical operator standing up his company's org on GitHub, assumed to know nothing about the ecosystem at the start. End users (Bob) never see any of this. |
| **Reads on** | `admin-experience-service-design.md` (THE authoritative input; §5 inventory of 16 surfaces, §7 ratified owner answers) · `control-tower-admin-flow.md` (the flow being replaced; surviving craft: refuse-and-teach, owner-named failures, count-never-score, roadmap grammar, §13 keyboard/VoiceOver discipline, the run-state vocabulary) · `control-tower-interaction-spec.md` §5 (source-list sidebar, StepShell grammar, the eight control states) · `control-tower-visual-system.md` (the "Quiet Instrument" language these layouts must be expressible in) · `control-tower-copy-deck.md` (voice). |
| **Voice** | Air-traffic controller for Earl: calm, factual, unhurried, names the owner of every fix. **Absolute rules honored in every drafted string:** no em-dashes, no time estimates, no aggregate scores, no celebration. Lines lifted verbatim from the sd doc or the copy deck are used as-is; genuinely new lines are marked `[cw]` for finalization. |
| **Governing invariants** | #1 parse-never-compute (the app **collects and renders only**; every GitHub mutation lives in the terminal script; no `gh`/GitHub logic in Swift) · #3 never-destroy (additive/idempotent, stated up front and legible after) · #4 security inherited-not-weakened (no `--force`/`--skip-verify`, no bypass) · #6 secrets never in git (secret-shape refusal on the two surfaces that still collect a store endpoint). |

---

## 0. Method, and the one interaction shape this doc commits to

The redesign is **not a wizard that sets up an org**. It is a **baton pass**: the app is the *confident briefer and honest verifier*; Claude Code (over the deterministic idempotent script) is the *capable, mess-absorbing driver*. The app owns **confidence before** and **truth after**; the terminal owns **execution**. Every layout below is built so the app never pretends to do, see, or judge the work in the terminal.

Four interaction consequences run through all 16 surfaces:

1. **No surface fires a GitHub mutation.** The onboarding surfaces *collect into a non-secret brief*; the Setup check *renders a read-only verify verb's rows*. The old "app fires bootstrap and streams `Created` / `Already there` rows" is gone; that never-destroy legibility **relocates** to Claude Code's terminal narration and to the Setup check re-run (which reads as a column of green with a plain count).
2. **Orientation precedes input, and now teaches the ecosystem from zero.** No content region collects before its purpose is on screen, and the first surface teaches *what the ecosystem is* (not just the arc) before anything else, via progressive disclosure: a calm main view with a **Learn more** affordance behind which the real depth lives.
3. **The admin declares nothing about integrations, and connects a store only if they choose to.** Integrations is education-only (no declaration act, no secret-shape refusal there anymore); the secret store is educate + connect-or-defer, never a hard gate.
4. **Refuse and teach, never bypass.** Where readiness or a value is short, the surface says what is true, names the one fix and its owner, and never a `--force` or a `--skip-verify`.

Method per surface: **layout** (StepShell zones inside the Admin window) → **interaction states** (enumerated from the sd inventory, every refusal included) → **annotation pair** (for the mockup: plain "what Earl sees" + technical "what actually happens, by whom") → **keyboard/VoiceOver** (brief; inherits the old flow's §13 discipline).

---

## 1. The new sidebar IA

### 1.1 The window frame (source-list sidebar + detail pane + handoff header)

One `Window`, a left source-list sidebar in **two sections** (Onboarding, Governance), a detail pane on `surface.window`, and the persistent read-only **handoff header** atop the window whenever an Onboarding item is selected. This reuses the established Admin frame (interaction-spec §5.2) unchanged in structure.

```
┌───────────────────────────── Administration ──────────────────────────────┐
│  ⇄  Publisher done · Setup v1.4.2 · Next: you (Admin)     [Reveal setup ›]  │  handoff header (Onboarding only)
├────────────────────────┬───────────────────────────────────────────────────┤
│ ONBOARDING             │   EYEBROW (ONBOARDING)                             │
│  ✓ Orientation         │   Step title                                       │
│  ✓ Prerequisites       │   Intro line (plain)                               │
│  ✓ Contacts            │   ┌── content region ──────────────────────────┐  │
│  ◐ Connect GitHub  3/5 │   │                                             │  │
│  ◉ Describe your org   │   │   (StepShell content for the selected item) │  │
│  ○ Integrations        │   │                                             │  │
│  ○ Secret store        │   └─────────────────────────────────────────────┘ │
│  ○ Review and hand off │   ───────────────── footer divider ────────────── │
│  ○ Handed off          │   [Back]                status            [Primary]│
│  ○ Setup check         │                                                    │
│  ○ Done                │                                                    │
│ ────────────────────── │                                                    │
│ GOVERNANCE             │                                                    │
│    Add a department    │                                                    │
│    Someone left        │                                                    │
│    Connect the store   │                                                    │
│    Org setup           │                                                    │
│    Analytics           │                                                    │
└────────────────────────┴───────────────────────────────────────────────────┘
```

### 1.2 Item vs state decisions (the interrogation the brief asked for)

The progression is eleven onboarding waypoints and **five** governance entries (Governance gained one). Three decisions, each made deliberately:

- **"Handed off" is its own item, not a state of "Review and hand off."** The sidebar's whole job is to answer *where is the baton*. Review = "the baton is in your hand, about to pass." Handed off = "the baton is in the terminal now." Setup check = "the baton is back with you to verify." A blind waiting state the app cannot see is exactly the moment the map must stay honest about, so it earns its own row; folding it into Review would make the map lie after Earl leaves for the terminal.

- **"Done" is its own item, not a state of "Setup check."** The done/current/upcoming grammar needs a *visible finish line*, and Done's job (invite the team on GitHub, hand out the user-face app) is forward-pointing action, not verification. A returning governance user re-runs the Setup check constantly but never needs Done again, so coupling them would clutter the verify surface.

- **"Connect the shared store" is its own Governance item, not part of "Org setup."** This is the ripple from the store becoming connect-or-defer. Connecting a store is a **write** (it adds the store pointer to the org setup, authored by the script through a hand-off); Org setup is **read-only** by design. Folding a write into a read-only summary would break that surface's honesty, so the deferred-store home is its own surface that reuses the standup connect form (one mental model, two entry points). This mirrors the sd's ratified placement rationale (§4 C3).

Everything else maps 1:1 (Orientation is its own item, the "you are here: start"; Prerequisites stays pure teach, Contacts stays the slim collect, so the surface that only explains never also asks). Governance entries carry **no** progression marks (they are occasional entries, not a pipeline).

### 1.3 The progression is a map, not a lock (and the advisory Connect GitHub signal)

The sharpest departure from the flow being replaced. In the old flow, "Connect GitHub gates everything downstream." **That gate is deleted.** The script is the real gate and Claude Code absorbs anything still missing, so:

- **Onboarding rows are all freely navigable.** Done/current/upcoming marks show *progress*, not permission. No downstream row is ever `disabled`, greyed, or lock-glyphed. The map guides, the terminal gates.
- **Connect GitHub's advisory-incomplete state reads as a quiet partial, never an alarm and never a block.** When some readiness rows are not green, the sidebar item shows a **neutral partial mark plus a plain count** (`◐ Connect GitHub 3/5`), rendered in `content.secondary` gray, *not* red or orange, and it never turns downstream rows off. The count is the honest signal; the freedom to proceed is the honest model. The item reaches `✓` only when all five rows are green, but reaching `✓` is never a precondition for anything.
- **The secret store never gates either.** Because the store is connect-or-defer (Surface 7), an unfinished store leaves its row upcoming (`○`) and downstream fully navigable; deferral is a valid path to Done.
- **Marks** reuse the established roadmap grammar (visual system §4.1): `✓` done; `◉` current; `○` upcoming. The **partial** mark (`◐` + count) is the one new token, proposed for the advisory Connect GitHub state and flagged for uid.
- **Revisitability:** completed rows are tappable to review; because nothing is locked, upcoming rows are tappable too. Closing mid-progression loses nothing (state is GitHub/brief truth, re-read on next open). The handoff header answers "where is the baton" at every moment.

### 1.4 StepShell grammar (reused, interaction-spec §5)

Every onboarding surface uses the established StepShell content anatomy in the detail pane: **eyebrow → title → intro → content region → pinned footer action bar** (Back leading, ephemeral status center, primary trailing). Governance surfaces use the same shell; the read/guidance ones drop the Back/primary progression footer, while the one governance *collect* surface (Connect the shared store) carries a hand-off footer. Every interactive element carries the standard eight control states per interaction-spec §5; the per-surface tables below enumerate the *flow* states from the sd inventory (idle/working/done/degraded/refused/empty), which is where the design decisions live.

---

## 2. Onboarding surfaces (1-11)

### Surface 1 — Orientation (teach the ecosystem, then the arc)  **[novel piece, double depth]**

**Purpose:** teach the ecosystem from zero (what it is, inheritance, the three repo types per layer, the user benefit) and then the whole arc, via progressive disclosure. Renders the arc, the handoff object, and (behind Learn more) two explainer views with theme-aware diagrams and concrete skill examples. Collects nothing.

**Layout (main view, calm)**

```
EYEBROW   ONBOARDING
TITLE     Here's what you're building, and the whole path
INTRO     Your copilots live in a set of shared spaces on GitHub that build
          on one another. The open-source foundation sits at the bottom.
          Your organization adds its own on top. Each department adds what
          only it needs. Each person adds their own on top of that. Everyone
          inherits everything beneath them, so you share broad capabilities
          widely and keep specialized ones narrow.
CONTENT   ┌─────────────────────────────────────────────────────────────┐
          │  1  Describe your organization here.                         │
          │  2  Claude Code sets it up in your terminal.                 │
          │  3  Come back and run the Setup check.                       │
          └──────────────────────────────────────────────────────────────┘
          This app never changes anything on GitHub itself. It gets you
          ready, hands the work to Claude Code, and checks the result.
          ↳ Learn how the ecosystem works ›        (secondary, pushes explainer)
FOOTER    (no Back)                                          [ Start ]
```

**Layout (Learn more, the pushed explainer)** — the detail pane pushes into an explainer while the sidebar and handoff header stay visible; a segmented pager switches the two views and a leading Back returns to the calm overview.

```
EYEBROW   LEARN MORE
SWITCHER  [ How it works | What your team gets ]   (segmented, view selector)
CONTENT   ┌───────────── theme-aware ecosystem diagram ─────────────────┐
          │        (redrawn per light/dark; legible, never a raster)     │
          │   personal  ── inherits ──▲                                  │
          │   department ── inherits ──▲                                  │
          │   organization ─ inherits ▲                                  │
          │   foundation (open source) ▲                                 │
          └──────────────────────────────────────────────────────────────┘
          VIEW 1 prose  Each layer carries three kinds of space: one for
                        instructions and agents (your harness's copilot),
                        one for knowledge (your company's information), and
                        one for integrations (tools that reach outside
                        systems). The org level carries org-level agents,
                        org-level integrations, and org information.
          VIEW 2 prose  Every person inherits your organization's agents,
                        skills, knowledge, and integrations, plus their
                        department's, on the open-source foundation. They
                        build their own solutions faster, going broad with
                        what the org shares and narrow with the department.
          VIEW 2 examples  Org: a skill that writes on-brand documents; a
                        proposal and SOW builder.  Accounting: a month-end
                        reconciliation skill.  IT: an onboarding and
                        offboarding access-runbook skill.  Sales: a call-prep
                        brief skill.
FOOTER    [ ‹ Back to the overview ]
```

**Navigation decision (the one this surface asks me to make): an in-pane push, not a modal sheet, and not always-visible sections.**
- *Not a modal sheet:* the explainer is optional depth, not a blocking decision, and modals interrupt the calm main view and steal the sidebar/handoff context. (Visual-system rule: never use modals for information that should be inline.)
- *Not always-visible scrollable sections:* that would front-load the depth into the calm main view and defeat the progressive disclosure that protects the hurried operator.
- *Selected: an in-pane push* (a `NavigationStack`-style push of the detail pane) with the **two explainer views as a segmented pager** inside it and a leading **Back to the overview**. The sidebar and handoff header stay put, so Earl never loses his place in the progression; the diagram gets the full content-pane width; and either view is one click away with a clean return. *Microinteraction:* trigger = click `Learn how the ecosystem works ›`; rules = push the explainer, segmented control defaults to View 1; feedback = detail pane cross-fades to the explainer (Reduce Motion keeps the cross-fade, no slide); loops = Back returns to the overview; a theme switch redraws both diagrams instantly.

**How the diagrams sit in the StepShell:** each diagram is a **theme-aware SVG redraw of the owner's canonical ecosystem diagram**, centered at the top of the content region under the eyebrow/switcher, width-constrained (`maxWidth` of the content column), with the prose and examples below it (stacked on a narrow window; the diagram may sit beside the prose on a wide window, uid's call). The diagram is meaningful content, not decoration, so it carries a full text alternative. Reduce Motion: the light/dark redraw is an instant swap, never an animated morph.

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| main view (calm) | The one-paragraph what-this-builds + the three-step arc + the Learn more affordance; handoff header populated | Start | `This app never changes anything on GitHub itself. It gets you ready, hands the work to Claude Code, and checks the result.` (sd A0) |
| explainer view 1 (how it works) | Pushed explainer; inheritance diagram + the three kinds of space | Back to the overview | `Each layer carries three kinds of space: one for instructions and agents, one for knowledge, and one for integrations.` [cw, from sd A0] |
| explainer view 2 (what the team gets) | Same push, view 2; benefit diagram + concrete skill examples | Back to the overview | `Every person inherits your organization's agents, skills, knowledge, and integrations, plus their department's, on the open-source foundation.` [cw, from sd A0] |
| handoff-unreadable (degraded) | Header swaps to `Not started yet`; holding line replaces header chips; teach content still renders | Start (still available) | `I couldn't read the result of this, so I won't guess.` (sd A0) |

**Annotation pair**
- *What Earl does and sees:* Earl, who may know nothing about the ecosystem, lands on a calm one-paragraph explanation of what he's building (shared spaces on GitHub that build on one another) and the three-step path, told plainly the app never touches GitHub. If he wants depth, Learn more opens two illustrated views: how inheritance works and the three kinds of space, then what his team actually gets, grounded in concrete skills like a month-end reconciliation skill and a call-prep brief. He returns to the calm overview and clicks Start.
- *What actually happens:* The app reads the Publisher-to-Admin handoff object and renders it; the diagrams are static explainer assets redrawn per theme (light and dark), rendering no live state. Nothing is read from or written to GitHub. If the handoff object is unreadable, the header shows `Not started yet` and the honest holding line; the teach content and diagrams never depend on live state, so they always render.

**Keyboard/VoiceOver:** the Learn more control is a button announced "Learn how the ecosystem works, opens an explainer"; the push keeps the sidebar reachable (nothing is trapped); the segmented pager is a standard segmented control (Left/Right, each segment announced); each diagram carries a full `accessibilityLabel` describing the inheritance structure (it is content, not decoration); Back to the overview is a real Back button. The handoff header is a VO container announced on window open. Reduce Motion: cross-fade the push, instant theme redraw.

---

### Surface 2 — Prerequisites and reality check

**Purpose:** teach what must be true before setup can run (org exists, owner, billing reality, tools present). Renders a teach checklist; collects nothing. Pure teach, so it never strands Earl on a boundary later.

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Before you begin
INTRO     A few things need to be true before setup can run. None of them
          happen here. This is just so nothing stops you halfway.
CONTENT   •  Your organization exists on GitHub. Creating one needs billing
             and a person, so it can't be automated. If it doesn't exist
             yet, create it at github.com first.         [Open github ›]
          •  You are an owner of it. Only an owner can create the
             organization's spaces.
          •  You have GitHub's command-line tool and Claude Code on this
             Mac. The next step checks and helps.
FOOTER    [Back]                                        [ Continue ]
```

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| idle / not-started | The three facts as read-only teach rows | Continue | `A few things need to be true before setup can run. None of them happen here. This is so nothing stops you halfway. Your organization exists on GitHub. Creating one needs billing and a person, so it can't be automated. You are an owner of it. Only an owner can create the organization's spaces.` (sd A1) |

No failure state by design: this stage names the one categorical automation boundary before anything can fail on it.

**Annotation pair**
- *What Earl does and sees:* Earl reads a short, honest list of what must already be true, told plainly that none of it happens here. If his org exists and he's an owner, he continues confident. If not, he learns the one thing to do first (create the org at github.com, which needs billing and a person) before he's stranded.
- *What actually happens:* Pure render of a static teach checklist. No detection runs here (detection is Surface 4); the app writes and reads nothing beyond its own copy. `Open github` is a deep link out.

**Keyboard/VoiceOver:** read-only VO list; each fact announced as text, `Open github` as a link; Continue is `.defaultAction`, Back is a real button (Esc inert in the window body).

---

### Surface 3 — Contacts

**Purpose:** record who owns this setup (feeds the handoff header and the Setup check owner names). Collects publisher / admin / point-of-contact names. Slim; metadata, not user management.

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Who's who
INTRO     Record who owns this setup, so the handoff is never guesswork.
          These names show in the handoff banner and in the setup check.
CONTENT   Publisher          [___________________________]
          Admin              [___________________________]
          Point of contact   [___________________________]
FOOTER    [Back]              Saved.                       [ Continue ]
```

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| empty | Three empty fields | Continue | `No contacts yet. Add the people who own this setup.` (copy deck 3.4) |
| saved | Field values retained; status shows confirmation | Continue | `Saved.` (copy deck 3.4) |

**Annotation pair**
- *What Earl does and sees:* Earl types the names of the people who own this setup, understanding these are just labels that will show up in the handoff banner and next to any red in the Setup check, so nothing is ever an anonymous "someone."
- *What actually happens:* The app collects three name strings into local setup metadata that feeds the handoff header chips and the owner labels the Setup check renders. Nothing here is user management and nothing is written to GitHub; these names never grant or change access.

**Keyboard/VoiceOver:** `FocusState` chain top to bottom; Return submits; each field labeled; the names feed the VO-announced handoff header and Setup-check owner labels.

---

### Surface 4 — Connect GitHub (readiness, refuse-and-teach)

**Purpose:** detect local readiness for the terminal session and, where short, teach the one fix. Renders detection results and collects the org name + a check intent. **No mutation.** Advisory and strongly guiding, never a hard block (ratified §7.3).

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Get this Mac ready
INTRO     A quick check that this Mac can run the terminal session. This
          changes nothing. Claude Code checks all of this again when setup
          runs, and helps you fix anything that's off.
CONTENT   Organization   [ acme-co ]
          ┌─────────────────────────────────────────────────────────────┐
          │  ✓  GitHub's command-line tool is installed                  │
          │  ✓  You're signed in                                         │
          │  ✗  Your account is an owner of acme-co     Ask an owner ...  │
          │  ✗  Your sign-in has the access setup needs                  │
          │        gh auth refresh -s admin:org -s repo      [ Copy ]    │
          │  ✓  Claude Code is installed                                  │
          └─────────────────────────────────────────────────────────────┘
          This step just gives you a head start. It never blocks the hand-off.
FOOTER    [Back]         Checking...           [ Check again ]
```

**Interaction states** (every refusal names one fix and its owner; **no bypass, ever**)

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| idle | Rows show `Not checked yet` | Check access | `Not checked yet.` [cw] |
| working | Rows resolve; header status `Checking...` (no ETA) | (none, in progress) | `Checking your GitHub access...` (sd A2) |
| ready | All five rows green | Continue (freely) | `Your GitHub access can set up acme-co.` [cw] |
| refused: gh not installed | That row `✗`, teach + copyable command | Check again | `GitHub's command-line tool isn't on this Mac yet. Setup runs through it.` + copyable `brew install gh` + download link (sd A2) |
| refused: not signed in | That row `✗` | Check again | `You're not signed in to GitHub's command-line tool yet.` + copyable `gh auth login` (sd A2) |
| refused: not an owner | That row `✗`, owner named | Check again | `Your GitHub account isn't an owner of this organization, so it can't create its spaces. Ask an owner to run this, or to make you one.` (sd A2) |
| refused: missing scope | That row `✗`, copyable refresh command | Check again | `Your GitHub sign-in is missing the access setup needs.` + copyable `gh auth refresh -s admin:org -s repo`. No bypass. (sd A2) |
| refused: Claude Code missing | That row `✗` | Check again | `Claude Code isn't on this Mac yet. Setup runs there, so you'll want it before you hand off.` (sd A2) |
| degraded | The check itself couldn't run; rows hold, honest line | Check again | `Something stopped me from checking your access, so I won't guess.` [cw] |

**Microinteraction (Check again):** *Trigger:* Earl fixes a row in Terminal, returns, clicks Check again. *Rules:* re-run local read-only detection. *Feedback:* each row resolves in place to green or a refusal; no ETA. *Loops:* a returning-to-green run reads calm; there is never a `--force`, `--skip-verify`, or "proceed anyway" that weakens posture.

**Annotation pair**
- *What Earl does and sees:* Earl sees a short list of plain readiness rows. Green ones reassure; a not-ready row tells him exactly one thing to do (a copy-paste command, or "ask an owner") and offers Check again. Nothing blocks him; the copy says Claude Code re-checks and helps anyway. A missing scope reads as copy-paste-and-continue, not a dead end.
- *What actually happens:* The app runs local, read-only detection only (`gh auth status`, version probes, an owner-and-scope check) and renders the rows. It computes no authoritative verdict and mutates nothing; the script re-checks everything in the terminal and is the real gate. The copyable commands are clipboard text, not commands the app runs.

**Keyboard/VoiceOver:** each refusal is a VO group ("GitHub access, not ready, and how to fix it"); the copyable command is `.textSelection(.enabled)` with Copy + "Copied"; Check again is `.defaultAction`. Status is a polite live region; the sidebar shows the advisory partial mark while rows are short, downstream never disabled.

---

### Surface 5 — Describe your organization  **[novel piece, double depth]**

**Purpose:** teach why departments get their own spaces; ask the harness once, org-wide; collect identity and departments; show the concrete plan by real name. Collects the harness choice, org slug, and department list; renders the teach layer, the add-later promise, and the live **"What this will create"** plan card. **Nothing is created here.** Serves A3 (standup) and C1 (add a department or the second harness).

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Describe your organization
INTRO     Tell setup your organization's name, the harness it builds with,
          and its departments. As you type, you'll see exactly what will be
          created. Nothing is created here. This is the plan setup will follow.
CONTENT   ┌── WHY DEPARTMENTS GET THEIR OWN SPACES (teach) ─────────────┐
          │  Departments get their own spaces so specialized             │
          │  capabilities are tailored to how that department works.     │
          │  Accounting's spaces hold Accounting's skills and knowledge; │
          │  each department's people inherit the whole organization's    │
          │  on top.                                                     │
          │                                                              │
          │  You don't have to add every department now. Adding one       │
          │  later is safe. Setting up again only adds what's new and     │
          │  never touches what's already there.                         │
          └──────────────────────────────────────────────────────────────┘
          Which development harness does your company build with?
            [ Claude Code   |   ◉ Codex ]        (segmented, org-wide default)
          This is your organization's default. Anyone can still use the
          other harness for themselves, on the open-source foundation plus
          their own personal setup. And you can add the second harness for
          the whole organization later, as a safe re-run that only adds
          what's new.
          ─────────────────────────────────────────────────────────────
          Organization name   [ acme-co ]
          Departments         [ Accounting     ]  [ – ]
                              [ Sales          ]  [ – ]
                              [ + Add a department ]
          ┌── WHAT THIS WILL CREATE ────────────────────────────────────┐
          │  Nothing is created here. This is the plan setup will follow.│
          │                                                              │
          │  Three shared spaces for your whole organization:            │
          │    acme-co/codex-copilot                                     │
          │    acme-co/knowledge-copilot                                 │
          │    acme-co/cli-copilot          Private.                     │
          │                                                              │
          │  Three spaces for the Accounting department:                 │
          │    acme-co/codex-copilot-accounting                          │
          │    acme-co/knowledge-copilot-accounting                      │
          │    acme-co/cli-copilot-accounting   Private.                 │
          │    An Accounting team that can reach them.                   │
          │                                                              │
          │  Three spaces for the Sales department:                      │
          │    acme-co/codex-copilot-sales                               │
          │    acme-co/knowledge-copilot-sales                           │
          │    acme-co/cli-copilot-sales    Private.                     │
          │    A Sales team that can reach them.                         │
          │                                                              │
          │  Your whole organization set to read by default.             │
          │                                                              │
          │  You don't have to add every department now. Adding one       │
          │  later is safe. Setting up again only adds what's new.        │
          └──────────────────────────────────────────────────────────────┘
FOOTER    [Back]                                        [ Continue ]
```

**The harness-choice control (the decision this surface asks me to make): a segmented control, default shown not silent, plan card mirrors the consequence.**
- *Control:* a **two-segment segmented control** (`Claude Code | Codex`), placed prominently *above* the plan card so cause and effect are adjacent. Segmented over radio because the two options are mutually exclusive, org-wide, and best kept both-visible-at-a-glance (the native macOS match, Jakob's Law; recognition over recall).
- *Default, made non-silent:* the sd ratifies "a sensible default, changeable until hand-off," so a default selection exists (Earl is never blocked by an unset control). It is **not silent** because (a) the selected segment is clearly active and labeled "your organization's default," and (b) the choice's *consequence is always literally on screen*: every harness-dependent name in the plan card reads `codex-copilot*` or `claude-copilot*` for the current selection. There is no state where a harness has been assumed but its effect is hidden. (Worked example: the flagship default may be Claude Code, but `acme-co` is a Codex shop, so its card shows `codex-copilot*`.)
- *Switching re-derives every name in one coordinated update.* *Microinteraction:* trigger = pick the other segment; rules = the app re-derives the `<harness>-copilot*` token in the org block and every department block by the same convention the script enforces (`<harness>-copilot`, `knowledge-copilot`, `cli-copilot`, each suffixed `-<unit>`); feedback = the whole plan card's harness-named rows update together (a single coordinated re-render, ~150ms, cross-fade under Reduce Motion), so it reads as "the plan just switched harness," not a flicker of unrelated rows; loops = the reassurance copy stays put, defusing "am I locking everyone into one tool forever?" before it forms.

**The live plan card, in detail (the strongest positive moment of truth).**
- *Fills as Earl types.* Trigger: every debounced keystroke in the org-name field, every add/remove/edit of a department row, and every harness switch. Rules: slugify the org and each department, derive the display names for legibility (the script is the authority that actually creates them). Feedback: the affected block appears or updates with a gentle reveal (~150ms; cross-fade under Reduce Motion). Re-typing the org name live-updates every derived name at once.
- *Exact enumeration format, by real name.* Repo and team names render as mono values, one per line, grouped by scope: the org block (three shared spaces + "Private."), one block per department (three spaces + "Private." + "A `<Unit>` team that can reach them."), then the org-wide "read by default" line. Never an abstract summary, never a raw YAML surface.
- *Card empty state.* Before a valid org name: `Type your organization's name to see the plan.` [cw]
- *The add-later promise* is repeated at the bottom of the card so "safe to add more later" is answered at the moment of decision (its after-the-fact answer is the green re-run in the Setup check).

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| teach + harness choice | Teach layer + prominent add-later note + the segmented harness control with reassurance | Continue | `This is your organization's default. Anyone can still use the other harness for themselves, on the open-source foundation plus their own personal setup. And you can add the second harness for the whole organization later, as a safe re-run that only adds what's new.` (sd A3) |
| empty | Fields empty; card shows the prompt line | Continue (disabled until a valid org name) | `Type your organization's name to see the plan.` [cw] |
| typing (plan fills live, named by chosen harness) | Card blocks appear/update per keystroke, department, and harness switch | Continue | (card header) `Nothing is created here. This is the plan setup will follow.` (sd A3) |
| invalid-slug refusal (inline) | The offending field shows an inline caption; **no half-valid block reaches the card** | fix inline, then Continue | `Give this department a name using letters, numbers, and dashes.` (sd A3) |

**Annotation pair**
- *What Earl does and sees:* Earl reads why departments get their own spaces and, prominently, that he can add more later safely. He picks his org's development harness once (Codex, for acme-co), reassured that individuals can still use the other one personally and the org can add the second later. He types his org name and departments, and the "What this will create" card fills with the exact spaces and teams by real name, `acme-co/codex-copilot-accounting` and a named Accounting team, updating live if he switches harness.
- *What actually happens:* The app collects the harness choice, org slug, and department list, validates each slug, and derives the display names by the same convention the script enforces (three spaces per layer, `<harness>-copilot` / `knowledge-copilot` / `cli-copilot` at org, each suffixed `-<unit>`, where `<harness>` is the chosen `claude` or `codex`), purely for legibility. It renders the plan; it creates nothing and writes nothing yet (the description, including the harness choice, is written to the brief only at Review). The script, in the terminal, is the authority that actually creates the spaces and teams.

**Keyboard/VoiceOver:** the harness control is a segmented control announced "Development harness, Codex selected, your organization's default"; switching it announces the plan card update as a polite live region ("Plan updated for Codex"). `FocusState` runs harness to org-name to the departments list; the plan card is a VO container ("What this will create, preview") read as a labeled list; inline slug errors announced on the offending field.

---

### Surface 6 — Integrations (education only)  **[novel piece, double depth]**

**Purpose:** education only. Teach the integration model and preview how integrations will arrive; the admin declares nothing. **Collects nothing.** No declaration form, no secret-shape refusal (both removed from this surface). Serves A4 and B (educate).

**The correction, made structural:** at standup no integrations exist, and the admin never declares one. This surface teaches, previews the lifecycle, shows a clearly-marked future-state mock, and ends honestly. Education leads (above the fold, not collapsible-away); there is no input anywhere on the surface.

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Integrations
INTRO     An integration here is a small command-line tool a developer
          builds, so a copilot can reach a system like Salesforce or your
          calendar. It isn't something you switch on.
CONTENT   ┌── HOW INTEGRATIONS WORK (education) ─────────────────────────┐
          │  It cascades              Built and published for the whole   │
          │                           organization, it's inherited by     │
          │                           every department. Published for one │
          │                           department, it belongs only there.  │
          │                           Published nowhere, it exists for no  │
          │                           one.                                │
          │  The key lives elsewhere  An integration names the key it     │
          │                           needs. The key never comes near     │
          │                           this app. It lives in the shared    │
          │                           store, handed out only to the right │
          │                           team.                               │
          └──────────────────────────────────────────────────────────────┘
          ── How integrations will arrive (a lifecycle preview) ─────────
          1  An engineer on a department builds skills, agents, and
             integrations inside that department's spaces. (Give an engineer
             write access to a department's team and they can build there.)
          2  Each integration is added to a registry, a plain document that
             lives in the same space and lists what has been built.
          3  Merging that document to the main copy publishes the integration.
          4  From then on, the people entitled to that space see it, and the
             app your team uses can let them know when a new one arrives.
          ┌╌╌╌╌╌╌ PREVIEW · not live · nothing here is a control ╌╌╌╌╌╌┐
          ┊  acme-co/cli-copilot-sales · registry (example)            ┊
          ┊    salesforce-lookup      needs SALESFORCE_API_KEY         ┊
          ┊    calendar-read          needs GOOGLE_CAL_TOKEN           ┊
          ┊  This is what a published registry will look like. It is    ┊
          ┊  an example, not your data, and nothing here is clickable.  ┊
          └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘
          There's nothing to set up here today. No integrations exist yet,
          and that's expected. They arrive when your departments' engineers
          build and publish them.
FOOTER    [Back]                                        [ Continue ]
```

**Distinguishing the future-state preview from live UI (the spec this surface asks for), so it can never be mistaken for a real control:**
- *A persistent preview frame + label.* The mock lives inside a visually distinct container (proposed: a dashed/tinted `surface.field` frame carrying a `PREVIEW · not live` ribbon at its top edge), clearly separated from the surrounding live UI. The distinctness is structural, not just a color tint (so it survives grayscale).
- *Fully inert.* No row is a tab stop; there are no buttons, chevrons, hover highlights, or focus rings; the cursor does not change over it. Anything that resembles a control is visibly non-actionable.
- *Obvious example data.* The names are framed as examples (`salesforce-lookup`, `calendar-read`) and the caption states it is an example, not Earl's data.
- *Announced as a preview.* VoiceOver announces the whole block as "Preview, example only, not interactive," and reads its rows as values, never actions.

**Interaction states** (no inputs, no refusals)

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| education | The model above the fold (what an integration is, the cascade, where the key lives) | Continue | `An integration here is a small command-line tool a developer builds, so a copilot can reach a system like Salesforce or your calendar. It isn't something you switch on.` (sd A4) |
| lifecycle preview | The four read-only beats | Continue | (beat 1) `An engineer on a department builds skills, agents, and integrations inside that department's spaces.` (sd A4) |
| registry mock (labeled preview, inert) | The distinct preview frame with example rows | (none; inert) | `This is what a published registry will look like. It is an example, not your data.` [cw, from sd A4] |
| honest empty ending | The closing statement | Continue | `There's nothing to set up here today. No integrations exist yet, and that's expected. They arrive when your departments' engineers build and publish them.` (sd A4) |

**Annotation pair**
- *What Earl does and sees:* Earl learns what an integration is (a small tool a developer builds, not a switch), how publishing at the org level cascades to every department, and where the key lives. He sees a four-step preview of how integrations will arrive later, an engineer builds one in a department's repos, adds it to a registry document, merging to main publishes it, and entitled people then see it, plus a clearly-labeled mock of what a published registry will look like. It ends honestly: nothing to set up here today, and that's expected.
- *What actually happens:* Pure render. This surface collects nothing and writes nothing to the brief; the declaration form and its secret-shape refusal are gone entirely. The org setup file carries no integration declarations; existence lives in per-repo registries, gated by entitlement (a user sees only the registries of the spaces they can reach). The lifecycle preview and registry mock are static explainer content rendering no live data.

**Keyboard/VoiceOver:** the education block reads as labeled chunks; the four beats read as an ordered list; the registry mock is a VO group announced "Preview, example only, not interactive," its rows read as values; there is no action target on the surface.

---

### Surface 7 — Secret store (educate, then connect or defer)

**Purpose:** educate on what a store is and how it is used at runtime, then connect or defer honestly (this supersedes "required"). Collects (if connecting) store type, address, and team-to-scope mapping; renders the education, the connect form, and the no-store choice. Secret-shape refusal is **retained here**. No hard gate on finishing standup.

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Your shared secret store
INTRO     A shared secret store is one service that holds your organization's
          keys and hands them out by team. Shared integrations need it: an
          integration names the key it needs, and at runtime the store checks
          that the person is on the right GitHub team and only then hands over
          the key. That is why a key never lives in a repo or in this app.
CONTENT   ── Connect a store ────────────────────────────────────────────
          Store type          [ Infisical  ▾ ]
          Store address       [ https://vault.acme-co.com          ]
                              This is a web address, not a secret.
          Which teams can use it   Accounting → [ acct scope  ▾ ]
                                   Sales      → [ sales scope ▾ ]
          ── No store yet? ──────────────────────────────────────────────
          Shared integrations can't work until you connect a store. You have
          no integrations yet, so you can finish setting up now and connect a
          store before your first one is built.
            •  Pause and go get one. Common shared stores are 1Password,
               Infisical, and Vault (also called OpenBao). Set one up, then
               come back with its web address.          [ How to set one up ›]
            •  Skip this for now. You'll be reminded to connect a store
               before your first shared integration can work.  [ Skip for now ]
FOOTER    [Back]                                        [ Continue ]
```

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| educate | The what-and-why on screen before any field | (read) | `A shared secret store is one service that holds your organization's keys and hands them out by team. Shared integrations need it ... That is why a key never lives in a repo or in this app.` (sd A5) |
| connect (form) | The guided form (type, address, team scoping) | Continue | (address helper) `This is a web address, not a secret.` (sd A5) |
| address-invalid refusal | The address field shows an inline caption on blur | fix the address | `That doesn't look like a valid address.` (sd A5) |
| secret-shape refusal (retained here) | Field shows the firm-but-plain error; value blocked, never stored | fix the value | `That looks like a secret. This setting never holds secrets. Secrets live in the store itself, or in your keychain, never here.` (sd A5) |
| no-store: pause-and-go-get | The truth line + named examples + link out; the app waits | Continue (still allowed) | `Common shared stores are 1Password, Infisical, and Vault (also called OpenBao). Set one up, then come back with its web address.` (sd A5) |
| no-store: defer-and-finish | An explicit, honest deferral with its consequence and follow-up home | Skip for now / Continue | `Skip this for now. You'll be reminded to connect a store before your first shared integration can work.` (sd A5) |
| connected | Fields retained; status confirms | Continue | `Connected. This will be included when you hand off.` [cw] |

**Annotation pair**
- *What Earl does and sees:* Earl first reads what a shared secret store is and how it's used at runtime (it hands out keys by GitHub team membership, which is why keys never live in a repo or this app). If he has one, he connects it with a short form and never pastes a key. If he doesn't, he's told the plain truth (shared integrations can't work without one, but he has none yet) and offered two honest choices: pause to go get one, with named options, or skip for now and finish, with a clear note that he'll be reminded and where to connect it later.
- *What actually happens:* If he connects, the app collects the endpoint URL and team-to-scope mapping into the brief as the non-secret store pointer; the secret-shape refusal guards every field. If he defers, the brief carries no store pointer and the org setup file simply has none yet. Nothing is mutated on GitHub. Continue is never gated (deferral is a valid path to Done); a connected-but-unreachable store surfaces honestly in the Setup check (IT infra named), and a deferred store surfaces there as an honest "not connected yet," not a failure.

**Keyboard/VoiceOver:** `FocusState` chain; URL validated on blur with the error announced on the field; the two no-store choices are announced as distinct actions ("Pause and go get one", "Skip for now"); the secret-shape refusal announced firmly.

---

### Surface 8 — Review and hand off  **[novel piece, double depth, the pivotal moment]**

**Purpose:** enumerate concretely what will be created; write the brief; generate the copyable command; frame the baton pass. Renders the final plan + the never-destroy promise; writes the non-secret brief; collects the copy action. **No "set up my org" mutation.**

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Review and hand off
INTRO     Here's everything setup will create. Copy the command below, open
          your terminal, and paste it. Claude Code walks you through the rest
          and checks everything with GitHub as it goes.
CONTENT   ┌── NEVER-DESTROY PROMISE (pinned to the top) ────────────────┐
          │  This adds and updates. It never deletes or overwrites        │
          │  anything already there.                                     │
          └──────────────────────────────────────────────────────────────┘
          ┌── WHAT SETUP WILL CREATE ───────────────────────────────────┐
          │  Org spaces: acme-co/codex-copilot, knowledge-copilot,        │
          │              cli-copilot   Private.                          │
          │  Accounting: three spaces + an Accounting team                │
          │  Sales:      three spaces + a Sales team                      │
          │  Your organization's setup file (ecosystem.yml).             │
          │  Your whole organization set to read by default.             │
          │  Harness: Codex.   Store: connected  /  not connected yet.    │
          └──────────────────────────────────────────────────────────────┘
          ┌── THE FILE SETUP WROTE FOR YOU ─────────────────────────────┐
          │  Setup wrote a plain description of your organization you      │
          │  can read:                                                    │
          │    ~/…/CopilotControlTower/standup-brief.md   [ Reveal ›]    │
          │  At a glance: acme-co · Codex · 2 departments · store         │
          │  connected. It carries no secrets and no integrations.        │
          └──────────────────────────────────────────────────────────────┘
          ┌── THE SETUP COMMAND ────────────────────────────────────────┐
          │  claude --skill admin-bootstrap  <points at the file above>  │
          │                              [ Copy the setup command ]      │
          │  This hands Claude Code a plain description of your            │
          │  organization. It carries no secrets. Claude Code checks it    │
          │  with you, then does the work.                                │
          │  When Claude Code says it's done, come back here and run the   │
          │  Setup check.                    When you've pasted it, come  │
          │                                  here to wait ›               │
          └──────────────────────────────────────────────────────────────┘
FOOTER    [Back]                                       [ Open Terminal ]
```

**The four mechanics, in detail:**
1. **Final enumeration + never-destroy placement.** The never-destroy promise is pinned above the enumeration so "is it safe?" is answered before Earl reads what will happen: `This adds and updates. It never deletes or overwrites anything already there.` (sd A6). The enumeration is the same real names from Describe (now `codex-copilot*` for acme-co), plus the org setup file, the read-by-default change, the harness, and the store state (connected, or "not connected yet" if deferred).
2. **The standup-brief story.** The brief is a markdown file at a known path (ratified §7.2). The card presents three honest facts: it exists (mono path), you can read it (a Reveal affordance opening it in Finder), and what it contains at a glance (org, harness, N departments, store state) plus `It carries no secrets and no integrations.` (there are no integration declarations to carry).
3. **The copyable command block.** One monospaced line in a `surface.field` block, with **Copy the setup command** as the prominent affordance physically attached to the command (Fitts). *Microinteraction (Copy):* trigger = click Copy; rules = the string goes to the clipboard, the app fires nothing; feedback = the label swaps to `Copied` for ~2s then fades (no toast); loops = re-copyable. The exact command shape and brief path are a TA contract item, shown as placeholders.
4. **Transition to waiting + the return instruction.** Two honest paths, no forced self-report: **Open Terminal** (footer) opens Terminal.app and advances the app to the Handed off resting state; the copy-only path uses the quiet `When you've pasted it, come here to wait ›` affordance (the Handed off sidebar item is also freely navigable). The return instruction is on the surface: `When Claude Code says it's done, come back here and run the Setup check.` (sd A6). The primary is **Copy the setup command**, never "Set up my org."

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| idle | Never-destroy promise + enumeration + brief card + command block | Copy the setup command | `Setup runs in your terminal, with Claude Code. Copy the line below, open your terminal, and paste it. Claude Code will walk you through the rest and check everything with GitHub as it goes.` (sd A6) |
| copied | Copy button label swaps to `Copied`, fades after ~2s | Open Terminal / go to wait | `Copied` (copy deck 2.5.1) |
| brief-write failure (retry) | An honest holding line replaces the brief card + command; command withheld | Try again | `I couldn't write the setup file, so I won't hand off a command that points at nothing. Try again.` [cw] |
| open-terminal | Terminal launches; app advances to Handed off | (advances) | `When Claude Code says it's done, come back here and run the Setup check.` (sd A6) |

**Annotation pair**
- *What Earl does and sees:* Earl sees the full, concrete list of what will be created, topped by a promise that setup only adds and never deletes. He sees the app wrote a plain file describing his org that he can open and read, carrying no secrets and no integrations. He copies one command, opens his terminal, and reads that Claude Code will check everything with him and with GitHub. It reads like a confident pass to a capable teammate.
- *What actually happens:* The app assembles the collected inputs and writes the non-secret standup brief to a known path as a markdown file (org slug, harness choice, department list, and, if connected, the store endpoint and team-to-scope mapping; no integration declarations and no secrets). It generates a copy-to-clipboard command that starts Claude Code with the admin-bootstrap skill pointed at that brief. The app fires zero GitHub mutations. The brief is a starting point, not a contract: the skill re-confirms with Earl and may diverge; GitHub truth wins and the Setup check reveals drift. If the brief cannot be written, the app withholds the command.

**Keyboard/VoiceOver:** the command is `.textSelection(.enabled)` in a VO group; Copy is the prominent action with a "Copied" confirmation announced politely; Reveal announces "Reveal the setup file in Finder"; the return instruction reads as text; Open Terminal is a footer button. Brief-write failure is an honest holding announcement, never a raw disk/permission string.

---

### Surface 9 — Handed off (terminal in progress)  **[novel piece, double depth, the blind resting state]**

**Purpose:** an honest blind resting state while the terminal works, and the one way back. Renders an honest "can't see the terminal" state; collects the intent to verify. **The app executes nothing and cannot see the terminal.**

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Setup is running in your terminal
INTRO     Claude Code is setting up your organization now.
CONTENT   ┌─────────────────────────────────────────────────────────────┐
          │        (calm, still resting state — no spinner)              │
          │   This app can't see your terminal, so it won't guess how    │
          │   it's going. When Claude Code says it's done, run the        │
          │   Setup check and this app will read the result straight      │
          │   from GitHub.                                                │
          │                  [ Run the Setup check ]                     │
          │   You can close this. Your organization's setup lives on      │
          │   GitHub, and the Setup check reads it fresh every time.      │
          └──────────────────────────────────────────────────────────────┘
```

**Why blindness is honest here, not abandoning:**
- **No fake spinner, ever.** The surface must not show a progress indicator, because that would fake seeing a terminal the app is blind to. **Stillness is the honesty.** The resting state is visually calm and static; "I can't see, so I won't guess" *is* the reassurance. One restrained ambient option is offered to uid: a very slow breath on a purely decorative element (the wordmark/glyph), explicitly not on anything that reads as progress, and droppable under Reduce Motion. Default is fully still.
- **A single action.** **Run the Setup check** is the only actionable control; there is no "how's it going?" affordance because the app has no honest answer.
- **Close-safe reassurance, always visible.** `You can close this. Your organization's setup lives on GitHub, and the Setup check reads it fresh every time.` (sd A7).

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| resting | The still honest waiting state; the one action | Run the Setup check | `Setup is running in your terminal. Claude Code is setting up your organization now. This app can't see your terminal, so it won't guess how it's going. When Claude Code says it's done, run the Setup check and this app will read the result straight from GitHub.` (sd A7) |
| close-safe reassurance | Pinned reassurance under the action | (close is safe) | `Your organization's setup lives on GitHub, and the Setup check reads it fresh every time.` (sd A7) |

**Annotation pair**
- *What Earl does and sees:* Earl is back in the app while Claude Code works in his terminal. The app doesn't pretend to watch; it says plainly it can't see the terminal and won't guess, and points at the one true way to know: run the Setup check when Claude Code says it's done. He's told he can close the app safely because the truth lives on GitHub.
- *What actually happens:* The app renders a static resting state and executes nothing; it cannot and must not read the terminal's report. Meanwhile the script (driven by Claude Code) runs the ordered, additive, idempotent GitHub sequence in the terminal, naming the spaces by the chosen harness. The app's only collected intent is "verify," which shells the read-only verify verb on the next surface.

**Keyboard/VoiceOver:** the resting copy is a VO container read once on entry (not a live region, since nothing changes); Run the Setup check is `.defaultAction`; the close-safe line reads as reassurance. No progress element exists to mislead a VO user into expecting completion announcements.

---

### Surface 10 — Setup check (post-run verification, from GitHub truth)  **[novel piece, double depth, the drift note]**

**Purpose:** post-run verification from GitHub truth; red/green, owner-named, count-never-score; reveal drift. Renders `{check, status, detail, owner}` rows and a plain count. **Computes no verdict.** Serves A8 and C1 verify.

**Layout**

```
EYEBROW   ONBOARDING
TITLE     The setup check
INTRO     An honest look at what's really on GitHub now. Every red names
          who has to fix it.
CONTENT   This reads what's really on GitHub, not what you typed here. If
          setup did more or less than your plan, you'll see it below.
          ┌─────────────────────────────────────────────────────────────┐
          │  ✓  Your org's three spaces exist, read-only by default  Ready│
          │  ✓  Accounting: three spaces exist                       Ready│
          │  ✓  Sales: three spaces exist                            Ready│
          │  ✗  Sales team can reach its spaces        Admin   [Go fix ›] │
          │  ●  IT: three spaces exist                                    │
          │        This wasn't in your plan. Setup added it, and that's   │
          │        fine.                                                  │
          │  ✓  Your organization's setup file reads cleanly         Ready│
          │  ◌  Shared store                          Admin   [Connect ›] │
          │        Not connected yet. Shared integrations can't work       │
          │        until you connect one. You chose to do this later.      │
          └──────────────────────────────────────────────────────────────┘
          SUMMARY   1 thing must be fixed. Nothing couldn't be checked.
FOOTER    [Run it again]                              [ Continue → Done ]
```

**The drift note and the store row, in detail:**
- **"This reads GitHub, not what you typed"** renders as a persistent note under the title, framing the whole list: `This reads what's really on GitHub, not what you typed here. If setup did more or less than your plan, you'll see it below.` [cw, from sd A8]. GitHub is labeled the source of truth, so a disagreement never reads as the app being wrong.
- **Beyond-plan items present as present-not-error.** A thing on GitHub the brief didn't declare (Earl added IT in conversation, or set up the second harness's spaces) renders as a **present** row, a neutral/green `●` + the item name + a quiet caption `This wasn't in your plan. Setup added it, and that's fine.` [cw]. No owner, no fix, no warning color, because the standup is additive and GitHub is authoritative.
- **The store row reads honestly by cause (the ripple decision this asks me to make).** Three renderings, and the deferred case is the new one:
  - *connected + answers* → `✓` green + `Ready`.
  - *connected + unreachable* → `✗` red (or `?` unknown if the check itself couldn't run) + owner **IT infra**, because a store that was connected and now fails is a real problem.
  - *deferred (Earl chose "later")* → a **neutral "not connected yet" mark** (`◌`, `content.secondary`, never red and never `unknown`-orange), owner **Admin**, with the plain consequence `Not connected yet. Shared integrations can't work until you connect one. You chose to do this later.` [cw] and a **Connect** action that jumps to the governance "Connect the shared store" surface. This row is **not counted as a "must be fixed"** (deferral was a valid choice), so the summary excludes it; it is surfaced so it's never forgotten. This is a fourth honest row state alongside pass/fail/unknown, flagged for uid.
- **The count never scores.** Summary is a plain count of what must be fixed and what couldn't be checked; beyond-plan present rows and the deferred-store row are excluded from both counts. `1 thing must be fixed. Nothing couldn't be checked.` / when clean `Everything's ready to hand over.`

**Microinteraction (row resolution):** *Trigger:* Run the Setup check. *Rules:* the app shells a read-only verify verb; rows arrive and resolve progressively. *Feedback:* each row fills in place (shape + color + text; a polite VO live region announces "check name, status, owner"); the count updates as a live region. *Loops:* a re-run against an already-standing org reads as a column of green with a plain count (never-destroy legible here); an Admin-owned red offers `Go fix this`, jumping to the surface that authored the offending input.

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| empty (never run) | The drift note + a Run CTA, no rows | Run the setup check | `Run the setup check before you hand this over. It catches blockers before your organization does.` (copy deck 3.8) |
| working | Rows fill progressively (no ETA) | (in progress) | `Checking what's really on GitHub...` [cw] |
| done (count + owners) | All rows resolved; the plain count summary | Continue → Done (when clean) / Run it again | `1 thing must be fixed. Nothing couldn't be checked.` / when clean `Everything's ready to hand over.` (sd A8) |
| beyond-plan present | A present row with the calm caption, not counted | (none required) | `This wasn't in your plan. Setup added it, and that's fine.` [cw] |
| store not-connected (deferred) | A neutral `◌` row, owner Admin, not counted, with a Connect jump | Connect a store | `Not connected yet. Shared integrations can't work until you connect one. You chose to do this later.` [cw] |
| unknown (never green) | `?` orange row + owner | Run it again | `Couldn't check this` (copy deck 3.8) |
| Admin-red `Go fix this` | The red row expands to a fix jump | Go fix this | (owner chip `Admin`) + `Go fix this` (copy deck 3.8) |

**Annotation pair**
- *What Earl does and sees:* Earl runs the Setup check and gets an honest red and green list of what's really on GitHub now, one row per thing, each red naming who has to fix it. A note tells him this reads GitHub, not what he typed, so a department Claude Code added in conversation shows up as present and fine, not an error. A store he deferred reads as "not connected yet, you chose to do this later," with a Connect jump, never a red failure. A plain count replaces any score, and a re-run reads green.
- *What actually happens:* The app shells a read-only verify verb that reads GitHub truth and the store's reachability and emits `{check, status, detail, owner}` rows. The app renders; it computes no verdict. Unknown is never green (fail-closed). The verify verb compares what the brief declared (org, harness, departments, and, if set, the store pointer) against GitHub truth: declared-but-missing is red (owner named), present-beyond-plan is shown as present, and a deferred store (no pointer in the brief) is a neutral not-connected row, not a failure. Owners named: Admin for repos, grants, and connecting a deferred store; GitHub org owner for base permission; IT infra for a connected store that won't answer; ENAC/external for the foundation reference.

**Keyboard/VoiceOver:** each row is a VO element announcing "check name, status, owner" with status always in the label (never color/shape alone); the drift note reads once as framing; the count summary is a live region; a red row's `Go fix this` and the deferred-store row's `Connect` are focusable and jump to the right surface.

---

### Surface 11 — Done, and what now

**Purpose:** confirm calmly; point to inviting via GitHub and to the user-face app. Renders next steps and deep links out; collects nothing. **No celebration.**

**Layout**

```
EYEBROW   ONBOARDING
TITLE     Your organization is set up
INTRO     The spaces exist, the teams can reach them, and your setup file is
          in place. Two things to do next.
CONTENT   ┌── INVITE THE TEAM, ON GITHUB ───────────────────────────────┐
          │  People join a department by being added to its team on      │
          │  GitHub. Add someone to the Sales team and they can join      │
          │  Sales from their own copilot. This app never manages people. │
          │  GitHub does.                        [ Open your teams ›]     │
          └──────────────────────────────────────────────────────────────┘
          ┌── POINT USERS AT THE APP ───────────────────────────────────┐
          │  Your team installs Copilot Control Tower themselves, and it  │
          │  sets them up from what you just built. Send them the app,     │
          │  and they'll see the departments they're on.                  │
          └──────────────────────────────────────────────────────────────┘
```

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| done | Calm confirmation + the two forward blocks + deep link | Open your teams (out) | `People join a department by being added to its team on GitHub. Add someone to the Sales team and they can join Sales from their own copilot. This app never manages people. GitHub does.` (sd A9) |

**Annotation pair**
- *What Earl does and sees:* Earl gets a calm confirmation, not a trophy: the spaces exist and the teams can reach them. Then the two real next things: invite people by adding them to teams on GitHub (with a link straight there), and hand his team the app, which sets each person up from what he built.
- *What actually happens:* Pure render, plus deep links out to the org's teams on github.com. The app triggers nothing and manages no people.

**Keyboard/VoiceOver:** the two blocks are VO containers; `Open your teams` announces "opens github.com in your browser." No celebratory sound or toast.

---

## 3. Governance surfaces (12-16)

### Surface 12 — Add a department, or the second harness (safe re-run)

**Purpose:** entry to steady-state; frame the safe re-run, then route into Describe. Routes into Surface 5 for a new unit or the second harness; reuses Review (8), Handed off (9), Setup check (10).

**Layout**

```
EYEBROW   GOVERNANCE
TITLE     Add a department
INTRO     Add a department here. Setting up again only adds what's new and
          never touches what's already there.
CONTENT   ┌─────────────────────────────────────────────────────────────┐
          │  Your organization already has: Accounting, Sales, on Codex. │
          │  Add a new department and you'll see the plan for just its    │
          │  three spaces and its team. You can also add Claude Code       │
          │  alongside Codex for the whole organization; it only adds the │
          │  new claude-copilot spaces and leaves everything else alone.  │
          └──────────────────────────────────────────────────────────────┘
          [ Describe the addition ]   → opens Describe (Surface 5)
```

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| idle | The safe-re-run framing + existing departments and harness listed | Describe the addition | `Add a department here. Setting up again only adds what's new and never touches what's already there.` (sd C1) |
| re-run (reuses 5, 8, 9, 10) | Routes into Describe with existing departments/harness pre-filled and locked, only the addition editable | Continue (through the same flow) | (Describe's plan card shows only the new unit's block, or the second harness's spaces, animating in) |

**Annotation pair**
- *What Earl does and sees:* Earl returns to add "IT," or to add Claude Code alongside Codex for the whole org. He's told plainly that setting up again only adds what's new and never touches what's already there. He describes just the addition, sees the plan for its spaces (and team, for a department), and hands off exactly as before. The green re-run answers the "will this break what works?" fear after the fact.
- *What actually happens:* The app frames the safe re-run and routes into Describe for the addition, writing an updated brief. The same idempotent script runs; everything already present narrates as already-there, and only the new unit's spaces/team/grant/setup-file entry, or the second harness's `claude-copilot*` spaces, are created. The Setup check afterward reads green for the existing org and green for the addition.

**Keyboard/VoiceOver:** governance source-list item; the existing-state list is read-only VO text; the CTA announces "Describe the addition, continues into the setup flow."

---

### Surface 13 — Someone left (instructional guidance, not management)

**Purpose:** instructional guidance for a leaver; render the person's teams and the named keys to rotate. Renders teams + tied key names; **triggers nothing.** No offboard button.

**Layout**

```
EYEBROW   GOVERNANCE
TITLE     Someone left
INTRO     This app doesn't manage people. When someone leaves, remove them
          from their teams on GitHub. Then rotate the keys those teams could
          reach in your shared store, so their old access is worthless.
CONTENT   Who left    [ octocat                    ]  (look up)
          ┌── TEAMS THEY WERE ON (remove them on GitHub) ───────────────┐
          │  Accounting team          [ Open on GitHub ›]                │
          │  Sales team               [ Open on GitHub ›]                │
          └──────────────────────────────────────────────────────────────┘
          ┌── KEYS TO ROTATE (in your shared store) ────────────────────┐
          │  SALESFORCE_API_KEY   (Sales)          [ Open the store ›]   │
          │  NETSUITE_TOKEN       (Accounting)     [ Open the store ›]   │
          └──────────────────────────────────────────────────────────────┘
```

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| idle | The guidance + a person lookup field | (look up) | `This app doesn't manage people. When someone leaves, remove them from their teams on GitHub. Then rotate the keys those teams could reach in your shared store, so their old access is worthless.` (sd C2) |
| render (teams + keys) | Two read-only lists: teams to remove-on-GitHub, keys to rotate-in-store | Open on GitHub / Open the store (out) | (list content; both lists deep-link out; the app triggers nothing) |
| unreadable | An honest holding line replaces the lists | (retry) | `I couldn't read the result of this, so I won't guess.` (copy deck 3.9) |

**Annotation pair**
- *What Earl does and sees:* Earl looks up the person who left. The app shows exactly which teams they were on and which named keys those teams could reach, with links straight to GitHub and to the store. There's no "offboard" button, because the app can't and shouldn't remove a person; instead it names precisely what to do and where, so nothing is missed.
- *What actually happens:* The app reads the person's team membership and, to name the keys to rotate, reads the registries of the spaces those teams could reach (registries name the required keys) together with the store's team-to-scope mapping. It triggers nothing. The acts happen elsewhere: team removal on github.com, key rotation in the store's own UI. Content already on a departed person's disk is not remotely wiped (accepted residual); the guarantee is revoked access plus rotated keys.

**Keyboard/VoiceOver:** the lookup is a labeled field; each list is a VO group ("Teams they were on", "Keys to rotate"); every row's action announces "opens on GitHub" / "opens the store." No control here mutates anything; VO announces the lists as read-only guidance.

---

### Surface 14 — Connect the shared store (the deferred / governance case)  **[new surface]**

**Purpose:** the governance home for connecting a store, for the org that deferred at standup or is adding one before its first integration ships. Reuses the A5 educate-and-connect form for one mental model. **A collect surface whose write is authored by the script through a hand-off**, deliberately distinct from the read-only Org setup summary.

**Layout** (the exact educate-and-connect form from Surface 7, with a hand-off footer)

```
EYEBROW   GOVERNANCE
TITLE     Connect the shared store
INTRO     Connect the store that holds your organization's shared keys. Your
          integrations will need it before they can work. A shared secret
          store hands out keys by GitHub team, so a key never lives in a repo
          or in this app.
CONTENT   Store type          [ Infisical  ▾ ]
          Store address       [ https://vault.acme-co.com          ]
                              This is a web address, not a secret.
          Which teams can use it   Accounting → [ acct scope  ▾ ]
                                   Sales      → [ sales scope ▾ ]
          ┌── HOW THIS IS ADDED ────────────────────────────────────────┐
          │  This adds your store pointer to your organization's setup.   │
          │  It never deletes or overwrites anything already there.       │
          │  Claude Code makes the change in your terminal, the same way   │
          │  it set up your organization.                                 │
          └──────────────────────────────────────────────────────────────┘
FOOTER    (no Back needed)              [ Copy the command to add it ]
```

**How Review/hand-off applies when only the store is being added:** connecting here produces a **small re-run brief** carrying only the store pointer (endpoint + team-to-scope mapping). Rather than a full Review surface, this surface folds the never-destroy promise and the copyable command inline (the change is small and single-purpose), then routes through the same **Handed off** resting state and **Setup check**, where the store row flips from the neutral "not connected yet" to green `Ready` (or names IT infra if the store won't answer). One mental model, one baton pass, minimal brief.

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| educate | The what-and-why on screen before the form | (read) | `A shared secret store hands out keys by GitHub team, so a key never lives in a repo or in this app.` [cw, from sd A5] |
| connect (form) | The guided form (type, address, team scoping) | Copy the command to add it | (address helper) `This is a web address, not a secret.` (sd A5) |
| secret-shape refusal | Field shows the firm-but-plain error; value blocked | fix the value | `That looks like a secret. This setting never holds secrets. Secrets live in the store itself, or in your keychain, never here.` (sd A5) |
| ready to hand off | The never-destroy promise + the small-re-run command block | Copy the command / Open Terminal | `This adds your store pointer to your organization's setup. It never deletes or overwrites anything already there.` [cw] |
| connected via hand-off | Routes to Handed off then Setup check; store row goes green | Run the Setup check | (Setup check store row) `Ready` |

**Annotation pair**
- *What Earl does and sees:* Earl (who deferred the store, or is adding one before the first integration ships) sees the exact same educate-and-connect form he'd have seen during standup, so there's one mental model. He fills it in, copies a command, and hands off; the change is small (just the store pointer) and additive, and the Setup check confirms the store now answers.
- *What actually happens:* The app collects the store type, address, and team-to-scope mapping (secret-shape refusal on every field) into a small re-run brief and hands off to the script, which adds the store pointer to the org setup file additively. The app authors nothing directly; connecting is a write, which is why this is its own surface and not folded into the read-only Org setup summary.

**Keyboard/VoiceOver:** `FocusState` chain identical to Surface 7; the secret-shape refusal announced firmly; the command is `.textSelection(.enabled)` with Copy + "Copied"; the hand-off note reads as text. This surface is a governance source-list item, announced as a collect-and-hand-off surface.

---

### Surface 15 — Org setup (read-only summary)

**Purpose:** show everything the org distributes; assert it is inherited and not editable here. Renders the parsed org setup (components, harness, departments, versions, store pointer) and a read-only roll-up of the departments' published integrations. Collects nothing. Merges the old store-config panel.

**Layout**

```
EYEBROW   GOVERNANCE
TITLE     Your organization's setup
INTRO     Everything your organization hands out, in one place. This comes
          from your organization's setup on GitHub. It isn't editable here,
          by design.
CONTENT   ┌── COPILOTS & HARNESS ───────────────────────────────────────┐
          │  Harness: Codex.  Codex · Knowledge · CLI   (versions shown) │
          ├── DEPARTMENTS ──────────────────────────────────────────────┤
          │  Accounting · Sales                                          │
          ├── PUBLISHED INTEGRATIONS (from the departments' registries) ─┤
          │  None published yet.                                         │
          ├── WHERE YOUR SHARED KEYS COME FROM ─────────────────────────┤
          │  Not connected yet.  Connect one before your first shared     │
          │  integration can work.            [ Connect the store ›]      │
          └──────────────────────────────────────────────────────────────┘
```

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| render | The four read-only sections filled from the org setup file + registry roll-up | (none; read-only) | `This comes from your organization's setup on GitHub. It isn't editable here, by design.` (sd C4) |
| store connected | The store section shows the endpoint (read-only) | (none) | `Where your shared keys come from` (copy deck 3.11) |
| store not connected (deferred) | The store section states the honest not-connected line + a jump to Connect the shared store | Connect the store (jumps to Surface 14) | `Not connected yet. Connect one before your first shared integration can work.` [cw] |
| no integrations published | The integrations section states the honest empty | (none) | `None published yet.` [cw] |

**Annotation pair**
- *What Earl does and sees:* Earl sees one read-only place with everything his organization distributes: its copilots and the harness it builds with (Codex), its departments, any integrations its engineers have published, and where its shared keys come from, or that no store is connected yet, with a jump to connect one. It's plainly labeled as coming from GitHub and not editable here.
- *What actually happens:* The app renders the parsed org setup file (`ecosystem.yml`, which carries components, harness, departments, versions, and the store pointer only) plus a read-only roll-up of the per-repo registries. Nothing is editable; security-sensitive config is honored only from inherited signed org config, never re-pointed from the app. Connecting a store from here is a jump to the dedicated write surface (14), not an edit in this read-only view.

**Keyboard/VoiceOver:** four VO sections read as labeled groups; values are read-only VO values (not tab stops); the not-editable note reads as framing; the `Connect the store` jump is the one focusable action.

---

### Surface 16 — Analytics

**Purpose:** off-by-default usage data with a read-only "what would share." Collects the opt-in switch; renders what would be sent. No dark pattern.

**Layout**

```
EYEBROW   GOVERNANCE
TITLE     Usage data
INTRO     Off. Nothing is shared unless you turn this on and your
          organization signs off on it.
CONTENT   [ ○ ] Share anonymous usage data
          ┌── WHAT THIS WOULD SHARE ────────────────────────────────────┐
          │  (read-only list of exactly what would be sent)              │
          └──────────────────────────────────────────────────────────────┘
```

**Interaction states**

| State | On-screen change | Primary action | User-facing line |
|---|---|---|---|
| off (default) | Switch off; the "what would share" list read-only | Toggle on | `Off. Nothing is shared unless you turn this on and your organization signs off on it.` (copy deck 3.10) |
| on | Switch on; the same list, now active | Toggle off | `Share anonymous usage data` (copy deck 3.10) |
| what-would-share | Read-only enumeration of what would be sent | (none) | `What this would share` (copy deck 3.10) |

**Annotation pair**
- *What Earl does and sees:* Earl sees a plain switch, off by default, with an honest read-only list of exactly what would be shared if he turned it on. Nothing nudges him toward on.
- *What actually happens:* The app collects the opt-in switch state locally and renders the "what would share" list. Off by default; nothing is shared unless Earl turns it on and the org signs off.

**Keyboard/VoiceOver:** the switch is a labeled `Toggle` announcing on/off; the "what would share" block is a read-only VO group.

---

## 4. Journey B: the Integrations surface is education-only

The Integrations surface (Surface 6) serves both the standup teach moment and the wider Journey B, and its shape is now education-only. Two enforcement rules make that structural, not incidental:

- **Education leads, and there is no input anywhere.** The model (what an integration is, the cascade, where the key lives) is above the fold; the "How integrations will arrive" lifecycle preview and the honest ending follow. There is no declaration form and no secret-shape refusal on this surface at all, because the admin declares nothing. Absence-equals-non-existence now lives in the per-repo registries, gated by entitlement, not in a central declaration.
- **The future-state preview can never be mistaken for a live control.** The registry mock sits in a distinct, clearly-labeled preview frame (`PREVIEW · not live`), is fully inert (no tab stops, no buttons, no hover/focus, no cursor change), uses obvious example data, and is announced to VoiceOver as "Preview, example only, not interactive." A first-time reader learns *what an integration is here* and *why there's nothing to switch on today* before anything asks for input, and the layout makes that order non-optional.

This is the fix for the old mystery, correctly relocated: the admin's job is to understand and to point engineers at the model, not to configure a catalog.

---

## 5. Flow map

One compact diagram of the full journey, including the two exits from the app (to the terminal at Review and at Connect-the-store; to github.com / the store UI from governance) and the re-entries (Setup check). Worked example: `acme-co`, a Codex shop, with Accounting and Sales.

```
  APP  (Admin window, onboarding progression)
  ─────────────────────────────────────────────────────────────────────────
  Orientation(teach ecosystem, Learn more) → Prerequisites → Contacts →
     Connect GitHub(advisory) → Describe your org(harness + live plan) →
     Integrations(education only) → Secret store(connect or DEFER) →
     Review and hand off
                                                              │
                                        EXIT 1  copy command  │  (app writes brief:
                                        ▼  ───────────────────┘   org, harness, depts,
                              ┌──────────────────────────┐        store-if-connected;
                              │  TERMINAL / Claude Code   │        no integrations, no secrets;
                              │  (the app is blind here)  │        fires no mutation)
                              └──────────────────────────┘  runs the additive,
                                        │                    idempotent GitHub standup
                              Handed off (blind resting state, no fake spinner)
                                        │
                        RE-ENTRY  "Run the Setup check"
                                        ▼
                              Setup check  ⇄  (re-run reads green)   ── reads GitHub truth
                                        │        │        │
                                        │        │        └── deferred store → "not connected yet" → Connect ›
                                        │        └── Admin-red → Go fix this → source surface
                                        ▼
                                      Done  → EXIT (deep links: invite on GitHub, hand out the app)

  GOVERNANCE  (occasional, no progression marks)
  ─────────────────────────────────────────────────────────────────────────
  Add a department / second harness → re-enters Describe → Review → EXIT 1 (terminal) → Handed off → Setup check
  Someone left        → EXIT 2  → github.com (remove from teams) + store UI (rotate keys)   [app guides, triggers nothing]
  Connect the store   → collect the store pointer → EXIT 1 (small re-run brief) → Handed off → Setup check (store → green)
  Org setup           → read-only render (source: ecosystem.yml + registries; store may read "not connected yet")
  Analytics           → local opt-in toggle
```

**The exits and re-entries, named:**
- **Exit 1 (to the terminal), at Review and at Connect the store:** the app writes a brief (a full one at standup, a small store-pointer-only one for the deferred store) and hands over a copyable command; it fires no GitHub mutation.
- **Exit 2 (to github.com / the store UI), from Someone left:** the app renders what to do and deep-links out; it triggers nothing.
- **Re-entry (Setup check):** the single honest way back from the blind terminal phase; the app reads GitHub truth and renders it, including the honest deferred-store row.

---

## 6. Routing and flags

**Flagged for cw (new lines to finalize in the copy deck):** the Orientation title and the two explainer-view prose/example lines; Connect GitHub `Not checked yet` / `Your GitHub access can set up acme-co` / the degraded line; the harness reassurance is drafted in the sd but the segmented-control label and the plan-card empty prompt `Type your organization's name to see the plan.` are new; the Integrations registry-mock caption and honest ending; the Secret store `Connected. This will be included when you hand off.` and the connect-or-defer choice labels; the Review brief-write failure line and the "no secrets and no integrations" at-a-glance; the Setup check drift note, the beyond-plan caption, and the **deferred-store row** consequence line; the Connect-the-shared-store hand-off note; the Org setup `Not connected yet` and `None published yet`. The copy deck's Surface 3 (Admin) still reflects the pre-redesign flow (Repositories & teams grant, Seed generator, Policy signers, integration declaration) and needs a pass to conform to the 16 redesigned surfaces.

**Flagged for uid (visual system):** the **theme-aware ecosystem diagrams** (light/dark redraws of the canonical SVG) and their placement in the Orientation explainer StepShell; the Orientation **in-pane push** treatment and its segmented pager; the new **partial/advisory sidebar mark** (`◐` + count) for Connect GitHub; the **harness segmented control** and the coordinated plan-card re-render on switch; the Integrations **future-state preview frame** (a distinct, inert `PREVIEW · not live` container that survives grayscale and is never mistaken for a control); the **deferred-store neutral Setup-check row** (`◌`, a fourth honest row state alongside pass/fail/unknown, never red and never orange); the still **Handed-off** resting state (no progress indicator; at most one droppable ambient breath on a decorative element); the **plan card** / **brief card** as `surface.field` preview blocks (mono repo/team names); the Review **command block** with prominent Copy + "Copied" + secondary Open Terminal.

**Flagged for ta (contract items surfaced by these layouts):** the standup brief now carries the **harness choice** and **no integration declarations**; the **small re-run brief** for the deferred store (store pointer only); the exact copyable command shape and the on-disk brief path (placeholders in Surfaces 8 and 14); the **per-repo registry manifest format** (the JSON document the lifecycle preview and Someone-left key-naming read); the verify verb's **store-row states** (connected-and-answers, connected-and-unreachable, deferred-not-connected) and its drift comparison (declared-but-missing vs present-beyond-plan, including the second harness).

**Inherited discipline (not re-invented):** keyboard and VoiceOver behavior follows the old flow's §13 and interaction-spec §5.9 throughout: source-list sidebar, `FocusState` form chains with Return submitting the section primary, copyable commands as `.textSelection(.enabled)` with Copy + "Copied", `.defaultAction` on primaries, polite live regions for status and resolving rows, refusals announced as VO groups, the handoff header announced on window open, and Reduce Motion cross-fading every transition (no spring). The run-state vocabulary (idle/working/done/degraded/refused) and the roadmap done/current/upcoming grammar carry over intact.

---

*Route to uid for the visual system pass on the flagged pieces (the theme-aware ecosystem diagrams and the Orientation push, the advisory sidebar mark, the harness control, the inert registry-mock preview frame, the deferred-store row, the still Handed-off state, the plan/brief blocks, the Review command block) and to build the HTML mockup walkthrough from these 16 surfaces + annotation pairs. Route to cw for the flagged new strings and the copy-deck Surface 3 conform. Route to ta for the brief shape (harness, no integrations, small store-only re-run), the registry manifest format, and the verify-verb store-row and drift states. The novel pieces (the Orientation ecosystem explainer, the harness-aware plan card, the Integrations lifecycle preview and registry mock, the Review baton pass, the blind Handed-off state, and the Setup-check drift note) are the untested moments; the sd's §7.5 recommendation to run the baton pass past one real operator stands.*
