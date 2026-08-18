# Copilot Control Tower — SOUL

> **The decision instrument. When in doubt, consult this file.**
> Not a vision statement and not a brand poster — the tool you use to decide whether a proposed feature *belongs* here. Run anything through **§5 Feature Filter**, gates in order. If it cannot survive in under a minute, the answer is **no**. It sits on top of `docs/product-design/00-overview/00-vision.md` (what the product *is*) and the six invariants in `CLAUDE.md` (its spine). Those say what the product does; this says **what is allowed to exist in it**.

> **STATUS: RATIFIED v2.0 — 2026-08-02.** Describes **v0.4.0** (build 19, embedded helper `cc 2.2.0`). Status: **DOGFOODING** — live on exactly one organization (ENAC), 16/16 layers applied live, not offered outside, not generally available. Rebuilt from evidence after the documentation drifted from a shipping product; the v1.0–v1.4 decision history carries forward with its original dates in §9.

<!--
Essentialism lens (Rams / Ive). The essence is DEMOCRATIZATION. The only way an always-on agent earns the right to deliver that unattended is TRUST, and trust here is earned by SUBTRACTION — nearly every "obvious" feature in this product is a trust regression. §2, §3 and §4 are the load-bearing sections: they exist to stop a well-meaning contributor from adding this product to death. Every dated anti-pattern actually happened. Read them before you build anything.
-->

---

## 1. The Job

**When** I have been handed an AI ecosystem that only a technical person could install, **I want to** get all of it working on my own Mac and have it stay working without my attention, **so I can** use a technical person's superpowers without becoming one — and without ever having to check whether it is really still working.

**The struggling moment.** The superpowers are real and almost nobody can reach them. The ecosystem lets a proficient person write well, check numbers, build software that does part of their own job, and integrate systems — but that intelligence is CLI-shaped, and the CLI shape is a wall. The typical worker uses only the software IT handed them, the way it was handed to them, and does not deviate. Meanwhile keeping it alive was a person, not a system: the owner carried it by hand across two machines just to reach parity — *"that shit gets exhausting"* (Pablo, 2026-07-06). The obvious fix — an always-on, token-holding agent on every machine — is exactly the shape of software a security team refuses to trust unless it can audit it. The trade-off on the table: democratize and accept an unauditable background agent, or stay safe and leave every non-technical employee behind.

**The reframe that matters.** This product is not hired to manage an ecosystem. It is hired to **make an unverifiable system trustworthy enough to be left alone by someone who cannot check it.** "Get it working" is a setup job, finished the day it finishes. "Stay working without my attention, and without my having to check" is a **trust job**, renewed every day the person does not open the popover. That is why the most important state is silence, and why a false green is not a bug class but a violation of the job itself.

**Who this serves:**

| User | What they need | Evidence |
|---|---|---|
| **Bob — the change-averse non-technical consumer** (primary) | A working, team-scoped set of copilots from one double-click; an icon that never lies; to be asked *only* about his own data. "Bob is not a reliable actor" is load-bearing, not a slight — nothing safety-critical may depend on him noticing anything. He is a psychology, not a job title, and the fear is professional consequence: he *will* catch a dishonest status. | **GROUNDED** in real people. **Never validated** — no non-technical person has completed the journey |
| **Earl — the IT / admin operator** (the enabler, never co-equal) | To stand an organization up from a guided tool and docs alone, see exactly what will be created before anything is, and hand over a report rather than a recollection. | **RUN ONCE, BY THE AUTHOR.** No third-party operator has ever touched Admin mode |
| **The trained early-adopter author** (the writable tier) | To author shared content in a markdown editor and have it reach the department, without ever being forced to become a Git user. | **MODEL-IN-HEAD, partly contradicted.** Never run with more than one writer; the one elevation attempt produced the 12,537-line deletion |
| **Pablo — owner and trust basis** | An agent that makes the ecosystem *safer* to adopt than the manual path, and releases him from being the sync layer. | **OBSERVED** daily; the direct origin of the product |
| **The user over time** | Months untouched, still healed and honestly-statused; authorized change simply appears, personal work untouched. | **DEMONSTRATED** on one machine. The second machine (V-5) is unproven |

---

## 2. The Essence

**Soul statement:** Copilot Control Tower **puts a technical person's AI superpowers into a non-technical person's hands and keeps them there without that person's attention** — earning the right to run unattended by rendering the CLI's verified truth, computing nothing of its own, and never claiming anything it cannot prove.

**Essence in one word: democratization.** Organizations are the *buyer*; the individual is where the value lands. *Parse, never compute* is not the essence — it is **how the product earns the right** to run in the background and deliver it. A feature that transforms an organization while requiring its people to be technical has failed this product's reason to exist.

**The deeper aim:** that the power one proficient person wields daily becomes reachable by anyone in a company, and that an enterprise can adopt an always-on, token-holding, auto-materializing agent and *trust it more* than the manual path it replaces — because the agent is open, legible, policy-bounded, and auditable by subtraction.

**As a person, this product would be** an air-traffic controller, and specifically **a witness under oath**: it reports what it saw, states plainly what it could not see, and never fills the gap. When it has nothing to say, it says nothing, and that silence is the signal. **It would NOT be** a co-pilot with opinions, a dashboard that decorates, a chatty assistant that scores its own health — or a tool that says "nothing changed" because that is the comfortable thing to say.

| It IS | It IS NOT |
|---|---|
| A **renderer over a versioned contract** — it parses `--json` and shows the result | A **resolver**. It computes nothing: no resolution, health score, signature check, merge or wipe. If Control Tower vanished, the CLI would still be correct |
| A **face and supervisor** for one person's own Mac | An **MDM / fleet tool**. MDM is dropped completely (D4) — no `.mobileconfig`, no Jamf/Kandji/Intune, no forced config domain, no fleet dashboard. Entitlement is GitHub repository access; install is a self-install |
| A tower that **watches and reports** | A **second pilot or agent that decides things**. No model-driven judgment, no chat surface. It renders a verdict; it never generates one |
| An **instrument** — one honest state, one sentence, one thing to do | A **dashboard**. No computed score, no sparkline, no trophy ring, no aggregate number implying the app judged anything |
| A surface that shows **folders and accounts** in a person's own words | A **Git client**. Conflict markers, detached-HEAD warnings and non-fast-forward rejections are the product's to absorb, never to forward |
| A carrier for the **CSE tooling components** — Knowledge, CLI, and the Claude/Codex instruction layer — across foundation → org → dept → personal | A syncer of **the products you build**. A project is self-contained (D10). *Control Tower syncs the tooling you build WITH, never the products you build* |
| A **cadence** carrier with a manual `Sync now` escape hatch | A **real-time refresher**: *"I can rarely imagine a moment where someone updates something that someone needs right now"* |
| A wall that makes personal → shared crossing **impossible by construction** | A path that lets private content reach a shared tier by accident, guarded only by discipline or a dialog |
| **Pure OSS, free forever** — openness *is* the security guarantee | A product with a paid tier, enterprise SKU, hosted service, or one closed component |

**Key boundary — read this twice.** The line everyone pushes on is **"can't the app just work this one thing out?"** — a health guess when offline, a blended status, a quick resolution, a convenience override. No, categorically. The one condition under which a borderline capability is allowed: **it renders or automates something the CLI already computed and verified, and adds zero judgment of its own.** The v0.4.0 connections roster is the model — the app filters purely on the CLI-computed `secret_state`, never inspects a secret value, and groups an unrecognized future state as *not available* rather than ready.

---

## 3. Design Principles

*Five named principles. Each kills a real feature. A principle that offends no one is decoration.*

### Principle 1: Say only what you can prove
**Meaning:** Every claim — about the past, the present, or its own intent — must be backed by evidence the product can point to *as it makes the claim*: a ledger, a re-run, a verified postcondition. Missing evidence degrades to an honest unknown, never to optimism. **Rejection:** We reject **"nothing changed" as a default message** — it is legal only against an empty completed-actions ledger. Equally: percentages and countdowns (a promise the app cannot keep), the celebratory green (a reward for a state it cannot re-prove), and the last-known-good fallback when the pipeline cannot answer. **Test:** *What evidence backs this claim, and what does it say when that evidence is absent?* If the answer is "it assumes" → reject.

### Principle 2: Parse, never compute
**Meaning:** Control Tower calls CLI verbs and renders the result. It holds **no** resolution, sync, signature, merge or wipe logic of its own. There is exactly one source of truth and it is not this app. **Rejection:** We reject **offline health scoring** — any path that lets the app decide a machine is healthy, resolve a conflict, or verify a signature it did not parse from the CLI. "So it still works offline" is not a reason; *waiting for network* is the answer. **Test:** *Does this require the app to compute ecosystem state?* If yes → it belongs in the CLI. Stop.

### Principle 3: Plain words, or nothing
**Meaning:** The reader must never need to understand the machinery to act correctly. A string that is accurate but requires knowing what a layer, a rank or a manifest is has failed the product's purpose, no matter how true it is. **Rejection:** We reject **any surface that renders an internal token to a person** — layer id, severity raw value, rank, manifest field. It equally rejects asking a person to author or rank a layer manifest: not a design trade-off, wrong on its face. **Test:** *Could someone who does not know what a layer or a manifest is read this and act correctly, unaided?* If no → rewrite or cut.

### Principle 4: Route by actor-competence × reversibility, not by event-class
**Meaning:** For every event, ask who is the *sole competent actor* and whether the action is *reversible*. Auto-act on reversible things the person cannot judge; route what they cannot action to whoever holds the authority; ask them only about non-deferrable decisions on their own material. **Rejection:** We reject **notify-and-hope** — routing a decision to whoever is standing at the menu bar. Letting someone approve a held major to clear a badge, or notifying them about a prune they cannot action, are both this failure. An unactionable notification spends the credibility of the one alert that matters. **Test:** *Who is the sole competent actor, and is the action reversible?* If the answer is not "this person, about their own material," it does not become their prompt.

### Principle 5: As little app as possible
**Meaning:** One signed binary. No daemon, no fallback loop, no heavy framework, no bypass flags. Trust comes from *less* surface an enterprise review must audit — and one person builds, signs and releases this, so smallness is survival, not aesthetics. **Rejection:** We reject **any surface that grows the audit burden without serving the essential job** — a chat UI, a settings panel that repoints the update feed, a second scheduler, `KeepAlive=true`, an in-app auto-updater. **Test:** *Does this add audit surface, and does the essential job survive without it?* If both → cut it.

### When Principles Conflict

**Priority order — settled:** **Say-only-what-you-can-prove > Parse-never-compute > Plain-words-or-nothing > Route-by-competence × reversibility > As-little-app.** Above all five sits the inviolable, non-tradeable constraint **security-posture-never-weakened** (invariant #4).

Parse-never-compute is the structural mechanism that makes honesty true for *state*, but it is subordinate to honesty itself — and the difference is not theoretical. On 2026-07-31 the app faithfully rendered a CLI claim that was false: parse-never-compute was satisfied and the person was still lied to. When faithful rendering would carry an unproven claim, the answer is never for the app to compute a correction — it is to refuse to render the claim as a claim, and to fix the proof upstream. Plain-words outranks routing because a correctly-routed sentence nobody can read has not been routed at all. As-little-app is the constant background pressure and the tie-breaker, but it never overrides honesty: an *added honest state* is worth its surface, because a false green is the one outcome worse than more UI.

---

## 4. Anti-Patterns

*Named failure modes. Every one below with a date has already happened to this product.*

### The Comfortable Lie
**Drift:** "The run stopped, so say it stopped. Nobody wants a wall of partial detail." **Why it kills us:** `2026-07-31` — 0.2.4's first live apply told the owner setup stopped *"before changing anything"* when two Personal GitHub repositories had already been created and seeded. The one product whose whole promise is honesty said something untrue about a person's own accounts. What they conclude is not "there is a bug" — it is *"this thing tells me what it wants me to hear,"* and there is no route back from that. **Early warning:** "just say it failed," "nobody needs the detail," "show progress as a percentage," "add a success toast," "keep showing the last known state so it doesn't look broken." **Line in the sand:** All deterministic preflight before any irreversible write; a completed-actions ledger threaded through **every** exit path including the failing ones; `HEAD == target` asserted as a postcondition; *held* never rendered as *blocked*. "Nothing changed" is legal only against an empty ledger.

### The Second Pilot *(and its AI-shaped form, The Copilot of the Copilot)*
**Drift:** "Let the app work out that the machine is fine when the CLI is slow or offline — a little local score, a quick resolution, an inline signature check." Or its modern costume: "add a chat box so people can ask if their Mac is okay." **Why it kills us:** Two sources of truth, and the app's is the one that can be wrong. `Through v0.2.3` a GitHub repo or a hidden mirror counted as an installed layer, so a person saw a green Personal result with no visible folder on their disk (fixed in 0.2.4, ADR-005). A model-driven surface is the same failure with better manners. **Early warning:** "so it works offline," "just a quick score," "the app can tell," "we already have the data," "add a chat," "let it reason about your setup." **Line in the sand:** Zero resolution/health/signature/merge/wipe logic in the app. No AI or conversational surface. Offline or unreadable is an *honest state*, never a fabricated green.

### The Quiet Bulldozer
**Drift:** "Point the materialize target at the real content directory — simpler than a mirror, and the reconcile keeps it tidy." **Why it kills us:** `2026-07-27` — `~/.claude/knowledge` was a symlink into the organization's authoring checkout *and* `cc update`'s materialize target. One routine update reconcile-deleted **12,537 lines** of org content in a single commit, which a backup cron then pushed to origin. "What if it quietly destroys work I own?" stopped being hypothetical that day. **Early warning:** "just symlink it," "the reconcile will clean that up," "easier if they share a directory," "we can restore from git." **Line in the sand:** Every visible working tree is human-owned — reuse a clean checkout or fast-forward it, never reset a dirty one. Refuse to write or delete through any symlink escaping the materialize root, and report that refusal as an honest *held* item.

### The Contract That Drifted
**Drift:** "It's just a field rename. Nothing consumes the old name any more." Version tolerance always looks like graciousness. **Why it kills us:** `2026-07-28` — a manifest field was renamed `component:` → `product:` while one resolver still filtered the old name. The org overlay vanished, the organization's own command disappeared, an *optional* notification hook exited non-zero, and **Claude Code rejected every prompt on the machine.** An optional Discord bridge became a total harness outage. **Early warning:** "backwards compatible enough," "we'll tolerate both shapes," "the mock passes," "an empty array just means nothing to report." **Line in the sand:** The schema gate is per-verb, exact-major and fail-closed; `schema_version` is decoded before any other field is trusted; a missing security field fails closed. Typed absence over ambiguous emptiness (ADR-007). Optional transports fail **open**. Release gates run against the **packaged** artifact — the prior gates all passed while source and signed binary disagreed on a user-visible field.

### The Machine Talking To Itself
**Drift:** "It's only the detail line — we already have the raw values." Jargon never arrives as a decision; it arrives as a default. **Why it kills us:** It breaks the essence directly, and **it is live right now.** `native/control-tower-tray.swift:1375` renders each component's detail as `foundation: pass · org: warn · department: … · personal: …` on the most-read surface in the product, while the ratified plain labels (`Core setup`, `Your organization`, `Your department`, `This Mac`) sit twenty-five lines earlier, scoped private to a different view and bypassed. A raw severity token also reaches the accessibility label. The jargon firewall exists; this surface routes around it. **Early warning:** "it's just the subtitle," "power users prefer the real names," "we can map it later," "the raw value is more precise." **Line in the sand:** No internal token — layer id, severity raw value, rank, manifest field — reaches any user-facing string, tooltip, or accessibility label. Mapping happens at the boundary, once, for every surface.

### The Alert Machine
**Drift:** "They should know what's happening — surface the prunes, the policy denials, the held major. Let them unblock a stuck update instead of waiting on IT." **Why it kills us:** Every alert a person cannot act on burns down the credibility of the one that matters, and the security alert that must land gets lost among the ten that should never have fired. **Early warning:** "notify them when…," "let the user approve," "add a badge so they can clear it," "empower the employee to self-serve," "just show them the log." **Line in the sand:** Route by who can act; the person-facing interrupt count trends toward zero. Nobody is asked to judge a held major, clear a policy denial, or self-unblock a gated update. A `Try again` button may exist only where the blocker can actually change.

### The Convenience Backdoor
**Drift:** "Give us `--force` to unstick a machine. Read the update feed from user preferences so power users can point at a mirror. Set `KeepAlive=true` so the tray never dies." Every one solves a real support case. **Why it kills us:** The whole safety claim is that the agent runs the *same* pipeline with *zero* bypass flags. A preference write that repoints the update feed is remote code execution with extra steps; `KeepAlive=true` resurrects a bad build into a crash loop. One backdoor and the review that gates all adoption ends in a no. **Early warning:** "just this once to unstick it," "a power-user mode," "read it from prefs," "make it never die," "add an override." **Line in the sand:** No bypass flag, no lower-bar mode, no "make it healthy anyway" ever exists in the codebase. Security-sensitive config only via compiled-in trust roots and signed, inherited config. `KeepAlive` is never `true`. Trust roots are compiled-in code, not configuration.

### The Leak
**Drift:** "Push everything through one remote and sort the tiers out later. We'll filter personal content on push." **Why it kills us:** Private content in an org or public repository is **irreversible** — a wipe cannot un-exfiltrate. A detail-oriented person who sees that boundary breached once never trusts the tool again. Reversibility does not save you, so the class must be *prevented, not detected*. **Early warning:** "one remote for everything," "we'll filter on push," "just don't put personal stuff there," "a warning dialog is enough." **Line in the sand:** Separate trees, separate remotes, tier-scoped and fail-closed. The scheduled path holds **no upward push credential** to any shared remote. Secrets never enter inheritance content or any git repo at any tier — references only, never values. The leak-scan is a backstop, not the guarantee.

### The Git Error To A Non-Technical Person
**Drift:** "Just surface the merge conflict — show the markers and let them resolve it; every developer does." **Why it kills us:** A raw VCS failure reads as *the tool broke my work* — the worst outcome for the most detail-oriented persona, and a trust break that does not heal. Collaborative tiers are the product's own doing, so the failures they introduce are the product's to absorb. `2026-07-31, live:` the string *"An existing GitHub SSH alias is user-managed; setup did not replace it"* reached a screen, and produced the H4 holding variant as its answer. **Early warning:** "show the conflict," "let them resolve it," "it's just a merge," "they can learn Git," "surface the raw error." **Line in the sand:** A collaborative conflict resolves invisibly with no data loss, or it holds safely and escalates to a competent author. A CLI string is framed verbatim under *What setup found:* only when it was written for a person; otherwise it goes into a collapsed support block. Never a headline, never concatenated into an app sentence.

### The Ledger That Learns to Bill
**Drift:** "Fleet observability is genuinely valuable — an enterprise tier or a hosted dashboard could fund the work." **Why it kills us:** Openness *is* the security guarantee. An always-on token-holder that materializes executable-adjacent content is trustworthy only if fully auditable, so a closed component undermines the reason to exist — and gates every other job, since a review that ends in no means none of the rest ever happens. **Early warning:** "enterprise SKU," "hosted version," "premium tier," "just this one closed component," "we could charge for the dashboard." **Line in the sand:** Pure OSS, free forever. No paid tier, no enterprise SKU, no hosted service, no closed component. Success is adoption, trust and reliability — never revenue.

---

## 5. Feature Filter

Use these gates **in order**. A feature must pass **all six**. Ordered cheapest-to-evaluate first, so most bad ideas die in the first two.

### Gate 1: Compute Test
> "Does this require the app to compute ecosystem state — resolve, score, verify, merge, prune, or wipe?"

Yes → it belongs in the CLI, not here. **Stop.**

### Gate 2: Proof Test
> "At the moment this makes a claim, what evidence backs it — and what does it say when that evidence is missing?"

If it assumes, defaults optimistically, estimates, or celebrates a state it cannot re-prove → **redesign or reject.**

### Gate 3: Spine Test
> "Does this serve the spine — a non-technical person getting and keeping a technical person's superpowers without technical skill, without their attention, and without their personal work being touched?"

If it is merely useful → **useful is not essential. Drop it.** If it makes *consuming* the ecosystem require technical skill, it does not just miss the spine, it contradicts the essence.

### Gate 4: Plain-Words Test
> "Could someone who does not know what a layer, a rank, a manifest or a repository is read this and act correctly, unaided?"

No → **rewrite it or cut it.** Applies to every string, tooltip, and accessibility label, not just the headline.

### Gate 5: Right-Actor Test
> "Is every prompt this creates routed to the sole competent actor for a reversible-or-owned decision — and does it keep the person's interrupt count near zero?"

No → **redesign the routing or reject.**

### Gate 6: Anti-Pattern Test
> "Does building this drift toward any named anti-pattern in §4 — or add audit surface the essential job survives without?"

Yes → **reject, or redesign until it doesn't.** Two are prevent-not-detect: The Leak must be impossible by construction, and a collaborative conflict must resolve invisibly or hold-and-escalate.

### Case Law (In / Out)

*Real verdicts from real decisions. Borderline calls teach the most and are marked.*

| Feature | Verdict | Gate | Reasoning |
|---|---|---|---|
| Silent, terminal-free nine-step first-run setup | **IN** | 3 | The essential job. Renders CLI phases; computes nothing |
| An icon that names the failing component ("Codex needs sign-in; Claude is fine") | **IN** | 1, 2 | A parse of `doctor --json`, worst-wins, re-derived every poll; never fabricates a verdict |
| Honest *waiting for network* / *could not check* states | **IN** | 2, 6 | Added surface, but honesty outranks as-little-app: the alternative is a false green |
| Held-vs-blocked as two distinct rendered facts | **IN** | 2 | A protective non-write and an active refusal are different facts. Conflating them turns never-destroy working correctly into "this tool is broken" |
| A completed-actions ledger on every exit path (ADR-006) | **IN** | 2 | Makes "nothing changed" checkable rather than hopeful. Required by the contract, not optional |
| Breaking `onboard` schema to 2.0 with a `layers_state` discriminator (ADR-007) | **IN** | 2, 6 | **Borderline.** Chosen over a "minor, non-breaking" framing precisely because an optimistic reader would otherwise keep misbehaving silently |
| Visible ecosystem repositories as the user-facing source locations (ADR-005) | **IN** | 2, 4 | A hidden mirror may never satisfy readiness. Names and paths are exposed; ranks stay internal |
| Seven holding variants chosen by *who owns the fix* | **IN** | 4, 5 | One generic "setup failed" conflates a fault, a courtesy, a wait, and someone else's homework |
| The v0.4.0 connections roster (CLI-computed `secret_state`) | **IN** | 1, 3 | The app never inspects a secret value; an unrecognized state groups as *not available*, never as ready. Invariant #1 working as designed |
| Twelve closed badge tokens, shape before colour | **IN** | 2, 6 | Honest status must survive a monochrome and colour-blind render |
| Dogfooding ENAC directly, no throwaway practice org (ADR-003) | **IN** | 3 | **Borderline.** The safer-looking rehearsal would have tested an easier problem; ENAC is publisher and first consumer at once |
| One GitHub org, no second company (ADR-001) | **IN** | 6 | The confidentiality boundary is the repository, not the organization |
| A ninth `parentless-snapshot-match` state in a closed classifier | **IN** | 2 | **Borderline** — adding to a closed set is normally a smell. Here a snapshot pin can never be an ancestor either direction, so a byte-identical checkout blocked forever with no action anyone could take |
| Adopting, not deleting, a repo or SSH key the transaction itself created | **IN** | 6 | **Borderline** — looks like never-destroy applied to the product's own mess. An automated delete the CLI cannot prove is safe to reverse is the larger blast radius |
| Deferring the `repair` and `publish` verbs (ADR-008) | **IN** *(as a deferral)* | 1, 6 | **The sharpest call in the record.** `publish`'s design — auto-merge → keep-yours/theirs/**both** → park-and-escalate — was *ratified at soul v1.2* as the answer to The Git Error To A Non-Technical Person, then formally deferred 2026-07-31. Holding the line meant admitting a soul-ratified answer is a design record, not shipping code. A parallel `repair` would create two sources of truth for the same git facts |
| Offline health scoring so the icon "still works" | **OUT** | 1 | The Second Pilot. A computed verdict is a second, wrong source of truth |
| `--force` / `--skip-verify` / "make it healthy anyway" / `KeepAlive=true` | **OUT** | 6 | The Convenience Backdoor. The safety claim is zero bypass flags, and an always-restart watchdog turns a bad build into a crash loop |
| Reading the update feed or a mirror from user preferences | **OUT** | 6 | A preference write becomes remote code execution. Trust roots are code, not configuration |
| Screen-scraping human CLI output instead of `--json` | **OUT** | 1 | A misread `fail` → `pass` shows green over red — the highest integration risk in the product |
| Percentages, countdowns, or time estimates | **OUT** | 2 | An estimate is a promise the app cannot keep. Name the phase |
| A celebratory green — fill, checkmark, confetti | **OUT** | 2, 6 | Healthy is the *absence* of signal, never a reward. The strongest word shipped is "Ready." |
| A computed "fleet health 94/100", sparkline, or trophy ring | **OUT** | 1, 6 | The Second Pilot as a *visual*: a number that looks computed-by-us implies the app judged health |
| MDM in any capacity — `.mobileconfig`, Jamf/Kandji/Intune, a forced config domain (D4) | **OUT** | 6 | Dropped completely as a mechanism, not deferred. Entitlement is repository access; install is a self-install |
| Windows | **OUT** | 3, 6 | Formally out of scope. The Windows tree describes a retired implementation that never once ran on Windows |
| Syncing the products and projects people build (D1/D10) | **OUT** | 3 | A project is self-contained. Control Tower syncs the tooling you build WITH, never the products you build |
| Telemetry, an analytics emitter, or any fleet view | **OUT** | 2, 6 | Nothing is collected, so nothing about a fleet may be claimed. A future emitter must make a personal item name un-emittable by construction |
| In-app self-update | **OUT** | 6 | Install-a-DMG and roll-back-a-DMG is a smaller, more auditable surface |
| Secrets committed to any tier's git repo, public or private | **OUT** | 6 | Git is a distribution and history mechanism, not a trust boundary |
| A git push credential placed in a shared or managed secret store | **OUT** | 6 | Push credentials are always per-user and on-device; a shared one recreates the attribution and blast-radius problem for the one class that must stay personal |
| Real-time / per-minute refresh of inherited content | **OUT** | 3 | Cadence is correct; `Sync now` covers the rare urgent case |

*Rows that would only restate a §4 line in the sand — raw Git shown to a non-technical person, a personal→shared path, a chat surface, a paid tier, colour-only status, asking a person to rank a manifest, letting someone approve a held major — are deliberately not repeated here. §4 is where they live, and it states them with more force.*

---

## 6. Quality Bar

**The standard:** done means an enterprise security team can audit the always-on agent and accept it as *safer than a human running `copilot update` by hand* — and a non-technical person never once had to be technical. "Working" is a running tray; "done" is a trustworthy one.

**Non-negotiables** (each checkable yes/no):

- [ ] Zero resolution / health / signature / merge / wipe logic in the app codebase.
- [ ] Exactly one signed binary; no headless daemon; no in-app fallback loop; `KeepAlive` never `true`.
- [ ] No `--force` / `--skip-verify` path exists anywhere; security-sensitive config read only from compiled-in trust roots and signed, inherited config.
- [ ] No code path can fabricate a healthy state; a missing security field in `--json` fails closed.
- [ ] Every user-facing claim about what happened is backed by a ledger, a re-run, or an asserted postcondition — and "nothing changed" appears only against an empty ledger.
- [ ] All deterministic preflight runs before the first irreversible write; a blocked row produces zero mutations.
- [ ] No internal token (layer id, severity raw value, rank, manifest field) reaches any string, tooltip, or accessibility label.
- [ ] Every escalation traces to auto-act / route-to-authority / ask-the-owner by the competence matrix; person-facing interrupt count trends toward zero.
- [ ] Never overwrites, resets, rebases, merges, deletes, or pushes a dirty human-owned working tree. Setup may append one ordinary local checkpoint commit in an eligible Product project when it can preserve the complete tracked/untracked work and prior index; it never checkpoints an ecosystem repository. Never write or delete through a symlink escaping the materialize root.
- [ ] Release gates run against the **packaged, signed** artifact, not a mock.
- [ ] Every release note names the prior signed DMG as the rollback artifact; release tags are immutable and a defective build is superseded, never moved.

**What this bar does not yet enforce — stated because a soul that claims a bar the product does not meet is itself a Comfortable Lie:**

- **G-1 — the invariants are stated but not enforced.** All forty `fitness_*.rs` tests scanned `src-tauri/src/**`, the retired Rust tree, which was removed from this repository in commit `chore: remove retired src-tauri tree`; it survives only in git history; they never saw a single line of the shipping Swift, and the CI job that ran them is disabled behind a repository variable. The six invariants in `CLAUDE.md` are architectural commitments upheld by architecture, review, and the shell release gates — **not** automatically-enforced properties of the shipping binary. Porting the suite to scan `native/*.swift` and re-enabling the job is an open item, ratified as documented-not-fixed on 2026-08-02 (A-5).
- **G-2 — invariant #2's watchdog is not implemented.** The crash-only `launchd` watchdog (`KeepAlive={SuccessfulExit:false}`) exists only in the retired Rust tree. The packaging assets and a fitness test for the plist exist; the shipping Swift app does not install or manage it. The invariant stands as the design position; the absence is the current state.
- **The primary persona has never touched the product.** No non-technical person has completed the journey, no second writer has authored, and the second machine has not cold-started (V-5). Everything designed for that persona is high-quality design against an unvalidated model.

**Taste test:** if the tray has to explain itself, it failed. A glance should answer "is it OK, and do I have to do anything?" in half a second, in one plain sentence that names the failing component — no jargon, no blended verdict, no reassurance it cannot back. When everything is fine, it is silent. Silence you can trust is the whole aesthetic.

**Quality failure modes:**

| Failure | Symptom |
|---|---|
| False green | The icon is quiet over a mis-provisioned or drifted machine — or a hidden mirror counts as an installed layer |
| Unbacked claim | A screen states what happened without a ledger, a postcondition, or a re-run behind it |
| Blended status | "Needs attention" that never says *which* component — the person learns a blur, not a fact |
| Jargon leak | An internal token reaches a person's screen or their screen reader |
| Alert fatigue | Interrupts a person cannot understand or action, and they start ignoring the app |
| Silent computation | Health, resolution or signature logic creeps into the app — a design failure regardless of metrics |

---

## 7. Voice & Tone

**Character:** a calm operator who refuses to guess — **a witness under oath.** It reports what it saw, states plainly what it could not see, and never fills the gap. It speaks in the first person about its own acts and limits ("I can't read this"), in the second person about the person's things ("your organization", "your own work"), and it pairs every limit with a preservation guarantee. It never hypes, never reassures beyond what it can prove, never uses "AI" as a flourish. Success is understated to the point of near-silence: the strongest celebratory word in the entire product is **"Ready."**

**Language rules** (left column quoted from shipping strings):

| We Say | We Don't Say |
|---|---|
| "I can't read the setup right now, so I won't guess." | "Something went wrong. Please try again." |
| "I found something that belongs to you, so I left it alone and stopped before changing anything." | "Setup failed: existing repository detected." |
| "Nothing was changed, moved, or removed." | *(silence about what was preserved)* |
| "Codex Copilot needs you to sign in. Everything else is fine." | "Something needs your attention." |
| "Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up." | "Schema version mismatch (expected 2.0, got 1.0)." |
| "Setting up…" / "Checking…" / "Connecting securely to GitHub…" | "About 2 minutes remaining" / "64% complete" |
| "Everything is set up." | "All good! 🎉" |
| "Core setup · Your organization · Your department · This Mac" | "foundation · org · department · personal" |
| "whoever looks after your Mac" | "your IT administrator" / "contact support" |
| "This app never manages people. GitHub does." | "Manage your team's access here." |

**Tone shifts:**

| Context | Tone |
|---|---|
| Everything fine | Silent. The best message is no message, and there is no reward mark |
| Honest holding state (offline, could not check, org-incomplete) | Calm and specific — names the state and who owns fixing it, no alarm |
| A courtesy stop (something of theirs was found and left alone) | Warm, blue, never orange. Never the words *paused, stopped, problem, error*. Primary action: `Keep what I have` |
| Only-they-can-do-it (their sign-in, their unsaved work) | Direct, singular, respectful of their ownership. No timer, because the bottleneck is a person |
| Security event, auto-acted | Quiet and past tense to the person; content-free and immediate to whoever holds authority |
| Bad-update rollback | Reassuring understatement — "Your previous setup was preserved in a rollback copy" |
| The one sanctioned emotional peak | "You have the tools. Now go change the world!" — the owner's own words, on the Done screen, and nowhere else |

---

## 8. Success Signals

**Positive signals — things we would be thrilled to overhear:**

- "I double-clicked once and had a working set of copilots scoped to my team. I never opened a terminal."
- "It found something of mine and left it alone, and it told me so in a way that did not make me feel stupid." *(The sentence a person repeats to a colleague. Nobody tells a story about a green icon.)*
- "I stopped checking it months ago."
- "It only ever asks me about my own stuff."
- "I stood the whole organization up from the app and the docs alone — I never hand-edited YAML, and the check told me what was really on GitHub."
- "Our security team read the source and said yes."

**Drift signals — the earliest outside sign we are losing the soul:**

| Signal | What it means |
|---|---|
| A screen states an outcome that nothing in the ledger backs | The Comfortable Lie is returning. This fires before anyone finds the false claim |
| Someone proposes an "offline mode" that shows status | The Second Pilot is knocking; an honest holding state is about to be replaced by a guess |
| A false green appears in the field | Parse-never-compute or the fail-closed gate has already broken |
| A new string ships containing an internal token | The jargon firewall is being routed around again — check the accessibility labels first, they leak before the headlines do |
| The person-facing interrupt count is climbing | The Alert Machine is winning; routing-by-competence is eroding |
| A support answer is "just force it" or "toggle the override" | A convenience backdoor exists or is being asked for; the safety claim is cracking |
| A roadmap line mentions a tier, a hosted service, a chat box, or a fleet score | The Ledger, the Copilot-of-the-Copilot, or the dashboard drift is arriving |
| A "compatible enough" version tolerance is proposed anywhere in the contract | The Contract That Drifted is repeating; the last one took every prompt on a machine down |
| The word "symlink" appears in a materialize or elevation proposal | The Quiet Bulldozer. Twelve thousand lines, once already |

**Recovery questions:**

1. If Control Tower vanished right now, would the CLI still be correct — and does this feature keep that true?
2. What evidence backs this claim at the moment it is made, and what does it say when that evidence is missing?
3. Who is the sole competent actor here, is the action reversible, and could a person who knows none of our vocabulary act on it unaided?

---

## 9. Founding Decisions

*The settled calls this instrument rests on. Each is dated, and future sessions are not free to casually reopen them.*

**Ratified 2026-07-06 (v1.0):**

1. **Pure OSS, no monetization — free and open forever.** Trust and adoption, never revenue. Openness is both the security requirement and the go-to-market. Resolves *The Ledger That Learns to Bill*.
2. **Bob-first (locked).** The non-technical consumer experience *is* the product; Admin mode is its **enabler**, first-class only where it makes a working consumer possible. When the two faces pull apart, the consumer wins.
3. **Success is trust + adoption + reliability.** False-green and security-shadow-miss are hard-zero invariants, not tuning targets.
4. **Name and identity.** The product is **"Copilot Control Tower"** and it is shown to the end user. The tray mark is the **aviator-sunglasses glyph**. **"Aviator" is a dead engineering codename** and never appears as a product name on any user-facing surface.
5. **Parse-never-compute is inviolable as the mechanism for state.** Offline or unreadable is an honest state, never a fabricated verdict. Resolves *The Second Pilot*.
6. **Security posture is inherited and never weakened** — a constraint above the principles, not a tradeable one. No bypass flags, no lower-bar mode, compiled-in trust roots plus signed inherited config only, `KeepAlive` never `true`. Resolves *The Convenience Backdoor*.

**Ratified 2026-07-06 (v1.1, owner interview):**

7. **Evidence-honesty on the unvalidated tiers.** The Admin/IT-operator experience and the multi-writer authoring flow are **hypotheses, not validated ground**. *(Status 2026-08-02: Admin has been run once, by the author; the multi-writer loop still has never run with more than one writer. Not upgraded.)*
8. **The anti-patterns are named and kept:** The Comfortable Lie · The Second Pilot (with The Copilot of the Copilot folded in) · The Quiet Bulldozer · The Contract That Drifted · The Machine Talking To Itself · The Alert Machine · The Convenience Backdoor · The Leak · The Git Error To A Non-Technical Person · The Ledger That Learns to Bill.

**Ratified 2026-07-07 (v1.2–v1.3):**

9. **The four inheritance-safety rules**, elevated to `CLAUDE.md` invariants: secrets never enter inheritance content or any git repo (references only); no cross-tier write capability from a personal-holding path; sync is pull-only and downward, all upward movement separate and human-invoked; a fail-closed leak-scan on every writable push as a **backstop only** — the real guarantee is structural separation.
10. **The credentials carrier is the per-user OS keychain and/or a tier-scoped managed secret store** whose endpoint travels in inherited org config (the endpoint is not a secret; access stays gated by GitHub-team membership). Git is permanently excluded at every tier; **push credentials are always per-user and on-device.**
11. **The writable-tier / never-destroy tension was apparent, not real.** Never-destroy governs the pull side; collaborative conflict lives on a publish side it never covered. The consumer-read-only / author-writable split keeps invariant #3 intact.

**Ratified 2026-07-09 (v1.4, CSE alignment):**

12. **Control Tower syncs the CSE tooling components, never the products built with them (D1/D2).** A project is self-contained, not a Control Tower layer (D10).
13. **MDM is dropped completely as a mechanism (D4)**; **entitlement is GitHub repository access (D3)**, the single spine. Offboarding is revoke-access plus rotate-store-tokens, with the honest accepted residual that content already on a departed person's disk is not remotely wiped.

**Ratified 2026-07-31 (initiative ADRs, all Accepted):**

14. **Ecosystem setup is a preflighted saga, not an atomic transaction (ADR-006).** Cross-system atomicity is not available, so a truthful partial-progress record replaces a false all-or-nothing claim: nine closed history states, only a merge-base-proven fast-forward may auto-repair, a required ledger, a `HEAD == target` postcondition. Answers *The Comfortable Lie*.
15. **Typed absence over ambiguous emptiness, at the cost of a breaking bump (ADR-007).** A present-but-empty array or a skeletal row may never read as evidence. Answers *The Contract That Drifted*.
16. **`repair` and `publish` are formally deferred (ADR-008).** History remediation lives inside `cc onboard`'s routing. The `publish` design — ratified at v1.2 as the answer to *The Git Error To A Non-Technical Person* — is a **design record, not a claim that the verb exists**. No document may list either as existing; rebuilding either requires a new ADR that supersedes ADR-008.

**Ratified 2026-08-02 (v2.0):**

17. **A-1 — Audience, in weight order:** the owner's future self and session continuity; buyers and non-technical evaluators; organizations looking to change how they work. **Deliberately not an audience:** open-source contributors submitting patches, and developers receiving a handoff.
18. **A-2 — The essence remains DEMOCRATIZATION.** Organizations are the buyer; the individual is where the value lands. The Feature Filter tests against the **mechanism** (democratization), never the outcome (organizational transformation) — a reframing the owner explicitly rejected.
19. **A-3 — The honest status claim is DOGFOODING, live on one org**, 16/16 layers applied. Never "the build has not started" (false — eight version lines, seven retained signed releases), and never general availability. What remains: the V-5 cold-laptop proof, then publicize, in that order because the second is irreversible.
20. **A-4 — Killed and out-of-scope technology.** Tauri v2 / the Rust core is dead as the shipping stack (the tree stays on disk as read-only reference). Windows is **formally out of scope**, not deferred. MDM is dropped completely.
21. **A-5 — Invariant enforcement is documented honestly as a named gap** (§6, G-1 and G-2), neither fixed nor reframed away. It is the only choice consistent with this file.
22. **Priority order is settled:** Say-only-what-you-can-prove > Parse-never-compute > Plain-words-or-nothing > Route-by-competence × reversibility > As-little-app, under the inviolable constraint security-posture-never-weakened.

*Open engineering items, not soul-blocking:* personal-layer content scope (it bounds where the leak wall stands), personal-key sync across one person's own machines, signing custody (a two-of-N model is designed but not staffed), urgent-revocation propagation, the fitness-suite port (G-1), and the native watchdog (G-2).

---

## 10. Evolution

This file changes only when: real user outcomes shift what the product is for; we learn something durable that contradicts a current principle or boundary; or the product's place in its ecosystem changes. Every change is logged below with its rationale.

### Changelog

| Date | Version | Change & rationale |
|---|---|---|
| 2026-08-02 | **v2.0 RATIFIED** | **Rebuilt from evidence after the documentation drifted from a shipping product.** v1.4 described a Tauri/MDM product at v0.3.x; the real product is native SwiftUI/AppKit at **v0.4.0**, dogfooding on one org at 16/16 layers. Every founding decision from v1.0–v1.4 carries forward with its original date (§9 #1–#13); the stale technology claims are gone. **Two new principles, both earned by incidents:** *Say only what you can prove*, promoted **above** parse-never-compute because on 2026-07-31 the app satisfied parse-never-compute and still lied to a person; and *Plain words, or nothing*, which makes the democratization essence testable per string. **Four new dated anti-patterns:** The Comfortable Lie (2026-07-31), The Quiet Bulldozer (2026-07-27), The Contract That Drifted (2026-07-28), and The Machine Talking To Itself (a **live** leak at `control-tower-tray.swift:1375`). The Copilot of the Copilot folds into The Second Pilot — same failure, better manners. The filter grows to **six gates** (adding the Proof and Plain-Words tests) and the case law is repopulated from real ADRs and CSE decisions with six borderline calls marked. **§6 now states what the bar does not enforce** (G-1, G-2), because a soul claiming a bar the product does not meet is itself a Comfortable Lie. A-1…A-5 added as #17–#22. Cut hard: a decision instrument nobody can hold in their head decides nothing. **Owner ratification walk-through, 2026-08-02:** the two contested calls were put to the owner directly and both were explicitly ratified rather than assumed — (a) promoting *say-only-what-you-can-prove* **above** parse-never-compute, which subordinates `CLAUDE.md` invariant #1 to honesty, ratified on the strength of the 2026-07-31 incident; and (b) the **pure-OSS, free-forever** boundary (§2, §9 #1), re-put specifically because the newly-named buyer and organization audiences create pressure toward a paid tier, and reaffirmed as **absolute** — openness *is* the security guarantee, and *The Ledger That Learns to Bill* stands. |
| 2026-07-09 | v1.4 RATIFIED | CSE alignment: Control Tower orchestrates the **tooling** components, never the products built with them (D1/D2); a project is self-contained (D10); **MDM dropped completely** (D4), with security posture rehomed to compiled-in trust roots plus signed inherited config; entitlement is GitHub repo access (D3). Essence, principles and anti-patterns unchanged. |
| 2026-07-07 | v1.3 RATIFIED | Closed the last open foundational seam: author git-push credentials are a per-user on-device ed25519 keypair authorized by GitHub Team membership. Adopted a tier-scoped managed secret store for identity-less integration credentials; invariant #6 broadened to "keychain and/or managed store," git excluded either way. |
| 2026-07-07 | v1.2 RATIFIED | Ratified `inheritance-and-publish.md` and `credentials-and-boundary.md`. Three foundational problems resolved: the writable-tier / never-destroy tension (apparent, not real), the non-technical merge conflict (layered publish, keep-both as the no-data-loss floor), and the credentials carrier. Added the four inheritance-safety rules and elevated them to invariants. |
| 2026-07-06 | v1.1 RATIFIED | Primary-evidence owner interview. **Essence reframed to democratization**; parse-never-compute demoted from *the point* to *how it earns the right to run unattended*. Added the writable inheritance model, the author tier, and two anti-patterns: **The Leak** and **The Git Error To A Non-Technical Person**. |
| 2026-07-06 | v1.0 RATIFIED | Ratified after the design challenge. Case law populated from the Phase 3–5 verdicts; priority order confirmed; Bob-first locked; name and identity settled ("Aviator" is a dead codename). |
| 2026-07-06 | v0.1 DRAFT | Drafted as a root-level decision instrument through an essentialism (Rams/Ive) lens: trust earned by subtraction. Synthesized from vision, scope, JTBD and moments-that-matter; spine from the invariants in `CLAUDE.md`. |
