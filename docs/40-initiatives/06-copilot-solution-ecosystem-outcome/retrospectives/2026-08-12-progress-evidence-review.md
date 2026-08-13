# Initiative 06 progress and acceptance-evidence review

Updated: 2026-08-13

Execution record: PRD-23, parent TASK-278

Evidence window: current task graph and work products through WP-917

Disposition: **Framework active; app track deferred; outcome not yet achieved**

## Plain-language answer

Apple app installation is no longer on this program's critical path. ADR-009
(WP-838), remediation WP-852, and fresh QA WP-853 move every app release and
installation requirement intact to owner-deferred PRD-24/TASK-301. The split
does not waive app security; it prevents Apple packaging from blocking proof of
the framework, content, routing, evaluation, fleet, and human outcome.

The framework itself has advanced. This Mac runs one exact reviewed framework
snapshot; an isolated fixture proves the exact organization and accounting
inputs through signed resolution, immutable materialization, selective
revocation, and deprovision; and TASK-296's production journey wiring now has
local implementation, QA, and security approval. That approval is bounded to
the local framework at WP-913 commit `db397cd`, QA WP-917, and security WP-915.
TASK-296 still needs a live signed journey against TASK-297's protected
organization and accounting releases before it can complete.

What changed materially:

- WP-838 established the one-way framework/app split. WP-852 removed the final
  app-only obligations from the framework security contract, and WP-853
  approved commit `ee9a49a`: both stream plans pass, the 303-task graph is
  acyclic, and no PRD-23 task reaches a PRD-24 task.
- WP-841 normalized the local `cc` and Codex Copilot installation to exact PR
  #66 commit `f3a3bc9`, tree `7b74d4e`, with one enabled plugin and rollback
  artifacts. Independent QA WP-844 approved the exact snapshot, 62/62 lock
  checks, 32 skills, and `cc` 2.12.8. This is local reviewed-snapshot evidence,
  not a protected hosted release.
- WP-850 exercised the exact organization and accounting content commits with
  ephemeral local signed tags. Both tiers resolved to distinct immutable
  snapshots; revoking accounting preserved organization; deprovision removed
  indexed content without touching unrelated state; 95 focused tests passed.
  The fixture does not replace protected merges, published tags, entitlement-
  qualified live proof, or provider garbage collection in TASK-297.
- TASK-296's production journey implementation at commit `db397cd`, tree
  `385f6ef`, now connects the canonical protocol route, signed Knowledge
  receipts, Agent dispatch authorization, and Task Copilot continuation while
  preserving exactly-once recovery and replay denial. QA WP-917 approved the
  322-test affected matrix, 500 contention repetitions, and 20 real-process
  runs; security WP-915 approved the same exact commit with no open local
  findings. The TASK-297 live signed proof remains open.
- TASK-284 now has an approved provisional foundation at commit `b2f72d`, tree
  `edfdef7`: closed schemas, models, fixtures, and safety controls passed 54
  focused tests under QA WP-882. This is not the completed behavioral-
  effectiveness contract; live release identities and the accepted TASK-296
  journey are still prerequisites for the final controls and evaluation run.
- The framework QA gate itself is repaired at signed Control Tower commit
  `e67088`, tree `e487c61`. WP-903 binds evidence to the exact selected QA row
  and accepts exactly one non-contradictory passing verdict; independent QA
  WP-904 approved 18 authored and 23 independent identity/verdict cases.
- WP-829 preserves a fresh 75-row fleet census with every row pending and
  `authorized_mutations=0`. It is preparation only and must be regenerated with
  current entitlement evidence after TASK-297.

## Program snapshot

| State | Tasks | Meaning |
| --- | --- | --- |
| Completed with accepted bounded evidence | TASK-279, 280-283, 293-295 | Eight framework foundation tasks are complete. |
| Active framework delivery | TASK-296, 297 | Local journey wiring is approved; its live signed proof waits on the protected content release. |
| Pending framework downstream | TASK-284, 285, 288, 290-292, 299, 300, 303 | TASK-284 has an approved provisional foundation; evaluation, security, census/fleet, clean-environment, human, and final-audit completion remains dependency-gated. |
| Deferred app track | PRD-24 / TASK-286, 287, 289, 298, 301, 302 | App evidence is preserved but does not block or count toward the framework verdict. |
| Parent | TASK-278 active | No final framework outcome claim is authorized. |

## Current active gates

### Locally approved production framework journey — TASK-296

- WP-913 is the locally approved production implementation at commit
  `db397cd`, tree `385f6ef`; QA WP-917 and security WP-915 reviewed those exact
  bytes and report no open local findings.
- The production path preserves one router and one signed Knowledge resolver,
  projects attributable receipts, records actual dispatch authorization, keeps
  Task Copilot as continuation authority, and denies completed-marker replay.
  A dispatch-only interrupted state can recover once only after current
  security and signed Knowledge are revalidated.
- QA WP-917 passed 322 affected tests, 500/500 thread contention repetitions,
  20/20 real-tc process runs, and both dedicated hook harnesses. Security
  WP-915 separately approved replay, chronology, lock, fork, persistence,
  provenance, revocation, and disclosure boundaries.
- **Remaining gate:** after TASK-297 publishes protected immutable inputs, run
  the representative journey against those exact signed organization and
  accounting identities. Local approval is not a protected-release or live-
  consumer claim.

### Provisional behavioral-evaluation foundation — TASK-284

- Commit `b2f72d`, tree `edfdef7`, provides the schema/model/fixture/safety-only
  foundation. QA WP-882 approved 54 focused tests plus lint, format, compile,
  and AST-identical formatting verification with no open provisional findings.
- The foundation includes closed and versioned evidence structures and hardened
  fixture/safety handling. It does not yet contain the final release-bound
  controls, real Claude/Codex attempts, comparison results, or an outcome
  verdict.
- **Remaining gate:** bind the final contract to accepted TASK-296 and TASK-297
  identities, then run TASK-285's controlled evaluations.

### Signed organization and accounting inputs — TASK-297

- PR #66 is bound to locally approved commit `f3a3bc9`, tree `7b74d4e`. The
  local runtime is normalized to those exact bytes under WP-841/WP-844.
- WP-850 proves the exact organization commit `c51784d`, tree `90b9aed`, and
  accounting commit `e0471f5`, tree `310156c`, through a disposable signed
  lifecycle fixture. It proves framework behavior against exact inputs without
  claiming a hosted release.
- PR #66, Organization PR #1, and Accounting PR #1 still need independent human
  approval. PR #66 still needs its required CodeQL check when Actions are
  restored through the approved maintenance ledger.
- GitHub Support must confirm removal of the legacy unreachable accounting
  object, and business owners must affirm or remove each inherited reader.
- Protected merges, new immutable signed tags/pins, and exact entitlement-
  qualified live consumer evidence remain required.

### Evidence-gate integrity — TASK-278

- WP-903 repairs the framework QA gate at signed commit `e67088`, tree
  `e487c61`. The gate now requires the fetched work-product row to match the
  selected QA ID and requires exactly one recognized, passing verdict.
- Independent QA WP-904 approved all 18 authored and 23 independent identity,
  substitution, title, guard, binding, and contradictory-verdict cases. This
  makes the remaining evidence gates stricter; it does not complete TASK-278.

### Fleet and validation preparation

- TASK-297's hosted approvals and TASK-300's post-release owner-approved census
  are the remaining remote/owner gates before any fleet mutation can begin.
- WP-829 records 75 rows: 42 dependency-pending candidates, 32 classification
  exclusions, and one safety hold. Every row is pending, ineligible, and
  plan-free, so it grants no mutation authority.
- TASK-300 must regenerate and obtain approval for an exact eligible census
  after TASK-297. TASK-288 may touch only that approved set through canonical
  `cc`; TASK-299 then checks entitlement and ownership boundaries.
- TASK-303 and TASK-290 remain real proof gates: an isolated framework journey
  and an observed non-technical participant journey. Neither requires the app.

## Acceptance evidence matrix

| AC | State | Evidence held now | What remains |
| --- | --- | --- | --- |
| AC-01 | Accepted stream gate | TASK-279/294 QA and security | Final integrated run against released refs |
| AC-02 | Accepted stream gate | TASK-280 QA | Final integrated full run |
| AC-03 | Partial | Approved transaction, conformance, and baseline work | Final live zero-S0 fleet result |
| AC-04 | Partial | Actionable unknown semantics | Final fleet-wide live verification |
| AC-05 | Accepted stream gate | TASK-281 QA | Revalidate after integration |
| AC-06 | Accepted stream gate | TASK-280 QA | Final integrated conformance |
| AC-07 | Partial | Approved organization inputs, signed consumer mechanics, WP-850 exact fixture | Protected release and exact entitled live proof |
| AC-08 | Partial | Signed sanitized accounting root, protected runtime approval, WP-850 lifecycle fixture | Provider GC, protected release, exact entitled live proof, and EVAL-05 |
| AC-09 | Partial | Approved `uids`/`cco` inputs | Immutable release and integrated loader proof |
| AC-10 | Pending | Phase 4 and WP-718 architecture | TASK-284/285 controlled behavior artifacts |
| AC-11 | Provisional foundation approved | TASK-284 commit `b2f72d`, QA WP-882, 54 tests | Bind final controls to released identities and run them |
| AC-12 | Partial | Transaction/content gates and WP-915 production-journey security approval | Behavioral leak cases and integrated framework security |
| AC-13 | Preparation approved | WP-829 zero-authority 75-row census | Post-TASK-297 approved census and fan-out proof |
| AC-17 | Preparation approved | WP-829 deterministic provisional census | TASK-300 approval, TASK-288 execution, integrated QA |
| AC-18F | Pending | Clean-framework protocol | TASK-299, then TASK-303 execution |
| AC-19F | Pending | Participant protocol | TASK-303, then observed TASK-290 journey |
| AC-20 | Partial | Durable tasks/work products plus exact-row QA gate WP-903/WP-904 | Protected releases and final TASK-292 validator |
| AC-21 | Accepted stream gate | TASK-295 QA/security plus WP-850 selective revoke/deprovision proof | Preserve through integrated review |
| AC-22 | Local production approved; live proof pending | WP-913 implementation, QA WP-917, security WP-915 | TASK-297-bound live signed organization/accounting journey |
| AC-23 | Active gate | Owner decisions, protected inputs, exact local runtime, WP-850 signed fixture | Human reviews, CodeQL, provider GC, roster decision, protected tags/pins, exact entitled proof |

The full criterion wording remains in the [PRD acceptance matrix](../phases/phase-1-outcome-prd.md#8-acceptance-criteria-and-current-evidence).
App criteria APP-AC-01 through APP-AC-04 are tracked only in [PRD-24](../tracks/control-tower-app-release-prd.md).

## What each remaining task will do

| Task and plain-language purpose | Current prerequisite or constraint | Concrete evidence required for completion |
| --- | --- | --- |
| **TASK-278: Deliver the framework outcome program.** | Every PRD-23 child gate must pass; PRD-24 is explicitly outside this verdict. | Every framework criterion accepted and linked through TASK-292. |
| **TASK-284: Build the behavioral-effectiveness contract and fixtures.** | Provisional schema/model/fixture/safety foundation `b2f72d` is approved by QA WP-882; final work waits for TASK-296/TASK-297 identities. | Release-bound controls, rubrics, runtime/content identity, safety gates, negative fixtures, and final QA/security. |
| **TASK-285: Run the controlled Claude/Codex evaluations.** | Waits for TASK-284 and TASK-296. | Criterion-level attempts and comparisons, safety results, parity dispositions, foundation non-regression. |
| **TASK-288: Remediate or disposition the eligible fleet.** | Waits for TASK-285, TASK-291, and owner-approved TASK-300. | Per-repository canonical-transaction ledger with explicit safe skips. |
| **TASK-290: Validate with a consenting non-technical person.** | Waits for TASK-299 and clean-environment TASK-303. | Observed rubric, privacy-safe findings, no terminal work or Pablo intervention. |
| **TASK-291: Perform integrated framework security before fleet mutation.** | Waits for exact content, evaluation, and production-journey evidence. | Review of signer policy, entitlements, locks, evaluation artifacts, census boundaries, and safe mutation. |
| **TASK-292: Run final framework QA, provenance, and outcome audit.** | Runs last after fleet, post-fan-out security, clean-environment, and human proof. | All PRD-23 criteria linked to exact work products, commits, reviews, releases, and validation. |
| **TASK-296: Integrate protocol, capabilities, Knowledge, and Task Copilot continuity.** | WP-913 production wiring is locally approved by QA WP-917 and security WP-915; TASK-297 still gates the live proof. | Representative journey against exact protected signed organization/accounting inputs, with preserved dispatch and continuation receipts. |
| **TASK-297: Publish signed immutable organization and accounting inputs.** | Human reviews, CodeQL, provider GC, and roster confirmation remain external gates. | Protected merges, immutable signed tags/pins, signer policy, and exact entitled consumer identities. |
| **TASK-299: Verify post-fan-out entitlement and ownership boundaries.** | Runs immediately after TASK-288. | Per-repository proof of no cross-entitlement, personal/shared, secret, symlink, lock, or ownership breach. |
| **TASK-300: Approve the exact fleet census.** | WP-829's 75-row census is bounded preparation with zero mutation authority; it must regenerate after TASK-297 with current entitlement evidence. | Deterministic row-level plans, independent QA, immutable census identity, explicit owner approval, and nonzero authority only for eligible rows. |
| **TASK-303: Prove the journey in a clean framework environment.** | Waits for TASK-299; app installation is irrelevant. | Isolated setup, materialization, routing, update, conformance, and continuation evidence. |

The completion evidence above is a gate, not a forecast. A task remains unfinished until its named artifacts and independent decisions exist.

## Dependency-safe path forward

1. Obtain independent human review for PR #66 and both content PRs; restore only authorized Actions checks and satisfy required CodeQL.
2. Complete provider garbage collection and the need-to-have reader decision; then publish protected signed content tags/pins and prove exact entitled consumption.
3. Run TASK-296's locally approved production journey against those exact signed inputs.
4. Finish TASK-284 from its approved provisional foundation and run TASK-285's controlled evaluations.
5. Complete framework-only integrated security, regenerate and approve TASK-300's entitlement-qualified census, execute TASK-288, and run TASK-299.
6. Execute clean-environment TASK-303 and observed participant TASK-290, then close only through TASK-292.
7. Resume PRD-24 separately when app release and installation become a priority.

## Claim boundary

It is accurate to say that the app no longer blocks the framework graph; the
local runtime matches the reviewed framework snapshot; exact signed-content
lifecycle behavior has bounded proof; TASK-296 production wiring is locally
approved; TASK-284 has an approved provisional foundation; and the exact-row QA
gate is independently approved. It is not accurate to say TASK-296 has live
signed release proof or to claim completion of protected content release,
behavior effectiveness, fleet propagation, clean-environment proof, or
non-technical-person validation.

This report does not approve a PR, restore Actions, merge or tag content,
authorize fleet mutation, publish an app, or close either PRD.
