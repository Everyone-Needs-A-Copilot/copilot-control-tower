# Changelog

All notable changes to Copilot Control Tower are recorded here.

## [0.5.5] - 2026-08-04

### Added

- Control Tower now presents the Python-owned `cc reconcile` workflow end to end: complete Mac and project assessment, explicit project/component selection, exact plan review, guarded apply, fresh verification, durable diagnostic receipt, and interrupted-run recovery.
- Projects with no Copilot integration can receive independently recommended Claude and Codex setup routes. Customized, dirty, ambiguous, excluded, and unsafe projects retain distinct Python-authored routes and explanations instead of disappearing into overlapping totals.

### Changed

- The embedded helper is now `cc 2.6.0`, built from signed parentless foundation snapshot `v5.13.39` and accepted by Apple notarization. The app now requires `cc >=2.6.0,<3.0.0`.
- The old grouped `workspace migrate` presentation is replaced by the reconciliation schema `1.0` contract. This is a new versioned verb contract, not a breaking change to an existing reconciliation consumer; the app's declared schema compatibility remains `>=1.0,<2.0`.
- Project totals are one primary state per project. Claude and Codex outcomes remain independent within each project, with the overlap explanation authored by Python.

### Security

- Swift passes explicit intent through an owner-only temporary request and never inspects project files or invents operations. Python re-inspects before mutation, claims one fresh opaque plan, constrains paths, rejects unsafe symlinks, snapshots bounded targets, locks projects, verifies components independently, and records truthful per-target rollback outcomes.
- Reconciliation diagnostics use private `0700` directories and atomic `0600` records, retain a bounded history, and omit credentials, environment values, stdin, file contents, and raw subprocess streams.

### Rollback

- Reinstall the signed `0.5.4` DMG to return to the previous app and helper. A successful project reconciliation is intentionally not undone by reinstalling the app; its Python-authored receipt remains the authoritative record. Release tags are immutable, so a defective build is superseded with a new version.

## [0.5.2] - 2026-08-03

### Added

- The embedded helper now provides `cc workspace migrate --project PATH|--all --json`, a read-only migration census that separates guided projects into deterministic eligible actions, safety holds, and genuine project-specific exceptions.
- A reviewed plan can be applied with `--apply --plan-id <exact-id>`. The helper re-inspects immediately before each project, refuses stale plans and dirty Git trees, changes only enumerated integration paths, verifies each targeted component independently, and emits a per-project action ledger. Handled failures restore the exact prior files and link targets.

### Safety

- There is no model-driven master prompt and no force/skip mode. Recognized legacy Claude entries and linked Codex plugins are the only initial migration kinds; custom gates, unknown layouts, malformed evidence, source symlinks, and dirty projects remain unchanged.
- A live read-only census of the current 33 guided projects found 9 safely eligible, 7 held, and 17 requiring residual guidance. No live project migration was applied while preparing this release.

### Changed

- The embedded helper is now `cc 2.5.0`, built from signed parentless foundation snapshot `v5.13.35` and accepted by Apple notarization.

### Rollback

- Reinstall the signed `0.5.1` DMG to return to the previous release. Release tags are immutable; supersede a defective build with a new version.

## [0.5.1] - 2026-08-03

### Fixed

- Projects installed by earlier Copilot versions with a shared linked Codex plugin now receive a reviewed, preservation-aware migration route instead of the dead-end "could not verify" result. The helper proves the legacy link, bridge, optional gate, and readable lock shape before offering guidance; unknown links, arbitrary framework edits, malformed locks, and custom integrations still fail closed.
- Project diagnostics now describe legacy `installType: symlink` metadata accurately instead of saying the configuration failed to name its plugin.
- Convoco now classifies as guided integration with an actionable project-author plan. Across the current 62-project inventory, the source-helper result changes from 26 ready / 17 guided / 19 could not verify to 26 ready / 33 guided / 3 could not verify.

### Changed

- The embedded helper is now `cc 2.4.0`, built from signed parentless foundation snapshot `v5.13.34` and accepted by Apple notarization.

### Rollback

- Reinstall the signed `0.5.0` DMG to return to the previous release. Release tags are immutable; supersede a defective build with a new version.

## [0.5.0] - 2026-08-03

### Added

- The P1 visual refresh: a new native design system (`native/design-system.swift`) with a consistent type/state-color system, visible cards replacing flat rows across Settings and the wizard, and de-uppercased labels throughout.
- The Connect sheet: a secure in-app secret-entry flow reachable from any "Available to connect" row. Values are read from the person's typed input and passed to the new `cc connect <service-id> [--check] --json` verb over **stdin only** — never argv, never an environment variable, never a file — and written straight to the OS keychain by the CLI. Control Tower never sees, logs, or persists a secret value at any point. See [`schemas/connect.schema.json`](docs/01-architecture/schemas/connect.schema.json) and `cli-contract.md`.

### Changed

- The embedded helper requirement is now `cc 2.3.0`. This is the first app release to carry the `cc 2.2.1` connections-honesty fixes as well: a permanent false `needs-connect` state is fixed, and `store.detail` is now always a plain-language, `cc`-authored sentence instead of a raw passthrough of an underlying command's stderr (the raw text is still available for logs only, in the additive `store.diagnostic` field).

## [0.4.0] - 2026-08-02

### Added

- The connections bridge: Settings and the wizard's new step 6, "Your connections," render the organization's full roster of declared services with their real shared-credential-store connection state, closing the "Your connections" empty-state gap. The app calls the new `cc connections --json` verb (see [`schemas/connections.schema.json`](docs/01-architecture/schemas/connections.schema.json) and `cli-contract.md`) and filters purely on the CLI-computed `secret_state` (`ready` | `needs-connect` | `no-store`) — Control Tower never inspects a secret value or computes connection state itself.
- `cc connections --json` is CLI-side end to end: it shells `copilot --json layers` (now requiring cli-copilot foundation ≥v0.3.2, which carries `requires_secret`/`store_scope` per service) and presence-checks each service's hinted secret names against the organization's shared Infisical store with one `copilot infisical --json secret list` call per run. The secret-store onboarding stage is fixed to check against this same real Infisical identity surface instead of a stale placeholder.

### Changed

- The embedded helper requirement is now `cc 2.2.0` (0.3.2 shipped `cc 2.1.2`). This is the first app release to carry `cc 2.1.3`–`2.1.5` as well: `resolve --explain` correctly joins a layer's `source.subpath` onto explicit local paths (2.1.3); the never-destroy guard now holds a committed customization to a framework-owned project file rather than overwriting it (2.1.4); `fold` falls back to the newest verified layer when the range's nominal winner is blocked-unverified instead of failing outright (2.1.5).

### Fixed

- A phantom secret-store provisioner that could report a store as configured when it was not is closed (`cc 2.2.0`).

## [0.3.2] - 2026-08-01

### Changed

- The embedded helper requirement is now `cc 2.1.2` (0.3.1 shipped `cc 2.0.2`), carrying the never-destroy symlink/clean-repo guard (2.0.3), `knowledge-env list` plus `resolve`/`doctor` fixes (2.0.3), the department catalog and knowledge-skill routing surface (2.1.0), decoupled manifest writes plus pinned-ref signature verification (2.1.1), and the doctor severity gate plus cold-start mirror seeding fix (2.1.2).
- `docs/01-architecture/schemas/onboard.schema.json` gains an optional `materialize` field on `ecosystemReport` (`$defs.materializeSummary`/`materializeHeldItem`/`materializeBlockedItem`), re-synced from `claude-copilot/tools/cc/tests/fixtures/schemas/onboard.schema.json` where this shape had already shipped. This is a compatible, additive `schema_version` 2.0 minor addition, not a bump — see `cli-contract.md`'s versioning note. Unchanged again for `cc 2.1.2` (byte-identical to the fixture at that commit).

### Fixed

- Held/blocked materialize items are now surfaced honestly in the onboard report instead of being conflated with a failed transaction or omitted entirely.
- A warn-severity doctor result immediately after materialize no longer rolls back an already-verified manifest write; cold-start mirror seeding is corrected for the first-run case doctor was misreading as fatal.

### Rollback

- Reinstall the signed `0.3.1` DMG to return to the previous release. All of `0.3.0`, `0.3.1`, and `0.3.2` share the same schema `2.0` floor, so no `cc` downgrade is required for this rollback specifically. Release tags are immutable; supersede a defective build with a new version.

## [0.3.1] - 2026-08-01

### Fixed

- The onboard history classifier gains a ninth git-history state: a parentless foundation-snapshot pin whose tree is byte-identical to a clean checkout's `HEAD` now classifies `current`/`reuse` instead of the permanent `diverged-identical`/`review` state 0.3.0 could never clear for a foundation-tier repository. This closes the one review row 0.3.0's classifier fix could not reach (a repository pinned via an orphan-snapshot foundation tag, as opposed to an ordinary branch/tag).
- The embedded helper requirement is now `cc 2.0.2`.

### Rollback

- Reinstall the signed `0.3.0` DMG to return to the previous release. Both `0.3.0` and `0.3.1` share the same schema `2.0` floor, so no `cc` downgrade is required for this rollback specifically. Release tags are immutable; supersede a defective build with a new version.

## [0.3.0] - 2026-08-01

### Changed

- The embedded helper requirement is now `cc 2.0.1`.
- Onboard's `--json` contract moves to schema `2.0` (a breaking/MAJOR schema bump per the versioning policy): `layers_state` discriminates `reported` from `not-computed`, every `ecosystemLayer` row requires its topology fields, `completed_actions` is required, and resume is blocked-only. The app enforces this via a per-verb schema gate — onboard now requires schema major `2`, every other verb keeps the existing `1.x` floor.
- `controltower.compat.json`'s `cc` range moves to `2.0.0`–`<3.0.0` (previously `1.7.16`–`<2.0.0`); its `schema_version` range widens to `1.0`–`2.0`.

### Fixed

- The onboard history classifier only claims a clean fast-forward when a merge-base-proven ancestry check passes; the other seven git history states (dirty, ahead-only, diverged, diverged-identical-tree, wrong-origin, unreadable, exact) route to the person instead of being auto-repaired.
- Apply now asserts `HEAD == target` as a postcondition and reports "already at target" and "fast-forwarded" as distinct outcomes instead of collapsing into one.
- All deterministic preflight, including the history classifier, now runs before any irreversible GitHub write, so a blocked review row produces zero mutations instead of partially creating repositories first and blocking after.
- Annotated-tag pins (for example `cli-copilot @ v0.3.1`) now compare the peeled commit SHA rather than the tag object SHA, so a repository sitting exactly at a signed release tag classifies as current/reuse instead of misclassifying as diverged.
- A `completed_actions` ledger threads through every onboard exit path and every resume hint, so "nothing changed" is only ever a legal claim on an empty ledger, and the app renders that ledger honestly at every site that used to show a generic "nothing changed" message.
- Try again is now gated on whether the CLI reports the specific failure as retryable, instead of always being offered.

### QA

- Added a sixteen-row, eight-history-state packaged-binary topology gate (`scripts/tests/test_packaged_cc_topology_contract.sh`) that drives the exact packaged `cc` binary — never a mock — against a fully local git fixture and asserts zero mutation, schema validity, and source/packaged parity; `scripts/verify-vendored-cc.sh` runs the same live onboard probe in both placeholder and `--release` modes.

### Rollback

- Reinstall the signed `0.2.4` DMG to return to the previous release; a `0.3.0` fleet member must also fall back to a `cc` version below `2.0.0` since the onboard schema floor is not backward-compatible. Release tags are immutable; supersede a defective build with a new version.

## [0.2.4] - 2026-07-31

### Fixed

- Setup now includes active Department membership and plans the complete
  Foundation, Organization, Department, and Personal topology for Knowledge,
  CLI, Claude, and Codex.
- A GitHub repository or hidden mirror no longer counts as a visible, connected,
  synchronized layer. Personal repositories are created or downloaded into the
  visible Copilot repository folder.
- Returning Settings uses the same repository evidence and setup route as first
  launch instead of claiming remote-only Personal setup is Ready.
- Setup now blocks a Ready verdict when the connected topology resolves no
  effective capabilities, and moves superseded hidden Personal checkouts out
  of the active mirror tree without discarding their contents.
- The embedded helper now extracts through a dedicated Control Tower cache
  directory, avoiding startup stalls caused by an overloaded shared macOS
  temporary directory.

### Changed

- The duplicate roster, inventory, and rank list is replaced by four expandable
  component rows with per-layer repository names, visible locations, and exact
  keep/create/download/initialize/update actions.
- Setup can infer one existing component cluster or ask the person to choose a
  visible folder. Existing working trees and local changes are preserved; only
  clean fast-forwards are allowed.
- The embedded helper requirement is now `cc 1.7.16`.

### QA

- Added sixteen-layer, Department-entitlement, visible-root inference,
  non-empty-resolution, legacy-Personal migration, schema, native compile, and
  live read-only machine-plan coverage.

## [0.2.3] - 2026-07-31

### Fixed

- Existing installations now adopt the complete Knowledge, CLI, Claude, and
  Codex topology instead of leaving Knowledge absent and CLI incomplete.
- Knowledge and CLI Foundation and Organization status is backed by canonical
  Doctor evidence, so Control Tower no longer misses repositories merely
  because their managed layer identifiers use different names.
- A recognized eight-layer setup is repaired additively to twelve layers while
  preserving authored repositories and an exact rollback copy.

### Changed

- Knowledge and CLI are synchronized into product-owned read-only mirrors for
  their native consumers. Claude and Codex continue to use their own
  materialization roots.
- Settings renders Foundation, Organization, Department, and Personal from the
  helper's canonical tier role rather than guessing from layer names.
- Admin handoffs now publish Knowledge and CLI component refs alongside the
  selected Claude/Codex assistants.

### QA

- Added existing-machine migration, atomic pointer commit, product-isolated
  mirror, canonical role, rollback, and full four-component UI regressions.

### Rollback

- Reinstall the signed `0.2.2` DMG to return to the previous release. Release
  tags are immutable; supersede a defective build with a new version.

## [0.2.2] - 2026-07-31

### Fixed

- **Run in Codex** and **Run in Claude Code** now open a visible Terminal
  session in the selected project and start the installed assistant with the
  complete CLI-generated prompt.
- The app resolves each assistant to its absolute executable before opening
  Terminal, avoiding Finder/Terminal `PATH` differences.
- Terminal receives the command before it is brought forward, preventing a
  separate empty startup window from hiding the guided session.
- A missing project folder or denied Terminal automation permission now shows
  a specific recovery message while keeping the copied prompt available.

### Security

- The signed User app now carries the Apple Events entitlement and purpose
  string required by macOS to request Terminal automation permission. macOS
  still requires the person's approval; Control Tower gains no Accessibility
  or UI-scripting permission.
- Guided prompts remain data in owner-only temporary files, while executable,
  project, and prompt-file paths are shell-quoted. Independent `cc` project
  verification remains the only way to mark a project Ready.

### QA

- The release gate now rejects a signed app that lacks either the Terminal
  automation entitlement or its user-facing purpose string.
- In-binary regression coverage verifies absolute assistant invocation,
  project-directory handling, prompt-file safety, Terminal ordering, and
  actionable Apple Events denial handling.

### Rollback

- Reinstall the signed `0.2.1` DMG to return to the previous release. Tags are
  immutable; a defective `0.2.2` must be superseded, never moved.

## [0.2.1] - 2026-07-30

### Added

- A returning-person ecosystem view for Knowledge, CLI, Claude, and Codex,
  with expandable Foundation, Organization, Department, and Personal status.
- A direct “Finish Personal Setup” route when any required Personal space is
  missing or incomplete.
- Project aftercare category cards in the completed app that reopen the same
  focused Step 7 experience used during setup.

### Changed

- “Personal” is now the user-facing tier name throughout Control Tower.
  “Private” is shown only as the GitHub repository visibility that protects a
  Personal space.
- Project aftercare emphasizes that people can finish one or two projects and
  return later; setup no longer implies every project must be completed in one
  session.
- The embedded helper is now `cc 1.7.14`, and
  `controltower.compat.json` requires that exact minimum contract.

### Fixed

- Aggregate onboarding now provisions all four Personal spaces—Knowledge,
  CLI, Claude, and Codex—even when Claude and Codex are the selected assistant
  runtimes.
- The completed app no longer claims the ecosystem is ready when required
  Personal spaces are missing.
- The completed Projects section no longer collapses actionable projects into
  an unexplained “needs review” total.

### Rollback

- Reinstall the signed `0.2.0` DMG to return to the previous known-good build.
  Foundation and app tags are immutable; a defective `0.2.1` must be
  superseded, never moved.

## [0.2.0] - 2026-07-30

### Added

- Focused Step 7 project triage with expandable, searchable, paginated
  categories instead of one continuous project list.
- Clear Ready, guided setup, owner decision, and couldn't-confirm detail views
  with actionable next steps and explicit “finish later” guidance.
- Visible Terminal sessions for Codex and Claude Code guided setup, followed by
  independent helper verification.
- Helper-authored, read-only diagnostic routes for projects whose integration
  evidence cannot yet be confirmed.
- Persistent project aftercare access from the Control Tower menu so project
  setup does not have to be completed during initial onboarding.

### Changed

- The embedded helper is now `cc 1.7.13`, produced from signed foundation tag
  `v5.13.15` and pinned by SHA-256.
- `controltower.compat.json` now declares app `0.2.0` and raises the minimum
  supported helper version from `1.7.11` to `1.7.13`.
- The JSON `schema_version` remains `1.0`; the helper diagnostic field is
  additive and optional for backward-safe decoding.

### Fixed

- Assistant launch controls now open an observable Terminal workflow instead
  of appearing to do nothing.
- Couldn't-confirm projects now show the exact evidence received and the
  smallest safe diagnostic action instead of leaving the user without a route.

### Security

- Diagnostic prompts are explicitly read-only, temporary prompt files use
  owner-only permissions, and only authoritative `cc workspace verify` results
  can mark a project Ready.

### Rollback

- Reinstall the signed `0.1.9` DMG to return to the previous known-good build.
  Foundation and app tags are immutable; a defective `0.2.0` must be
  superseded, never moved.
