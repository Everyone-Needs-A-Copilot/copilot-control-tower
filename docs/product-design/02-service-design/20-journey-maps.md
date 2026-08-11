# User Journeys

<!--
FACILITATION GUIDE — Service Designer
======================================
This document maps the end-to-end experience. We're designing for
humans, not screens. The Service Designer has VETO POWER over any
decision that harms user experience.

PREREQUISITE: 00-vision.md, JTBD, and at least one interview must
be completed.

CONVERSATION FLOW:
1. Identify who the users are (personas)
2. Map each persona's journey with emotional state, pain, and solve per stage
3. Find the struggling moments (where friction lives)
4. Map the emotional arc (how they feel at each stage)
5. Define touchpoints (every point of interaction)
6. Map intelligence handoffs (what flows between systems/stages)
7. Capture critical design requirements

QUESTIONS TO ASK:

## Round 1: Personas
- "Who are the different types of people who would use this?"
- "For each type: What's their context? What do they already know?
  What are they feeling when they arrive?"
- "Which persona is the PRIMARY user we design for first?"
- "Consider: the primary operator, the reviewer/approver, the admin/configurator,
  and any secondary beneficiaries"

## Round 2: Primary Persona Journey
For the primary persona, walk through the full journey with this
structure for each stage:

- What happens at this stage?
- Emotional state: How are they feeling? (one word + "I am..." quote)
- Pain (today): What goes wrong without this product?
- Solve: What does {{PRODUCT_NAME}} do at this stage?

Ask:
- "How do they first discover or encounter this product?"
- "What's their first interaction? What do they see, do, feel?"
- "Walk me through a typical session — from opening the product
  to finishing their work."
- "When do they have their 'aha' moment?"
- "What brings them back? What does ongoing use look like?"

## Round 3: Secondary Persona Journeys
For each additional persona:
- "Walk me through [persona]'s journey — from first contact with
  the product to getting their job done."
- Keep secondary journeys high-level (stage names + what they need
  at each stage), not full narrative.
- "What do they share with the primary persona's journey?
  Where do their needs diverge?"

## Round 4: Struggling Moments
- "Where in this journey would someone get confused?"
- "Where would they feel frustrated or stuck?"
- "Where might they give up and leave?"
- "What's the hardest thing they have to do?"
- "What information do they need that they don't have at each step?"
- "Where could the AI get in the way instead of helping?"

## Round 5: Emotional Arc
For each stage of the journey, ask:
- "How is the user feeling here? Overwhelmed? Hopeful? Skeptical?"
- "What would make them feel confident at this moment?"
- "What could go wrong emotionally?"

## Round 6: Touchpoints
- "What are ALL the ways a user interacts with this product?"
- "Are there touchpoints outside the product? (Email notifications,
  calendar reminders, team collaboration)"
- "Which touchpoint has the most impact on their overall experience?"

## Round 7: Intelligence Handoffs
- "What data flows in from outside this product?"
- "What does this product hand off to other tools when a stage completes?"
- "What would break if the handoff failed?"

## Round 8: Critical Design Requirements
- "Looking across all personas and all stages, what are the must-have
  design requirements — the ones that, if missed, the product fails?"
- "For each requirement: Why is it required? What's the success metric?"

SYNTHESIS:
Build the journey for the primary persona as a stage-by-stage narrative
with emotional state, pain, and solve per stage.
Secondary personas can be abbreviated. End with a requirements table
derived from the journeys.
-->

> **Status — rebuilt from evidence 2026-08-02.** Mapped from the shipping code (`native/wizard.swift` — nine real stages, `native/control-tower-tray.swift` — the steady state, `native/user-settings.swift`, `native/admin.swift`), the copy specs in `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/`, the live-run evidence in that initiative's phase files, and the schema-mismatch incident record. It describes **v0.4.0** (build 19, 2026-08-02, embedded helper `cc 2.2.0`). Product status is **DOGFOODING**: live on exactly one organization (ENAC), sixteen of sixteen layers applied live, not offered outside, not generally available.
>
> **This is a documented journey, not an imagined one.** Every struggling moment below actually happened and is cited. The one persona whose journey remains largely a bet — the third-party admin operator — is labelled as such in the same breath as its stages.
>
> **A note on vocabulary.** The stage names below are the ones a *person* experiences, not the ones the system uses. Where a stage has an on-screen name in the shipping app, that name is quoted. Internal words like rank, manifest, package, and tier appear only in the backstage columns, where they belong, and never as something a person is asked to understand.

## Personas

Three personas carry real weight. They are not three market segments; they are three different relationships to the same system, and the product succeeds or fails at each one independently.

**1. Bob — the change-averse non-technical adopter (PRIMARY).** No terminal, no YAML, routinely denies OS permission prompts, ignores single nudges. He arrives sceptical, because most tools rolled out at work have made his job harder. He is precise and detail-oriented, so **he will catch a dishonest status** — which makes an icon that cannot lie a survival property rather than a nicety. "Bob is not a reliable actor" is a load-bearing design assumption, not a slight: nothing safety-critical depends on him noticing anything. He is asked about his own data and nothing else. Target emotion: comfortable *and* excited — these are superpowers he has wanted his whole career. `Evidence: GROUNDED archetype. Open gap: no person other than the author has yet been observed completing first-run setup unaided.` <!-- TODO: confirm how many people at ENAC beyond the owner are running Control Tower today, and whether any of them completed first-run setup with no assistance. This is the single highest-value unmeasured fact about the product, and it is also flagged in 00-overview/20-success-metrics.md. -->

**2. Earl — the organization owner and admin operator.** He runs a separate Admin build with sixteen surfaces. He is accountable to a security team and to whoever asks him later why a repository exists. He needs to be able to defend every change he authorized. `Evidence: RUN ONCE, BY THE AUTHOR. Admin mode has stood a real sixteen-layer organization up end to end. No third-party operator has ever touched it, so his journey below is the largest untested assumption in the product and should be read as a hypothesis with a working implementation behind it.`

**3. Pablo — the author who publishes upstream, and the trust basis.** He writes the content everyone else inherits, holds the signing identity, and is the person the product exists to release from being the sync layer by hand. His journey is the only one with longitudinal evidence, and it is also the journey that produced the product's two worst incidents. `Evidence: OBSERVED, continuously.`

**Deliberately not personas:** open-source contributors wanting to submit patches, and developers receiving an engineering handoff. Contribution mechanics stay minimal on purpose.

## 1. Bob's Journey — the non-technical adopter

The shipping first-run experience is **nine steps** (`Step 1 of 9` through `Step 9 of 9`, verified in `native/wizard.swift`), but the *journey* is larger than the wizard at both ends, and it is not a line. It has a first-class stop that is not a failure, it has loops back into itself, and it has a long tail that is the real product.

```
Handed a link → Install & first sight → "Which organization?" → Sign in in the browser
   → "Checking this Mac" → The roster reveal (4 steps, one beat) → "Set up"
   → [ Holding — 7 named variants, a real destination, not a dead end ]
   → "Verify" → THE QUIET ────┬──> "Something changed"  ──┐
                              ├──> "Something needs you" ─┤
                              └──> "Coming back for a project" ──┘  (all three return to THE QUIET)
```

Three loops are designed rather than tolerated: **Holding → Set up** (`Try again` / `Check again`), **Holding → the quiet** (`Continue in the menu bar`, which deliberately does *not* mark setup complete — the tray carries the state), and **the quiet → Set up** (finish personal setup later, from the popover). A person is allowed to leave the wizard unfinished and be fine, which is the opposite of how installers usually behave.

**Stage 1: Handed a link**

- Someone at work sends a link to the organization's own download page, or an invitation email. The page is org-branded and prints the organization's own GitHub name in a labelled, one-tap-copyable block, because the very next thing the app may need to ask is a question Bob cannot answer from memory.
- Emotional state: **guarded** — "I am about to be given another tool that will make my job harder, and I will be blamed if I do not use it."
- Pain (today): the ecosystem is CLI-shaped, so there is no link to send. The realistic alternative is a colleague sitting at his machine, which mostly never happens.
- Solve: a signed, notarized DMG that installs like any other Mac app, and a page that already knows the answer to the question the app is about to ask.

**Stage 2: Install and first sight**

- He drags the app across, opens it, and macOS accepts it because it is notarized and stapled. An aviator glyph appears in the menu bar. Nothing else happens.
- Emotional state: **relieved, and slightly suspicious** — "I am relieved nothing exploded. I am also not sure a small icon is really the whole thing."
- Pain (today): an unsigned or unnotarized binary at this moment is a hard stop for a person who has been trained to distrust exactly this dialog.
- Solve: Developer ID signing, notarization, stapling, and a Gatekeeper check run against the mounted download before release. The launch environment is handled too, because Finder does not hand an app the same `PATH` a Terminal does — the app resolves its helper from inside its own bundle by absolute path, never from `$PATH`.

**Stage 3: "Which organization are you with?"**

- Only shown when nothing on the Mac already knows. The app exhausts a pointer already set on the machine, then the admin standup's own record, silently, before it asks anyone anything.
- Emotional state: **momentarily exposed** — "I am being asked something about my own company that I am not sure I know, and I do not want to get it wrong."
- Pain (today): before this existed, *every fresh Mac* hit the underlying error and fell through to the generic "Something stopped me from reading your setup, so I won't guess" screen — a dead end at the second screen of the product. `Evidence: walkthroughs/org-question-copy-spec.md §1.`
- Solve: one field on an inline screen, in accent blue and never orange, because a question is not a pause. The field accepts a pasted address as readily as a name. And the primary fix is not copy at all — it is that the organization's own page prints the name, so most people never see this screen.

**Stage 4: Sign in in your browser**

- A browser device flow. A short code, the GitHub page, and the app waiting. The app's data model has **no field a token could occupy**, by construction.
- Emotional state: **at ease, briefly** — "I am doing the one thing on this whole screen I have done a hundred times before."
- Pain (today): every alternative sign-in shape either asks a non-technical person to paste a credential somewhere, or puts a vendor in the middle of their identity.
- Solve: the only human-paced wait in the product, and it says what *he* has to do rather than what the app is doing. A lost browser window is the common failure, so there is a way back in. An expired code has its own ending rather than a stall.

**Stage 5: "Checking this Mac"**

- Three real calls in one seam: who you are signed in as, the health of what is already here, and a read-only plan of the whole topology. Nothing is changed. The four components are **named before results arrive**, so the screen is never a field of unexplained circles.
- Emotional state: **braced** — "I am waiting to be told a list of things that are wrong with my computer."
- Pain (today): the honest answer to "is my machine correct?" is normally "nobody has looked," and the only person who could look is busy.
- Solve: an inventory that separates five independent facts per layer — the space exists, the folder is visible, it is connected, it is current, and it was verified. A hidden mirror is never evidence that something is present. This is the fix for a real defect: through v0.2.3 a person could see a green Personal result with **no visible folder anywhere on their disk** (closed in 0.2.4, ADR-005).

**Stage 6: The roster reveal — "What you're getting", "Departments", "Your connections", "Your projects"**

- Four wizard steps, one emotional beat: *here is everything that is about to become yours.* What you're getting names the four copilots in plain language. Departments offers per-row **Join** for what his access already permits. **Your connections** (new in v0.4.0) shows the organization's declared services grouped into "Ready to use" and "Available to connect." Your projects triages his own work into five CLI-authored categories: Ready, Can finish automatically, Needs guided setup, Needs the project owner, Couldn't confirm.
- Emotional state: **startled, then quietly excited** — "I am startled that I apparently get all of this, and nobody had to approve it for me."
- Pain (today): entitlement is invisible. People do not know what they could have, so they never ask, and organizations conclude there is no demand.
- Solve: entitlement is repository access and nothing else, rendered as a list rather than negotiated as a favour. Before v0.4.0 the connections step had nothing to show at all — an empty state where the organization's roster should have been. `Evidence: CHANGELOG 0.4.0, "closing the 'Your connections' empty-state gap".`

**Stage 7: "Set up"**

- The one irreversible act. All deterministic preflight — including a nine-state git-history classifier — runs first, so a blocked row yields zero changes rather than half a set. Progress is a named list of real things, filling in place, with a count only while work is genuinely in flight. **No percentage, no countdown, no estimate**, ever.
- Emotional state: **held breath** — "I am at the moment where, if this is going to break something of mine, it breaks it now."
- Pain (today): the alternative is a stranger's shell script and hope.
- Solve: the preflighted saga. Only a merge-base-proven fast-forward is auto-repaired; every other history state routes to a person. Apply asserts that the result equals the target, and a run-scoped ledger of completed actions threads through every exit path — so "nothing changed" is only ever a legal claim on an empty ledger. The count only exists while the run is alive, so it can never be misread as a score afterwards.

**Stage 8: Holding — the honest stop (a destination, not an error branch)**

- Reachable from stages 5, 6, and 7. **Seven named variants**, chosen by *who owns the fix*, never by what went wrong: H1 the helper is not installed · H2 I cannot read your setup · H3 I could not finish one part · H4 **something here is already yours** · H5 waiting · H6 waiting on your organization · H7 one permission only you can grant.
- Emotional state, and this is the whole design: **not blamed.** On H4 — "I am relieved. It did not fail; it found something of mine and left it exactly as it was." On H6 — "I am off the hook, and I know who is on it." On H2 — "I am worried, but it did not guess, and it did not touch anything."
- Pain (today): one generic "setup paused" screen conflates a fault, a courtesy, a wait, and someone else's homework, so a person cannot tell whether to worry, and the safe default is to worry.
- Solve: H4 is forbidden from being orange and forbidden from using the words *paused*, *stopped*, *problem*, or *error*, because it is a success with a question attached. It shows a card titled **What I left alone**, the reassurance line **Nothing was changed, moved, or removed**, and its primary action is **Keep what I have**. H6 is the only variant whose primary is not a retry, because retrying cannot change the outcome — the forward action is to leave, and it says so. Every variant has at least two exits, one of which works offline and with a broken helper. A raw machine sentence never becomes a headline: it is either framed under **What setup found:** when the CLI wrote it for a person, or it goes only into a collapsed **Details for support** block addressed to whoever looks after the Mac.

**Stage 9: "Verify"**

- The same health pipeline is re-run against the result. The person advances only when results are known, and a failed item can be retried on its own.
- Emotional state: **trusting, cautiously** — "I am inclined to believe this, because it checked twice and it told me the awkward parts."
- Pain (today): installers declare success by having finished, not by having checked.
- Solve: readiness requires the complete expected roster, visible folders, connection, successful synchronization, **and** a post-apply verification. There is no confetti. Silence is the success state, and the finished list stays reachable as evidence rather than being replaced by a reward.

**Stage 10: The quiet (the real product)**

- A single timer at three hundred seconds, plus a refresh on launch and on opening the popover. Twelve badge tokens, shape first and colour second, so the state survives a monochrome or colour-blind render. Most days: nothing.
- Emotional state: **forgetting it exists** — "I am not thinking about this at all, which I now realise is the entire point."
- Pain (today): being the person who has to remember to check, forever.
- Solve: healthy is the *absence* of signal, never a reward. Real-time refresh is explicitly the wrong model; cadence with a manual `Sync now` covers the rare urgent case.

**Stage 11a: Something changed**

- An authorized upstream change lands, or a department he joined appears. `What changed` opens a plain list grouped into projects set up for him and projects brought up to date, with an explicit **"Nothing has changed since you last looked."** empty state.
- Emotional state: **mildly delighted** — "I am pleased that something I did not ask for and did not have to do just turned up."
- Pain (today): a change made once does not land everywhere; the human is the sync layer.
- Solve: pull-only and downward by construction. The scheduled path holds no upward push credential to any shared remote, so the worst leak — a silent bidirectional sync — is closed structurally rather than by discipline.

**Stage 11b: Something needs you**

- A badge appears with one sentence naming the specific component and the specific next action: `Review your changes` for a working tree only he can decide about; `Grant this on GitHub` for a missing permission; `Add the connection`; `Choose folder…`.
- Emotional state: **a small cold drop, then resolution** — "I am briefly anxious that something is wrong, and then it turns out to be one sentence and one button, and it is about my own stuff."
- Pain (today): a raw VCS error reads to a non-technical person as *the tool broke my work*, and there is nowhere to go from there.
- Solve: routing by actor-competence times reversibility. Auto-act on reversible things he cannot judge; route to whoever holds the authority what he cannot action; ask him only about non-deferrable decisions on his own material. Proximity to the menu bar is not competence.

**Stage 12: Coming back for a project**

- Later, and by his own choice, he opens a project's detail from the popover. Depending on the CLI's classification he gets a bounded safe action, or **Run in Codex** / **Run in Claude Code** opening a real Terminal session at that project with the CLI-generated prompt, or **Copy project-owner handoff** — an actionable package for the person who actually owns that project.
- Emotional state: **capable, and appropriately bounded** — "I am being handed the part I can do, and the part I cannot is being handed to a named person rather than left on me."
- Pain (today): "the owner will review" with no route, no prompt, and no verification is where projects go to die.
- Solve: *"Owner will review" without a prepared route, prompt, or verification step is not a completion state.* The app resolves each assistant to an absolute executable first, because Finder and Terminal do not share a `PATH` — a defect that shipped once and was fixed in 0.1.2.

---

## 2. Earl's Journey — the organization owner and admin operator

Abbreviated, and honestly labelled: this journey has been walked exactly once, by the person who wrote it. Eleven onboarding surfaces and five governance surfaces, all over a deterministic bash engine that decides existence and idempotency by check-then-act.

```
Orientation → Prerequisites → Contacts → Connect GitHub → Describe your organization
   → Integrations → Secret store → Review setup → Organization setup → Setup check → Done
                          ↓ (later, and repeatedly)
   Add a department · Someone left · Connect the shared store · Org setup · Analytics
```

- **Orientation and Prerequisites:** to know what he is committing to before he commits, and to find out his machine is ready without installing anything himself — `gh` and `jq` are vendored into the bundle.
- **Connect GitHub, Describe your organization:** to sign in as himself, and to describe the organization in plain fields rather than in configuration.
- **Integrations, Secret store:** to point at a shared store rather than distribute values. The endpoint is not a secret; access stays gated by each person's own GitHub team membership.
- **Review setup:** the decisive surface. To read exactly what will be reused, created, downloaded, initialized, connected, synchronized, and verified — by name and by destination — **before** the first irreversible write.
- **Organization setup:** to watch a named list of real things fill in, with a count only while the run is alive, a bar only above seven rows and only as the visual twin of that count, and no percentage anywhere. If it goes silent, the run says **No answer yet** and stops animating, offering `Keep waiting` and `See what's really on GitHub` — because a dead operation must never look like a slow one.
- **Setup check:** to read GitHub read-only and find blockers before his colleagues do. This is his equivalent of Bob's Verify, and it is the surface his credibility rests on.
- **Governance, later:** to add a department without hand-editing anything, to offboard someone through a defined path, and to accept honestly that content already on a departed person's disk is not remotely wiped — stated rather than hidden.

**Where Earl diverges from Bob:** Bob is asked only about his own material; Earl is asked about everyone's. Bob's worst outcome is a broken machine; Earl's is a half-created organization that hides its own history. So Earl's journey is weighted almost entirely toward *see-before-create* and *stop-cleanly*, and almost not at all toward reassurance.

---

## 3. Pablo's Journey — the author who publishes upstream

```
Author in an editor → Commit and push to a tier → Cadence carries it down
   → Watch it land on entitled machines → (open) Elevate something from a project
   → Cut a release → Rollback if defective
```

- **Author:** to write markdown in his own editor and save, not to perform a Git ceremony. `Evidence: MODEL-IN-HEAD — the multi-writer loop has never been run with more than one writer.`
- **Publish downward:** to have one change reach everyone entitled to it, on cadence, without touching anything anyone owns. This is the origin job and it is the only one that ever mattered to him personally.
- **Elevate:** to raise something built inside one project to a shared tier. **This is the unfinished part of his journey.** The `publish` verb is formally deferred (ADR-008); the interim route is a documented manual copy-commit-push into the tier repository's own working directory, with symlinking explicitly forbidden.
- **Release:** to have the gates catch what he would have missed, and to be able to name a rollback artifact anyone can install without a support conversation.

**Where Pablo diverges from both others:** he is the only persona who *writes* into the system, which means he is the only one who can destroy something at scale — and he did. His journey is therefore the one most shaped by refusals rather than by capabilities.

---

## Struggling Moments

Every row below happened. This is not a risk register; it is a defect record, which is why it is the right list of design targets.

| Moment | What Goes Wrong | What They Need | Severity |
|--------|----------------|----------------|----------|
| **"It said nothing changed, and it had already created two repositories."** | Control Tower 0.2.4's first owner-run apply stopped on a repository whose history was not fast-forwardable, and the screen said setup stopped *"before changing anything."* Two Personal GitHub repositories had already been created and seeded minutes earlier. The claim was false for that run | An account of what happened that is bounded by a ledger rather than by intent: all deterministic preflight before any irreversible write, and never the words "nothing changed" without an empty completed-actions ledger to back them | **Existential.** The one product whose entire promise is honesty told a person something untrue about their own accounts |
| **"Claude Code rejected every prompt on my machine."** | A shared manifest field was renamed from `component` to `product`, while one resolver still filtered the old name. It loaded foundation-only, the organization's own `discord` command vanished, the prompt hook exited non-zero, and the assistant blocked every prompt. An optional notification bridge became a full harness outage | A canonical field with bounded legacy compatibility and a hard failure on conflicting duals; optional transports that fail *open*; and a per-verb schema gate that decodes only the version before trusting any other field | **Existential.** The ecosystem itself stopped answering, and nothing the person did caused it |
| **"One routine update deleted 12,537 lines of our organization's content."** | A materialize target pointed at a human-owned authoring checkout through a symlink. A single reconcile deleted the content in one commit, and a backup job then pushed it to origin | Structural separation, not care: a guard that refuses to write or delete through any symlink escaping the materialize root, and a documented copy-commit-push elevation path with symlinking forbidden | **Existential.** Never-destroy is the invariant this cost was paid for |
| **"It says Personal is ready and there is no folder anywhere on my disk."** | Through v0.2.3 a GitHub repository or a hidden mirror counted as an installed layer, so a person could see a green result backed by nothing they could see | Readiness that requires the complete roster, a visible folder, a connection, a successful sync, **and** a post-apply verification. A hidden mirror is never evidence of presence | **Critical.** Fixed in 0.2.4 under ADR-005; this is the canonical false-green |
| **"The app couldn't find the command that is definitely installed."** | The bundled helper resolved its own dependency by searching `PATH`. Finder launches an app with `/usr/bin:/bin:/usr/sbin:/sbin`, so a Homebrew install vanished. Tests had mocked the helper and stopped at the app boundary, never exercising its dependencies | The helper owns machine inventory and resolves every dependency to a canonical absolute executable; the app stays parse-only; and the release gate runs the real packaged artifact under Finder's environment | **Critical.** Fixed in 0.1.2; the release gate that catches this class shipped in 0.1.3 |
| **"A dead operation and a live one drew the same spinner."** | Progress was a four-case enum whose idle and working states shared one branch, and readiness was a plain boolean — and a boolean cannot express *started but silent*, so it could stay true forever and still look healthy | Progress as a phase carrying timestamps and the name of what it is working on, with the animated indicator reachable *only* from the alive state, plus a silence watchdog that moves a quiet run to a state with no motion at all | **High.** A person cannot tell waiting from broken, and waiting-forever is how trust dies quietly |
| **"Nine of sixteen rows want my review, and three of them are just scratch files."** | The history classifier checks the working tree before it compares anything, and any non-empty status — even entirely untracked scratch files — routes to review without fetching. In the real live run, six of the seven already-present repositories landed on review for this reason | The conservative behaviour is *correct* (nothing can distinguish someone's uncommitted edit from their scratch file without making a judgment that belongs to a human) — so the design burden falls entirely on the copy: this must read as courtesy, not as a wall of failures. This is exactly why H4 exists | **High.** The most common real outcome of a first setup is a screen full of holds |
| **"An existing GitHub SSH alias is user-managed; setup did not replace it."** | A raw machine sentence reached the screen as if it were an explanation for a person | A frame-or-replace rule: a CLI string written for a person is framed verbatim under *What setup found:*; a string that names machinery goes only into the collapsed support block. Never a headline, never concatenated into an app sentence | **High.** This exact string is the live-verified case that produced the H4 variant |
| **"It took three tries and two helper fixes to finish one setup."** | The real live apply blocked twice for two genuinely different reasons — a materialize policy gate treating a protective hold as fatal, then a health check treating an honest cold-start warning as fatal — before succeeding on the third attempt | The rule that emerged: a *held* item (a passive, protective non-write) must never share fatal treatment with a *blocked* one (an active refusal), and only a genuine failure may undo an already-verified write | **High.** For the owner this was three sessions; for a Bob it would have been the end of the relationship |
| **"There is nothing on this step."** | Before v0.4.0, the connections step had no roster to show — an empty state where the organization's declared services should have been | The organization's full roster with its real connection state, computed entirely by the CLI and grouped by the app, with an unrecognized state failing closed into the not-available group rather than being shown as ready | **Medium.** Closed in v0.4.0 |
| **"Which organization am I with?"** | Every genuinely fresh Mac hit an error the app could not interpret, and fell through to a generic "something stopped me" screen at the second screen of the product | Resolve it silently from what the machine already knows; if that fails, ask one question in accent blue with a field that accepts a pasted address; and make the organization's own download page print the answer so most people never see the question | **Medium.** Closed; the copy spec notes that if the download page does not print the name, the screen's own sentence becomes a lie |

## Emotional Arc

Specific and contextual. Note that the arc deliberately **does not end high** — it ends in nothing at all, and that is the design.

| Stage | Feeling | What Builds Confidence | What Could Go Wrong |
|-------|---------|----------------------|---------------------|
| Handed a link | Guarded; expecting another mandated tool | The page is his own organization's, signed by it, and names it | It looks like a vendor's page, so it reads as software being sold to him rather than given to him |
| Install & first sight | Relieved, faintly suspicious of how little happened | Gatekeeper accepts it without a scary dialog | An unsigned build; or the app cannot find its own helper because Finder's environment is not Terminal's |
| "Which organization?" | Momentarily exposed at being asked something he may not know | The name is on the page he just came from, one tap to copy | Being told to "check with IT" — which is the answer that ends adoption |
| Sign in in the browser | Briefly at ease, on familiar ground | A short code and a page he has seen before; the app never asks him to paste a credential | The browser window is lost behind other windows and the wait looks like a hang |
| "Checking this Mac" | Braced for a verdict on his competence | The four copilots are named *before* any result arrives; the wait has a subject | A field of unexplained spinning circles, which reads as the machine being examined for faults |
| The roster reveal | Startled, then quietly excited — the first genuine pull | Seeing what he gets, in plain names, with nobody's approval required | A wall of internal vocabulary; or an empty step where his organization's connections should be |
| "Set up" | Held breath; the single highest-stakes second in the journey | Having just read exactly what will be created, downloaded, and left alone | A percentage or a countdown, which promises something the app cannot keep; or silence with no named subject |
| Holding (H4) | **Relieved and slightly flattered** — the tool noticed something was his and stepped back | Blue not orange; *Nothing was changed, moved, or removed*; a primary that says `Keep what I have` | Orange, the word "error", or a raw Git sentence — any of which converts a courtesy into a catastrophe |
| Holding (H6) | Off the hook, and clear about who is on it | *There's nothing for you to do*, plus a copyable block for whoever looks after his Mac | Being handed a retry button that cannot change the outcome, which teaches him the buttons are decorative |
| "Verify" | Cautiously trusting | It checked again rather than assuming; the awkward parts were named too | Celebration. Confetti here would tell him the app cares about the milestone rather than the fact |
| The quiet | Nothing. He forgets it exists | Days of silence that turn out to have been accurate | One false green. He is precisely the person who will notice, and there is no recovery from it |
| Something changed | Mildly delighted by an unasked-for gift | A plain list of what actually changed, and an honest empty state when nothing did | A notification about something he cannot act on, which spends the credibility of the alert that matters |
| Something needs you | A cold drop, then quick resolution | One sentence naming the specific component and one button about his own material | A vague "something needs your attention", which is the alert-machine failure in miniature |
| Coming back for a project | Capable, and appropriately bounded | The safe part is offered; the unsafe part is packaged for a named owner | "The owner will review" with no route — a completion state that completes nothing |

## Touchpoints

Ranked by impact on the whole relationship, not by frequency of use.

1. **The menu-bar badge.** Twelve shape-first tokens on a three-hundred-second cadence. Highest impact by a wide margin, because it is the only touchpoint that operates when nothing is happening — and the product's core claim is about what happens when nothing is happening. It is also the only touchpoint that can destroy the relationship in a single frame.
2. **The Holding screen.** The most emotionally decisive surface in the product. Seven variants exist because this is where a person decides whether the tool is careful or broken.
3. **The Set up transaction and its progress list.** The only irreversible touchpoint, and the only place a person's own accounts are changed.
4. **The roster reveal (What you're getting / Departments / Your connections / Your projects).** The only touchpoint that generates *pull* rather than managing anxiety.
5. **The popover.** `YOUR COPILOTS`, `AVAILABLE TO JOIN`, `SHARED WITH YOUR TEAM`, `YOUR ACCOUNTS`, with `Sync now`, `What changed`, `Set up`, `Settings…`.
6. **A real Terminal session, opened at a project with a generated prompt.** The handoff out of the product into the assistant, and the one place the app deliberately stops being the interface.
7. **Settings.** Four components by four tiers, with the visible folder and repository name shown rather than an internal rank.
8. **The Admin app's Review and Setup check surfaces.** Earl's whole credibility, in two screens.
9. **Outside the product entirely:** the organization's own download page (which must print the organization's name for the app's own copy to be true), the invitation email, the GitHub device-flow page, the signed DMG and its rollback instruction, and the collapsed **Details for support** block a person copies and sends to whoever looks after their Mac.

**The touchpoint with the most leverage and the least visibility is the badge.** Everything else is an event; the badge is a standing claim, renewed every five minutes, all day, forever.

## Intelligence Handoffs (Ecosystem)

| Handoff | From → To | What Flows |
|---------|-----------|-----------|
| Entitlement | GitHub repository and team access → the CLI | Who may reach which layer. This is the *only* entitlement mechanism; there is no second access model, no directory integration, and no device-management path |
| Verdicts | the CLI → Control Tower | Typed, versioned JSON: health, the full topology plan with a per-row action, layers and joinability, freshness, project classifications, and connection state. The app decodes `schema_version` **before** trusting any other field, requires an exact major match per verb, and fails closed on a missing security field |
| Organization shape | the admin standup's own record on GitHub → the CLI → both apps | The organization's name, its declared departments, and its declared services. Read at the moment it is needed; the product owns no org structure of its own |
| Connection state | the shared credential store → the CLI → Control Tower | Presence-checked *names* per service, never values. The app groups on the CLI-computed state alone; an unrecognized future state is grouped as not-available rather than rendered as ready. This is the cleanest single example of parse-never-compute in the product |
| Materialization | the CLI → the person's disk | Sixteen layers as visible folders. Written by the CLI; the app never writes a layer |
| A project's work | the CLI → an assistant, via a real Terminal session | A generated prompt naming what to preserve, what is prohibited, the bounded allowed actions, the verification command, and the stop conditions requiring an owner decision. The app displays, copies, and passes it through; it never composes the technical judgment |
| A handoff to a person | Control Tower → whoever looks after the Mac, or the project's owner | A copyable block with the app version, the resolved helper path, the report format, the step, the result, the code, the verbatim message, and when it was recorded. Any line the app cannot fill is **omitted rather than filled with "unknown"** |

**What breaks if a handoff fails, in order of severity.** If the *verdict* handoff drifts, the app renders a stale contract as if it were current — this is the schema-mismatch class, and it took down every prompt on a machine, which is why the gate is per-verb, exact-major, and fail-closed rather than lenient. If the *entitlement* handoff fails, a person is silently under-provisioned and has no way to know what they are missing. If the *connection-state* handoff fails, the app degrades to the same honest empty state the step always had, with a quiet update hint — never to an optimistic one. If the *assistant* handoff fails, the app names the missing assistant, states that nothing changed, keeps the generated payload, and offers the other assistant or a copy.

## Critical Design Requirements (Summary)

| Requirement | Why | Success Metric |
|-------------|-----|----------------|
| **Never claim a state you cannot prove** | The whole product is a standing claim renewed every five minutes. One false green ends the relationship with the exact person it was built for | Zero layers claimed ready without a visible folder, a connection, a sync, a non-empty resolution, and a post-apply verification (ADR-005). Zero "nothing changed" claims on a non-empty ledger |
| **All deterministic preflight before any irreversible write** | A partial transaction that reports success is the sharpest failure in the record, and it happened | A blocked row produces zero mutations rather than a partial set; the apply asserts the result equals the target |
| **A stop is classified by who owns the fix, never by what went wrong** | A courtesy and a fault feel identical if they share a screen, and the safe default for a change-averse person is to assume the worst | Seven Holding variants, each addressed to exactly one actor; H4 is never orange and never uses failure words |
| **A raw machine sentence never becomes a headline** | A VCS or system error reads to a non-technical person as *the tool broke my work* | Frame-or-replace is applied per string; unpresentable text goes only to the collapsed support block; nothing is concatenated into an app sentence |
| **No percentage, no countdown, no estimate — ever** | An estimate is a computed promise the app cannot keep, and the product's currency is kept promises | Progress is a named phase and an honest count of real work in flight; the count disappears when the run ends so it can never read as a score |
| **A dead operation must never look like a slow one** | Waiting forever is how trust dies quietly, and it shipped once | Motion is reachable only from a live phase that carries the name of its subject; a silence watchdog moves a quiet run to a state with no motion at all |
| **Every screen has at least two exits, one of which works offline** | A dead end for a non-technical person is the end of the product, not the end of the session | `Continue in the menu bar` exists on every Holding variant and never marks setup complete |
| **Ask only about the person's own material** | Handing someone a decision they have no basis for trains blind approval and burns the alert that matters | The set of things a person is asked about stays small and stays about their own material |
| **Never touch a human-owned working tree** | It is the one failure that cannot be apologised for, and it has already cost 12,537 lines | Every visible checkout is human-owned; a clean one may be reused or fast-forwarded, a dirty one is never touched; compensation reports rather than deletes |
| **The app computes nothing** | Two sources of truth, and the app's is the one that can be wrong | Zero resolution, health, signature, merge, or wipe logic in the shipping Swift. **Upheld by architecture, review, and the shell release gates — not by automatically enforced properties of the binary.** The forty architectural fitness tests all scan the retired Rust tree and cannot see a line of the shipping Swift; this is open gap **G-1** and this documentation pass does not close it |

## Service Blueprint Layers

Backstage is given more room than frontstage here on purpose: every existential failure in this product's history originated backstage and only *surfaced* as a frontstage lie.

| Layer | Description |
|-------|-------------|
| **Customer Actions** | Install a signed DMG · name their organization when nothing else knows it · approve one GitHub sign-in in a browser · read a plan of what will be created, downloaded, and left alone · join the departments their access permits · choose which of their own projects to include · authorize one irreversible setup · decide on a hold about their own material (`Keep what I have`) · copy a support block or an owner handoff and send it to a named person · open a project in an assistant · reinstall a prior signed build to roll back |
| **Frontstage** | The menu-bar glyph and its twelve shape-first badge tokens · the popover's four named regions and its action row · the nine-step wizard · the inline organization question · the seven Holding variants and the collapsed **Details for support** disclosure · the named-phase progress list with its count-while-alive and its silence card · the `What changed` view with a real empty state · Settings' four components by four tiers with visible folders and paths · the project drill-in with five CLI-authored categories · the Admin app's sixteen surfaces, of which Review and Setup check carry the weight |
| **Backstage** | Nine verb families over a versioned JSON contract: health, sign-in and permission grant, layers and joining, freshness, update and fan-out, onboard for a person and for an organization, nine workspace subverbs, and connections · a schema gate that decodes only the version before trusting any other field and requires an exact major match per verb (onboard requires major 2; everything else major 1), with a fail-closed vocabulary including *unreadable*, *out of range*, and *missing security field* · a locator that resolves the helper from inside the bundle by absolute path and never consults `$PATH` · a private temporary directory and a marker environment variable for the child process · a nine-state git-history classifier where only a merge-base-proven fast-forward may auto-repair · a run-scoped completed-actions ledger threading every exit path · a never-destroy guard refusing to write or delete through a symlink escaping the materialize root · cold-start mirror seeding so a first-ever layer is not misread as unhealthy · a deterministic bash standup engine doing check-then-act, GET before every write, with `gh` and `jq` vendored · presence-checking of secret *names* against a shared store, never values |
| **Support Processes** | Developer ID signing, Apple notarization, stapling, and a Gatekeeper check against the mounted download · a helper pinned by SHA-256 and independently notarized, verified as not re-signed by packaging · a release gate suite: a 138-scenario smoke harness, a headless detect run through the exact production seam, a sixteen-row eight-history-state topology gate driven against the **packaged** binary rather than a mock, a headless setup-transaction proof against an inert fixture, a schema-compatibility gate, and a check that rejects a signed app missing its automation entitlement or purpose string · in-binary selftests hard-guarded so an arbitrary helper override can never turn a test into a live mutation · immutable release tags, a retained signed artifact per release, and a named rollback in every release note · a declared compatibility pin shipped in every release directory, including a fail-open policy for optional hooks that is the codified outcome of the harness-outage incident |

**Two named gaps in the support layer, stated rather than hidden.** **G-1:** the forty architectural fitness tests all scan the retired Rust tree and cannot see the shipping Swift, and the CI job that runs them is disabled behind a repository variable — so the six invariants are upheld by architecture, review, and the shell gates, not by automatically enforced properties of the binary. **G-2:** the crash-only watchdog described by the invariants exists only in that same retired tree; the shipping app does not install or manage it. Neither is closed by this documentation pass.

---

**Related:** [JTBD](30-jtbd.md) | [Moments That Matter](40-moments-that-matter.md)
