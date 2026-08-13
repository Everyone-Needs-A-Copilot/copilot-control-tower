---
initiative: 06-copilot-solution-ecosystem-outcome
title: Copilot Solution Ecosystem — From Conformance to Proven Solution Creation
status: active
status_note: Nine foundational tasks are complete; signed content, protected Knowledge runtime controls, and public Control Tower source now exist, while the root-only publisher anchor, provider purge, human review, hosted CI restoration, outcome, fleet, and human proof remain open.
owner: Pablo Alejo
created: 2026-08-12
execution_context:
  prd: PRD-23
  tasks: TASK-278 parent; TASK-279 through TASK-300 delivery graph
superseded_by: null
---

# Copilot Solution Ecosystem — From Conformance to Proven Solution Creation

> Mode: Initiative
> Status: Active
> Source evidence: Initiative 05 audit and live `cc conformance`

## Goal

Give every person access to a trustworthy, company-aware, multidisciplinary solution team—one that helps them turn real problems into working solutions without requiring technical expertise, while safely carrying the organization's accumulated knowledge and capabilities to them.

The ultimate goal is democratizing high-quality solution creation, not merely installing and maintaining a collection of copilots.

## Scope

This initiative closes the distance between a mechanically installed ecosystem and one that demonstrably improves the solutions people create. It covers:

- one canonical, complete Claude + Codex project-install transaction;
- truthful, complete conformance and regression evidence;
- real organization and accounting-department contributions;
- Claude/Codex parity and specialist-extension coverage;
- controlled behavioral evaluation of company- and department-specific outcomes;
- personal-layer isolation and inherited-content security;
- Control Tower's native enforcement and crash-recovery gaps;
- fleet remediation, clean-machine proof, and non-technical user validation;
- durable documentation and Task Copilot provenance.

## Non-Goals

- synchronizing or taking ownership of the products people build;
- putting ecosystem resolution, health scoring, signature verification, merge, or wipe logic in Control Tower;
- MDM, fleet surveillance, telemetry, a hosted dashboard, or employee monitoring;
- a chat surface or an AI “copilot of the copilots” inside Control Tower;
- Windows or the retired Tauri/Rust implementation;
- secrets in inherited content or Git repositories;
- real-time inherited-content refresh;
- reviving the deferred `repair` or `publish` verbs without a superseding ADR;
- declaring general availability before cold-machine and non-technical-person evidence exists.

## Outcome contract

The initiative is complete only when all of the following are true:

1. A sanctioned setup path produces the complete Claude + Codex reference install and every other setup surface delegates to that transaction.
2. Ordinary `cc conformance check --full` includes round-trip verification, reports zero S0 failures, and has no unexplained could-not-run results.
3. All remaining failures are either fixed or represented once as reviewed, evidence-backed exceptions with an owner and reason.
4. Real organization and department contributions win resolution, materialize into a project, and are recorded in its lock.
5. The `uids` and `cco` specialists receive substantive tier-appropriate direction where their work requires it.
6. Controlled evaluations show attributable company-context, department-method, decision, and artifact differences in the intended direction without reducing foundation quality; they do not claim generalized solution quality.
7. Personal content and credentials cannot move into shared layers; the proof includes negative leak fixtures.
8. Control Tower renders only CLI-computed truth in plain language, its native Swift invariants run in CI, and crash-only supervision is implemented with `KeepAlive` never set to `true`.
9. A clean-machine installation and a real non-technical user journey complete without terminal work or Pablo acting as the synchronization layer.
10. The task, test, security, release, and provenance record is recoverable from the initiative and `tc`.
11. Entitled, unentitled, offline, stale, and revoked access states fail safely and explain who can recover them.
12. A representative problem actually flows through protocol routing, layered specialist context, bounded operational capabilities, and durable Task Copilot continuity.

## Execution documents

- [Goal-to-current-state gap analysis](phases/phase-0-goal-gap-analysis.md)
- [Comprehensive outcome PRD](phases/phase-1-outcome-prd.md)
- [Integration and QA plan](phases/phase-2-integration-and-qa-plan.md)
- [Security boundary and abuse-case plan](phases/phase-3-security-boundary-plan.md)
- [Behavioral effectiveness evaluation design](phases/phase-4-effectiveness-evaluation-design.md)
- [Validated parallel stream plan](phases/stream-plan.json)
- [Current progress and acceptance-evidence review](retrospectives/2026-08-12-progress-evidence-review.md)
- [Readable standalone HTML progress report](retrospectives/2026-08-12-progress-evidence-review.html)
- [Initiative 05 post-handoff audit](../05-ecosystem-conformance-audit/retrospectives/2026-08-12-work-audit.md)
- [Readable Initiative 05 HTML audit](../05-ecosystem-conformance-audit/retrospectives/2026-08-12-work-audit.html)

Live assignments, dependencies, QA state, and work products are maintained in Task Copilot rather than duplicated here.

Task Copilot entry point: `tc task get 278 --json`. The first parallel wave is TASK-279 (canonical transaction), TASK-280 (conformance truth), and TASK-282 (organization content).

TASK-294 records the trust work revealed during implementation: Codex organization and department plugins must be selected from signed immutable tier sources, materialized as verified atomic plugins, and represented in the canonical project lock with layer/ref/tree/signer provenance before parity or effectiveness can pass.

TASK-295 through TASK-300 close the independent program-review gaps: entitlement lifecycle, the real protocol/capabilities/Task Copilot journey, owner-approved signed content releases, security-before-publication ordering, post-fan-out security, and an explicit approved fleet census.

## Validation contract

- `cc conformance check --full --json`
- the complete `claude-copilot/tools/cc` test suite
- canonical-install round-trip and degraded-install recovery fixtures
- controlled behavioral evaluation fixtures with and without nearer-tier content
- leak, entitlement, signature, lock-integrity, and symlink-escape tests
- native Swift build and invariant checks against packaged source
- clean-user-home installation proof
- signed, notarized, stapled Control Tower release verification for any application change
- observed non-technical user acceptance against the journey rubric

## Current summary

The program has nine completed foundational tasks. The canonical transaction, conformance/full-mode truth, regression baseline, organization and accounting inputs, signed Codex source handling, native Control Tower rendering boundary, and entitlement lifecycle have accepted bounded evidence.

Owner decisions are complete. Accounting now has a signed sanitized root and `v1.0.0`; branch/tag protections are active, but GitHub Support must still purge the unreachable legacy object and runtime security remains open. Organization content is a signed exact-tree candidate behind required review.

Control Tower now has a clean Apache-2.0 public repository with one new history root, while the former repository is retained as a private archive. An independently signed, notarized, and stapled publisher anchor was installed and passed QA, but security rejected its `/Applications` location. Architecture WP-808 replaces later circular privileged helpers with a script-free, Developer ID Installer-signed payload package. WP-812 implements that local package boundary and source QA WP-813 approves it, but security WP-814 rejects the remaining first-trust handoff: the mutable checkout still retains signing authority, and the verified package path is not durably bound to the exact package and intended source that Installer consumes. Architecture WP-815 concludes that a fully automated first install is impossible under the required hostile-same-user model without a previously trusted component. The secure route is an owner-attended, independently signed exact-package approval and root-staged install with a monotonic anti-downgrade ledger. No Developer ID Installer identity, approved exact-package tuple, security-approved anchor, app candidate, or publication exists.

GitHub Actions are temporarily disabled on all 55 organization repositories under WP-785, with zero queued or running jobs and an exact restore ledger. Signed `claude-copilot` PR #63 is locally green, and signed Knowledge runtime PR #65 has QA and security approval through WP-782. Complete Action-SHA pinning corrections remain local and unpushed during the owner-directed GitHub pause. Actions, full-SHA pinning, required-check bindings, and clean hosted verification must be restored before merge or release. Behavioral evaluation, propagation, integrated security, publication, clean-machine proof, and observed nontechnical-person validation remain downstream. Read the designed [HTML progress report](retrospectives/2026-08-12-progress-evidence-review.html) or its paired [Markdown source](retrospectives/2026-08-12-progress-evidence-review.md) for exact gates and the criterion-by-criterion matrix.
