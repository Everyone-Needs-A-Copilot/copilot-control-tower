# Copilot Control Tower — SOUL

> **The decision instrument. When in doubt, consult this file.**
> Not a vision statement or a brand poster — the tool you use to decide whether a
> proposed feature *belongs* in this product by staying true to its purpose.
>
> **How to use it:** Run any feature, request, or "wouldn't it be cool if…"
> through **Section 5: Feature Filter**. Pass the gates in order. If a feature
> can't survive the filter in under a minute, the answer is **no**.
>
> **It is living.** Drafted after service design as a north star for everything
> downstream, then ratified after the design challenge once the hard calls were
> concrete. It now changes only when real evidence says the product changed —
> every change logged in **Section 10**.
>
> Sits on top of `docs/product-design/00-overview/00-vision.md` (what the product
> *is*) and the five invariants in `CLAUDE.md` (its spine). This file decides
> *what is allowed to exist in it.*

> **STATUS: RATIFIED v1.2** — drafted 2026-07-06, ratified with the owner (Pablo)
> 2026-07-06 after the design challenge (Phases 1–5 complete, design brief approved).
> **Revised to v1.1 (2026-07-06)** after a primary-evidence owner interview
> (`scratchpad/interview-ground-truth.md`) reframed the essence to **democratization**
> and surfaced the writable-inheritance / author tier, the Leak and Git-error anti-
> patterns, and three open foundational problems.
> **Revised to v1.2 (2026-07-07):** the owner ratified the two architecture/security
> designs that resolve those problems — `docs/01-architecture/inheritance-and-publish.md`
> (writable-tier vs. never-destroy; non-technical conflict resolution) and
> `docs/05-security/credentials-and-boundary.md` (credentials carrier + leakage wall).
> Three of the open foundational problems are now **RESOLVED**; four inheritance-safety
> rules are added as founding decisions and **elevated to `CLAUDE.md` invariants**; one
> credential seam (author git-push provisioning) remains the sole open foundational item.
> Supersedes the earlier stub at `docs/00-overview/soul.md`; the canonical soul is now
> this root file. Changes only on durable evidence, logged in Section 10.

<!--
  Essentialism lens (Rams / Ive): this product's essence is DEMOCRATIZATION — a
  technical person's superpowers in a non-technical person's hands — and the only
  way an always-on agent earns the right to deliver that unattended is TRUST, which
  is earned by SUBTRACTION, not addition. Nearly every "obvious" feature here is a
  trust regression. The IS-NOT table and the Anti-Patterns are therefore the
  load-bearing sections — they exist to stop a well-meaning contributor from adding
  the product to death, and (v1.1) from letting personal data leak or dumping Git on
  a non-technical person. Read them before you build anything.
-->

---

## 1. The Job

*The struggling moment this product exists to resolve, in the user's own words.*

**When** I'm a non-technical person handed the Copilot ecosystem (or the IT admin
standing it up for a company),
**I want to** get — and keep — a technical person's AI superpowers without ever
learning YAML or the terminal,
**so I can** build, answer, and integrate what I need instead of being stuck with
the software IT handed me — and trust an always-on agent to keep my environment
Copilot-ready without my attention.

**The struggling moment:**
The Copilot ecosystem already gives a *technically proficient* person real
superpowers — write well, check numbers, build software that does part of the job,
integrate data across sources. But those superpowers are **locked behind technical
proficiency:** the intelligence is **CLI-shaped**, and the CLI shape is a wall.
Almost no one inside a company can climb it; the typical worker uses only the
software IT gave them, in a fixed way, and doesn't deviate. So the power stays
undemocratized and locked to one diligent person's hands. And keeping it alive is
manual — a change made once does not land everywhere; the human *is* the sync
layer, re-updating machine after machine by hand ("that shit gets exhausting").

The mechanism that would fix this — an always-on, token-holding, self-updating
agent on every machine that quietly keeps the environment ready — is exactly the
thing an enterprise security team refuses to trust unless it can *audit* it. The
trade-off today: democratize the ecosystem and accept an unauditable background
agent, or stay safe and leave every non-technical employee behind. This product
refuses that trade-off — it earns the right to run unattended by being legible.

**Who this serves:**

*Two consumer psychographics, not one: the change-averse consumer who must feel
**SAFE**, and the trained early-adopter author who wants **POWER**. The docs used to
collapse them.*

| User | What they need | Evidence |
|------|---------------|----------|
| **Bob — change-averse non-technical consumer** (primary) | A working, team-scoped partner from one double-click (or zero, managed); an icon that never lies; to be asked *only* about his own data, *never* a decision he can't judge. **"Bob is not a reliable actor" is load-bearing.** Target emotion: comfortable *and* excited — the superpowers he's wanted his whole career. | **GROUNDED** — real people across real companies |
| **The trained early-adopter author** (the writable tier) | To author org/department content in a markdown editor (Obsidian → save → push) and have it sync across the department — power, not just safety; write access *earned and gated*, starting with a few innovators. Never forced to become a Git user to resolve a collision. | **MODEL-IN-HEAD** — never run with >1 writer |
| **Raj — IT / Admin operator** (the enabler) | To stand up and deploy the whole ecosystem from a guided tool + docs alone — no hand-YAML, no hand-crafted profiles; a fleet he can see, trust, and govern centrally. | **HYPOTHESIS** — no real IT operator has touched it |
| **Pablo — ecosystem owner / trust basis** | An always-on agent that makes the ecosystem *safer* to adopt, not riskier: open-source, reproducibly built, provably safer than a human running `copilot update` by hand — and that releases him from being the sync layer by hand across two machines. | **OBSERVED** — lived daily |
| **The user over time** | The machine stays healed, honestly-statused, and *Copilot-ready* for months untouched — an authorized upstream change simply appears on cadence, without clobbering personal work — and comes off cleanly when they leave, orphaning nothing. | **OBSERVED** (pain) / MODEL-IN-HEAD (multi-writer) |

---

## 2. The Essence

**Soul statement:**
Copilot Control Tower **gives a non-technical person the AI superpowers of a deeply
technical one — safely enough to run unattended.** It is the one-click bridge that
lets someone with "absolutely no clue" wield the Copilot ecosystem, and then
**keeps their environment Copilot-ready** — synced and self-healed on a cadence, an
authorized change made once upstream simply *appearing* on the machine without ever
touching personal work. It earns the right to run unattended the only way an
always-on, token-holding agent can: by **faithfully rendering the CLI's truth and
never computing that truth itself** — the icon that cannot lie.

**Essence, in one line:** democratization — a technical person's superpowers in a
non-technical person's hands, kept ready on its own. *"Parse, never compute"* is not
the essence; it is *how it earns the right* to run in the background.

**The deeper aim:**
That the power one proficient person wields daily becomes usable by anyone in a
company — breaking them out of the paradigm of only ever using the software IT
handed them — and that an enterprise can adopt the always-on, token-holding,
auto-materializing agent that makes this possible and *trust it more* than the
manual path it replaces, because the agent is legible, verified, policy-bounded, and
auditable by subtraction. Democratization is the product; trust is what lets it run
unattended. Everything else is in service of those two.

**As a person, this product would be:**
An air-traffic controller. Calm, spare, never theatrical. It watches every flight,
keeps them coordinated and on schedule, clears them to proceed, and raises the
alarm when something is off. It says exactly what is true and no more. It never
flies the plane, never guesses, never pretends the weather is clear when it can't
see the sky. When it has nothing to say, it says nothing — and that silence is the
signal that everything is fine.

**Would NOT be:**
A co-pilot with opinions. A dashboard that decorates. A chatty assistant that
reasons about your machine, scores its own health, and reassures you it's probably
fine. A "smart" second brain that, the moment it disagrees with the tower it's
supposed to render, becomes a second and untrustworthy pilot.

| It IS | It IS NOT |
|-------|-----------|
| A **face + supervisor** that parses `copilot doctor --json` and renders it | A **second brain** that computes health, resolution, signatures, or wipes of its own |
| A single signed binary — tray + supervisor + scheduler in one process | A separate headless **daemon** or an in-app fallback loop |
| An icon that **fails closed** — never shows Healthy it can't prove | A status light that **guesses** or scores machine health offline to "still be useful" |
| An agent that runs the *same* pipeline with **zero bypass flags** | An "unstick it" mode with `--force` / `--skip-verify`, or a "make it Healthy anyway" override |
| A router that **auto-suspends** a security-shadowing override and tells IT | A notifier that pings Bob and hopes he lets Bob **self-unblock** a held update |
| A crash-only watchdog (`KeepAlive={SuccessfulExit:false}`) | A resurrect-always watchdog (`KeepAlive=true`) that crash-loops a bad build |
| A tower that **surfaces** state living in GitHub / MDM / HR | A system of record that owns org structure, or an **AI chat surface** |
| A carrier that **propagates authorized change quietly on cadence** across foundation→org→dept→personal, without clobbering personal work | A **real-time / constant-refresh syncer** — per-minute refresh is explicitly wrong; cadence with a manual "sync now" escape hatch is correct |
| A bridge that makes the ecosystem consumable **by the non-technical** — writable org/dept tiers authored by trained early-adopters (Obsidian → push → cadence sync) | A tool **only for the technical**, or one that makes consuming the ecosystem require technical skill |
| A wall that makes personal↔shared crossing **impossible by accident** — personal content is structurally un-pushable to a shared tier | A path that lets **private personal information reach a shared/public tier** by accident (*The Leak* — never permitted) |
| A resolver that handles a collaborative conflict **invisibly, or holds safely and escalates to a competent author** | A surface that dumps a **raw Git/VCS error** on Bob and expects Git literacy (*The Git Error To A Non-Technical Person*) |
| Pure OSS, free forever — openness *is* the security guarantee | A product with a paid tier, enterprise SKU, or closed component |

**Key boundary — read this twice:**
The line everyone will push on is **"can't the app just compute this one thing?"** —
a health guess when offline, a blended status, a quick resolution, a convenience
override read from the user domain. The answer is no, categorically. If a decision
requires computing ecosystem state, it belongs in the CLI, not here. The single
condition under which a borderline capability is allowed: **it renders or automates
something the CLI already computed and verified, and adds zero judgment of its own.**
If Control Tower vanished, the CLI would still be correct. The moment that stops
being true, the product has failed.

---

## 3. Design Principles

*Three named principles. Each must reject a real feature, not voice a shared value.*

### Principle 1: Parse, never compute
**Meaning:** Control Tower calls CLI verbs and renders the result. It holds **no**
resolution, sync, signature, or wipe logic of its own. All intelligence stays in
the hardened pipeline; the app adds none. There is exactly one source of truth.
**Rejection:** We reject **offline health scoring** — any code path that lets the
app decide a machine is Healthy (or resolve a conflict, or verify a signature) when
it hasn't parsed that verdict from the CLI. "So it still works offline" is not a
reason; an honest *Waiting-for-network* state is the answer.
**Test:** *Does this require the app to compute ecosystem state?* If yes → it
belongs in the CLI. Stop.

### Principle 2: Route by actor-competence × reversibility, not event-class
**Meaning:** For every event, ask who is the *sole competent actor* and whether the
action is *reversible*. Auto-act on reversible things the user can't judge; escalate
to IT what the user can't action; ask Bob only about non-deferrable decisions on his
own data. Proximity to the menu bar is not competence.
**Rejection:** We reject **notify-and-hope** — routing a decision to whoever is
standing at the menu bar. Letting Bob approve a held-major to clear a badge, or
notifying him on a prune he can't action, are both this failure. A notification Bob
can't act on is a regression, because it burns the credibility of the one alert that
matters.
**Test:** *Who is the sole competent actor, and is the action reversible?* If the
answer isn't "Bob, about his own data" and the action isn't his to make → it does
not become a Bob-facing prompt.

### Principle 3: As little app as possible
**Meaning:** One signed binary. No daemon, no fallback loop, a tiny web UI, no heavy
framework, no bypass flags, security keys honored only from the forced/managed
domain. Trust comes from *less* surface an enterprise review must audit, not more.
Every added capability is weighed against the auditability that is the moat.
**Rejection:** We reject **any surface that grows the audit burden without serving
the essential job** — a chat UI, a settings panel that re-points the update feed,
a second scheduler, `KeepAlive=true`. If you find yourself re-implementing
resolution or sync in Rust, stop; it goes in the CLI.
**Test:** *Does this add surface area an enterprise security review has to audit —
and does the essential job survive without it?* If it adds audit surface and the job
survives without it → cut it.

### When Principles Conflict
*The order is settled (ratified 2026-07-06) so a live argument doesn't have to be.*

**Priority order — definitive:** **Parse-never-compute (honesty — the icon that
cannot lie) > Route-by-competence × reversibility > As-little-app.** Above all three
sits the inviolable, non-tradeable constraint **security-posture-never-weakened**
(invariant #4).

Parse-never-compute is absolute — it is the trust guarantee and never yields to
convenience. When routing-by-competence tempts the app to compute (e.g. "auto-decide
this so we don't have to bother anyone"), parse-never-compute wins: escalate instead
of computing. As-little-app is the tie-breaker and the constant background pressure,
but it never overrides honesty — an *added* honest state (Waiting-for-network,
IT-config-incomplete) is worth the surface, because a false-Healthy is the one outcome
worse than more UI. The design challenge confirmed this order rather than revising it:
every guardrail that shaped the visual concepts (no computed score, no celebratory
green, no color-only status) is honesty winning over convenience and over minimalism.

<!-- Security-posture-never-weakened sits above all three as an inviolable
     constraint (invariant #4), not a tradeable principle — see Founding Decisions. -->

---

## 4. Anti-Patterns

*Named failure modes — the specific ways this product could rot into something worse.*

### The Second Pilot
**Drift:** "It'd be so much more useful if the app could just figure out the machine
is fine when the CLI's slow / offline / not installed yet — a little local health
score, a quick conflict resolution, a signature check inline." Each starts as a
reasonable convenience.
**Why it kills us:** The instant the app computes a verdict, there are two sources of
truth — and the app's is the one that can be wrong. A false-Healthy makes the icon a
liar and the fleet dashboard worthless. This is the single worst outcome in the whole
product.
**Early warning:** "so it works offline," "just a quick score," "the app can tell,"
"resolve it in Rust," "we already have the data, let's just compute it."
**Line in the sand:** Zero resolution/health/signature/wipe logic in the app
codebase — a code-review gate every release. Offline or uninstalled reads as an
*honest state*, never a fabricated Healthy.

### The Alert Machine
**Drift:** "Bob should know what's happening — surface the prunes, the policy denials,
the held-major, the security fix. Let him approve things, let him unblock a stuck
update so he's not waiting on IT." It feels empowering.
**Why it kills us:** Every alert Bob can't act on burns down the credibility of the
one that matters. Handing him decisions he has no basis to make trains blind-approve
or indefinite drift. The security alert that must land gets lost in the noise of the
ten that shouldn't have fired.
**Early warning:** "notify Bob when…," "let the user approve/unblock," "add a badge
so they can clear it," "empower the employee to self-serve," "just show them the log."
**Line in the sand:** Route by who can act. Bob-facing notification count trends
toward zero. He is never asked to judge a held-major, clear a policy denial, or
self-unblock a security-gated update. Only IT gets authority-requiring items.

### The Convenience Backdoor
**Drift:** "A machine is stuck — give us a `--force` / `--skip-verify` to unstick it.
Read `UpdateFeedURL` from the user domain so power users can point at a local mirror.
Set `KeepAlive=true` so the tray never dies." Every one solves a real, annoying
support case.
**Why it kills us:** The entire safety claim is that the always-on agent runs the
*same* pipeline with *zero* bypass flags. A lower-bar mode is a supply-chain RCE
waiting to happen (a preference-write repoints the update feed); `KeepAlive=true`
resurrects a bad build into a crash-loop. One backdoor and the security review that
gates all adoption says no.
**Early warning:** "just this once to unstick it," "a power-user mode," "read it from
the user prefs for convenience," "make it never die," "add an override."
**Line in the sand:** No bypass flag, no lower-bar mode, no "make it Healthy anyway"
ever exists in the codebase. Security-sensitive config honored *only* from the
forced/managed domain. `KeepAlive` is never `true`. Trust roots are compiled-in code,
not config.

### The Copilot of the Copilot
**Drift:** "There's a menu-bar surface right here — add a chat box so Bob can ask
'is my machine okay?' and get a friendly answer. Let it reason about his setup."
The AI-everywhere instinct.
**Why it kills us:** It's a tower, not the pilot. A model-driven surface contradicts
parse-never-compute and single-process by definition, and it invites exactly the
computed judgment the whole product exists to refuse. It also multiplies the audit
surface the moat depends on shrinking.
**Early warning:** "add a chat," "let it reason about," "an AI assistant for the
agent," "conversational health," "ask-me-anything about your Mac."
**Line in the sand:** No AI/conversational surface. The app renders the CLI's
verdict in plain language; it never generates one.

### The Ledger That Learns to Bill
**Drift:** "Fleet observability is genuinely valuable — an enterprise tier, a hosted
dashboard, a premium analytics add-on could fund the work." Reasonable, profit-minded.
**Why it kills us:** Openness *is* the security guarantee. An always-on token-holder
that materializes executable-adjacent content is only trustworthy if it is fully
auditable — a paywalled or closed component directly undermines the product's reason
to exist. Monetization would trade the moat for money.
**Early warning:** "enterprise SKU," "hosted version," "premium tier," "just this one
closed component," "we could charge for the dashboard."
**Line in the sand:** Pure OSS, free forever. No paid tier, no enterprise SKU, no
hosted service, no closed component. Success is adoption + trust + reliability, never
revenue.

### The Leak
**Drift:** "The author had a personal aside in the buffer; the sync carried the whole
file up. It's just easier to push everything to one place and sort tiers later — one
remote, one flow, less plumbing." Convenience of a single path.
**Why it kills us:** Private personal content in an org or public repo is
**irreversible** — a wipe can't un-exfiltrate it. This is the nightmare scenario
Pablo named. A change-averse, detail-oriented Bob who sees the boundary breached
*once* never trusts the tool again. Reversibility does not save you here, so the
class must be *prevented, not detected* — impossible by construction, not by
discipline or a checkbox.
**Early warning:** "one remote for everything," "we'll filter personal on push,"
"just don't put personal stuff in the shared vault," "a warning dialog is enough."
**Line in the sand:** Personal and shared live in **separate trees with separate
remotes**; the push path is tier-scoped and fails closed. A personal-layer artifact
has **no route** into a shared remote. The product must make crossing the boundary
**impossible by accident** — never merely discouraged.

### The Git Error To A Non-Technical Person
**Drift:** "Two people edited the same file and it collided. Just surface the merge
conflict — show the `<<<<<<< HEAD` markers and let them resolve it; it's standard,
every developer does it." Treating a VCS internal as a user-facing event.
**Why it kills us:** Bob (and even the trained author) does not know Git. A financial
file where being wrong loses the company money, plus a raw conflict marker, equals a
person who concludes *the tool broke my work* — the worst failure for the most
detail-oriented persona, and a trust make-or-break lost for good. Collaborative
tiers are the product's own doing; the failure they introduce is the product's to
absorb, not to dump on the user.
**Early warning:** "show the conflict," "let them resolve it," "it's just a merge,"
"they can learn Git," "surface the raw VCS error."
**Line in the sand:** A collaborative conflict resolves **elegantly and invisibly —
no data loss, no Git literacy** — or it **holds the file safely and escalates to a
competent author.** Raw Git/VCS output is **never** shown to Bob. Resolution is
non-technical by construction or it does not surface to a non-technical person at all.

---

## 5. Feature Filter

*The instrument. Sequential gates plus a growing case-law table. A stranger should
reach the same in/out verdict you would, in under a minute.*

Use these gates **in order**. A feature must pass **all** of them.

### Gate 1: Parse-Not-Compute Test
> "Does this require the app to compute ecosystem state — resolve, score, verify,
> prune, or wipe?"

If yes → it belongs in the CLI, not here. **Stop.** (This is the cheapest and
kills the most bad ideas.)

### Gate 2: Essential-Job Test
> "Does this serve the spine — give a non-technical person a technical person's
> superpowers *without technical skill*; provision Bob silently and keep his
> environment Copilot-ready (synced/self-healed on cadence, without clobbering
> personal work); keep him honestly-statused; let IT deploy and see it; keep the
> personal↔shared wall un-crossable; and never let a security fix or a leaver's
> content depend on Bob?"

If it only makes something "useful" but doesn't touch the spine → useful is not
essential. **Deprioritise or drop.** If it makes *consuming* the ecosystem require
technical skill, it doesn't just miss the spine — it contradicts the essence.

### Gate 3: Right-Actor Test
> "Is every prompt this creates routed to the sole competent actor for a reversible-
> or-owned decision — and does it keep Bob's notification count near zero?"

If it asks Bob something he can't judge, or notifies him on something he can't act
on → **redesign the routing or reject.**

### Gate 4: Trust-Surface Test (Anti-Pattern check)
> "Does building this drift toward The Second Pilot, The Alert Machine, The
> Convenience Backdoor, The Copilot of the Copilot, The Ledger That Learns to Bill,
> **The Leak** (personal content crossing into a shared tier by accident), or **The
> Git Error To A Non-Technical Person** (a raw VCS failure dumped on Bob) — or add
> audit surface the essential job survives without?"

If yes → **reject, or redesign until it doesn't.** Two of these are prevent-not-
detect: The Leak must be impossible *by construction*, and a collaborative conflict
must resolve invisibly or hold-and-escalate — never surface Git to a non-technical
person.

### Case Law (In / Out)

*Real verdicts. Seeded now from decisions already derivable; grows forever after.*

| Feature | Verdict | Gate | Reasoning |
|---------|---------|------|-----------|
| Silent managed first-run (zero questions, fail-closed validation) | **IN** | 2 | The Silent First Light — the essential job for Bob; renders CLI/wizard phases, computes nothing. |
| Icon that names the failing host ("Codex needs sign-in; Claude is fine") | **IN** | 1, 2 | The Icon That Cannot Lie — a parse of `doctor --json`, worst-wins; never fabricates Healthy. |
| Auto-suspend a security-shadowing override + escalate to IT | **IN** | 3 | The Fix That Acts Itself — reversible + Bob-can't-judge ⇒ auto-act, never notify-and-hope. |
| Honest *Waiting-for-network* / *IT-config-incomplete* states | **IN** | 1, 4 | Added surface, but honesty > as-little-app; the alternative is a false-Healthy, the worst outcome. |
| Crash-only watchdog with staged-bundle rollback | **IN** | 4 | Owns rollback outside the bundle that may not start; `KeepAlive={SuccessfulExit:false}`. |
| Admin-mode seed + MDM-profile generator + red/green preflight | **IN** | 2 | The enabler of the silent path at fleet scale; generates artifacts, computes no ecosystem verdict. |
| Held-major routes to IT's dashboard as an *actionable* item (US-A09) | **IN** | 3 | Right actor — approval authority is IT's; the same event Bob may only see as a non-actionable sentence. |
| Distinct per-state badge shapes (wrench/key/clock/dot/triangle/bang) legible in grayscale | **IN** | 4 | Shape is the first encoder, color the second; honest status must survive color-blind + monochrome render. |
| Offline health score so the icon "still works" when the CLI can't run | **OUT** | 1 | The Second Pilot — a computed verdict is a second, wrong source of truth. Use an honest holding state. |
| In-app AI chat surface ("ask if your machine is okay") | **OUT** | 1, 4 | The Copilot of the Copilot — violates parse-never-compute + single-process; it's a tower, not the pilot. |
| Let Bob approve a held-major upgrade to clear the badge | **OUT** | 3 | The Alert Machine — approval authority is IT's; proximity to the menu bar is not competence. |
| Let Bob self-unblock a blocked/held update | **OUT** | 3, 4 | Same — hands a non-competent actor a decision that trains blind-approve or defeats a gate. |
| `--force` / `--skip-verify` "unstick it" mode | **OUT** | 4 | The Convenience Backdoor — the whole safety claim is zero bypass flags; no lower-bar mode may exist. |
| `KeepAlive=true` so the tray never dies | **OUT** | 4 | The Convenience Backdoor — resurrects a bad build into a crash-loop; watchdog is crash-only. |
| Read `UpdateFeedURL` / mirror from the user preference domain | **OUT** | 4 | Supply-chain RCE via preference write; security keys honored only from the forced/managed domain. |
| A "make it Healthy anyway" manual override | **OUT** | 1, 4 | Fabricates the exact false-Healthy the fail-closed states exist to prevent. |
| Screen-scraping human CLI output instead of `--json` | **OUT** | 1 | A misread `fail`→`pass` shows green over red — the highest integration risk; parse the contract, not the prose. |
| A computed "fleet health 94/100" score, trophy rings, or sparkline flourish on the Admin dashboard | **OUT** | 1, 4 | The Second Pilot as a *visual* — a number that looks computed-by-us implies the app judges health; it renders CLI facts only. |
| A celebratory Healthy — green fill, checkmark, or "All good! 🎉" toast | **OUT** | 4 | Violates silence-is-success; Healthy is the *absence* of signal, never a reward. The quietest mark, never the brightest. |
| Status conveyed by color alone (no badge shape, no sentence) | **OUT** | 4 | Fails the a11y hard rule and honesty; a blended color blob is a blur, not a fact — shape and sentence must carry state. |
| Time estimates in the setup wizard ("about 2 minutes left") | **OUT** | 1 | An estimate is a computed promise the app can't keep honestly; name the *phase* ("Setting up Claude…"), not a countdown. |
| Paid enterprise tier / hosted dashboard | **OUT** | 4 | The Ledger That Learns to Bill — openness is the security guarantee; monetization trades the moat for money. |
| Non-technical, invisible merge-conflict resolution (no data loss, no Git literacy) — auto-merge non-overlapping edits; plain-language "keep both / choose" for a genuine collision; hold-and-escalate if unsafe | **IN** | 2, 4 | A *requirement*, not a nicety — collaborative tiers are the product's own doing, so the conflict is the product's to absorb. Answers *The Git Error To A Non-Technical Person*. (MODEL-IN-HEAD · resolution mechanism UNSOLVED — held as a hypothesis, see Founding Decisions.) |
| Any path that lets personal-layer content reach a shared/public tier by accident (one remote for all tiers; filter-on-push; a warning dialog as the only guard) | **OUT** | 4 | *The Leak* — the leak is irreversible, so it must be impossible by construction: separate trees + separate remotes, tier-scoped fail-closed push. Discipline is not a control. |
| Real-time / per-minute refresh of inherited content | **OUT** | 2 | Cadence is correct — "I can rarely imagine a moment where someone updates something that someone needs *right now*." A manual "sync now" escape hatch covers the rare urgent case; constant refresh burns battery/attention for no essential gain. |
| Surfacing a raw Git/VCS conflict or error to Bob (`<<<<<<< HEAD` markers, "resolve the merge") | **OUT** | 4 | *The Git Error To A Non-Technical Person* — Bob has no Git literacy; a raw VCS failure reads as "the tool broke my work." Resolve invisibly or hold-and-escalate; never dump Git on a non-technical person. |
| Any design that makes *consuming* the ecosystem require technical skill (a terminal step, a config edit, YAML the consumer must touch) | **OUT** | 2 | Violates the essence — democratization means a non-technical person wields it without understanding the layers underneath. If consuming needs technical skill, the product has failed its reason to exist. |
| OS keychain + per-integration OAuth/device-flow as the secrets carrier; inheritance content references a secret's **name + acquisition method**, never its value | **IN** | 1, 4 | The ratified answer to the credentials-carrier problem (`docs/05-security/credentials-and-boundary.md`). Secret material lives per-user in the OS keychain via the CLI's own auth flow; the app renders the browser/code wrapper and holds nothing. References-not-secrets keeps *The Leak* impossible on the inheritance path. |
| Pull-only / downward sync — `copilot update` has read-only, downward credentials and **no push capability** to any shared remote; personal content structurally cannot flow up | **IN** | 2, 4 | Ratified write-direction rule (`docs/01-architecture/inheritance-and-publish.md`, `docs/05-security/credentials-and-boundary.md`). The unattended scheduler has no upward credential, so the worst leakage path (silent bidirectional sync) is closed by construction, not by discipline. |
| **Keep-both** as the always-available floor on a genuine merge overlap (both versions land side-by-side, no data loss, no Git literacy) | **IN** | 2, 4 | The no-data-loss floor of the ratified layered `copilot publish` (auto-merge → keep-yours/theirs/both → park-and-escalate). CLI computes and applies; the app only renders the plain-language choice. Answers *The Git Error To A Non-Technical Person* without ever showing Git. |
| Secrets (API keys, integration tokens) committed to **any tier's git repo**, public or private — even a private dept/org repo | **OUT** | 4 | The ratified credentials rule (DREAD ≈ 9.2/10): git is a distribution/history mechanism, not a trust boundary; a committed secret is irreversibly exposed the moment it lands. No git host is a secrets carrier at any tier. Elevated to a `CLAUDE.md` invariant. |
| Background / automated sync that can push **personal content upward** to a shared tier (a defect or design flaw making the cadence sync bidirectional) | **OUT** | 4 | *The Leak*, its worst form — DREAD ≈ 9.4/10 because it needs **zero human error**, only a code defect, and fires on every machine every cadence tick. Closed by construction: no personal-holding path has an upward push credential. Elevated to a `CLAUDE.md` invariant. |

---

## 6. Quality Bar

**The standard:**
Done means an enterprise security team can audit the always-on agent and accept it as
*safer than a human running `copilot update` by hand* — and a non-technical person
never once had to be technical. "Working" is a running tray; "done" is a *trustworthy*
one.

**Non-negotiables** (every release must pass; each is checkable yes/no):

- [ ] Zero resolution/health/signature/wipe logic in the app codebase (code-review gate).
- [ ] Exactly one signed binary; no headless daemon; no in-app fallback loop; `KeepAlive` never `true`.
- [ ] No `--skip-verify` / `--force` path exists; security keys read only from the forced/managed domain (CI entitlement + preference lint).
- [ ] The icon has no code path to fabricate Healthy; missing security fields in `--json` fail closed to fail, never safe.
- [ ] Every escalation traces to auto-act / escalate-IT / ask-Bob by the competence matrix; Bob-facing notification count trends toward zero.
- [ ] Silent managed first-run reaches Healthy or an *honest* holding state — never a false-Healthy.
- [ ] Never touches a dirty personal working tree (never-destroy).
- [ ] A personal item name is un-emittable by construction in telemetry.

**Taste test:**
If the tray has to explain itself, it failed. A glance should answer "is it OK, and
do I have to do anything?" in half a second, in one plain sentence that names the
failing host — with no jargon, no blended verdict, no reassurance it can't back up.
When everything is fine, it is silent. Silence you can trust is the whole aesthetic.

**Quality failure modes:**

| Failure | Symptom |
|---------|---------|
| False-Healthy | The icon shows fine over a foundation-only, mis-provisioned, or drifted machine. |
| Blended status | "Needs attention" that doesn't say *which* host broke — Bob learns a blur, not a fact. |
| Alert fatigue | Bob gets notifications he can't understand or action, and starts ignoring the app. |
| Silent computation | Any health/resolution/signature logic creeps into Rust — a design-level failure regardless of metrics. |

---

## 7. Voice & Tone

**Character:**
The air-traffic controller from Section 2. Spare, factual, unhurried. It states what
is true and the one thing to do about it, then stops. It never hypes, never
reassures beyond what it can prove, never uses "AI" as a flourish. It speaks in the
language of supervision — *watch, clear, hold, raise the alarm* — never in the
language of a second brain that *decides* or *knows*.

**Language rules:**

| We Say | We Don't Say |
|--------|--------------|
| "Control Tower parses the CLI's verdict and renders it" | "Control Tower determined your machine is healthy" |
| "Codex needs sign-in; Claude is fine" | "Something needs your attention" |
| "Waiting for network" / "IT setup incomplete" | "Healthy" (when it can't prove it) |
| "An update is waiting on IT" | "Review and approve this update — or wait for IT" |
| "Kept your working version" | "Update failed — please contact support" |
| "Watch the fleet," "cleared to proceed," "raise the alarm" | "AI decides," "auto-resolve," "second brain" |
| "Safer than running `copilot update` by hand" | "Trust us, it's automatic" |

**Tone shifts:**

| Context | Tone |
|---------|------|
| Everything fine | Silent. The best message is no message. |
| Honest holding state (offline / IT-incomplete) | Calm and specific — names the state and who owns fixing it, no alarm. |
| Bob-actionable (his sign-in, his dirty WIP) | Direct, singular, respectful of his ownership — the one thing only he can do. |
| Security event (auto-acted) | Quiet and past-tense to Bob ("kept you safe"); content-free and immediate to IT. |
| Bad-update rollback | Reassuring understatement — "kept your working version," never a scary failure. |

---

## 8. Success Signals

**Positive signals (we're on track):**

- "I double-clicked once and had a working partner scoped to my team. I never opened a terminal."
- "It just sits there, quietly solid — it works, and it stays working on its own."
- "It only ever asks me about my own stuff."
- "I stood up the whole fleet from Admin mode and the docs alone — I never hand-edited YAML."
- "I can tell a healthy Mac from a stuck one at a glance."
- "Our security team audited it and accepted it as safer than manual `copilot update`."

**Drift signals (we're losing the soul):**

| Signal | What it means |
|--------|---------------|
| A false-Healthy appears in the field | The app is computing, or a status path can fabricate green — parse-never-compute is breaking. |
| Bob's notification volume is climbing | The Alert Machine is winning; routing-by-competence is eroding. |
| A support answer is "just force it / toggle the override" | A convenience backdoor exists or is being asked for — the safety claim is cracking. |
| Someone proposes an "offline mode" that shows status | The Second Pilot is knocking — an honest holding state is being replaced by a guess. |
| A roadmap line mentions a tier, hosted service, or chat box | The Ledger or the Copilot-of-the-Copilot is drifting in. |

**Recovery questions:**

1. If Control Tower vanished right now, would the CLI still be correct — and does this feature keep that true?
2. Who is the sole competent actor for this, and is the action reversible? Is that where the prompt goes?
3. Does this add surface an enterprise security review must audit — and does the essential job survive without it?

---

## 9. Founding Decisions

*The settled calls this instrument rests on, all locked by Pablo and dated as founding.
At v1.0 ratification (2026-07-06) the design-challenge tensions converted to definite
calls. The v1.1 owner interview then **re-opened three genuinely foundational problems**
(logged below) — these were un-settled by evidence, not by neglect. At v1.2 (2026-07-07)
the owner **ratified the two designs that resolve them** — `inheritance-and-publish.md`
and `credentials-and-boundary.md` — so those three problems are now marked **RESOLVED**
below, four inheritance-safety rules are added as Founding Decision #10 and elevated to
`CLAUDE.md` invariants, and a **single** foundational seam (author git-push-credential
provisioning) remains open.*

Founding calls, ratified with the owner **2026-07-06**:

1. **Pure OSS, no monetization — free and open forever.** Purpose is trust +
   adoption of the copilot ecosystem, never revenue. No paid tier, no enterprise SKU,
   no hosted service, no closed component. Resolves *The Ledger That Learns to Bill*;
   openness is both the security requirement and the go-to-market.
2. **Bob-first (locked).** The non-technical Operator experience *is* the product;
   Admin/fleet mode is its **enabler** — first-class and P0 where (and only where) it
   makes a working Bob possible, else P1 — never a co-equal audience. This resolves the
   former Admin-vs-Bob-primacy tension: Admin standup (A1) is the enabler of Bob's
   Silent First Light (B1), not co-primary. The first release leads with, and is judged
   by, the Operator experience; the fleet dashboard exists because a silently-working
   Bob at scale requires it. When the two faces pull apart, Bob wins.
3. **Success is trust + adoption + reliability**, with provisional targets, not
   revenue. The headline metric (live fleets/machines) is unbounded; false-Healthy and
   security-shadow-miss are hard-zero invariants, not tuning targets.
4. **Product name & identity (settled at ratification).** The product name is
   **"Copilot Control Tower"** (short *Control Tower*) and it **is shown to the end
   user** — in the dropdown/popover header, the setup wizard, and About. It is **not**
   name-light: Bob sees the product's name. The menu-bar tray **mark** is the
   **aviator-sunglasses glyph** (`#2D294E`, a system-tinted template image). **"Aviator"
   is a dead engineering-only codename** and must **never** appear as a product name on
   any user-facing surface. The mark and the retired codename are decoupled: the
   silhouette survives as the glyph, the word "Aviator" does not survive as a name. This
   resolves the naming open decision carried by the design brief §8.3 and the UI doc.

Spine-level, inherited from the five invariants and confirmed at ratification:

5. **Parse-never-compute is inviolable** and outranks every other principle. Offline
   or uninstalled reads as an honest state, never a fabricated verdict. Resolves *The
   Second Pilot*.
6. **Security posture is inherited and never weakened** — a constraint above the
   principles, not tradeable. No bypass flags, no lower-bar mode, security keys only
   from the forced/managed domain, `KeepAlive` never `true`. Resolves *The Convenience
   Backdoor*.
7. **Priority order is settled (confirmed 2026-07-06):** Parse-never-compute (honesty)
   > Route-by-competence × reversibility > As-little-app — with
   security-never-weakened as an inviolable constraint above all three. The design
   challenge confirmed rather than revised this order; see Section 3, *When Principles
   Conflict*.
8. **The anti-patterns are named and kept:** The Second Pilot, The Alert Machine, The
   Convenience Backdoor, The Copilot of the Copilot, The Ledger That Learns to Bill,
   and (added v1.1) **The Leak** and **The Git Error To A Non-Technical Person.**

Added at v1.1 (2026-07-06 owner interview):

9. **Evidence-honesty on the unvalidated tiers.** As of 2026-07-06, the **Admin / IT-
   operator experience** (MDM standup, fleet dashboard, deprovision) and the **multi-
   writer authoring flow** (Obsidian → push → cadence sync across a department) are
   **HYPOTHESES, not validated with real operators/writers** — no real IT admin has
   touched Admin mode; the authoring loop has never run with more than one writer.
   The Soul holds these as **assumptions to be tested**, not settled ground: design
   for them, but do not over-commit or treat their shape as proven. Bob-first (#2)
   still governs — the change-averse consumer is the product; the author tier and
   Admin mode are its subordinate enablers.

Added at v1.2 (2026-07-07 owner ratification of the two foundational designs):

10. **The four inheritance-safety rules (ratified — being elevated to `CLAUDE.md`
    invariants).** Ratified with the owner **2026-07-07** alongside
    `docs/01-architecture/inheritance-and-publish.md` and
    `docs/05-security/credentials-and-boundary.md`. These are the concrete, enforceable
    mechanism for the prose already in the *The Leak* and *The Git Error To A
    Non-Technical Person* anti-patterns (Section 4) — they make those lines-in-the-sand
    true **by construction**, not by discipline. They are being promoted from Soul
    decisions into `CLAUDE.md` invariants so every workstream inherits them:
    1. **Secrets never enter inheritance content or any git repo.** API keys, tokens,
       and integration credentials MUST NEVER be committed to, stored in, or transmitted
       via any tier's git repository, public or private. Inheritance content may
       reference a secret's *name and acquisition method*; never its value. No git host
       is a secrets carrier at any tier. *(Carrier is the OS keychain + per-integration
       OAuth — Case Law IN; reinforces **The Leak**.)*
    2. **No cross-tier write capability from a personal-holding path.** No working tree,
       credential, or automated code path that holds personal-tier content is ever
       configured with write access to a department/org/foundation remote. Reaching a
       broader tier is always a separate, explicitly-credentialed, human-invoked action.
       *(Reinforces **The Leak** — separate trees, separate remotes, tier-scoped.)*
    3. **Sync is pull-only / downward — personal never flows up automatically.** The
       cadence-sync/materialize path (`copilot update`) holds read-only downward
       credentials only and has **no** push capability to any shared remote. All upward
       movement is a distinct, explicitly-invoked action (an author's own push, or
       `copilot promote`), never the background scheduler. *(Closes the worst leakage
       path — silent bidirectional sync — by construction; reinforces **The Leak**.)*
    4. **Fail-closed leak-scan on every writable push.** Every writable-tier push and the
       promotion pipeline is fail-closed gated by a leak-scan (secrets/tokens,
       personal-tier markers, PII) before the remote accepts the change. A tripped scan
       blocks the push with a plain-language, non-technical explanation — **never a raw
       git/VCS error**. *(Defense-in-depth behind rules 2–3; reinforces both **The Leak**
       and **The Git Error To A Non-Technical Person**.)*

**Three RESOLVED foundational problems (v1.2 — 2026-07-07, ratified with the owner):**
The three genuinely-foundational problems the v1.1 interview surfaced are now settled by
evidence and ratified design. Recorded here (not merely deleted) so the resolution and
its canonical doc are traceable:

- [x] **RESOLVED — Writable-tier vs. never-destroy / read-only-mirrors tension.** The
  tension was **apparent, not real**: never-destroy governs the *pull/materialize* side;
  collaborative conflict lives entirely on a separate *push/publish* side it never
  covered. The **consumer-read-only / author-writable split** — a disposable read-only
  mirror distinct from the author's tier-scoped authoring checkout (itself already a
  "dirty personal working tree" invariant #3 forbids touching) — keeps invariant #3
  **intact, no wording change required**. Ref `docs/01-architecture/inheritance-and-publish.md`.
- [x] **RESOLVED — Non-technical merge conflict.** A **layered `copilot publish`**:
  auto-merge non-overlapping edits → plain-language keep-yours / keep-theirs / **keep-both**
  chooser on a true overlap → park-and-escalate to a competent author for sensitive or
  declined cases. **Keep-both is the no-data-loss floor; escalate is the never-cornered
  exit.** Merge logic is CLI-side; the app renders the choice only (invariant #1 intact).
  Raw Git is never shown to Bob. Ref `docs/01-architecture/inheritance-and-publish.md`.
- [x] **RESOLVED — Credentials-carrier.** Secrets ride the **OS keychain** (per-user)
  established via **per-integration OAuth/device-flow** — requiring no cloud secret store;
  inheritance content carries **references, not secrets**; **never git**. A narrow
  MDM-provisioned machine-credential covers unattended kiosk machines. Ref
  `docs/05-security/credentials-and-boundary.md`. *(One provisioning seam remains open —
  see below.)*

**One OPEN foundational problem remaining (v1.2):**

- [ ] **TODO — Author git-push-credential provisioning.** The credentials design settles
  *where secrets live* and *how consumers pull*, but the **author's write credential** —
  what safely delivers a tier-write/push credential to a trained author's machine in a
  pull-based model with no cloud secret store — is specified **in principle, not fully
  worked**. This gates opening write access to a **second** author and must land before
  the multi-writer authoring loop ships. Route to security / architecture. *(The single
  remaining foundational seam; everything else the writable tiers need is ratified.)*

*Engineering-roadmap open items (not Soul-blocking, tracked in architecture/user-story
TODOs): **personal-layer content scope** (what beyond writing-voice belongs in the
personal layer — bounds where the leak wall stands, now that the wall's mechanism is
ratified), urgent-revocation propagation (freshness floor vs. publish webhook), sync
cadence values, signing custody (who holds the second key), kiosk/multi-user a11y depth,
and Codex/host parity.*

---

## 10. Evolution

This file changes only when:
- Real user outcomes shift what the product is for
- We learn something durable that contradicts a current principle or boundary
- The product's place in its ecosystem changes (another product takes over a job)

When updated, add the rationale to the changelog below.

### Changelog

| Date | Version | Change & rationale |
|------|---------|--------------------|
| 2026-07-07 | **v1.2 RATIFIED** | Ratified with the owner (Pablo) alongside the two foundational designs, now canonical at `docs/01-architecture/inheritance-and-publish.md` and `docs/05-security/credentials-and-boundary.md`. **Three of the open foundational problems are RESOLVED** (§9, recorded with resolution + canonical ref, not deleted): (1) **writable-tier vs. never-destroy** — the consumer-read-only / author-writable split keeps invariant #3 intact with no wording change; (2) **non-technical merge conflict** — layered `copilot publish` (auto-merge → keep-yours/theirs/**both** → park-and-escalate), keep-both = no-data-loss floor, merge logic CLI-side; (3) **credentials-carrier** — OS keychain + per-integration OAuth, references-not-secrets in inheritance content, never git. Added **Founding Decision #10 — the four inheritance-safety rules** (secrets never in inheritance content/git; no cross-tier write from a personal-holding path; sync pull-only/downward; fail-closed leak-scan on every writable push), cross-referencing and hardening *The Leak* and *The Git Error To A Non-Technical Person* — **being elevated to `CLAUDE.md` invariants**. Extended Case Law with **5 new verdicts** (3 IN / 2 OUT): OS-keychain+OAuth carrier → IN, pull-only downward sync → IN, keep-both floor → IN; secrets in any git repo → OUT, background sync pushing personal content upward → OUT. New totals **12 IN / 20 OUT (32)**. §9 now shows **3 RESOLVED + 1 remaining** open foundational item — the **author git-push-credential provisioning** seam (specified in principle, not fully worked) — with **personal-layer content scope** demoted to the engineering-roadmap TODOs. |
| 2026-07-06 | **v1.1 RATIFIED** | Revised after a primary-evidence owner interview (`scratchpad/interview-ground-truth.md`). **Essence reframed to democratization** — "give a non-technical person the AI superpowers of a deeply technical one, safely enough to run unattended"; *parse-never-compute / the icon that cannot lie* is reframed from the point to *how it earns the right to run unattended*, and "keeps your environment Copilot-ready" is woven in (Sections 1, 2). Added the **writable inheritance model** (foundation→org→dept→personal, cadence-not-realtime, without clobbering personal work) and the **trained early-adopter author** as a second consumer psychographic to IS/IS-NOT and Who-this-serves. Added two anti-patterns — **The Leak** (personal content crossing into a shared tier by accident — impossible-by-construction) and **The Git Error To A Non-Technical Person** (a raw VCS conflict must resolve invisibly or hold-and-escalate, never dump Git on Bob). Extended Case Law with **5 new verdicts** (1 IN / 4 OUT): invisible non-technical merge-conflict resolution → IN; accidental personal→shared path, real-time refresh, raw Git errors to Bob, and any technical-skill-to-consume path → OUT. New totals **9 IN / 18 OUT (27)**. Added **evidence-honesty** (Founding Decision #9): Admin/IT-operator and multi-writer authoring are HYPOTHESES held as assumptions, not proven ground. **Logged three open foundational problems** as prominent TODOs: the credentials-carrier, personal-layer content scope, and the writable-tier vs. never-destroy/read-only-mirrors architectural tension. Kept the ratified priority order and the pure-OSS / Bob-first founding decisions. |
| 2026-07-06 | **v1.0 RATIFIED** | Ratified with the owner after the design challenge (Phases 1–5 complete, brief approved). Populated the Feature Filter Case Law with 22 real Phase 3–5 verdicts (8 IN / 14 OUT), including the visual Case Law from experience design (no computed fleet-health score, no celebratory green, no color-only status, no wizard time estimates). Confirmed the definitive principle priority order (parse-never-compute/honesty > route-by-competence > as-little-app, under the inviolable security constraint) and removed its TODO. Locked **Bob-first** and resolved the Admin-vs-Bob-primacy TODO (Admin is the enabler, not co-primary). Added the founding **name & identity** decision — the product is "Copilot Control Tower," shown to the end user; the tray mark is the aviator-sunglasses glyph; "Aviator" is a dead codename banned from every user surface. Left urgent-revocation, signing custody, kiosk a11y, and Codex parity as engineering-roadmap open items. |
| 2026-07-06 | v0.1 | Drafted as root-level decision instrument through an essentialism (Rams/Ive) lens: trust earned by subtraction. Synthesized from the vision, scope & non-goals, success metrics, JTBD, and moments-that-matter; spine from the five invariants in `CLAUDE.md`. Records the three founding decisions (pure OSS, Bob-first, trust/adoption/reliability). Supersedes the stub at `docs/00-overview/soul.md`. |
