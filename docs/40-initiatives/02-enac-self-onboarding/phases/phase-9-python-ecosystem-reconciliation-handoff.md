# Phase 9 handoff: Python ecosystem reconciliation

> **Current continuation point (2026-08-04):** Phase 9.2 implementation and
> changed-scope QA are complete, but the `0.6.0` release is **not published or
> installed**. The exact release blocker and continuation commands are in
> [section 19](#19-phase-92-implementation-complete-release-blocked-on-owner-notarization-credential-2026-08-04).
> That section supersedes older version and status statements in this rolling
> handoff.

> **Start instruction:** Read this document completely and begin. Do not ask the
> owner to restate the objective or reconstruct the prior conversation. Use the
> available simultaneous multi-agent sessions in parallel, with non-overlapping
> file ownership, and continue until every completion gate in this document is
> satisfied or a genuinely owner-only decision is reached.

## 1. Mission

Build and prove a Python-owned capability that can:

1. analyze a Mac and its Copilot ecosystem;
2. determine what is missing or inconsistent;
3. produce an exact, reviewable plan;
4. put the correct pieces in place safely;
5. update every selected project through a supported route;
6. identify projects with no Copilot capabilities;
7. offer and apply an explicit ecosystem integration for those projects;
8. independently verify every result; and
9. emit a versioned contract that the native macOS Swift app only displays.

This is a macOS product. The shipping app is native SwiftUI/AppKit. References
to iOS in the originating conversation were corrected by the owner to macOS.

The owner has explicitly authorized the next session to use simultaneous
multi-agent parallel work. Use all useful concurrency slots in waves. Do not
assign two agents overlapping write ownership in the same files.

## 2. Owner decisions already made

Do not ask these questions again.

- Python owns machine analysis, project inspection, planning, filesystem
  mutation, Git safeguards, rollback, and verification.
- Swift launches the helper, passes explicit user intent, decodes versioned
  JSON, and renders Python-authored truth.
- Success means every selected project is safely accounted for and has a route
  into the ecosystem. It does not mean blindly mutating dirty, ambiguous, or
  customized repositories.
- Projects without Copilot should receive Python-authored component
  recommendations and require confirmation before installation. A future
  organization policy may supply defaults, but hidden universal installation
  is not acceptable.
- Customized projects must not be abandoned. When a universal deterministic
  recipe is unsafe, Python must produce a complete project-specific integration
  dossier and a reviewed recipe. Python must remain the executor and verifier.
- The Python behavior must be validated against real projects before another
  app release is built. Build, sign, notarize, and publish the app once after
  the Python contract and live behavior are stable.

## 3. Product and architecture boundary

The intended boundary is:

```text
person or Swift user intent
            |
            v
Python assess -> plan -> apply -> verify -> durable diagnostic
            |
            v
versioned JSON contract
            |
            v
Swift Decodable DTOs -> SwiftUI/AppKit presentation
```

Python is authoritative for ecosystem and project truth. Swift must not:

- inspect project integration files;
- calculate eligibility or readiness;
- create or alter migration actions;
- perform project filesystem operations;
- reconcile overlapping counts;
- decide whether verification passed; or
- claim rollback succeeded.

Swift may continue to own app-local concerns such as preferences,
security-scoped folder bookmarks, window state, and temporary launcher files.

Read before making architectural or product-facing changes:

- `AGENTS.md`
- `SOUL.md`
- `docs/01-architecture/12-architecture-guiding-principles.md`
- `docs/01-architecture/cli-contract.md`
- `docs/01-architecture/schemas/workspace-migrations.schema.json`
- this handoff

The retired `src-tauri/` Rust/TypeScript application is not the shipping app.
Do not implement behavior there. Some historical JSON fixtures still live
there and are consumed by native contract tests; move them to a neutral native
test-fixture location if that can be done without obscuring provenance.

## 4. Repositories and starting state

### Control Tower

- Path: `/Volumes/Dev/Sites/COPILOT/copilot-control-tower`
- Branch at handoff creation: `app-build`
- Starting published provenance commit: `2ddfc9b`
- Current published app: `0.5.4` build `24`
- Shipping source: `native/*.swift`
- Release script: `scripts/package-user-release.sh`

### Python helper / Claude Copilot

- Path: `/Volumes/Dev/Sites/COPILOT/claude-copilot`
- Branch at handoff creation: `feat/adopt-and-project-setup`
- Starting commit: `a4ab92e`
- Python package: `tools/cc`
- Current published helper embedded by the app before this work: `cc 2.5.2`

### Related repositories

- Codex Copilot source:
  `/Volumes/Dev/Sites/COPILOT/codex-copilot`
- CLI Copilot source and environment:
  `/Volumes/Dev/Sites/COPILOT/cli-copilot`
- CLI Copilot environment file:
  `/Volumes/Dev/Sites/COPILOT/cli-copilot/.env`

Do not modify unrelated dirty worktrees. Inspect every repository before
editing and preserve all changes that were not created by this initiative.

## 5. Why this phase exists

Control Tower reported 62 projects:

- 26 ready;
- 17 needing guided assistance; and
- 19 that could not be confirmed.

After grouped migration work, the app displayed a 33-project receipt:

- 6 updated during the run;
- 3 unable to finish and rolled back; and
- 29 still guided after the run.

Those numbers overlap. They are not three partitions. Two projects were
updated in one component while another component remained guided, and all
three rolled-back projects remained guided. The app did not explain the
overlap clearly.

The live run also proved that the current Python engine only has two
deterministic legacy recipes:

- `claude-canonical-entry-v1`
- `codex-portable-copy-v1`

Projects were left unchanged for legitimate but incompletely supported
reasons:

- dirty Git working trees;
- customized verification gates;
- no recognized deterministic migration recipe; or
- a component mismatch that the current recipe did not repair.

The three observed rollback projects were:

- `convoco-site`
- `method-copilot`
- `saas-financial-model`

The observed partial successes included `insights-copilot` and
`knowledge-copilot-internal`: Codex became ready, but Claude remained guided.

This phase replaces repeated app-build iteration with direct Python
development and live Python validation. The app is updated only after the
behavior is proven.

## 6. Definition of success

### 6.1 Complete machine assessment

One Python-owned workflow must report, without mutation:

- helper, framework, and relevant CLI versions;
- configured authoritative framework sources;
- machine configuration and approved project roots;
- authentication state and credential presence, never credential values;
- ecosystem layers and their readiness;
- required dependencies and permissions;
- connectivity as a separate fact from sign-in or configuration state;
- all blockers, their evidence, and the responsible actor; and
- the exact next safe action.

Reuse existing authoritative Python functions and contracts where possible.
Do not build a second truth engine beside `cc doctor`, `cc onboard`,
`cc connections`, and `cc workspace`; compose or extend them behind one
coherent workflow.

### 6.2 Complete project census

Discover every Git project under explicitly approved roots and assign one
primary state:

- `ready`
- `safe-setup-available`
- `safe-update-available`
- `copilot-not-present`
- `customized-guided-route`
- `held`
- `owner-decision`
- `could-not-verify`
- `excluded`

Names may differ if existing enums should be extended instead, but the
semantics must remain distinct. Every project also carries independent
component states for each applicable product. A project must never disappear
into an unexplained aggregate.

### 6.3 Projects without Copilot

For a selected project with no capabilities, Python must:

1. inspect the project without writing;
2. recommend applicable components with reasons;
3. accept the person's explicit component selection;
4. produce an exact plan and preservation boundary;
5. install project-local, portable integration evidence;
6. preserve project-owned content;
7. verify each selected component independently; and
8. return an idempotent result on a second run.

### 6.4 Existing and customized projects

Every selected project must receive one complete route:

- A recognized state uses a versioned deterministic recipe.
- A dirty tree is held without mutation and reports the exact hold reason.
- A customized state receives a project-specific integration dossier and
  reviewed recipe.
- An ambiguous state receives an explicit owner decision with enough evidence
  to resolve it.
- An unsupported state becomes a named implementation gap with a fixture and
  acceptance test, not a permanent generic message.

The project-specific dossier must include current component evidence, missing
requirements, preservation rules, allowed target paths, prohibited actions,
verification commands, and stop conditions. An agent may author a proposed
recipe from that dossier, but Python validates, applies, rolls back, and
verifies it. Agents must not bypass the Python transaction boundary by editing
live selected projects directly.

Prefer a closed set of typed recipe operations over a generic arbitrary shell
or patch executor. If a new operation type is necessary, threat-model it,
schema it, and fault-test it before use.

### 6.5 Exact-plan transaction

Every apply must require a fresh opaque plan identifier and must:

- re-inspect immediately before mutation;
- refuse a stale plan;
- verify Git state and project root identity;
- constrain every target beneath the project;
- reject unsafe symlinks and path traversal;
- snapshot every bounded target before mutation;
- record every completed operation;
- independently verify targeted components;
- restore every completed target on failure;
- record each rollback target separately; and
- tell the truth if any restoration fails.

One project's failure must not corrupt another project or erase its receipt.

### 6.6 Verification and idempotence

Verification must be a fresh authoritative inspection, not mutation-code
self-report. A project is `updated` only when its targeted components pass.
Overall project readiness remains separate from targeted-component success.

After a successful full run:

- a second assessment returns the same truth when the filesystem is unchanged;
- a second apply proposes zero already-completed work;
- all ready projects remain ready;
- every remaining non-ready project has a concrete route; and
- batch counts reconcile from per-project records.

### 6.7 Durable diagnostics

Every apply run must save one Python-owned, private, redacted record containing:

- schema, helper version, run id, timestamps, and requested/fresh plan ids;
- machine assessment relevant to the run;
- per-project preflight classification and component evidence;
- source versions and fingerprints;
- bounded target kinds and fingerprints, never contents;
- planned and completed operations;
- post-apply component verification evidence;
- exception type and redacted detail;
- each rollback outcome; and
- final census and overlap explanation.

Requirements:

- atomic same-directory replacement;
- diagnostics directories mode `0700`;
- files mode `0600`;
- reject symlinked diagnostic boundaries;
- retain the newest 20 owned records by default;
- never include file contents, environment values, stdin, credentials, or raw
  subprocess streams; and
- diagnostic-write failure must not falsify the in-memory action receipt.

### 6.8 Versioned presentation contract

Python authors:

- states and classifications;
- counts;
- overlap counts and plain-language explanation;
- per-project outcome text;
- next actions;
- verification truth; and
- the diagnostic reference.

Swift decodes these values without recreating them. Unknown or incompatible
schemas fail closed with an honest compatibility message.

## 7. Required user workflow

The exact command names may extend existing verbs if that produces a smaller
and more coherent API. Do not create redundant analyzers merely to match these
illustrative names. The finished capability must nevertheless support this
sequence from Python alone:

```text
ASSESS  -> complete read-only machine and project census
SELECT  -> explicit roots, projects, and recommended components
PLAN    -> exact immutable actions and preservation contract
APPLY   -> guarded Python transaction using the reviewed plan id
VERIFY  -> fresh component and project inspection
RECEIPT -> complete JSON result plus durable redacted diagnostic
REPEAT  -> zero duplicate work; remaining routes stay explicit
```

The owner must be able to complete and diagnose this sequence conversationally
without rebuilding Control Tower.

## 8. Acceptance matrix

Build fixtures and automated tests for at least:

### Machine states

- complete and healthy;
- missing helper or framework source;
- incompatible versions;
- signed out;
- credential absent;
- credential store unreachable;
- offline with otherwise valid local state;
- approved roots absent or unreadable; and
- diagnostics location unavailable or symlinked.

### Project states

- empty project with no Copilot;
- Claude-only, Codex-only, and both components;
- current portable integration;
- each recognized legacy integration;
- mixed ready/guided components;
- customized `CLAUDE.md`, `AGENTS.md`, `.mcp.json`, skill bridge, plugin, gate,
  config, and lock evidence;
- missing required files;
- mismatched checksums;
- external and internal symlinks;
- clean, dirty, detached, unreadable, and non-Git roots;
- owner hold and exclusion; and
- stale plan between review and apply.

### Transaction and failure states

- success after each recipe type;
- failure injected before the first write;
- failure injected after every individual mutation boundary;
- verifier failure after all writes;
- rollback success for every snapshot kind;
- rollback failure for each target type;
- one failed project among successful batch peers;
- process interruption and recoverable durable evidence;
- repeated apply after success; and
- concurrent or overlapping runs against the same project.

### Security and contract states

- path traversal and symlink escape refusal;
- project-owned file preservation;
- credential-shaped value redaction;
- no environment, stdin, or content leakage;
- strict JSON Schema validation for every success and error shape;
- backward/forward compatibility gates; and
- Swift decoding fixtures for every renderable outcome.

Use temporary Git repositories for integration tests. Add property- or
invariant-based tests where they reduce gaps, especially for path containment,
count reconciliation, idempotence, and redaction.

## 9. Live validation protocol

Do not begin with a 62-project mutation.

1. Run the source Python helper's complete read-only assessment.
2. Save the report and compare repeated runs for stability.
3. Select disposable fixtures and then one clean real canary project.
4. Review the exact plan, preservation set, and plan id.
5. Apply through Python.
6. Inspect the durable diagnostic.
7. Run independent verification in a fresh invocation.
8. Run the same plan again and prove idempotence/staleness handling.
9. Expand to one example of every recognized project family.
10. Only then run the reviewed selected-project cohort.
11. Re-run the full census and account for every project.

Never normalize away a dirty working tree merely to make a test pass. Never
commit or discard changes in another project without the owner explicitly
placing that repository's changes in scope.

## 10. Multi-agent execution plan

The root agent is the integrator and keeps `tc` authoritative. Use available
parallel slots in waves.

### Wave 1: evidence and contract

- **Architecture/contract agent:** map existing `cc` commands and internal
  sources of truth; propose the smallest unified assess/plan/apply/verify
  contract; own schemas and architectural decision record.
- **Project-state agent:** inventory real classification families read-only;
  build the fixture taxonomy and identify missing recipes.
- **QA/security agent:** threat model the transaction and diagnostic model;
  author the acceptance matrix, fault-injection strategy, and leak assertions.
- **Root agent:** integrate decisions, create PRD/tasks, resolve overlaps, and
  prevent divergent contracts.

Wave 1 must converge on one contract before implementation branches proliferate.

### Wave 2: Python implementation

- **Machine-assessment agent:** machine/ecosystem composition and tests.
- **Project-reconciliation agent:** census, recommendations, no-Copilot setup,
  and recipe planning.
- **Transaction/diagnostics agent:** exact-plan apply, locking, snapshots,
  rollback, durable diagnostics, and fault injection.
- **Root agent:** shared types/schema integration and end-to-end command flow.

Assign explicit file ownership. If implementation areas overlap, sequence them
instead of accepting concurrent edits to the same module.

### Wave 3: proof and live canaries

- QA runs the complete automated suite and validates artifacts.
- Security reviews redaction, containment, locking, and rollback evidence.
- A project-family agent executes read-only live classification and canary
  plans.
- Root integrates defects and repeats until all gates pass.

### Wave 4: thin Swift integration and release

Only after the Python contract and live canaries are stable:

- update Swift DTOs and views once;
- run native contract, accessibility, and visual verification;
- release the Python helper first;
- vendor the exact immutable helper artifact into Control Tower;
- build from immutable pushed source;
- sign, notarize, staple, and verify the macOS artifact;
- publish provenance; and
- install the released app for final end-to-end validation.

## 11. Current work already implemented but not yet released

Task Copilot task `228`, **Add durable redacted project-migration
diagnostics**, is in progress. Architecture work product `441` and security
work product `442` record the initial decisions.

The checkpoint committed with this handoff adds:

### Python helper

- `machine_diagnostics_root()` under the existing `CC_MACHINE_ROOT` seam;
- a Python-owned `migration_diagnostics.py` writer;
- atomic mode-`0600` records and mode-`0700` directories;
- 20-record retention;
- credential-shaped value redaction;
- per-action preflight, source fingerprint, bounded target fingerprints,
  completed operations, post-apply component evidence, exception
  classification, and per-target rollback outcomes;
- truthful handling when every rollback target cannot be restored;
- migration schema `1.1`;
- CLI-authored overlap counts and explanation;
- a diagnostic reference in apply responses;
- helper version staged as `2.5.3`; and
- targeted unit and command tests.

### Native app

- Swift DTOs for schema `1.1`, overlap fields, and diagnostic reference;
- clearer labels: `Updated this run`, `Could not finish`, and `Guided now`;
- rendering of the Python-authored overlap explanation;
- a `Show in Finder` action for the Python-owned diagnostic record;
- app version staged as `0.5.5` build `25`; and
- updated native contract fixtures and schema documentation.

This checkpoint is not the full Phase 9 capability. In particular, it does not
yet provide a unified machine reconciliation workflow, full no-Copilot project
integration, project-specific reviewed recipes for all customized families, or
live all-family proof.

No `0.5.5` app release or `2.5.3` helper release existed when this handoff was
drafted. Do not claim otherwise. The release is intentionally deferred until
the Python workflow is proven.

## 12. Known verification state at handoff

The focused Python tests for migration behavior, durable diagnostics, and the
command contract passed. Focused Ruff checks for changed Python files passed.
The native bulk-project-migration DTO/contract script passed after the schema
update. `scripts/build-user.command` also compiled and signed the local native
app successfully; it emitted only existing macOS 14 `onChange` deprecation
warnings.

A repository-wide Ruff invocation reports many pre-existing lint violations in
unrelated helper modules and tests. Do not silently repair hundreds of unrelated
files as part of this phase. Establish the repository's intended baseline gate,
keep changed files clean, and separately record any baseline debt.

The full helper pytest suite was run independently from `tools/cc/`. It reaches
completion but is not green because of unrelated environment/baseline failures:

- 3 cross-tool FTS tests cannot import the separately packaged `tc` module; and
- 14 MCP schema tests inspect private `mcp.Server` attributes that are absent in
  the installed MCP package version.

The new migration/diagnostic tests pass within that same environment. The next
session must either reproduce these failures on the starting commit or establish
the intended dependency/test invocation before treating them as Phase 9
regressions. Do not waive them silently.

The next session must re-run and record exact evidence from the committed
checkpoint rather than relying only on this prose.

## 13. Task tracking and evidence

Use `tc` in the Control Tower repository.

1. Retrieve task `228` and its work products.
2. Create a Phase 9 PRD and child tasks for the parallel workstreams.
3. Mark implementation tasks with `metadata.requiresQa=true`.
4. Store architecture, implementation, test, security, documentation, and
   release work products.
5. A passing QA work product must contain an `ARTIFACT:` marker and an accepted
   `VERDICT:` token.
6. Keep task state authoritative in `tc`; do not reproduce a mutable task board
   in this document.

For three or more related `tc` operations, prefer one `tc.api` transaction.
Keep `tc.api` and `cc.api` operations in separate Python blocks.

## 14. Completion gates

Do not mark Phase 9 complete until all are true:

- [ ] The Python-only user workflow covers assess, select, plan, apply, verify,
      receipt, and repeat.
- [ ] Every selected project receives a complete route into the ecosystem.
- [ ] Projects without Copilot can be recommended, selected, integrated, and
      independently verified.
- [ ] Customized projects can use reviewed typed recipes without bypassing the
      Python transaction boundary.
- [ ] Dirty, ambiguous, excluded, and unsafe projects remain unchanged and have
      precise explanations.
- [ ] Exact-plan freshness, project locking, containment, snapshots, rollback,
      and truthful incomplete-rollback behavior are proven.
- [ ] Diagnostics are durable, redacted, bounded, private, and useful for the
      three known rollback families.
- [ ] All automated acceptance fixtures pass.
- [ ] Full helper tests pass or any unrelated baseline failures are explicitly
      isolated with changed-scope gates passing.
- [ ] Read-only live census is stable across repeated runs.
- [ ] Canary projects from every supported family pass apply, fresh verify, and
      repeat/idempotence checks.
- [ ] The final selected-project census accounts for every project and every
      remaining route.
- [ ] Swift decodes and renders every Python contract outcome without computing
      ecosystem truth.
- [ ] The helper is released from immutable pushed source.
- [ ] Control Tower vendors that exact helper, then is built, signed, notarized,
      stapled, verified, published with provenance, and installed.
- [ ] Final QA and security work products approve the shipped artifacts.

## 15. Stop conditions

Stop and ask the owner only when:

- a selected customized project requires a product or ownership decision that
  cannot be inferred from existing project evidence;
- live mutation would overwrite or discard project-owned work;
- a required credential must be created or rotated by the owner;
- signing/notarization authority is unavailable; or
- two viable architectures would materially change the user's workflow or
  trust boundary.

Do not stop merely because the work is large, a project needs a new typed
recipe, a test exposes another defect, or a batch contains mixed outcomes.
Those are the purpose of this phase.

## 16. Final operating principle

The deliverable is not a larger app and not a prettier receipt. It is a
trustworthy Python reconciliation engine that can explain, plan, execute,
restore, verify, and account for the complete selected ecosystem. The macOS app
is one thin view over that proven engine.

## 17. Phase 9.1 default-batch addendum (2026-08-04)

The owner simplified the project-selection decision after reviewing the shipped
`0.5.5` screen. The follow-up contract and native surface are tracked in PRD 17.

The accepted behavior is:

- Python re-assesses every project that is not fully ready with both Claude and
  Codex selected.
- Only deterministic, safe selected assessments enter `default_selection`.
- Dirty, excluded, ambiguous, unverifiable, owner-dependent, missing-source,
  and multi-recipe projects remain outside the batch.
- `batch_summary` partitions the complete census into new setup, correction,
  ready, and needs review exactly once.
- The app starts with the complete safe batch selected and exposes only a
  project-level individual fallback. It never exposes separate product toggles.
- `machine_summary` replaces the repeated blocker-action list with one useful
  status and next step.
- Exact-plan review, explicit apply consent, freshness checks, bounded writes,
  rollback, receipts, and independent verification are unchanged.

The service, UX, and UI artifacts are in `../walkthroughs/` under
`default-project-batch-*.md` and walkthroughs 19–20.

## 18. Phase 9.2 bounded Claude Code reconciliation work record (2026-08-04)

PRD 18 extends the Phase 9.1 default-all batch without moving project write
authority out of Python. Its release version is Control Tower `0.6.0` build
`27`, paired with exactly `cc 2.7.0` and a declared helper range of
`>=2.7.0,<3.0.0`. Reconciliation remains schema `1.0` with a declared app
range of `>=1.0,<2.0`.

### Accepted product behavior

- Assessment now supplies two disjoint Python-authored selection lists:
  deterministic `default_selection` work and bounded `assistant_selection`
  work. Their union is selected by default; a person may remove only whole
  projects. Both Claude Copilot and Codex Copilot remain universal for every
  selected project.
- `resolution_summary` authors the automatic, Claude-assisted, held, total
  actionable, new-setup, and correction counts. Swift renders those counts and
  does not derive category membership or reconcile totals.
- One **Resolve with Claude Code** action creates a private expiring session and
  launches a visible Terminal command containing only the exact bundled `cc`
  path and `reconcile assistant-run --session-id <opaque-id>`. There is no
  prompt copy/paste and no project path, prompt, proposal content, patch, or
  free-form instruction on that command line.
- Claude Code receives only a content-free Python-authored candidate packet in
  a private helper workspace. It selects opaque candidates; it cannot inspect
  or write a live selected project, invent operations, or decide that work
  passed verification.
- Python rejects malformed, unknown, repeated, incomplete, stale, expired,
  tampered, unsafe, or concurrently claimed results. A validated selection is
  bound to one opaque proposal. The app attaches only that identifier to the
  unchanged request and resumes the existing exact plan review, explicit apply,
  rollback, receipt, and fresh verify transaction.
- Dirty, held, unsafe, unreadable, owner-dependent, or otherwise unauthorized
  work remains unchanged with Python-authored detail. The standard
  deterministic-only path remains available when assistant preparation cannot
  be opened.

### Implementation and evidence record

- Task 245 completed the service, UX, UI, architecture, and security contract.
  Its approved walkthroughs and durable specs are under `../walkthroughs/` as
  walkthroughs 21–22 and `resolve-with-claude-code-*.md`.
- Task 246 owns the Python helper lifecycle and adversarial tests. The helper
  source identifies itself as `cc 2.7.0` and implements `assistant-prepare`,
  `assistant-run`, `assistant-status`, proposal binding, constrained Claude
  invocation, and fail-closed candidate validation.
- Task 247 owns the native DTO, client, exact Terminal launcher, status polling,
  default-all/individual-selection presentation, proposal attachment, and
  convergence on the existing plan/apply/verify flow. Architecture,
  implementation, and focused QA are recorded as work products 514–516.
- Task 248 owns integrated live-machine, security, packaged-helper, canary, and
  installed-app evidence. Task 249 owns the immutable helper release and the
  app build/sign/notarize/staple/publish/install sequence. These gates remain
  authoritative; this work record does not mark them complete merely because
  the version and release notes are staged.

### Release and rollback boundary

The release pipeline must vendor the exact independently signed/notarized
`cc 2.7.0` artifact, build Control Tower from immutable pushed source, sign the
outer app, notarize and staple the app and DMG, verify Gatekeeper and checksums,
publish provenance, and install the published artifact before Phase 9.2 is
closed.

The known-good rollback artifact is the signed
`Copilot-Control-Tower_0.5.6_arm64.dmg` retained under
`release/control-tower-0.5.6-c3a0455/`. Reinstalling it rolls back the app and
bundled helper to `0.5.6` / `cc 2.6.1`; it does **not** undo project changes
that Python already applied after explicit plan approval. Project receipts
remain the durable record of those changes.

## 19. Phase 9.2 implementation complete; release blocked on owner notarization credential (2026-08-04)

This is the authoritative continuation point for the next developer. Do not
reconstruct the work from chat history, and do not describe the app as released
or ready for owner testing yet.

### 19.1 What is complete

The Python helper and native app implementation are complete for the accepted
bounded-Claude workflow:

- Python assessment partitions work into deterministic `default_selection`,
  bounded `assistant_selection`, and held projects. Both actionable lists are
  selected by default in the app.
- A selected project always targets both Claude Copilot and Codex Copilot; the
  app does not expose per-product toggles.
- Customized projects use the private
  `assistant-prepare -> assistant-run -> assistant-status` lifecycle. The app
  launches the exact bundled helper in visible Terminal with only an opaque
  session id.
- Claude Code receives a content-free, candidate-id-only packet from a private
  workspace. It receives no project path, project content, patch, command, or
  write authority.
- Python validates and binds one expiring proposal, authors the exact plan,
  applies only after the existing review/consent step, rolls back bounded
  writes on failure, and performs fresh verification.
- The app presents Python-authored new-setup, correction, automatic,
  Claude-assisted, and held counts. It defaults to all actionable projects and
  retains a whole-project deselection fallback.
- The exact vendored-binary release gate now exercises both the deterministic
  reconciliation lifecycle and the bounded assistant lifecycle against clean,
  disposable Git repositories. It proves zero mutation before apply and checks
  the protected Claude invocation, private workspace, environment filtering,
  opaque ids, closed schema, and schema-valid reports.

The helper repository is clean and pushed:

- repository: `/Volumes/Dev/Sites/COPILOT/claude-copilot`
- branch: `feat/adopt-and-project-setup`
- release-tool head: `3630821e2cca34e13f588595ad57a67f263be39f`
- signed foundation ref: `v5.13.42`
- signed foundation source commit:
  `ee94af0fce9e64d6a53fd72bb93bc161c27e77be`
- helper version: `cc 2.7.0`

The key helper implementation/release commits after the main feature commit
are:

```text
3630821 fix(release): account for macOS probe launcher env
5d84237 test(release): harden frozen assistant probe
9704e14 fix(release): canonicalize assistant state root
4c08daa fix(cc): include assistant modules in frozen helper
32a81d2 fix(release): canonicalize assistant fixture paths
56a61b1 fix(release): use complete config in assistant probe
9d88a9d feat(cc): prepare customized projects with bounded Claude
```

Do not create another foundation snapshot unless runtime Python source changes.
The commits after the signed snapshot change only the release tool/probe; the
release metadata must therefore identify `3630821...` as the release-tool
commit and `ee94af...` as the immutable runtime source commit.

### 19.2 Evidence already obtained

Changed-scope helper QA passed:

- 239 reconciliation tests passed;
- 75 of those tests cover the assistant lifecycle and adversarial cases;
- Python compilation and `git diff --check` passed;
- the release probe's shell syntax and all embedded Python blocks passed static
  validation; and
- a real Claude Code `2.1.221` invocation returned an accepted structured
  result. No live selected project was applied or mutated.

Task Copilot evidence includes:

- task 248 implementation work product `517`;
- task 248 QA work product `518`, containing `VERDICT: APPROVED`;
- task 248 security work product `519`; and
- task 249 documentation work product `520`.

Control Tower checks passed against a freshly frozen `cc 2.7.0` binary from
the signed source snapshot:

```text
reconciliation DTO/client contract: PASS
reconciliation JSON schemas/fixtures: PASS
reconciliation wizard source contract: PASS
reconcile schema 1.0 lifecycle PASS
reconcile schema 1.0 assistant lifecycle PASS
vendored-cc reconcile release gate test: PASS
Swift user-source typecheck: PASS (three existing macOS 14 deprecation warnings)
user app bundle tests: PASS
```

The hardened universal helper packaging run reached
`cc release: submitting helper to Apple notarization`. Reaching that line
proves that the exact frozen universal binary had already passed its code-sign
verification, Finder-environment assessment probe, deterministic
reconciliation probe, and bounded-assistant probe. It then stopped because the
notarization credential was unavailable; no `cc 2.7.0` release directory was
emitted.

The latest live **read-only** assessment accounted for 63 projects exactly
once:

| Route | Projects | Meaning |
|---|---:|---|
| Already ready | 16 | The app should acknowledge these and not include them in the update batch. |
| Actionable now | 17 | Selected by default: 1 deterministic correction and 16 bounded Claude-assisted corrections. |
| Held | 30 | Intentionally unchanged because Python did not authorize a safe route. These must not be described as automatically fixable. |
| Total | 63 | Complete current census. |

The assessment reported zero machine-level next actions. The actionable split
was 0 new setups and 17 corrections at the time of that scan. Re-run the
read-only assessment before release because project state may change.

### 19.3 Exact blocker

The Developer ID signing identity is present and usable. The separate Apple
notarization credential is not available:

```text
Error: No Keychain password item found for profile: ct-notary
```

This was reproduced both from the agent process and from a command launched in
the signed-in Terminal application. The repository's `.env.release.local`
contains only the non-secret profile name. No alternative App Store Connect
`.p8` key, `CT_NOTARY_KEY_*` environment, or configured GitHub release secret
was found. Accepted `0.5.6` evidence proves the profile existed previously but
does not restore its secret.

This is correctly owner-only. Never request that the password be pasted into
chat, placed in an environment file, committed, or handed to an agent. The
owner must use `scripts/publisher-setup.command` and, with **Skip notarization
off**, store profile `ct-notary` using the Apple Developer email and an
Apple-generated app-specific password. Because `.env.release.local` already
exists, **Replace existing file** must be enabled. Stop Publisher Setup at
**Ready to build the release**; do not use its build button against an
uncommitted or unpinned checkout.

Confirm restoration without exposing the credential:

```bash
xcrun notarytool history \
  --keychain-profile ct-notary \
  --output-format json \
  --no-progress >/dev/null
```

### 19.4 Control Tower checkpoint state

The commit containing this section on branch `app-build` is the implementation
handoff checkpoint. It stages app version `0.6.0` build `27`, the `cc 2.7.0`
compatibility floor, native implementation, schemas, fixtures, walkthroughs,
release gates, README, changelog, and this handoff.

It is deliberately **not** a releasable artifact commit yet:

- `packaging/cc/cc` is still the published `cc 2.6.1` binary;
- `packaging/cc/VERSION`, `PINNED_SHA256`, and `NOTARIZATION.json` still
  describe `cc 2.6.1`; and
- no Control Tower `0.6.0` app, DMG, release provenance, tag, GitHub release,
  or installed application exists.

Do not run the app release script until the exact notarized `cc 2.7.0` binary
and its metadata replace those four `packaging/cc` artifacts and all release
gates pass.

### 19.5 Continuation procedure

After the owner restores `ct-notary`, complete these steps in order.

1. Verify both repositories are on the documented branches, clean, and equal
   to their pushed refs. Do not package from uncommitted source.

2. Build, sign, probe, and notarize the helper from the signed foundation
   snapshot:

   ```bash
   cd /Volumes/Dev/Sites/COPILOT/claude-copilot
   source /Volumes/Dev/Sites/COPILOT/copilot-control-tower/.env.release.local
   scripts/package-cc-macos-release.sh \
     --source-ref v5.13.42 \
     --source-commit ee94af0fce9e64d6a53fd72bb93bc161c27e77be \
     --output-dir /Volumes/Dev/Sites/COPILOT/claude-copilot/dist/cc-2.7.0-v5.13.42
   ```

   The output must report `cc 2.7.0`, both `arm64` and `x86_64`, Apple status
   `Accepted`, release-tool commit `3630821...`, source commit `ee94af...`, and
   all four probe claims as `passed`, including
   `finder_reconciliation_assistant_probe`.

3. Vendor the exact upstream output into Control Tower without re-signing it:

   - copy the output `cc` to `packaging/cc/cc`, preserving its signature;
   - set `packaging/cc/VERSION` to `2.7.0`;
   - set `packaging/cc/PINNED_SHA256` to the exact output SHA-256; and
   - copy the complete helper `release-metadata.json` to
     `packaging/cc/NOTARIZATION.json`.

4. Run the exact-artifact gates:

   ```bash
   cd /Volumes/Dev/Sites/COPILOT/copilot-control-tower
   ./scripts/tests/test_reconciliation_contract.sh
   ./scripts/tests/test_reconciliation_wizard.sh
   ./scripts/tests/test_vendored_cc_reconcile_release_gate.sh
   ./scripts/verify-vendored-cc.sh --release packaging/cc/cc
   CT_FORCE_REBUILD=1 ./scripts/tests/test_user_app_bundle.sh
   git diff --check
   ```

5. Commit the vendored helper and final provenance changes, push `app-build`,
   and prove local HEAD equals `origin/app-build`. This produces the immutable
   app source commit used by the release script.

6. Build the native release from that pushed source into a new output
   directory:

   ```bash
   source .env.release.local
   ./scripts/package-user-release.sh \
     --source-ref app-build \
     --output-dir dist/user-release-v0.6.0
   ```

   Verify the embedded helper SHA equals `PINNED_SHA256`; verify Developer ID
   signatures, Apple notarization, app and DMG staples, Gatekeeper, release
   metadata, compatibility metadata, and the DMG checksum.

7. Copy the verified release set into
   `release/control-tower-0.6.0-<source-short-sha>/`, commit and push release
   provenance, create and verify immutable tag `v0.6.0`, and publish the GitHub
   release with the DMG, checksum, compatibility file, helper notarization
   evidence, and release metadata.

8. Preserve the currently installed app as a recoverable backup, install the
   published `0.6.0` app in `/Applications`, launch it, verify its embedded
   helper reports `cc 2.7.0`, and run a final read-only assessment. Do not
   authorize a live project apply merely to prove installation.

9. Store final packaged-artifact QA, security, and release work products in
   tasks 248–249. Only then complete tasks 246–249 and close Phase 9.2.

### 19.6 Final honesty requirements

- Passing source and disposable-project tests does not mean `0.6.0` is
  released.
- The signed foundation snapshot is not the same thing as a signed/notarized
  standalone helper artifact.
- The app must never claim it can correct the 30 currently held projects.
- Reinstalling `0.5.6` rolls back the app/helper only; it does not reverse
  project changes already applied by Python.
- No live selected project was mutated while producing this checkpoint.
