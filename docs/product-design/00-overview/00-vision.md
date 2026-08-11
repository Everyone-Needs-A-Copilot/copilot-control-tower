# Product Overview

<!--
FACILITATION GUIDE — Service Designer + Product Discovery
=========================================================
This is the starting point. Before anything gets designed or built,
we need to understand what this product IS and WHY it exists.

CONTEXT:
Read the project's CLAUDE.md for any existing product description.
Use that as a starting point, but let the conversation reveal the
full picture. Don't assume — ask.

CONVERSATION FLOW:
1. Start with the problem (what's broken in the world?)
2. Move to who feels this pain
3. Define what "done" looks like
4. Capture the jobs to be done
5. Map the forces (Moments Framework)
6. Establish what this is NOT
7. Articulate the AI philosophy (where AI helps vs. what humans do)
8. Define A+ capabilities and the essential minimum
9. Map the ecosystem and establish guardrails

QUESTIONS TO ASK (in order):

## Round 1: The Problem
- "What problem does this product solve?"
- "Who experiences this problem? Describe them as real people."
- "What's broken about the current reality? What happens today without this?"
- "What has this problem cost — emotionally, financially, in time?"
- "Why does this problem exist? What's the root cause?"

## Round 2: The Vision
- "If this product existed perfectly, what would change for the user?"
- "What's the magic moment — the single instant where a user thinks 'this is it'?"
- "What would make someone tell a colleague about this?"
- "Walk me through what you see in your mind when someone is using this.
  What does it feel like?"

## Round 3: Forces Mapping (Moments Framework)
- PUSH (away from current state): "What's driving people away from how they
  do this today?"
- PULL (toward new solution): "What's the dream? What's pulling people toward
  something better?"
- ANXIETY (about switching): "What worries people about trying something new here?"
- HABIT (keeping them stuck): "What keeps people doing it the old way even
  when it's broken?"

## Round 4: Jobs to Be Done
- "When [situation], I want to [motivation], so I can [expected outcome]"
- Ask for 3-5 of these. Probe: "What job is the user hiring this product to do?"
- Consider different personas and contexts.

## Round 5: Boundaries
- "What should this product absolutely NOT do?"
- "What would make this product fail — not technically, but as an idea?"
- "What's the one thing this must do well, even if everything else is mediocre?"

## Round 6: AI Philosophy
- "Where does AI help in this product — and where must a human stay in control?"
- "What is the AI's job? What is the human's job? Where does that line sit?"
- "What language should we use and avoid when describing what AI does here?"
- "Apply the Magic Test to each AI feature you're imagining:
    1. Would it feel like magic? Not 'useful' — magic.
    2. Does it create 100x value? Not 2x, not 10x.
    3. Does it serve the human or replace them? If it replaces, rethink it.
    4. Are we anchored on AI as the solution? Start with the problem instead.
    5. Would we build this even without AI?"
- "What are the things we say about AI in this product, and what do we
  specifically NOT say?"

## Round 7: Capabilities & Essence
- "What are the 3-5 capabilities that make this excellent, not just useful?
  What does delight look like for each one?"
- "If you stripped this product to its absolute minimum — the core of what
  it is — what would remain?"
- "How many lines of core logic does this product need? Where does scope
  bloat come from?"
- "What is a capability that would be a B- version of this product?
  What would the A+ version of that same capability feel like?"

## Round 8: Ecosystem & Guardrails
- "Where does {{PRODUCT_NAME}} sit in a broader product ecosystem?
  What flows in? What flows out?"
- "Are there other products this connects with? What's the intelligence
  handoff — what data crosses the boundary?"
- "What feature requests should be an immediate no — the ones that are
  a regression trigger if they appear?"
- "Who are the three stakeholders who must accept this product for it
  to be considered successful? What does acceptance look like for each?"

SYNTHESIS:
After the conversation, fill in the sections below using the user's
own language wherever possible. Keep it concrete and human.
-->

> **Status — rebuilt from evidence 2026-08-02.** This document was rewritten from the shipping code, the release history, the accepted ADRs, and the ratified decision records, replacing a version that described a Tauri/MDM product that no longer exists. It describes **v0.4.0** (released 2026-08-02); the underlying code survey was taken one release earlier at v0.3.2 (commit `e0bf0c3`), and every fact affected by the difference has been reconciled forward. Product status is **DOGFOODING** — running in production on exactly one organization (ENAC), not offered to outside organizations, not generally available. Seven signed, notarized releases exist; the claim "the build has not started" that appears in older documents is false.
>
> **Version note.** During this rebuild, **v0.4.0** was cut (2026-08-02): it adds the connections bridge and moves the embedded helper to `cc 2.2.0`. Nothing in this document changes as a result; where a fact is version-specific it is marked.

## Product Name

Copilot Control Tower (short: **Control Tower**)

## Summary

Control Tower is a native macOS menu-bar app that hands a non-technical person the working environment of a deeply technical one, and then keeps it that way without their attention. It is the face and supervisor over the `copilot`/`cc` command line: it asks the CLI what is true, renders the answer in plain language, and never computes a verdict of its own. Two faces ship from one source tree — a **User app** (the menu-bar tray plus a nine-step first-run setup) and an **Admin app** (sixteen surfaces that stand an organization's ecosystem up) — plus an owner-only **Publisher Setup** app used to sign and notarize releases.

What it keeps current is the **tooling you build with**, never the products you build: four components — Knowledge Copilot, CLI Copilot, Claude Copilot, Codex Copilot — across four tiers — foundation, organization, department, personal. Four components times four tiers is the sixteen-layer topology the app names on screen, sets up, and verifies. Entitlement is GitHub repository access and nothing else: you have a layer if and only if you can reach its repository.

The name is the model. A control tower does not fly the plane. It watches every flight, keeps them coordinated, clears them to proceed, and raises the alarm when something is off. It says exactly what is true and no more — and when it has nothing to say, it says nothing.

## Problem Statement

**The superpowers are real, and almost nobody can reach them.** The Copilot ecosystem already lets a technically proficient person write well, check numbers, build software that does part of their own job, and integrate data across systems. But that intelligence is CLI-shaped, and the CLI shape is a wall. The typical worker inside a company uses only the software IT handed them, in the way it was handed to them, and does not deviate. So the power stays locked to whoever is diligent and technical enough to hold it. `Evidence: OBSERVED` — before this product, Knowledge Copilot and CLI Copilot were effectively single-user inside ENAC; the absence of Control Tower is precisely why.

**Keeping it alive was a person, not a system.** The owner held the whole thing together by hand across two machines — telling the assistants to update, syncing components, pushing his own changes, re-updating everything on the laptop just to reach parity with the desktop. Nothing propagated unless he remembered. A change made once did not land everywhere; the human *was* the sync layer. `Evidence: OBSERVED` — lived daily, and the direct origin of the product.

**The obvious fix is the thing security teams refuse to trust.** What would actually solve both problems is an always-on, token-holding agent on every machine that quietly keeps the environment ready — which is exactly the shape of software an enterprise will not accept unless it can audit it. The trade-off on the table was: democratize the ecosystem and accept an unauditable background agent, or stay safe and leave every non-technical employee behind. Control Tower refuses that trade-off by earning the right to run unattended through legibility — one open-source signed binary that parses a versioned JSON contract and computes nothing.

**And the cost of getting this wrong is not hypothetical.** Three recorded incidents define the failure surface this product lives inside. A layer-manifest field rename shipped while the resolver still filtered on the old field name, so the org overlay vanished and the `UserPromptSubmit` hook exited non-zero — **Claude Code rejected every prompt on the machine** (`docs/40-initiatives/03-schema-mismatch/`, remediated in Control Tower 0.1.1). A materialize target was pointed at a human-owned authoring checkout, and one routine `cc update` reconcile-deleted **12,537 lines of org content** in a single commit, which a backup cron then pushed to origin (`docs/01-architecture/inheritance-and-publish.md`, "Elevating project content today"). And through v0.2.3 the app could report a Personal layer as ready when it existed only as a hidden mirror with no visible repository beside it — a false green (fixed in 0.2.4, ADR-005). Every invariant in this product traces to a failure of this class.

## Target Users

> **"Bob" is a psychology, not a job title.** The archetype is the change-averse, intensely detail-oriented professional found in every company and every department — IT, HR, finance, and executives can all be Bob. Accounting is the exemplar because accountants are archetypally not rule-breakers: they use what they are given, follow standards well, and are precise. Bob is uncomfortable with change because change means loss of control over something he is currently competent at, and being wrong could lose information, lose the company money, or lose him his standing. **The fear is professional consequence.** The design consequence is direct: Bob will catch a dishonest status, so an icon that cannot lie is survival, not decoration.

- **Bob — the change-averse non-technical consumer (PRIMARY).** `Evidence: GROUNDED` — real people across real companies. No terminal, no YAML, routinely denies OS permission prompts, ignores single nudges. "Bob is not a reliable actor" is a load-bearing design assumption, not a slight: the product is built so that nothing safety-critical depends on him noticing anything. He is asked about his own data and nothing else. Target emotion: comfortable *and* excited — these are superpowers he has wanted his whole career and is only now getting.
- **The trained early-adopter author — the writable tier.** `Evidence: MODEL-IN-HEAD, partially contradicted by one incident` — the multi-writer loop (write markdown in Obsidian, save, push, everyone pulls on cadence) has still never been run with more than one writer. What *has* been run is a single author's elevation path, and it produced the 12,537-deletion incident, which is why the current documented elevation procedure is copy-commit-push into the tier repository's own working directory and explicitly never a symlink.
- **Earl — the IT/admin operator (the enabler, not a co-equal audience).** `Evidence: RUN ONCE, BY THE AUTHOR` — upgraded from HYPOTHESIS on 2026-08-02. Admin mode has now stood up a real sixteen-layer organization end to end (Phase 7 reached 16/16 live apply). But it was run by the person who wrote it, on his own organization. **No third-party IT operator has ever touched it.** Whether a real admin trusts a guided tool enough to run an organization's standup through it remains an untested behavioral bet.
- **Pablo — the ecosystem owner and trust basis.** `Evidence: OBSERVED` — authors the foundation, holds the signing identity (`Developer ID Application: Pablo Alejo Jr`), and is the person the product releases from being the sync layer. He needs the always-on agent to make the ecosystem *safer* to adopt than the manual path, which is why the app is open source, why security-sensitive configuration comes only from compiled-in trust roots and signed inherited configuration, and why there is no bypass flag anywhere in it.

Not an audience, deliberately: open-source contributors looking to submit patches, and developers receiving an engineering handoff. Contribution mechanics stay minimal on purpose. The documents in this package are written for the owner's future self, for buyers and non-technical evaluators, and for organizations trying to change how they work.

## Core Capabilities

These are the capabilities that exist in the shipping binary at v0.4.0, described in the app's own on-screen vocabulary.

- **A menu-bar tray that states one honest thing.** An aviator-glyph status item badged from a closed twelve-token vocabulary (pass, ring, key, update, triangle, wrench, clock, cloud-slash, bang, spinner, hollow, none), refreshed on a single 300-second timer plus on launch and on open. Badge shape carries state first and color second, so status survives a monochrome or color-blind render. The popover names things in the user's language, not the system's: `YOUR COPILOTS`, `AVAILABLE TO JOIN` with per-row **Join**, `SHARED WITH YOUR TEAM`, `YOUR ACCOUNTS`. Actions are `Sync now`, `What changed`, `Set up`, `Settings…`.
- **A nine-step first-run setup that never requires a terminal.** Welcome, connect GitHub (browser device flow, no token ever held by the app), detect, what you're getting, departments, **Your connections**, **Your projects**, **Set up**, verify. Progress is named by phase, never by countdown or percentage — an estimate is a promise the app cannot keep honestly.
- **A settings window that shows the whole topology.** Four components (Knowledge, CLI, Claude, Codex) by four tiers (Foundation, Organization, Department, Personal), each row resolving to ready / needs setup / needs attention / not joined / could not check — derived purely from the CLI's own reports, with the visible repository name and on-disk path shown rather than an internal rank.
- **Project aftercare that routes work to the right assistant.** Projects are triaged into five CLI-authored categories with per-project detail: `Run in Codex` / `Run in Claude Code` open a real Terminal session at the project with the CLI-generated prompt, `Copy prompt`, `Copy project-owner handoff`, `Finish safely`, `Check again`. The app resolves each assistant to an absolute executable first, because Finder and Terminal do not share a `PATH`.
- **An Admin app that stands an organization up without hand-editing YAML.** Sixteen surfaces across two families — eleven onboarding (orientation, prerequisites, contacts, connect GitHub, describe your organization, integrations, secret store, review setup, organization setup, setup check, done) and five governance (add a department, someone left, connect the shared store, org setup, analytics). Every existence and idempotency decision is made by a deterministic bash engine using check-then-act (GET before POST/PATCH/PUT), never by a model and never by the UI.
- **A setup transaction that refuses to be half-done.** All deterministic preflight — including a nine-state Git history classifier — runs before any irreversible GitHub write. Only a merge-base-proven fast-forward is auto-repaired; every other history state routes to a person. Apply asserts `HEAD == target` as a postcondition, and a run-scoped ledger of completed actions threads through every exit path, so "nothing changed" is only ever a legal claim on an empty ledger.

## Status

- **Phase:** Dogfooding — live on one organization (ENAC), sixteen of sixteen layers applied live. Not general availability.
- **Stack:** Native macOS SwiftUI/AppKit, ~22,650 lines of Swift compiled by `swiftc` into three executables (User app, Admin app, Publisher Setup). The app shells out to a pinned, independently notarized `cc` helper embedded in the bundle and reads its versioned `--json` output. The earlier Tauri v2 / Rust / web-UI plan is **retired**; that tree remains on disk as read-only historical reference and is not built by the release pipeline.
- **Remaining before publicizing:** the V-5 cold-laptop proof (a second machine with an empty keychain onboards, clones both mirrors, and resolves every service with no hand-copied secret and no `.env`), then the scrub-rotate-publicize step for the two private foundation repositories. The second is deliberately last because it is irreversible and gated on credential rotation.

## Forces Map

<!-- Moments Framework. Re-grounded 2026-08-02 against the shipped record; the Push and Anxiety rows now carry incident evidence rather than only interview language. -->

| Force | Description |
|-------|-------------|
| **Push** (away from current) | Being the sync layer by hand. Two machines, and every laptop pickup meant re-updating the framework, Knowledge Copilot, and CLI Copilot just to reach parity — "that shit gets exhausting." Nothing propagated unless one person remembered. For everyone else, the push is sharper and quieter: they cannot reach Knowledge or CLI Copilot at all, so they stay inside whatever software IT gave them. `Evidence: OBSERVED` |
| **Pull** (toward new) | Make a change **once** and never wonder whether it landed. The environment is Copilot-ready without anyone thinking about it — an authorized upstream change simply appears on the next sync, and personal work is untouched. For the non-technical person the pull is the superpowers themselves: build the report instead of asking for it, draft in your own voice, reach the systems outside your computer. `Evidence: OBSERVED (the pain) / TESTED at one org (the mechanism)` |
| **Anxiety** (about change) | Three specific fears, in the order people actually feel them. (1) **"What if it breaks and I can't get back?"** — a non-technical person has no dignified recovery path, which is why every release since 0.2.0 ships an explicit rollback paragraph naming the prior signed DMG, and why release tags are immutable. (2) **"What if my private stuff ends up somewhere public?"** — the boundary is a trust wall and crossing it is irreversible; a wipe cannot un-exfiltrate. (3) **"What if it quietly destroys work I own?"** — no longer hypothetical after the 12,537-deletion incident. Underneath all three, for the security reviewer: an always-on token-holding auto-updater must be auditable, which is answered by pure open source, one signed binary, zero bypass flags, and a fail-closed schema gate. |
| **Habit** (keeping stuck) | Falling back to a generic chat window — the Claude app, ChatGPT, Gemini — for every question, instead of reaching for the solution-oriented ecosystem. The habit is not laziness; it is that the generic tool is one click away and always works, while the powerful one used to require a terminal. Control Tower's entire job on this axis is to make the powerful path the one that is already set up. |

## Jobs to Be Done

- **When** I make a change once to foundation, organization, or department content, **I want** it to land on every entitled machine quietly and without clobbering anyone's personal work, **so I can** stop being the sync layer and stop wondering whether it landed. *(The owner/author job — the origin job.)*
- **When** I am a non-technical person handed this ecosystem, **I want** a technical person's AI superpowers without understanding the layers underneath, **so I can** build, answer, and integrate what I need instead of being stuck with the software IT handed me. *(The democratization job — the essence.)*
- **When** something breaks or looks wrong, **I want** the system to either fix it or tell me in one plain sentence exactly what is wrong and who fixes it, **so I can** recover with dignity without being technical. *(The recovery job — Anxiety #1.)*
- **When** I work across personal and shared content, **I want** it to be structurally impossible for my private material to reach a shared place, **so I can** stop policing myself. *(The leak job — Anxiety #2; answered by construction, not by discipline.)*
- **When** I am setting my organization up, **I want** to be shown exactly what will be created, downloaded, or left alone before anything irreversible happens, **so I can** authorize a change I actually understand. *(The admin job — answered by preflight-before-any-irreversible-write.)*
- **When** I join a department or gain access to a new capability, **I want** it to appear on my machine because my repository access says it should, **so I can** stop filing tickets to get tools. *(The entitlement job — entitlement is GitHub repository access, full stop.)*

## The Magic Moment

Setup finishes, the menu-bar icon goes quiet, and a person who has never opened a terminal is now running the full sixteen-layer ecosystem on their own Mac — every component at every tier they are entitled to, each one named on screen with the repository it came from and the folder it lives in. Nothing was hidden, nothing was guessed, and they never had to be technical. From then on the deeper magic is the absence of events: an authorized change made once upstream simply appears on the next sync, without their attention and without touching a single thing they own.

For the owner, the same moment reads differently and just as strongly: the thing he used to carry by hand across two machines now carries itself, and the proof is a setup transaction that told him what it was about to do before it did it.

## Non-Goals

The full set with rationale lives in `10-scope-and-non-goals.md`. The five that matter most here:

- **Not a second brain.** No resolution, health scoring, signature verification, merge, or wipe logic exists in the app. If a decision requires computing ecosystem state, it belongs in the CLI. If Control Tower vanished, the CLI would still be correct.
- **Not a device-management product.** MDM is dropped completely as a mechanism — no `.mobileconfig`, no Jamf/Kandji/Intune flow, no forced configuration domain. Entitlement and deployment are GitHub repository access. People self-install a signed, notarized DMG.
- **Not cross-platform.** Windows is formally out of scope. The shipping app is native macOS SwiftUI/AppKit; the Windows work that exists lives entirely in the retired Rust tree and was never once run on Windows.
- **Not a manager of the things you build.** A product or project carries its own knowledge, skills, agents, and integrations inside its own repository. It is never a Control Tower sync layer. Control Tower syncs the tooling you build *with*, never the products you build.
- **Not a business.** Pure open source, free forever. No paid tier, no enterprise SKU, no hosted service, no closed component. Openness is not a pricing choice here; it is the security guarantee that lets an always-on token-holder be trusted at all.

## The One Thing

**It must never say something is fine when it cannot prove it.** Everything else in this product is negotiable in some direction; this is not. Bob is detail-oriented and change-averse, so one false green loses him permanently — and an always-on agent that can lie about state is worse than no agent, because it converts an honest unknown into a confident error. This is why the status vocabulary includes states like *waiting for network* and *could not check*, why missing security fields in the CLI's JSON fail closed rather than safe, why the app decodes `schema_version` before it trusts any other field, and why a warn-severity result must not be allowed to masquerade as either success or catastrophe. Honesty outranks convenience, and it outranks minimalism.

## AI Philosophy

Control Tower is a deliberate inversion of the "add AI" instinct. The intelligence already exists in the ecosystem's CLI; this product's job is to add exactly zero intelligence of its own and instead make that intelligence legible, safe, and always-on for people who cannot run it by hand. It is not an AI feature. It is the thing that puts AI capability into hands that could not otherwise hold it.

> **AI principle:** Control Tower adds no judgment of its own. It renders the CLI's verdict, automates only what is reversible, and escalates everything else to whoever is actually competent to decide it.

### What AI Does vs. What Users Do

| AI Provides | Users Do |
|-------------|----------|
| The CLI computes every health verdict, every layer resolution, every git-history classification, every signature check, every materialization | The person approves the one GitHub sign-in that is theirs to approve |
| The CLI generates the guided prompt for a project setup; the app opens a real Terminal session with it | The person watches the assistant work and stays in control of their own project |
| Control Tower parses `--json`, renders per-component and per-tier status, and re-runs the same pipeline on a schedule | The person decides which departments to join — bounded by what their repository access already permits |
| Control Tower auto-acts only where the action is reversible and the person could not reasonably judge it | The person owns every dirty working tree; the app never touches one |

### Language That Reflects This Principle

| We Say | We Don't Say |
|--------|--------------|
| "Control Tower renders the CLI's verdict" | "Control Tower determined your machine is healthy" |
| "Codex needs sign-in; Claude is fine" | "Something needs your attention" |
| "Waiting for network" / "Could not check" | "Healthy" (when it cannot prove it) |
| "Kept your working version" | "Update failed — contact support" |
| "Setting up Claude…" (a phase name) | "About 2 minutes remaining" (a computed promise) |
| "Your connections", "Your projects", "Available to join" | "Layer manifest", "rank", "package resolution" |

### The Magic Test

Before adding any AI feature — or any feature at all — ask:

1. **Would this feel like magic?** Not "useful." Not "efficient." Magic.
2. **Does this create 100x value?** Not 2x. Not 10x. If it is not 100x, it is probably not worth building.
3. **Does this serve the human, or replace them?** If it replaces, rethink it.
4. **Are we anchored on AI as the solution?** If yes, step back. Start with the problem.
5. **Would we build this even without AI?** If no, we are building for technology, not humans.

Applied to this product: (1) yes — sixteen layers live on a machine whose owner has never opened a terminal is magic to that person, and an upstream change appearing unbidden is magic to the author. (2) Yes — the alternative is per-machine hand-provisioning by the one person capable of it, which does not scale past one. (3) It serves: it removes toil from Bob and hand-craft from the admin, and it never takes a judgment away from the person who owns it. (4) Deliberately not — the anchor is trust and legibility of intelligence that already exists, and the first invariant forbids the app from adding model-driven judgment. (5) Yes — this is a supervision, provisioning, and distribution product; that what it distributes happens to be AI tooling is incidental to how Control Tower itself works.

## Capabilities & Essence

**The essence is DEMOCRATIZATION: a technical person's superpowers in a non-technical person's hands, kept ready on its own.** Organizations are the buyer; the individual is where the value lands. Parse-never-compute is not the essence — it is *how the product earns the right* to run unattended and deliver that essence.

The three capabilities below are the ones that make this excellent rather than merely useful, followed by two that make it durable. Every one is tested against the mechanism (democratization), not against the outcome (organizational transformation) — a feature that transforms an organization while requiring its people to be technical has failed this product's reason to exist.

### 1. Sixteen layers, no terminal (CRITICAL)

**The delight:** A person who could not have installed any part of this ecosystem gets all of it — four components at four tiers — from a double-click, a browser sign-in, and a screen that names in plain language exactly what it is about to create, download, or leave exactly as it found it.

**Example:** The nine-step wizard's Set up stage runs the preflighted saga: it classifies every repository's git history first, plans the full topology, shows the person the visible folder each repository will live in, and only then performs an irreversible write. A blocked row produces zero mutations rather than half a set of repositories.

**Impact:** This is the product's reason to exist for the end user. It removes the single biggest adoption barrier — that the ecosystem is CLI-shaped and its intended beneficiaries have no CLI.

### 2. The icon that cannot lie (CRITICAL — survival, not polish)

**The delight:** Status is one honest sentence naming the failing component, carried by a badge shape before it is carried by a color, refreshed by re-running the real pipeline rather than by remembering the last good answer.

**Example:** The schema gate decodes only `schema_version` before trusting any field, and requires an exact major match per verb (`onboard` requires major 2, everything else major 1). An out-of-range or unparseable response becomes an explicit unreadable state, never an optimistic one. Missing security fields fail closed.

**Impact:** Trust is the whole permission slip for running unattended. Bob will catch a drifted status, and one false green ends the relationship. The 0.2.4 fix — a GitHub repository or hidden mirror no longer counts as an installed layer — is what this capability costs when it is not upheld.

### 3. Change made once, landing everywhere, touching nothing it does not own (CRITICAL — the everyday hero)

**The delight:** An authorized upstream change appears on every entitled machine on cadence. Nobody runs a command. Nobody's personal work is disturbed. The author never has to ask whether it landed.

**Example:** Sync is pull-only and downward by construction — the scheduled path holds no upward push credential to any shared remote, so the worst leakage failure (a silent bidirectional sync) is closed structurally rather than by discipline. Visible working trees are human-owned: Control Tower may reuse a clean checkout or fast-forward it, and never resets a dirty one.

**Impact:** This is what released one person from being the sync layer, and it is what makes the ecosystem extensible by a team rather than usable by an individual. It is also the capability that opens the hardest remaining design problem — genuinely collaborative writable tiers.

### 4. Escalation routed by competence, not by proximity (DIFFERENTIATOR)

**The delight:** The system never notifies whoever happens to be standing at the menu bar. It auto-acts on reversible things the person cannot judge, routes to whoever holds the authority when authority is required, and asks the person only about their own data.

**Example:** The dirty-working-tree hold surfaces as `Review your changes` rather than as a git error; the missing `write:public_key` scope surfaces as `Grant this on GitHub` rather than as an OAuth failure; a project whose evidence cannot be confirmed offers a read-only diagnostic route rather than a verdict.

**Impact:** Every alert a person cannot act on burns down the credibility of the one that matters. Keeping the interrupt count near zero is what makes the rare real interrupt land.

### 5. Auditability as the moat (LONG-TERM MOAT)

**The delight:** An enterprise security review can read the entire thing. One signed binary. No daemon. No bypass flags. No closed component. Security-sensitive configuration comes only from compiled-in trust roots and signed inherited configuration, never from anything a user or an attacker can write locally.

**Example:** The embedded `cc` helper is SHA-256 pinned and independently notarized; the release gate rejects a signed app that lacks its Apple Events entitlement or purpose string; the in-binary setup-transaction selftest refuses to run unless the helper's filename is literally `mock-cc`, so an arbitrary override can never turn a test into a live mutation.

**Impact:** This is the thing a competitor cannot bolt on afterwards, because it is a discipline expressed as a hundred small refusals rather than a feature. It is also the go-to-market: openness is why an organization can say yes to an always-on token-holder at all.

## Essential Minimum

Stripped to its core, this product is a renderer over a contract. Everything below is load-bearing; everything not below is decoration.

| Component | Purpose | Notes |
|-----------|---------|-------|
| The versioned CLI `--json` contract | The entire safety boundary. The app cannot supervise a CLI it cannot read machine-readably | Lives in the CLI repository, not here. Fifteen schemas on disk; per-verb major gate; missing security fields fail closed |
| A locator that never resolves a bare name | The app must run *the* helper, not whatever `PATH` offers | Bundle `Contents/Resources/cc` first, then known absolute paths; `Process.executableURL` never consults `$PATH`, and `gh copilot` can never be mistaken for it |
| The status state machine and its twelve-token badge vocabulary | Turns a parsed report into one honest glanceable fact | Shape before color; no computed score; no celebratory success state |
| The nine-step wizard with named phases | Provisions a non-technical person without a terminal | No countdown, no percentage; a blocked step is a named state, not a spinner |
| The Admin bootstrap engine | Makes an organization exist, idempotently | Deterministic bash, check-then-act, GET before every write; the model and the UI decide nothing |
| The preflighted saga with a completed-actions ledger | Makes setup honest about what it did | All deterministic preflight before any irreversible write; `HEAD == target` postcondition; never-destroy compensation reports rather than deletes |
| Pinned, notarized helper + signed, notarized app + immutable release tags | Makes the thing installable by someone who cannot verify it themselves | Rollback is reinstalling the prior signed DMG; a defective release is superseded, never moved |

## Ecosystem Context

```
GitHub repository access (the single entitlement)   Shared secret store (endpoint via inherited org config)
              |                                                  |
              |  (who is entitled to which layer)                |  (references, never values)
              v                                                  v
                    +-------------------------------------------+
                    |            copilot / cc  CLI              |
                    |  computes: resolve, doctor, onboard,      |
                    |  layers, freshness, update, workspace     |
                    +-------------------------------------------+
                              |  versioned --json
                              v
                    +-------------------------------------------+
                    |         COPILOT CONTROL TOWER             |
                    |   User app (tray + wizard + settings)     |
                    |   Admin app (16 surfaces)                 |
                    |   parses, renders, schedules — never      |
                    |   computes                                |
                    +-------------------------------------------+
                              |
                              v
      Sixteen live layers on the machine: Knowledge / CLI / Claude / Codex
      x Foundation / Organization / Department / Personal
                              |
                              v
      The person's own work: their projects, in their own repositories,
      which Control Tower sets up integrations for and never syncs as layers
```

Flows **in:** the CLI's typed JSON reports, GitHub repository and team access, the organization's declared services and their connection state, the person's own choices about departments and projects. Flows **out:** materialized layers on disk (written by the CLI, never by the app), a real Terminal session handed to the chosen assistant, and a plain-language account of what changed. It replaces no system of record: GitHub remains the source of truth for access, the CLI remains the source of truth for state, and the person remains the owner of their own tree.

## Warning Signs (Regression Triggers)

| Request | Why It Is Wrong |
|---------|-----------------|
| "Let the app compute health when the CLI is slow or offline, so it still works" | Two sources of truth, and the app's is the one that can be wrong. An honest holding state is the answer; a guess is the one failure worse than more UI |
| "Add a `--force` or `--skip-verify` to unstick a machine" | The entire safety claim is that the agent runs the same pipeline with zero bypass flags. One lower-bar mode and the security review that gates all adoption says no |
| "Read the update feed or a mirror location from user preferences for power users" | A preference write becomes remote code execution. Security-sensitive configuration comes only from compiled-in trust roots and signed inherited configuration |
| "Show the merge conflict and let them resolve it — every developer does" | A raw VCS error reads to a non-technical person as *the tool broke my work*. Resolution is non-technical by construction or it does not surface to them at all |
| "Add a chat box so people can ask if their machine is okay" | It is a tower, not the pilot. A model-driven surface contradicts parse-never-compute by definition and multiplies the audit surface the moat depends on shrinking |
| "Add a paid tier or a hosted dashboard to fund the work" | Openness *is* the security guarantee. A closed component directly undermines the reason an organization can trust an always-on token-holder |
| "Show percent complete or time remaining during setup" | An estimate is a computed promise the app cannot keep honestly. Name the phase |
| "Push everything through one remote and sort the tiers out later" | Private content reaching a shared place is irreversible. Separate trees, separate remotes, and no upward credential on any personal-holding path |
| "Let the person approve the held update so the badge clears" | Proximity to the menu bar is not competence. Handing someone a decision they have no basis for trains blind approval |

## Acceptance Criteria

### For Users

*"I clicked once, signed in with my browser, and everything was set up. I have never opened a terminal. It told me exactly what it was going to do before it did it, and it only ever asks me about my own stuff. When something is wrong it tells me in one sentence what is wrong, and most of the time there is nothing to tell me at all."*

### For the Business

*"It is pure open source and free forever, and that is the strategy rather than a concession — openness is what lets an organization accept an always-on agent at all. Worth-it is measured in adoption, trust, and reliability: machines running honestly, setups that complete without a human rescuing them, and security reviews that end in a yes. There is no revenue metric here by design."*

### For the Ecosystem

*"An organization's people get the tooling their repository access already says they should have, without anyone hand-provisioning a machine. A change authored once lands everywhere entitled to it. Nothing personal ever moves upward, and no shared change ever destroys something a person owns. The ecosystem became something a team can extend, not something one technical person has to carry."*
