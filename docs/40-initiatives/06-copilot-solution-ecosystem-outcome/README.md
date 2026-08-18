---
initiative: 06-copilot-solution-ecosystem-outcome
title: Copilot Solution Ecosystem — Technical Readiness for Owner Dogfooding
status: active
status_note: The active delivery graph proves the technical ecosystem through Claude Code and Codex. Control Tower, non-technical participant validation, and long-term dogfooding are future work and do not block Initiative 06.
owner: Pablo Alejo
created: 2026-08-12
execution_context:
  prd: PRD-23
  tasks: TASK-278 technical-ecosystem parent; TASK-279 through TASK-300 plus TASK-303, TASK-306, and TASK-307; app tasks remain under PRD-24/TASK-301
superseded_by: null
---

# Copilot Solution Ecosystem — Technical Readiness for Owner Dogfooding

> Mode: Initiative Status: Active Source evidence: Initiative 05 audit and live `cc conformance`

## Goal

Give every person access to a trustworthy, company-aware, multidisciplinary solution team—one that helps them turn real problems into working solutions without requiring technical expertise, while safely carrying the organization's accumulated knowledge and capabilities to them.

That remains the long-term product goal. The active Initiative 06 objective is narrower and earlier in the sequence: make the underlying technical ecosystem released, complete, safe, scenario-proven, and ready for Pablo to use directly through Claude Code and Codex. Dogfooding will inform the later app and product experience.

## Scope

This initiative closes the distance between a mechanically installed candidate and one dependable technical ecosystem. It covers:

- one canonical, complete Claude + Codex project-install transaction;
- truthful, complete conformance and regression evidence;
- real organization and accounting-department contributions;
- Claude/Codex parity and specialist-extension coverage;
- controlled behavioral evaluation of company- and department-specific outcomes;
- personal-layer isolation and inherited-content security;
- realistic problem-to-solution scenario tests across Claude Code and Codex;
- framework fleet remediation and clean-environment technical proof;
- CLI Copilot capability boundaries and Task Copilot continuity;
- solo-owner repository governance with repository-level exceptions;
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
- declaring general availability or the full democratization goal achieved from technical readiness alone;
- long-term dogfooding conclusions or non-technical participant validation;
- Control Tower product design, source changes, packaging, publisher first trust, publication, installation, supervision, rollback, and app-specific cold-Mac proof; prior app work remains preserved in [PRD-24's deferred app track](tracks/control-tower-app-release-prd.md).

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
9. The complete technical journey succeeds in an isolated clean environment without Control Tower, publisher-machine caches, copied state, or manual repository wiring.
10. The task, test, security, release, and provenance record is recoverable from the initiative and `tc`.
11. Entitled, unentitled, offline, stale, and revoked access states fail safely and explain who can recover them.
12. Representative problems flow through intake, routing, entitled assembly, application, artifact creation, preservation, fresh-session continuation, approved update, and recovery in Claude Code and Codex wherever supported.
13. GitHub governance permits Pablo to authorize and merge non-Hermes work without an independent-review deadlock while preserving configured technical checks.

## Execution documents

- [Current technical completion plan](phases/phase-5-technical-ecosystem-completion-plan.md)
- [Readable standalone HTML technical plan](phases/phase-5-technical-ecosystem-completion-plan.html)
- [Current Claude/Codex effectiveness and release continuation handoff](handoff/2026-08-15-effectiveness-release-continuation.md)
- [Superseded 2026-08-14 technical ecosystem handoff](handoff/2026-08-14-technical-ecosystem-continuation.md)
- [Technical-first scope decision](decisions/adr-010-technical-ecosystem-first.md)
- [Solo-owner repository-governance decision](decisions/adr-011-solo-owner-repository-governance.md)
- [GitHub governance audit](validation/github-governance-audit-2026-08-14.md)
- [Superseded point-in-time ecosystem goal audit — 2026-08-14](2026-08-14-ecosystem-goal-audit.md)
- [Superseded standalone HTML goal audit](2026-08-14-ecosystem-goal-audit.html)
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
- Initiative 05 post-handoff audit (removed — see Initiative 05 note)
- Readable Initiative 05 HTML audit (removed — see Initiative 05 note)

Live assignments, dependencies, QA state, and work products are maintained in Task Copilot rather than duplicated here.

Task Copilot entry point: `tc task get 278 --json`. The first parallel wave is TASK-279 (canonical transaction), TASK-280 (conformance truth), and TASK-282 (organization content).

TASK-294 records the trust work revealed during implementation: Codex organization and department plugins must be selected from signed immutable tier sources, materialized as verified atomic plugins, and represented in the canonical project lock with layer/ref/tree/signer provenance before parity or effectiveness can pass.

TASK-295 through TASK-300 plus TASK-303 close entitlement lifecycle, the real protocol/capabilities/Task Copilot journey, signed content releases, framework security before fan-out, post-fan-out security, an explicit approved fleet census, and clean-environment proof. TASK-306 records the applied solo-owner governance change. TASK-307 owns the technical-first rebaseline. TASK-290 is future product validation and is not a TASK-292 dependency. TASK-286/287/289/298 and their work products remain under PRD-24; TASK-302 is the future app-release security gate.

## Validation contract

- `cc conformance check --full --json`
- the complete `claude-copilot/tools/cc` test suite
- canonical-install round-trip and degraded-install recovery fixtures
- controlled behavioral evaluation fixtures with and without nearer-tier content
- realistic problem-to-solution, create, preserve, resume, update, and recovery scenarios in Claude Code and Codex
- leak, entitlement, signature, lock-integrity, and symlink-escape tests
- clean-home framework setup, materialization, routing, update, and continuity proof

App build, signing, notarization, installation, supervision, rollback, non-technical participant, and long-term dogfooding gates are future work. They are neither waived nor counted toward this initiative's technical-readiness verdict.

## Current summary

The [2026-08-15 effectiveness and release handoff](handoff/2026-08-15-effectiveness-release-continuation.md) is the current operational record. Its verdict is **active and incomplete**.

Claude Copilot and Codex Copilot are usable for ordinary ecosystem development. The release branch is three signed commits ahead of `origin/main` and prepares framework `5.14.11` / `cc 2.12.11`, an exact 28-cell evaluator, protected Knowledge publication, durable assessment/finalization evidence, and fail-closed no-call readiness. Release-input preflight passes, but six broker/prepared files remain uncommitted, the fake/process broker has four unresolved QA defects, the production Codex credential/TLS boundary is absent, and installed signed source still disagrees with physical lock/materialization for routed foundation content.

No live effectiveness call has started. The exact 28-cell run, final signed assessment, integrated security approval, immutable release/install, and any later fleet fan-out remain separate gated work.
