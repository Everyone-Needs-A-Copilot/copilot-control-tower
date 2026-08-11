# HANDOFF: Admin Mode / Native Prototype Build

**Audience:** a new developer picking up the native SwiftUI Admin-mode work on branch `app-build`.
**Verified against the repo on 2026-07-10.** Where a claim could not be verified it is marked
**[UNVERIFIED]**.

---

## TL;DR — where things stand

- This repo contains **two separate app codebases** (see below — read that section first, it is
  the biggest way to get lost here).
- The **native SwiftUI prototype** (`native/*.swift`) is the current design direction. It is a
  **local, unsigned, unpackaged prototype** for design review. Every screen renders **mocked
  data** — nothing is wired to a live CLI.
- The newest, largest piece of that prototype is **Admin mode** (`native/admin.swift`, ~2,185
  lines): an org-standup + governance UI (surfaces ADM-1..9 + governance G1..G3).
- **All Admin screens are temporarily unlocked for review** via a hardcoded flag
  (`native/admin.swift:63`, `allScreensUnlockedForReview = true`). This bypasses the real
  GitHub-connection gate. Flip it to `false` before this ships for real use.
- The real blocker for turning any of this into a working product is **WS-A**: the `copilot` CLI's
  versioned `--json`/`flock` contract. It is unstarted. Until it lands, the native app (and the
  Admin flow specifically) can only render mocks.
- **Nothing described here has been committed.** See "Current git state" below — this is all
  uncommitted/untracked work on `app-build`, awaiting owner approval to commit.

---

## Reading order

1. This file (orientation for the native/Admin-mode work specifically).
2. Root [`CLAUDE.md`](../CLAUDE.md) — the six architectural invariants that govern everything in
   this repo. Invariant #1 ("parse, never compute") is the one this build leans on hardest.
3. [`docs/10-reference/copilot-solutioning-ecosystem.md`](10-reference/copilot-solutioning-ecosystem.md)
   and [`docs/10-reference/cse-alignment-decisions.md`](10-reference/cse-alignment-decisions.md) — the
   canonical product model (see "Product model" below) and the decision record (D1-D10) that
   corrected the repo onto it.
4. [`docs/03-design/control-tower-admin-flow.md`](03-design/control-tower-admin-flow.md) — the
   flow spec `native/admin.swift` implements screen-for-screen.
5. [`docs/03-design/admin-agentic-setup.md`](03-design/admin-agentic-setup.md) — the spec for the
   agentic engine Admin mode is a face of (not yet built — see below).
6. [`docs/03-design/control-tower-copy-deck.md`](03-design/control-tower-copy-deck.md) — verbatim
   user-facing strings (Surface 3 = Admin).
7. [`docs/03-design/control-tower-visual-system.md`](03-design/control-tower-visual-system.md) —
   the "Quiet Instrument" visual language.
8. [`docs/03-design/control-tower-native-experience-architecture.md`](03-design/control-tower-native-experience-architecture.md)
   and [`control-tower-interaction-spec.md`](03-design/control-tower-interaction-spec.md) — broader
   native-app architecture/interaction rules.

**A caution on the older orientation docs:** [`docs/START-HERE.md`](START-HERE.md) and
[`docs/HANDOFF.md`](HANDOFF.md) still describe an earlier plan (Tauri v2 as *the* app, "app not
started," milestone-1 language). [`docs/RESUME-HERE.md`](RESUME-HERE.md) is more current — it
describes the Tauri app's 9-milestone build as complete and paused on Apple Developer approval —
but it predates the CSE realignment and the native-SwiftUI pivot described in this file, so it
does not mention `native/*.swift` at all. Treat all three as historical/partially stale; this file
and the `docs/03-design/` docs listed above are the current source of truth for the native/Admin
work.

---

## The two codebases (read this before touching any Swift file)

| | Tauri app | Native SwiftUI prototype |
|---|---|---|
| Location | `src-tauri/` (Rust + web UI) | `native/*.swift` |
| Status | Built (9 milestones, ~860 tests per `RESUME-HERE.md` [UNVERIFIED count]), **packaged, signed, notarized** | Local prototype, **not packaged, not signed, not notarized** |
| Distribution pipeline | `scripts/sign.sh` + notarization scripts target this | None yet |
| App icon | Lives here (`src-tauri/icons`) | N/A |
| Relationship to `CLAUDE.md` | Superseded per `CLAUDE.md` ("supersedes the prior Tauri v2 / web-UI plan") | The current direction |
| What this handoff covers | Not covered | Everything below |

`scripts/publisher_setup.swift` is a **third, separate artifact**: a standalone signed helper app
(the Publisher Setup app, ~2,345 lines) that the native prototype's Welcome screens and
roadmap-sidebar/`StepShell` grammar are modeled on. It is not part of either codebase above; it is
its own signed deliverable with its own runbook
([`docs/07-contributing/publisher-release-runbook.md`](07-contributing/publisher-release-runbook.md)).

**Do not** add Rust/Tauri code to fix something in `native/*.swift`, and do not add resolution/
sync/compute logic to either — that violates invariant #1 (parse-never-compute) and belongs in the
CLI (`copilot`/`cc` repo), not here.

---

## Product model (one paragraph)

Control Tower orchestrates the **Copilot Solutioning Ecosystem (CSE) tooling** — the
knowledge/CLI/Claude/Codex Copilot *components* — across four inheritance layers
(Foundation → Org → Department → Personal), entitled by GitHub repo access. It does **not** manage
the user's own products/projects. MDM was dropped completely as a mechanism (no `.mobileconfig`,
no forced-managed-domain, no fleet console). See
[`docs/10-reference/copilot-solutioning-ecosystem.md`](10-reference/copilot-solutioning-ecosystem.md) and
the decision record D1-D10 in
[`docs/10-reference/cse-alignment-decisions.md`](10-reference/cse-alignment-decisions.md).

---

## What's built in the native prototype

All of the below renders **mocked data only**. No file in `native/` makes a live `gh`/GitHub API
call or shells out to a real `copilot`/`cc` CLI verb.

### Tray + popover — `native/control-tower-tray.swift` (522 lines)

- `NSStatusItem` menu-bar app, `.accessory` activation policy.
- Menu-bar glyph is `AviatorGlyph` (defined `native/models.swift:326`) — **menu-bar icon only**.
- `NSPopover` with vibrancy, a component-currency tree, and a dev "Preview state" menu.
- Two dev/smoke-test launch hooks read from `ProcessInfo.processInfo.environment`:
  - `CT_OPEN_WIZARD=1` opens the first-run wizard directly (`control-tower-tray.swift:489`).
  - `CT_OPEN_ADMIN=1` opens Admin mode directly (`control-tower-tray.swift:497`).
- Tray right-click menu also has an "Open Administration..." entry (`control-tower-tray.swift:~458`
  onward) that is **always available** — see the ADM-0 entry-point open decision below.

### First-run wizard — `native/wizard.swift` (1,448 lines) + shared model code in `native/models.swift` (415 lines)

- `NavigationSplitView` roadmap sidebar + a reusable `StepShell` (eyebrow → title → intro → content
  → pinned footer action bar), explicitly modeled on `scripts/publisher_setup.swift`'s grammar.
- 8 phases plus a holding state: `welcome`, `detect`, `chooseComponents`, `departments`,
  `integrations`, `materialize`, `verify`, `done` (`native/wizard.swift:439-446`), plus a separate
  `.holding` phase.
- `ControlTowerGlyph` (`native/models.swift:382`) loads `docs/10-reference/control-tower.svg` as the
  in-app hero illustration — the code notes it is illegible below ~40pt, hence used only for large
  brand art, never the menu-bar icon.

### Admin mode — `native/admin.swift` (2,185 lines, the newest and largest piece)

- `AdminWelcomeView`, explicitly modeled on the Publisher Setup app's welcome screen.
- Two `NavigationSplitView` sections: **ONBOARDING** and **GOVERNANCE**
  (`native/admin.swift:50-53`).
- Onboarding surfaces (`AdminItem.onboarding`, `native/admin.swift:75-78`), matching ADM-1..9 in the
  flow spec: Prerequisites, Contacts, Connect GitHub (with a scope-refusal preflight),
  Repositories & teams, Secret store, Seed, Policy signers, Review & run, Preflight.
- Governance surfaces (`AdminItem.governance`, line 79): Add/offboard, Analytics, Secret store
  config.
- **Review & run (ADM-8)** streams a mocked ordered checklist. `AdminModel.runBootstrap()`
  (`native/admin.swift:704`) and `resolveOutcome(for:)` (line 676) use Swift structured concurrency
  (`Task { ... try? await Task.sleep(...) }`) to advance each step to one of three outcomes:
  Created / Already there / Nothing to redo. The file's own header comment (lines 18-33) is explicit
  that `resolveOutcome` and `computePreflightChecks` are mock stand-ins for what a real
  `copilot admin bootstrap --json` engine feed would send, and that the UI computes nothing beyond
  that mock.
- Opens via `CT_OPEN_ADMIN=1` at launch, or tray right-click → "Open Administration...".
- **`allScreensUnlockedForReview = true`** (`native/admin.swift:63`): a temporary override so every
  sidebar screen is reachable regardless of GitHub-connection state, for design review. The real
  gate (`AdminItem.requiresGitHubGate` / `AdminModel.githubGateOpen`) is untouched underneath —
  this flag just bypasses the one call site that reads it (`AdminSidebar.row(_:)`). **Flip to
  `false`** to restore real entitlement gating before this is used for anything but review.

### SwiftUI/AppKit safety discipline honored in this build

`native/admin.swift`'s own header comment calls out the constraint explicitly: no blocking
`Process`/file I/O runs during any `@State`/`@StateObject` `init()`. `AdminModel.init()` is the
implicit memberwise default; all mock "engine" work is scheduled from a user action via
`Task { ... }`, never from a property initializer. This is a direct lesson from a prior crash in
`scripts/publisher_setup.swift` (see Conventions section below).

---

## What's spec'd but NOT built: the agentic setup engine

The design (`docs/03-design/admin-agentic-setup.md`) calls for **one engine, three faces**:

1. A versioned `copilot admin bootstrap --json` CLI verb — lives beside `admin/seed.rs` in the
   `copilot`/`cc` CLI repo, **not this repo**. Not started.
2. An open-source `.claude/skills/admin-bootstrap/` skill — the same engine, runnable agentically
   from Claude Code/Codex. Not built.
3. The Admin-mode GUI described above — currently the only one of the three that exists, and it
   renders mocks because the other two don't exist yet.

The intended GitHub sequence (spec §1.3): create `copilot-org` → per-department
`copilot-dept-<unit>` repo + `<org>/<unit>` team + read/write grant (the grant *is* the
entitlement) + members → additive seed → fail-closed leak-scan → verify. Idempotent, additive,
never-destroy, and never touches the personal tier. Integration-per-layer means a layer declares
which integrations exist, carrying only `requires_secret: <NAME>` references, never keys; absence
of a declaration means non-existence, not "unconfigured."

---

## The big blocker: WS-A

The real CLI `--json`/`flock` contract — covering verbs like `copilot layers`, `doctor --json`,
the wizard's verbs, and `admin bootstrap` — is workstream WS-A in the `copilot` CLI repo (a
sibling repo, not this one). **It is unstarted/frozen as of this handoff.** Until it exists and its
schema is frozen, every screen in this native app (wizard and Admin alike) can only render mocked
data, by design and by invariant #1 (parse-never-compute) — the app must not grow its own
resolution/sync logic to compensate for the missing verb.

---

## What's real vs. mocked vs. unbuilt

| Layer | State |
|---|---|
| Tray + popover UI (`control-tower-tray.swift`) | Real UI, mocked component-currency data |
| First-run wizard UI (`wizard.swift`, `models.swift`) | Real UI, mocked detection/materialize/verify transitions |
| Admin-mode UI (`admin.swift`) | Real UI, mocked bootstrap run + preflight checks, GitHub gate bypassed for review |
| `copilot admin bootstrap --json` CLI verb | **Not built** (lives in the CLI repo, unstarted) |
| `.claude/skills/admin-bootstrap/` OSS skill | **Not built** |
| WS-A `--json`/`flock` contract (all verbs) | **Not built / unstarted / frozen** |
| Tauri app (`src-tauri/`) | Built, packaged, signed, notarized — but superseded as the design direction per `CLAUDE.md` |
| Native prototype packaging/signing/notarization | **Not done** — local build only |

---

## Build & run

```bash
scripts/control-tower-tray.command
```

What it does (verified against the script):
- Compiles `native/*.swift` together as one module (`swiftc native/*.swift -o .copilot/control-tower-tray/control-tower-tray`), rebuilding only if a source file is newer than the existing binary.
- Sets `CC=/usr/bin/cc PATH=/usr/bin:$PATH` before invoking `swiftc` — the `copilot` CLI is installed as `cc` on this machine and shadows the real C compiler; this avoids that collision for any linked C dependency.
- Runs the resulting binary as a menu-bar (`.accessory`) app.

Dev/smoke-test launch hooks:

```bash
CT_OPEN_WIZARD=1 scripts/control-tower-tray.command   # jump straight to the first-run wizard
CT_OPEN_ADMIN=1 scripts/control-tower-tray.command     # jump straight to Admin mode
```

---

## Current git state (branch `app-build`, verified 2026-07-10)

Local branch is 10 commits ahead of `origin/app-build` (unpushed, not part of this handoff's
scope).

**Uncommitted, not yet owner-approved:**

```
 M native/control-tower-tray.swift
 M scripts/control-tower-tray.command
?? docs/03-design/admin-agentic-setup.md
?? docs/03-design/control-tower-admin-flow.md
?? docs/03-design/control-tower-copy-deck.md
?? native/admin.swift
?? native/models.swift
?? native/wizard.swift
```

Note this is broader than "new design docs plus new native files" — `native/control-tower-tray.swift`
and `scripts/control-tower-tray.command` are **modified**, not just the three new files
(`admin.swift`, `models.swift`, `wizard.swift`) being untracked. Do not commit any of this until the
owner has reviewed it. This machine can run multiple concurrent Claude/Codex sessions against the
same repo tree (a documented hazard in project memory — "bridge-session-collision"); confirm no
sibling session is mid-write to any of these files before staging/committing.

---

## Open decisions a new developer will hit

From `docs/03-design/admin-agentic-setup.md` §5 and `docs/03-design/control-tower-admin-flow.md`
§14 (left open by design, not resolved by this build):

1. **Interim engine home.** Ship a vetted idempotent `scripts/admin_bootstrap.sh` (`gh` script) as
   the real engine now, pre-WS-A, migrating into `copilot admin bootstrap --json` at freeze — or
   wait for the upstream verb before shipping any real automation?
2. **WS-A scope.** Fold `admin bootstrap [--add-department] [--verify] --json` into upstream WS-A
   scope alongside `publish`/`layers`, or keep it control-tower-originated?
3. **`admin:org` acquisition.** Teach `gh auth refresh -s admin:org` on the admin's own PAT, or
   stand up a GitHub App with fine-grained org-admin permissions (avoids a broad user PAT; adds
   custody of an App private key, which the shared secret store would need to home)? This directly
   changes ADM-3's refusal/fix copy and flow.
4. **Fresh-repo seed delivery.** On an empty `copilot-org`, do an initial commit then enable branch
   protection after (additive, since the repo is empty), switching to PR-only once the repo carries
   content — or PR-only from the start (which is chicken-and-egg on an empty repo's
   branch/CODEOWNERS)?
5. **Integration classification.** Which integrations the seed may declare as shared-store-backed
   vs. must-stay-personal (e.g. Salesforce/M365 are shareable; anything acting as an individual
   identity must stay per-user)? This decides whether ADM-4's integration `id` field is a
   constrained picker (safer) or free text (guarded only by the secret-shape refusal).
6. **Admin entry point (`admin_capable` path 2a vs 2b).** First-run opt-in ("I'm setting this up
   for my organization") vs. always-available (every unmanaged user is their own admin)? **This
   build has ratified "always-available"** (`native/control-tower-tray.swift:~428`, comment cites
   this as "open decision 6" resolved as path 2b) — but the design docs still list it as open for
   the owner to confirm.

Additionally, flagged in the copy deck (`docs/03-design/control-tower-copy-deck.md:192-197,602`):
the pinned, un-dismissable security banner's exact wording/affordance needs an owner/UXD pass,
because rendering a security event as a decision for the end user ("Bob") is explicitly flagged as
possibly not a Bob-level decision at all — routed to UXD, not resolved in this build.

---

## Conventions and lessons (do not regress these)

- **No em-dashes in user-facing copy.** Owner requirement, stated explicitly in the copy deck
  (`control-tower-copy-deck.md:25`): periods, commas, colons, and parentheses only.
- **Never run `Process`/blocking I/O in a SwiftUI model's `init()` or during first layout.** A prior
  crash in `scripts/publisher_setup.swift` was caused by exactly this (SwiftUI AttributeGraph abort
  on launch). Defer such work to `.task {}` or a background queue, and deliver results on
  `@MainActor`. `native/admin.swift`'s header comment documents this discipline explicitly for its
  own `Task { }`-based mock engine.
- **`AviatorGlyph` is menu-bar only.** The `ControlTowerGlyph` illustration is the in-app brand
  image; it is illegible below ~40pt, so it's used only for large hero art, never the tray icon.
- **Invoke the CLI by absolute, translocation-safe path — never bare `copilot`.** A bare `copilot`
  collides with `gh copilot`. The CLI is installed on this machine as `cc`, which shadows the real C
  compiler, so any cargo/swiftc build that needs a C toolchain (in the CLI repo or here) requires
  `CC=/usr/bin/cc PATH=/usr/bin:$PATH` — already applied in `scripts/control-tower-tray.command`.
- **Check for concurrent sessions before committing.** This machine runs multiple concurrent
  Claude/Codex sessions in the same repo tree; `native/*.swift` files are currently untracked, so a
  sibling session could be mid-write. Verify before staging.

---

## Suggested next steps (options, not a sequence — no time estimates implied)

1. Commit the current uncommitted batch once the owner has reviewed and approved it.
2. Build the OSS `.claude/skills/admin-bootstrap/` skill plus an interim
   `scripts/admin_bootstrap.sh`, so the agentic setup path is real before the CLI verb exists
   (resolves open decision 1 in the "ship now" direction).
3. Resolve the open decisions listed above with the owner (particularly #3, since it changes
   ADM-3's flow directly, and the security-banner copy flagged for UXD).
4. When WS-A lands and its schema is frozen, replace the mocked feeds in `wizard.swift` and
   `admin.swift` with the real `--json` verbs — the mock functions (`resolveOutcome`,
   `computePreflightChecks` in `admin.swift`, and the equivalent transition mocks in
   `wizard.swift`) are the explicitly-flagged seams to replace.
5. Restore `allScreensUnlockedForReview = false` in `native/admin.swift` before this is used for
   anything beyond design review, to reinstate the real GitHub-connection gate.
6. Fold the copy deck (`control-tower-copy-deck.md`) verbatim strings into the wizard and Admin UI
   where they are not already exact matches.
7. Eventually reconcile the native prototype into a packaged, signed, notarized artifact — only the
   Tauri build (`src-tauri/`) has a working distribution pipeline (`scripts/sign.sh` +
   notarization) today.
