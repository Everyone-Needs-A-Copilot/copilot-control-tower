# Phase 5 — Technical ecosystem completion and dogfooding-readiness plan

Status: Active Date: 2026-08-14 Owner: Pablo Alejo Execution record: PRD-23 / TASK-278 Scope decision: [ADR-010](../decisions/adr-010-technical-ecosystem-first.md) Repository-governance decision: [ADR-011](../decisions/adr-011-solo-owner-repository-governance.md)

Readable version: [Standalone HTML plan](phase-5-technical-ecosystem-completion-plan.html)

## Executive decision

The current technical ecosystem goal is **not yet achieved**. The release candidate and core mechanics are credible, and the solo-owner GitHub blocker is gone, but the system is not yet a released, fully resolved, scenario-proven, fleet-verified environment that Pablo can depend on for real work.

Initiative 06 now ends when the technical ecosystem is ready for Pablo to dogfood directly through Claude Code and Codex. It does not wait for a Control Tower release, a non-technical participant study, or a long-term usage period.

## The finish line

Initiative 06 is complete only when one exact released ecosystem can do this repeatably:

1. Accept a real problem without requiring ecosystem vocabulary.
2. Route the problem to the appropriate Claude Code or Codex specialist sequence.
3. Resolve and assemble the entitled foundation, organization, department, personal, Knowledge, CLI, and Task Copilot pieces.
4. Apply those pieces to produce a useful, self-contained project artifact.
5. Preserve source identity, decisions, evidence, task state, and project ownership.
6. Resume the work in a fresh session without manual reconstruction.
7. Consume an approved shared update without damaging human-owned work.
8. Fail safely under revoked access, offline state, bad signatures, stale locks, optional-service failure, secret input, or path attack.

## Scope

### In scope now

- Claude Code and Codex installation, routing, specialists, skills, hooks, and runtime behavior.
- `cc` entitlement, layer resolution, signed immutable inputs, materialization, update, lock, provenance, and conformance.
- Knowledge Copilot organization/accounting inputs and attributable runtime receipts.
- CLI Copilot bounded operational capabilities and fail-open optional integrations.
- Task Copilot planning, work products, pause/resume, continuity, and provenance.
- Realistic technical problem-to-solution scenarios with deterministic and bounded model-behavior evidence.
- Personal/shared security, project-work preservation, clean-environment proof, eligible-fleet propagation, and final technical audit.
- GitHub governance that permits the owner to merge while retaining technical checks.

### Explicitly deferred

- Control Tower product design, source changes, packaging, signing, notarization, installation, supervision, rollback, and app release.
- Non-technical participant testing.
- Claims about general usability, organization-wide adoption, or democratization.
- Long-term dogfooding conclusions. Initiative 06 creates the trustworthy starting point; the lived-use record begins after completion.

## Current component audit

| Component | Technical contract | Current evidence | Gap to close | Owning work |
| --- | --- | --- | --- | --- |
| GitHub governance | Owner-authorized merges are not blocked by required third-party approval; repository exceptions remain possible | Complete live audit across 51 non-Hermes repositories; zero review gates remain; four Hermes repos untouched | Future app configuration must not reapply a one-review default | TASK-306; ADR-011; future PRD-24 correction |
| Framework release | One reviewed and immutable framework identity installs Claude and Codex completely | Candidate PR #66 is exact, clean, hosted-green, and installed locally; round trip is 19/19 | Merge on owner instruction, publish immutable release, reinstall from release identity | TASK-297 release sequence |
| Canonical transaction | Setup and update share one preflight, materialization, ledger, lock, and postcondition implementation | Candidate implementation and round-trip fixtures approved | Reprove against released framework and signed real layers | TASK-279 closure through TASK-297/303 |
| Entitlement and layer resolution | Foundation → organization → department → personal winners are explicit across entitled, unentitled, offline, stale, revoked, and recovered states | Lifecycle implementation and fixtures approved | Prove exact live signed organization/accounting winners after release | TASK-295/297/303 |
| Claude Code runtime | Protocol chooses appropriate agents/commands/hooks and consumes attributable layered context | Structural integration and local QA exist | Execute realistic released-content scenarios and preserve artifacts | TASK-296/285/303 |
| Codex runtime | Native skills/plugin express the same intent and consume signed tier-provenant inputs | Signed plugin materialization and one enabled plugin source approved | Execute parity cells; label real unsupported surfaces instead of omitting them | TASK-294/296/285/303 |
| Knowledge Copilot | Organization and department knowledge are immutable, entitled, attributable, and behaviorally consumed | Approved organization/accounting content exists; accounting projection works | Merge, sign, pin, update, and prove both live receipts | TASK-297/285 |
| CLI Copilot | Operational capabilities remain bounded services and optional failures do not reject core work | Capability and hook fixtures approved locally | Exercise success, timeout, missing-service, denial, and recovery paths in the integrated suite | TASK-296/291/303 |
| Task Copilot | Plans, decisions, work products, handoffs, and continuation survive process/session boundaries | Deterministic pause/resume and continuity machinery approved locally | Prove fresh-session continuation, idempotence, and concurrency safety in scenario artifacts | TASK-296/303 |
| Conformance | Full mode proves all designed layers, zero S0, zero unexplained could-not-run, and reviewed residual truth | Round trip passes; regression layer has no current delta | Release organization content, eliminate six S0 rows, reconcile all residual failures, adopt the approved lock correction | TASK-297/288/292 |
| Behavioral evaluation | Layered inputs cause attributable, bounded changes without foundation or safety regression | Runner, fixtures, rubrics, and synthetic cases exist | Run required Claude/Codex foundation-versus-layered cases and preserve criterion-level evidence | TASK-284/285 |
| Propagation | One signed shared change reaches every approved eligible project through `cc` without touching held repositories | Exact provisional census machinery exists | Regenerate from released entitlement ledger, approve exact set, pilot, fan out, verify | TASK-300/288/299 |
| Integrated security | Personal content, credentials, untrusted sources, unsafe paths, and destructive repair fail closed | Strong component controls and negative fixtures exist | Close the accepted evaluator residual or record a current owner-backed disposition; run pre/post propagation review | TASK-291/299 |
| Clean environment | A fresh home can install, create, route, preserve, resume, update, and verify without hidden publisher state | Protocol exists | Execute it against exact released identities with independent QA | TASK-303 |

## Delivery sequence

### Gate 0 — Normalize governance and scope

Outcome: the solo-owner merge deadlock is removed, Hermes remains exempt, the app and long-term human proof are no longer active completion dependencies, and the initiative/task graph points to this plan.

Evidence: ADR-010, ADR-011, the live governance audit, updated PRD-23, and a dependency check proving TASK-292 no longer waits on TASK-290 or PRD-24.

### Gate 1 — Land and publish exact framework and content releases

1. Re-read framework PR #66, organization-content PR #1, and accounting-content PR #1 immediately before mutation.
2. Verify exact head identities, clean merge state, required technical checks, and absence of unexpected changes.
3. Merge each named pull request when Pablo directs the merge. No independent approval is required.
4. Publish new signed, non-moving framework, organization, and accounting refs from the merged identities.
5. Update signer policy and pins without moving old tags.
6. Reinstall the exact released framework snapshot and run `cc update --json`.
7. Verify binary/command/plugin hashes, signed winners, content trees, Knowledge receipts, materialized destinations, and lock projections.

Stop if a head changed after verification, a required technical check failed, a signer is not authorized, a tag moved, or consumer bytes do not match the released tree.

### Gate 2 — Close conformance truth

1. Run the released runtime's disposable round trip and require 19/19 or the current intentionally versioned equivalent with zero fail and zero could-not-run.
2. Run `cc conformance check --full --no-cache --json`.
3. Eliminate all S0 results, including the six organization-extension selections.
4. Reconcile every result that conflicts with `expected_today`.
5. Fix residual failures or record a structured disposition with check identity, path, reason, scope, owner, evidence, and review decision.
6. Correct the Control Tower project-lock checksum through an evidence-bound adoption transaction without overwriting the approved gate file.
7. Regenerate and review regression truth only after the live result is understood.

Pass condition: zero S0, zero unexplained could-not-run, zero unreviewed regressions, and no residual failure hidden by a global acknowledgement or aggregate score.

### Gate 3 — Prove each technical component in isolation

Run contract tests for entitlement, resolution precedence, source verification, atomic materialization, lock/disk parity, Claude routing, Codex skill loading, Knowledge receipts, CLI capability boundaries, Task Copilot persistence, and update idempotence.

Every test must bind its result to exact framework and content identities. A mocked fixture can prove a failure shape; it cannot substitute for at least one live signed-input success path.

### Gate 4 — Run the realistic problem-to-solution scenario suite

The suite starts with ordinary problems and observes the ecosystem from the user's side. It does not prompt the runtime with internal component names merely to make wiring visible.

#### S-01 — Start with a problem and route it

Given a vague synthetic service, organizational, interface, or accounting problem, invoke the normal protocol entry point in Claude Code and Codex. Assert that routing selects the appropriate specialist sequence, records the route and rationale, asks only necessary questions, and does not begin with infrastructure setup.

Required evidence: prompt packet, runtime identity, route events, selected specialists/skills, rejected alternatives, and task record.

#### S-02 — Assemble the entitled pieces

Run foundation-only, organization, accounting-department, and synthetic-personal variants. Assert deterministic resolution precedence; immutable source/tree/signer identity; Claude and Codex runtime-specific materialization; Knowledge receipts; bounded CLI capabilities; and one canonical lock that matches disk state.

Required evidence: `resolve --explain`, source receipts, destination inventory, lock, disk hashes, and parity map.

#### S-03 — Apply the work and create something

Use the assembled team to produce a self-contained artifact from a realistic problem: a decision brief, service blueprint, implementation slice, interface specification, or accounting evidence-gap package. Assert that the relevant specialist craft is visible, organization/department context changes decisions rather than vocabulary alone, facts are separated from assumptions, and the output stays in the project.

Required evidence: foundation and layered artifacts, criterion-level evaluation, project tree, ownership declaration, and no external product dependency.

#### S-04 — Preserve and continue

Pause after meaningful decisions and partial work. End the process. Resume in a fresh Claude Code or Codex session using Task Copilot. Assert that the next action, decisions, evidence, unresolved questions, artifact links, and exact ecosystem identities are recoverable without a manually reconstructed prompt.

Required evidence: pre-pause task/WP state, handoff, fresh-process transcript, resumed next action, and idempotence check.

#### S-05 — Keep working through a shared update

Publish or select an approved immutable organization or department update, apply it through `cc update`, and continue the same project. Assert that eligible managed content changes, human-owned work remains byte-identical, the completed-actions ledger is accurate, the new source identity appears in receipts and lock state, and continuation still works.

Required evidence: before/after trees, released ref, update ledger, preservation hashes, resumed artifact, and rollback ref.

#### S-06 — Hold dirty or ambiguous work safely

Repeat update with tracked changes, untracked files, staged changes, intentional customization, interrupted state, and escaping symlinks. Assert preflight holds before destructive mutation, reports the competent actor and exact recovery, and never resets, deletes, rebases, merges, pushes, or rewrites human-owned content.

Required evidence: fixture matrix, before/after hashes, empty or bounded completed-actions ledger, and held-state JSON.

#### S-07 — Exercise entitlement lifecycle and connectivity

Run entitled, unentitled, offline, stale, revoked, and reauthorized states for organization and accounting layers. Assert protected layers fail closed, previously downloaded content is not falsely described as current entitlement, recovery names the correct actor, and reauthorization restores the exact approved source rather than a mutable branch.

Required evidence: state transition log, access probes without credential values, active/inactive materialization state, and recovery result.

#### S-08 — Exercise operational capability failures

Run an available capability, an absent optional capability, a timeout, malformed output, and a security-mandatory denial. Assert optional transports fail open with a recorded limitation, mandatory security blocks before agent/knowledge execution, and no secret value enters prompts, logs, locks, or work products.

Required evidence: bounded invocation transcript, exit/result contract, redaction check, route continuation or denial, and task event.

#### S-09 — Reject provenance and boundary attacks

Inject an unsigned tag, wrong signer, moved tag, missing path, mutable ref, tampered lock, secret-bearing URL, cross-tier write, personal marker, hardlink/symlink escape, and mismatched materialized bytes. Assert fail-closed behavior before executable-adjacent consumption or shared write.

Required evidence: one positive control per validator, negative fixture results, filesystem boundary proof, credential-path inspection, and integrated security verdict.

#### S-10 — Prove Claude/Codex intent parity

Run the same eligible cases in both runtimes. Assert equivalent organizational purpose, specialist selection intent, Knowledge use, safety posture, ownership, and durable output expectations. Runtime-specific implementation may differ, but every unsupported surface must be explicit and dispositioned.

Required evidence: criterion-by-criterion parity table, exact runtime/model/plugin identities, artifacts, and supported/unsupported decision record.

#### S-11 — Propagate safely across the approved fleet

Regenerate the exact census after releases, obtain Pablo's approval of the mutation set, pilot representative repositories, then update every eligible clean project. Exclude Hermes and every dirty, unentitled, archived, ambiguous, or explicitly held repository according to the approved census.

Required evidence: census identity, owner approval, pilot result, per-repository ledger, exclusions, postconditions, and post-fan-out conformance/security reports.

#### S-12 — Reproduce the ecosystem in a clean environment

Use a dedicated empty home with no copied caches, checkouts, locks, credentials, or task state. Install the released framework, authenticate normally, run S-01 through S-05 at minimum, exercise S-07 recovery, and finish with conformance. Control Tower must not be installed or used.

Required evidence: environment inventory, install transcript, exact identities, scenario artifacts, fresh-session continuation, update proof, and independent QA verdict.

## Test matrix

The suite uses risk-based required cells instead of an unbounded Cartesian product.

| Axis | Required cells |
| --- | --- |
| Runtime | Claude Code; Codex; explicit unsupported cell where parity is unavailable |
| Layer set | Foundation; foundation + organization; foundation + organization + accounting; synthetic personal overlay where allowed |
| Lifecycle | Fresh install; idempotent reinstall; update; pause/resume; failure recovery |
| Entitlement | Entitled; unentitled; offline; stale; revoked; reauthorized |
| Project state | Clean; tracked dirty; untracked; staged; customized; interrupted; symlink/hardlink boundary |
| Source trust | Valid signed immutable ref; unsigned; wrong signer; moved/mutable; missing path; mismatched tree/bytes |
| Capability | Available success; optional missing; timeout; malformed result; mandatory denial |
| Evidence type | Deterministic structural; transactional; behavioral; security; provenance |

Minimum runtime coverage:

- S-01 through S-05 and S-10 run in Claude Code and Codex where the capability is supported.
- S-06 through S-09 run at the shared implementation boundary plus runtime-specific adapters.
- S-11 runs across the exact approved fleet.
- S-12 runs once per supported runtime from the same released ecosystem identities.
- EVAL-01, EVAL-02, one of EVAL-03/EVAL-04, and EVAL-05 retain foundation and applicable layered variants. There is no aggregate score; any hard safety or ownership violation fails the case.

## Evidence contract

Each passing claim records:

- scenario and test-cell identity;
- exact repository, commit, tree, tag, signer, framework version, runtime/model, plugin, and fixture digest where applicable;
- preconditions and relevant environment facts without credential values;
- commands or supported entry points used;
- raw machine-readable result;
- output/project artifact and content hash;
- Task Copilot task, work-product, QA, and security links;
- deviation, disposition, owner, and recovery path when the result is not a clean pass.

Narrative assertions, screenshots without source identity, and aggregate percentages cannot close a gate.

## Final technical acceptance gates

| Gate | Passing evidence |
| --- | --- |
| Released identities | Framework, organization, and accounting changes are merged under ADR-011, published as signed immutable refs, pinned, installed, and matched at runtime |
| Canonical setup/update | Clean and degraded installs converge; dirty/ambiguous work holds; lock and disk agree; reruns are idempotent |
| Conformance truth | Full no-cache run has zero S0, zero unexplained could-not-run, zero unreviewed regressions, and reviewed dispositions for every residual |
| Runtime integration | Claude Code and Codex complete required scenario cells with explicit parity or explicit supported exceptions |
| Layered behavior | Required evaluations show attributable organization/accounting method and artifact differences without foundation, safety, privacy, or ownership regression |
| Operational continuity | CLI capabilities obey mandatory/optional failure semantics; Task Copilot preserves and resumes work across a fresh process |
| Security | Provenance, entitlement, personal/shared, secret, project-work, and filesystem attacks fail closed; pre/post propagation security verdicts pass |
| Propagation | Exact owner-approved eligible fleet receives the release with per-repository ledgers and held repositories untouched |
| Clean environment | A fresh home completes install, problem intake, assembly, creation, preservation, resume, update, recovery, and conformance without Control Tower |
| Provenance | Initiative, PRD, tasks, work products, source identities, tests, security, and final verdict cross-link and can be recovered later |

## Task sequence

1. Complete TASK-306 and TASK-307 as the governance and scope baseline.
2. Use TASK-297 to reconcile the three clean PRs, merge only on Pablo's explicit instruction, publish signed immutable releases, update pins, and prove live consumers.
3. Close TASK-296 and TASK-284 against those exact released inputs.
4. Run TASK-285's required behavioral cases and parity evidence.
5. Reconcile full conformance, including the six S0 rows, the Control Tower lock mismatch, `expected_today` contradictions, and structured residual dispositions.
6. Run TASK-291 integrated security against the exact release and evaluation artifacts.
7. Regenerate and approve TASK-300's exact census, then execute TASK-288 and TASK-299.
8. Execute TASK-303's clean-environment scenario set.
9. Run TASK-292 as the final technical-readiness and provenance audit.
10. Begin Pablo's dogfooding record as future product-validation work; do not reopen Control Tower automatically.

## Final verdict language

- **Technically ready for owner dogfooding:** every active gate above passes with linked evidence.
- **Active and incomplete:** one or more active technical gates lacks evidence or has a rejected verdict.
- **Held:** a safe external prerequisite prevents execution and the competent actor and recovery path are recorded.
- **Rejected:** a completion claim depends on missing identity, hidden manual wiring, weakened security, simulated runtime behavior, or damage to human-owned work.

The current verdict is **active and incomplete**.
