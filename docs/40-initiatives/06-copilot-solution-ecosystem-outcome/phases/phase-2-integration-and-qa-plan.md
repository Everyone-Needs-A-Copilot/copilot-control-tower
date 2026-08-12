# Phase 2 — Integration and QA plan

Date: 2026-08-12
Execution record: PRD-23, parent TASK-278

## Purpose

This plan prevents stream-local success from being mistaken for ecosystem success. Every result must cross the boundaries it claims to fix: source → resolution → materialization → lock → runtime consumption → solution behavior → supervision → human use.

## Evidence classes

| Class | Question it answers | Valid artifacts |
| --- | --- | --- |
| Structural | Is the capability declared and shaped correctly? | schema validation, file checks, source scans, manifest and registry tests |
| Transactional | Does the sanctioned operation produce the right real disk state safely? | isolated Git round-trips, before/after trees, completed-actions ledgers, postcondition checks |
| Attribution | Can every installed item prove where it came from? | `resolve --explain`, immutable refs, content hashes, canonical lock, destination evidence |
| Behavioral | Does nearer-tier content change the resulting work in the intended direction? | controlled prompts, resolved-context identity, output artifacts, bounded rubric verdicts |
| Security | Can authority, secrets, or personal content cross a forbidden boundary? | abuse fixtures, negative tests, credential/path inspection, independent security review |
| Product | Can the non-technical person understand and complete the journey? | state/copy/a11y checks, clean-home run, signed-artifact run, observed journey record |
| Operational | Does the capability stay working and roll back safely? | cadence runs, crash/clean-Quit behavior, fleet ledgers, immutable release and rollback artifact |
| Provenance | Can a future session recover why the claim was accepted? | Initiative/PRD/task/WP/commit/QA/release cross-links |

## Acceptance traceability

| Acceptance criterion | Producing stream | Independent gate | Minimum passing evidence |
| --- | --- | --- | --- |
| AC-01 Canonical complete transaction | A | Stream-A QA + integrated QA | clean/degraded/dirty isolated round-trips, complete Claude + Codex reference lock, adapter call-path proof |
| AC-02 Full includes round-trip | B | Stream-B QA | CLI help/schema tests and a real ordinary full result containing round-trip checks |
| AC-03 Zero S0 | A + B + F | integrated QA | live full JSON with zero S0; S0 negative fixtures remain red |
| AC-04 Zero unexplained unknown | B + F | integrated QA | each previous could-not-run removed or names prerequisite and competent actor |
| AC-05 Current regression truth | B | Stream-B QA | classified delta record, regenerated baseline, zero unreviewed PASS→FAIL |
| AC-06 Actionable conformance | B | Stream-B QA | global results once, reviewed exclusions structured, authoring distinction tested |
| AC-07 Organization wins | C + A | Stream-C QA | real organization resolve winner, installed file/skill, lock and hash |
| AC-08 Department wins | C + A | Stream-C QA | same chain for accounting-relevant contribution |
| AC-09 `uids`/`cco` extensions | C | Stream-C QA + security | substantive loader result, fallback result, source citations, no personal material |
| AC-10 Behavior changes | D | Stream-D QA | controlled foundation/layered artifacts meeting bounded rubric in applicable runtimes |
| AC-11 Foundation does not regress | D | Stream-D QA | control cases stay within accepted foundation bounds |
| AC-12 Personal cannot leak upward | A + C + D | independent security | cross-tier/secret/upward-write negative suite and path/credential proof |
| AC-13 Shared change propagates | F | Stream-F QA | one immutable nearer-tier release reaches multiple eligible projects without manual copies |
| AC-14 Native invariants enforced | E | Stream-E QA | unconditional CI over shipping Swift and removal of retired-tree proof claim |
| AC-15 Crash-only supervision | E | Stream-E QA + security | crash restart, clean Quit remains quit, install/uninstall, plist `SuccessfulExit:false` |
| AC-16 Plain-language app | E | Stream-E QA | visible/a11y scans and rendering tests with no raw internal tokens |
| AC-17 Fleet dispositioned | F | integrated QA | zero S0/unknown plus machine-readable reviewed disposition for every residual deviation |
| AC-18 Clean-machine journey | G | Stream-G QA | signed artifact, fresh environment, cold-machine transcript, rollback named |
| AC-19 Non-technical person succeeds | G | service-design + QA | observed task success without terminal/Pablo intervention and with actor-correct prompts |
| AC-20 Provenance complete | Z | final QA | cross-link validator and recoverable artifacts for every acceptance claim |
| AC-21 Entitlement lifecycle safe | A + Z | Stream-A QA/security + pre/post-release security | entitled/unentitled/offline/stale/revoked/reauthorization fixtures and no-leak evidence |
| AC-22 Problem-to-solution integration | D | Stream-D QA/security | protocol routing, layered-context identity, optional-transport fail-open, and resumed `tc` continuity artifact |
| AC-23 Signed shared content inputs | C + A | Stream-C QA/security/owner approval + Stream-A consumer proof | immutable signed releases, manifest pins, signer policy, and exact runtime identity |

## Stream QA gates

### Stream A — canonical transaction

- Characterization tests show the pre-change differences between `/setup-project`, `cc workspace`, and Codex setup.
- One implementation owns resolution, preflight, materialization, ledger, lock generation, and postconditions.
- Adapters contain no independent file-set or lock decisions.
- Clean install is complete and idempotent.
- Degraded eligible install repairs to the same reference result.
- Dirty/customized/ambiguous states hold without reset, overwrite, rebase, merge, delete, or push.
- The three personal-plugin E-4 failures pass for the right reason, while a mismatched fixture still fails.
- Security review covers paths, refs, credentials, and symlink escapes.

### Stream B — conformance truth

- The command/help/schema contract defines full mode once and tests it.
- Round-trip uses only an isolated temporary environment.
- Global result identity is deterministic and cannot accidentally deduplicate repo-scoped failures.
- Structured exclusions require path, reason, decision authority, and review evidence.
- Authoring-checkout acceptance cannot waive mirror requirements for managed consumer checkouts.
- Every could-not-run result names missing evidence rather than becoming skip/pass.
- Expected verdict changes have written rationale and paired fail-shape fixtures.

### Stream C — layered content

- Every new statement traces to ratified organization or department knowledge.
- Content is placed at the narrowest stable layer.
- No personal name, preference, memory, private fact, credential, or client-confidential material is promoted.
- New contributions add company or department substance rather than reproducing foundation instructions.
- Claude and Codex representations express the same intent within runtime conventions.
- `uids` and `cco` extensions use the real loader shape and do not invent brand facts.
- Real resolver output can select the contribution before it is called effective.

### Stream D — behavioral effectiveness

- Cases begin with realistic user problems and hide ecosystem internals from the acting agent where feasible.
- The only planned independent variable is the applicable layer set; runtime/model and prompt fixture are recorded.
- Hard safety failures cannot be averaged away.
- Human judgment uses an explicit rubric and preserves the artifact it judged.
- Exact prose is not required; observable methods, constraints, evidence, and outcome qualities are.
- A foundation-only control establishes that the nearer tier adds value rather than repairing a broken base.

### Stream E — Control Tower trust

- Tests scan or exercise shipping `native/*.swift`, not retired Rust.
- Any new state originates in a versioned CLI contract.
- Unknown contract values fail closed and render in plain language.
- Clean Quit, crash restart, repeated crash, install, uninstall, and rollback are distinct cases.
- The release gate exercises the packaged signed binary.
- Application changes do not stop before version, immutable push, sign, notarize, staple, verification, publication, and rollback provenance.

### Stream F — fleet closure

- Read-only discovery precedes every write.
- Active dirty work, unentitled paths, unresolved exclusions, and out-of-scope security incidents are not mutated.
- Each eligible repo receives a before/after ledger and postcondition.
- Pilot evidence precedes fan-out.
- A residual failure has an owner, reason, and accepted disposition; no bulk acknowledgement hides it.

### Stream G — external validation

- Fresh-home validation does not inherit Pablo's caches, materialized trees, credentials, or untracked fixes.
- Second-machine evidence distinguishes network/entitlement failures from product defects.
- The participant receives only the signed user-facing artifact and ordinary instructions.
- Observers do not coach around product failures.
- No unrelated personal information enters the record.
- If a human participant or second machine is unavailable, the initiative remains active; no simulated result substitutes for the evidence.

## Integration sequence

1. Freeze and record each stream's source commit and task work product.
2. Run stream-local QA against its owned changes.
3. Integrate A + B and run canonical transaction through ordinary full conformance.
4. Integrate C and prove real organization/department attribution, materialization, and lock identity.
5. Run D against the exact integrated content and transaction commits.
6. Produce and verify the signed application candidate, then run independent pre-publication security before fleet fan-out or publication.
7. Publish only the approved app and tier-content releases.
8. Approve the exact fleet census, pilot F through the real cadence/Sync Now path, inspect ledgers, then fan out only to approved eligible projects.
9. Run post-fan-out security and the complete live conformance/regression suite.
10. Run G only against the final signed artifacts and immutable layer refs.
11. Run Z's provenance and outcome audit; mark complete only if every acceptance row has evidence.

## Stop conditions

Integration stops and returns to the owning stream when:

- a check is weakened, deleted, or reclassified without an evidence-backed contract decision;
- a user-facing healthy claim lacks a current CLI proof;
- an operation mutates a dirty or ambiguous human-owned tree;
- personal or secret content appears in a shared path or artifact;
- two installer surfaces still produce different reference results;
- organization/department behavior is claimed from only a synthetic marker;
- application source changes exist without a releasable signed-artifact plan;
- a human or second-machine result is inferred rather than observed.

## Final verdict language

- **Achieved:** all AC-01 through AC-23 have passing, linked evidence.
- **Partially achieved:** a useful technical or content milestone landed, but one or more outcome criteria remain unproved.
- **Rejected:** a completion claim relies on missing evidence, weakened checks, synthetic-only effectiveness, or an unsafe boundary.

There is no “substantially complete” escape hatch for S0 truth, personal privacy, or non-technical journey evidence.
