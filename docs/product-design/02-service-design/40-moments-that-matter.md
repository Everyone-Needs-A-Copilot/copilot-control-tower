# Moments That Matter

<!--
FACILITATION GUIDE — Service Designer
======================================
Moments That Matter are the critical inflection points in the user
experience — the moments where the product either earns trust or
loses it. These are NOT the same as features. They are the emotional
and functional turning points.

For each moment, define both the B- state (mediocre, what the product
might deliver if we're not careful) and the A+ state (excellent, what
it should actually feel like). The gap between B- and A+ is the design
challenge.

PREREQUISITE: Journey maps and JTBD must be completed.

CONVERSATION FLOW:
1. Identify the moments from the journey map that carry the most weight
2. For each moment, define the B- state (mediocre) and A+ state (excellent)
3. Define the design implications (what the product must do here)
4. Capture pain-to-delight transformations
5. Rank by impact on trust and retention

QUESTIONS TO ASK:

## Round 1: Identifying Moments
- "Looking at the journey map, which moments carry the most weight?"
- "Where does the user make a decision about whether to trust this product?"
- "What's the first moment where the product proves its value?"
- "What's the moment where, if it fails, the user never comes back?"
- "Is there a moment where AI-generated content is first shown to the
  user? What needs to be true about that moment?"

## Round 2: B- to A+ Analysis
For each moment identified, define both states:

B- (mediocre):
- "What does this moment look like if we build it adequately?
  What does 'good enough' feel like for the user?"
- "What's the version of this moment that works but doesn't delight?"

A+ (excellent):
- "What does this moment look like if we build it exceptionally?
  What does the user say, feel, or do differently?"
- "What's the version of this moment that earns a word-of-mouth referral?"
- "What would make someone describe this as magic?"

For each A+ state, ask:
- "What capabilities enable this?"

## Round 3: Design Implications
For each moment:
- "What must the product do at this moment to earn trust?"
- "What information must be visible?"
- "What must the AI get right?"
- "What would make the user say 'this actually understands me'?"

## Round 4: Pain-to-Delight Transformations
- "What are the recurring pain points in the current process
  that this product inverts?"
- "For each pain point: What is the current state? What is the A+ state?"
- "Which pain point, if solved, would generate the most word-of-mouth?"

## Round 5: Ranking
- "If we could only nail THREE moments, which three?"
- "What's the cost of getting each moment wrong?"
- "Which moments are minimum lovable product anchors — the ones that
  define the minimum lovable bar?"

SYNTHESIS:
Present as named, numbered moments with:
- A vivid scene description (time, context, who is there)
- Success and failure states
- The B- to A+ narrative (current state → excellent state)
- What capabilities enable the A+ state
- Design implication

Follow with the Pain-to-Delight table and the MLP anchors.
-->

> **Status — rebuilt from evidence 2026-08-02.** Every moment below is drawn from something that actually happened to this product: the ENAC live run that reached sixteen of sixteen layers applied, the schema-mismatch incident that took every Claude Code prompt down, the false "nothing changed" claim in the 0.2.4 apply, the 12,537-line content deletion, and the copy specs those failures produced. It describes **v0.4.0** (build 19, 2026-08-02, embedded helper `cc 2.2.0`). Product status is **DOGFOODING**: live on exactly one organization, not offered outside, not generally available.
>
> **These are not hypothetical failure states.** Where a failure state is written below, it has a citation, because it is a thing the product has already done to a real person. That is what makes this list the right list.

## Critical Moments

---

### MTM-1: The account of what just happened

> The setup transaction has stopped. The person is looking at a screen that is about to tell them what was done to their own accounts and their own disk. Everything the product has ever claimed about itself is settled in this one paragraph of text.

- **Success:** The person is told exactly what was created, what was downloaded, what was reused, what was held, and what is left — and every item on that list is verifiably true. If nothing was done, "nothing was done" is backed by an empty ledger rather than by an intention.
- **Failure:** The screen says nothing changed, and something changed. `Evidence: this happened. Control Tower 0.2.4's first owner-run apply stopped on a repository whose history was not fast-forwardable and reported that setup stopped "before changing anything." Two Personal GitHub repositories had already been created and seeded minutes earlier; the handoff document's own words are "That statement is false for this run."` What the person concludes is not "there is a bug." It is *"this thing tells me what it wants me to hear."* There is no route back from that conclusion.
- **Design implication:** Every deterministic check — including git ancestry — runs **before** the first irreversible write, so a blocked row produces zero mutations rather than a partial set. A run-scoped ledger of completed actions threads through every exit path, including the failing ones. The apply asserts that the result equals the target as a postcondition, and reports "already at target" and "fast-forwarded" as distinct outcomes rather than collapsing them. A *held* item (a passive, protective non-write) may never share fatal treatment with a *blocked* one (an active refusal), and only a genuine failure may undo an already-verified write.

#### Current State (B-)

The installer runs a sequence, catches an error somewhere in the middle, and shows the error. Whatever the sequence had already done to the world before that point is unmentioned, because the code that wrote the message does not know. The person is left to reconcile GitHub by hand — which, for the intended user, means not reconciling it at all. On a second run the tool sees the repositories its own failed attempt created, treats them as pre-existing, and quietly erases the evidence that it made them.

#### A+ State

There is nothing to reconcile, because the transaction refused to begin until it had proven every precondition the apply would enforce. When it does stop, the stop is *bounded*: the screen names what completed, and the ledger behind it is the same object the engineering evidence is written from. In the real live run this held under genuine adversity — the apply blocked twice, for two independent reasons, and on neither occasion did it leave a false claim behind: the manifest file was byte-verified unchanged both times, and the third attempt reported the full ledger including six seeded mirrors, one manifest write, and one materialization pass. When it finally succeeded, the report still carried the honest awkward parts — four items held by a protection guard, one blocked — rather than rounding to success.

**What enabled this:**

| Capability | Role |
|------------|------|
| The preflighted saga (ADR-006) | All deterministic preflight before any irreversible write; a nine-state history classifier where only a merge-base-proven fast-forward may auto-repair |
| The completed-actions ledger | Makes "nothing changed" a checkable claim rather than a hopeful one; required by the contract rather than optional |
| The `HEAD == target` postcondition | Turns "the command exited zero" into "the world is in the state we promised" |
| Held-versus-blocked separation | A protective non-write and an active refusal are different facts and must render as different facts |
| A topology gate driven against the **packaged** binary | The prior gates all passed while source and signed binary disagreed on a user-visible field; a mock cannot catch that |

---

### MTM-2: The day nothing happens

> It is an ordinary Tuesday, months after setup. The person has not thought about Control Tower in weeks. The glyph in their menu bar is quiet, as it has been every day since they installed it.

- **Success:** They do not look at it. The silence is accurate, and it has been accurate long enough that they have stopped verifying it. This is the product working at full strength, and it produces no observable event at all.
- **Failure:** The icon is quiet and something is wrong. This is the **false green**, and it is the single worst outcome in the product. `Evidence: this happened. Through v0.2.3 a GitHub repository or a hidden mirror counted as an installed layer, so a person could see a green Personal result with no visible folder anywhere on their disk — fixed in 0.2.4 under ADR-005.` The person concludes that the icon is decorative, and from that moment onward every future green is worthless, including the true ones.
- **Design implication:** Healthy is the **absence** of signal, never a reward — no green fill, no checkmark, no confetti. Status is re-derived by re-running the real pipeline, never by remembering the last good answer. The vocabulary must include *waiting for network* and *could not check* as first-class states, because an honest unknown is infinitely cheaper than a confident error. Missing security fields fail closed. Shape carries state before colour does, so the claim survives a monochrome or colour-blind render.

#### Current State (B-)

A status light with three colours and an optimistic default. When the check cannot run, it keeps showing the last thing it knew, because showing nothing "looks broken." That single accommodation — made for the best of reasons — converts the product from an instrument into a decoration, and nobody notices the moment it happens.

#### A+ State

The check is re-run on a three-hundred-second cadence and on every launch and popover open, and its result is rendered rather than remembered. When the pipeline cannot answer, the app says so in its own state rather than falling back to the last green. When the response cannot be read at all — an unparseable body, a version outside the accepted range, a missing security field — that becomes an explicit unreadable state, never an optimistic one. Over months, the silence accumulates into something rarer than any feature: a person who has stopped checking.

**What enabled this:**

| Capability | Role |
|------------|------|
| The twelve-token shape-first badge vocabulary | Encodes state in shape before colour, and includes honest non-answers as real tokens |
| The fail-closed schema gate | Decodes only the version before trusting any other field; exact major match per verb; unreadable is a state, not a fallback |
| Re-running the pipeline rather than caching a verdict | The claim is always about now, never about the last time it worked |
| No celebratory success state | Silence is the reward, so there is nothing for a lie to hide behind |

---

### MTM-3: The stop that is not a failure

> Setup has been running. It halts. The screen changes. In the next two seconds the person decides whether this tool is careful or broken — and whichever they decide, they will keep deciding it for the rest of the relationship.

- **Success:** They read *"Something here is already yours"* and feel a small, specific relief: the tool found something of theirs, recognised it as theirs, and left it exactly as it was. The primary action is `Keep what I have`. Nothing on the screen implies a fault, because there is not one.
- **Failure:** The same underlying event renders as orange, as the word *error*, or as a raw machine sentence — and the person concludes the tool broke their work. `Evidence: this exact string reached the screen: "An existing GitHub SSH alias is user-managed; setup did not replace it." It is the live-verified case that produced the H4 variant.` Or worse, the tool actually does overwrite what it found. `Evidence: this happened too. One routine update reconcile-deleted 12,537 lines of organization content in a single commit, which a backup job then pushed to origin.`
- **Design implication:** The Holding screen is **seven named variants**, and the variant is chosen by **who owns the fix** — never by what went wrong. H4 is forbidden from being orange and forbidden from using the words *paused*, *stopped*, *couldn't*, *problem*, or *error*, because it is a success with a question attached. It shows a card headed **What I left alone**, a caption reading **Nothing was changed, moved, or removed**, and a confirmation state that says **Kept as it is**. A CLI-authored string is never a headline: it is framed verbatim under *What setup found:* when it was written for a person, and otherwise goes only into the collapsed support block.

#### Current State (B-)

One screen called "Setup failed," with the underlying error printed into it. It conflates four unrelated situations — a fault, a courtesy, a wait, and somebody else's homework — so a change-averse person has no way to tell which one they are looking at, and the safe assumption is always the worst one. The most common real outcome of a first setup becomes indistinguishable from the rarest catastrophic one.

#### A+ State

Nine of sixteen rows landing on review is not a wall of failures; it is the system being careful nine times, and the screen says so. `Evidence: in the real live run's first read-only plan pass, nine of sixteen rows classified as review — six of the seven already-present repositories, three of them purely because of untracked scratch files.` The person sees a blue screen that names what was left alone, in their own words, and offers them the one decision that is genuinely theirs. When the fix belongs to their organization instead, the screen says **there's nothing for you to do** and its primary action is to leave — because a retry button that cannot change the outcome teaches people that buttons are decorative. Every variant has at least two exits, and one of them works offline and with a broken helper.

**What enabled this:**

| Capability | Role |
|------------|------|
| Routing by actor-competence times reversibility | Chooses the variant by who owns the fix, so the screen is addressed to exactly one actor |
| Never-destroy, enforced structurally | A guard that refuses to write or delete through any symlink escaping the materialize root — the direct fix for the 12,537-line deletion |
| The dirty-tree short-circuit in the classifier | Any non-empty working tree routes to a person without fetching or comparing, because nothing can distinguish an uncommitted edit from a scratch file without a judgment that belongs to a human |
| The frame-or-replace rule | A machine sentence never becomes a headline, and is never concatenated into an app sentence |
| A collapsed **Details for support** block | Raw technical vocabulary is correct in exactly one place, addressed to exactly one reader, and any line the app cannot fill is omitted rather than filled with "unknown" |

---

### MTM-4: The roster reveal

> Four steps into setup, a person who has spent their career using only what IT handed them is looking at a list of everything that is about to become theirs — four copilots, the departments their access already permits, their organization's connected services, and their own projects.

- **Success:** They feel the pull for the first time. Not "this will be useful" — *"I did not know I was allowed to have this."* This is the only moment in the journey that generates desire rather than managing anxiety.
- **Failure:** The screen is a wall of internal vocabulary, or it is empty. `Evidence: before v0.4.0 the connections step had nothing to show at all — an empty state where the organization's declared services should have been. Closed in 0.4.0 by the connections bridge.` An empty roster at the exact moment a person is deciding whether this is worth it reads as *there is nothing here for me*.
- **Design implication:** Entitlement is GitHub repository access and nothing else, and it is rendered as a list rather than negotiated as a favour. No internal vocabulary reaches this surface — the words are `YOUR COPILOTS`, `AVAILABLE TO JOIN`, `SHARED WITH YOUR TEAM`, `Your connections`, `Your projects`. The organization's roster is computed entirely by the CLI and only grouped by the app; an unrecognized future state is grouped as not-available rather than shown as ready, so the roster fails closed in the one direction that matters.

#### Current State (B-)

A configuration screen listing what the administrator has provisioned, in the administrator's vocabulary, with the person's job being to not break it. It communicates obligation rather than possibility, and it is the reason most internal rollouts feel like something being done *to* people.

#### A+ State

The list is about them. It says what they get, in the names of things rather than the names of mechanisms, and it makes clear that nobody had to approve any of it — their access already said so. Departments they can join have a Join button next to them, not a request form. Their organization's services are grouped into *Ready to use* and *Available to connect*, with a plain sentence naming exactly which credentials are missing from the shared store and never a value. Their own projects are triaged into five categories with a plain-language meaning attached to each. The person leaves this beat wanting the next screen to finish.

**What enabled this:**

| Capability | Role |
|------------|------|
| Entitlement as repository access | Removes the approval step entirely — you have it if you can reach it |
| The connections bridge (new in v0.4.0) | Renders the organization's full declared roster with real store state, computed CLI-side end to end; the app never inspects a secret value |
| Fail-closed grouping | An unrecognized connection state is grouped as not-available, never as ready |
| CLI-authored project classification | Five categories with plain-language meanings, so a person is never asked to interpret a project's internals |

---

### MTM-5: The one thing only they can do

> The app needs a permission it does not have. A browser opens. For the only time in the journey, the product is genuinely waiting on this specific human.

- **Success:** The wait names what *they* need to do, not what the app is doing. They finish in the browser, the app picks up, and at no point were they asked to paste a credential anywhere.
- **Failure:** They lose the browser window behind other windows and the wait looks like a hang — or they are asked for a permission far broader than the thing being done, and a careful person correctly refuses.
- **Design implication:** This is the only human-paced wait in the product, and it carries no timer and no count, because the bottleneck is a person. A lost browser window is the common failure, so there is a way back in; an expired code has its own ending rather than a stall. The app's data model has **no field a token could occupy**, by construction. When a broader permission is genuinely needed, it is asked for on its own, later, in its own screen, with explicit terminal states for the two ways it can legitimately fail — the wrong identity, and an insufficient grant.

#### Current State (B-)

A single up-front consent screen requesting every permission the product might ever need, presented at the moment the person knows least about what the product is. A careful person reads it, does not understand why so much is required, and declines — and the product records that as a funnel drop rather than as the correct decision it was.

#### A+ State

The sign-in is the browser flow they have done a hundred times, at the moment it is needed and no earlier. The extra permission — a narrow, specific one — is requested separately, at the point of use, as `Grant this on GitHub` rather than as an authentication failure. If they grant it as the wrong identity, that is a named state with its own copy rather than a generic error. The app never holds the credential at any point, and the design makes that structurally true rather than merely intended.

**What enabled this:**

| Capability | Role |
|------------|------|
| Browser device flow with no token field in the model | Makes "the app never holds your credential" a property of the code rather than a promise in a document |
| Least-privilege, just-in-time permission grant | The broad permission is asked for once, at the point of use, with its own explicit failure states |
| The human-paced wait pattern | Names what the person must do, offers a way back to a lost browser window, and gives expiry its own ending |

---

### MTM-6: The change that arrives without being asked for

> Nobody ran anything. An author, possibly on another continent, made one change to shared content. On this person's machine, on the next sync, it is simply there.

- **Success:** The person notices something new is available — or, more often, does not notice at all and simply benefits. The author never has to ask whether it landed. This is the origin job of the entire product.
- **Failure:** The change does not arrive, and nobody finds out until something breaks. Or it arrives and takes something with it. `Evidence: 12,537 lines, one commit, then pushed by a backup job.`
- **Design implication:** Sync is pull-only and downward **by construction** — the scheduled path holds no upward push credential to any shared remote, so the worst possible leak (a silent bidirectional sync) is closed structurally rather than discouraged by care. Visible working trees are human-owned: a clean one may be reused or fast-forwarded, a dirty one is never touched. And when something has changed, `What changed` shows a plain list grouped by what happened, with a real empty state that says **"Nothing has changed since you last looked."** — because "nothing changed" has to be a claim the app can back here too.

#### Current State (B-)

The author remembers, or does not. A change made once does not land everywhere; the human *is* the sync layer, walking machine by machine and project by project. The owner's own words for this are *"that shit gets exhausting."* It does not scale past one person, and its failure mode is silent by nature — nobody knows about the machine that was missed.

#### A+ State

The author writes once and stops thinking about it. Every entitled machine picks it up on cadence, without anyone running anything, and without disturbing a single thing anyone owns. On the receiving side there is either nothing to see, or a plain list of what actually arrived. `Evidence: DEMONSTRATED at one organization, single-machine. The multi-writer and second-machine cases are what the V-5 cold-laptop proof is for and are not yet demonstrated.`

**What enabled this:**

| Capability | Role |
|------------|------|
| Pull-only, downward-only sync | No upward push credential on any personal-holding path; the leak is impossible rather than discouraged |
| Human-owned visible checkouts | Reuse or fast-forward a clean tree; never touch a dirty one |
| Cadence rather than real-time | A deliberate design parameter, with a manual `Sync now` for the rare urgent case |
| An honest empty state in `What changed` | "Nothing changed" is a claim, and it is backed here too |

---

### MTM-7: The organization's first standup, and the check before handover

> An operator is about to create a set of repositories, teams, and access grants that other people will depend on and that they will be asked about later. Then, before telling anyone it is ready, they run a read-only check.

- **Success:** Before anything is created they can see exactly what will be reused, created, downloaded, initialized, connected, synchronized, and verified — by name and by destination. Afterwards, the read-only check tells them what is genuinely on GitHub, and they find their own blockers before their colleagues do.
- **Failure:** A half-created organization that hides its own history. The operator cannot say what exists, cannot safely re-run, and has to audit GitHub by hand — which for most operators means declaring it done and finding out later.
- **Design implication:** Every existence and idempotency decision is made by a deterministic engine using check-then-act — GET before every POST, PATCH, or PUT — never by a model and never by the UI. The run is a named list of real things filling in place, with a count only while it is alive, a bar only above seven rows and only as the visual twin of that count, and **no percentage anywhere**. If it goes silent, it says **No answer yet**, stops animating entirely, and offers `Keep waiting` and `See what's really on GitHub` — because the truth path is a read-only check, never a guess. `Evidence: RUN ONCE, BY THE AUTHOR — no third-party operator has ever touched Admin mode, so every claim in this moment is a demonstrated capability and an untested behavioural bet at the same time.`

#### Current State (B-)

A runbook and a terminal. It works, and only the person who ran it knows what state the organization is in. It cannot be resumed safely after an interruption, because nothing recorded what had already been done, and re-running it risks creating things twice.

#### A+ State

The operator reads a plan they can defend, authorizes it, and watches sixteen named rows fill in — the same rows, in the same order, with the same names they just read on the review screen. They are watching the list they approved. If it stops, it stops cleanly and says what exists. When it finishes, the read-only setup check reads GitHub back and reports what is really there, and that report is what they hand over — not their own recollection.

**What enabled this:**

| Capability | Role |
|------------|------|
| A deterministic check-then-act engine | Idempotent by construction; safe to re-run after any interruption |
| Review before any irreversible write | The operator authorizes a plan they have read, in names and destinations |
| Progress as named work, never as a percentage | The count comes from the approved plan; the denominator grows only if the engine reports something the plan did not |
| A silence watchdog that stops all motion | A dead run cannot look like a slow one; the recovery is to read GitHub, not to cancel |
| The read-only setup check | Turns handover from a claim into a report |

---

### MTM-8: The day the ecosystem stops answering

> A person types a prompt into their coding assistant, as they have every day for months. It is rejected. So is the next one. Nothing they did caused this, and nothing they can do will fix it.

- **Success:** They can tell that this is not their fault, get a route to whoever fixes it, and get back to a working state by installing a named prior build — without understanding what went wrong.
- **Failure:** They are stranded with a system-level failure and no vocabulary to describe it. `Evidence: this happened. A shared manifest field was renamed from "component" to "product" while one resolver still filtered the old name; it loaded foundation-only, the organization's own command vanished, an optional notification hook exited non-zero, and Claude Code rejected every prompt on the machine. An optional notification bridge became a full harness outage.`
- **Design implication:** Three durable countermeasures came out of that incident and all three are now load-bearing. Optional transports are **fail-open**: a hook shim returns success with a concise diagnostic when its optional command is unavailable or fails, because losing an optional notification must never make the assistant unusable. The contract gate is per-verb, exact-major, and fail-closed, so drift surfaces as an honest unreadable state rather than as a silently wrong result. And the release gate runs the exact packaged artifact under a Finder-shaped environment, because the prior gates all passed while the shipped binary and its source disagreed on a user-visible field.

#### Current State (B-)

An optional integration is wired in such a way that its absence is indistinguishable from a hard failure, and a version mismatch anywhere in the chain is treated as ordinary data. Testing stops at the mock boundary, so the packaged artifact is never the thing under test — and the packaged artifact is the only thing anyone actually runs.

#### A+ State

The optional thing degrades to nothing and says so quietly. The version mismatch surfaces as *"Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up."* — a sentence with no jargon, no blame, and no invitation to force past it. And if the person does end up stranded, the recovery is a named prior signed build they can install themselves, under a rule that release tags are immutable and a defective build is superseded rather than moved. `Evidence: the codified outcome of that incident is a declared fail-open hook policy with a bounded internal timeout, shipped in every release directory's compatibility pin.`

**What enabled this:**

| Capability | Role |
|------------|------|
| Transport fail-open for optional hooks | An optional notification can never make the harness unusable |
| The per-verb, exact-major, fail-closed schema gate | Drift becomes an honest unreadable state rather than a silently wrong result |
| Release gates driven against the packaged binary | Catches the class where source and signed artifact disagree, which a mock cannot see |
| A named rollback artifact in every release note | Recovery does not require understanding the failure |

---

### MTM-9: Coming back for a project

> Weeks later, a person opens a project of their own and wonders whether it can be part of this. The project has its own agents, its own rules, and years of somebody's thinking in it.

- **Success:** The safe, bounded part is offered directly with a clear statement of what will be added, what will be preserved, and what will not be changed. The unsafe part is handed to whoever actually owns that project, as an actionable package rather than as a suggestion.
- **Failure:** The project's own content is flattened, or the interaction ends at "the owner will review" with no route, no prompt, and no verification — which is where projects go to die.
- **Design implication:** *"Owner will review" without a prepared route, prompt, or verification step is not a service outcome.* Readiness is evaluated per assistant, so an existing setup for one does not block a safe addition of the other. Project-specific customization is treated as a **visible positive fact**, not as a blocker. When work needs semantic judgment, the CLI generates a prompt that names what to preserve, what is prohibited, the bounded allowed actions, the verification command, and the stop conditions requiring an owner decision — and the app opens a real Terminal session at that project with it, observing the launch lifecycle without ever interpreting the assistant's output.

#### Current State (B-)

A tool that either refuses to touch anything with existing content, or overwrites the project's instructions with a template. Both outcomes lose the project's accumulated thinking — the first by omission, the second by force — and neither leaves anyone with a next step.

#### A+ State

The project is classified into one of five plain-language categories by the CLI, and the person is only ever shown the actions that match their actual authority. A ready project with local customization says so approvingly: *"Ready. Claude and Codex are connected. This project also has its own pipeline, writing, and legal agents."* A project needing judgment gets a real Terminal session with a generated prompt, or a copyable handoff for its owner. And the app resolves each assistant to an absolute executable before launching, because Finder and Terminal do not share the same environment — a defect that shipped once and is now a rule.

**What enabled this:**

| Capability | Role |
|------------|------|
| Per-assistant classification | An existing setup for one assistant never blocks a safe addition of the other |
| The generated prompt contract | Names preservation, prohibitions, bounded actions, verification, and stop conditions — composed by the CLI, never by the app |
| Actor routing per situation | Reversible exact-match adoption goes to the CLI; semantic reconciliation goes to an authorized author; everything else goes to the named owner |
| Absolute executable resolution | Finder and Terminal do not share a `PATH`, and that fact has already cost one release |

---

## MLP Anchors

The three moments the product must nail. Everything else can be merely good.

1. **The account of what just happened (MTM-1)** — the transaction never claims less than it did, and never claims more. A blocked row produces zero changes, and "nothing changed" is only ever said against an empty ledger.
2. **The day nothing happens (MTM-2)** — the quiet icon is always right, and when it cannot be sure it says so instead of staying quiet. Silence is the success state, and a false green is a violation of the product rather than a bug in it.
3. **The stop that is not a failure (MTM-3)** — a courtesy never renders as a catastrophe. The person can tell, in two seconds and without help, whether something is wrong or whether something of theirs was recognised and left alone.

These three are one claim in three forms: **the product never says something it cannot prove.** MTM-1 is that claim about the past, MTM-2 about the present, and MTM-3 about intent.

---

## Pain Point to Delight Point Transformations

| Pain Point | Current State | A+ State |
|------------|---------------|----------|
| **Being the sync layer** | A change made once does not land everywhere. The author walks machine by machine and project by project, and remembers, or does not. "That shit gets exhausting" | Authored once, pulled on cadence by everyone entitled, personal work untouched. The author stops asking whether it landed |
| **The wall between the person and the power** | The intelligence is CLI-shaped and the CLI shape is a wall. The layers stayed effectively single-user inside the organization | A double-click, a browser sign-in, and nine named steps to a working sixteen-layer machine, with no terminal and no configuration file |
| **Not knowing whether the machine is right** | Ask the one person who could tell, or find out when something breaks. The honest answer is usually "nobody has looked" | One glanceable honest state, re-derived by re-running the real pipeline, with *could not check* as a real answer rather than a fallback to optimism |
| **A stop you cannot interpret** | One "setup failed" screen for a fault, a courtesy, a wait, and someone else's homework. The safe assumption is always the worst one | Seven variants chosen by who owns the fix. Blue for a courtesy, and a primary action that says `Keep what I have` |
| **The raw machine sentence** | A VCS or system error lands on the screen and reads as *the tool broke my work* | Framed verbatim when it was written for a person; otherwise only in a collapsed block addressed to whoever looks after the Mac. Never a headline, never concatenated |
| **The estimate that is a promise** | A percentage, a countdown, or a timer-paced phase label — a promise the app cannot keep, and one it will eventually break in front of someone | Named phases and an honest count of real work in flight, which disappears when the run ends so it can never read as a score |
| **Waiting that might be broken** | A dead operation and a live one draw the same spinner. A boolean cannot express *started but silent*, so it stays true forever and still looks healthy | Motion reachable only from a live phase carrying the name of its subject, and a silence watchdog that stops all motion the moment the truth changes |
| **Invisible entitlement** | People do not know what they could have, so they never ask, and the organization concludes there is no demand | A roster of what is already theirs, with a Join button instead of a request form |
| **No way back** | A non-technical person has no dignified recovery path and must find someone who does | A named prior signed build they can install themselves, under an immutable-tag rule, in every release note since 0.2.1 |
| **"The owner will review"** | A dead end wearing the costume of a next step | An actionable package: what to preserve, what is prohibited, what is allowed, how to verify, and when to stop and ask |

**The transformation most likely to generate word of mouth is not any of the delights — it is MTM-3.** "It found something of mine and left it alone, and it told me so in a way that did not make me feel stupid" is the sentence a person repeats to a colleague. Nobody tells a story about a green icon.

---

## Moment Ranking

| Rank | Moment | Impact if Failed | Design Priority |
|------|--------|-----------------|-----------------|
| 1 | **MTM-1 — The account of what just happened** | Existential and already realised. The person concludes the product tells them what they want to hear, and no later honesty recovers it | **P0.** Preflight before any irreversible write; a required ledger; a postcondition assertion; held never treated as blocked |
| 2 | **MTM-2 — The day nothing happens** | Existential. A false green makes the icon decorative and every subsequent true green worthless. Already realised through v0.2.3 | **P0.** Fail-closed gate; honest non-answer states; shape before colour; no celebratory state; re-derive, never remember |
| 3 | **MTM-3 — The stop that is not a failure** | Very high, and the most frequent of the three. The most common real outcome of a first setup is a screen full of holds; misread, it ends the relationship | **P0.** Seven variants routed by who owns the fix; H4 never orange; frame-or-replace; every screen has an offline exit |
| 4 | **MTM-6 — The change that arrives unasked** | High. Without it the product is a one-time installer and the origin job is unmet — and its failure mode destroys someone's work | **P0.** Pull-only and downward by construction; human-owned trees; an honest empty state in `What changed` |
| 5 | **MTM-4 — The roster reveal** | High for adoption, low for safety. Without it there is no pull at all, and anxiety wins by default | **P0** for adoption. Entitlement as access; no internal vocabulary; fail-closed grouping; a roster that is never empty |
| 6 | **MTM-7 — The organization's first standup** | High and untested. A half-created organization that hides its own history, and an operator who cannot defend what they authorized | **P0** for the buyer, **and the largest untested assumption in the product** — no third-party operator has ever run it |
| 7 | **MTM-8 — The day the ecosystem stops answering** | High and already realised. A person stranded by a system-level failure they did not cause and cannot describe | **P0.** Fail-open optional transports; a per-verb fail-closed contract gate; gates against the packaged artifact; a named rollback |
| 8 | **MTM-5 — The one thing only they can do** | Medium. A careful person correctly refuses an over-broad request, and the product records it as a drop rather than as the right decision | **P1.** Just-in-time least-privilege grant; no token field in the model; a human-paced wait with a way back in |
| 9 | **MTM-9 — Coming back for a project** | Medium. Handled badly it becomes a support queue; handled well it is the second reason to open the app | **P1.** Per-assistant classification; a generated prompt contract; no completion state that completes nothing |

**If only three could be nailed: MTM-1, MTM-2, and MTM-3.** They are the same promise in three tenses, and they are the only three whose failure cannot be repaired by anything else in the product.

---

**Related:** [Journey Maps](20-journey-maps.md) | [JTBD](30-jtbd.md)
