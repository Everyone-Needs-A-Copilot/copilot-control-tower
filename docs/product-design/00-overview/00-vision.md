# Product Overview

> **Provenance.** A Discovery synthesis, now **re-grounded in primary evidence** — a facilitated
> owner interview with Pablo, 2026-07-06 (`01-research/10-interviews/01-interview-self.md`;
> `scratchpad/interview-ground-truth.md`). That interview **reframed the soul of the product**
> (see "The reframe" below) and this file has been rewritten to lead with it. Supporting engineering
> intent still lives in the docs (`product-brief.md`, `soul.md`, `01-architecture/architecture.md`,
> `02-prd/prd.md`, `04-validation/redteam-use-cases.md`, `reference/ecosystem-use-cases.md`).
> Every foundation stone below carries an honest **Evidence** stamp (TESTED / OBSERVED / GROUNDED /
> HYPOTHESIS / ASPIRATION); inline `<!-- TODO -->` marks genuine open decisions.

> **The reframe (primary evidence, 2026-07-06).** The earlier drafts led with *"close the
> observability gap."* That is the **mechanism, not the soul.** The soul is **democratization: give a
> non-technical person the AI superpowers of a deeply technical one — safely enough to run
> unattended.** Pablo can wield the ecosystem only because he is extremely technically proficient;
> almost no one inside a company can. Control Tower is the one-click bridge that lets someone with
> "absolutely no clue" break out of the paradigm of *only ever using the software IT handed them* —
> to build, answer, and integrate what they need without understanding the technical layers
> underneath. Observability and self-heal are what **earn the right** to run in the background; they
> are not the point.

## Product Name
Copilot Control Tower (short: **Control Tower**)

## Summary
Control Tower is the always-on macOS menu-bar client for the Copilot ecosystem — two faces over one
open-source binary — and its purpose is **democratization: to give a non-technical person a
technical person's AI superpowers, safely, unattended.** *Operator mode* gives a non-technical
person (the **"Bob"** psychographic, the primary consumer) a working, focus-scoped Copilot partner
from one double-click, then **keeps that environment Copilot-ready** — synced and self-healed on a
cadence — for as long as it runs, so a change made once upstream *finds its way onto the machine
quietly, without clobbering personal work.* Bob's "silent first light," followed by an environment
that stays ready on its own, is the hero experience. *Admin mode* — the open-source IT setup/deploy
tool that lets an IT team stand up and deploy the whole ecosystem for their org (seed generator,
MDM-profile generator, preflight validation, fleet dashboard, deployment runbooks) without
hand-editing YAML — is the **enabler** of that experience, not a co-equal product.

> **Evidence stamp.** Claude Copilot delivering value to a team is **TESTED** (several real users on
> Pablo's team). That non-technical teammates cannot reach Knowledge / CLI Copilot unaided is
> **OBSERVED** (those layers are effectively single-user today; the missing Control Tower is why).
> The Admin / IT-operator experience is a **HYPOTHESIS** (no real IT operator has touched it — see
> Target Users). Multi-writer org/dept authoring is a **MODEL-IN-HEAD**; enterprise scale is an
> **ASPIRATION**.

The name is the model. A control tower doesn't fly the plane — it watches every flight, keeps them
coordinated and on schedule, clears them to proceed, and raises the alarm when something is off.
Control Tower is that supervisor role over the ecosystem's `copilot`/`cc` CLI, **never** a second
brain that reimplements what the CLI already does.

## Problem Statement
The Copilot ecosystem already gives a technical person real superpowers — Pablo uses it daily to
write well, check accounting numbers, build software that does parts of his own job, and integrate
data across sources. **But those superpowers are locked behind technical proficiency, and locked to
one person's diligence.** Two problems, one root:

- **The power is undemocratized.** A non-technical employee is stuck in the paradigm of *only ever
  using the software IT handed them.* Reaching Knowledge Copilot or CLI Copilot requires the terminal
  fluency almost no one has; today those layers are effectively **single-user** — only Pablo reaches
  them. `> **Evidence: OBSERVED**` — the missing Control Tower is precisely *why* no teammate can.
- **Keeping it alive is manual and unglamorous.** Pablo holds the whole thing together **by hand** —
  constantly telling Claude Code and Codex to update, syncing systems, and pushing his own changes.
  He runs **two machines**, and every time he touches the laptop he re-updates the framework,
  Knowledge Copilot, and CLI Copilot just to reach parity. *"That shit gets exhausting."* It works
  only because *he* remembers. `> **Evidence: OBSERVED**` (lived daily).
- **Nothing propagates on its own.** A change made once does not land everywhere. There is no
  cadence-based pull that carries foundation / org / department content onto every machine quietly,
  without clobbering personal work. The human *is* the sync layer.

The mechanism that fixes all three — and that earns the right to run unattended on someone else's
machine — is **observability and honest self-heal**, the ecosystem's own **named gap**
(`architecture.md` §9): IT "literally cannot tell a healthy Mac from a bricked one" when machines
drift, fall behind, or lose auth. What that costs today: stalled or mis-provisioned machines that
report false-Healthy (`redteam-use-cases.md` C1, H7, H12); security fixes that don't take because
they depend on a notification Bob never sees (C3); a leaver's materialized company content persisting
silently (C4); and an always-on token-holding auto-updater an enterprise cannot trust because it is
not auditable (`architecture.md` §1). Observability is not the soul — it is the trust that lets the
democratization run in the background.

## Target Users
> **Bob is a PSYCHOLOGY, not a role.** "Bob the Accountant" is a behavioral archetype found in every
> company and every department — IT, HR, and executives can all "be Bob." Accounting is the exemplar
> because accountants are archetypally *not* rule-breakers: they use the software they're given,
> don't deviate, follow standards well, and are **intensely detail-oriented.** Bob is uncomfortable
> with change because change = **loss of control** over the thing he's comfortable with; a new tool
> means he can make a mistake, break something, or be *wrong* — and being wrong could lose
> information, lose the company money, or lose his job. **The fear is professional consequence.**

> **Two consumer psychographics** (the earlier draft collapsed them into one):
> - **(a) The change-averse consumer (Bob)** — reads / consumes; must feel **SAFE** above all. Target
>   emotion: **comfortable AND excited** — the tools give him *"superpowers he's wanted his entire
>   career and is only now getting."*
> - **(b) The trained early-adopter author** — writes org/department content via a markdown editor
>   (Obsidian); more comfortable with the machinery; wants **POWER.** Write access is *earned and
>   gated*, starting with a few innovators and growing as demand rises.

- **Bob — the change-averse non-technical consumer (PRIMARY).**
  `> **Evidence: GROUNDED**` — real people across real companies. Not a developer, no terminal,
  routinely denies OS permission prompts, ignores single nudges, may run Focus/DND. **"Bob is not a
  reliable actor"** is a load-bearing design assumption (`redteam-use-cases.md`, Bob-agency
  recommendation; `prd.md` §13). Asked *at most three* things at setup, interrupted almost never
  after. **Design consequence:** Bob's detail-orientation means he *will catch* any dishonest or
  drifted status — so **"the icon that cannot lie" is survival, not decoration.** One false green and
  a change-averse Bob is gone for good.
- **The trained early-adopter author — the writable-tier consumer.**
  `> **Evidence: MODEL-IN-HEAD**` — the multi-writer authoring loop (Obsidian → save → push → sync)
  has never been run with more than one writer. Authors org / department content (new skills, agents,
  Knowledge Copilot content, CLI Copilot integrations) via a markdown editor; wants power, not just
  safety.
- **The IT / admin operator (Admin mode) — the enabler, not a co-equal product.**
  `> **Evidence: HYPOTHESIS**` — **no real IT operator has ever touched Admin mode, a fleet
  dashboard, or a deprovision.** Whether a real IT admin will trust a dashboard enough to *act* on it
  (vs. wait for Bob to call) is an untested behavioral bet. Modeled as **Earl** (platform lead) and the
  org security team from `reference/ecosystem-use-cases.md` (UC6, UC11), but those personas are
  inferred, not interviewed. Stands up the ecosystem and deploys it via Jamf/Kandji/Intune; wants a
  fleet they can see, trust, and provision without hand-editing YAML.
  <!-- TODO: confirm with Pablo — has any real IT/MDM admin reviewed the Admin-mode flow? -->
- **Pablo — the ecosystem owner / ENAC maintainer, and today the *only* operator.**
  `> **Evidence: OBSERVED**` — authors the foundation layer and keeps two machines in parity by hand.
  Needs the always-on agent to make the ecosystem *safer* to adopt, not riskier — the whole reason
  the app is open source with reproducible builds and two-of-N signing (`architecture.md` §1, §7).

Secondary context personas from `reference/ecosystem-use-cases.md`: **Rosa** (a developer with all
four layers), **Mira** (Finance dept lead), **Dwayne** (independent solo user). Control Tower must not
break their existing CLI workflow — it supervises the same pipeline they run by hand.

## Core Capabilities
- Deliver a working, focus-scoped partner from one double-click (or a silent MDM push).
- Keep every machine synced and self-healed on a schedule, as a **face + supervisor over the CLI**.
- Turn `copilot doctor --json` into a glanceable, per-host menu-bar status that names the failing host.
- Route every event by **actor-competence × reversibility** — auto-act, escalate to IT, or (rarely) ask Bob.
- Give IT an open-source tool + first-class docs to author seeds, generate MDM profiles, preflight,
  and watch fleet health.

## Status
- **Phase:** Design (Discovery)
- **Stack:** Tauri v2 · Rust core + minimal web UI · single process · macOS-first (Windows = later re-skin)

## Forces Map
<!-- Moments Framework, grounded in the owner interview (2026-07-06) §2,4,5,7 — Pablo's own forces. -->

| Force | Description (owner's framing) |
|-------|------------------------------|
| **Push** (away from current) | Keeping the ecosystem alive **by hand**: constantly telling Claude Code and Codex to update, syncing systems, pushing his own changes. Two machines — every laptop pickup means re-updating the framework, Knowledge Copilot, and CLI Copilot just to reach parity. Nothing propagates unless *he* remembers. **"That shit gets exhausting."** And for everyone else: they can't reach Knowledge / CLI Copilot at all, stuck using only IT-approved software in a fixed way. |
| **Pull** (toward new) | Never having to think about it — make a change **once** and never worry whether it landed where it needs to; the system carries it, quietly, on cadence, without clobbering personal work. **"Control Tower ensures my environment is Copilot-ready."** And for Bob: the *superpowers he's wanted his entire career and is only now getting* — build, answer, integrate what he needs without understanding the layers underneath. |
| **Anxiety** (about change) | (1) **"What if it doesn't work?"** — and a *non-technical* person has **no dignified way to recover.** Failure with no path back is the real fear. (2) **Leakage across boundaries** — mixing personal into department/org, or accidentally pushing private personal information into a public/shared place. The data boundary is a trust wall; crossing it by accident is the nightmare scenario. (Underneath, for the security reviewer: an always-on token-holding auto-updater must be auditable — answered by open source + reproducible builds + two-of-N signing + never-destroy + zero bypass flags.) |
| **Habit** (keeping stuck) | Falling back to what they've always used — **the Claude app, ChatGPT, Gemini** — a "useless" generic chat tool. The mistake is defaulting to generic chat for every conversation instead of reaching for the solution-oriented ecosystem, from "what email do I send" to "I'm not getting the report I need — let's actually build one." |

## Inheritance & Propagation Model
<!-- Core mechanism, from the owner interview §3. The write/read hierarchy the tool must operate. -->

The ecosystem inherits down a **four-tier hierarchy — foundation → org → department → personal** —
with a *write/read* split that is gated and **earned, not universal:**

| Tier | Who writes | How it moves |
|------|-----------|--------------|
| **Foundation** | Pablo authors | Published upstream |
| **Org** | A *team* authors — new skills, agents, Knowledge Copilot content, CLI Copilot integrations | Authored in a markdown editor (**Obsidian**) → save → push |
| **Department** | A *smaller, trained* group with write access to that department's repo | Same authoring loop, department-scoped |
| **Personal** | The individual — personal Knowledge Copilot content (e.g. writing styles) | Local; **must never leak upward into a shared/public place** |
| **Everyone else** | *Reads / pulls on a **cadence*** — not real time | Control Tower carries it quietly onto every machine |

**Write access starts with a few trained early-adopters and grows as demand rises.** The tool's core
job: when an authorized person changes foundation / org / department content, it **finds its way onto
every machine automatically, quietly, on cadence — without clobbering personal work.** A manual
"sync now" is an escape hatch; constant per-minute refresh is explicitly *wrong* ("I can rarely
imagine a moment where someone updates something that someone needs right now").

> `> **Evidence: MODEL-IN-HEAD**` — this multi-writer authoring hierarchy has **never been run with
> more than one writer.** It introduces *writable, collaborative tiers*, which strains the current
> "never-destroy / read-only mirrors" safety assumption (see the merge-conflict open problem in
> `10-scope-and-non-goals.md`).

## Jobs to Be Done
- **When** I make a change to foundation / org / department content once, **I want** it to land on
  every machine quietly, on cadence, without clobbering anyone's personal work, **so I can** stop
  being the sync layer and never worry whether it landed. *(Pablo / author — the core job)*
- **When** I'm a non-technical employee handed the ecosystem, **I want** a technical person's AI
  superpowers without understanding the layers underneath, **so I can** build, answer, and integrate
  what I need instead of being stuck with the software IT handed me. *(Bob — the democratization job)*
- **When** it breaks, **I want** the system to either fix it for me or walk me through it, **so I
  can** recover with dignity even though I'm not technical. *(Bob — the recovery job; Anxiety #1)*
- **When** I author or consume across tiers, **I want** a hard wall between personal and shared
  content, **so I can** never accidentally push private personal information into a public place.
  *(both consumers — the leakage job; Anxiety #2)*
- **When** I (a trained early-adopter) want to contribute a skill or knowledge, **I want** to write
  it in a markdown editor and have it sync across the department, **so I can** extend the ecosystem
  without a technical release process. *(author psychographic)*
- **When** I roll the ecosystem out to my org, **I want** to generate the seed and MDM profile from a
  guided tool and preflight it, **so I can** deploy to a fleet without hand-editing config. *(IT —
  HYPOTHESIS: untested with a real operator)*
- **When** a machine drifts or a security fix ships, **I want** it seen and self-healed (the
  vulnerable override auto-suspended), **so I can** trust the fleet without depending on a
  non-technical user noticing a notification. *(IT / ecosystem)*

## The Magic Moment
Bob double-clicks once — and without answering a single technical question (or, on a managed fleet,
without even clicking) he watches a short progress bar and then has a working, company-scoped Copilot
partner: **the superpowers he's wanted his entire career, and is only now getting.** He never sees a
terminal, never edits a config file. From then on the menu-bar icon just sits there, quietly solid,
and — this is the deeper magic — **an authorized change made once, somewhere upstream, simply
appears** on his machine on the next cadence, without his attention and without touching his personal
work. His environment stays *Copilot-ready* on its own. For Pablo the magic is the release from
carrying two machines by hand; for IT (still a HYPOTHESIS) it is the mirror image — upload one
generated `.mobileconfig`, and the fleet self-provisions and reports green on a dashboard that did
not exist before.

## Non-Goals
- **Not a second brain.** No resolution logic, no health scoring, no signature verification, no
  prune/wipe logic lives in the app — that would duplicate a hardened pipeline and create two
  sources of truth (`product-brief.md`; invariant #1).
- **No independent decision-making about systems of record.** Reads happen unprompted; writes
  confirm. It does not replace GitHub, MDM, or Teams/HR directories — it supervises and surfaces
  state that already lives there.
- **Not an AI chat surface / copilot-of-the-copilot.** It renders the CLI's verdict; it does not
  reason about your machine.
- **Windows is deferred**, not designed against — macOS-first; Windows is a later six-shim re-skin.
- **No multi-org-per-machine** in v1 (ecosystem-level, deferred — `prd.md` §1).

## The One Thing
**Essence line (from the owner interview): *keeps your environment Copilot-ready.*** It gives a
non-technical person a technical person's superpowers and quietly keeps the environment that delivers
them ready — synced, healed, current — without the person ever having to think about it. It does this
by **faithfully rendering the CLI's truth and keeping the machine synced and self-healed without ever
computing that truth itself.** If Control Tower vanished, the CLI would still be correct. The moment
the app computes a health verdict, resolves a conflict, or weakens a security check, it stops being a
control tower and becomes a second, untrustworthy pilot — the honesty that earns unattended trust
collapses, and the whole democratization idea fails with it.

## AI Philosophy
Control Tower is a deliberate inversion of the usual "add AI" instinct. **The intelligence already
exists in the ecosystem's CLI; the product's job is to add zero intelligence of its own** and
instead make that intelligence *legible, safe, and always-on* for people who can't run it by hand.
The "smart" part of the system — resolution, health scoring, signature checks, wipes — stays in the
hardened CLI pipeline. Control Tower **parses, it never computes.**

> **AI principle:** Control Tower adds no judgment of its own — it renders the CLI's verdict and
> automates only what is reversible and safe. All computation lives in the hardened pipeline; the
> app is the trustworthy face, not a second brain.

### What the System Does vs. What Humans Do
<!-- "AI/automation" here = the CLI pipeline + Control Tower's deterministic routing. -->

| Automation Provides (CLI + Control Tower routing) | Humans Do |
|---------------------------------------------------|-----------|
| Computes every health verdict, resolution, signature check, prune, wipe (CLI) | Bob approves the one sign-in; commits dirty personal work before a sync |
| Parses `--json`, renders per-host status, keeps machine synced/healed on a schedule | IT authors the seed, approves held-major upgrades centrally, signs capability policy |
| Auto-acts on reversible, un-judgeable changes; escalates what Bob can't action to IT | IT reads the fleet dashboard and preflight report; decides rollout timing |
| Auto-suspends a security-shadowing override (reversible) | Bob may re-affirm an override he still wants |

### Language That Reflects This Principle

| We Say | We Don't Say |
|--------|--------------|
| "Control Tower parses the CLI's verdict and renders it" | "Control Tower determined your machine is healthy" |
| "Watch the fleet," "cleared to proceed," "raise the alarm" | "AI decides," "auto-resolve," "second brain" |
| "Supervises," "surfaces," "re-materializes" | "Computes," "scores," "verifies" (as the app's own act) |
| "Safer than running `copilot update` by hand" | "Trust us, it's automatic" |

### The Magic Test

1. **Would this feel like magic?** Yes — a non-technical person gets a working, team-scoped AI
   partner from one click and it stays healthy untouched; IT stands up a whole fleet from one upload.
2. **Does this create 100x value?** The alternative is per-machine hand-provisioning and a fleet
   nobody can see — Control Tower turns that into a single artifact and a self-healing, observable fleet.
3. **Does this serve the human, or replace them?** It serves — it removes terminal/YAML toil for Bob
   and hand-craft for IT; it never replaces IT's judgment (held-majors, policy) or Bob's ownership of
   his personal data.
4. **Are we anchored on AI as the solution?** Deliberately not — the anchor is *trust and legibility
   of existing intelligence*, and the invariant forbids adding model-driven judgment to the app.
5. **Would we build this even without AI?** Yes — this is a supervision/observability/deployment
   product; that it delivers an AI ecosystem is incidental to *how* Control Tower itself works.

## A+ Capabilities

> **Re-ranking under the reframe.** With democratization (not observability) as the soul, the ranking
> holds but the *reasons* shift: #1 and #2 are the democratization + unattended-trust core and stay
> CRITICAL; **#2 rises in weight** because Bob's detail-orientation makes "the icon that cannot lie"
> *survival, not polish.* **A new #6 (cadence-based propagation without babysitting)** is surfaced by
> the interview as the everyday hero mechanism — "make a change once and never worry whether it
> landed." #3 (Admin mode) and #5 (fleet observability) remain first-class *enablers* but are now
> honestly stamped **HYPOTHESIS** — no real IT operator has touched them.

### 1. One-double-click working partner → democratization entry (CRITICAL)
> `> **Evidence: OBSERVED**` — the CLI-shaped barrier is real; Knowledge/CLI Copilot are single-user today.

**The delight:** A non-technical employee goes from a fresh laptop to a working, team-scoped Copilot
partner without answering a technical question — asked *at most three* things unmanaged, *zero* on a
managed fleet where IT shipped a complete profile.

**Example:** IT pushes the app + `.mobileconfig` via Jamf; Bob's wizard runs silently; he watches a
progress bar and is done (`architecture.md` §4, silent managed path).

**Impact:** Removes the single biggest adoption barrier — that the ecosystem is CLI-shaped and Bob has
no terminal. This is the product's reason to exist for the end user.

### 2. Always-on self-heal with glanceable, honest health — "the icon that cannot lie" (CRITICAL / SURVIVAL)
> `> **Evidence: GROUNDED**` (Bob's psychology) — Bob is intensely detail-oriented and *will catch* a
> drifted or dishonest status. One false green and a change-averse Bob is gone for good. This is not
> decoration; it is the survival condition for unattended trust.

**The delight:** The machine stays synced and healed on a schedule while running, and the menu-bar
icon is an honest projection of `copilot doctor --json` — never false-Healthy, always naming the
failing host in plain language ("Codex needs sign-in; Claude is fine").

**Example:** A partial two-host update fails on Codex; the icon goes amber and the sentence names
Codex, not a blended "needs attention" (`architecture.md` §2, §5; fixes A-M14, H7, H12).

**Impact:** Trust. An always-on agent that runs the *same* pipeline with zero bypass flags is
*safer* than a human running `copilot update` by hand — every pull is visible, verified,
policy-bounded, auditable.

### 3. Admin mode — stand up the ecosystem without hand-YAML (HIGH VALUE / ENABLER)
> `> **Evidence: HYPOTHESIS**` — no real IT operator has ever run Admin mode, preflight, or a fleet
> deploy. The value proposition is sound in the model but entirely untested in the field.

**The delight:** IT authors the org `ecosystem.yml`, scaffolds per-department repos, signs
capability policy, and generates a ready-to-upload MDM profile from a guided flow — then preflights
it end-to-end and gets a red/green report before pushing to the fleet.

**Example:** The MDM profile generator emits one `.mobileconfig` (managed keys + login-item +
notifications payloads) so every employee's wizard runs silent (`architecture.md` §8.1; `prd.md` H1–H6).

**Impact:** Turns a hand-crafted, error-prone one-time setup into a guided, validated, reproducible
deployment — the enablement that lets an enterprise adopt the ecosystem at all.

### 4. Actor-competence × reversibility escalation (DIFFERENTIATOR)

**The delight:** The system never "notifies Bob and hopes." It auto-acts on reversible things Bob
can't judge, escalates to IT what Bob can't action, and asks Bob only when he is the *sole competent
actor about his own data*.

**Example:** A `security:`-trailer fix that a personal override shadows is **auto-suspended** (Bob
can re-affirm) and escalated to IT in parallel — the vulnerable version can't win silently
(`architecture.md` §9; fixes A-C3). Capability-policy denials go to the IT log only, never a Bob
notification (fixes A-M15).

**Impact:** Every alert Bob can't act on burns down the credibility of the one that matters. Routing
by competence, not event-class, is what makes the escalation model actually work — and it's rare in
the category.

### 5. Fleet observability + auditable always-on trust basis (LONG-TERM MOAT / ENABLER)
> `> **Evidence: HYPOTHESIS** (usage) / ASPIRATION (scale).** The dashboard and its acting-on-it
> behavior are untested with a real IT operator; enterprise scale (3 → 600,000) is a flexibility
> aspiration, not a proven capability. Observability is the *mechanism that earns unattended trust*,
> not the product's soul.

**The delight:** IT sees who's healthy, stuck, behind, or needs re-auth on a dashboard — closing the
ecosystem's named observability gap — over telemetry that is opt-in, org-scoped, and PII-minimizing
by construction (a personal item name is *un-emittable*).

**Example:** `machine_id = hmac(hardware_uuid + posix_uid, per-install-random-salt)` — per-user,
non-reversible from MDM inventory; usage emits only CLI-verified {org,dept,foundation} items
(`architecture.md` §9; fixes B-H5).

**Impact:** Observability + open source + reproducible builds + two-of-N signing is the trust basis
an enterprise security review demands. It's the moat: the thing a competitor can't bolt on later
without the same invariant discipline.

### 6. Cadence-based propagation without babysitting — "keeps your environment Copilot-ready" (CRITICAL / EVERYDAY HERO)
> `> **Evidence: OBSERVED** (the pain) / MODEL-IN-HEAD (multi-writer).** Pablo lives the pain of
> hand-syncing two machines daily; the *multi-writer* propagation loop (Obsidian → push → sync across
> a department) has never been run with more than one writer.

**The delight:** An authorized change made **once** upstream — foundation, org, or department —
simply appears on every machine on the next cadence, quietly, without clobbering personal work. The
consumer never thinks about it; the author never wonders whether it landed. A manual "sync now" is
there as an escape hatch, but real-time refresh is deliberately absent.

**Example:** A department lead edits a Knowledge Copilot file in Obsidian, saves, and pushes; every
machine in that department pulls it on the next sync cadence — no one runs a command, no one's
personal writing-style content is touched.

**Impact:** This is the everyday embodiment of the essence. It is what releases Pablo from being the
sync layer and what makes the ecosystem *extensible by a team*, not just usable by one person. It
also opens the hardest design problem — writable collaborative tiers and non-technical merge-conflict
resolution (see `10-scope-and-non-goals.md`).

## Essential Minimum

| Component | Purpose | Notes |
|-----------|---------|-------|
| CLI `--json` / `flock` / `COPILOT_MANAGED_BY` contract | The whole safety boundary — the app can't supervise a CLI it can't read machine-readably | Lives in `copilot`, not here (WS-A). Bidirectional schema gate; missing security fields fail closed. **Prerequisite for everything.** |
| Single-process Tauri shell + status state machine + menu | Tray, supervisor, scheduler in one signed binary; renders per-host status | No headless daemon, no in-app fallback loop (invariant #2) |
| GUI first-run wizard (silent managed path + fail-closed validation) | Turns Ring-1 phases into a GUI; provisions Bob | Asks ≤3 unmanaged; schema-validate profile → `IT-config-incomplete` on missing key |
| SMAppService login item + `launchd` crash-only watchdog | "Stays on, keeps synced"; self-update rollback | `KeepAlive={SuccessfulExit:false}`, never `true` |
| Actor-competence × reversibility escalation router | Routes every event to auto-act / escalate-IT / ask-Bob | Assumes Bob is not a reliable actor |
| Admin mode: seed + MDM-profile generator + preflight | Lets IT stand up + deploy the fleet | Open source is a *requirement*, not goodwill |

## Ecosystem Context

```
copilot / cc CLI (--json verdicts)   ecosystem.yml seed   MDM managed profile (dev.enac.controltower)
        |                                   |                        |
        |  (parses, never computes)         | (products, pins)       | (org values, forced-domain security keys)
        v                                   v                        v
                        ┌─────────────────────────────────────────┐
                        │           COPILOT CONTROL TOWER          │
                        │   Operator mode  ·  Admin mode           │
                        └─────────────────────────────────────────┘
        |                         |                          |
        v                         v                          v
  materialized .claude/     IT fleet dashboard        generated .mobileconfig + seed
  (via CLI, per host)       (opt-in org telemetry)    → Jamf / Kandji / Intune
                                  |
                                  v
                        content-free safety escalations → IT AdminContact channel
```

Flows **in:** CLI JSON verdicts, the `ecosystem.yml` seed, the MDM managed profile, host detection.
Flows **out:** re-materialized `.claude/` (done by the CLI), org-scoped fleet telemetry to the IT
dashboard, generated MDM profiles/seeds/runbooks (Admin mode) to the MDM vendor, content-free safety
signals to the IT channel. It **does not** replace any system of record — it supervises them.

## Warning Signs (Regression Triggers)

| Request | Why It Is Wrong |
|---------|-----------------|
| "Add health scoring / resolution in the app so it works offline" | Duplicates the CLI, creates two sources of truth — violates *parse-never-compute* (invariant #1) |
| "Let the app edit `.claude/` or resolve conflicts directly" | Same — the CLI owns materialization; the app renders, it doesn't mutate |
| "Add a `--force` / `--skip-verify` to unstick a machine" | *Security posture is inherited and never weakened* (invariant #4) — no lower-bar mode may exist |
| "Let Bob approve a held-major upgrade to clear the badge" | Approval authority is IT's; Bob has no basis to judge (fixes A-H11). Proximity to the menu bar ≠ competence |
| "Set `KeepAlive=true` so it never dies" | Crash-loops a bad build and resurrects after a clean Quit (fixes B-C2) — the watchdog is crash-only |
| "Make it a full chat UI / a second brain" | It's a tower, not the pilot — an AI surface is out of scope by definition |
| "Read `UpdateFeedURL`/`FoundationMirror` from the user domain for convenience" | Supply-chain RCE via preference write (fixes B-C5) — security keys honored only from the forced/managed domain |
| "Notify Bob on every prune / policy denial" | Alert fatigue burns the one alert that matters (C3); route by who can act (fixes A-M15) |

## Acceptance Criteria

### For Users
Bob: *"I double-clicked once and had a working partner scoped to my team. I never opened a terminal
or edited a config file. It just stays working, and it only ever asks me about my own stuff."*

### For the Business
Pablo / ENAC: *"It's **pure open source, free forever** — no paid tier, no enterprise SKU, no hosted
service — and that is exactly why enterprises trust it: open source is both the security requirement
and the go-to-market. It's auditable and MDM-deployable, so enterprises adopt the whole Copilot
ecosystem without friction, and the always-on agent is provably *safer* than a human running
`copilot update` by hand. Success is **adoption, trust, and reliability** — machines running healthy,
security reviews passed, contribution health — never revenue. Every one of the 25 Critical/High
red-team findings is closed."*
<!-- DECIDED (Pablo, 2026-07-06): Business model = pure OSS, no monetization. Control Tower is free
     and open-source forever; its purpose is to drive trust and adoption of the broader copilot/cc
     ecosystem. Open source is both a security *requirement* and the go-to-market. No paid tier, no
     enterprise SKU, no hosted service. "Worth building" is judged by adoption + trust + reliability,
     not revenue. -->

### For the Ecosystem
IT / fleet: *"I stood up and deployed the ecosystem from Admin mode and the docs alone. I can see
healthy-vs-stuck at a glance, every escalation reaches a live channel, and a leaver loses access
reliably even offline — the observability gap is closed."*
