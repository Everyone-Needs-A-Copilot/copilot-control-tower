# Interview 01 — Self-Interview

<!--
FACILITATION GUIDE — Service Designer (Research)
=================================================
Mode: Research artifact (Diátaxis: Reference)

This is a self-interview. You are simultaneously:
- The founder and primary product creator
- The first and primary user (you experience the problem yourself)
- The domain expert (you know the pain intimately)

Self-interviews are valid research artifacts. The goal is to make tacit knowledge
explicit and on the record — so that design decisions are traceable to real
experience rather than assumption.

APPROACH FOR SELF-INTERVIEW:
Write in first person. Be brutally specific. Avoid describing the ideal state;
describe the actual current state, including its embarrassing inefficiencies.

The questions from 00-interview-template.md apply here, adapted for
the self-interview context:

Round 1 — Context:
- Role: Founder / primary operator
- Frequency: How often do you encounter the problem in a typical week or month?
- Current process: Walk through how you handle the problem domain today

Round 2 — Current Reality:
- Where do you currently go to address this problem? (specific sources, tools, workarounds)
- How do you decide whether to invest time in a given instance?
- How do you actually do the work? What tools? What's the workflow?
- How long does a typical cycle take from discovery to completion?

Round 3 — Pain Points:
- What is the part of the process you most dread?
- Where do you lose the most time to manual, repetitive work?
- Have you ever missed something important because of the current process?
- Have you ever wasted significant effort that turned out to be a dead end?
- What information would have changed your decision if you'd had it earlier?

Round 4 — Key Quotes:
- What do you find yourself saying when you describe this frustration to others?
- Is there a phrase or metaphor you use to describe how broken the current process is?

Round 5 — Risks & Takeaways:
- What assumptions about {{PRODUCT_NAME}} users should be checked against other people,
  not just yourself?
- What might be true for you that is NOT true for a typical user of this product?
-->

> **STATUS — rebuilt from evidence 2026-08-02. Describes Copilot Control Tower v0.4.0** (build 19, embedded helper `cc 2.2.0`), the shipping release as of this date. This document replaces a version written 2026-07-17 that carried a superseded MDM/fleet framing. The interview testimony itself is unchanged and preserved verbatim; what has been rebuilt is the surrounding record of *which testimony later evidence confirmed, which it overtook, and what is still unproven*.

---

## Provenance and the quote rule

**This document is a record of the owner's own words. Nothing in it may be invented.** Every quotation below is reproduced verbatim from a dated primary source and is attributed to that date. Where a statement is a summary, an inference, or a decision-of-record rather than something the owner said in those words, it is written as prose and labelled — never dressed up as a quote.

**Where the quotes come from.** The primary source is a **facilitated self-interview with Pablo Alejo, conducted 2026-07-06**, originally transcribed to `scratchpad/interview-ground-truth.md`. That transcript **no longer exists on disk and was never committed** — `scratchpad/` is gitignored, and a search of the full git history across all refs finds no blob at that path. Consequently **this document is now the surviving record of that interview**: the quotes preserved here were carried into the 2026-07-17 version of this file directly from the transcript, and they are preserved here again unchanged. `SOUL.md` (RATIFIED v1.4) independently corroborates the interview's existence, its date, and its central reframe, citing `scratchpad/interview-ground-truth.md` in its own §10 changelog row for v1.1. Treat the 2026-07-06 quotes as **primary evidence at one remove**: faithfully transcribed, no longer independently re-checkable against the transcript.

**Secondary dated testimony** comes from four corroborating classes of record, all of which are traceable and all of which are labelled inline where used: the ratified owner decisions in `SOUL.md` §9 (dated 2026-07-06 through 2026-07-09); the owner-ratification memory entries in this project's session memory (2026-07-10, 2026-07-16, 2026-07-24, 2026-07-25); the Accepted ADRs under `docs/40-initiatives/02-enac-self-onboarding/decisions/` (2026-07-16 through 2026-07-31); and the **ratified owner answers of 2026-08-02** that govern this rebuild. Of these, only two carry verbatim speech; the rest are decisions of record and are written as such.

<!-- TODO: if `scratchpad/interview-ground-truth.md` still exists in any backup, restore it to a committed location. This document currently carries the only surviving copy of its quotes, and that is a single point of failure for the product's primary evidence. -->

---

## Participant

| Field | Value |
|-------|-------|
| Name / alias | Pablo Alejo — ecosystem owner, ENAC maintainer, sole publisher |
| Role | Founder and foundation-layer author of the whole Copilot ecosystem; at v0.4.0 still the primary — and for the Admin face, the *only* — operator |
| Organisation type | Open-source AI-tooling ecosystem ("Everyone Needs a Copilot" / ENAC); positioned for any company from a 3-person team to a 600,000-person enterprise |
| Interview date | 2026-07-06 (primary); dated follow-on ratifications 2026-07-07 → 2026-08-02 |
| Interview format | Facilitated self-interview |
| Conducted by | Pablo (self), facilitated |

---

## The "why" — origin and soul

*What this is actually for, in Pablo's own framing, 2026-07-06.*

The Copilot ecosystem — Claude Copilot, Codex Copilot, Memory Copilot, Task Copilot, Knowledge Copilot, CLI Copilot — gives Pablo, a deeply technical person, a foundation to *consistently* do great work: write well, check accounting numbers, build software that does parts of his own job, integrate data from different places, and make daily progress on hard things.

The pivotal realization is that he can wield this only because he is extremely technically proficient — and almost no one inside a company can. The typical worker uses only the software IT handed them, in a fixed way, and doesn't deviate. The ecosystem is a way to break them out of that paradigm: to let anyone at any company, in his words, *"do tremendous things without the constraints of software and interfaces"* — build, answer, integrate what they need — without understanding the technical layers underneath. *(Quoted fragment, 2026-07-06.)*

> **The reframe, recorded 2026-07-06.** The docs that preceded this interview led with "close the observability gap." That is the *mechanism*, not the soul. The soul is **democratization: give a non-technical person the AI superpowers of a deeply technical one, safely enough to run unattended.** Observability and supervision are what *earn the right* to run in the background — not the point of the product.

Control Tower is the one-click bridge that makes the ecosystem — and its inheritance model, foundation → org → department → personal — usable by someone with "absolutely no clue," runs everything in the background, and when something goes wrong either fixes it for them or walks them through it.

**Status as of v0.4.0: this framing is CONFIRMED and re-ratified, not superseded.** The owner's ratified answer of 2026-08-02 (A-2) states the essence is unchanged from `SOUL.md` v1.4 — a technical person's superpowers in a non-technical person's hands — and explicitly rejects re-centring the product on organizational transformation. Organizations are the buyer; the individual is where the value lands.

---

## Current Process

### As recorded 2026-07-06 — how Pablo kept the ecosystem alive before Control Tower existed

> **Evidence: OBSERVED (lived by Pablo daily).** Not inferred from architecture docs; the participant's actual routine.

Pablo kept the whole thing alive by hand. He was constantly telling Claude Code and Codex to update, syncing systems, and pushing up his own changes. He ran **two machines — a Mac Mini and a laptop** — and every single time he picked up the laptop he had to re-update the framework, Knowledge Copilot, and CLI Copilot *just to reach parity* with the Mini before he could do real work.

> "That shit gets exhausting." *(Pablo, 2026-07-06.)*

It worked only because *he* remembered to do it. There was no propagation: a change made on one machine did not find its way to the other unless he personally carried it. Nobody else on his team operated at that layer at all — they used Claude Copilot (which was TESTED and delivering value), but **Knowledge Copilot and CLI Copilot were effectively single-user**, because reaching them required terminal fluency only Pablo had. The missing bridge *is* Control Tower.

The propagation model he described wanting Control Tower to run: **Foundation** — Pablo authors. **Org** — a *team* authors: new skills, new agents, Knowledge Copilot content, CLI Copilot integrations. **Department** — a *smaller, trained* group with write access to that department's repo. **Everyone else** — reads and pulls on a **cadence**, not in real time. The core job: when an authorized person changes foundation / org / department content, it should find its way onto every machine automatically, quietly, on cadence — without clobbering anyone's personal work. A manual "sync now" exists as an escape hatch, but constant per-minute refresh is explicitly wrong. The authoring surface he described is a markdown editor like Obsidian: load the files and write (or have AI update the docs) → save → push → sync across the department.

### What is actually true at v0.4.0 — what changed, and what did not

The bridge exists and it runs in production on one organization. `docs/40-initiatives/02-enac-self-onboarding/phases/phase-7-live-run-evidence-stage-a.md` records the terminal state: **16 of 16 ecosystem layers live**, a real `cc onboard --apply` writing a 16-layer manifest with every `source.path` populated, exit code 0, byte-verified before and after, three orphaned personal repositories adopted rather than recreated, and zero destructive git operations across three apply attempts. The daily hand-sync of the *content* layers is genuinely gone on that machine. Seven signed, notarized releases are retained under `release/`; v0.4.0 is the eighth version line.

**Three parts of the 2026-07-06 process, however, are not yet resolved, and the record must say so plainly:**

1. **The laptop — the exact machine that produced "that shit gets exhausting" — has not been proven.** The remaining owner-gated acceptance item is **V-5, the two-machine cold-laptop onboarding proof with an empty keychain**. The pain that opened this interview is precisely the pain whose fix is still unverified on the second machine. That is not an incidental gap; it is the original job, unclosed.
2. **The multi-writer authoring loop has still never run with more than one writer.** `SOUL.md` §9 Founding Decision #9 stamped this a HYPOTHESIS on 2026-07-06 and nothing since has upgraded it.
3. **No non-technical teammate has completed onboarding on their own machine.** The Admin face has been exercised, but by the owner. The democratization claim — the soul of the product — remains untested against the persona it exists for.

---

## Tools Used Today

*Two columns of truth: the routine as recorded 2026-07-06, and its disposition at v0.4.0.*

| Tool / Method (2026-07-06) | Purpose | Pain level then | Disposition at v0.4.0 |
|---|---|---|---|
| Manual `copilot update` on the Mac Mini | Pull framework / Knowledge / CLI updates | Medium — worked, but only because Pablo remembered | **Largely absorbed.** The tray polls `freshness` every 300 s and offers `Sync now`; `update --fanout` propagates across projects. Remembering is no longer the mechanism on this machine. |
| Hand re-sync of the laptop on every pickup | Re-update framework, Knowledge Copilot, CLI Copilot to reach parity with the Mini | **High — the daily two-machine tax** | **UNPROVEN.** The mechanism exists; the second machine has not been through it. Open as V-5. |
| Manually pushing his own changes upstream | Get foundation edits off his machine into the repos | High — nothing propagated unless done by hand | **Still manual, and deliberately so.** `cc publish` is formally deferred (ADR-008, Accepted 2026-07-31); the documented substitute is a human-invoked copy → commit → push into the tier repo (`inheritance-and-publish.md`, "Elevating project content today"). Upward movement staying human-invoked is invariant #6, not a shortfall — but the *labour* Pablo described is unchanged. |
| Obsidian (markdown editor) | Author / edit foundation content | Low as an editor — no sync layer behind it | Unchanged. The authoring lane was never built into the app; `SOUL.md` §4 note on primacy says the Operator surface leads and the author lane is a subordinate enabler. |
| *(No tool)* | Propagate a change to every machine on cadence without clobbering personal work | **Highest — the tool did not exist** | **Built.** Pull-only, downward, cadence-based; never-destroy holds a dirty tree, now with a symlink-escape guard after the 2026-07-27 incident (below). |
| *(No tool)* | Let a non-technical teammate reach Knowledge / CLI Copilot at all | **Highest — the CLI-shaped barrier** | **Built and shipped, not yet validated with a non-technical person.** The 9-step wizard, the tray, and Settings exist; no independent user has run them. |

---

## Key Quotes

*Every line below is verbatim. Date and source are attached to each.*

> "That shit gets exhausting." — **Pablo, 2026-07-06**, on hand-syncing two machines. The PUSH force, in one line. *Still the product's founding grievance; still not closed on the second machine (V-5).*

> "Control Tower ensures my environment is Copilot-ready." — **Pablo, 2026-07-06.** The PULL force, and the source of the essence line *"keeps your environment Copilot-ready."* *Carried into `SOUL.md` §2 at v1.1 and unchanged since.*

> "…usable by someone with absolutely no clue." — **Pablo, 2026-07-06**, on who the product is for. *Reinforced 2026-07-24, below.*

> "It's a way to break them out of that paradigm." — **Pablo, 2026-07-06**, on the worker locked into IT-approved software. The democratization thesis in one sentence.

> "do tremendous things without the constraints of software and interfaces" — **Pablo, 2026-07-06**, quoted fragment, on what a non-technical person should be able to reach.

> "Superpowers he's wanted his entire career and is only now getting." — **Pablo, 2026-07-06**, on the target emotion for the non-technical consumer: comfortable *and* excited, not merely unblocked.

> "If it's easy for people to use, people will adopt it, and that is the sign of success." — **Pablo, 2026-07-06.** Success is adoption. *Ratified into `SOUL.md` Founding Decision #3 (trust + adoption + reliability, never revenue) and never revised.*

> "I can rarely imagine a moment where someone updates something that someone needs right now." — **Pablo, 2026-07-06**, on why cadence-based pull is right and real-time refresh is a non-goal. *Shipped literally: a single 300-second timer, with `Sync now` as the manual escape hatch.*

> "In the future, don't ask to fix broken code, functionality, or experiences. Identify them, deal with them, verify them." — **Pablo, 2026-07-25**, recorded verbatim in session memory after a defect whose real cause sat in another repository was diagnosed and then merely *reported*. *This is a working-method ruling, not a product statement, but it belongs in the record: it is why cross-repo defects in `cc` are fixed rather than routed.*

> "You have the tools. Now go change the world!" — **Pablo, 2026-07-16**, the final send-off copy on the wizard's Done screen, recorded as the owner's own words picked from alternates. *An explicit owner override of the product's otherwise flat register — one of exactly three sanctioned emotional peaks.*

**Statements the record contains but which are NOT quotes**, and are written here as inference so they are never mistaken for testimony: that a proposal requiring a user to author or rank a manifest is "wrong on its face, not a design tradeoff" (**owner ratification, 2026-07-24**, paraphrased in session memory, not transcribed speech); that the owner asked for the brand rules to be documented so he would not have to keep repeating them (**2026-07-16**, paraphrased); and the entire set of ratified answers A-1 through A-5 of **2026-08-02** (audience, essence, status, killed technology, invariant-enforcement honesty), which are decisions of record captured in the retrofit brief rather than transcribed speech.

<!-- TODO: confirm with Pablo — a dated first-person anecdote for the first time he handed the ecosystem to a non-technical teammate and watched them fail to reach it. The single-user reality of Knowledge/CLI Copilot is OBSERVED; a specific story would make it the strongest evidence in the file. This TODO has stood open since 2026-07-06 and is now more load-bearing, not less: with the product shipping, an unvalidated primary persona is the largest evidence gap in the product. -->

---

## Pain Points

*Severity is as the owner framed it in 2026-07-06. The status column is evidence as of v0.4.0 — and is where prior testimony is marked superseded.*

| Pain point | Severity | Context (2026-07-06) | Status at v0.4.0 |
|---|---|---|---|
| Keeping two machines at parity is manual and constant | Critical | Every laptop pickup = re-update framework + Knowledge + CLI by hand (OBSERVED) | **Partially resolved, formally unproven.** Resolved in mechanism and demonstrated on the primary machine (16/16 live). The second machine is the open V-5 acceptance item. |
| Nothing propagates unless Pablo personally carries it | Critical | No cadence-based pull; he *was* the sync layer (OBSERVED) | **Resolved for the downward/pull direction.** Not resolved upward, by design: publishing is a separate, human-invoked, distinctly-credentialed act (invariant #6), and `cc publish` is deferred (ADR-008). |
| Non-technical teammates cannot reach Knowledge / CLI Copilot at all | Critical | Requires terminal fluency only Pablo has (OBSERVED) | **Addressed in build, unvalidated in the field.** The wizard, tray, Settings, and Admin app all ship. No non-technical person has completed the journey. This is the product's central open evidence gap. |
| A non-technical person has no dignified way to recover when it breaks | Critical | Anxiety #1: "What if it doesn't work?" — failure with no path back (GROUNDED) | **Designed and shipped as a named surface.** The holding-copy family (H1–H7), five CLI-authored project triage categories including "Couldn't confirm," `Diagnose in Codex` / `Diagnose in Claude Code`, `Copy diagnostic report`, `Copy project-owner handoff`, and per-release Rollback instructions naming the prior signed DMG. Unvalidated with a real non-technical person. |
| Personal content can leak into a shared / public place | Critical | Anxiety #2: the data boundary as a trust wall (GROUNDED) | **Closed by construction, and independently reinforced.** Separate trees, separate remotes, pull-only downward sync with no upward credential on the automated path, secrets never in any git repo, fail-closed leak scan as backstop (`SOUL.md` Founding Decision #10; `CLAUDE.md` invariant #6). |
| Two non-technical colleagues editing the same file → merge conflict, neither knows Git; *"Pablo is genuinely unsure what's possible"* | High | Open design problem at interview time | **SUPERSEDED, then partly re-opened — record both moves.** *Superseded 2026-07-07:* the owner ratified the layered publish design (auto-merge → keep-yours/keep-theirs/**keep-both** → park-and-escalate; merge logic CLI-side, app renders the choice only), closing `SOUL.md` §9 open problem #2. *Re-opened 2026-07-31:* ADR-008 formally **deferred** the `cc publish` verb, so the ratified design is design-record, not shipping code. The conflict class cannot arise today because the writable-author lane was never opened to a second writer. |
| Everyone defaults back to generic chat (Claude app / ChatGPT / Gemini) | High | The HABIT to break | **Unchanged and unmeasured.** No telemetry exists in the shipping app to observe it; the Admin "Analytics" surface has a toggle and no emitter. |

**One additional Critical pain point that the 2026-07-06 interview did not — and could not — anticipate, added here from incident evidence:** on **2026-07-27**, `~/.claude/knowledge` was a symlink into the organization's own knowledge authoring checkout while simultaneously being `cc update`'s materialize target. A routine update reconcile-deleted everything under the paths it owned there — 5 org agent extensions including the brand-voice binding, 16 agents, all commands, all memory, hooks and skills, 10 of 11 top-level docs files, and the knowledge manifest: **12,537 deletions in one commit, which a backup cron then pushed to origin.** The content was restored and pushed; a guard now refuses to write or delete through any symlink escaping the materialize root, and fires as 4 honest `held` items on every apply. Recorded in `docs/01-architecture/inheritance-and-publish.md`. This is the never-destroy invariant's worst real-world near-miss and belongs in the product's own pain record, not only in an architecture appendix.

---

## Forces (Moments Framework, in Pablo's voice)

| Force | Pablo's framing (2026-07-06) | Reading at v0.4.0 |
|---|---|---|
| **Push** | Hand-keeping it all alive: constantly telling Claude Code and Codex to update, syncing systems, pushing his own changes, re-syncing the laptop on every pickup. *"That shit gets exhausting."* | Still the strongest force, and still the one with an unclosed proof (V-5). |
| **Pull** | Never having to think about it — make a change **once** and never worry whether it landed. *"Control Tower ensures my environment is Copilot-ready."* | Demonstrated on one machine, one org, 16/16 layers. |
| **Anxiety** | (1) *"What if it doesn't work?"* and a non-technical person has no dignified recovery. (2) Leakage — personal content crossing into a shared or public place by accident. | Anxiety 2 is closed by construction. Anxiety 1 is answered by design (holding copy, triage, rollback) and remains unvalidated with a real user. A third anxiety has emerged from the shipping product and is the owner's own: *does the tool tell the truth about itself?* — the "phantom secret-store provisioner that could report a store as configured when it was not," fixed in `cc 2.2.0`, is exactly that fear made real. |
| **Habit** | Falling back to the generic chat tool (Claude app / ChatGPT / Gemini) for every conversation instead of reaching for the solution-oriented ecosystem. | Unchanged, and structurally unmeasurable in the current build. |

---

## Risks & Unknowns

*What this interview surfaced that must be checked against other people — not just Pablo. Updated with what shipping has since settled.*

- **Pablo is the *opposite* of the primary consumer.** He owns a terminal and wrote the pipeline; the target user can do neither. Everything he finds "obvious" about `copilot update` is exactly what they cannot do. His intuitions about what is easy are disqualified for the persona that matters. **Status: unchanged, and now the governing risk of the whole programme** — every surface has been designed and shipped without a single independent user in the loop.
- **The Admin / IT-operator experience was entirely a HYPOTHESIS** (2026-07-06). **Status: partially advanced, still a hypothesis for an independent operator.** The Admin app now ships as a real 16-surface build over a deterministic bash engine, and the ENAC organization was genuinely stood up — but the operator was the owner. `SOUL.md` Founding Decision #9 has not been upgraded. The 2026-07-10 ratification round even records the owner's own instruction that the Admin journey "stays a hypothesis; validate the A6→A8 baton pass with one real operator before it hardens."
- **Org / department multi-writer authoring was a MODEL-IN-HEAD.** **Status: unchanged. Never run with more than one writer.**
- **Enterprise scale (3 → 600,000) is an ASPIRATION.** **Status: unchanged.** A flexibility target the design should not foreclose, not a tested claim. Live footprint today is one organization.
- **Two first-class open items carried into the security / architecture work:**
  - **Credentials — what carries secrets through a pull-based inheritance model with no cloud secret store? "GitHub, somehow, safely? Unsolved."** **SUPERSEDED — RESOLVED 2026-07-07, and now shipping.** The carrier is the per-user OS keychain via per-integration OAuth/device flow, plus (v1.3 amendment, same day) an optional tier-scoped, IT-managed shared secret store — self-hosted Infisical — whose *endpoint* travels in inherited org config while its *values* never do. Inheritance content carries `requires_secret: <NAME>` references only. Git is permanently excluded as a carrier at every tier. As of **v0.4.0 this is visible in the product**: `cc connections --json` presence-checks each declared service's hinted secret *names* against the org's Infisical store and returns a per-row `secret_state` of `ready` / `needs-connect` / `no-store`, which the wizard's step 6 and Settings render. Control Tower never sees a value.
  - **Personal-layer content scope** — writing styles are plural and context-dependent; what else belongs in the personal layer? **Status: still open**, demoted at `SOUL.md` v1.2 from a foundational problem to an engineering-roadmap item. <!-- TODO: confirm with Pablo — this has been open since 2026-07-06 and now bounds where the leak wall stands in a live 16-layer topology. -->
- **Framings the record must mark as dead, because a reader of the old version would otherwise inherit them:** the **MDM / Jamf / Kandji / Intune** mechanism (dropped completely, ratified `SOUL.md` v1.4 and `cse-alignment-decisions.md` D4, 2026-07-09 — security posture is compiled-in trust roots plus signed, inherited org/foundation config, and nothing else); the **fleet dashboard as an Admin centre of gravity** (same decision); **Tauri v2 / the Rust core** as the shipping stack (retired; the tree stays on disk as read-only reference, and the app is native SwiftUI/AppKit); and **Windows** (formally out of scope, 2026-08-02).
- **A risk that did not exist in 2026-07-06 and exists now: the product's own invariants are not automatically enforced on the shipping binary.** All 40 fitness tests scan the retired Rust tree and cannot see a line of the shipping Swift; the CI job that runs them is disabled. The six invariants are architectural commitments upheld by review, not machine-checked properties. The owner's ratified answer of 2026-08-02 (A-5) chose to **document this honestly as an open item** rather than fix it in this pass or quietly reframe it away. It is recorded here because a research document that omitted it would be doing exactly what this rebuild exists to correct.

---

## Takeaways

1. **The soul is democratization, not observability — and this was re-ratified, not merely inherited.** The product exists to give a non-technical person a technical person's AI superpowers, safely enough to run unattended. Observability and self-heal are the mechanism that earns unattended trust, not the headline. The owner reaffirmed this on 2026-08-02 and explicitly declined to re-centre the product on organizational transformation: organizations are the buyer, the individual is where the value lands.
2. **The real job is propagation without babysitting — and it is now demonstrated on one machine and one organization, not on two machines and not with anyone else.** 16 of 16 layers live, manifest written by a real apply, zero destructive git operations. The honest claim is *dogfooding, live on one org*: never "not started" (seven signed releases and eight version lines contradict that), never general availability.
3. **The most important sentence in this file is a gap, not a finding.** No non-technical person has completed the journey; no second writer has authored; the second machine has not cold-started. The product's own primary persona has never touched it. Everything designed for that persona — the holding copy, the triage categories, the recovery paths, the playful Done screen — is high-quality *design against an unvalidated model*, and must be stamped as such by everything downstream.
4. **The honesty discipline turned out to be load-bearing in a way the interview only half-predicted.** The 2026-07-06 concern was that a detail-oriented user would catch a drifted status. What actually happened is that *the system lied to itself* three separate times and was caught only by live evidence: a rollback that re-ran the same failing gate and reported `rollback-failed` over a byte-identical file; a warn-only "offline" health signal that rolled back a verified 16-layer manifest write; and a secret-store provisioner that could report a store as configured when it was not. Each was found, root-caused by reading the code rather than trusting a message, and fixed upstream in `cc` — never forced past. "The icon that cannot lie" is not decoration and not only about the icon.
5. **Two questions are worth putting to the owner before the next phase, and neither can be answered from the record.** First: is V-5 (the cold-laptop proof) the product's true acceptance bar, given that it is the literal machine that generated the founding complaint? Second: what is the smallest honest test of the democratization claim — one non-technical person, one department, one week — that could be run *before* publicize, rather than after?

---

**Related:** [Vision](../../00-overview/00-vision.md) | [Scope & Non-Goals](../../00-overview/10-scope-and-non-goals.md) | [Success Metrics](../../00-overview/20-success-metrics.md) | [Service Blueprint](../../02-service-design/10-service-blueprint.md) | [SOUL.md](../../../../SOUL.md)
