# Initiative 06 progress and acceptance-evidence review

Date: 2026-08-12

Execution record: PRD-23, parent TASK-278

Evidence window: current task graph plus WP-683 through WP-718, with earlier gate history retained where needed

Disposition: **Active; outcome not yet achieved**

## Plain-language answer

The program has made meaningful, independently reviewed progress, but it has not yet proved the Copilot Solution Ecosystem outcome. The core installation and conformance machinery is substantially stronger, real shared-content inputs exist, and the shipping native app boundary is better tested. That is foundational progress, not the final result.

The entitlement lifecycle is now an accepted stream gate. The release implementation has fresh QA approval but still awaits security and immutable-source candidate proof, while the fleet owner-gate preparation remains rejected:

- WP-716 replaces the replayable shared-interpreter release path with a dedicated compiled launcher. WP-717 approves that implementation, but security review is pending and the reviewed source remains uncommitted/unpushed. There is no verified immutable-source release candidate.
- WP-708 binds entitlement authority through canonical reconciliation. Security WP-713 and QA gate WPs 714/715 approve the bounded evidence, and TASK-295 is complete. Final integrated and release regression proof still remains.
- WP-710 confirms that WP-686's provisional census is deterministic and authorizes nothing, but rejects promotion to an owner gate because approval semantics, repository-specific entitlement, target binding, and one redaction claim are not yet safe.

The organization/accounting release is also waiting at an explicit owner gate. WP-683 is a decision package, not release authority. No commit, push, tag, history rewrite, access change, manifest pin, or publication is claimed. The fleet census in WP-686 is provisional and authorizes zero mutations.

## Program snapshot

| State | Tasks | Meaning |
| --- | --- | --- |
| Completed with recorded QA approval | TASK-279, 280, 281, 282, 283, 286, 293, 294, 295 | Canonical transaction, conformance truth/baseline, content inputs, native invariants/plain language, accounting current-tree containment, signed Codex source mechanics, and entitlement lifecycle have accepted bounded evidence. |
| Active | TASK-287, 297 | Release candidate and shared-content release still require security/immutable-source proof or owner decisions. |
| Pending downstream | TASK-284, 285, 288–292, 296, 298–300 | Behavioral proof, protocol integration, integrated security, publication, approved fan-out, clean-machine/human validation, and final provenance cannot start or close until their dependencies do. |
| Parent | TASK-278 active | The initiative remains open; no final release or outcome verdict is authorized. |

## Gate history through WP-718

### Control Tower release candidate — TASK-287

- WP-697 closed the Git-configuration redirect found in WP-694 and passed QA in WP-698; security WP-700 then rejected Bash startup-file execution and mutable credential-helper trust.
- WP-704 introduced a startup-safe launcher, but QA WP-705 proved its private-entry marker was caller-forgeable.
- WP-707 moved the shell program to a pipe-streamed capability. QA WP-709 proved any foreign Swift script running under the shared interpreter could recreate it.
- WP-716 replaces that path with a dedicated compiled launcher and source/binary identity proof; QA WP-717 approves the implementation and exact foreign-parent negative.
- Evidence-window result: **QA-approved implementation; security and immutable-source candidate pending**. Reviewed changes remain dirty/uncommitted/unpushed, and no signed candidate or publication exists.

### Entitlement lifecycle — TASK-295

- WP-699 bound ordinary update materialization and lock commit to the entitlement revision lease; QA WP-702 approved 39 dedicated and 180 combined tests.
- Security WP-703 then reproduced a canonical plan-to-apply race: a later revocation can occur after fresh plan comparison but before canonical project writes, and the old plan can still install protected content.
- WP-708 adds private entitlement bindings and ordered leases across canonical reconciliation. Independent QA evidence is indexed in WP-714/715, and security WP-713 approves the complete mutation/rollback boundary.
- Evidence-window result: **accepted stream gate**. TASK-295 is complete; final integrated and release regression checks remain downstream.

### Shared content release — TASK-297

- WP-683 records exact proposed content identities, signer procedure, rollback, current access facts, and four owner decisions.
- Evidence-window result: **owner-gated**. Semantic approval, accounting-history disposition, least-privilege access confirmation, and signer authorization remain pending. External/destructive release actions remain unauthorized.

### Problem-to-solution integration — TASK-296

- WP-706 defines a bounded synthetic fixture and deterministic contracts for protocol route evidence, attributable Knowledge consumption, optional-transport fail-open behavior, and fresh-process Task Copilot continuity.
- It explicitly records current adapter gaps, including unproven Codex organization-layer composition receipts, and makes no model-quality or AC-22 claim.
- WP-718 defines TASK-284's exact schema/fixture/runner architecture, foundation controls, hard gates, and synthetic accounting packet. It is also design-only.
- Evidence-window result: **architecture prepared; implementation dependency-gated** by accepted TASK-295 and TASK-297 inputs.

### Fleet census — TASK-300

- WP-686 defines a read-only exact-path schema and a provisional 75-row census. Every row is unapproved and ineligible; target paths are empty and authorized mutations are zero.
- WP-710 independently confirmed deterministic collection, exact classification coverage, wildcard-free paths, digest integrity, and the zero-authority provisional state.
- WP-710 rejected promotion to owner approval because invalid approval combinations and unbound targets pass schema validation, entitlement is fleet-wide rather than repository-specific, and the stored ledger source path contradicts the identity-redaction claim.
- Evidence-window result: **rejected preparation gate**. The current provisional file remains non-authoritative and safe only because it permits no mutation.

## Acceptance evidence matrix

| AC | State | Evidence held now | What remains |
| --- | --- | --- | --- |
| AC-01 | Accepted stream gate | TASK-279/294 QA and security | Final integrated run against released refs |
| AC-02 | Accepted stream gate | TASK-280 QA | Final integrated full run |
| AC-03 | Partial | Approved transaction/conformance/baseline fixes | Final live zero-S0 fleet result |
| AC-04 | Partial | Approved actionable-unknown semantics | Final fleet-wide live verification |
| AC-05 | Accepted stream gate | TASK-281 QA | Revalidate after integration |
| AC-06 | Accepted stream gate | TASK-280 QA | Final integrated conformance |
| AC-07 | Partial | Approved organization inputs and signed consumer mechanics | TASK-297 release/pins and real consumer proof |
| AC-08 | Partial | Bounded accounting contribution and current-tree containment | TASK-297 plus accounting resolution/materialization/EVAL-05 |
| AC-09 | Partial | Approved organization extension inputs | Immutable release and integrated loader proof |
| AC-10 | Pending | Phase 4 design plus WP-718 implementation architecture | TASK-284/285 controlled behavior artifacts after TASK-296/297 |
| AC-11 | Pending | WP-718 criterion-wise foundation non-regression contract | Implement and run foundation controls |
| AC-12 | Partial | Several bounded transaction/content security gates | Behavioral and integrated pre/post-publication security |
| AC-13 | Rejected preparation gate | Deterministic zero-authority census; WP-710 rejection | Repair semantic validation and per-repository entitlement, then approve and execute real fan-out |
| AC-14 | Accepted stream gate | TASK-286 QA/security | Preserve through packaged release |
| AC-15 | Active gate | WP-716 dedicated launcher; WP-717 QA approval | Fresh security, committed/pushed immutable source, and signed candidate proof |
| AC-16 | Accepted stream gate | TASK-286 QA/security | Packaged-release regression check |
| AC-17 | Rejected preparation gate | WP-686 provisional census; WP-710 rejection | Repair census approval/target/redaction contracts, then approve dispositions and execute fleet work |
| AC-18 | Pending | No signed final artifact | Clean-machine/second-machine TASK-289 |
| AC-19 | Pending | No observed user result | TASK-290 |
| AC-20 | Partial | Durable task/WP trail and this matrix | Commit/tag/release links and final validator |
| AC-21 | Accepted stream gate | WP-708 implementation; WP-713 security and WP-714/715 QA approval; TASK-295 complete | Preserve through integrated pre/post-release review |
| AC-22 | Pending | WP-706 journey contract and WP-718 dependent evaluation architecture | Implement after TASK-297, then obtain structural and behavioral evidence |
| AC-23 | Owner-gated | WP-683 decision package | Owner decisions, signed releases, pins, consumer proof |

The fuller criterion wording and evidence requirements remain in the [PRD acceptance matrix](../phases/phase-1-outcome-prd.md#8-acceptance-criteria-and-current-evidence).

## Dependency-safe path forward

1. Preserve TASK-295's accepted entitlement controls through final integrated and release regression checks.
2. Complete security review of WP-716, then build and verify—but do not publish—a candidate from committed and pushed source.
3. Resolve WP-683's four owner decisions for TASK-297; only then perform the approved signed-content release procedure.
4. Implement WP-706's TASK-296 structural journey and WP-718's TASK-284 evaluation contract, then run TASK-285 against those exact entitlement and content identities.
5. Run TASK-291 pre-publication security before TASK-298 publication or any fleet mutation.
6. Repair WP-710's census findings, refresh after TASK-295/297, independently recheck and obtain owner approval, then execute TASK-288 and TASK-299 with per-repository evidence.
7. Run clean-machine TASK-289 and observed-person TASK-290 against the final signed artifacts.
8. Use TASK-292 to validate every acceptance row and publish a final outcome verdict only if all 23 have linked passing evidence.

## Claim boundary

It is accurate to say that the program has accepted foundational transaction, conformance, content-input, native-invariant, and bounded security work. It is not accurate to say the ecosystem is complete, released, fleet-propagated, behaviorally effective, safe under every entitlement race, clean-machine proven, or validated with a non-technical person.

This report records evidence; it does not change task status, approve owner decisions, authorize publication, or authorize fleet mutation.
