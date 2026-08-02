# Jobs to Be Done

<!--
FACILITATION GUIDE — Service Designer
======================================
JTBD captures what the user is HIRING this product to do. Not features.
Not tasks. The underlying motivation.

Format: "When [situation], I want to [motivation], so I can [outcome]."

PREREQUISITE: 00-vision.md and at least one interview must be completed.

CONVERSATION FLOW:
1. Identify the different contexts users are in when they need this
2. For each context, articulate the job
3. Group jobs by persona — each persona has distinct jobs
4. Rank jobs by importance and frequency within each persona
5. Identify competing solutions (what they hire today instead)
6. Summarize priority across all personas (P0/P1/P2)

QUESTIONS TO ASK:

## Round 1: Contexts
- "Think about the different moments when someone would reach for
  this product. What's happening in their world at that moment?"
- "Are there different personas with different contexts?"
- "Are there time-pressure or urgency contexts?"

## Round 2: Job Articulation
For each context identified:
- "When [this situation happens], what does the user want to do?"
- "Why? What outcome are they trying to achieve?"
- "What would 'success' look like for this specific job?"
- Frame as: "When ___, I want to ___, so I can ___."

## Round 3: Job Grouping by Persona
For each persona identified in the journey maps:
- "What are [persona]'s distinct jobs in this product?"
- "How many jobs does this persona have? Rank them by importance."
- "What is the job this persona would miss most if the product disappeared?"

## Round 4: Job Ranking
- "Which of these jobs is the MOST important? The one that, if we
  nail it, everything else can be mediocre?"
- "Which job happens most frequently?"
- "Which job has the highest stakes if it goes wrong?"
- "Of all the jobs across all personas, which are P0 — must-have
  for the first version? Which are P1 — high value but not blocking?
  Which are P2 — nice to have?"

## Round 5: Competing Solutions
For each job:
- "What do people hire today to do this job?"
- "What's good about that current solution?"
- "What's bad about it?"
- "Why haven't they switched to something better already?"

## Round 6: Priority Warning
- "How many total jobs have we articulated? Is that number realistic
  for the first version?"
- "A product that tries to serve all jobs equally will serve none well.
  Which jobs define the minimum lovable product?
  Everything else is earned through adoption."

SYNTHESIS:
Present jobs grouped by persona, not by feature area. Within each
persona group, order by priority. Include a cross-persona priority
summary at the end. Add a warning if the total job count is high —
too many jobs means the product is trying to be too many things.
-->

> **Status — rebuilt from evidence 2026-08-02.** Rewritten against the shipping code (`native/wizard.swift`, `native/control-tower-tray.swift`, `native/user-settings.swift`, `native/admin.swift`), the accepted ADRs, the ENAC self-onboarding initiative's live-run evidence, and the schema-mismatch incident record — replacing a version written before most of it had happened. It describes **v0.4.0** (build 19, 2026-08-02, embedded helper `cc 2.2.0`). Product status is **DOGFOODING**: live on exactly one organization (ENAC), sixteen of sixteen layers applied live, not offered to outside organizations, not generally available.
>
> These jobs are **retrofitted from a shipped product**, not proposed for one. Where a job has been demonstrated, it says so. Where it is still a bet, it says so in the same sentence.

## The brief, reframed

The brief this product was originally given was *"build a face and supervisor over the CLI."* That is a description of a mechanism, and a mechanism is not a job. Taken literally it produces a status dashboard — and nobody hires a status dashboard, because nobody wakes up wanting to know the state of their layer manifest.

**The assumption worth challenging is that the job is about the machine.** It is not, and every piece of real evidence in this repository points the other way. The origin pain recorded in the vision is *"that shit gets exhausting"* — a person, worn down by being the sync layer between two of his own machines. The primary user is defined by a psychology (change-averse, detail-oriented, professionally exposed if he is wrong), not by a technical situation. And the sharpest failure in the record is not a broken machine at all: it is a screen that said **"setup stopped before changing anything"** at a moment when two GitHub repositories had already been created.

So the reframe: **Control Tower is not hired to manage an ecosystem. It is hired to make an unverifiable system trustworthy enough to be left alone by someone who cannot check it.** Every distinctive thing the product does — the fail-closed schema gate, all deterministic preflight before any irreversible write, the completed-actions ledger, the refusal to render a percentage — is that job expressed as engineering rather than as reassurance.

## The primary job

> **When** I have been handed an AI ecosystem that only a technical person could install, **I want to** get all of it working on my own Mac and have it stay working without my attention, **so I can** use a technical person's superpowers without becoming one — and without ever having to check whether it is really still working.

The trailing clause carries the weight. "Get it working" is a setup job, and it would be finished the day it finished. "Stay working without my attention, and without my having to check" is a **trust job**, and it is renewed every single day the person does not open the popover. That is why the product's most important state is silence, and why a false green is not a bug class but a violation of the job itself.

Three sub-outcomes decide whether this job is done, in the order the person experiences them:

1. **Functional** — every component the person is entitled to is present and current on their Mac, and they never opened a terminal to get it there.
2. **Emotional** — the person *believes* the icon. Not "finds it informative." Believes it, to the point of not checking.
3. **Social** — the person can hand the one thing they cannot solve to the one person who can solve it, without being embarrassed by not understanding it.

## Bob's jobs — the change-averse non-technical adopter (PRIMARY)

Bob is a psychology, not a job title: the detail-oriented professional in accounting, HR, legal, operations, or the executive suite who uses what IT hands him, follows standards well, and is precise. He is change-averse because change costs him control over something he is currently competent at, and because being wrong could lose information, lose money, or lose him standing. **The fear is professional consequence.** `Evidence: GROUNDED — the archetype is drawn from real people across real companies; see 00-overview/00-vision.md.`

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| B1 | Arrival | **When** someone at work sends me a link and says this will change how I work, **I want to** install it and find out what it actually is before I commit to anything, **so I can** decide whether to trust it without having already changed my machine. | **P0** |
| B2 | Setup | **When** I am setting this up, **I want to** be shown exactly what it is about to create, download, or leave alone — in words about folders and accounts, not repositories and manifests — **so I can** authorize something I actually understand instead of clicking through. | **P0** |
| B3 | Setup | **When** setup runs, **I want to** never be asked a question I have no basis to answer, **so I can** stop worrying that I will be the one who broke it. | **P0** |
| B4 | Setup | **When** setup stops, **I want to** be told plainly whether it stopped because something is wrong or because it found something that is already mine, **so I can** tell a problem apart from a courtesy. | **P0** |
| B5 | Completion | **When** setup says it is done, **I want** that claim to have been verified rather than assumed, **so I can** stop checking. | **P0** |
| B6 | Steady state | **When** nothing is wrong, **I want** the app to say nothing at all, **so I can** forget it exists and get on with my actual job. | **P0** |
| B7 | Steady state | **When** something *is* wrong, **I want** one sentence naming what is wrong and who fixes it, **so I can** either act or hand it on without diagnosing anything. | **P0** |
| B8 | Steady state | **When** something new becomes available to me because of a change at work, **I want** it to just appear, **so I can** stop filing tickets to get tools I am already entitled to. | P1 |
| B9 | Recovery | **When** something breaks after an update, **I want** a way back that does not require me to understand what broke, **so I can** recover with my dignity intact. | P1 |
| B10 | Work | **When** I want to use one of my own projects with this, **I want** the safe part done for me and the unsafe part routed to whoever owns that project, **so I can** get value without becoming responsible for something I do not understand. | P1 |
| B11 | Ongoing | **When** my work changes and I need something the ecosystem could give me, **I want to** reach it without a technical intermediary, **so I can** build the thing myself instead of asking someone to build it for me. | P1 |

**The job Bob would miss most if the product vanished is B6.** Not the setup — the silence. Setup is a one-off he would grudgingly get help with. The silence is worth something every day, and no amount of help can substitute for it.

**B4 earns its own line because it was learned the hard way.** The Holding screen exists as **seven named variants** precisely because one generic "setup paused" screen conflates unrelated situations: something is broken (H2, H3), something is already yours and was left exactly as it was (H4), we are waiting (H5), your organization has something left to do (H6), and there is one permission only you can grant (H7). The variant is chosen by **who owns the fix**, never by what went wrong — and H4 is forbidden from being orange or using the words *paused*, *stopped*, *problem*, or *error*, because it is a success with a question attached. `Evidence: SHIPPED — walkthroughs/holding-copy-spec.md, implemented as HoldingVariant/HoldingInfo in native/wizard.swift.`

## Earl's jobs — the organization owner and admin operator

Earl stands the ecosystem up for a company. In the shipped product he uses a separate Admin build with sixteen surfaces over a deterministic bash engine that makes every existence and idempotency decision by check-then-act, GET before POST/PATCH/PUT, with `gh` and `jq` vendored into the bundle so his Mac needs neither. `Evidence: RUN ONCE, BY THE AUTHOR — Admin mode has stood a real sixteen-layer organization up end to end (Phase 7, 16/16 live apply). No third-party IT operator has ever touched it. Every job below is a demonstrated capability and an untested behavioural bet at the same time.`

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| E1 | Standup | **When** I am standing an organization up, **I want to** see exactly what will be created on GitHub before anything is created, **so I can** authorize a change I can defend to whoever asks me about it later. | **P0** |
| E2 | Standup | **When** the standup runs, **I want** it to check before it acts at every single step, **so I can** re-run it after an interruption without creating anything twice. | **P0** |
| E3 | Standup | **When** it stops, **I want** it to stop cleanly and tell me exactly what exists and what does not, **so I can** pick up from a known state instead of auditing GitHub by hand. | **P0** |
| E4 | Handover | **When** I am about to hand the organization to its people, **I want** a read-only check that reports what is genuinely on GitHub, **so I can** find blockers before my colleagues do. | **P0** |
| E5 | Governance | **When** a new department forms, **I want to** add it without hand-editing configuration, **so I can** grant access by structure rather than by favour. | P1 |
| E6 | Governance | **When** someone leaves, **I want** a defined offboarding path, **so I can** revoke their reach without hunting through systems. | P1 |
| E7 | Governance | **When** the organization has shared credentials to connect, **I want to** point at a store rather than distribute values, **so I can** never be the person who emailed a secret. | P1 |
| E8 | Security | **When** my security team asks what this thing does on our machines, **I want** an answer that survives them reading the source, **so I can** get a yes instead of an exception request. | **P0** |

**E8 gates every other job in this table.** No standup happens if the review ends in a no. This is why the product is pure open source, one signed binary, zero bypass flags, compiled-in trust roots, a pinned and independently notarized helper, and a fail-closed contract gate — and why "add a paid tier to fund the work" is a regression trigger rather than a business idea.

**E7 has a scar.** A phantom secret-store provisioner could report a store as configured when it was not; it is closed in `cc 2.2.0`, shipped in v0.4.0. Any report of readiness that is not backed by a verification the app can point at is the same defect wearing a different hat.

## Pablo's jobs — the author who publishes upstream, and the ecosystem's trust basis

Pablo authors the foundation, holds the signing identity, and is the person the product exists to release from being the sync layer. He is also the only person who has ever exercised the writable-tier authoring path. `Evidence: OBSERVED, continuously — this is the only genuinely longitudinal evidence the product has.`

| # | Phase | Job Statement | Priority |
|---|-------|---------------|----------|
| A1 | Authoring | **When** I make a change once to shared content, **I want** it to land on every entitled machine on cadence, **so I can** stop being the sync layer and stop wondering whether it landed. | **P0** |
| A2 | Authoring | **When** that change propagates, **I want** it to be structurally impossible for it to clobber anyone's personal work, **so I can** publish without rehearsing the blast radius every time. | **P0** |
| A3 | Authoring | **When** I write in my own editor and save, **I want** the publish path to be markdown-and-save rather than a Git ceremony, **so I can** author at the speed of thinking. | P1 |
| A4 | Elevation | **When** something I built inside one project turns out to be useful to everyone, **I want** a safe route to raise it to a shared tier, **so I can** grow the shared layer without improvising. | P1 |
| A5 | Release | **When** I cut a release, **I want** the gates to catch what I would have missed, **so I can** ship without being the last line of defence myself. | **P0** |
| A6 | Release | **When** a release turns out to be defective, **I want** a rollback anyone can follow, **so I can** fix it without a support conversation per person. | **P0** |
| A7 | Machines | **When** I pick up my second machine, **I want** it to already be at parity, **so I can** stop re-updating everything just to get back to where I was. | P1 |

**A3 and A4 are the two jobs the product has not finished.** The multi-writer authoring loop has still never been run with more than one writer, and the `publish` verb is formally deferred (ADR-008, Accepted 2026-07-31). The interim answer for A4 is a documented manual copy-commit-push into the tier repository's own working directory, with symlinking explicitly forbidden — a rule written after one routine update reconcile-deleted **12,537 lines** of organization content in a single commit through a symlink, which a backup job then pushed to origin. `Evidence: INCIDENT — docs/01-architecture/inheritance-and-publish.md. The guard now in cc refuses to write or delete through any symlink that escapes the materialize root; in the live run it fired correctly as 4 held items, not as a failure.`

**A7 is the origin pain in its last unfixed form.** Personal-key sync across one person's own machines is accepted as a real need and remains unsolved; the V-5 cold-laptop proof is the first evidence that will inform it.

## Priority Summary

**P0 jobs (must-have for the minimum lovable product):** B1 arrival without commitment · B2 informed authorization · B3 never asked what you cannot answer · B4 a stop you can interpret · B5 verified completion · B6 silence when fine · B7 one sentence when not · E1 see before create · E2 check before act · E3 stop cleanly and truthfully · E4 read-only proof before handover · E8 survives a security review · A1 change made once lands everywhere · A2 never clobbers personal work · A5 gates catch it first · A6 a rollback anyone can follow.

**P1 jobs (high-value, next tier):** B8 entitlement appears on its own · B9 recovery with dignity · B10 project aftercare routed by ownership · B11 reach the ecosystem without an intermediary · E5 add a department · E6 offboard someone · E7 point at a store, never distribute values · A3 author in markdown, not in Git · A4 a safe elevation route · A7 machine-to-machine parity.

**P2 jobs (nice to have, post-MLP):** none are claimed. Every job in this document traces to something already built, already demanded by an incident, or already named as an open gap. A P2 list here would be speculation, and speculation is exactly what this rebuild exists to remove.

**Total: 26 jobs across 3 user types.**

> **Warning: 26 jobs is a lot, and the product knows it.** The count is only defensible because sixteen of them are already shipped and evidenced rather than proposed. The **six** jobs that actually define the minimum lovable product are **B2, B4, B5, B6, B7, and A1** — informed authorization, an interpretable stop, verified completion, silence, one honest sentence, and a change that lands. If those six hold, everything else in this document is either a convenience or a consequence of them. If any one of them fails, the rest stop mattering, because they all sit on top of a person's willingness to leave the thing running.

## Job Ranking

| Job | Importance | Frequency | Stakes |
|-----|-----------|-----------|--------|
| **B6 — silence when nothing is wrong** | Highest. After day one it *is* the value proposition | Every day, invisibly | Existential. A false green ends the relationship permanently, and Bob is precisely the person who will catch it |
| **B5 — verified completion** | Highest | Once per machine, and again after every repair | Existential, and proven: through v0.2.3 a GitHub repository or a hidden mirror counted as an installed layer, so a person could see a green Personal result with no visible folder anywhere on their disk (fixed in 0.2.4 under ADR-005) |
| **A2 — never clobbers personal work** | Highest | Every propagation | Existential, and proven: 12,537 lines of organization content deleted in one commit, then pushed by a backup job |
| **E8 — survives a security review** | Highest. It gates every other job | Once per organization | Existential for adoption. A no here means zero of the other jobs are ever exercised |
| **B2 — informed authorization** | Highest | Once per machine, plus every subsequent structural change | Very high. This is the moment a person consents to an irreversible act on their own accounts |
| **B4 — a stop you can interpret** | Highest | Every non-trivial setup. In the real live run **9 of 16 rows** landed on `review` on the first plan pass | Very high. Misread as failure, it turns never-destroy working correctly into "this tool is broken" |
| **A1 — change made once lands everywhere** | Highest | Continuous, on cadence | High. This is the origin job; without it the product is a one-time installer |
| **B7 — one sentence naming what and who** | High | Rare by design, and the rarity is the point | High. Every alert a person cannot act on burns down the credibility of the one that matters |
| **E1 / E2 / E3 — see, check, stop cleanly** | High | Once per organization, plus every governance change | High. A half-created organization is worse than none, because it hides its own history |
| **A6 — a rollback anyone can follow** | High | Rare, and catastrophic when needed | High. Every release since 0.2.1 ships an explicit rollback paragraph naming the prior signed DMG, under an immutable-tag rule |
| **B10 — project aftercare** | Medium | Recurring, whenever a person picks a project back up | Medium. Handled badly it becomes a support queue; handled well it is the second reason to open the app |
| **B8 — entitlement appears on its own** | Medium | Occasional | Low individually, high culturally — it makes access feel structural rather than political |

## Competing Solutions

What people actually hire today instead of this. Each row is a real alternative, and each is genuinely *good at something* — which is exactly why it persists.

| Job | Current Solution | What's Good | What's Bad |
|-----|-----------------|-------------|-----------|
| **A1 — get a change onto every machine** | **Manual per-project fan-out.** The author walks each project and each machine by hand, running the update, remembering which ones he has done | Total control. Nothing happens that the author did not personally do, so nothing can surprise him | It does not scale past one person, and it fails silently: a change made once does not land everywhere, because the human *is* the sync layer. Named as the owner's number-one pain. Nothing propagates unless someone remembers, and remembering is not a mechanism |
| **A1 / A4 — share something useful** | **Copy-paste between repositories.** Copy the skill, agent, or command into the next project and move on | Immediate, zero setup, works with any tool | Every copy is a fork. The copies drift, nobody can say which is canonical, and a fix to one never reaches the others. It converts one shared asset into N diverging private ones |
| **B1–B5 — get it working at all** | **A technical person does it for me.** A colleague sits at the machine, or screen-shares, and installs the ecosystem by hand | It genuinely works, and it needs no product at all | It does not scale, it makes the recipient permanently dependent, and mostly it never happens because nobody has the time. The resulting machine is also undocumented, so nobody can later say what state it is in. Before this product, Knowledge Copilot and CLI Copilot were effectively single-user inside the organization for exactly this reason |
| **B11 — get an answer, or build a thing** | **A generic chat window** — the Claude app, ChatGPT, Gemini | One click away, always works, never needs setup, never breaks | It holds none of the organization's own knowledge, method, or integrations, and it cannot act on the person's real systems. This is the **Habit** force, and it is not laziness: the generic tool is one click away while the powerful one used to require a terminal. Control Tower's whole job on this axis is to make the powerful path the one that is already set up |
| **B2 / B5 — know whether the machine is right** | **Ask the one person who could tell**, or find out when something breaks | Authoritative, when that person is available | It routes every question through a single human bottleneck, and it means the honest answer to "is my machine correct?" is usually "nobody has looked" |
| **E1–E4 — stand an organization up** | **Hand-created repositories and hand-set access**, guided by a runbook | Fully understood by whoever does it, and adaptable mid-flight | Non-idempotent, unauditable afterwards, and impossible to resume safely from an interruption. The state of the organization lives in one person's memory of what they did |
| **B8 — get a tool you are entitled to** | **File an IT ticket** | Legible, has an owner, leaves a record | The latency kills the impulse. By the time it lands, the reason for wanting it has passed — which is how organizations end up with people who stop asking |
| **B9 — recover from a bad update** | **Improvise**, or wait for the person who knows | Sometimes fast | Undignified and unrepeatable. A non-technical person has no recovery path at all, which is Anxiety #1 and the direct reason every release names a rollback artifact |
| **All of it** | **Do without.** Stay inside the software IT handed you | Zero risk, zero effort, zero blame | This is the real incumbent, and it wins by default. It is also the entire cost this product exists to remove: the superpowers are real, and almost nobody can reach them |

### Why they have not switched already

Read against those alternatives, the Moments forces explain the inertia precisely. **Push** is real but unevenly felt: the author feels it acutely and daily, while Bob feels only a vague sense of missing out, because you cannot miss what you have never been able to reach. **Pull** is strong but abstract until the person has actually seen the roster of what they get — which is why the "what you're getting" and "your connections" steps are load-bearing rather than decorative. **Anxiety** is the binding constraint, and it is specific rather than general: *what if it breaks and I cannot get back*, *what if my private material ends up somewhere public*, *what if it quietly destroys work I own* — the third of which is no longer hypothetical. **Habit** is the quiet killer: the generic chat window is one click away and always works.

The practical consequence for design is that **anxiety must be answered structurally before pull is worth increasing.** Marketing the superpowers harder to a person who is afraid of losing control produces nothing at all. That is why the product spends so much of its surface on preflight, on named honest states, on rollback, and on refusing to say "nothing changed" without an empty ledger to back it — and why it spends none of that surface on celebration.

---

**Related:** [Journey Maps](20-journey-maps.md) | [Moments That Matter](40-moments-that-matter.md)
