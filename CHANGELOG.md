# Changelog

All notable changes to Copilot Control Tower are recorded here.

## [0.6.9] - 2026-08-12

### Added

- The native User app now carries and activates one per-user crash-only
  LaunchAgent. Unsuccessful termination is restarted; an intentional Quit
  exits successfully and remains stopped until the person opens the app again.
- The signed bundle includes explicit install and uninstall lifecycle commands.
  Both operate only in the current user's `gui/$UID` launchd domain and never
  require administrator access.

### Safety

- `KeepAlive` is a dictionary containing only `SuccessfulExit=false`;
  `RunAtLoad=false` remains separate from login-item registration. A real
  launchd regression test covers clean exit, repeated crash restart, and
  complete uninstall.
- Automatic registration is limited to the trusted production-signed User app
  at `/Applications/Copilot Control Tower.app`. Development, Admin, headless,
  visual, copied-candidate, and selftest launches do not change LaunchAgents.
- The canonical macOS icon now lives in the active native packaging tree.
  Shipping build scripts no longer read the retired Tauri source tree.

### Changed

- The app and Admin bundle are version `0.6.9` build `36`. The release
  candidate continues to require and bundle exactly `cc 2.10.2`;
  `controltower.compat.json` declares `cc >=2.10.2,<3.0.0`.

### Rollback

- Uninstall crash recovery with the signed app's bundled
  `uninstall-watchdog.sh`, then reinstall the signed `0.6.8` DMG,
  `Copilot-Control-Tower_0.6.8_arm64.dmg`. Reinstalling changes only the
  app/helper and supervision registration; it does not alter project work,
  Copilot repositories, or saved diagnostic reports.

## [0.6.8] - 2026-08-06

### Fixed

- Verify no longer pauses when healthy Foundation repositories use signed,
  annotated release tags backed by disconnected parentless snapshot commits.
  The Python helper now peels annotated tags and proves snapshot currency from
  the declared tag, exact remote commit, parentless snapshot shape, and an
  identical full Git tree.
- Knowledge Copilot and CLI Copilot now compare against their peeled release
  commits instead of annotated tag objects. Claude Copilot and Codex Copilot
  preserve their unequal authoring/snapshot commit identities while reporting
  the proven content match honestly.

### Safety

- This is a Python/helper correction; Swift remains a display and orchestration
  layer and no Swift source changed. `cc doctor` remains read-only.
- The exception is Foundation-only and fails closed for branches, lightweight
  tags, ordinary history tags, missing refs, different trees, or any remote
  commit mismatch. Update symlink guards, target allowlists, GitHub permission
  evidence, and download-only shared setup are unchanged.

### Changed

- The app and Admin bundle are version `0.6.8` build `35`. The release requires
  and bundles exactly `cc 2.10.2`, built from signed parentless Foundation
  snapshot `v5.13.55`; `controltower.compat.json` declares
  `cc >=2.10.2,<3.0.0`.

### Rollback

- Reinstall the signed `0.6.7` DMG,
  `Copilot-Control-Tower_0.6.7_arm64.dmg`, to return to bundled `cc 2.10.0`.
  Reinstalling changes only the app/helper version; it does not alter project
  work, Copilot repositories, or saved diagnostic reports.

## [0.6.7] - 2026-08-06

### Added

- Step 7 now begins with active preparation instead of a passive assessment. Control Tower asks the helper to create local checkpoint commits for eligible dirty Product projects, download clean fast-forward updates for shared Foundation, Internal, and Department Copilot repositories, and then return one fresh assessment.
- The preparation card reports exactly how many projects were saved locally, how many shared updates were downloaded, and which conditions still need attention. It says explicitly that nothing is pushed and that shared setup is download-only.
- GitHub repository permission is now typed evidence: `READ`, `TRIAGE`, and unknown remain read-only; `WRITE`, `MAINTAIN`, and `ADMIN` prove only that a separate governed authoring workflow could be allowed. Setup never becomes a publishing workflow.

### Changed

- Misleading copy such as **No projects can be changed safely right now**, **Protected work**, and **Left unchanged to protect your work** is replaced with the outcome of the work Control Tower actually performed and a narrower **Needs your attention** section for genuine unresolved conditions.
- Product checkpointing includes tracked and untracked non-ignored work in one local commit, preserves configured Git identity and signing, and restores the exact prior index if the commit fails. Repository hooks and filesystem-monitor hooks are disabled for the unattended operation so a discovered project cannot execute arbitrary hook code during setup.
- Ecosystem repositories are never checkpointed. Dirty, ahead, divergent, detached, wrong-origin, or unreadable shared checkouts remain unchanged; only clean merge-base-proven fast-forwards are allowed and verified against the fetched target.
- The app and Admin bundle are version `0.6.7` build `34`. The release requires and bundles exactly `cc 2.10.0`, built from signed parentless Foundation snapshot `v5.13.53`; `controltower.compat.json` declares `cc >=2.10.0,<3.0.0`.

### Rollback

- Reinstall the signed `0.6.6` DMG, `Copilot-Control-Tower_0.6.6_arm64.dmg`, to return to the passive Step 7 assessment and bundled `cc 2.9.2`. Local checkpoint commits and completed shared fast-forwards are ordinary Git history and are not removed by reinstalling the app.

## [0.6.6] - 2026-08-06

### Fixed

- Verify now preserves the evidence from its exact check-update-check attempt instead of reducing a paused result to the app version, helper path, report format, and timestamp. The new support report identifies each non-ready product and layer role, records whether the update changed, held, or blocked work, and shows the fresh post-update result.
- The report is intentionally safe to paste into Claude Code, Codex, or a support conversation. It is built from a closed set of typed fields and omits host, account, organization and project names, paths, repository addresses, layer IDs, file content, process output, environment values, commit IDs, and secrets.
- Control Tower saves up to 20 reports under `~/.claude/cc/diagnostics/control-tower/` with owner-only directory and file permissions, offers **Show in Finder**, and keeps **Copy support report** available if safe persistence is unavailable. Symlinked or untrusted storage is refused.
- The bundled helper includes the `codex-portable-copy-v1` migration fix for projects that do not already have a `scripts/` directory. Failed migrations also remove only the empty directories they created during rollback.

### Changed

- Repeated Verify pauses now say **The latest check reached the same result.** The app no longer claims that nothing changed without ledger evidence.
- Native smoke checks now exercise the User and Admin models without ordering windows onscreen, and install-artifact verification detaches the DMG before executing its helper. Release QA no longer flashes the app repeatedly or causes macOS removable-volume permission prompts.
- The app and Admin bundle are version `0.6.6` build `33`. The release requires and bundles exactly `cc 2.9.2`, built from signed parentless Foundation snapshot `v5.13.52`; `controltower.compat.json` declares `cc >=2.9.2,<3.0.0`.

### Rollback

- Reinstall the signed `0.6.5` DMG, `Copilot-Control-Tower_0.6.5_arm64.dmg`, to return to the previous Verify support surface and bundled `cc 2.9.1`. Reinstalling changes the app/helper version only and does not alter any Copilot checkout, saved diagnostic report, or project content. Release tags are immutable, so a defective build is superseded with a new version.

## [0.6.5] - 2026-08-06

### Changed

- Project integration is now a user-controlled handoff. Control Tower writes one Python-authored work order for the complete selected batch, opens a normal Terminal at the Sites/projects folder, and stops there. It does not start Claude Code or Codex, paste a prompt, create per-project sessions, watch a process, or show assistant progress it cannot actually know.
- The project screen gives the person four plain steps: start `codex` or `claude` in the Terminal, copy the displayed Python-authored prompt, paste it into that conversation, and keep talking to the assistant until the work is resolved. The prompt points to the exact private instruction file, which contains the project list, evidence, preservation rules, allowed changes, stop conditions, and exact Python verification commands.
- The person explicitly chooses **Check the projects** when ready. Control Tower then asks Python to verify the complete batch and shows the real remaining reasons. Individual project details no longer contain actions that auto-launch an assistant inside that repository.
- The app and Admin bundle are version `0.6.5` build `32`. The release requires and bundles exactly `cc 2.9.1`, built from signed parentless Foundation snapshot `v5.13.51`; `controltower.compat.json` declares `cc >=2.9.1,<3.0.0`. Reconciliation response schema remains `2.0`; guide reports now require the additive `start_prompt` handoff field.

### Safety

- Python still owns selection, work-order content, project checks, final verification, and every Ready/remaining verdict. A conversation or assistant statement is never proof.
- The Terminal command is exactly one quoted `cd` to Python's returned workspace root. No assistant executable, instruction content, helper command, project path, or prompt is passed on the command line.
- Existing project work and project-specific instructions remain protected by the work order. Copilot ecosystem repositories, dirty or held projects, unsafe paths, ambiguous states, and owner-only decisions remain outside unauthorized changes.

### Rollback

- Reinstall the signed `0.6.4` DMG, `Copilot-Control-Tower_0.6.4_arm64.dmg`, to return to the prior auto-launched conversation behavior and bundled `cc 2.9.0`. Reinstalling changes the app/helper version only and does not alter any Copilot checkout or project content. Release tags are immutable, so a defective build is superseded with a new version.

## [0.6.4] - 2026-08-06

### Changed

- Project setup now opens one Codex or Claude Code conversation for the complete selected batch. Control Tower writes one Python-authored instruction package in the projects folder, opens Terminal at the right location, supplies the instructions automatically, and lets the person ask questions in that same conversation while it works through every selected project.
- The work order names the exact project paths, component requirements, current evidence, preservation rules, allowed targets, stop conditions, and Python verification commands. The assistant is not asked to invent what “done” means, and the person is never sent into one session per project.
- The project screen now shows live Python-owned progress: selected, freshly verified, remaining, and the last checked project. A stopped or lost watcher becomes an explicit state with a concrete action instead of an unexplained spinner.
- Final results show one status and the real current reasons for every project. Successful copy feedback is displayed as a normal confirmation rather than an orange failure, and a person can reopen the same work order in either assistant or run a fresh final check.
- The Verify step now actually installs an available helper update and then calls `doctor` again. Setup can finish only when that second independent check reports healthy, which fixes the prior “An update is ready” pause that promised an install without performing one.
- The app and Admin bundle are version `0.6.4` build `31`. The release requires and bundles exactly `cc 2.9.0`, built from signed parentless Foundation snapshot `v5.13.50`; `controltower.compat.json` declares `cc >=2.9.0,<3.0.0`.

### Safety

- Python re-assesses the exact batch before writing its work order and remains the only authority that can mark a project ready. Assistant output and Terminal process state are never treated as proof.
- Knowledge Copilot, Claude Copilot, Codex Copilot, CLI Copilot, and every other proven ecosystem repository remain managed separately. Dirty, held, unsafe, ambiguous, or owner-decision projects are excluded rather than handed to the assistant.
- Only workspace roots that contain selected projects are opened to the assistant. With nested approved roots, Python selects the narrowest containing root. The instruction and project files are private, immutable, fingerprinted, and bound to the saved batch.
- The guided conversation may not commit, push, reset, clean, stash, delete unrelated files, alter dirty projects, or place credentials in a project. Project-owned instructions and integration behavior must be inspected and preserved.
- Publisher automation now recognizes that `notarytool` profiles live in the macOS Data Protection Keychain, retries only transient local profile-lookup failures before and during notarization, and never describes one failed lookup as proof that credentials were deleted. Remote authentication rejection and every other notarization failure still fail closed.

### Rollback

- Reinstall the signed `0.6.3` DMG, `Copilot-Control-Tower_0.6.3_arm64.dmg`, to return to the prior app and bundled `cc 2.8.0`. Reinstalling changes the app/helper version only and does not alter any Copilot checkout or project content. Release tags are immutable, so a defective build is superseded with a new version.

## [0.6.3] - 2026-08-05

### Changed

- The project review now separates ordinary product projects from Knowledge Copilot, Claude Copilot, Codex Copilot, CLI Copilot, and other proven Copilot ecosystem repositories. Ecosystem repositories are counted as **managed separately** and are never offered project-level integration work.
- The review summary now states exactly what each total means: automatic proposals, Claude-assisted proposals, managed-separately repositories, and projects left unchanged. Every unchanged reason is shown as its own Python-authored bucket, and every affected project remains visible with its reason and next action.
- Component selection is exact per project. A proposal can target Claude Copilot only, Codex Copilot only, or both, based solely on Python's verified recommendation; Swift can remove a whole project from the batch but cannot add components or widen the route.
- Claude Code preparation now displays Python-authored stages and liveness. A spinner appears only while work is active or waiting; stale work becomes a static warning with a concrete next step instead of spinning indefinitely.
- The app and Admin bundle are version `0.6.3` build `30`. The release requires and bundles exactly `cc 2.8.0`, built from signed parentless Foundation snapshot `v5.13.48` and accepted by Apple notarization; `controltower.compat.json` now declares `cc >=2.8.0,<3.0.0`.
- Reconciliation responses move from schema `1.0` to `2.0`; private selection requests remain schema `1.0`. The app gates reconciliation on response major `2` and continues to treat Python as the sole owner of scope, eligibility, counts, explanations, progress, planning, mutation, rollback, and verification.

### Safety

- Assessment and assistant preparation remain read-only. Dirty worktrees, detached heads, unreadable repositories, missing authoritative sources, owner decisions, customized projects without an approved bounded route, and any other unproven state remain unchanged and are surfaced with their exact reason.
- Scope classification fails closed. A repository is excluded from project integration only when Python proves it is part of the Copilot ecosystem; an unfamiliar name or path is not enough.

### Rollback

- Reinstall the signed `0.6.2` DMG, `Copilot-Control-Tower_0.6.2_arm64.dmg`, to return to the previous app and bundled `cc 2.7.3`. Reinstalling changes the app/helper version only and does not alter any Copilot checkout or project content. Release tags are immutable, so a defective build is superseded with a new version.

## [0.6.2] - 2026-08-05

### Fixed

- A clean Claude Copilot authoring checkout no longer appears as **Foundation — Needs review** merely because release tooling or metadata outside the active `.claude` payload differs from the parentless Foundation snapshot. Control Tower still leaves the checkout untouched; the bundled helper now proves that the exact Copilot content in use matches the current release and reports the layer as current.
- The exception is intentionally narrow. A dirty checkout, wrong origin, missing or changed `.claude` content, unreadable repository, non-parentless divergent history, or any other unproven state still fails closed and remains visible for review.

### Changed

- The app and Admin bundle are version `0.6.2` build `29`. The release requires and bundles exactly `cc 2.7.3`, built from signed parentless Foundation snapshot `v5.13.45` and accepted by Apple notarization; `controltower.compat.json` now declares `cc >=2.7.3,<3.0.0`.
- The Swift app and onboarding schema are unchanged. The fix remains in the Python-owned history classifier so Control Tower continues to render the helper's proven state instead of computing repository truth itself.

### Rollback

- Reinstall the signed `0.6.1` DMG, `Copilot-Control-Tower_0.6.1_arm64.dmg`, to return to the prior app and bundled `cc 2.7.2`. Reinstalling changes the app/helper version only and does not alter any Copilot checkout or project content. Release tags are immutable, so a defective build is superseded with a new version.

## [0.6.1] - 2026-08-05

### Security

- The `CT_CLI_PATH` environment override can no longer redirect a signed release build to an unverified `cc` binary. A compiled-in trust root now requires any override to carry the same Developer ID signature the app itself is released under, verified fresh against the file's own embedded signature on every resolution. Ad-hoc-signed development and test builds are unaffected, so the override remains a working development seam. This closes a gap present in `0.6.0`, in which a local attacker able to set the app's process environment could have redirected every helper invocation, including the Terminal-launched reconciliation assistant.
- The bundled helper no longer lets `PATH` ordering decide which `claude` executable it invokes. Resolution now consults an explicit override, then a closed registry of known install locations, and only consults `PATH` as a last resort when nothing earlier matches; a `PATH` result can never preempt a known location, and every candidate is still subject to the existing ownership and permission checks. When no trustworthy executable can be resolved, bounded preparation refuses cleanly and the deterministic reconciliation route remains available.

### Changed

- The app and Admin bundle are version `0.6.1` build `28`. The release requires and bundles exactly `cc 2.7.2`; `controltower.compat.json` now declares `cc >=2.7.2,<3.0.0`.
- Reconciliation remains schema `1.0` with the declared range `>=1.0,<2.0`. There are no contract or behavior changes beyond the two security fixes above.

## [0.6.0] - 2026-08-04

### Added

- **Resolve with Claude Code** extends the default-all project workflow to customized projects that Python has explicitly authorized for bounded preparation. One action creates a private expiring helper session, opens one visible Terminal session, waits for Python-validated results, and converges on the existing exact-plan review, explicit apply confirmation, receipt, and fresh verification flow.
- The project summary now counts every authorized route as either a new setup or a correction while separately identifying work Control Tower can handle directly, work prepared with Claude Code, projects already ready, and projects held unchanged. Individual project opt-out remains available; Claude Copilot and Codex Copilot remain universal for every selected project.
- The reconciliation contract adds `assistant-prepare`, `assistant-run`, and `assistant-status` reports, Python-authored `assistant_selection` and `resolution_summary` assessment fields, and an opaque `assistant_proposal_id` on the otherwise unchanged exact request.

### Changed

- The app and Admin bundle are version `0.6.0` build `27`. The release requires and bundles exactly `cc 2.7.0`; `controltower.compat.json` now declares `cc >=2.7.0,<3.0.0`.
- Reconciliation remains schema `1.0`, and the declared schema range remains `>=1.0,<2.0`. The assistant reports and assessment fields are additive to that contract; the higher helper floor ensures the app never offers this workflow against a helper that lacks them.

### Security

- Terminal receives only the exact bundled `cc` executable plus `reconcile assistant-run --session-id <opaque-id>`. It receives no project path, copied prompt, proposal content, patch, or free-form instruction.
- Claude Code runs in a private helper-owned working directory with a constrained environment, safe/plan-only settings, no tools, no project filesystem access, and no session persistence. It can return only one offered opaque candidate identifier per Python-authored project/component group. Unknown, repeated, incomplete, malformed, oversized, stale, expired, concurrently claimed, or content-bearing output is rejected without changing a project.
- Python binds a validated selection to one expiring proposal, attaches only its opaque identifier to the exact selected request, re-inspects before planning and applying, and remains the sole planner, project writer, rollback authority, and verifier.

### Rollback

- Reinstall the signed `0.5.6` DMG, `Copilot-Control-Tower_0.5.6_arm64.dmg`, to return to the previous app and bundled `cc 2.6.1`. Reinstalling an app changes the app/helper version only: it does **not** undo project changes that were already reviewed and applied. Retain the Python-authored receipt and resolve any desired project-content reversal separately. Release tags are immutable, so a defective build is superseded with a new version.

## [0.5.6] - 2026-08-04

### Changed

- Project setup now starts with every project that can be handled safely already selected. The screen says how many are new setups and how many need correction, quietly acknowledges projects that are already ready, and keeps projects requiring a judgment outside the automatic batch.
- Claude Copilot and Codex Copilot are now one universal project setup choice. A selected project always receives both; there are no separate product or recipe controls. People who do not want the full safe batch can switch to individual project selection and use Select all or Select none.
- Repeated “Machine readiness” instructions are replaced by one plain-language Mac status and next step. The primary action remains visible as “Review changes for N projects,” after which the exact Python-authored plan must still be reviewed and approved before anything changes.
- The embedded helper is now `cc 2.6.1`, built from signed parentless foundation snapshot `v5.13.40` and accepted by Apple notarization. The app now requires `cc >=2.6.1,<3.0.0`; reconciliation schema compatibility remains `>=1.0,<2.0`.

### Safety

- The automatic batch is authored entirely by Python after a second assessment with both copilots selected. Dirty, held, excluded, ambiguous, owner-dependent, missing-source, multi-recipe, and unverifiable projects are never selected automatically. Swift can only remove projects from that safe list; it cannot add an ineligible project or alter Python’s component and recipe bindings.

### Rollback

- Reinstall the signed `0.5.5` DMG to return to the previous selection screen and helper. Project changes already approved and verified are not undone by reinstalling the app. Release tags are immutable, so a defective build is superseded with a new version.

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
