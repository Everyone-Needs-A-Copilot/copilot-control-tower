# Copilot Solution Ecosystem goal audit

> **Superseded as the current decision record later on 2026-08-14.** This audit accurately records the evidence before Pablo changed the initiative scope and repository-governance policy. Independent human review is no longer a non-Hermes ENAC merge gate, Control Tower and long-term human validation are no longer Initiative 06 completion gates, and the active finish line is technical readiness for owner dogfooding. Use the [Phase 5 technical completion plan](phases/phase-5-technical-ecosystem-completion-plan.md), [ADR-010](decisions/adr-010-technical-ecosystem-first.md), and [ADR-011](decisions/adr-011-solo-owner-repository-governance.md) for current decisions. The core technical verdict remains active and incomplete.

- Date: 2026-08-14
- Initiative: 06 — Copilot Solution Ecosystem Outcome
- Execution record: PRD-23 / TASK-278
- Audit scope: the framework, content, live machine/fleet evidence, delivery gates, human-outcome proof, and the deferred Control Tower track
- Decision: **THE ECOSYSTEM GOAL HAS NOT YET BEEN ACHIEVED**

Readable version: [Standalone HTML audit](2026-08-14-ecosystem-goal-audit.html)

## Executive answer

No. The work has produced a strong, independently tested **framework release candidate**, but it has not yet produced the outcome Pablo asked for: an ordinary person receiving a trustworthy, company-aware, multidisciplinary solution team without needing technical expertise or Pablo to connect and maintain it.

The distinction matters:

- The **mechanism** is substantially better. A canonical Claude + Codex transaction exists, full conformance now exercises its disposable round trip, the installed candidate passes that round trip 19/19, the framework candidate passed its hosted test matrix, signed-source and entitlement controls are much stronger, real organization/accounting inputs exist, and the evaluation and journey machinery is largely built.
- The **outcome** is not yet demonstrated. The protected framework and content changes remain unreviewed and unpublished, live full conformance still fails, no real layered behavioral evaluation has run, no approved fleet propagation has occurred, no clean-environment journey has passed, and no non-technical participant has completed the workflow.
- The **whole ecosystem** also includes Control Tower's non-technical setup and dependable-supervision job in the original goal. Moving app work to PRD-24 is a legitimate delivery split, but a scope split cannot be used as evidence that the ecosystem's democratization goal is complete.

The honest status is therefore:

> **Framework candidate: technically credible and substantially complete.**
>
> **Framework initiative outcome: active and incomplete.**
>
> **Original ecosystem goal: not achieved.**

This is not a rejection of the work. It is a rejection of a completion claim.

## Goal used for this audit

The governing goal comes from the Initiative 05 outcome audit (removed — see Initiative 05 note):

> Give every person access to a trustworthy, company-aware, multidisciplinary solution team—one that helps them turn real problems into working solutions without requiring technical expertise, while safely carrying the organization's accumulated knowledge and capabilities to them.

That goal requires more than installed copilots. It requires all of these observable outcomes:

1. A person begins with a real problem, not software configuration.
2. The right specialist workflow is assembled across Claude and Codex.
3. Organization, department, and personal context changes the work in an attributable and appropriate way.
4. Operational capabilities are bounded, secure, and usable by the workflow.
5. Task Copilot preserves decisions, evidence, and continuation.
6. The resulting solution remains self-contained and owned by its creators.
7. Shared improvements safely reach every entitled recipient without Pablo manually wiring each project.
8. A non-technical person can use and trust the system without learning Git, terminals, repositories, manifests, layers, or infrastructure.
9. Personal content cannot travel upward into shared layers.
10. Control Tower can make setup and ongoing supervision dependable without becoming a second resolver.

The [product decision lens](../../../SOUL.md) confirms that democratization is the essence. The test is not whether the framework exists; it is whether a non-technical person receives and keeps the capability without their attention. The [architecture principles](../../01-architecture/12-architecture-guiding-principles.md) correctly keep ecosystem truth in `cc`, but that mechanism is only part of the goal.

## Evidence reviewed

This is a point-in-time, evidence-first audit. It used:

- the [2026-08-13 continuation handoff](handoff/2026-08-13-framework-continuation.md);
- the Initiative 05 HTML goal and outcome audit;
- this initiative's goal, PRD, gap analysis, evaluation design, validation protocols, and prior progress report;
- PRD-23 task and work-product state, including TASK-278, TASK-284/285, TASK-288/290/291/292, TASK-296/297, TASK-299/300/303, and WP-966/WP-1013;
- live GitHub state for the three protected PRs;
- the installed `cc 2.12.8` runtime manifest and immutable snapshot identity;
- a fresh disposable round-trip run; and
- a fresh full, no-cache conformance run against the current classified fleet.

No protected merge, tag, release, Actions change, fleet mutation, app change, or external approval was performed during this audit.

## What the work has genuinely achieved

### 1. The canonical install mechanism is real

The installed candidate at framework commit `3e5f12952410fd94e6d7d0f7311c830534ffc638`, tree `986795503108a8658012c07fb106fca2565a8912`, reports `cc 2.12.8` and is materialized from an immutable local snapshot. The runtime manifest binds the `cc` binary, all six global commands, and the single enabled Codex Copilot plugin to that snapshot.

A fresh audit run of:

```text
cc conformance check --layer roundtrip --full --no-cache --json
```

produced 19 pass, 0 fail, and 0 could-not-run results. This closes the original split-installer problem at the candidate level and proves that the current full mode contains the sandboxed round-trip layer.

### 2. The release candidate has meaningful independent verification

Framework PR #66 remains at the exact handoff head. Its hosted CodeQL, conformance, root, `tools/cc`, `tools/tc`, skill, TUI, smoke, onboarding, hardcoded-path, wiring, time-language, and local evaluation checks passed. The billed live-model evaluation was intentionally skipped. WP-1013 binds the hosted and installed evidence to the exact commit and tree with an approved QA verdict.

This is strong candidate evidence. It is not release evidence because the PR has not received the required human review or merged through the protected path.

### 3. Several Initiative 05 root causes moved from design to tested code

The following are no longer merely proposals:

- one canonical Claude + Codex project transaction;
- round-trip coverage in ordinary full conformance;
- reviewed regression-baseline behavior;
- signed, tier-provenant Codex plugin materialization;
- entitlement lifecycle handling for entitled, unentitled, offline, stale, revoked, and reauthorized states;
- substantive ENAC organization inputs and accounting-department inputs;
- `uids` and `cco` organization extension content;
- deterministic protocol/journey, Knowledge-receipt, hook-dispatch, capability, pause/resume, and Task Copilot continuity machinery; and
- a bounded behavioral-evaluation runner and immutable synthetic fixture set.

These are substantial assets and should be preserved.

### 4. The evidence record is much stronger

PRD-23 is active, TASK-278 remains in progress, and the implementation streams carry commit/tree-bound QA and security work products. The handoff names exact runtime, PR, content, evaluation, fleet, and validation dependencies. This is a major improvement over Initiative 05's missing task provenance.

## Why the answer is still no

### Finding 1 — A release candidate is not an entitled, reviewed release

As of this audit, all three protected changes still have zero reviews:

| Protected change | Current state | Consequence |
| --- | --- | --- |
| [Framework PR #66](https://github.com/Everyone-Needs-A-Copilot/claude-copilot/pull/66) | Open, `BLOCKED`, `REVIEW_REQUIRED`, zero reviews | The tested framework head is not a protected merge or immutable release. |
| [Organization content PR #1](https://github.com/Everyone-Needs-A-Copilot/knowledge-copilot-internal/pull/1) | Open, clean/mergeable, zero reviews | The approved organization tree is not a newly published signed immutable input. |
| [Accounting content PR #1](https://github.com/Everyone-Needs-A-Copilot/knowledge-copilot-accounting/pull/1) | Open, `BLOCKED`, `REVIEW_REQUIRED`, zero reviews | The remediation has not passed its required protected review. |

The accounting repository does have a signed `v1.0.0` root and its live E-4 projection works. That does not satisfy the remaining organization release or the accounting remediation review.

### Finding 2 — Full conformance is complete in coverage but not green in truth

A fresh audit run of:

```text
cc conformance check --full --no-cache --json
```

reported `result: fail` with:

| Layer      |  Pass | Fail | Skip | Could not run |
| ---------- | ----: | ---: | ---: | ------------: |
| Tier       |    76 |   15 |   10 |             0 |
| Stack      |    78 |    2 |   32 |             0 |
| Repository | 1,493 |  137 |  527 |             0 |
| Lock       |   318 |    1 |   16 |             0 |
| Round trip |    19 |    0 |    0 |             0 |
| Regression |    22 |    0 |    0 |             0 |

The 155 live failures comprise 6 S0, 81 S1, 39 S2, and 29 S3 rows. The six S0 failures are six views of the unpublished organization-extension condition: `cco`, `do`, `ind`, `sd`, `uids`, and `uxd` do not select the required nearest organization declaration.

The absence of regression-layer failures must not be read as conformance. Of the 155 failed rows, 101 currently carry `expected_today: pass`; the regression comparison being stable only says the committed comparison did not identify a new delta. It does not satisfy the initiative requirement to fix or explicitly disposition the live fleet.

The remaining lock failure is the known Control Tower `scripts/copilot-gate.sh` checksum mismatch. The handoff correctly classifies it as non-S0, but it still remains unresolved.

### Finding 3 — The system is not yet proven effective

The retrospective explicitly separated **installed**, **wired**, and **effective**. The work now has credible installed and structural-wiring evidence, but effectiveness is still absent:

- TASK-284 remains in progress and is explicitly bounded to runner/fixture integration pending signed content.
- TASK-285, which must run the Claude/Codex layered evaluations and preserve outcome evidence, is pending with no work products.
- The hosted live-model evaluation job was skipped.
- EVAL-01, EVAL-02, one of EVAL-03/EVAL-04, and EVAL-05 have not produced the required foundation-versus-layered artifacts.

Therefore there is still no evidence that real ENAC organization and accounting context changes a representative solution's method, decisions, or artifacts in the intended direction without weakening foundation quality.

### Finding 4 — Pablo has not been removed as the rollout layer

Fleet propagation is still preparation, not execution:

- TASK-300 is pending. Its latest census contains 75 exact repository rows but deliberately grants zero mutation authority.
- TASK-288 is pending with no work products; no reviewed change has propagated through the canonical transaction to the approved eligible set.
- TASK-291 and TASK-299, the pre- and post-fan-out security gates, are pending.
- Business need-to-have confirmation for the seven-person access roster and provider-side accounting garbage collection remain external gaps.

Until a released shared change reaches multiple entitled projects safely and without manual copies, the claim that Pablo is no longer the synchronization layer is unproved.

### Finding 5 — The primary user outcome has never been observed

The clean and human gates are still entirely open:

- TASK-303, the isolated clean-environment framework journey, is pending with no work products.
- TASK-290, the real non-technical participant journey, is pending with no work products.
- No second-machine cold start or non-technical completion artifact exists.

This is decisive. The product's primary persona has not demonstrated that they can begin with a problem, follow the specialist workflow, understand its prompts, and continue the work without Pablo or ecosystem vocabulary.

### Finding 6 — The security story is strong but not closed

The candidate has meaningful fail-closed entitlement, signature, lock, symlink, disclosure, and fixture controls. However:

- integrated pre-fan-out and post-fan-out security tasks are still pending;
- behavioral leak evidence is still downstream of the live evaluation;
- WP-966 is an explicit rejected security finding for a same-UID final namespace-binding race in the local evaluator; later bounded integration accepted that residual rather than proving it absent; and
- provider garbage collection and final least-privilege confirmation are not complete.

The residual may be bounded, but an audit cannot silently convert a recorded `VERDICT: REJECTED` into full security closure.

### Finding 7 — The delivery split cannot satisfy the whole-product goal

[ADR-009](decisions/adr-009-framework-app-delivery-split.md) correctly prevents Apple packaging from blocking framework learning. That is a sequencing decision. It is not a redefinition of the original ecosystem goal.

The retrospective assigns Control Tower the job of making the ecosystem installable and dependable for a non-technical person. The product SOUL makes that Bob-first outcome the essence. PRD-24 currently defers app publication, installation, native invariant enforcement, crash-only supervision, app cold machine proof, and the app-specific non-technical journey. Consequently:

- PRD-23 may eventually prove the framework without releasing the app;
- the **full ecosystem goal cannot be declared achieved** until the linked app track and the combined human journey are also proved.

## Initiative 06 outcome-contract audit

Status terms are deliberately qualitative. There is no aggregate score because a high count of passing mechanisms cannot cancel one missing human or safety outcome.

| # | Outcome contract | Audit status | Evidence and remaining gate |
| --: | --- | --- | --- |
| 1 | One canonical complete Claude + Codex setup transaction | **Candidate demonstrated** | Installed 19/19 round trip; protected release still pending. |
| 2 | Full includes round trip, zero S0, zero unexplained unknown | **Partial** | Round trip included and unknowns are zero; six S0 failures remain. |
| 3 | Every residual fixed or reviewed once with owner/reason | **Not demonstrated** | 155 live failures remain; 101 contradict `expected_today: pass`; fleet disposition is pending. |
| 4 | Real organization and department contributions win and lock | **Partial** | Accounting E-4 works; organization release is absent and causes six S0 failures. |
| 5 | `uids` and `cco` receive substantive tier direction | **Partial** | Content is authored and reviewed locally; immutable organization selection is not live. |
| 6 | Controlled evaluations show attributable intended differences | **Not demonstrated** | Runner exists; live layered evaluation has not run. |
| 7 | Personal content/credentials cannot move upward | **Partial** | Strong structural tests exist; behavioral leak and final integrated gates remain. |
| 8 | Approved change reaches the exact eligible fleet safely | **Not demonstrated** | Census is provisional with zero mutation authority; fan-out has not run. |
| 9 | Clean environment and non-technical participant succeed | **Not demonstrated** | TASK-303 and TASK-290 are pending with no evidence. |
| 10 | Task/test/security/release/provenance record is recoverable | **Partial** | `tc` record is strong; releases, final audit, and some current-summary documentation remain open. |
| 11 | Entitlement lifecycle fails safely and routes recovery correctly | **Candidate demonstrated** | Approved implementation and fixtures; final released integrated proof remains. |
| 12 | A real problem flows through routing, context, capabilities, and continuity | **Partial** | Structural journey candidate is tested; live signed-content problem-to-solution proof is pending. |

## Required path to an honest completion claim

The next work should stay in Initiative 06 and close gates in dependency order:

1. Obtain independent human reviews and complete the protected framework, organization, and accounting release sequence. Do not bypass protections.
2. Reinstall only the reviewed immutable framework/content identities; prove signed winners, receipts, lock projections, and the 19/19 round trip.
3. Run full no-cache conformance to zero S0 and zero could-not-run, then review the 101 failing `expected_today: pass` rows and every other residual into either a fix or a structured, owner-backed disposition.
4. Run the bounded behavioral cases across foundation and applicable layered conditions, preserving criterion-level Claude/Codex artifacts without an aggregate quality score.
5. Complete integrated pre-fan-out security, regenerate and approve the exact eligible-fleet census, perform canonical fan-out, and complete post-fan-out security and conformance.
6. Prove the framework in an isolated clean environment and observe a real non-technical participant completing the provisioned problem-to-solution journey without Pablo intervention.
7. Resume the linked PRD-24 Control Tower track and prove the original double-click setup, trustworthy supervision, packaged release, cold-machine, and non-technical ownership outcomes required by the whole ecosystem goal.
8. Run TASK-292 as the final cross-record audit only after these artifacts exist, then close PRD-23/TASK-278 and the overall initiative from evidence.

## Final determination

**Preserve and release the candidate after review. Continue the initiative. Do not declare the ecosystem goal achieved.**

The work has moved the program from “a harness that proves the ecosystem is broken” to “a credible framework candidate with most of the machinery needed to prove the outcome.” That is a major change. The remaining work is no longer a vague technical gap: it is a concrete chain of protected release, live effectiveness, safe propagation, clean-environment proof, non-technical human validation, and the deferred Control Tower delivery.

The finish line remains the same as the original goal: a real person starts with a real problem and receives company-aware multidisciplinary help that changes the solution appropriately, stays safe, survives sessions, reaches the right people without manual wiring, and does not require them to become technical.
