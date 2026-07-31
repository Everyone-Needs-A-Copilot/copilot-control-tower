# Phase 6 — Control Tower 0.2.4 live setup blocker handoff

Status: **Blocked on a confirmed cross-repository transaction defect**

Date: 2026-07-31

Owner: Pablo Alejo

Pickup task: `tc` 203

Parent task: `tc` 202

App repository: `copilot-control-tower`, branch `app-build`

Helper repository: `claude-copilot`, branch `feat/adopt-and-project-setup`

## Purpose

This is the current pickup document for the ENAC self-onboarding initiative.
It supersedes the completion claim in
[`phase-6-project-integration-aftercare-handoff.md`](phase-6-project-integration-aftercare-handoff.md).
Control Tower 0.2.4 shipped the intended visible sixteen-layer experience, but
the first owner-run apply stopped on `cli-copilot` after making earlier remote
changes. Do not treat 0.2.4 as live-setup complete.

The next developer's job is to make setup safely recover from the exact state
recorded here, prove source and packaged-helper parity, complete the sixteen
visible layers, and publish new immutable helper and app releases.

## Immediate safety instruction

**Do not click “Try again” and do not run `cc onboard --apply` on this Mac until
the transaction is fixed and its read-only plan has been reviewed.** The same
history shape will block again, and 0.2.4 has already demonstrated that it can
make remote changes before reporting this blocker.

Do not reset, clean, switch, merge, or otherwise rewrite any existing Copilot
repository to get past the failure. In particular, preserve:

- `/Volumes/Dev/Sites/COPILOT/cli-copilot`;
- `/Volumes/Dev/Sites/COPILOT/knowledge-copilot`;
- all other visible component working trees;
- the active manifest and hidden mirrors until the repaired transaction has
  verified its replacement topology.

## What Pablo is trying to accomplish

The target is one visible repository family under
`/Volumes/Dev/Sites/COPILOT`, covering four components and four entitled layers:

| Component | Foundation | Organization | Accounting | Personal |
|---|---|---|---|---|
| Knowledge | `knowledge-copilot` | `knowledge-copilot-internal` | `knowledge-copilot-accounting` | `knowledge-copilot-private` |
| CLI | `cli-copilot` | `cli-copilot-internal` | `cli-copilot-accounting` | `cli-copilot-private` |
| Claude | `claude-copilot` | `claude-copilot-internal` | `claude-copilot-accounting` | `claude-copilot-private` |
| Codex | `codex-copilot` | `codex-copilot-internal` | `codex-copilot-accounting` | `codex-copilot-private` |

Personal repositories are private on GitHub but visibly checked out beside the
other repositories. A hidden mirror may be a disposable runtime cache, but it
cannot satisfy visible presence or readiness. Existing authored repositories
must be preserved. Control Tower should do the technical work, explain the
result plainly, and independently verify it before showing Ready.

The person may finish ecosystem setup without completing every downstream
project. Project aftercare must remain available from Settings later.

## Installed release and observed failure

The owner installed the published release and selected setup:

```text
Copilot Control Tower 0.2.4 (15)
Setup helper: /Applications/Copilot Control Tower.app/Contents/Resources/cc
Report format: 1.0
Step: visible-repositories
Result: blocked
Message: /Volumes/Dev/Sites/COPILOT/cli-copilot could not be fast-forwarded
safely; local work was preserved.
Recorded: 2026-07-31 14:28
```

The screen also said setup stopped “before changing anything.” That statement
is false for this run; see the transaction-order evidence below.

## Confirmed diagnosis

### 1. The checkout is clean, but its history is not a fast-forward

`cli-copilot` is not dirty:

```text
branch: hotfix/schema-mismatch-v0.3.1
HEAD:   949f37846cf5993766d3726a1f7fbbd4dbec6b45
tracks: origin/hotfix/schema-mismatch-v0.3.1 at the same commit
status: clean
```

The helper resolves the Foundation range `^0.3.0` to signed tag `v0.3.1`:

```text
v0.3.1 commit: 48cbcf5055e4b6200e5864ddecc666f96c27bf31
local vs tag:  1 commit ahead, 1 commit behind
```

The two commits have **the exact same Git tree**:

```text
local tree: e4922c5f562eed5f948959d330c06f1840264703
tag tree:   e4922c5f562eed5f948959d330c06f1840264703
```

This is a PR/hotfix history-shape difference, not different file content and
not uncommitted local work.

### 2. The planner claimed a safe repair without testing ancestry

In `claude-copilot/tools/cc/src/cc/commands/onboard.py`:

- `_topology_report_layers` calls a clean checkout `behind`/`repair` whenever
  local HEAD differs from the target remote SHA. It does not prove that local
  HEAD is an ancestor of the target.
- `_apply_visible_topology` later fetches and runs
  `git merge --ff-only FETCH_HEAD`.
- The merge correctly fails for the 1-ahead/1-behind history above.

The apply-time safety stop is correct. The plan-time classification is not. A
plan must never promise “a clean fast-forward is available” without proving the
ancestry condition the apply will enforce.

### 3. The transaction made remote changes before this precondition failed

Before `_apply_visible_topology`, `build_ecosystem_onboard_report` runs the
Personal apply. The owner-run transaction created and seeded two repositories:

| Repository | Created UTC | Evidence after failure |
|---|---:|---|
| `pablitoalejo/knowledge-copilot-private` | 2026-07-31 18:27:55 | private, `main`, contains `copilot.layer.yml` |
| `pablitoalejo/cli-copilot-private` | 2026-07-31 18:27:57 | private, `main`, contains `copilot.layer.yml` |

Those timestamps are immediately before the 14:28 local failure. Before this
run, the read-only diagnostic reported both repositories missing. They now
exist, while their intended visible checkouts are still absent:

```text
missing /Volumes/Dev/Sites/COPILOT/knowledge-copilot-private
missing /Volumes/Dev/Sites/COPILOT/cli-copilot-private
```

The active manifest was not changed. It is still the eight-layer manifest from
2026-07-30 14:51 local time, containing CLI, Claude, and Codex entries but no
Knowledge entries and no Accounting entries.

This means the transaction is partially applied even though the UI says nothing
was changed. Re-running the current release now sees all four Personal GitHub
repositories as existing, which hides the fact that two were created by the
failed attempt.

### 4. Current visible state remains 7 of 16

Present visible checkouts:

- all four Foundation repositories;
- Knowledge and CLI Organization repositories;
- Claude Personal.

Missing visible checkouts:

- Claude and Codex Organization;
- all four Accounting repositories;
- Knowledge, CLI, and Codex Personal.

The new Knowledge and CLI Personal remotes should now plan as downloads, not
creates. No live recovery action was run during this diagnostic.

### 5. The signed helper and source helper disagree

For the same read-only command and repository root:

```bash
cc onboard \
  --org auto \
  --products claude,codex \
  --repository-root /Volumes/Dev/Sites/COPILOT \
  --json
```

- the source checkout at helper commit `761c0dc` returns 16 `layers` rows;
- the installed, signed cc 1.7.16 returns `components` for all four components
  but an empty top-level `layers` array, while its `layer-manifest` stage still
  reports 16 layers.

The exact release binary therefore does not match the source-level contract in
a user-visible field. Investigate the PyInstaller import/build inputs and add a
packaged-artifact assertion. Do not assume `--version` proves behavioral parity.

## Why the release gates did not catch this

The 0.2.4 gates were broad but did not exercise this boundary:

1. Source tests covered dirty preservation and successful clean fast-forwards,
   but not a clean, branch-diverged checkout with an identical tree.
2. The headless setup transaction used inert fixtures rather than a real Git
   graph with a non-fast-forward target.
3. The release helper probe checked that a `layer-manifest` inventory item was
   present, but did not require sixteen top-level topology rows.
4. Walkthrough acceptance checked the helper version and supported verbs, not
   source-versus-signed-binary topology parity.
5. No failpoint test stopped after Personal GitHub creation and before visible
   repository setup to verify rollback or truthful partial-result reporting.

The prior **40/40** walkthrough result remains evidence for the intended screens;
it is not evidence that this live transaction completed.

## Required product and architecture decisions

Resolve these explicitly before implementation. Record a new ADR if the chosen
behavior changes ADR-005.

### A. Classify repository history before offering an action

At minimum, distinguish:

- exact target commit;
- clean and provably fast-forwardable;
- dirty working tree;
- local commits not contained by the target;
- divergent history with identical tree content;
- divergent history with different content;
- wrong origin or unreadable repository.

Only the second state may be labeled a safe fast-forward. Never reset an
existing visible checkout. For the identical-tree/divergent-history case, decide
whether to preserve the current published branch as equivalent, use a separate
managed checkout, or route to a competent owner. The decision must be reversible
and understandable without dumping a raw Git error on a non-technical person.

### B. Make mutation ordering honest

Run every deterministic preflight—including Git ancestry checks—before creating
or seeding Personal repositories. Cross-system atomicity is not literally
available across GitHub and local Git, so use one of these honest models:

- a fully preflighted ordered transaction whose remaining actions cannot fail
  for already-known reasons; or
- a recorded saga with exact completed actions, bounded compensation where
  safe, and a truthful resumable partial state.

Do not claim “nothing changed” after an irreversible GitHub repository creation.
If a later step blocks, report exactly what was created, what remains, and the
safe next actor/action.

### C. Prove the artifact that ships

The helper release gate must execute the signed binary against a deterministic
four-component/four-layer fixture and assert:

- exactly 16 topology rows;
- expected repository names and visible paths;
- expected actions for exact, fast-forward, divergent, missing, and empty
  repositories;
- no mutation in plan mode;
- the same normalized result as the source helper.

The app gate must consume that exact binary report, not a source mock, for the
topology contract.

## Recommended implementation sequence

1. Start `tc` task 203 and record the architecture decision before coding.
2. Build a temporary Git fixture with two sibling commits that produce the same
   tree; reproduce the false `repair` plan and failed `--ff-only` apply without
   touching live repositories.
3. Add plan/apply tests for every history state listed above.
4. Move all visible-repository and history preflight ahead of Personal apply.
5. Add a transaction ledger or partial-result contract for cross-system writes;
   update the schema and UI so the app cannot claim zero changes after partial
   progress.
6. Fix and diagnose the frozen-helper source/artifact mismatch. Strengthen
   `scripts/package-cc-macos-release.sh` and the Control Tower vendored-helper
   gate to assert topology rows from the exact binary.
7. Update the setup recovery view. “Try again” may be offered only when the
   reported blocker can actually change; otherwise route to a specific owner or
   repair action.
8. Run source QA, packaged-helper QA, native app QA, and the full release gates.
9. Publish new immutable helper and app versions. Do not move or reuse
   `v5.13.18` or `v0.2.4`.
10. Install the new app on this Mac, review the read-only sixteen-row plan, then
    perform one live apply. Record pre/post repository fingerprints and GitHub
    inventory.

## Live acceptance criteria

The initiative is not complete until all of these are proven on this Mac:

- Detect and Settings receive and render 16 topology rows from the exact signed
  helper.
- `cli-copilot` is preserved; no reset, forced checkout, lost branch, or lost
  commit occurs.
- The identical-tree/divergent-history state receives the newly approved,
  tested route rather than a false fast-forward promise.
- A blocker found during preflight causes zero mutations.
- A simulated blocker after a write produces an exact partial-action ledger and
  truthful recovery, never “nothing changed.”
- the existing Knowledge and CLI Personal remotes are downloaded visibly rather
  than recreated;
- all 16 repositories are visible under `/Volumes/Dev/Sites/COPILOT` or a
  user-approved replacement root;
- the active manifest contains the complete 16-layer topology;
- update/materialization succeeds for Knowledge, CLI, Claude, and Codex;
- resolution returns a non-empty effective capability set;
- Doctor independently verifies the result before the app shows Ready;
- project aftercare remains deferrable and available from Settings;
- the final helper, app, and DMG are signed, notarized, Gatekeeper-accepted,
  published, downloaded, and checksum-verified.

## Learning path for the next developer

Read in this order before changing code:

1. [`SOUL.md`](../../../../SOUL.md), especially parse-never-compute,
   never-destroy, actor competence, and the “Git Error to a Non-Technical
   Person” anti-pattern.
2. [`docs/01-architecture/12-architecture-guiding-principles.md`](../../../01-architecture/12-architecture-guiding-principles.md).
3. [`ADR-005-visible-ecosystem-repositories.md`](../decisions/ADR-005-visible-ecosystem-repositories.md).
4. [`phase-6-project-integration-aftercare-handoff.md`](phase-6-project-integration-aftercare-handoff.md)
   for the release lineage and prior diagnostics.
5. The truthful setup
   [service specification](../walkthroughs/truthful-setup-recovery-service-spec.md),
   [UX specification](../walkthroughs/truthful-setup-recovery-uxd-spec.md), and
   [UI specification](../walkthroughs/truthful-setup-recovery-uids-spec.md).
6. [`docs/01-architecture/cli-contract.md`](../../../01-architecture/cli-contract.md)
   and [`onboard.schema.json`](../../../01-architecture/schemas/onboard.schema.json).
7. In `claude-copilot`, read
   `tools/cc/src/cc/commands/onboard.py`, focusing on
   `_topology_report_layers`, `_apply_visible_topology`,
   `build_ecosystem_onboard_report`, `_ecosystem_result`, manifest adoption,
   rollback, resolve, and pointer commit.
8. Read helper tests in `tools/cc/tests/test_onboard_contract.py` plus update,
   resolver, Doctor, configuration, and packaging tests.
9. In Control Tower, read `native/cli-dtos.swift`, `native/cli-client.swift`,
   `native/wizard.swift`, and `native/user-settings.swift`.
10. Read `scripts/package-user-release.sh`, the helper packaging script, and
    every vendored-helper, schema, walkthrough, completed-setup, CLI-smoke, and
    headless-transaction gate.
11. Retrieve task evidence:

    ```bash
    tc task get 202 --json
    tc task get 203 --json
    tc wp list --task 202 --json
    ```

Use the project-local `$protocol` route for the pickup, `$ta` for the transaction
decision, `$me` for implementation, and `$qa` for evidence-bound verification.

## Safe reproduction commands

These commands are read-only. Do not append `--apply`.

```bash
# Installed signed helper
TMPDIR=/tmp \
  '/Applications/Copilot Control Tower.app/Contents/Resources/cc' onboard \
  --org auto \
  --products claude,codex \
  --repository-root /Volumes/Dev/Sites/COPILOT \
  --json

# Source helper
cd /Volumes/Dev/Sites/COPILOT/claude-copilot/tools/cc
TMPDIR=/tmp uv run cc onboard \
  --org auto \
  --products claude,codex \
  --repository-root /Volumes/Dev/Sites/COPILOT \
  --json

# Confirm the CLI history shape without fetching or changing it
git -C /Volumes/Dev/Sites/COPILOT/cli-copilot status -sb
git -C /Volumes/Dev/Sites/COPILOT/cli-copilot rev-list \
  --left-right --count HEAD...v0.3.1^{}
git -C /Volumes/Dev/Sites/COPILOT/cli-copilot rev-parse \
  HEAD^{tree} v0.3.1^{}^{tree}
```

Prefer a temporary fixture for implementation testing. Do not use the live
working trees as test fixtures.

## Release lineage and repository state

Completed and published work:

- helper implementation commit:
  `761c0dc83b57a8e064473eb70072f61242c5cde9`;
- helper release: `v5.13.18`, cc 1.7.16;
- app source commit/tag:
  `b84aa2b17d44012f679fb0dee9c97ef378114fea`, `v0.2.4`;
- app release-artifact/handoff commit:
  `65c1714aa679b23233ac570e330095f3fa26675e`.

The app worktree contains pre-existing deletions under historical
`release/control-tower-0.1.1-*` through `0.2.0-*`. They are not part of this
work and must not be staged, restored, or deleted by the pickup. The helper
worktree also contains pre-existing untracked project-integration files. Inspect
and preserve both worktrees before committing.

## Definition of done

Task 203 may close only with an evidence-bound QA work product, a successful
live apply on this Mac, a truthful completed-state screenshot, exact repository
and manifest evidence, and newly published helper and Control Tower releases.
Source-only and fixture-only success are insufficient.
