# User Stories

<!--
FACILITATION GUIDE — Service Designer + UX Designer
=====================================================
User stories translate jobs to be done into actionable requirements.
They are written from the user's perspective and must be testable.

Format: "As a [persona], I want to [action], so that [outcome]."

Each story must include inline acceptance criteria — not just what the
user wants, but how we know the product has delivered it. Stories without
acceptance criteria are not implementation-ready.

Story ID format: US-[Persona Code][Number]
  Assign persona codes based on the personas defined in the journey maps.

PREREQUISITE: JTBD, journey maps, and moments that matter must be
completed.

CONVERSATION FLOW:
1. Map stories to personas (from journey maps)
2. Map stories to jobs (from JTBD)
3. Write acceptance criteria inline for each story
4. Ensure every core capability has at least one story
5. Prioritize stories for initial release
6. Confirm critical view coverage

QUESTIONS TO ASK:

## Round 1: Primary Persona Stories
- "As the primary persona, what do they need to do in the core workflow?"
- "What's the trigger for starting this workflow?"
- "What does successful completion look like — what can they now do?"
- "What's the acceptance criterion? If you wrote a test, what would you check?"

## Round 2: Secondary Persona Stories
- "As each secondary persona, what are their most important interactions?"
- "Where do their needs differ from the primary persona?"
- "What information do they need that the primary persona doesn't?"

## Round 3: Administration Stories
- "Who configures the system? What do they need to set up?"
- "What settings need to be adjustable?"
- "How are things maintained over time?"

## Round 4: Prioritization
- "Which stories are essential for the first version?"
- "Which stories can wait for a later release?"
- "Are there stories that depend on other stories?"
- "Which critical views from the design challenge do these stories cover?
  Are there any views with no story coverage?"

SYNTHESIS:
Present stories grouped by persona, then ordered by priority.
Each story should be small enough to be independently testable.
Mark priority: P0 (must have), P1 (should have), P2 (nice to have).
Each story must have inline acceptance criteria before it is
considered implementation-ready.
End with a Story Summary table and Critical View Coverage map.
-->

> **Status — rebuilt from evidence 2026-08-02. Describes Copilot Control Tower v0.4.0** (build 19, source commit `453d15f`, embedded helper `cc 2.2.0`, notarized arm64 DMG). This replaces a version written against a Tauri/MDM product that never shipped — its stories about silent managed provisioning, `.mobileconfig` generators, fleet dashboards, telemetry, and self-update rollback describe machinery that exists only in the retired Rust tree and has no Swift caller anywhere.
>
> **This is a retrofit.** These are not stories proposed for a future build. The product ships, seven signed releases are retained, and a real sixteen-of-sixteen live apply has been completed on one organization. Every story below therefore carries a **Status** — `SHIPPED`, `PARTIAL`, or `NOT SHIPPED` — measured against v0.4.0, and no story exists for a feature that does not exist and is not planned. Product status overall is **DOGFOODING**: live on exactly one organization (ENAC), not offered outside, not generally available.
>
> **The architectural rule every story respects: Control Tower parses, it never computes.** No story below asks the app to decide anything. Where a decision is required — is this layer current, is this project safe to configure, is this connection ready, is this git history fast-forwardable — the CLI decides and the app renders. A story that would require app-side resolution logic is the wrong story.
>
> **Vocabulary rule.** Stories are written in the words a person actually sees. Rank, manifest, package, tier, schema, and repository slug are internal words and never appear as something a person is asked to understand.

## Personas and codes

Carried unchanged from the journey maps and JTBD so the codes line up across phases.

| Code | Persona | Relationship to the system | Evidence |
|---|---|---|---|
| **B** | **Bob — the change-averse non-technical adopter (PRIMARY)** | Uses what work hands him. No terminal, no configuration files. Precise and detail-oriented, which means he will catch a dishonest status | GROUNDED archetype. **No independent non-technical person has yet completed first-run setup unaided** — the single largest unvalidated fact in the product |
| **E** | **Earl — the organization owner and admin operator** | Stands the organization up and governs it afterwards. Accountable to a security team and to whoever asks him later why a repository exists | RUN ONCE, BY THE AUTHOR. A real sixteen-layer organization stood up end to end. No third-party operator has ever touched Admin mode |
| **A** | **Pablo — the author who publishes upstream, and the trust basis** | Writes the content everyone inherits, holds the signing identity, cuts releases | OBSERVED, continuously. The only longitudinal evidence the product has |

Codes match the JTBD's job codes exactly: `US-B*` serves jobs B1–B11, `US-E*` serves E1–E8, `US-A*` serves A1–A7. **Deliberately not personas:** open-source contributors wanting to submit patches, and developers receiving an engineering handoff.

## How to read the Status field

| Status | Meaning |
|---|---|
| **SHIPPED** | The behaviour exists in the v0.4.0 binary or its release pipeline and can be observed by running it |
| **PARTIAL** | The behaviour exists but with a named, honest limitation — a residual the design accepts, or a rule the product states and does not always keep |
| **NOT SHIPPED** | The behaviour is stated somewhere as a commitment or a real need, and the shipping app does not do it. Named as an open item rather than hidden |

---

## Bob — the non-technical adopter (PRIMARY)

### Getting it onto the machine

**US-B01 (P0) — SHIPPED.** As Bob, when someone at work sends me a link to install this, I want it to open on my Mac like any other app, so that my first experience is not a security dialog I have been trained to refuse.

**Acceptance Criteria:**
- The download is a Developer ID-signed, notarized, stapled arm64 DMG; Gatekeeper assesses it without a blocking dialog on a machine that has never seen it.
- The app finds its own helper from inside its own bundle by absolute path and never from `$PATH`, because Finder hands an app `/usr/bin:/bin:/usr/sbin:/sbin` and Terminal does not.
- No admin password, no privileged helper, no installer package. Drag to Applications and open.

*Serves job B1. The `$PATH` rule is the direct fix for a defect that shipped once and was corrected in 0.1.2.*

---

**US-B02 (P0) — SHIPPED.** As Bob, when the app needs to know which organization I am with and nothing on this Mac already knows, I want to be asked exactly one plain question, so that I am not dead-ended at the second screen of a product I have not decided to trust yet.

**Acceptance Criteria:**
- The app exhausts every silent source first — a pointer already on the machine, then the admin standup's own record — and only asks when both fail.
- The question renders inline in accent blue, never orange, and never uses the words *paused*, *stopped*, *problem*, or *error*. A question is not a fault.
- The field accepts a pasted GitHub address and rewrites it in place to the bare name with no message, because the rewrite is its own feedback. Three closed validations fire only after the field is touched and non-empty; a name containing spaces offers a one-click corrected value.
- The disabled primary action always shows its reason as visible text, not only as a tooltip.
- Two exits exist: **Help me find it** and **Continue in the menu bar**.

*Serves jobs B1, B2. Before this existed, every genuinely fresh Mac fell through to the generic "something stopped me from reading your setup" screen. The primary fix is upstream of the copy: the organization's own download page prints the name, so most people never reach this screen.*

---

**US-B03 (P0) — SHIPPED.** As Bob, when I connect my GitHub account, I want to do it in my browser on GitHub's own page, so that I am never asked to paste a credential into something I do not understand.

**Acceptance Criteria:**
- A browser device flow: a short code with **Copy code**, an **Open GitHub** button, and the line "Waiting for you to finish in your browser…".
- The app's data model has **no field a token could occupy**. This is structural, not a convention.
- A lost browser window is the common failure, so a second route back exists: "Didn't see the browser? **Open it again**".
- An expired code has its own ending rather than a stall.
- On success the card collapses to one line naming who signed in. **Continue** stays disabled until then.
- The app requests only what it needs at the moment it needs it. The broader `write:public_key` permission is a separate, later, narrower request (see US-B16).

*Serves jobs B2, B3; MTM-5. The wait names what **Bob** must do rather than what the app is doing, because he is the bottleneck.*

---

### Understanding before authorizing

**US-B04 (P0) — SHIPPED.** As Bob, when the app checks my Mac, I want to see what is already here before anything changes, so that I know it looked before it acted.

**Acceptance Criteria:**
- Nothing is written during this stage. It is a read-only plan.
- The four copilots are **named before any result arrives**, so the screen is never a field of unexplained spinning circles.
- Each layer separates five independent facts: the space exists, the folder is visible, it is connected, it is current, and it was verified. **A hidden mirror is never evidence that something is present.**
- The visible folder where repositories will live is shown, with **Choose folder…**.
- Every row carries the CLI's own plain explanation and its planned action. The app renders the action; it never computes one.

*Serves job B2. This is the fix for the canonical false green: through v0.2.3 a GitHub repository or a hidden mirror counted as an installed layer, so a person could see a green Personal result with no visible folder anywhere on their disk. Closed in 0.2.4 under ADR-005.*

---

**US-B05 (P0) — SHIPPED.** As Bob, when I am partway through setup, I want to see everything that is about to become mine in plain names, so that I understand what I am getting rather than what I am configuring.

**Acceptance Criteria:**
- The step is framed as a confirmation, not a choice: "Everyone on your team gets all of this. There's nothing to pick."
- Exactly one optional checkbox exists in the entire flow — "I also use Codex. Include Codex Copilot too." — and it is framed as a personal preference rather than a configuration.
- No internal vocabulary reaches this screen.

*Serves the roster reveal (MTM-4), the only moment in the journey that generates desire rather than managing anxiety.*

---

**US-B06 (P1) — SHIPPED.** As Bob, when my access already permits me to join a department, I want to join it with one button, so that I stop filing tickets for tools I am already entitled to.

**Acceptance Criteria:**
- Only departments the CLI reports as entitled ever appear. No administrative decision leaks onto this screen, and there is no request form.
- Five row states in words: Joined, Available to join, Joining…, Waiting for the network, or a plain not-available caption.
- Joining is an **offer**, never an alarm: an available department renders as a quiet row and never badges the menu bar.
- On success the row disappears and a full refresh runs, so the copilot rows fill in with the new layer. **The tree filling in is the reward; there is no toast.**
- Retry appears only on retryable outcomes. A stall past twenty seconds gets deliberately different wording from a reported failure: "Sales hasn't come through yet. Nothing was changed."
- Empty state: "No departments are available to you yet. When someone adds you to one, it'll show up here."

*Serves job B8. Entitlement is GitHub repository access and nothing else; the CLI computes it and the app passes back a chosen id.*

---

**US-B07 (P0) — SHIPPED (new in v0.4.0).** As Bob, when I am deciding whether this is worth it, I want to see my organization's own connected services and exactly what is missing from the ones that are not ready, so that the screen is about my company rather than about my laptop.

**Acceptance Criteria:**
- Two groups: **Ready to use** — beginning with the GitHub connection just established — and **Available to connect**.
- An unready row names precisely which credential **names** are missing from the organization's store, in plain language, and never a value.
- The app filters on exactly one CLI-computed field, `secret_state` (`ready` | `needs-connect` | `no-store`). It never inspects a secret, never contacts the store, and never derives readiness itself.
- **An unrecognized future state groups with not-available, never with ready.** The roster fails closed in the one direction that matters.
- When the organization's inherited configuration has not materialized yet, the full roster still renders with every store-dependent row honestly marked as having no store — never an empty list.
- A helper too old to answer degrades to the same honest empty state plus a quiet "Update to see your organization's connections."

*Serves MTM-4. Before v0.4.0 this step had nothing to show at all — an empty state exactly where the organization's roster should have been. This is the cleanest single example of parse-never-compute in the product, in a feature that could very easily have been built the other way.*

---

**US-B08 (P1) — SHIPPED.** As Bob, when I have my own projects on this Mac, I want to choose which of them to include and be told plainly which ones are not mine to decide about, so that I get value without becoming responsible for something I do not understand.

**Acceptance Criteria:**
- The person chooses a folder; only the folders they selected are checked.
- Every project lands in one of five **CLI-authored** categories: Ready · Can finish automatically · Needs guided setup · Needs the project owner · Couldn't confirm. The app filters rows by these categories; it never assigns one.
- Selection is by checkbox rather than immediate action, because at this point in the flow the copilots a project would copy from do not exist on this Mac yet.
- The primary action names its own consequence: **Continue setup**, or **Set up 3 and continue**.
- A standing card reads "Come back whenever you want."

*Serves job B10. "Couldn't confirm" is a first-class, non-embarrassed state.*

---

### The one irreversible act, and its honest account

**US-B09 (P0) — SHIPPED.** As Bob, when I authorize setup, I want it to either do the whole thing or nothing at all, and to tell me truthfully which, so that I am never left reconciling my own accounts by hand.

**Acceptance Criteria:**
- **All deterministic preflight runs before any irreversible write**, including the git-history classification of every repository. A blocked row produces zero mutations rather than a partial set.
- Only a merge-base-proven fast-forward may auto-repair. Every other history state routes to a person and stops the transaction before any personal-repository, key, store, or manifest change.
- Apply asserts that the result equals the target as a postcondition, and reports "already at target" and "fast-forwarded" as distinct outcomes rather than collapsing them.
- A run-scoped ledger of completed actions threads through **every** exit path, including the failing ones. **"Nothing changed" is only a legal claim against an empty ledger.**
- Orphaned personal repositories are adopted, never recreated: create is reachable only when a remote is genuinely missing, and an explicit HTTP 404 is the only accepted evidence of absence.
- A **held** item — a passive, protective non-write — never shares fatal treatment with a **blocked** one, which is an active refusal; and only a genuine failure may undo an already-verified write.
- Progress is a named list of real outcomes with a count only while the run is alive. **No percentage, no countdown, no estimate, ever.**
- Six row states with six distinct symbols and six distinct sentences, including the reconciliation state "Setup didn't say what happened here." for any row the run never mentioned.

*Serves jobs B2, B3; MTM-1, the highest-ranked moment in the product. This is the story the 0.2.4 incident was paid for: an apply that reported it had stopped "before changing anything" after two Personal repositories had already been created and seeded.*

---

**US-B10 (P0) — SHIPPED.** As Bob, when setup stops, I want to be told in two seconds whether something is wrong or whether something of mine was recognised and left alone, so that I can tell a fault from a courtesy without help.

**Acceptance Criteria:**
- Seven named Holding variants, and the variant is chosen by **who owns the fix**, never by what went wrong: H1 whoever installs software · H2 nobody, retry · H3 nobody, retry · H4 the person, and it is a decision · H5 nobody, wait · H6 the organization · H7 the person, and it is a real fix they can complete here.
- **H4 is forbidden from being orange** and forbidden from the words *paused*, *stopped*, *couldn't*, *problem*, or *error*. It shows a card headed **What I left alone**, the caption **Nothing was changed, moved, or removed**, and a primary action reading **Keep what I have**.
- **H6 is the only variant whose primary is not a retry**, because retrying cannot change the outcome. The forward action is to leave, and the screen says so.
- **Frame-or-replace, per string.** A CLI string written for a person is framed verbatim under *What setup found:*; a string that names machinery goes only into a collapsed **Details for support** block. A raw machine sentence is never a headline and is never concatenated into an app sentence.
- The support block prints only lines it genuinely has. **Never print "unknown"; a missing line is honest.**
- Every variant has at least two exits, one of which works offline and with a broken helper. **Continue in the menu bar** appears on every variant and never marks setup complete.
- Focus moves to the title when a Holding screen appears, so a keyboard or VoiceOver user is never stranded on a control that has just disappeared.

*Serves job B4; MTM-3, the most frequent of the three anchor moments. The live-verified string that produced the H4 variant is "An existing GitHub SSH alias is user-managed; setup did not replace it."*

---

**US-B11 (P0) — SHIPPED.** As Bob, when setup says it is done, I want that to have been checked rather than assumed, so that I can stop checking.

**Acceptance Criteria:**
- The same health pipeline is re-run against the result. The person advances only when results are known, and a failed item can be retried on its own.
- Readiness requires the complete expected roster, a visible folder, a connection, a successful synchronization, **and** a post-apply verification. Any one missing means not ready.
- If the completion rule does not pass, the screen **refuses to congratulate**: it renders the honest-incomplete pattern and the finish action is not reachable from it. There is no hedged middle wording.
- No confetti, no celebration. A "Ready now" card lists what was verified; a "Still to do" card appears only when something genuinely remains.

*Serves job B5. Installers normally declare success by having finished; this one declares it by having checked.*

---

### The real product: the quiet

**US-B12 (P0) — SHIPPED.** As Bob, when nothing is wrong, I want the app to say nothing at all, so that I can forget it exists.

**Acceptance Criteria:**
- Healthy draws **no badge at all**. Silence is the success state; there is no green fill, no checkmark, no toast, no celebration.
- Status is re-derived by re-running the real pipeline on a 300-second timer plus on launch and on every popover open. It is never remembered from the last good answer.
- The status vocabulary is twelve closed tokens, **shape first and colour second**, so the state survives a monochrome or colour-blind render. The menu-bar badge does not animate at all, so every state is legible frozen.
- Honest non-answers are first-class tokens rather than fallbacks: *waiting for the network*, *offline*, and *could not check*.
- A response the app cannot read — unparseable, outside the accepted version range, or missing a security-relevant field — becomes one explicit red state with the sentence "I can't read the setup right now, so I won't guess." **It never becomes an optimistic one.**
- There is no "mark this healthy anyway" override anywhere in the product.

*Serves job B6; MTM-2. This is the job Bob would miss most if the product vanished — not the setup, the silence. A single false green ends the relationship permanently and makes every subsequent true green worthless.*

---

**US-B13 (P0) — SHIPPED.** As Bob, when something is wrong, I want one sentence naming the specific thing and the one action that is mine, so that I can act or hand it on without diagnosing anything.

**Acceptance Criteria:**
- The status sentence names the failing component and layer — "Codex needs sign-in; Claude is fine" — never a blended "something needs your attention."
- At most **one prompt** renders at a time; notices may stack. The prompt lane checks the unsaved-changes hold first, then the permission prompt, and never renders both.
- Each prompt is about the person's **own material** and offers exactly one action: `Review your changes` · `Grant this on GitHub` · `Add the connection` · `Choose folder…`.
- The person is never asked to approve a held update, unblock a gated one, or judge anything they have no basis to judge. Proximity to the menu bar is not competence.
- A secondary read that fails degrades quietly, never blocks the primary verdict, and never claims a pending offer it could not confirm.
- Work a person *could* do but does not have to never raises an alarm: the projects notice carries no menu-bar badge and reads "N projects can have your copilots. Nothing is added until you say so."

*Serves job B7. Every alert a person cannot act on burns down the credibility of the one that matters.*

---

**US-B14 (P1) — SHIPPED.** As Bob, when something has changed on my machine without my doing anything, I want a plain list of what actually changed, so that an unasked-for gift does not read as an unexplained event.

**Acceptance Criteria:**
- `What changed` opens a **Recently** list grouped into "Projects set up for you" and "Projects brought up to date."
- The empty state is explicit and unapologetic: **"Nothing has changed since you last looked."** "Nothing changed" has to be a claim the app can back here too.
- The entry point appears only when there is something to show.
- Changes arrive **pull-only and downward by construction**: the scheduled path holds no upward push credential to any shared remote, so a silent bidirectional sync is impossible rather than discouraged.

*Serves job B8; MTM-6.*

---

**US-B15 (P1) — SHIPPED.** As Bob, when I stop partway through, I want to be able to leave and pick it up later from the menu bar, so that abandoning a screen is never the same as losing my progress.

**Acceptance Criteria:**
- **Continue in the menu bar** exists on every Holding variant and **deliberately does not mark setup complete** — the tray carries the state.
- Settings' header offers **Finish Copilot Setup**, which reopens the setup window after a fresh check. It does not replay Welcome and it does not reset anything.
- The projects card offers **Open project aftercare…** and one row per category, each reopening the setup window directly on that category.
- Opening Settings is a read. Nothing is created, downloaded, or changed by opening it.

*Serves the design position that a dead end for a non-technical person is the end of the product, not the end of the session.*

---

**US-B16 (P1) — SHIPPED.** As Bob, when the app needs a permission only I can grant, I want to be asked for that one narrow thing at the moment it is needed, so that I am never handed an over-broad consent screen at the point I know least.

**Acceptance Criteria:**
- The permission is requested separately from sign-in, later, in its own screen, as **Grant this on GitHub** rather than as an authentication failure.
- Exactly one scope is requested: `write:public_key`.
- The upgrade requires an existing sign-in and commits the replacement only after the returned identity matches and the scope is confirmed. The two legitimate failures — wrong identity, insufficient grant — are explicit terminal states with their own copy, not a generic error.
- The menu-bar prompt **re-navigates** to the screen that already knows how to handle this rather than reimplementing the flow, so it inherits that screen's honest degradation for free.
- If the mechanism is unavailable on this helper, the screen falls back to a manual sheet rather than dead-ending.

*Serves MTM-5.*

---

**US-B17 (P1) — SHIPPED.** As Bob, when I want one of my own projects to use my copilots, I want the safe part done for me and the part that needs judgment routed to whoever owns that project, so that "the owner will review" is a route rather than a dead end.

**Acceptance Criteria:**
- The three-row panel **Will add / Will preserve / Will not change** precedes every project write.
- A brand-new project in a watched folder, where nothing of the person's is at risk, is set up silently on the check that already runs. One lifetime notice fires afterwards, once ever; the fact still appears as a past-tense line in `What changed` every time.
- **Can finish automatically** shows the preservation panel and a **Finish safely** button. Nothing is written until it is pressed.
- **Needs guided setup** shows what will be added, preserved, and left alone, the full CLI-generated prompt behind a disclosure, and **Run in Codex** / **Run in Claude Code** / **Copy prompt**. Running one opens a real, visible Terminal session, with **Bring Terminal forward** available while it is out there.
- On return the app **re-inspects both assistants itself and does not trust the external assistant's report**.
- **Needs the project owner** offers a prepared handoff to copy or share and changes nothing: "Control Tower will not change this project without that decision."
- **Couldn't confirm** shows exactly what could not be proven, offers a read-only diagnostic session, a copyable report, and **Check again**.
- Undo is offered for exactly as long as the CLI can still prove that what was added is untouched. When it cannot, **there is no control at all — never a disabled one with no explanation** — and the row's caption carries the reason.
- Each assistant is resolved to an absolute executable before launching, because Finder and Terminal do not share a `PATH`.

*Serves jobs B10, B11; MTM-9. "Owner will review" without a prepared route, prompt, or verification step is not a completion state.*

---

### Recovery and durability

**US-B18 (P1) — PARTIAL.** As Bob, when a new version breaks something, I want a way back that does not require me to understand what broke, so that I can recover with my dignity intact.

**Acceptance Criteria:**
- Rollback is reinstalling the prior signed DMG. Release tags are immutable; a defective build is superseded by a new version, never moved.
- Every retained release directory holds the signed DMG, its checksum, the compatibility pin, the helper's notarization record, and release metadata — so the artifact to roll back to still exists.
- **Every release note names the prior signed DMG explicitly**, and states whether a helper downgrade is required.

**Why PARTIAL:** the rule holds for 0.2.1 through 0.3.2, and **v0.4.0's changelog entry has no Rollback paragraph at all**. The artifact exists and rollback works, but the instruction a non-technical person is meant to follow is missing from the very release this document describes. There is also no in-app updater, by ratified decision, so a person must locate and reinstall the DMG themselves. <!-- TODO: confirm whether the missing v0.4.0 Rollback paragraph is an oversight to correct in CHANGELOG.md, or whether the standing rule now lives only in each release directory's metadata. This is a documentation-only pass and it was not corrected here. -->

*Serves job B9; Anxiety #1 in the forces map.*

---

**US-B19 (P2) — NOT SHIPPED.** As Bob, when the app itself dies unexpectedly, I want it to come back on its own, so that my menu bar does not silently stop telling me the truth.

**Acceptance Criteria (as designed, not as built):**
- A crash-only watchdog: restart after an unclean exit, **never** after a clean quit. Restarting after a clean quit is disrespectful; always-restarting a crashing build is a crash loop.

**Why NOT SHIPPED:** this is open gap **G-2**. The invariant describes it, the packaging assets and a plist test exist, and the machinery lives entirely in the retired Rust tree. The shipping Swift app neither installs nor manages the LaunchAgent. The mitigation is the product's founding property: if the face dies, the pipeline is still correct — the person loses their window, not their environment. Related and equally real: the 300-second poll is the only heartbeat and **nothing monitors it**, so a silently stopped poll freezes the glyph on its last honest state and looks exactly like success.

---

## Earl — the organization owner and admin operator

> Every story in this section is a demonstrated capability and an untested behavioural bet at the same time. Admin mode has stood a real sixteen-layer organization up end to end — run by the person who wrote it, on his own organization. **No third-party operator has ever touched it.**

**US-E01 (P0) — SHIPPED.** As Earl, when I am about to create repositories and access grants other people will depend on, I want to read exactly what will be created before anything is, so that I can authorize a change I can defend to whoever asks me about it later.

**Acceptance Criteria:**
- The Review setup surface enumerates the exact repository and team names that will exist, by name and by destination, and states what will be reused, created, downloaded, initialized, connected, synchronized, and verified.
- Nothing irreversible has happened when this screen renders.
- Each surface teaches before it collects; the register is orientation-before-input throughout.
- The Integrations surface honestly ends at "nothing to configure here today" rather than inventing a configuration step — integrations are built later, in department repositories, by an engineer assigned to that department.

*Serves job E1; MTM-7.*

---

**US-E02 (P0) — SHIPPED.** As Earl, when the standup runs, I want it to check before it acts at every step, so that I can re-run it after an interruption without creating anything twice.

**Acceptance Criteria:**
- A deterministic engine — not the app, not a model — makes every existence and idempotency decision, and every mutation is check-then-act: GET before POST, PATCH, or PUT.
- Nothing is forced, skipped past, or overwritten.
- The content-bearing work branch is fixed and deterministic: never timestamped, never force-pushed, reused and fast-forwarded across re-runs.
- Foundation version floors are pinned per product as fully-specified ranges, so a major version of one product can never be mistaken for a version of another.
- `gh` and `jq` are vendored into the bundle, so the operator's machine needs neither.

*Serves job E2.*

---

**US-E03 (P0) — SHIPPED.** As Earl, when the run stops, I want it to stop cleanly and tell me exactly what exists, so that I can pick up from a known state instead of auditing GitHub by hand.

**Acceptance Criteria:**
- The run is a named list of real things filling in place, in the same order and with the same names the review screen just showed. The operator is watching the list they approved.
- A count exists only while the run is alive. A bar appears only above seven rows and only as the visual twin of that count. **No percentage anywhere.**
- The denominator comes from the approved plan and grows only if the engine reports something the plan did not.
- If the run goes silent it says **No answer yet**, **stops animating entirely**, and offers `Keep waiting` and `See what's really on GitHub` — because a dead operation must never look like a slow one, and the truth path is a read-only check rather than a guess.

*Serves job E3.*

---

**US-E04 (P0) — SHIPPED.** As Earl, when I am about to hand the organization to its people, I want a read-only check that reports what is genuinely on GitHub, so that I find blockers before my colleagues do.

**Acceptance Criteria:**
- Setup check reads GitHub and reports what is really there. It changes nothing.
- The report — not the operator's recollection — is what gets handed over.
- Surfaces with no real seam yet render their honest degraded state and are marked as such, rather than filled with plausible fake data.

*Serves job E4; MTM-7. This is Earl's equivalent of Bob's Verify, and it is the surface his credibility rests on.*

---

**US-E05 (P1) — SHIPPED.** As Earl, when a new department forms, I want to add it without hand-editing configuration, so that I grant access by structure rather than by favour.

**Acceptance Criteria:**
- Adding a department is a governance surface, not a configuration-file edit.
- The department becomes reachable through the same entitlement spine as everything else: repository and team access, and nothing else. There is no separate permissions system, no license server, and no enrolment.
- A person who becomes entitled sees the department appear in `AVAILABLE TO JOIN` on their next check, with no ticket and no approval step.

*Serves job E5, and completes US-B06 from the other side.*

---

**US-E06 (P1) — PARTIAL.** As Earl, when someone leaves, I want a defined offboarding path, so that I revoke their reach without hunting through systems.

**Acceptance Criteria:**
- A governance surface walks the path: remove the person's GitHub team membership, and rotate the shared-store tokens their teams could read.
- Entitlement is repository access, so removing access removes reach on every future sync.

**Why PARTIAL:** the honest accepted residual is that **content already on a departed person's disk is not remotely wiped**. There is no device-management path and no deprovision surface in the shipping app — MDM was dropped completely as a mechanism, and the deprovision machinery exists only in the retired Rust tree with no Swift caller. This is acceptable for the target of small, trusted organizations, and it is stated rather than hidden.

*Serves job E6.*

---

**US-E07 (P1) — SHIPPED.** As Earl, when the organization has shared credentials to connect, I want to point at a store rather than distribute values, so that I am never the person who emailed a secret.

**Acceptance Criteria:**
- The store is connected by **endpoint**, delivered through inherited organization configuration. The endpoint is not a secret; access stays gated by each person's own GitHub team membership.
- **Secrets never enter inheritance content or any git repository, at any tier, public or private.** Inheritance content carries a reference to a secret's *name* only.
- Git push credentials are always per-user and on-device, and are explicitly excluded from the shared store.
- The store is **optional and deferrable**: an unreachable or unconfigured store renders as a deferred, non-blocking stage, and every dependent row honestly reads as having no store.
- The stage checks against the store's real identity surface, not a placeholder.

*Serves job E7. This story carries a scar: a phantom provisioner could report a store as configured when it was not — a false-positive readiness claim, which is precisely the class the product's whole honesty discipline exists to prevent, occurring backstage rather than in the icon. Closed in `cc 2.2.0`, shipped in v0.4.0.*

---

**US-E08 (P0) — PARTIAL.** As Earl, when my security team asks what this thing does on our machines, I want an answer that survives them reading the source, so that I get a yes instead of an exception request.

**Acceptance Criteria:**
- Pure open source, free forever. No paid tier, no hosted service, **no closed component**. Openness is the security guarantee, not a pricing decision.
- One signed binary. No daemon, no separate agent, no in-app fallback loop.
- **Zero bypass flags.** No `--force`, no `--skip-verify`, no lower-bar mode anywhere.
- Security-sensitive configuration comes only from compiled-in trust roots and signed, inherited organization or foundation configuration. Nothing security-critical is readable from user-editable local preferences.
- The helper is SHA-256 pinned, independently notarized, verified as not re-signed by the release gate, and preferred over any machine-installed copy.
- The contract gate is per-verb, exact-major, and fail-closed. A missing security-relevant field reads as unsafe, never as safe.
- Userland only: no admin rights, no privileged helper, no writable shared state.
- Nothing is collected. There is no telemetry emitter in the shipping app, so there is no collection surface to argue about.

**Why PARTIAL:** the posture ships; **the automatic enforcement of the posture does not.** This is open gap **G-1**. All forty architectural fitness tests scan the retired Rust tree and cannot see a single line of the shipping Swift, and the CI job that runs them is disabled behind a repository variable. Several native-side properties genuinely *are* enforced — never a bare CLI name, the fail-closed schema gate, the selftest that refuses a non-mock helper — but by code review and shell release gates, not by the named fitness functions. A reviewer asking "what stops a future change from violating this?" gets an honest answer of *review*, not *a test*. Porting the suite to scan `native/*.swift` and re-enabling the job is an open item that this documentation pass does not close.

*Serves job E8, which gates every other job in Earl's table: no standup happens if the review ends in a no.*

---

## Pablo — the author who publishes upstream

**US-A01 (P0) — SHIPPED.** As the author, when I make a change once to shared content, I want it to land on every entitled machine on cadence, so that I stop being the sync layer and stop wondering whether it landed.

**Acceptance Criteria:**
- An authorized upstream change appears on every entitled machine on the poll cadence, without anyone running a command.
- The cheap poll target is a single lock-SHA comparison, not a full update.
- Nobody's personal work is disturbed by the arrival.
- On the receiving side there is either nothing to see, or a plain list of what arrived (US-B14).

*Serves job A1; MTM-6, the origin job of the entire product. Demonstrated at one organization, single-machine. The multi-writer and second-machine cases are not demonstrated.*

---

**US-A02 (P0) — SHIPPED.** As the author, when that change propagates, I want it to be structurally impossible for it to clobber anyone's personal work, so that I can publish without rehearsing the blast radius every time.

**Acceptance Criteria:**
- Three trees, three protections, never conflated: a read-only mirror is disposable and may be reset or recloned freely; a materialized tree is disposable and may be re-materialized freely; **a human's working tree — a dirty personal checkout, or an author's tier-scoped authoring checkout — is never touched.**
- A clean visible checkout may be reused or fast-forwarded; a dirty one is never touched, in any state.
- A guard refuses to write or delete through **any symlink that escapes the materialize root**.
- Never-destroy compensation **reports, never deletes**. Before any migrate or repair, the original manifest bytes are written to a content-addressed local rollback directory.
- Sync is pull-only and downward. The scheduled path holds no upward push credential to any shared remote.

*Serves job A2. This story is the direct cost of an incident: one routine update reconcile-deleted **12,537 lines** of organization content in a single commit through a symlink, which a backup job then pushed to origin. The guard that now prevents it is also the source of the four legitimately held items in the live run — which is exactly what a safety mechanism looks like from the inside.*

---

**US-A03 (P1) — PARTIAL.** As the author, when I write in my own editor and save, I want publishing to be markdown-and-save rather than a Git ceremony, so that I can author at the speed of thinking.

**Acceptance Criteria:**
- Authoring is editing markdown in the author's own editor, committing, and pushing to the tier repository. Every consuming machine picks it up on its next pull.
- No app surface is required, and none exists.

**Why PARTIAL:** there is **no product surface for this lane at all** — it is a documented manual procedure, and the verb that would make it a product path is formally deferred (ADR-008). More consequentially, **the multi-writer loop has never been run with more than one writer**, so the collaborative half of this story is a model in the author's head rather than an observed behaviour.

*Serves job A3.*

---

**US-A04 (P1) — PARTIAL.** As the author, when something I built inside one project turns out to be useful to everyone, I want a safe route to raise it to a shared tier, so that I can grow the shared layer without improvising.

**Acceptance Criteria (the interim route, as documented):**
- Elevation is always **copy → commit → push** into the tier repository's own working directory.
- **Symlinking is explicitly forbidden**, and a materialize target is never pointed at an authoring checkout. This procedure is safe independently of the guard's state.

**Why PARTIAL:** the `publish` verb is formally deferred per ADR-008. Its full design — auto-merge non-overlapping edits, then a plain-language keep-yours / keep-theirs / keep-both chooser, then park-and-escalate, with **all merge computation CLI-side and the app rendering only the choice** — is preserved as a design record, and nothing schedules building it. Its schema file still exists on disk. No document in this repository may list it as an existing verb.

*Serves job A4.*

---

**US-A05 (P0) — SHIPPED.** As the author cutting a release, I want the gates to catch what I would have missed, so that I am not the last line of defence myself.

**Acceptance Criteria — the gates that run on every release, in order:**
- Build the app from an **explicit source list, never a glob**, so a file cannot silently join a build.
- Developer ID signing, then a check that the signed app carries its Apple Events entitlement **and** its user-facing purpose string — because source that merely contains an automation string is not sufficient.
- The embedded helper's checksum is compared against the one built, then verified against the pinned checksum **and** confirmed not re-signed. The app is never a second signing authority for the helper.
- **Headless Detect**: the exact three production calls, through the production client, under a Finder-shaped `PATH`, printing typed JSON and exiting before any UI exists.
- **Headless setup transaction**: the real wizard model driven from Set up through Verify against an inert fixture helper that records argv, so the proof requires the right commands to have been sent rather than merely a decodable response — plus a second, independent leg that drives the exact **packaged** helper against a deterministic local git fixture and asserts a sixteen-row topology across eight history states.
- Notarize the app, staple, assemble and sign the DMG, notarize and staple the DMG, then validate the staple on both, `codesign --verify --strict --deep`, and two Gatekeeper assessments.
- A retained release directory with the signed artifacts, checksums, the compatibility pin, the helper's notarization record, and release metadata.

*Serves job A5. The testing shape these gates encode was learned from an incident: test the state engine directly, test the app's typed seam headlessly, then run the same headless command against the final packaged artifact. Opening the UI is a visual-product check, not the primary integration test.*

---

**US-A06 (P0) — PARTIAL.** As the author, when a release turns out to be defective, I want a rollback anyone can follow, so that I fix it without a support conversation per person.

**Acceptance Criteria:**
- Release tags are immutable. A defective build is superseded by a new version, never moved or replaced.
- The prior signed DMG is retained and its checksum is published alongside it.
- The release note names the prior signed DMG explicitly, and states whether a helper downgrade is required.

**Why PARTIAL:** identical to US-B18 from the author's side — **v0.4.0's changelog entry carries no Rollback paragraph**, breaking a rule every release since 0.2.1 has kept. The artifact and the checksum exist; the instruction does not.

*Serves job A6.*

---

**US-A07 (P1) — NOT SHIPPED.** As the author, when I pick up my second machine, I want it to already be at parity, so that I stop re-updating everything just to get back to where I was.

**Acceptance Criteria, as required for the claim to be true:**
- A second machine starting with an **empty keychain** onboards, clones both mirrors, and resolves every service with **no hand-copied secret and no `.env` file**.

**Why NOT SHIPPED:** this is the **V-5 cold-laptop proof**, and it has not been run. Until it passes, "a new machine can join unaided" is a design intent rather than a demonstrated fact. Underneath it sits the genuinely unsolved problem — personal-key sync across one person's own machines, the origin pain in its last unfixed form. Solving it needs a carrier that reconciles with the per-user on-device key model without becoming a shared-credential store, and the V-5 proof is the first evidence that will inform it.

*Serves job A7.*

---

**US-A08 (P1) — NOT SHIPPED.** As the author, when I change the shipping app, I want the invariants enforced by something other than my own attention, so that the safety claim survives a future change I do not review carefully enough.

**Acceptance Criteria, as required:**
- The architectural fitness suite scans `native/*.swift` — the code that actually ships — rather than a retired implementation.
- The job that runs it is enabled and gates a release.

**Why NOT SHIPPED:** open gap **G-1**, stated in full under US-E08. All forty fitness tests scan the retired Rust tree; the shipping app is roughly 22,650 lines of Swift they cannot see. The release pipeline never invokes `cargo`; the workflow that does is disabled behind a repository variable. The six invariants are architectural commitments upheld by review and by the shell release gates, **not** automatically-enforced properties of the shipping binary. The owner's ratified position of 2026-08-02 is to document this honestly rather than fix it in this pass or quietly reframe it away.

---

## Story Priority Matrix

| ID | Story | Persona | Priority | Status | Depends On |
|----|-------|---------|----------|--------|------------|
| US-B01 | Installs and opens like any Mac app | Bob | P0 | SHIPPED | — |
| US-B02 | One plain question when nothing knows the organization | Bob | P0 | SHIPPED | US-B01 |
| US-B03 | Browser sign-in; the app holds no credential | Bob | P0 | SHIPPED | US-B01 |
| US-B04 | See what is already on this Mac before anything changes | Bob | P0 | SHIPPED | US-B03 |
| US-B05 | See what you are getting, in plain names | Bob | P0 | SHIPPED | US-B04 |
| US-B06 | Join a department you are already entitled to | Bob | P1 | SHIPPED | US-B03, US-E05 |
| US-B07 | See the organization's connections and what is missing | Bob | P0 | SHIPPED | US-B03, US-E07 |
| US-B08 | Choose which of your own projects to include | Bob | P1 | SHIPPED | US-B04 |
| US-B09 | One setup that never half-happens, and says so truthfully | Bob | P0 | SHIPPED | US-B04, US-B05 |
| US-B10 | A stop you can interpret in two seconds | Bob | P0 | SHIPPED | US-B09 |
| US-B11 | Completion verified, not assumed | Bob | P0 | SHIPPED | US-B09 |
| US-B12 | Silence when nothing is wrong | Bob | P0 | SHIPPED | US-B11 |
| US-B13 | One sentence naming what and who | Bob | P0 | SHIPPED | US-B12 |
| US-B14 | A plain list of what changed, with an honest empty state | Bob | P1 | SHIPPED | US-B12, US-A01 |
| US-B15 | Leave unfinished, pick it up from the menu bar | Bob | P1 | SHIPPED | US-B09 |
| US-B16 | Grant one narrow permission, at the point of use | Bob | P1 | SHIPPED | US-B03 |
| US-B17 | Project aftercare routed by who can decide | Bob | P1 | SHIPPED | US-B08, US-B11 |
| US-B18 | A way back to the previous version | Bob | P1 | **PARTIAL** | US-A06 |
| US-B19 | The tray comes back if it dies | Bob | P2 | **NOT SHIPPED** | — |
| US-E01 | See exactly what will be created, before it is | Earl | P0 | SHIPPED | — |
| US-E02 | Check before acting, at every step | Earl | P0 | SHIPPED | US-E01 |
| US-E03 | Stop cleanly and say what exists | Earl | P0 | SHIPPED | US-E02 |
| US-E04 | A read-only check before handover | Earl | P0 | SHIPPED | US-E03 |
| US-E05 | Add a department without editing configuration | Earl | P1 | SHIPPED | US-E04 |
| US-E06 | A defined path when someone leaves | Earl | P1 | **PARTIAL** | US-E04 |
| US-E07 | Point at a store, never distribute values | Earl | P1 | SHIPPED | US-E01 |
| US-E08 | Survives a security review | Earl | P0 | **PARTIAL** | — |
| US-A01 | A change made once lands everywhere entitled | Author | P0 | SHIPPED | US-B09 |
| US-A02 | Propagation can never clobber personal work | Author | P0 | SHIPPED | — |
| US-A03 | Author in markdown, not in a Git ceremony | Author | P1 | **PARTIAL** | US-A01 |
| US-A04 | A safe route to raise something to a shared tier | Author | P1 | **PARTIAL** | US-A02 |
| US-A05 | Release gates catch what the author would miss | Author | P0 | SHIPPED | — |
| US-A06 | A rollback anyone can follow | Author | P0 | **PARTIAL** | US-A05 |
| US-A07 | A second machine already at parity | Author | P1 | **NOT SHIPPED** | US-B09 |
| US-A08 | Invariants enforced on the shipping binary | Author | P1 | **NOT SHIPPED** | US-A05 |

## Story Summary

| User Type | P0 | P1 | P2 | Total | SHIPPED | PARTIAL | NOT SHIPPED |
|-----------|----|----|----|-------|---------|---------|-------------|
| Bob — non-technical adopter (primary) | 11 | 7 | 1 | **19** | 17 | 1 | 1 |
| Earl — organization owner / admin | 5 | 3 | 0 | **8** | 6 | 2 | 0 |
| Pablo — author / trust basis | 4 | 4 | 0 | **8** | 3 | 3 | 2 |
| **Total** | **20** | **14** | **1** | **35** | **26** | **6** | **3** |

**Read the two right-hand columns together.** Bob's lane is almost entirely shipped, which is correct — he is the reason the product exists. The author's lane is where the unfinished work concentrates: three PARTIAL and two NOT SHIPPED out of eight, and every one of them is about the *writable* direction — publishing upward, elevating content, a second machine, and enforcing the rules on the shipping binary. That is a fair picture of the product today. **The consuming half is built and proven once; the authoring half is one person's working practice with a documented manual procedure standing in for a product path.**

## Critical View Coverage

The views a design challenge would have to demonstrate, and the stories that cover each. All seven exist in the shipping app.

| Critical view | Covered by | Why it is critical |
|---|---|---|
| **The menu-bar glyph and its twelve badges** | US-B12, US-B13 | The only touchpoint that operates when nothing is happening, and the product's core claim is about what happens when nothing is happening. It is also the only touchpoint that can destroy the relationship in a single frame |
| **The Holding screen, and H4 in particular** | US-B10 | The most emotionally decisive surface in the product. The most common real outcome of a first setup is a screen full of holds, and this is where a person decides whether the tool is careful or broken |
| **The Set up progress list and its ledger-backed account** | US-B09, US-B11 | The only irreversible touchpoint, and the only place a person's own accounts change |
| **The roster reveal — What you're getting / Departments / Your connections / Your projects** | US-B05, US-B06, US-B07, US-B08 | The only touchpoint that generates pull rather than managing anxiety |
| **The popover: four named regions and one prompt lane** | US-B13, US-B14, US-B06 | The day-to-day home, and where the one-prompt-at-a-time rule is enforced |
| **The project drill-in and its handoffs** | US-B17 | The second reason to open the app, and the difference between a dead end and a door |
| **Admin: Review setup and Setup check** | US-E01, US-E04 | Earl's whole credibility, in two screens |

**Deliberately uncovered, and why.** There is no story for the **Analytics** governance surface: telemetry is a ratified non-goal, nothing is collected, and the surface has a toggle with no emitter behind it. It is a frontstage element with no backstage, recorded as an open item rather than dressed up as a feature. There is likewise no story for a fleet dashboard, a device-management profile, a deprovision screen, a resolve view, a chat surface, or an in-app updater — all are ratified non-goals or retired machinery with no Swift caller. Writing stories for them is exactly the failure mode this rebuild exists to correct.

---

**Related:** [JTBD](../02-service-design/30-jtbd.md) | [Journey Maps](../02-service-design/20-journey-maps.md) | [Moments That Matter](../02-service-design/40-moments-that-matter.md) | [Service Blueprint](../02-service-design/10-service-blueprint.md) | [Use Cases & Scenarios](20-use-cases-and-scenarios.md) | [Acceptance Criteria](30-acceptance-criteria.md) | [UX Design](../04-experience-design/50-ux-design.md) | [CLI Contract](../../01-architecture/cli-contract.md)
