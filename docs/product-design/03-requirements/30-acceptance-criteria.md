# Acceptance Criteria

<!--
FACILITATION GUIDE — QA / Design Review
=========================================
Acceptance criteria are the verifiable conditions that determine
whether a feature is "done." Every user story and scenario must have
testable criteria.

PREREQUISITE: User stories and use cases must be completed.

CONVERSATION FLOW:
1. For each user story, define what "done" looks like
2. Define testable conditions (Given/When/Then)
3. Define performance criteria
4. Define quality criteria

QUESTIONS TO ASK:

## Round 1: Functional Criteria
For each user story:
- "How do we verify this story is working correctly?"
- "What's the minimum acceptable behavior?"
- "What should NEVER happen?"
- Given/When/Then format:
  "Given [precondition], when [action], then [expected result]"

## Round 2: Performance Criteria
- "How fast should the core operations be?"
- "What's an acceptable response time for the UI?"
- "How much data should the system handle?"
- "What are the concurrency requirements?"

## Round 3: Quality Criteria
- "What accuracy or quality levels are acceptable?"
- "How do we measure output quality?"
- "What accessibility standards apply?"

## Round 4: Data Quality Criteria
- "What's an acceptable error rate?"
- "What completeness thresholds apply?"
- "What data formats must be supported reliably?"

SYNTHESIS:
Present in Given/When/Then format grouped by feature area.
Every criterion must be testable — no subjective language like
"should be fast" or "should look good."
-->

> **Status — rebuilt from evidence 2026-08-02. Describes Copilot Control Tower v0.4.0** (build 19, source commit `453d15f`, embedded helper `cc 2.2.0`). This replaces a version whose criteria were written against MDM-pushed silent provisioning, a fleet dashboard, telemetry, and in-app self-update — none of which exist in the shipping app.
>
> **Read the verification column before you read anything else.** This document's most important content is not the criteria; it is the honest statement of how few of them are automatically verified. **Ten of fifty-three criteria have automated verification that runs on every release. Twenty-four rest on code review and manual inspection alone.** Zero are verified by the forty architectural fitness tests, because those tests scan a retired implementation and cannot see one line of the shipping Swift.
>
> **The architectural rule every criterion respects: Control Tower parses, it never computes.** Not one criterion below requires the app to decide anything. Where a decision appears, it is phrased as *the CLI reports X, the app renders Y*. A criterion that would require app-side resolution, health, merge, entitlement, or signature logic is the wrong criterion and does not belong in this document.

---

## The verification problem, stated plainly

This is gap **G-1**, and it is the first thing any reader of this document needs.

**All forty `fitness_*.rs` architectural tests scan `src-tauri/src/**` — the Rust crate that no longer ships.** They cannot see a single line of the roughly 22,650 lines of Swift that are the product. They were written to enforce the six invariants and they still enforce them, over a retired implementation. **The CI job that runs them is disabled behind a repository variable** (`vars.RELEASE_CI_ENABLED`), and the release pipeline that actually cuts releases runs locally and never invokes `cargo` at all.

Consequently the six invariants in `CLAUDE.md` are **architectural commitments upheld by design and by review, not automatically-enforced properties of the shipping binary.** Several native-side properties genuinely *are* enforced — never a bare CLI name, the fail-closed schema gate, the selftest that refuses a non-mock helper — but by code review and by shell release gates, not by the named fitness functions. Porting the suite to scan `native/*.swift` and re-enabling the job is an open item, and the owner's ratified position of 2026-08-02 is to document this honestly rather than fix it in this pass or quietly reframe it away.

A second, quieter consequence deserves naming: **most of the shell harnesses that do exercise the Swift are not wired into the release path either.** The disabled CI job is the only place that runs the 138-scenario smoke matrix, the app-bundle check, the cross-version schema gate, and the notarization-order gate. They are real, they are runnable on demand, and they were run — the smoke matrix's last recorded result is 138/138 green. But they do not gate a release today, so a regression in any behaviour they cover would ship unless someone remembered to run them.

### The four verification classes used in this document

| Class | Meaning | What actually runs it |
|---|---|---|
| **A — Automated, gates every release** | A failure blocks the release, automatically, every time | `scripts/package-user-release.sh`: notary-profile preflight, signing, the automation-entitlement check, the embedded-helper checksum comparison, the pinned-and-not-re-signed helper verification, headless Detect, the headless setup transaction and its packaged-helper topology leg, notarization and stapling of app and DMG, strict signature verification, and two Gatekeeper assessments |
| **H — Harness exists, on demand only** | A real test asserts it, but nothing runs that test as a condition of release | The 138-scenario smoke matrix, the app-bundle checks, the cross-version schema gate, the notarization-order gate, the admin bootstrap harness, the project-integration contract, and the env-gated in-binary selftests. Most live in the **disabled** CI job |
| **L — Live-run evidence** | Demonstrated once, against real accounts, with recorded evidence. Not repeatable automatically | The ENAC 16/16 live apply and its recorded stage evidence |
| **M — Manual / inspection only** | No test asserts it on the shipping code. Upheld by code review and by the design's own structure | — |

**Some criteria carry two classes.** Where a criterion is asserted both by a release gate and by a recorded live run, both are named, and the automated one is what counts for the tally.

---

## Functional Criteria (Given / When / Then)

### AC-C · The contract seam — parse, never compute

**AC-C1 — The version is decoded before any other field, per verb.** *Given* any response from the helper, *when* the app decodes it, *then* it reads **only** `schema_version` first and requires an **exact major match for that specific verb** — major 2 for `onboard`, major 1 for every other verb — before trusting any other field. *Verification:* **A** — headless Detect drives the real gate through the production client on every release; **H** — the smoke matrix asserts the resulting states. *(US-B12, US-E08)*

**AC-C2 — The version range gate is bidirectional.** *Given* a declared compatibility window of helper `2.0.0 – <3.0.0` and schema `1.0 – 2.0`, *when* the helper falls outside it in **either** direction, *then* the app fails closed into the unreadable state. **A helper older than the floor is exactly as fatal as one newer than the ceiling.** *Verification:* **H** — the cross-version schema gate drives the exact packaged artifacts against legacy, canonical, matching-dual, and conflicting manifests, but it runs only in the disabled CI job. *(US-B12)*

**AC-C3 — A missing security-relevant field is unsafe, never safe.** *Given* a response with an absent `destructive`, `signed`, or `severity`, *when* the app renders it, *then* it treats the item as destructive, unsigned, and failing. **It never treats absence as safety.** *Verification:* **M**. *(US-E08)*

**AC-C4 — The helper is never resolved from `$PATH`.** *Given* the app launched from Finder with `/usr/bin:/bin:/usr/sbin:/sbin`, *when* it invokes the helper, *then* it resolves an absolute path in a fixed order — an explicit executable override, then the bundle's own copy, then three known absolute locations — and **never** a bare name. *Verification:* **A** — headless Detect runs under exactly that Finder-shaped `PATH` on every release. *(US-B01)*

**AC-C5 — The app's vocabulary is closed and does not include the deferred verbs.** *Given* the full app, *when* its call sites are enumerated, *then* they consist of exactly nine verb families — health, sign-in and grant, layers and join, freshness, update and fan-out, personal and organization onboard, nine workspace subverbs, and connections — and **`resolve`, `deprovision`, `repair`, and `publish` are never called.** *Verification:* **M**. *(US-A04, US-E06)*

**AC-C6 — The child process is isolated and marks itself.** *Given* any helper invocation, *when* the process is spawned, *then* it receives a private mode-0700 temporary directory under the app's own cache and an environment marker that **disables the helper's own self-update**, so there is never a two-updater fight over the same binary. *Verification:* **M**. *(US-E08)*

---

### AC-S · The setup transaction

**AC-S1 — All deterministic preflight precedes any irreversible write.** *Given* a sixteen-row topology plan, *when* apply runs, *then* every deterministic check — including the git-history classification of every repository — completes before the first irreversible write, and **a blocked row yields zero mutations rather than a partial set**. *Verification:* **A** — the packaged-helper topology gate drives the exact shipping helper against a deterministic local git fixture asserting sixteen rows across eight history states, as a leg of the headless setup transaction on every release; **L** — the ENAC live run. *(US-B09)*

**AC-S2 — Only a merge-base-proven fast-forward may auto-repair.** *Given* a repository in any history state, *when* the classifier routes it, *then* only a state whose fast-forward is proven by merge base may be repaired automatically; **every other state routes to a person and stops the transaction** before any personal-repository, key, store, or manifest mutation. *Verification:* **A** (topology gate); **L**. *(US-B09, US-A02)*

**AC-S3 — Apply asserts the world matches the promise.** *Given* a completed apply, *when* it reports success, *then* the result equals the target as an asserted postcondition, and "already at target" and "fast-forwarded" are reported as **distinct** outcomes rather than collapsed into one. *Verification:* **A** (topology gate); **L**. *(US-B09)*

**AC-S4 — "Nothing changed" is legal only against an empty ledger.** *Given* any exit path, including every failing one, *when* the app renders an account of the run, *then* that account is bounded by a run-scoped completed-actions ledger, and **the words "nothing changed" may not be rendered when the ledger is non-empty**. *Verification:* **H** — the smoke matrix asserts the ledger is rendered at every site that once rendered a false "nothing changed"; **L**. *(US-B09; the direct fix for ES-1)*

**AC-S5 — Orphans are adopted, never recreated.** *Given* a personal repository that already exists remotely, *when* apply runs, *then* it is adopted with its creation timestamp unchanged, and a create action is reachable **only** on an explicit HTTP 404 as the sole accepted evidence of absence. *Verification:* **A** (topology gate asserts each row's action against its history state); **L** — three previously-orphaned repositories adopted with creation timestamps byte-identical before and after. *(US-B09)*

**AC-S6 — A held item never shares fatal treatment with a blocked one.** *Given* a materialize pass that reports held items (a passive, protective non-write) and blocked items (an active refusal), *when* the transaction evaluates its result, *then* neither is fatal to the manifest write or the overall result on its own, and **only a genuine environment failure may undo an already-verified write**. Rollback confirmation is a direct byte comparison of the file, never a re-run of the gates that failed. *Verification:* **L** only — found and proven by the live run; no automated gate asserts it. *(US-B09; the direct fix for ES-6)*

**AC-S7 — No estimate is ever rendered.** *Given* a setup run of any duration, *when* progress is displayed, *then* it is a named list of real outcomes with a count that exists **only while the run is alive**, and **no percentage, no countdown, and no time estimate appears anywhere**. The count disappears when the run ends so it can never read as a score. *Verification:* **M** on the shipping Swift. A fitness test asserts this rule — over the retired tree. *(US-B09, US-E03)*

---

### AC-H · Stops, holds, and failure routing

**AC-H1 — A stop is classified by who owns the fix.** *Given* any stop during setup, *when* a Holding screen renders, *then* the variant is selected by **who owns the fix** — whoever installs software, nobody, the person, the organization — and never by what technically went wrong. Two failures with identical technical causes land on different screens when different people own them. *Verification:* **M**. *(US-B10)*

**AC-H2 — A courtesy never renders as a catastrophe.** *Given* the variant meaning *something here is already yours*, *when* it renders, *then* it is **not orange**, uses none of the words *paused*, *stopped*, *couldn't*, *problem*, or *error*, shows a card headed **What I left alone** with the caption **Nothing was changed, moved, or removed**, and its primary action reads **Keep what I have**. *Verification:* **M**. *(US-B10)*

**AC-H3 — A button that cannot change the outcome is not offered.** *Given* the variant meaning *your organization has something left to do*, *when* it renders, *then* its primary action is **not** a retry; the forward action is to leave, and the screen says so. *Verification:* **M**. *(US-B10)*

**AC-H4 — Frame or replace, per string.** *Given* a string authored by the CLI, *when* the app displays it, *then* a string written for a person is framed **verbatim** under *What setup found:*, and a string naming machinery goes **only** into the collapsed support block. **A raw machine sentence is never a headline and is never concatenated into an app sentence.** *Verification:* **M**. *(US-B10; the direct response to ES-2 and to the live-verified string that produced the H4 variant)*

**AC-H5 — Every screen has two exits and one of them works offline.** *Given* any Holding variant, *when* it renders, *then* at least two exits exist and at least one works offline and with a broken helper. **Continue in the menu bar** appears on every variant and **never marks setup complete**. *Verification:* **M**. *(US-B10, US-B15)*

**AC-H6 — A missing line is omitted, never filled.** *Given* the collapsed diagnostic block, *when* the app cannot fill a field, *then* the line is **omitted**. The word "unknown" is never printed. *Verification:* **M**. *(US-B10)*

---

### AC-T · The tray and honest status

**AC-T1 — Healthy draws nothing.** *Given* a healthy verdict, *when* the tray renders, *then* the glyph carries **no badge at all** and no sentence, toast, checkmark, or celebration appears anywhere. *Verification:* **H** — the smoke matrix asserts `badge=none` with the sentence "Everything is set up." *(US-B12)*

**AC-T2 — Shape carries state before colour, and nothing animates.** *Given* any of the twelve closed badge tokens, *when* it renders, *then* it has a distinct symbol before it has a colour, and **the menu-bar badge does not animate** — no pulse, no rotation — so every state is legible frozen and in grayscale. **No state anywhere is carried by colour alone.** *Verification:* **H** (badge scenarios); **M** (the no-animation rule). *(US-B12)*

**AC-T3 — The claim is always about now.** *Given* the steady state, *when* the app reports status, *then* the result is produced by re-running the real pipeline on a 300-second timer plus on launch and on every popover open — **never by remembering the last good answer**, and never by computing an offline verdict. *Verification:* **M**. *(US-B12)*

**AC-T4 — Unreadable is one explicit red state, never an optimistic one.** *Given* a response that is unparseable, out of range, or missing a security field, *when* the app renders, *then* it shows exactly one red state with the sentence "I can't read the setup right now, so I won't guess", renders no copilot rows and no join row, offers a retry, and **shows neither the reason token nor the raw error text**. *Verification:* **H** — the smoke matrix asserts the red token and the "won't guess" sentence for an environment-error exit. *(US-B12)*

**AC-T5 — The sentence names the specific thing.** *Given* one failing component among several, *when* the status sentence renders, *then* it names the failing component and layer — "Codex needs sign-in; Claude is fine" — and **never** a blended "something needs your attention." *Verification:* **H** (the smoke matrix asserts sentences alongside badges). *(US-B13)*

**AC-T6 — At most one prompt; any number of notices.** *Given* a machine with both an unsaved-changes hold and a pending permission, *when* the popover renders, *then* the prompt lane renders **exactly one** prompt, checking the unsaved-changes hold first, and notices render sequentially and independently so a prompt can never make a notice invisible. An offer — a joinable department, a project that *could* be set up — **never badges the menu bar**. *Verification:* **H** (the selftest surface exposes both the prompt and the notice states). *(US-B13, US-B06)*

---

### AC-W · The wizard flow

**AC-W1 — Nine stages, named, with no eleventh.** *Given* first launch, *when* the setup window opens, *then* it presents exactly nine stages — Welcome, Connect GitHub, Detect, What you're getting, Departments, Your connections, Your projects, Set up, Verify — labelled "Step N of 9", with completed rows reviewable and upcoming rows not. *Verification:* **H** (wizard selftest scenarios); **M**. *(US-B01–US-B11)*

**AC-W2 — Detect writes nothing.** *Given* the Detect stage, *when* it runs, *then* it performs exactly three read-only calls and **has no apply counterpart by construction**; nothing on the machine or on GitHub is changed. *Verification:* **A** — the headless Detect entry point runs those three exact calls through the production client on every release and exits before any UI exists. *(US-B04)*

**AC-W3 — The organization question is asked last and framed as a question.** *Given* that the organization cannot be resolved, *when* the question appears, *then* every silent source has already been exhausted, the screen renders **inline and in accent blue rather than orange**, a pasted address is rewritten in place to the bare name with no message, the disabled primary shows its reason as **visible text**, and two exits are offered. *Verification:* **M**. *(US-B02)*

**AC-W4 — Verify cannot be talked into congratulating you.** *Given* a completion rule that does not pass, *when* Verify renders, *then* it shows the honest-incomplete pattern, **the finish action is not reachable**, and no hedged middle wording exists. Readiness requires all five of: the complete roster, a visible folder, a connection, a successful sync, and a post-apply verification. *Verification:* **H** — the completed-setup acceptance gate asserts this, by source pattern rather than behaviourally, and runs on demand only. *(US-B11; the direct fix for ES-4)*

**AC-W5 — The sign-in seam cannot hold a credential.** *Given* the sign-in flow at any point, *when* its state is inspected, *then* **no field exists that a token could occupy**; the state carries only the code, the address, the poll handle, and the interval. This is structural, not conventional. *Verification:* **M** on the shipping Swift. A fitness test asserts this rule — over the retired tree. *(US-B03)*

---

### AC-N · Connections

**AC-N1 — One CLI-computed field decides the grouping.** *Given* the organization's declared service roster, *when* the app groups it into Ready to use and Available to connect, *then* it filters on exactly one CLI-computed field and **derives nothing itself**: it does not contact the store, does not inspect a secret, and does not compute readiness. *Verification:* **H** (the connections selftest surface). *(US-B07)*

**AC-N2 — An unrecognized state fails closed.** *Given* a future connection state the app does not recognize, *when* it renders, *then* it is grouped with **not-available** and given an honest explanation. It is **never shown as ready and never silently dropped**. *Verification:* **H**. *(US-B07)*

**AC-N3 — An unmaterialized organization configuration still renders a full roster.** *Given* that the inherited organization configuration has not materialized on this machine, *when* the connections step renders, *then* the **full roster** appears with every store-dependent row honestly marked as having no store — **never an empty list and never an error screen**. *Verification:* **H**. *(US-B07; the direct fix for the pre-0.4.0 empty state)*

**AC-N4 — Names travel, values never do.** *Given* an unready service, *when* the app names what is missing, *then* it names credential **names** only. No credential value ever crosses the seam, in either direction, at any point. *Verification:* **M**. *(US-B07, US-E07)*

---

### AC-P · Projects and aftercare

**AC-P1 — The app filters categories; it never assigns one.** *Given* a set of discovered projects, *when* they are displayed, *then* every project carries one of five CLI-authored categories, and the app **filters rows by category and never classifies a project**. "Couldn't confirm" is a first-class state rendered without apology. *Verification:* **H** (the project-integration contract compiles the shipping data types against a fixture); **M**. *(US-B08, US-B17)*

**AC-P2 — Preservation is stated before the action, not logged after it.** *Given* any project write, *when* it is offered, *then* the three-row **Will add / Will preserve / Will not change** panel precedes it, and nothing is written until the person presses the action. Failure copy states what **survived**, not only what failed. *Verification:* **H** (source-pattern acceptance gates, on demand only). *(US-B17)*

**AC-P3 — The assistant is resolved to an absolute executable before launch.** *Given* a request to run in an assistant, *when* the app launches it, *then* it resolves an absolute executable first — because Finder and Terminal do not share a `PATH` — and opens a real, visible Terminal session. If the assistant is absent, the app **names it, states that nothing changed, keeps the generated payload**, and offers the other assistant or a copy. *Verification:* **M**; **A** for the adjacent capability — the release gate rejects a signed app lacking its Apple Events entitlement or its purpose string. *(US-B17)*

**AC-P4 — The app verifies for itself and never trusts the assistant's report.** *Given* a returning person after a guided session, *when* the app reports the project's state, *then* it re-inspects **both** assistants itself and does not accept the external assistant's own claim of success. *Verification:* **M**. *(US-B17)*

---

### AC-D · Admin

**AC-D1 — The script decides; the app renders.** *Given* any organizational mutation, *when* it is performed, *then* the decision to perform it was made by the deterministic engine using check-then-act — GET before every POST, PATCH, or PUT — and **never by the app and never by a model**. Nothing is forced, skipped past, or overwritten. *Verification:* **H** (the admin bootstrap harness). *(US-E02)*

**AC-D2 — Review precedes any irreversible write.** *Given* the Review setup surface, *when* it renders, *then* it enumerates the exact repository and team names that will exist, by name and destination, and **nothing irreversible has yet occurred**. *Verification:* **H**. *(US-E01)*

**AC-D3 — Progress is the approved plan, counted honestly.** *Given* a running standup, *when* progress renders, *then* the rows are the same rows in the same order with the same names the operator just approved; a count exists only while the run is alive; a bar appears only above seven rows and only as the visual twin of that count; the denominator grows **only** if the engine reports something the plan did not; and **no percentage appears anywhere**. *Verification:* **H** (the admin harness selftests). *(US-E03)*

**AC-D4 — A dead run never looks like a slow one.** *Given* a run that goes silent, *when* the silence threshold passes, *then* the surface says **No answer yet**, **stops animating entirely**, and offers Keep waiting and See what's really on GitHub — because the truth path is a read-only check, never a guess or a cancel. *Verification:* **H**. *(US-E03)*

---

### AC-R · Release, recovery, and security posture

**AC-R1 — Every shipped artifact is signed, notarized, stapled, and Gatekeeper-assessed.** *Given* a release, *when* it is cut, *then* the app and the DMG are both Developer ID-signed, notarized, stapled, strictly signature-verified, and assessed by Gatekeeper, in that order, before the release directory is written. *Verification:* **A**. *(US-B01, US-A05)*

**AC-R2 — The helper is pinned, independently notarized, and never re-signed by this app.** *Given* the embedded helper, *when* a release is cut, *then* its checksum is compared against the build output, verified against the pin, and confirmed **not re-signed** — the app is a single owner of the helper but **never a second signing authority for it**. *Verification:* **A**. *(US-E08)*

**AC-R3 — A signed app without its automation entitlement and purpose string is rejected.** *Given* a signed app, *when* the release gate runs, *then* a bundle lacking the Apple Events entitlement or the user-facing purpose string **fails the release**. Source that merely contains an automation string is explicitly not sufficient. *Verification:* **A**. *(US-B17, US-A05)*

**AC-R4 — The build's source list is explicit.** *Given* the build, *when* it compiles, *then* the source files are enumerated explicitly and **never** by a glob, so a file cannot silently join a build; and the user build's list deliberately excludes the admin sources, so the ordinary build is structurally unable to reach Admin. *Verification:* **M** (inspection of the build scripts). *(US-E08)*

**AC-R5 — Every release note names the prior signed DMG.** *Given* a release, *when* its note is written, *then* it names the prior signed DMG to reinstall and states whether a helper downgrade is required, under the standing rule that release tags are immutable and a defective build is superseded rather than moved. *Verification:* **M** — a manual read of the changelog. **STATUS: NOT MET at v0.4.0.** Every release from 0.2.1 through 0.3.2 carries this paragraph; **the v0.4.0 entry does not.** The signed artifact and its checksum are retained, so rollback is still possible — but the instruction the non-technical person is meant to follow is missing from the release this document describes. <!-- TODO: confirm whether to correct CHANGELOG.md's 0.4.0 entry or to relocate the standing rule into release metadata. Documentation-only pass; not corrected here. --> *(US-B18, US-A06)*

**AC-R6 — There is no bypass anywhere.** *Given* the whole product, *when* it is searched, *then* no `--force`, no `--skip-verify`, no lower-bar mode, and no "make it healthy anyway" override exists; and no security-sensitive configuration is read from user-editable local preferences — only from compiled-in trust roots and signed, inherited configuration. *Verification:* **M** on the shipping Swift. Fitness tests assert this family of rules — over the retired tree. *(US-E08)*

---

### AC-X · Accessibility and copy

**Target: WCAG 2.1 AA, expressed through the macOS accessibility APIs.** This is a native application, so the conformance surface is VoiceOver, Full Keyboard Access, Reduce Motion, Reduce Transparency, Increase Contrast, and Dynamic Type — not ARIA.

**AC-X1 — Status is always in words, and never in colour alone.** *Given* any status row, *when* assistive technology reads it, *then* the row is a single element announcing name, status, and detail — "Sales, available to join"; "Claude Copilot, Ready"; "Personal, Needs setup, *the CLI's own explanation*". Decorative marks are hidden from assistive technology because the sentence beside them already carries the meaning. The menu-bar item exposes the button role and the current status sentence as its label, refreshed on every check. *Verification:* **M**. *(US-B12, US-B13)*

**AC-X2 — A reason you can only find by hovering is not a reason.** *Given* any disabled primary action, *when* it renders, *then* its reason appears as **visible caption text as well as help text**. *Verification:* **M**. *(US-B02, US-B08)*

**AC-X3 — Focus is never stranded.** *Given* a Holding screen appearing over a stage, *when* it renders, *then* focus moves to its title through an explicit focus binding, so a keyboard or VoiceOver user is never left on a control that has just disappeared. Every control is a standard system control, so Tab traversal, arrow-key navigation, and the system focus ring are inherited rather than reimplemented, and the focus ring is never restyled. Return activates the default primary on every step; `⌘,` opens Settings; `⌘q` quits. *Verification:* **M**. *(US-B10)*

**AC-X4 — Every primary names its consequence.** *Given* any button in the product, *when* it is labelled, *then* it names its consequence — Get Started, Review setup, Set up 3 and continue, Finish safely, Finish setup, Grant this on GitHub, Add the connection, Keep what I have. **No button is labelled "Submit."** There is no "Update" button, because updates install themselves. No em-dashes appear in any user-facing string, and no raw error text, configuration syntax, serialization message, or version-control conflict marker is ever displayed. *Verification:* **M**. *(all Bob stories)*

**AC-X5 — Contrast.** *Given* every rendered text-over-background pair, *when* measured, *then* it meets 4.5:1. **STATUS: UNVERIFIED.** No contrast measurement is recorded anywhere in this repository. The app uses system semantic colours throughout, which follow Apple's own contrast behaviour and respond to Increase Contrast, and materials use system vibrancy so Reduce Transparency falls back to opaque system colours automatically — but **there is no documented audit of the actual rendered pairs**, in particular small caption text over the translucent popover material. An audit is an open item. *Verification:* **M**, and not yet performed. <!-- TODO: run and record a 4.5:1 contrast audit of the rendered pairs, and record tab order for the popover once Region 6 carries a prompt — the framework's default document order is very probably correct for these layouts, but "probably correct by default" is not the same as designed. -->

---

## Verification Summary

**This is the headline of the document.**

| Class | Criteria | Share |
|---|---|---|
| **A — Automated, gates every release** | AC-C1, AC-C4, AC-S1, AC-S2, AC-S3, AC-S5, AC-W2, AC-R1, AC-R2, AC-R3 | **10 of 53** |
| **H — Harness exists, runs on demand, does not gate a release** | AC-C2, AC-S4, AC-T1, AC-T2, AC-T4, AC-T5, AC-T6, AC-W1, AC-W4, AC-N1, AC-N2, AC-N3, AC-P1, AC-P2, AC-D1, AC-D2, AC-D3, AC-D4 | **18 of 53** |
| **L — Live-run evidence only** | AC-S6 | **1 of 53** |
| **M — Manual / inspection only** | AC-C3, AC-C5, AC-C6, AC-S7, AC-H1–AC-H6, AC-T3, AC-W3, AC-W5, AC-N4, AC-P3, AC-P4, AC-R4, AC-R5, AC-R6, AC-X1–AC-X5 | **24 of 53** |

**Stated as plainly as it can be: fewer than one criterion in five is automatically verified on every release, and nearly half rest on a person having read the code carefully.** Zero criteria are verified by the forty architectural fitness tests, because those tests scan an implementation that no longer ships.

**Where the automated coverage concentrates, and why that is not an accident.** Every class-A criterion sits in one of two places: the **distribution boundary** (signing, notarization, stapling, the helper's pin and its non-re-signing, the automation entitlement) or the **setup transaction's topology contract** (preflight before writes, fast-forward-only auto-repair, the postcondition assertion, adopt-never-recreate). Those are exactly the two surfaces where a defect is either irreversible or invisible — a bad signature reaches every user, and a half-done transaction lies about someone's accounts. The coverage is where the blast radius is, which is the right instinct even though the coverage is thin.

**Where the automated coverage is absent, and what that costs.** All six holding-and-failure-routing criteria, all five accessibility criteria, and the whole of the honest-status vocabulary rest on review or on a harness nobody is obliged to run. These are precisely the behaviours that constitute the product's claim about itself — that a courtesy never renders as a catastrophe, that a raw machine sentence never becomes a headline, that no state is carried by colour alone. **They are the most important behaviours in the product and the least mechanically defended.**

**Two criteria are currently not met and are recorded as such rather than quietly dropped:** AC-R5 (v0.4.0 ships with no rollback instruction in its release note) and AC-X5 (no contrast audit has ever been performed).

---

## Performance Criteria

**No latency or throughput target in this product has ever been measured, because there is no instrumentation and no telemetry.** Every number below is a configured or structural fact read out of the shipping code and the compatibility pin — not an observed measurement, and not a target anyone is holding the product to. Inventing measured-sounding targets here is exactly the failure this rebuild exists to correct.

| Area | Value | Nature of the number | Verification |
|---|---|---|---|
| Status refresh cadence | **300 seconds**, plus on launch and on every popover open | Configured. A deliberate design parameter: real-time refresh is explicitly the wrong model, and a manual sync covers the rare urgent case | **M** (code fact) |
| Poll cost | A **single lock-SHA comparison**, not a full update | Structural. The cheap poll target exists so that cadence is affordable | **M** |
| Named-wait silence threshold | **20 seconds**, after which a named wait stops presenting itself as progress and states that nothing came through and nothing was changed | Configured. Deliberately different wording from a reported failure | **H** (the smoke matrix exercises the wait states) |
| Optional-hook transport timeout | **≤ 25 seconds**, declared in the compatibility pin alongside a fail-open policy | Declared. The codified outcome of the harness-outage incident | **M** (config fact) |
| Shipped artifact size | DMG roughly **24–25 MB**, of which the embedded helper is **21.4 MB** | Observed from the retained release artifacts | **A** (checksums recorded per release) |
| Topology size | **16 layers** — four components across four tiers. ENAC's live service roster is **20 declared services** | Structural | **A** (the topology gate asserts sixteen rows); **L** |
| Concurrency | Mutating verbs serialize on a **global per-host lock**, failing fast when held. **The app neither holds nor observes that lock** | Structural. The pipeline is the serialization authority, not the app | **M** |

**Deliberately absent, and why.** There is no p95 status-latency target, no time-to-healthy target, no fleet-convergence target, and no self-update rollback timing. The first three would require instrumentation that does not exist and that the non-goals rule out; the fourth would require a self-updater the product does not have. <!-- TODO: if any performance target is ever wanted, it needs an instrumentation decision first, and that decision has to clear the same bar as the rest of the security posture — a personal item name must be un-emittable by construction. Absent that, collecting nothing is the correct posture and measuring nothing is its honest consequence. -->

---

## Quality Criteria

Stated as the things that must **never** happen. Each is a violation of the product rather than a bug in it, and each traces to something that has already occurred at least once.

| Must never happen | Why it is a violation rather than a defect | Traces to |
|---|---|---|
| **A green state the app cannot prove** | The whole product is a standing claim renewed every five minutes. One false green makes the icon decorative and every subsequent true green worthless — and Bob is precisely the person who will notice | ES-4, MTM-2 |
| **"Nothing changed" against a non-empty ledger** | The one product whose promise is honesty telling a person something untrue about their own accounts. There is no route back from that conclusion | ES-1, MTM-1 |
| **A partial transaction reported as a stop** | A blocked row must yield zero mutations. A half-done transaction that reports cleanly is the sharpest failure in the record | ES-1 |
| **Touching a human-owned working tree** | The one failure that cannot be apologised for. It has already cost 12,537 lines of organization content in a single commit | ES-3 |
| **A raw machine sentence as a headline** | To a non-technical person a version-control error reads as *the tool broke my work*, and there is nowhere to go from there | ES-2, MTM-3 |
| **A courtesy rendered as a catastrophe** | The most common real outcome of a first setup is a screen full of holds. Misread, never-destroy working correctly becomes "this tool is broken" | ES-8, MTM-3 |
| **A percentage, countdown, or time estimate** | An estimate is a computed promise the app cannot keep, and the product's only currency is kept promises | US-B09 |
| **A dead operation drawing the same indicator as a live one** | Waiting forever is how trust dies quietly, and it shipped once | ES-9 |
| **A notification about something the person cannot act on** | It spends the credibility of the one alert that matters. Proximity to the menu bar is not competence | US-B13 |
| **A state carried by colour alone** | It fails a colour-blind reader, a monochrome render, and a frozen frame simultaneously | AC-T2, AC-X1 |
| **Personal content reaching a shared tier** | Irreversible. A wipe cannot un-exfiltrate, so this must be impossible by construction rather than discouraged by discipline | US-A02 |
| **Any bypass flag, or a "healthy anyway" override** | The entire safety claim is that the agent runs the same pipeline with zero bypass flags. One backdoor and the security review that gates all adoption ends in a no | US-E08 |
| **A selftest that can become a live mutation** | An arbitrary helper override must never turn a test into a real write. The guard requires both an explicit permission and a literal mock filename | AC-R6 |

---

## Data Quality Criteria

The completeness thresholds the contract itself enforces. These are properties of the JSON seam, not of the app — which is the point.

| Threshold | Requirement | Verification |
|---|---|---|
| **Topology completeness** | A reported topology carries **sixteen fully-populated rows** — four components across four tiers. Every row must carry its full field set; a skeletal look-alike row carrying only identity fields is invalid by schema | **A** (topology gate); **L** |
| **Empty is never ambiguous** | An empty layer array is valid **only** when paired with the explicit not-computed discriminator, emitted by the single exit path that returns before any topology is built. **A present-but-empty array can never masquerade as evidence** | **H** (schema validation) |
| **Ledger completeness** | The completed-actions ledger is a **required** field of the contract, not an optional one, and is present on every exit path including failing ones | **H**; **L** |
| **Action vocabulary** | Row actions are a **closed set** — reuse, create, migrate, repair, review. An unrecognized action is a contract violation, not an unknown to render | **A** (topology gate) |
| **Severity is not status** | Per-checker severity (pass / warn / fail) and aggregate status are **different fields** and may never be conflated. A gate must count fail-severity checkers directly rather than read an aggregate label | **L** (the direct fix for ES-6) |
| **Role is closed; identifier is opaque** | The layer role is a closed four-value set that clients may render. The layer identifier is an **opaque manifest string and must never be parsed for role semantics** | **M** |
| **Connection roster completeness** | The roster is returned **in full** in every result state, including when the organization's configuration is unavailable. An unrecognized state groups as not-available. **Names only; never a value** | **H** |
| **Secrets in inheritance content** | **Zero**, at every tier, public or private. Inheritance content carries a reference to a secret's name and how to acquire it, never a value. Git is a distribution mechanism, not a trust boundary | **M** |
| **Telemetry emitted** | **Zero.** There is no emitter in the shipping app. Nothing is collected, so nothing about a fleet can be claimed | **M** |

---

## Traceability

| Area | Criteria | Stories | Scenarios |
|---|---|---|---|
| Contract seam | AC-C1 – AC-C6 | US-B12, US-E08, US-A04 | ES-2, edge-case table |
| Setup transaction | AC-S1 – AC-S7 | US-B09, US-B11, US-A02 | UC-1, UC-2, ES-1, ES-6 |
| Stops and holds | AC-H1 – AC-H6 | US-B10, US-B15 | ES-2, ES-3, ES-8 |
| Tray and status | AC-T1 – AC-T6 | US-B12, US-B13, US-B06 | UC-4, ES-4, ES-9 |
| Wizard | AC-W1 – AC-W5 | US-B01 – US-B11 | UC-2, ES-4 |
| Connections | AC-N1 – AC-N4 | US-B07, US-E07 | UC-2, ES-7 |
| Projects | AC-P1 – AC-P4 | US-B08, US-B17 | UC-6, ES-5 |
| Admin | AC-D1 – AC-D4 | US-E01 – US-E05 | UC-3 |
| Release and posture | AC-R1 – AC-R6 | US-A05, US-A06, US-B01, US-B18, US-E08 | UC-7, ES-5 |
| Accessibility and copy | AC-X1 – AC-X5 | all Bob stories | UC-2, all critical views |

**Three stories have no functional criteria in this document, deliberately.** US-B19 (a watchdog), US-A07 (a second machine at parity), and US-A08 (invariants enforced on the shipping binary) are all `NOT SHIPPED`. Their criteria are stated inside the stories themselves as *what would have to be true*, and writing them here as though they were verifiable conditions of the current release would misrepresent the product. They are gaps G-2, the outstanding V-5 cold-laptop proof, and G-1 respectively.

---

**Related:** [User Stories](10-user-stories.md) | [Use Cases & Scenarios](20-use-cases-and-scenarios.md) | [Service Blueprint](../02-service-design/10-service-blueprint.md) | [Moments That Matter](../02-service-design/40-moments-that-matter.md) | [UX Design](../04-experience-design/50-ux-design.md) | [Scope & Non-Goals](../00-overview/10-scope-and-non-goals.md) | [CLI Contract](../../01-architecture/cli-contract.md)
