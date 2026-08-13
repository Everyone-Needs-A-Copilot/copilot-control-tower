# Initiative 06 progress and acceptance-evidence review

Updated: 2026-08-13

Execution record: PRD-23, parent TASK-278

Evidence window: current task graph and work products through WP-857

Disposition: **Framework active; app track deferred; outcome not yet achieved**

## Plain-language answer

Apple app installation is no longer on this program's critical path. ADR-009
(WP-838), remediation WP-852, and fresh QA WP-853 move every app release and
installation requirement intact to owner-deferred PRD-24/TASK-301. The split
does not waive app security; it prevents Apple packaging from blocking proof of
the framework, content, routing, evaluation, fleet, and human outcome.

The framework itself has advanced. This Mac now runs one exact reviewed
framework snapshot; an isolated fixture proves the exact organization and
accounting inputs through signed resolution, immutable materialization,
selective revocation, and deprovision; and the deterministic protocol journey
contract has independent QA and security approval. The immediate engineering
step is production wiring: connect that contract to the real protocol trace,
signed Knowledge resolver, Agent dispatch hook, and Task Copilot continuation
path described in WP-846. The approved contract is not yet evidence that those
production boundaries are connected.

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
- TASK-296's deterministic journey contract at commit `dfaafbe` now binds
  canonical content to verifier-issued Knowledge provenance, fails mandatory
  security closed, serializes continuation across processes, binds Task Copilot
  rows, and avoids persisting plaintext prompts. QA WP-856 and security WP-857
  approve 23 focused tests and the final attack matrix. Production wiring and a
  live signed journey remain open.
- WP-829 preserves a fresh 75-row fleet census with every row pending and
  `authorized_mutations=0`. It is preparation only and must be regenerated with
  current entitlement evidence after TASK-297.

## Program snapshot

| State | Tasks | Meaning |
| --- | --- | --- |
| Completed with accepted bounded evidence | TASK-279, 280-283, 293-295 | Eight framework foundation tasks are complete. |
| Active framework delivery | TASK-296, 297 | Production journey wiring and protected content release are the current gates. |
| Pending framework downstream | TASK-284, 285, 288, 290-292, 299, 300, 303 | Evaluation, security, census/fleet, clean-environment, human, and final-audit work remains dependency-gated. |
| Deferred app track | PRD-24 / TASK-286, 287, 289, 298, 301, 302 | App evidence is preserved but does not block or count toward the framework verdict. |
| Parent | TASK-278 active | No final framework outcome claim is authorized. |

## Current active gates

### Production framework journey — TASK-296

- WP-855 is the approved deterministic contract implementation at commit
  `dfaafbe`, tree `b244ff5`; QA WP-856 and security WP-857 report no open
  findings in that bounded scope.
- The contract proves canonical content attribution, verifier-issued provenance,
  mandatory-security fail-closed behavior, task-bound persistence, disclosure
  controls, and one-host concurrent continuation serialization.
- It does not yet prove real protocol-to-Knowledge invocation. WP-846 is the
  accepted production architecture: the existing protocol remains the only
  router, the existing signed Knowledge stack remains the only resolver, the
  existing Agent hook records actual dispatch, and Task Copilot remains the
  continuation authority.
- **Next step:** implement and verify `cc journey` production adapters and CLI,
  receipt-preserving signed Knowledge composition, actual Agent dispatch
  enforcement, and exact pause/resume behavior. Then run the local production
  harness and, after TASK-297, the live signed organization/accounting proof.

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

### Fleet and validation preparation

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
| AC-11 | Pending | Criterion-wise foundation-control contract | Implement and run controls |
| AC-12 | Partial | Transaction/content gates and WP-857 journey-contract security approval | Behavioral leak cases and integrated framework security |
| AC-13 | Preparation approved | WP-829 zero-authority 75-row census | Post-TASK-297 approved census and fan-out proof |
| AC-17 | Preparation approved | WP-829 deterministic provisional census | TASK-300 approval, TASK-288 execution, integrated QA |
| AC-18F | Pending | Clean-framework protocol | TASK-299, then TASK-303 execution |
| AC-19F | Pending | Participant protocol | TASK-303, then observed TASK-290 journey |
| AC-20 | Partial | Durable tasks, work products, commits, reviews, and this report | Protected releases and final TASK-292 validator |
| AC-21 | Accepted stream gate | TASK-295 QA/security plus WP-850 selective revoke/deprovision proof | Preserve through integrated review |
| AC-22 | Approved contract; production pending | WP-855 implementation, QA WP-856, security WP-857 | WP-846 production wiring, live signed journey, final delta QA/security |
| AC-23 | Active gate | Owner decisions, protected inputs, exact local runtime, WP-850 signed fixture | Human reviews, CodeQL, provider GC, roster decision, protected tags/pins, exact entitled proof |

The full criterion wording remains in the [PRD acceptance matrix](../phases/phase-1-outcome-prd.md#8-acceptance-criteria-and-current-evidence).
App criteria APP-AC-01 through APP-AC-04 are tracked only in [PRD-24](../tracks/control-tower-app-release-prd.md).

## What each remaining task will do

| Task and plain-language purpose | Current prerequisite or constraint | Concrete evidence required for completion |
| --- | --- | --- |
| **TASK-278: Deliver the framework outcome program.** | Every PRD-23 child gate must pass; PRD-24 is explicitly outside this verdict. | Every framework criterion accepted and linked through TASK-292. |
| **TASK-284: Build the behavioral-effectiveness contract and fixtures.** | Waits for accepted TASK-296 production integration and TASK-297 identities. | Versioned controls, rubrics, runtime/content identity, safety gates, negative fixtures, QA/security. |
| **TASK-285: Run the controlled Claude/Codex evaluations.** | Waits for TASK-284 and TASK-296. | Criterion-level attempts and comparisons, safety results, parity dispositions, foundation non-regression. |
| **TASK-288: Remediate or disposition the eligible fleet.** | Waits for TASK-285, TASK-291, and owner-approved TASK-300. | Per-repository canonical-transaction ledger with explicit safe skips. |
| **TASK-290: Validate with a consenting non-technical person.** | Waits for TASK-299 and clean-environment TASK-303. | Observed rubric, privacy-safe findings, no terminal work or Pablo intervention. |
| **TASK-291: Perform integrated framework security before fleet mutation.** | Waits for exact content, evaluation, and production-journey evidence. | Review of signer policy, entitlements, locks, evaluation artifacts, census boundaries, and safe mutation. |
| **TASK-292: Run final framework QA, provenance, and outcome audit.** | Runs last after fleet, post-fan-out security, clean-environment, and human proof. | All PRD-23 criteria linked to exact work products, commits, reviews, releases, and validation. |
| **TASK-296: Integrate protocol, capabilities, Knowledge, and Task Copilot continuity.** | Deterministic contract is approved; production wiring and live signed proof remain. | WP-846 wiring, actual-dispatch receipts, exact pause/resume, production harness, signed live proof, delta QA/security. |
| **TASK-297: Publish signed immutable organization and accounting inputs.** | Human reviews, CodeQL, provider GC, and roster confirmation remain external gates. | Protected merges, immutable signed tags/pins, signer policy, and exact entitled consumer identities. |
| **TASK-299: Verify post-fan-out entitlement and ownership boundaries.** | Runs immediately after TASK-288. | Per-repository proof of no cross-entitlement, personal/shared, secret, symlink, lock, or ownership breach. |
| **TASK-300: Approve the exact fleet census.** | Must regenerate after TASK-297 with current entitlement evidence. | Deterministic row-level plans, independent QA, immutable identity, explicit owner approval. |
| **TASK-303: Prove the journey in a clean framework environment.** | Waits for TASK-299; app installation is irrelevant. | Isolated setup, materialization, routing, update, conformance, and continuation evidence. |

The completion evidence above is a gate, not a forecast. A task remains unfinished until its named artifacts and independent decisions exist.

## Dependency-safe path forward

1. Implement WP-846's production journey wiring without adding a second router or resolver; run focused, hook, continuation, and local production-harness checks.
2. Obtain independent human review for PR #66 and both content PRs; restore only authorized Actions checks and satisfy required CodeQL.
3. Complete provider garbage collection and the need-to-have reader decision; then publish protected signed content tags/pins and prove exact entitled consumption.
4. Run TASK-296's live signed proof and final delta QA/security, then complete TASK-284/285.
5. Complete framework-only integrated security, regenerate and approve TASK-300's census, execute TASK-288, and run TASK-299.
6. Execute clean-environment TASK-303 and observed participant TASK-290, then close only through TASK-292.
7. Resume PRD-24 separately when app release and installation become a priority.

## Claim boundary

It is accurate to say that the app no longer blocks the framework graph; the
local runtime matches the reviewed framework snapshot; exact signed-content
lifecycle behavior has bounded proof; and the deterministic journey contract
has QA/security approval. It is not accurate to say production journey wiring,
protected content release, behavior effectiveness, fleet propagation,
clean-environment proof, or non-technical-person validation is complete.

This report does not approve a PR, restore Actions, merge or tag content,
authorize fleet mutation, publish an app, or close either PRD.
