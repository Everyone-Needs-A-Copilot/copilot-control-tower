---
initiative: 06-copilot-solution-ecosystem-outcome
title: Copilot Solution Ecosystem — From Conformance to Proven Solution Creation
status: active
status_note: The active delivery graph is framework-only. App release and installation work moved intact to owner-deferred PRD-24, so Apple packaging no longer blocks framework content, routing, evaluation, security, fleet, or human-outcome proof.
owner: Pablo Alejo
created: 2026-08-12
execution_context:
  prd: PRD-23
  tasks: TASK-278 framework parent; TASK-279 through TASK-300 plus TASK-303 framework graph; app tasks are tracked under PRD-24/TASK-301
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
- framework fleet remediation, clean-environment proof, and non-technical outcome validation;
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
- Control Tower packaging, publisher first trust, app publication, app installation,
  app rollback, and app-specific cold-Mac proof; those requirements and all prior
  evidence are preserved in [PRD-24's deferred app track](tracks/control-tower-app-release-prd.md).

## Outcome contract

The initiative is complete only when all of the following are true:

1. A sanctioned setup path produces the complete Claude + Codex reference install and every other setup surface delegates to that transaction.
2. Ordinary `cc conformance check --full` includes round-trip verification, reports zero S0 failures, and has no unexplained could-not-run results.
3. All remaining failures are either fixed or represented once as reviewed, evidence-backed exceptions with an owner and reason.
4. Real organization and department contributions win resolution, materialize into a project, and are recorded in its lock.
5. The `uids` and `cco` specialists receive substantive tier-appropriate direction where their work requires it.
6. Controlled evaluations show attributable company-context, department-method, decision, and artifact differences in the intended direction without reducing foundation quality; they do not claim generalized solution quality.
7. Personal content and credentials cannot move into shared layers; the proof includes negative leak fixtures.
8. An approved framework/content change reaches the exact eligible fleet through the canonical `cc` path without touching dirty, unentitled, excluded, or ambiguous repositories.
9. The framework journey succeeds in an isolated clean environment, and a real non-technical participant can use the already-provisioned workflow without Pablo acting as the synchronization layer.
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
- [Deferred Control Tower app release PRD](tracks/control-tower-app-release-prd.md)
- [Clean framework environment protocol](validation/clean-framework-environment-validation-protocol.md)
- [Current progress and acceptance-evidence review](retrospectives/2026-08-12-progress-evidence-review.md)
- [Readable standalone HTML progress report](retrospectives/2026-08-12-progress-evidence-review.html)
- [Initiative 05 post-handoff audit](../05-ecosystem-conformance-audit/retrospectives/2026-08-12-work-audit.md)
- [Readable Initiative 05 HTML audit](../05-ecosystem-conformance-audit/retrospectives/2026-08-12-work-audit.html)

Live assignments, dependencies, QA state, and work products are maintained in Task Copilot rather than duplicated here.

Task Copilot entry point: `tc task get 278 --json`. The first parallel wave is TASK-279 (canonical transaction), TASK-280 (conformance truth), and TASK-282 (organization content).

TASK-294 records the trust work revealed during implementation: Codex organization and department plugins must be selected from signed immutable tier sources, materialized as verified atomic plugins, and represented in the canonical project lock with layer/ref/tree/signer provenance before parity or effectiveness can pass.

TASK-295 through TASK-300 plus TASK-303 close the independent framework-review gaps: entitlement lifecycle, the real protocol/capabilities/Task Copilot journey, owner-approved signed content releases, framework security before fan-out, post-fan-out security, an explicit approved fleet census, and clean-environment proof. TASK-286/287/289/298 and their work products moved intact to PRD-24; TASK-302 is the future independent app-release security gate.

## Validation contract

- `cc conformance check --full --json`
- the complete `claude-copilot/tools/cc` test suite
- canonical-install round-trip and degraded-install recovery fixtures
- controlled behavioral evaluation fixtures with and without nearer-tier content
- leak, entitlement, signature, lock-integrity, and symlink-escape tests
- clean-home framework setup, materialization, routing, update, and continuity proof
- observed non-technical framework-outcome acceptance against the journey rubric

App build, signing, notarization, installation, rollback, and native-app gates are
validated only when PRD-24 resumes; they are not waived or counted toward this
initiative's framework verdict.

## Current summary

The framework program has eight completed foundational tasks. The canonical transaction, conformance/full-mode truth, regression baseline, organization and accounting inputs, signed Codex source handling, and entitlement lifecycle have accepted bounded evidence. TASK-286 remains completed with its original QA/security evidence, but now belongs to PRD-24 and does not count as a framework completion gate.

Owner decisions are complete. Accounting now has a signed sanitized root and `v1.0.0`; branch/tag protections are active, but GitHub Support must still purge the unreachable legacy object and runtime security remains open. Organization content is a signed exact-tree candidate behind required review.

Control Tower work is intentionally not on the framework critical path. PRD-24 preserves the public-source transition, native enforcement, publisher-first-trust design, signing forensics, candidate work, QA/security verdicts, and remaining installation/release gates without claiming that the app is complete. The existing Developer ID Application identity is sufficient for app/DMG signing but not the selected Installer-package first-trust mechanism; that distinction has no bearing on whether the framework works.

GitHub Actions remain temporarily disabled under WP-785. Framework PR review, CodeQL, provider purge, least-privilege confirmation, immutable content release, behavioral evaluation, approved fleet propagation, framework security, clean-environment proof, and observed nontechnical-person validation remain real gates. None was weakened by the app split. The [Markdown progress review](retrospectives/2026-08-12-progress-evidence-review.md) contains the current scope-reset addendum; the paired HTML remains a historical 2026-08-12 rendering.
