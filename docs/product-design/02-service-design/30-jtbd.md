# Jobs to Be Done

> **Provenance.** Grounded synthesis from the Phase-1 Discovery set (`00-overview/00-vision.md`
> Jobs-to-Be-Done + Forces Map + Inheritance & Propagation Model, `10-scope-and-non-goals.md`,
> `20-success-metrics.md`), the **primary-evidence owner interview** (2026-07-06,
> `01-research/10-interviews/01-interview-self.md`; `scratchpad/interview-ground-truth.md`), and the
> engineering source (`architecture.md`, `redteam-use-cases.md`, `ecosystem-use-cases.md`). Jobs are
> grouped by persona, not by feature. Every job traces to a source; genuine unknowns are marked
> `<!-- TODO -->`. Prerequisites: `00-vision.md`, `01-interview-self.md`.
>
> **The reframe (primary evidence, 2026-07-06).** The soul is **democratization: give a non-technical
> person the AI superpowers of a deeply technical one, safely enough to run unattended.** Observability
> and self-heal are the *mechanism that earns the right* to run in the background — not the point. Every
> job below is therefore a *democratization / trust / legibility / continuity* job — Control Tower adds
> zero intelligence of its own (invariant #1); it never becomes a "compute this for me" job.
>
> **Two consumer psychographics — do not collapse them.** The earlier draft treated "the consumer" as
> one person. The interview splits them:
> - **(a) The change-averse consumer (Bob)** — *reads / consumes*; must feel **SAFE** above all.
> - **(b) The trained early-adopter author (Ada)** — *writes* org/department content via a markdown
>   editor (Obsidian); more comfortable with the machinery; wants **POWER.** Access is *earned and
>   gated*, starting with a few innovators and growing as demand rises.

---

## Personas (carried from Phase 1)

> **Bob is a PSYCHOLOGY, not a role** (`interview-ground-truth.md` §8). "Bob the Accountant" is a
> behavioral archetype found in every company and department — IT, HR, executives can all *be* Bob.
> Accounting is the exemplar because accountants are archetypally *not* rule-breakers: they use the
> software they're given, don't deviate, follow standards, and are **intensely detail-oriented.** Bob is
> uncomfortable with change because change = **loss of control**; a new tool means he can make a mistake,
> break something, or be *wrong* — and being wrong could **lose information, lose the company money, or
> lose his job. The fear is professional consequence.** Target emotion: **comfortable AND excited** — the
> tools give him *"superpowers he's wanted his entire career and is only now getting."* **Design
> consequence:** Bob's detail-orientation means he *will catch* any drifted or dishonest status — so
> **"the icon that cannot lie" is survival, not decoration.**

- **Bob — the change-averse non-technical consumer (PRIMARY).** No terminal, denies OS prompts,
  ignores single nudges, may run Focus/DND. **"Bob is not a reliable actor" is load-bearing.** The
  **primary** Operator-mode persona; must feel **safe**.
  `> **Evidence: GROUNDED** (his psychology — real people across real companies) / **HYPOTHESIS** (the
  *full* ecosystem reaching a non-technical person unaided — never run end-to-end).`
- **Ada — the trained early-adopter author (NEW tier; writable-tier consumer).** Sits *between* Pablo
  (foundation) and Bob (consumer): a trained innovator with **earned, gated** write access to org /
  department content (new skills, agents, Knowledge Copilot content, CLI Copilot integrations). Authors
  in a markdown editor (**Obsidian**) → save → push → the change syncs to every machine on cadence. More
  comfortable than Bob; wants **power**, not just safety. Not a Git user.
  `> **Evidence: MODEL-IN-HEAD** — the multi-writer authoring loop (Obsidian → save → push → sync) has
  **never been run with more than one writer.**`
- **Raj (IT / Admin operator)** — stands up the ecosystem for the org and deploys it via
  Jamf/Kandji/Intune; owns the fleet. The **primary Admin-mode persona.**
  `> **Evidence: HYPOTHESIS** — no real IT operator has touched Admin mode, a fleet dashboard, or a
  deprovision. This whole persona's journey is an untested behavioral bet.`
- **Pablo (ecosystem owner / ENAC maintainer)** — authors the foundation, keeps two machines in parity
  *by hand today*, and needs the always-on agent to make the ecosystem *safer* to adopt, not riskier.
  The **trust-basis** persona and the *original author* (the foundation-tier case of Ada's job).
  `> **Evidence: OBSERVED** (his daily hand-sync pain).`
- **Jane / Sam (developer-contributor)** — *secondary context only.* They keep using the CLI directly
  (`ecosystem-use-cases.md` UC1–UC12). Control Tower must **not break** their workflow, but the
  end-user experience is not designed for them (`10-scope-and-non-goals.md`, explicit non-goal).

---

## Bob — Change-Averse Non-Technical Consumer (Primary Persona) Jobs

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| B0 | The soul | **When** I'm handed the ecosystem as a non-technical employee, **I want** a technical person's AI superpowers without understanding the layers underneath, **so I can** build, answer, and integrate what I need instead of being stuck with the software IT gave me — comfortable *and* excited, not just unblocked. | **P0** (the democratization job) |
| B1 | Onboarding | **When** I'm handed a new work laptop, **I want** a working AI partner scoped to my team without being technical, **so I can** do my job without ever learning YAML or the terminal. | **P0** (the entry gate to B0) |
| B2 | Steady-state | **When** my machine drifts, falls behind, or loses sync while I'm just working, **I want** it to stay synced and self-healed on its own without interrupting me, **so I can** trust it's current without babysitting it. | **P0** |
| B3 | Any moment | **When** I glance at the menu bar, **I want** an honest, plain-language answer to "is my partner OK, and do I have to do anything?", **so I can** trust it's never quietly lying that it's fine (my detail-orientation *will* catch a false green — and one false green and I'm gone). | **P0** |
| B4 | Interruption | **When** the system genuinely needs a human, **I want** to be asked *only* about my own data (a sign-in, my dirty work) and *never* about a decision I can't judge, **so I can** keep trusting the one alert that matters instead of learning to ignore it. | **P1** |
| B5 | Recovery | **When** it breaks, **I want** the system to either fix it for me or walk me through it with dignity, **so I can** recover even though I'm not technical (Anxiety #1: failure with *no path back* is the real fear). | **P0** |
| B6 | Habit-break | **When** I have any question — from "what email do I send this person" to "I'm not getting the report I need", **I want** to reach for this solution-oriented partner by reflex, **so I can** stop defaulting to a generic chat app (Claude app / ChatGPT / Gemini) that only ever answers instead of *building*. | **P1** (adoption-defining) |
| B7 | Removal | **When** I no longer want it (or I leave), **I want** it to come off cleanly without orphaning a background agent or a ghost login item, **so I can** trust it isn't lingering. | **P2** |

## Ada — Trained Early-Adopter Author (NEW writable-tier Persona) Jobs

> `> **Evidence: MODEL-IN-HEAD**` — this whole authoring loop has **never been run with more than one
> writer.** It introduces *writable, collaborative tiers*, which strains the current "never-destroy /
> read-only mirrors" safety assumption (see W3 + `10-service-blueprint.md` Failure Points). Write access
> is **earned and gated**, starting with a few innovators and growing as demand rises.

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| W1 | Publish | **When** I publish a change to org / department content once, **I want** to know it reached everyone on cadence *without breaking anyone's personal work*, **so I can** stop being the sync layer and never wonder whether it landed. | **P0** (the propagation / everyday-hero job) |
| W2 | Author | **When** I want to contribute a skill, agent, or knowledge, **I want** to write it in a familiar markdown editor (Obsidian) — load files, edit, save, push — with no technical release process, **so I can** extend the ecosystem with the power I was trained for. | **P1** |
| W3 | Collaborate | **When** a colleague and I edit the same department file and our syncs collide, **I want** the conflict resolved elegantly and invisibly with *no data loss and no Git knowledge required*, **so I can** collaborate without ever becoming a Git user. | **P0** (unsolved — trust make-or-break) |

## Cross-Cutting — Both Consumers (the Leakage Wall)

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| X1 | Any authoring / sync | **When** I author or consume across tiers, **I want** the system to make crossing the personal↔shared boundary **impossible by accident**, **so I can** never push private personal information into a shared/public place (Anxiety #2 — the nightmare scenario). | **P0** (new trust guarantee — Bob *and* Ada) |

<!-- TODO (open item, route to security/threat-model): CREDENTIALS — what carries secrets through a
     pull-based inheritance model when a company has no cloud secret store? GitHub, somehow, safely?
     Unsolved (`interview-ground-truth.md` §10). This gates W1/W3 in practice. -->
<!-- TODO (open item): PERSONAL-LAYER CONTENT SCOPE — writing styles are plural and context-dependent
     (email voice ≠ documentation voice ≠ thought-leadership voice); Knowledge Copilot is the natural
     home. What ELSE belongs in the personal layer for Knowledge Copilot + the CLI Copilot integration
     layer? Shapes X1's boundary definition. -->

## Raj — IT / Admin Operator (Primary Admin-mode Persona) Jobs

> `> **Evidence: HYPOTHESIS**` — every job in this table is an untested behavioral bet; no real IT
> operator has run any of it.

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| A1 | Setup | **When** I roll the Copilot ecosystem out to my org, **I want** to generate the seed and MDM profile from a guided tool and preflight it red/green *before* pushing, **so I can** deploy to a whole fleet without hand-editing config or crafting `.mobileconfig` by hand. | **P0** |
| A2 | Operate | **When** an employee's machine drifts, falls behind, or loses auth, **I want** to see it on a dashboard while it self-heals, **so I can** trust the fleet without touching each machine or waiting for Bob to call. | **P0** |
| A3 | Govern | **When** something needs *my* authority (a held-major upgrade, a capability-policy conflict), **I want** it to reach me centrally — never the employee — **so I can** decide with the competence and authority the employee lacks. | **P1** |
| A4 | Offboard | **When** an employee leaves, **I want** company content and access revoked reliably even if they trash the app or stay offline, **so I can** guarantee "no secret ever materialized" rather than a fragile, app-contingent wipe. | **P0** |
| A5 | Audit | **When** my security team reviews what the always-on agent did, **I want** a content-free, tamper-evident record on a live channel, **so I can** prove every auto-pull was visible, verified, and policy-bounded. | **P1** |

## Pablo — Ecosystem Owner / ENAC Maintainer (Trust-basis Persona) Jobs

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| O1 | Security propagation | **When** a security fix ships upstream but a personal override shadows it, **I want** the vulnerable version auto-suspended (reversibly) so the fix wins immediately, **so I can** close exposure without depending on a non-technical user noticing a notification. | **P0** |
| O2 | Enterprise trust | **When** an enterprise security team audits the always-on, token-holding, auto-materializing agent, **I want** it to be open-source, reproducibly built, and provably *safer* than manual `copilot update`, **so I can** get the whole ecosystem adopted at all. | **P0** |
| O3 | Integrity | **When** Control Tower renders any state, **I want** it to *parse* the CLI's verdict and never compute one, **so I can** guarantee there is never a second, wrong source of truth. | **P0** |
| O4 | Privacy | **When** telemetry flows to an IT dashboard, **I want** a personal item name to be *un-emittable by construction*, **so I can** close the observability gap without creating a surveillance tool. | **P1** |

## Jane / Sam — Developer-Contributor (Secondary Context) Jobs

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| D1 | Coexistence | **When** Control Tower supervises the same pipeline I run by hand, **I want** my direct `copilot update` / `resolve --explain` workflow to keep working untouched, **so I can** keep my terminal habits without the GUI double-writing my tree. | **P1** (do-no-harm) |

---

## Priority Summary

**P0 Jobs (must-have for minimum lovable product):**
- **B0** — a non-technical person gets a technical person's superpowers. *The soul; the reason to exist.*
- **B1** — one-double-click working, team-scoped partner (zero terminal). *The entry gate to B0.*
- **B2** — always-on self-heal that stays current without interrupting Bob.
- **B3** — honest, glanceable, never-false-Healthy status that names the failing host.
- **B5** — dignified recovery when it breaks (fix-it-for-him or walk-him-through).
- **W1** — publish once → reaches everyone on cadence, breaking no one's personal work. *(author; MODEL-IN-HEAD)*
- **W3** — invisible, no-data-loss, no-Git-required merge-conflict resolution. *(author; unsolved)*
- **X1** — the leakage wall: personal↔shared crossing impossible by accident. *(both consumers)*
- **A1** — guided seed + MDM-profile generator + preflight (no hand-YAML). *(HYPOTHESIS)*
- **A2** — fleet dashboard: healthy / stuck / behind / needs-auth at a glance. *(HYPOTHESIS)*
- **A4** — MDM-native, offline-resilient deprovision ("no secret ever materialized"). *(HYPOTHESIS)*
- **O1** — auto-suspend a security-shadowing override (never notify-and-hope).
- **O2** — auditable, open-source, safer-than-manual always-on agent (the enterprise-adoption gate).
- **O3** — parse-never-compute integrity (no second source of truth).

**P1 Jobs (high-value, next tier):**
- **B4** — route by actor-competence so Bob is asked only about his own data.
- **B6** — break the generic-chat habit; make the solution-oriented partner the reflex.
- **W2** — author in Obsidian with no technical release process.
- **A3** — held-majors / policy conflicts go to IT centrally.
- **A5** — content-free, tamper-evident audit trail on a live channel.
- **O4** — PII-minimizing telemetry (personal names un-emittable).
- **D1** — do-no-harm coexistence with the developer's direct CLI use.

**P2 Jobs (nice to have, post-MLP):**
- **B7** — clean, non-orphaning removal / uninstall.

**Total: 22 jobs across 5 user types (Bob 8, Ada 3, cross-cutting 1, Raj 5, Pablo 4, Jane/Sam 1).**

> **Warning:** 22 jobs is a lot, and the temptation is to weight every persona equally. Don't — and
> keep **Bob-first primacy** even now that the author tier exists. The P0 jobs cluster into two spines
> that share one boundary: **(1) the consumer spine** — *give Bob superpowers (B0) by provisioning him
> silently (B1), keeping him healed and honestly-statused (B2/B3), and giving him a dignified recovery
> (B5)*; and **(2) the author/propagation spine** — *let Ada publish once and have it land everywhere on
> cadence without clobbering personal work (W1), resolve collisions invisibly (W3)*. Both spines are
> policed by the **same leakage wall (X1)** and the escalation router (invariant #5). B1 + B3 + W1 are
> the "if we could only ship three things" set; everything else is earned through adoption. Note the
> asymmetry of evidence: the consumer spine is **GROUNDED**, the author spine is **MODEL-IN-HEAD**, and
> the entire Admin tier is **HYPOTHESIS** — do not let downstream design over-trust the untested tiers.

---

## Job Ranking

| Job | Importance | Frequency | Stakes if it goes wrong |
|-----|------------|-----------|--------------------------|
| **B0** (superpowers / democratization) | **Highest** — the soul | Every working moment | The whole product is pointless; Bob stays stuck in IT-approved software |
| **B1** (onboard silently) | **Highest** — the entry gate to B0 | Once per employee (but every employee) | Adoption fails; the ecosystem stays CLI-shaped and unadoptable by non-technical staff |
| **B3** (honest status) | Highest | Continuous (every glance) | **Worst outcome in the whole product:** Bob's detail-orientation catches a false green; the icon becomes a liar and a change-averse Bob is *gone for good* (`20-success-metrics.md`; A-C1/H7/H12) |
| **X1** (leakage wall) | Highest | Every author/sync | Private personal info lands in a shared/public repo — Anxiety #2, the nightmare scenario; irreversible trust loss |
| **W1** (publish → lands everywhere, breaks no one) | Highest (author) — the everyday hero | Whenever anyone authors | Author becomes the sync layer again; a publish clobbers a colleague's personal work (**MODEL-IN-HEAD**) |
| **O1** (auto-suspend security shadow) | Highest | Rare but decisive | A shipped security fix silently defeated by a personal override + an unseen notification (the C3 class) |
| **B5** (dignified recovery) | High | On any failure | A non-technical Bob hits a dead end with no path back — Anxiety #1; he abandons |
| **W3** (invisible merge-conflict resolution) | High — trust make-or-break | Whenever two authors collide | A raw Git error a non-technical person can't act on; two colleagues' edits lost or stuck (**unsolved**) |
| **B2** (self-heal) | High | Continuous (poll ~6h/1h/15m) | Machine drifts/falls behind silently; the "stays working on its own" promise dies |
| **B6** (break the chat habit) | High | Every conversation | Bob defaults back to generic chat; the ecosystem is installed but unused |
| **A2** (fleet observability) | High | Continuous (IT) | The named gap stays open — IT can't tell healthy from bricked (**HYPOTHESIS**) |
| **A1** (Admin generator + preflight) | High | Once per org (gates the fleet) | Hand-craft error ships a broken fleet; a missing key mis-provisions every machine silently (**HYPOTHESIS**) |
| **A4** (deprovision) | High | Rare, high-severity | A leaver's company content persists; "no secret materialized" guarantee breaks (**HYPOTHESIS**) |
| **O2 / O3** (auditable, never-compute) | High (the moat) | Design-continuous | The always-on agent fails an enterprise security review; a second source of truth appears |
| **B4 / A3** (route by competence) | Medium-High | Ongoing | Bob-notification fatigue burns the one alert that matters |

---

## Competing Solutions

| Job | Current Solution (what they hire today) | What's Good | What's Bad | Why they haven't switched |
|-----|------------------------------------------|-------------|------------|----------------------------|
| **B0** (superpowers) | Generic chat apps (Claude app / ChatGPT / Gemini) | Familiar; zero setup; answers anything | *Only answers* — doesn't build, integrate, or persist; no company context; the HABIT to break | It's what everyone already reaches for; no solution-oriented alternative is on their machine |
| **B1** (onboard) | A `./onboard.sh` shell script + a department prompt + reading `copilot update` output (`ecosystem-use-cases.md` UC1) | Works perfectly *for a developer* | Requires a terminal and judgment Bob doesn't have; **no non-technical path exists** | There is no alternative — the barrier *is* the CLI shape; nothing to switch *to* |
| **W1** (publish → lands everywhere) | Pablo hand-carries every change between two machines; nothing propagates unless he remembers (`interview-self.md` Current Process) | Total control | "That shit gets exhausting"; doesn't scale past one diligent person; no cadence pull | The tool does not exist — Pablo *is* the sync layer (**MODEL-IN-HEAD** for >1 writer) |
| **W3** (merge-conflict) | **Nothing non-technical** — raw `git merge`, which neither Bob nor Ada can do | Correct for a Git user | A Git conflict message a non-technical person cannot act on; edits lost or stuck | No invisible-resolution path exists; Pablo is *genuinely unsure what's possible* (open design problem) |
| **X1** (leakage wall) | Human discipline — "just don't push personal stuff to the shared repo" | Costs nothing to *say* | One fat-finger and private personal info is in a public place, irreversibly; discipline is not a control | No boundary enforcement exists; the wall is entirely in the user's head today |
| **B2 / B3** (stay current, know status) | Manual/cron `copilot update` + `copilot doctor` in a terminal | Deterministic, hardened, correct | Prunes + `security:` trailers swallowed by cron; output unreadable to Bob; no glanceable state (`architecture.md` §8.3; A-H9) | Same — the intelligence is CLI-shaped; Bob can't run it |
| **A1** (org standup) | Hand-written `ecosystem.yml` + hand-created per-dept repos + hand-crafted `.mobileconfig` per MDM vendor (`architecture.md` §8.1) | Total control; nothing hidden | Error-prone, doesn't scale, a typo ships a 404; per-vendor rework | It's the only known way; the toil is accepted as the cost of adoption |
| **A2** (fleet health) | **Nothing** — wait for the employee to call (`architecture.md` §9) | — | Can't tell a healthy Mac from a bricked one; false-Healthy hides drift | The tool does not exist |
| **A4** (offboard) | `copilot deprovision <org>` run by hand, if the machine is online (`ecosystem-use-cases.md` C4/leaver) | Wipes materialized content when it runs | Contingent on a user-deletable app + an online machine; a motivated leaver defeats it (A-C4) | No MDM-native enforcement path exists yet |
| **O1** (security propagation) | A `security:` trailer materializes the fix + a notification | The fix *materializes* | Bob's override still wins; the notification is never seen — "notifies but does not act" (A-C3) | The design *had* this gap; Control Tower's auto-suspend is the fix |
| **O2** (enterprise trust) | "Trust us, it's automatic" — a closed always-on updater | Convenient | An un-auditable token-holding agent fails security review; the anxiety is unresolved (`00-vision.md` Forces / Anxiety) | Enterprises simply *won't* adopt an un-auditable always-on agent — the block is the whole problem |

---

## The One Primary Job (for downstream design)

> **B0 — "When I'm handed the ecosystem as a non-technical employee, I want a technical person's AI
> superpowers without understanding the layers underneath, so I can build, answer, and integrate what I
> need — comfortable *and* excited."**
>
> This is the reframe made concrete: the soul is **democratization**, and B0 is its job statement.
> **B1** (silent provision) is the *entry gate* that first delivers it, and **B3** (honest status —
> never lie that it's fine) is its *inseparable twin*, because a change-averse, detail-oriented Bob who
> catches one false green never comes back. If we nail B0 through B1+B3, the rest can be merely good and
> Control Tower still succeeds. Every other consumer job keeps B0's promise true *over time* (B2),
> *dignified when it breaks* (B5), and *reflexive* (B6, breaking the generic-chat habit).
>
> **Bob-first primacy holds** even with the new author tier. The author/propagation job **W1**
> ("publish once → lands everywhere on cadence, breaking no one") is the *everyday-hero mechanism* and
> ranks at the **top of the author spine** — but it exists to *feed* Bob's B0, not to displace it. Both
> spines are policed by the same leakage wall **X1**. The Magic Moment (`00-vision.md`) is the delivery
> of B0: one double-click → superpowers, no terminal, no config — and an authorized change made once
> upstream simply *appears* on Bob's machine on the next cadence, without touching his personal work.

<!-- TODO: confirm with Pablo — is Admin-mode standup (A1) co-primary with Bob's B0/B1, or strictly the
     enabler of it? The docs frame Bob as *the* primary persona, but "two faces, one binary" puts A1 on
     the critical path. This affects whether the first release leads with the Operator or Admin experience.
     Note A1 is HYPOTHESIS — no real IT operator has touched it. -->
<!-- TODO: confirm with Pablo — does the author spine (W1/W2/W3, Ada) belong in the *first* release, or
     is v1 consumer-only (Bob reads a foundation Pablo still hand-authors) with the multi-writer tiers
     deferred until the merge-conflict + credentials problems are solved? MODEL-IN-HEAD status argues
     for deferral; the everyday-hero framing argues for inclusion. -->

---

**Related:** [Journey Maps](20-journey-maps.md) | [Moments That Matter](40-moments-that-matter.md) | [Self-Interview](../01-research/10-interviews/01-interview-self.md)
