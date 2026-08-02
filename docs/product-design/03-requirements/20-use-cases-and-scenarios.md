# Use Cases & Scenarios

<!--
FACILITATION GUIDE — Service Designer + UX Designer
=====================================================
Use cases are end-to-end scenarios that test the full system.
They are more detailed than user stories and describe the complete
interaction from trigger to outcome.

PREREQUISITE: User stories must be completed.

CONVERSATION FLOW:
1. Define end-to-end scenarios for each major workflow
2. Define edge cases and error scenarios
3. Define critical view (CV) scenarios for the design challenge

QUESTIONS TO ASK:

## Round 1: Core E2E Scenarios
Walk through each major workflow end-to-end:
- "Walk me through the complete happy path for [workflow]."
- "What triggers this scenario?"
- "What does the user do at each step?"
- "What does the system do at each step?"
- "What's the expected outcome?"

## Round 2: Edge Cases & Error Scenarios
- "What happens when things go wrong?"
- "What happens with bad input or incomplete data?"
- "What happens under time pressure?"
- "What happens when multiple users are involved?"
- "What happens when the system is slow or unavailable?"

## Round 3: Critical View Scenarios
- "For the design challenge, which views need to be designed or prototyped?"
- "What's the most important screen?"
- "What scenarios should each critical view demonstrate?"

SYNTHESIS:
Present as detailed narratives with clear triggers, steps,
and expected outcomes. E2E scenarios should be testable.
CV scenarios feed directly into the design challenge brief.
-->

> **Status — rebuilt from evidence 2026-08-02. Describes Copilot Control Tower v0.4.0** (build 19, source commit `453d15f`, embedded helper `cc 2.2.0`). This replaces a version whose scenarios were written against an MDM-pushed, Tauri-cored product that never shipped.
>
> **The error scenarios in this document are not hypotheticals.** Every one of the first seven actually happened to this product, to a real person, on real accounts, and each has a citation and a remediation version. This is a defect record, not a risk register — which is exactly what makes it the right list to design and test against. Where a scenario is still open, it says OPEN and does not soften it.
>
> **The architectural rule every scenario respects: Control Tower parses, it never computes.** In every scenario below, the CLI decides and the app renders. If a step reads as the app deciding something, the step is wrong.

## How to read the evidence stamps

| Stamp | Meaning |
|---|---|
| **PROVEN** | Exercised in a real run against real accounts, with recorded evidence in this repository |
| **SHIPPED** | Implemented in the v0.4.0 binary or its release pipeline; observable by running it |
| **HYPOTHESIS** | Designed and shipped, but never validated with the actor it is for |
| **OPEN** | A currently-unresolved gap. Stated, not smoothed over |
| **REMEDIATED** | An incident that happened and whose fix has shipped in a named version |

---

## End-to-End Scenarios

### UC-1 — The ENAC live run: sixteen layers onto a real organization · **PROVEN**

**The one scenario that matters most, because it is the only one that has actually happened end to end.** It is presented first, and honestly: it took three attempts, and the two failures were more instructive than the success.

**Trigger.** The owner runs the setup transaction against the real ENAC organization — publisher and first consumer at once, deliberately, because it is the hardest case and a throwaway rehearsal would have tested an easier problem.

**Steps and system behaviour:**

1. **The read-only plan pass.** The CLI classifies every repository's git history and returns a sixteen-row topology — four components across four tiers — with a per-row action drawn from a closed set: reuse, create, migrate, repair, review. **Nine of the sixteen rows classify as `review`.** Six of the seven already-present repositories land there, and three of those purely because of *untracked* framework-materialization litter — not one modified tracked file among them. Nothing is written.
2. **First apply — blocked, and it rolled back its own correct work.** A complete and correct sixteen-layer manifest write was undone because the transaction treated *any* non-zero materialize exit as fatal, including `held`. Four items were held because the symlink guard was correctly refusing to write through a symlink escaping the materialize root; forty-eight were blocked because the fail-closed policy default blocks any executable item with no signature verifier wired in yet. **Neither is a defect.** Worse, the rollback-confirmation step re-ran the same failing gates against the restored manifest, could not prove its own success, and self-reported `rollback-failed` over a file that was byte-identical to its baseline — a false negative about the system's own safety.
3. **Second apply — blocked again, for an unrelated reason.** After the first fix, the post-materialize health check rolled back on anything short of healthy. A brand-new layer legitimately cannot have a positive freshness pointer or a local mirror on its very first appearance. **Nine checkers reported `warn`; zero reported `fail`;** the aggregate label read offline; the manifest write was undone again.
4. **Third apply — success, and still honest about the awkward parts.** Sixteen of sixteen layers. Three previously-orphaned personal repositories **adopted, not recreated**, with their creation timestamps byte-identical before and after. Zero destructive git operations across all three attempts. A manifest written by a real apply rather than by hand. The report still carried four items held by the protection guard and one blocked, rather than rounding to success.

**Outcome.** The ecosystem is live at 16/16 on one organization. Both blocking defects were fixed by **narrowing the gate rather than weakening it**: rollback now triggers only on a genuine environment failure; rollback confirmation is a direct byte comparison of the file; the health gate counts `fail`-severity checkers directly rather than reading an aggregate label; and cold-start mirrors are seeded before the check.

**The transferable lesson, and the reason this scenario leads the document:** *a fail-closed system that cannot distinguish "honestly imperfect" from "broken" will destroy its own correct work, and will do it deterministically.* Both defects were found only by a live run against real accounts, and both were root-caused by reading the diff rather than trusting the fix message. Neither was ever forced past.

**Serves:** US-B09, US-B10, US-B11, US-A02, US-A05.

---

### UC-2 — Bob's first run, the designed path · **SHIPPED / HYPOTHESIS as an experience**

**Trigger.** Someone at work sends Bob a link to the organization's own download page.

| Step | What Bob does | What the system does |
|---|---|---|
| 1 | Downloads and drags the app across | A signed, notarized, stapled arm64 DMG. Gatekeeper accepts it without a blocking dialog |
| 2 | Opens it | An aviator glyph appears in the menu bar. The setup window opens by itself. **Nothing else happens** — no Dock icon, no dialog |
| 3 | Reads Welcome (Step 1 of 9) | "You don't need to be technical for any of this." Three copilots named with one benefit sentence each; two things to have handy. Leading action is Quit; primary is Get Started |
| 4 | Connects GitHub (Step 2 of 9) | A browser device flow: a short code, an Open GitHub button, a second route back for a lost window. **No field in the app's model can hold a token.** On success the card collapses to "Signed in as *you*" |
| 4a | *(Only if nothing on this Mac knows)* names the organization | An inline question in accent blue, one field, a pasted address rewritten in place. Never a numbered step, never a sidebar row, never orange |
| 5 | Waits through Detect (Step 3 of 9) | Three read-only calls in one seam: who you are, the health of what is here, and a full topology plan. **Nothing is changed.** The four copilots are named before results arrive. The visible repository folder is shown with Choose folder… |
| 5a | *(Only if the plan found something already his)* answers "One question first" | "Want me to include what you already have?" — cards separating what is already in GitHub from what is already on this Mac, one checkbox per item, and the guarantee "Nothing you already have is changed. Setup only adds what's missing" |
| 6 | Reads what he is getting (Step 4 of 9) | A confirmation, not a choice. One optional checkbox for Codex, framed as a personal preference |
| 7 | Joins any department he is entitled to (Step 5 of 9) | Only entitled departments appear. Per-row Join. Skip for now is always available |
| 8 | Reviews his connections (Step 6 of 9) | The organization's full declared roster — twenty services in ENAC's live configuration — grouped into Ready to use and Available to connect, each unready row naming the missing credential **names** and never a value |
| 9 | Reviews his projects (Step 7 of 9) | Five CLI-authored categories. Selection by checkbox. The primary names its consequence: "Set up 3 and continue" |
| 10 | Presses **Set up** (Step 8 of 9) | The preflighted saga. A named list of real outcomes filling in place, a count only while work is genuinely in flight, six row states with six distinct symbols and sentences. **No percentage, no countdown, no estimate** |
| 11 | Reads Verify (Step 9 of 9) | The same health pipeline re-run against the result. A "Ready now" card, a "Still to do" card only if something genuinely remains, and "What happens next": "Look for the aviators: a quiet icon means there is nothing you need to do." No confetti |
| 12 | Closes the window | The glyph carries no badge. **From here the product's entire behaviour is silence** |

**Outcome.** Sixteen layers live on a Mac whose owner has never opened a terminal, each one named on screen with the repository it came from and the folder it lives in.

**The honest caveat that governs this whole scenario:** it is shipped, gated, and exercised headlessly against both an inert fixture and the packaged helper — and **no independent non-technical person has ever walked it**. Every emotional claim in it is a well-evidenced design against an unvalidated model. <!-- TODO: confirm how many people at ENAC beyond the owner are running Control Tower today, and whether any of them completed first-run setup with no assistance. This remains the single highest-value unmeasured fact about the product. -->

**Serves:** US-B01 through US-B11.

---

### UC-3 — Earl stands an organization up · **PROVEN once, by the author**

**Trigger.** An organization decides to adopt the ecosystem. Earl opens the separately-built Admin app.

**Steps:**

1. **Orientation and Prerequisites.** He learns what he is committing to before committing, and finds his machine is already ready — `gh` and `jq` are vendored into the bundle, so he installs nothing.
2. **Contacts, Connect GitHub, Describe your organization.** He signs in as himself and describes the organization in plain fields rather than in configuration.
3. **Integrations.** The surface honestly ends at "nothing to configure here today." Integrations are built later, in department repositories, by an engineer assigned to that department.
4. **Secret store.** He points at a shared store by endpoint, or explicitly defers it. Deferring is a supported outcome, not a failure: every dependent row will honestly read as having no store until someone returns to the Connect-the-store governance surface.
5. **Review setup — the decisive surface.** The exact repository and team names that will exist, by name and destination, and what will be reused, created, downloaded, initialized, connected, synchronized, and verified. **Nothing irreversible has happened yet.**
6. **Organization setup.** A deterministic bash engine executes, deciding every existence and idempotency question by check-then-act — GET before every POST, PATCH, or PUT. He watches the same named rows he just approved fill in, with a count only while the run is alive and no percentage anywhere.
7. **Setup check.** A read-only read of GitHub reporting what is genuinely there. This report — not his recollection — is what he hands over.
8. **Done**, and later the five governance surfaces: add a department, someone left, connect the shared store, org setup, analytics.

**Outcome.** An organization exists on GitHub, idempotently, resumably, and with a read-only report Earl can defend.

**Honest limits:** the Analytics governance surface has a toggle and **no emitter behind it** — a frontstage element with no backstage, flagged rather than described as working. And no third-party operator has ever run any of this.

**Serves:** US-E01 through US-E05, US-E07.

---

### UC-4 — The everyday glance, and the change that arrives unasked · **SHIPPED**

**Trigger.** None. This scenario has no trigger, which is the entire point.

**Steps:**

1. Every 300 seconds — plus on launch and on every popover open, so an open popover is never stale — the app re-runs the real pipeline. It does not remember the last good answer.
2. If everything is fine, the glyph carries **no mark** and Bob does nothing. That is the whole flow, and it is the intended one.
3. Meanwhile, an author somewhere makes one change to shared content and pushes it to the tier repository. Nobody runs anything on Bob's machine.
4. On a later poll the change is simply there. Bob either notices nothing and benefits, or opens `What changed` and reads a plain Recently list grouped into "Projects set up for you" and "Projects brought up to date."
5. If nothing has changed, the empty state says so plainly: **"Nothing has changed since you last looked."**
6. For the rare urgent case, `Sync now` exists. The header swaps immediately to "Bringing everything up to date…" with the syncing mark. No percentage, no estimate. It is inert while offline or already syncing, and prints "Waiting for the network." underneath when offline.

**Outcome.** A change made once lands everywhere entitled to it, and the receiving person's experience of it is either nothing at all or one honest list.

**Structural guarantee:** sync is pull-only and downward **by construction** — the scheduled path holds no upward push credential to any shared remote, so the worst possible leak, a silent bidirectional sync, is impossible rather than discouraged.

**Serves:** US-B12, US-B14, US-A01.

---

### UC-5 — Joining a department from the menu bar · **SHIPPED**

**Trigger.** Earl adds Bob to a department team on GitHub. Nobody tells Bob.

**Steps:** on the next check the CLI reports a layer Bob is entitled to and has not joined → an `AVAILABLE TO JOIN` row appears in the popover, with **no badge and no alarm**, because an offer is not a fault → Bob clicks **Join** → the row shows a named waiting indicator and the button disappears while it runs → on success the row simply vanishes and a full refresh runs, so the copilot rows fill in with their new layer.

**Outcome.** **The tree filling in is the reward. There is no toast.**

**Every other outcome has its own sentence**, and only retryable ones get their button back: no longer available to you (no retry), waiting for the network (retry), could not join right now (retry). If nothing answers within twenty seconds the row stops presenting itself as progress and reads "Sales hasn't come through yet. Nothing was changed." — deliberately different wording from a reported failure, so a stall is never misread as an answer.

**Serves:** US-B06, US-E05.

---

### UC-6 — Coming back for a project · **SHIPPED**

**Trigger.** Weeks after setup, Bob opens a project of his own from the popover and wonders whether it can be part of this. The project has its own agents, its own rules, and years of somebody's thinking in it.

**Steps, by the CLI's classification — never the app's:**

- **Ready.** Nothing to do. Local customization is stated as a **visible positive fact**, not a blocker: "Ready. Claude and Codex are connected. This project also has its own pipeline, writing, and legal agents."
- **Can finish automatically.** The three-row **Will add / Will preserve / Will not change** panel, then **Finish safely**. Nothing is written until it is pressed.
- **Needs guided setup.** The CLI writes a plan naming what to preserve, what is prohibited, the bounded allowed actions, the verification command, and the stop conditions requiring an owner decision. The app shows it, offers the full prompt behind a disclosure, and **Run in Codex** / **Run in Claude Code** / **Copy prompt**. Running one opens a real, visible Terminal session, with **Bring Terminal forward** while it is out there. On return **the app re-inspects both assistants itself and does not trust the external assistant's report**.
- **Needs the project owner.** A prepared handoff to copy or share. Nothing changes: "Control Tower will not change this project without that decision."
- **Couldn't confirm.** Exactly what could not be proven, a read-only diagnostic session, a copyable report, and **Check again**.

**Outcome.** The safe part is done; the unsafe part is packaged for a named person. *"Owner will review" without a prepared route, prompt, or verification step is not a completion state.*

**Serves:** US-B08, US-B17.

---

### UC-7 — Cutting a release, and rolling one back · **SHIPPED, PROVEN across eight version lines**

**Trigger.** The author has work worth shipping.

**Steps:** build from an explicit source list, never a glob → Developer ID sign → verify the signed app carries its Apple Events entitlement **and** its purpose string → confirm the embedded helper's checksum is unchanged, matches the pin, and was not re-signed → run **headless Detect** through the exact production seam under a Finder-shaped `PATH` → run the **headless setup transaction**, driving the real wizard model from Set up through Verify against an inert fixture that records argv, plus an independent leg driving the exact **packaged** helper against a deterministic local git fixture to assert a sixteen-row topology across eight history states → notarize and staple the app → assemble, sign, notarize and staple the DMG → validate both staples, verify the signature strictly, and run two Gatekeeper assessments → write a retained release directory with artifacts, checksums, the compatibility pin, the helper's notarization record, and release metadata.

**Rollback:** reinstall the prior signed DMG named in the release note. Release tags are immutable; a defective build is superseded by a new version, never moved.

**The honest gap in this scenario:** **v0.4.0's changelog entry carries no Rollback paragraph**, which every release from 0.2.1 to 0.3.2 does. The artifact and checksum are retained, so rollback works — but the instruction the person is meant to follow is missing from this release.

**Serves:** US-A05, US-A06, US-B18.

---

## Edge Cases & Error Scenarios

*Ordered by demonstrated blast radius. The first seven happened. Nothing in this table is invented.*

### ES-1 — "It said nothing changed, and it had already created two repositories" · **REMEDIATED**

**Trigger.** Control Tower 0.2.4's first owner-run apply stopped on a repository whose history was not fast-forwardable.

**What happened.** The screen reported that setup had stopped **"before changing anything."** Two Personal GitHub repositories had already been created and seeded minutes earlier. The handoff document's own words: *"That statement is false for this run."*

**Why it is the sharpest failure in the record.** The one product whose entire promise is honesty told a person something untrue about their own accounts. What the person concludes is not "there is a bug" — it is *"this thing tells me what it wants me to hear,"* and there is no route back from that conclusion. On a second run the tool would see the repositories its own failed attempt created, treat them as pre-existing, and quietly erase the evidence that it made them.

**Expected behaviour now.** All deterministic checks — including git ancestry — run **before** the first irreversible write, so a blocked row produces zero mutations rather than a partial set. A run-scoped completed-actions ledger threads through every exit path including the failing ones, and the apply asserts that the result equals the target as a postcondition. **The words "nothing changed" are legal only against an empty ledger.** Held and blocked are distinct facts and render as distinct facts.

**Serves:** US-B09. **Anchors:** MTM-1, the highest-ranked moment in the product.

---

### ES-2 — "Claude Code rejected every prompt on my machine" · **REMEDIATED in 0.1.1–0.1.3**

**Trigger.** A shared layer manifest migrated a field from `component:` to `product:`. One consumer's resolver still filtered on the old name.

**What happened, in order.** The resolver found zero matching entries and — this is the actual defect — **treated "zero matches" as the ordinary foundation-only state** rather than as schema drift. It loaded the public foundation only. The organization's own `discord` command, which lives in the org overlay, vanished from the command tree. A user-level prompt hook then invoked a command that no longer existed and exited non-zero. Claude Code correctly treats a non-zero prompt hook as a prompt rejection. **An optional notification transport became a total harness outage: every prompt rejected, regardless of content, and nothing the person did caused it.**

**Expected behaviour now.** Three controls, all shipped and all load-bearing. **Optional transports fail open** — a hook shim returns success with a concise diagnostic when its optional command is absent or fails, and this is codified in the compatibility pin as a declared fail-open policy with a bounded internal timeout. **The contract gate is per-verb, exact-major, and fail-closed**, so drift surfaces as an honest unreadable state rather than a silently wrong result. And **the release gate tests the exact packaged artifacts** against legacy, canonical, matching-dual, and conflicting manifests, because the prior gates all passed while the shipped binary and its source disagreed on a user-visible field.

**The transferable lesson.** The blast radius of a shared-contract change is the union of every consumer, and **a consumer that cannot distinguish "legitimately empty" from "I no longer understand this format" will always fail silently in the most expensive direction.**

**Serves:** US-B12, US-B18, US-E08. **Anchors:** MTM-8.

---

### ES-3 — "One routine update deleted 12,537 lines of our organization's content" · **REMEDIATED**

**Trigger.** A materialize target pointed at a human-owned authoring checkout **through a symlink**.

**What happened.** A single reconciling sync deleted everything under the paths it owned there: five organization agent extensions including the brand-voice binding, sixteen agents, all commands, all memory, hooks and skills, ten of eleven top-level docs files, and the knowledge manifest — **12,537 deletions in one commit, which a backup job then pushed to origin.**

**Root cause, precisely.** Two-fold. The personal-tree guard protected a path only if it was a *registered* personal root or a *currently dirty* git tree — and a clean authoring checkout is neither. And the registered-roots list had no production feeder, so that branch never fired for a real authoring checkout at all.

**Expected behaviour now.** A guard **refuses to write or delete through any symlink that escapes the materialize root.** The documented elevation procedure is unambiguous: never elevate content by symlink, never point a materialize target at an authoring checkout, and always copy → commit → push into the tier repository's own working directory — which is safe independently of the guard's state.

**The instructive coda.** That same guard produced the four `held` items in UC-1, where it briefly read like an incomplete transaction. **This is what a safety mechanism looks like from the inside**, and mistaking one for a failure is how UC-1's first apply destroyed its own correct work.

**Serves:** US-A02, US-A04. **Anchors:** MTM-3, MTM-6.

---

### ES-4 — "It says Personal is ready and there is no folder anywhere on my disk" · **REMEDIATED in 0.2.4**

**Trigger.** Any machine through v0.2.3 where a layer existed as a GitHub repository or a hidden mirror but had no visible checkout.

**What happened.** A GitHub repository or a hidden mirror **counted as an installed layer**, so a person could see a green Personal result backed by nothing they could see. This is the canonical false green.

**Expected behaviour now.** Readiness requires all five: the complete expected roster, a visible folder, a connection, a successful synchronization, **and** a post-apply verification. **A hidden mirror is never evidence of presence.** Personal is never present only under the hidden mirror tree; every repository has a visible checkout under one visible root.

**Why it belongs near the top.** The false green makes the icon decorative, and from that moment every subsequent true green is worthless — including the honest ones. Bob is precisely the person who will notice.

**Serves:** US-B04, US-B11, US-B12. **Anchors:** MTM-2.

---

### ES-5 — "The app couldn't find the command that is definitely installed" · **REMEDIATED in 0.1.2, gate added in 0.1.3**

**Trigger.** Launching the app from Finder rather than from a terminal.

**What happened.** Control Tower correctly located its bundle-relative helper by absolute path. That helper then located *its own* dependency by searching `$PATH`. Finder launches an app with `/usr/bin:/bin:/usr/sbin:/sbin`, so a Homebrew installation disappeared. The person was told a command was unavailable on a machine where it plainly was available.

**Three testing gaps let it ship**, and all three are instructive: app tests replaced the helper with a mock and therefore stopped at the app boundary, never exercising the real helper's own dependencies; the upstream release probe erased the whole environment instead of changing only `PATH`, and accepted any non-crashing report without requiring a real inspection; and the branch producing the helper had no CI for its onboarding contracts.

**Expected behaviour now.** One rule: **the helper owns machine inventory and resolves every direct dependency to a canonical absolute executable; the app stays parse-only.** Both the UI and the headless runner call the same production seam, and neither reimplements inventory. The release gate runs the real packaged artifact under a Finder-shaped environment.

**Serves:** US-B01, US-B17, US-A05.

---

### ES-6 — Honest imperfection rolled back verified work, twice · **REMEDIATED in `cc` 2.1.1 and 2.1.2**

Fully narrated as steps 2 and 3 of **UC-1**. Summarized here because it is the sharpest *class* of error in the product: **a fail-closed system that cannot distinguish "honestly imperfect" from "broken" will destroy its own correct work, deterministically.** Expected behaviour now: a held item never shares fatal treatment with a blocked one; rollback triggers only on a genuine environment failure; rollback confirmation is a direct byte comparison of the file; the health gate counts `fail`-severity checkers directly rather than reading an aggregate label; and cold-start mirrors are seeded before the check.

**Serves:** US-B09, US-B10, US-B11.

---

### ES-7 — A backstage component that lied about its own readiness · **REMEDIATED in `cc` 2.2.0**

**Trigger.** Provisioning the organization's shared secret store.

**What happened.** A phantom provisioner could report a store as **configured when it was not**.

**Why it is the most soul-relevant failure in the list.** Not an outage, not data loss — a **false-positive readiness claim**, the exact class the product's whole honesty discipline exists to prevent, occurring backstage rather than in the icon. Any report of readiness that is not backed by a verification the app can point at is this same defect wearing a different hat.

**Expected behaviour now.** The secret-store stage checks against the store's **real identity surface** rather than a stale placeholder. Fixed alongside the connections bridge and shipped in v0.4.0.

**Serves:** US-E07, US-B07.

---

### ES-8 — Conservative safety reads as a wall of problems · **OPEN, by design**

**Trigger.** Any first setup on a machine with pre-existing repositories.

**What happens.** The history classifier checks the working tree before it compares any SHA, and **any** non-empty status routes to review without fetching or ancestry-checking. In the live run that meant six of seven present repositories landed on review, and in every case the non-emptiness was one hundred percent *untracked* framework litter — not a single modified tracked file.

**Why the behaviour is correct and stays.** Nothing can distinguish someone's uncommitted edit from their scratch file without making exactly the judgment call this product has decided belongs to a human.

**Why it is nevertheless open.** Nine review rows presented to a non-technical person is not safety, it is a wall. **The design burden therefore falls entirely on the copy** — this must read as courtesy rather than as a list of failures, which is precisely why the H4 Holding variant exists. The unbuilt, unscheduled opportunity is a frontstage translation layer that says *"we found files here we didn't put there, so we stopped"* rather than surfacing a count of review states.

**Serves:** US-B10.

---

### ES-9 — The silent-failure surface · **OPEN, a deliberate consequence**

Four ways this service can fail today without telling anyone, named explicitly rather than smoothed over.

- **The 300-second poll is the only heartbeat, and nothing monitors it.** If it silently stops, the glyph freezes on its last honest state and **looks exactly like success**.
- **The app has no watchdog.** The crash-only LaunchAgent the invariants describe exists only in the retired tree; if the tray dies, nothing restarts it. Mitigation: the pipeline is still correct — the person loses their window, not their environment.
- **No telemetry exists**, so nothing detects a stuck fleet. The Analytics surface has a toggle and no emitter.
- **No fleet dashboard exists**, so an admin learns that someone is stuck only when that person says so. Escalation is entirely person-carried, through whatever channel the organization already uses.

Each is a real cost of choosing a small audit surface over observability, and it is defensible for a small, trusted organization. It is also **the single largest scaling risk in the service model.**

**Serves:** US-B19, US-E06.

---

### Edge-case table

*Every row is a state the shipping app actually renders. The `secret_state` and category rows are the two most tempting places to break parse-never-compute, and both are single-field filters over CLI-authored values.*

| Scenario | Trigger | Expected Behaviour |
|---|---|---|
| **Offline** | No network at any point | `Sync now` is inert with "Waiting for the network." beneath it. The badge is the crossed-cloud token. *Waiting for network* and *offline* are first-class states, never a fallback to the last green |
| **The CLI cannot be read at all** | Unparseable body, a version outside the accepted range, or a missing security-relevant field | One explicit red state: "I can't read the setup right now, so I won't guess." No copilot rows, no join row, one retry. **Never an optimistic state.** The reason token itself is never shown and the raw error text is never shown |
| **The helper is newer than the app's window** | A `cc` whose schema major is outside `1.0 – 2.0`, or outside the declared `2.0.0 – <3.0.0` version range | Fail closed into the unreadable state with the plain sentence "Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up." **The gate is bidirectional: older than the floor is as fatal as newer than the ceiling** |
| **A security-relevant field is absent** | An omitted `destructive`, `signed`, or `severity` | Treated as destructive, unsigned, and failing. **A missing security field is never treated as safe** |
| **Organization config has not materialized** | The person's machine has no inherited org configuration yet | The connections roster still renders **in full**, with every store-dependent row honestly marked as having no store. Never an empty list, never an error screen |
| **An unrecognized connection state** | A future `secret_state` value the app does not know | Grouped with not-available and given an honest explanation. **Never shown as ready, never silently dropped** |
| **The organization's OAuth app was never created** | Standup skipped or failed at that step | The person's Connect GitHub step has nothing to authenticate against. This is a handoff failure between Admin Done and the person's Welcome, and it renders as an honest sentence naming who owns the missing piece — not a blank screen |
| **The shared store was deferred at standup** | Earl chose to defer | Every integration row reads as having no store, honestly and indefinitely, until someone returns to the Connect-the-store governance surface. Deferring is a supported outcome, not a failure |
| **The browser window is lost during sign-in** | Bob switches away and cannot find the GitHub page | "Didn't see the browser? **Open it again**" — a second route back, because this is the common failure of this flow |
| **The device code expires** | Bob takes too long | An explicit ending of its own, never a stall. The wait carries no timer and no count, because the bottleneck is a person |
| **The grant is made as the wrong identity** | Bob signs in to the permission upgrade as a different GitHub account | A named terminal state with its own copy, not a generic error. The replacement token is committed only after the returned identity matches and the scope is confirmed |
| **The grant is insufficient** | Bob authorizes less than `write:public_key` | A second named terminal state with its own copy |
| **The chosen assistant is not installed** | Bob presses Run in Codex on a machine without Codex | The app names the missing assistant, states that nothing changed, keeps the generated payload, and offers the other assistant or a copy |
| **A dirty working tree blocks a sync** | Bob has uncommitted work in a visible checkout | `Review your changes`. The tree is **never** touched in any state. This is one of only two things the product stops and asks him about |
| **A department is revoked between list and join** | Access removed after the row rendered | `not-entitled` is a normal, renderable outcome, not a crash. The row states it is no longer available and offers **no** retry, because retrying cannot change it |
| **A join stalls with no answer** | Twenty seconds pass with no response | The row stops presenting itself as progress and says nothing came through and nothing was changed, with retry restored. **Deliberately different wording from a reported failure** |
| **A slow answer arrives from an abandoned attempt** | Two overlapping attempts on one row | Each attempt carries a generation number, so a stale answer can never overwrite a newer one |
| **Another `cc` invocation holds the lock** | A mutating verb is already running on this host | The mutating verbs serialize on a global per-host lock and fail fast when it is held. **The app neither holds nor observes that lock** — the pipeline is the serialization authority |
| **A secondary read fails** | The department list, account check, freshness sweep, or project scan errors | The main verdict still renders and the affected region is simply absent. **A failed read never claims a pending offer it could not confirm** |
| **A row the run never mentioned** | The engine finishes without reporting on a planned row | The reconciliation state: "Setup didn't say what happened here." A row is never quietly assumed to have succeeded |
| **A run goes silent mid-flight** | The engine stops answering | The screen says **No answer yet**, stops animating entirely, and offers Keep waiting and See what's really on GitHub. **A dead operation must never look like a slow one** |
| **A raw machine sentence reaches the app** | The CLI emits text naming machinery | Frame-or-replace, per string: a string written for a person is framed verbatim under *What setup found:*; anything else goes only into the collapsed **Details for support** block. Never a headline, never concatenated into an app sentence |
| **A support line has no value** | The app cannot fill a field of the diagnostic block | **The line is omitted. Never print "unknown."** A missing line is honest |
| **Undo is no longer provably safe** | The CLI can no longer prove what was added is untouched | **There is no control at all** — never a disabled one with no explanation — and the row's caption carries the reason |
| **Verify does not pass** | The completion rule fails | The screen refuses to congratulate: it renders the honest-incomplete pattern, and the finish action is not reachable. **There is no hedged middle wording** |
| **A selftest is pointed at a real helper** | An arbitrary helper path is set on a setup-transaction selftest | It **refuses to run** unless it is explicitly permitted *and* the helper's filename is literally the mock fixture's. An arbitrary override must never turn a selftest into a live mutation |

---

## Critical View Scenarios

The scenarios each critical view must demonstrate. These feed the design challenge directly.

| Critical view | Scenarios it must demonstrate |
|---|---|
| **The menu-bar glyph** | Silence when healthy (no mark at all) · each of the honest non-answers — offline, waiting for network, could not check · the single red unreadable state · **legibility frozen, in grayscale, at menu-bar size**, because the badge never animates |
| **The Holding screen** | All seven variants side by side, so the routing-by-owner rule is visible · **H4 rendered next to H3** to prove a courtesy and a fault cannot be confused · H6 with a primary that is not a retry · the collapsed support block with a line legitimately absent |
| **Set up progress** | A clean run · a run with held items · a run with blocked items · **a row the engine never mentioned** · a run that goes silent · and the honest account screen at the end of each, including the one that must say nothing changed against an empty ledger |
| **The roster reveal** | A full twenty-service roster · a roster where the organization's configuration has not materialized (full list, all rows marked no store) · a roster containing an unrecognized state that must group as not-available · the five project categories with their plain-language meanings |
| **Verify** | Success · honest-incomplete with the finish action unreachable · a single failed item retried on its own |
| **The popover** | Everything fine (very little rendered) · one prompt and several notices, proving at most one prompt renders · an `AVAILABLE TO JOIN` offer that carries no badge · the `What changed` drill-in in both its populated and empty states |
| **The project drill-in** | All five categories · the three-row preservation panel · a real Terminal handoff with Bring Terminal forward · an owner handoff that changes nothing · **Couldn't confirm rendered without embarrassment** |
| **Admin Review setup and Setup check** | The full plan before any write, by name and destination · a stopped run reporting what exists · the read-only check that is handed over |

---

**Related:** [User Stories](10-user-stories.md) | [Acceptance Criteria](30-acceptance-criteria.md) | [Service Blueprint](../02-service-design/10-service-blueprint.md) | [Journey Maps](../02-service-design/20-journey-maps.md) | [Moments That Matter](../02-service-design/40-moments-that-matter.md) | [UX Design](../04-experience-design/50-ux-design.md) | [CLI Contract](../../01-architecture/cli-contract.md)
