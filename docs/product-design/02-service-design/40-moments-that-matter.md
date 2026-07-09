> **Superseded framing.** This document predates the Copilot Solutioning Ecosystem (CSE) realignment. Its MDM/fleet framing and its use of "product" to mean a CSE tool are superseded. The corrected model is in `docs/reference/copilot-solutioning-ecosystem.md`; the decisions are in `docs/reference/cse-alignment-decisions.md`.

# Moments That Matter

> **Provenance.** Grounded synthesis from `20-journey-maps.md`, `30-jtbd.md`, the **primary-evidence
> owner interview** (2026-07-06, `01-research/10-interviews/01-interview-self.md`;
> `scratchpad/interview-ground-truth.md`), and the red-team failure scenarios (`redteam-use-cases.md`
> [A], `redteam-platform.md` [B]) — the moments below are the inflection points where trust is won or
> lost. B-/A+ states are traced to the architecture's fixes. Prerequisites: journey maps + JTBD complete.
>
> **The reframe (primary evidence, 2026-07-06).** The soul is **democratization: give a non-technical
> person the AI superpowers of a deeply technical one, safely enough to run unattended.** Observability
> and self-heal are the *mechanism that earns the right* to run in the background — not the point. Two of
> the moments below (MTM-6 Leakage Wall, MTM-7 Merge-Conflict) were surfaced by the interview and did not
> exist in the earlier draft; both are ranked **high** because they are where a change-averse, detail-
> oriented consumer's trust breaks irreversibly.
>
> **Two consumer psychographics.** Most Bob moments are about feeling **SAFE**; the author-tier moment
> (MTM-7) is about a trained early-adopter keeping **POWER** without becoming a Git user. The leakage
> wall (MTM-6) polices *both*.
>
> **Evidence legend.** Each moment carries an honest stamp: **GROUNDED** (Bob's psychology — real people)
> · **OBSERVED** (Pablo's lived pain) · **MODEL-IN-HEAD** (multi-writer authoring — never run with >1
> writer) · **HYPOTHESIS** (Admin/IT — no real operator) · **UNSOLVED** (open design problem).

## Critical Moments

---

### MTM-1: The Silent First Light

> Day one. Bob unboxes a managed Mac (or double-clicks one icon). He has no terminal, no idea what a
> "department" or a "layer" is, and a learned expectation that IT software means a support ticket. The
> next ninety seconds decide whether the whole ecosystem is adoptable by someone like him.

- **Success:** A progress bar runs; nothing is asked he can't answer; he ends with a working,
  team-scoped Copilot partner and a one-line cheat sheet. He never saw a terminal.
- **Failure:** The wizard hangs on a bar, or silently completes wired to an empty/wrong department and
  marks the icon **Healthy** — Bob has no idea, IT has no idea (A-C1).
- **Design implication:** Silent provision must **fail closed**, never guess. A missing managed key →
  a distinct, visible *IT-config-incomplete* state + an IT escalation, never a false-Healthy.

#### Current State (B-)
Onboarding is a shell script + a department prompt + reading `copilot update` output Bob can't judge
(`ecosystem-use-cases.md` UC1). For a non-technical employee there is simply *no path* — he's stuck at
the first command. A "good enough" GUI would ask him the same three things a script does and call it
progress.

#### A+ State
IT pushed the app + a complete `.mobileconfig`; the wizard runs **silently**, schema-validating the
managed profile before entering silent mode, installing the login-item + crash-watchdog at the *first*
phase (so even a mid-setup quit resumes headlessly), and — if offline — finishing foundation-only into
an honest *Waiting-for-network* hold rather than a false-Healthy. Bob watches a bar and is done. This
is the Magic Moment (`00-vision.md`).

**What enabled this:**

| Capability | Role |
|------------|------|
| Silent managed path (`DisableWizard=true`) | Removes every question for the persona who can't answer them |
| Fail-closed schema validation of the managed profile | Turns a missing key into a visible IT problem, not a silent mis-provision |
| Watchdog + checkpoint installed at first phase (A-H6) | An interrupted setup finishes itself |
| *Waiting-for-network* state (A-H7) | Offline first-run is honest, not falsely-Healthy |

---

### MTM-2: The Icon That Cannot Lie

> Any Tuesday, mid-afternoon. Bob glances at the menu bar between tasks. He isn't debugging — he's
> deciding, in half a second, whether to trust that his partner is current and fine, or whether he
> needs to do something. Every glance for months is this moment.

- **Success:** The icon is an honest projection of `doctor --json`; when something's wrong it says so
  in plain language and **names the failing host** ("Codex needs sign-in; Claude is fine").
- **Failure:** The icon shows **Healthy** over a foundation-only, mis-provisioned, or drifted machine.
  Now the icon is a liar and the fleet dashboard is worthless (`20-success-metrics.md`; A-C1/H7/H12).
- **Design implication:** Status is **computed by the CLI, parsed by the app** (invariant #1). The app
  must have *no* path to fabricate Healthy — missing security fields fail closed to fail, never safe.

#### Current State (B-)
`copilot doctor` output in a terminal Bob can't open, or a blended "needs attention" that doesn't say
*which* host broke (A-M14). A mediocre version blends the two-host verdict and loses the attribution
Bob needs.

#### A+ State
A single glanceable icon (worst-wins across hosts) whose dropdown top line is always a plain-language
sentence naming the failing host. *IT-config-incomplete* wears a wrench badge; *Waiting-for-network* a
clock; *Signed-out* a key — each an honest, distinct state, never a generic red or a false green.

**What enabled this:**

| Capability | Role |
|------------|------|
| Parse-never-compute (`status` computed CLI-side) | The app can't invent a verdict it might get wrong |
| Bidirectional `--json` schema gate; missing security fields fail closed (B-H6) | Schema drift or an absent field can never read as "safe/green" |
| Per-host transactional status + host-naming sentence (A-M14) | Bob learns *which* host, not a blur |

---

### MTM-3: The Fix That Acts Itself

> A security fix ships upstream for an agent Bob personally overrode months ago and forgot. His
> override still points at the vulnerable version. Bob has Focus on, never granted notification
> permission, and hasn't opened the dropdown in weeks. This is the exact case the design calls
> Critical — and the one it must not delegate to him.

- **Success:** The vulnerable override is **auto-suspended** (reversibly) so the fixed version wins
  immediately; IT is escalated in parallel; Bob can re-affirm later if he still wants his override.
- **Failure:** The fix *materializes* but Bob's override still wins; the only signal is a notification
  he never sees. The exposure persists silently and indefinitely — "notifies but does not act" (A-C3).
- **Design implication:** `severity_trailer: security` + `override-stale` is **auto-act + escalate**,
  never notify-and-hope. A Bob-facing notification may never be the *sole* control on a live exposure.

#### Current State (B-)
A `security:` trailer + an "un-dismissable" red banner inside a dropdown Bob never opens. The design
*had* this gap — it notified the least-reliable actor and left the vulnerable version winning.

#### A+ State
The override is suspended the moment the fix is seen; the fixed version is live before Bob knows
anything happened; IT gets a content-free safety signal on the mandatory `AdminContact` channel. The
exposure window is closed by an action, not a hope. Because suspension is reversible, Bob's ownership
of his own override is preserved — he re-affirms if he means it.

**What enabled this:**

| Capability | Role |
|------------|------|
| Actor-competence × reversibility router (invariant #5) | Reversible + Bob-can't-judge ⇒ auto-act, not notify |
| Auto-suspend + parallel IT escalation (A-C3) | The fix wins immediately *and* a competent actor is told |
| Split safety-channel, on-by-default for managed (A-C5) | "IT notified" is never a no-op |

---

### MTM-4: The Decision That Goes to the Right Desk

> A held-major upgrade arrives. Someone has to decide whether the fleet takes it. The menu bar is in
> front of Bob — but the competent actor is IT.

- **Success:** The held-major routes to IT centrally; Bob sees a non-actionable "an update is waiting
  on IT," never a decision he has no basis to make.
- **Failure:** Bob is asked to "review and approve — or wait for IT." He blind-approves to clear the
  badge (breakage) or ignores it forever (indefinite drift, invisible to IT) — A-H11.
- **Design implication:** Approval authority is declared in `ecosystem.yml`; proximity to the menu bar
  is not competence. Route by *who can act*, not by who's standing there.

#### Current State (B-)
The UI presents a major-version decision to whoever's at the menu bar. A mediocre build "empowers" Bob
with a choice that is actually a trap.

#### A+ State
The held-major reaches IT's dashboard as an actionable item; Bob's view is informational and calm; a
Bob-actionable item left un-acted past a deadline (backup-missing, re-auth) *time-boxes* to IT rather
than degrading silently forever (A-H13). Nobody is asked to judge what they can't.

---

### MTM-5: The Watchdog That Catches a Bad Update

> Control Tower self-updates overnight. The new bundle crashes on launch — a panic before the webview
> even mounts. Under a naive design this is a crash-loop that pegs the CPU and leaves Bob with a dead
> menu bar and no terminal to recover.

- **Success:** A tiny stable watchdog (never self-updated) staged the new bundle, launched it with
  `--self-test`, waited for an early liveness heartbeat, saw none, discarded it, kept the working
  version, marked the bad version poisoned, and notified. Bob sees nothing — or a calm "kept your
  working version."
- **Failure:** The rollback logic lives *inside* the bundle that won't start, so it can't run; under
  `KeepAlive=true` the machine crash-loops until IT force-pushes a good pkg (B-C2/B-C3).
- **Design implication:** The health gate + rollback live in the **stable watchdog**, not the new
  bundle; `KeepAlive={SuccessfulExit:false}` + a circuit breaker; the watchdog verifies the staged
  bundle is stapled offline before promoting.

---

### MTM-6: The Leakage Wall

> `> **Evidence: GROUNDED** (the fear — Anxiety #2, in Pablo's voice) / **UNSOLVED** (structural
> enforcement not yet designed).`

> The moment a piece of **personal** content could cross into a **shared/public** tier. Bob keeps a
> private writing-style note in his personal Knowledge Copilot layer; an author (Ada) edits a
> department file with a personal aside still in the buffer; a sync is about to carry the change
> upward. One push could put private personal information into an org — or public — repo, forever.
> This is the boundary Pablo named as the **nightmare scenario.**

- **Success:** Crossing the personal↔shared boundary is **impossible by accident.** Personal-layer
  content is *structurally* un-pushable to a shared tier; the sync/push surface only ever offers the
  tier the content belongs to; a stray personal artifact is refused and kept local, never silently
  carried up.
- **Failure:** Private personal information lands in the org/public repo. It is **irreversible** — a
  wipe can't un-exfiltrate it — and a change-averse, detail-oriented Bob who sees this happen *once*
  never trusts the boundary, or the tool, again (Anxiety #2).
- **Design implication:** The wall is enforced **by construction**, not by discipline or a checkbox.
  Reversibility does not save you here — leaked personal data can't be undone — so this class must be
  **prevented, not detected.** Personal and shared live in separate trees with separate remotes; the
  push path is tier-scoped and fails closed. (Same principle as telemetry's *un-emittable-by-
  construction* personal name, B-H5.) This is a **new P0 trust guarantee** for *both* consumers.

#### Current State (B-)
Human discipline — *"just don't push personal stuff to the shared repo."* The wall lives entirely in
the user's head; one fat-finger and private personal info is in a public place, irreversibly. Discipline
is not a control.

#### A+ State
Personal and shared content are structurally separated (distinct vaults/trees, distinct remotes). The
authoring surface (a tier-scoped Obsidian vault) and the sync/push path can only ever move an artifact
to the tier it belongs to; a personal-layer file has **no route** into a shared remote. An attempt to
cross fails closed with a plain-language *"this stays on your machine."*

**What enabled this:**

| Capability | Role |
|------------|------|
| Structural personal/shared separation (separate trees + remotes) | A personal artifact has no path to a shared remote — leak-by-accident is impossible |
| Tier-scoped push, fail-closed at the boundary | The push surface offers only the correct tier; a cross-tier attempt is refused, not carried |
| Prevent-not-detect posture (irreversible ⇒ no reliance on undo) | Matches the invariant that reversibility gates automation — here it gates *nothing*, so it must be structurally impossible |

<!-- TODO (open item, route to security/threat-model): PERSONAL-LAYER CONTENT SCOPE — writing styles
     are plural and context-dependent (email voice ≠ documentation voice ≠ thought-leadership voice);
     Knowledge Copilot is the natural home. What ELSE belongs in the personal layer? Its exact scope
     defines where this wall stands (`interview-ground-truth.md` §10). -->

---

### MTM-7: The Merge-Conflict Moment

> `> **Evidence: MODEL-IN-HEAD** (never run with >1 writer) / **UNSOLVED** (Pablo is genuinely unsure
> what is technically possible for invisible, non-technical resolution).`

> Bob the accountant edits a financial file in **department** knowledge. A colleague edits the *same*
> file. The next cadence sync collides. **Neither of them knows Git.** Two detail-oriented, change-
> averse people, one conflict, zero Git literacy — and the file is financial, where being wrong could
> lose the company money. Pablo named this as a real, unsolved design problem.

- **Success:** The conflict resolves **elegantly and invisibly** — *no data loss, no Git literacy
  required.* Ideally the system handles it behind the scenes; at worst it offers a plain-language,
  side-by-side *"your colleague also edited this — keep both, or choose"* — **never** a raw
  `<<<<<<< HEAD` marker.
- **Failure:** A raw Git conflict message a non-technical person cannot act on; edits lost or the file
  stuck. A change-averse Bob concludes *the tool broke his work* — a **trust make-or-break** lost for
  good, and for the detail-oriented persona most likely to notice, the worst possible failure.
- **Design implication:** Writable, collaborative tiers **strain the "never-destroy / read-only
  mirrors" safety assumption** (invariant #3) — this is the hardest open design problem the interview
  surfaced. Trained-few-writers-first shrinks the blast radius but does **not** remove it. Resolution
  must be non-technical *by construction* or escalate to a competent author — **never** to
  Bob-as-a-Git-user. **FLAG:** unsolved; route to the architecture / security work.

#### Current State (B-)
**Nothing non-technical** — a raw `git merge` and its conflict markers, which neither Bob nor Ada can
resolve. The only "fix" today is to fetch Pablo.

#### A+ State *(hypothesized — not yet validated)*
Non-overlapping edits auto-merge with full history retained; a genuine content collision surfaces as a
plain-language *"two people changed this — here's both versions, which stays?"* choice, resolvable by a
trained author, with **every byte preserved** and Git internals never shown. If it cannot be resolved
safely, it holds the file and escalates to a competent author rather than losing or corrupting work.

**What enabled this:**

| Capability | Role |
|------------|------|
| Non-technical, side-by-side resolution UX (no Git markers) | A change-averse consumer can act without becoming a Git user |
| History-preserving / append-first strategy | "No data loss" is structural, not best-effort |
| Trained-writers-first gating + escalate-don't-lose | Shrinks blast radius; a truly ambiguous conflict goes to a competent author, never to Bob |

<!-- TODO (open item, route to security/threat-model): CREDENTIALS — what carries secrets through a
     pull-based inheritance model when a company has no cloud secret store? GitHub, somehow, safely?
     Unsolved (`interview-ground-truth.md` §10). This gates the whole write/publish path that makes
     MTM-7 possible in the first place. -->

---

## MLP Anchors

*The moments the first release MUST nail.*

1. **The Silent First Light (MTM-1)** — a managed Bob reaches a working partner (or an honest holding
   state) with zero questions and zero false-Healthy.
2. **The Icon That Cannot Lie (MTM-2)** — status is parsed from the CLI, names the failing host, and
   has no path to fake Healthy.
3. **The Fix That Acts Itself (MTM-3)** — a security-shadowing override is auto-suspended, never left
   to a notification Bob won't see.
4. **The Leakage Wall (MTM-6)** — the personal↔shared boundary is impossible to cross by accident.
   *Applies even to a consumer-only v1:* Bob has a personal layer the moment any sync runs, so this
   P0 guarantee is not deferrable with the multi-writer tiers.

> **Deferrable, but the top author-tier moment:** **The Merge-Conflict (MTM-7)** is a trust make-or-
> break, but it belongs to the multi-writer authoring path, which is **MODEL-IN-HEAD** and **UNSOLVED**.
> If v1 ships consumer-only (Bob reads a foundation Pablo still hand-authors), MTM-7 is deferred with
> that path — but it must be solved *before* write access is opened to a second author.

---

## Pain Point to Delight Point Transformations

| Pain Point | Current State | A+ State |
|------------|---------------|----------|
| Onboarding needs a terminal | Bob runs a shell script + confirms a department he doesn't understand | One double-click (or zero, managed) → a working partner; ≤3 questions unmanaged |
| The machine drifts silently | Cron `copilot update` swallows prunes + security trailers; nobody sees drift | Always-on self-heal; a *used* pruned tool notifies; drift is visible on the icon and dashboard |
| "Is this Mac healthy?" is unknowable | IT waits for Bob to call; false-Healthy hides brick | Dashboard: healthy / stuck / behind / needs-auth at a glance — the named gap, closed |
| A security fix depends on Bob noticing | Vulnerable override keeps winning behind an unseen notification | The override auto-suspends; the fix wins immediately; IT is told |
| Standing up an org is hand-craft | Hand-written YAML + per-vendor `.mobileconfig` + a typo that ships a 404 | Guided seed + MDM-profile generator + a red/green preflight *before* the fleet breaks |
| A leaver's content persists | Deprovision contingent on a user-deletable app being online | MDM-native + server-side revocation; "no secret ever materialized" |
| An always-on token-holder is un-auditable | "Trust us, it's automatic" → security review says no | Open source + reproducible builds + two-of-N signing + zero bypass flags = *safer than manual* |
| Personal content can leak into a shared/public place | "Just don't push personal stuff" — one fat-finger is an irreversible leak | Structural personal/shared separation + tier-scoped, fail-closed push = crossing the boundary is impossible by accident (MTM-6) |
| Two non-technical colleagues collide on a file | A raw `git merge` conflict neither can resolve; edits lost or stuck | Invisible resolution / plain-language "keep both or choose"; no Git markers; no data loss (MTM-7, *UNSOLVED*) |
| Everyone defaults back to generic chat | Claude app / ChatGPT / Gemini only *answers* — it doesn't build, integrate, or know the company | A solution-oriented partner more present and capable at the moment of need, seeded from the first-run "teach" step (habit-break; journey Stage 3b) |

---

## Moment Ranking

| Rank | Moment | Impact if Failed | Design Priority |
|------|--------|------------------|-----------------|
| 1 | MTM-2 — The Icon That Cannot Lie | False-Healthy makes the icon a liar and the whole dashboard worthless — the single worst outcome | **Highest** — parse-never-compute + fail-closed status |
| 2 | MTM-1 — The Silent First Light | No non-technical adoption path; the ecosystem stays CLI-shaped | **Highest** — silent path + fail-closed validation |
| 3 | MTM-6 — The Leakage Wall | Private personal info in a shared/public repo — irreversible; a change-averse Bob is gone (Anxiety #2) | **Highest** — structural personal/shared separation; prevent-not-detect (*new P0 · UNSOLVED*) |
| 4 | MTM-3 — The Fix That Acts Itself | A shipped security fix silently defeated; exposure persists | **Highest** — auto-suspend + escalate |
| 5 | MTM-7 — The Merge-Conflict Moment | A raw Git conflict a non-technical person can't act on; a colleague's edits lost; trust make-or-break | High — non-technical/invisible resolution; no data loss (*MODEL-IN-HEAD · UNSOLVED*; deferrable with the author path) |
| 6 | MTM-5 — The Watchdog Catches a Bad Update | A bricked menu bar Bob can't recover, or a crash-loop | High — watchdog-owned rollback + heartbeat |
| 7 | MTM-4 — The Decision at the Right Desk | Blind-approve breakage or silent indefinite drift; Bob-fatigue | High — route by competence, central IT approval |

---

**Related:** [Journey Maps](20-journey-maps.md) | [JTBD](30-jtbd.md) | [Service Blueprint](10-service-blueprint.md)
