# Copilot Control Tower — Design Package Status

> **Purpose:** Pick this up in a new conversation to finish the design package.
> **How to use:** Tell Claude "Check TODO-DESIGN-PACKAGE.md for where I left off"
> **Note:** Phases 1–5 are complete. Phase 6 (Prototype) is the next open item — that's where you pick up.

---

## Foundational decisions

### ✅ RESOLVED & RATIFIED (owner, 2026-07-07)

1. **Writable org/dept tiers vs. never-destroy** → RESOLVED. Consumer-read-only / author-writable split preserves invariant #3 intact. See [`../01-architecture/inheritance-and-publish.md`](../01-architecture/inheritance-and-publish.md).
2. **Non-technical merge-conflict resolution** → RESOLVED. Layered `copilot publish` (auto-merge → keep-yours/theirs/**both** chooser → park-and-escalate); "keep both" is the no-data-loss floor. Same doc; new `copilot publish --json` verb added to WS-A.
3. **Credentials-carrier for pull-based inheritance** → RESOLVED. OS keychain + per-integration OAuth; `requires_secret:` references-not-secrets; never git. See [`../05-security/credentials-and-boundary.md`](../05-security/credentials-and-boundary.md).

These four safety rules were **elevated to CLAUDE.md invariants** (new invariant #6): secrets-never-in-git · no cross-tier write · sync pull-only/downward · fail-closed leak-scan.

### ⏳ STILL OPEN

1. **Author git-push-credential provisioning** — the SSH-alias *model* is settled; the *provisioning mechanism* (key generation/distribution/rotation to a trained author's machine) is not. The one remaining foundational seam. See credentials doc §6.
2. **Personal-layer content scope** — what belongs in the personal layer (writing styles, etc.) is unsettled.
3. **Admin/IT operator experience** — unvalidated hypothesis; needs real IT operators to confirm.
4. **Multi-writer authoring flow** — unvalidated hypothesis; needs real writers to confirm.
5. **Pre-existing engineering TODOs** — cadence values, urgent-revocation propagation, signing custody, kiosk depth, Codex parity.

---

## Status Summary

| Status | Count |
|--------|-------|
| NOT STARTED | 1 |
| IN PROGRESS | 0 |
| DONE | 15 |

Both checkpoints have **PASSED**: Design Foundation and Design Complete. Phases 1–2 were revised from a live owner interview conducted 2026-07-06.

---

## Phase 1: Discovery

### Design Foundation Checkpoint requirement: Vision + scope + success metrics exist — MET

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 1 | `00-overview/00-vision.md` | DONE | Problem, users, vision, forces, JTBD, AI philosophy, capabilities, ecosystem context, warning signs |
| 2 | `00-overview/10-scope-and-non-goals.md` | DONE | Scope, non-goals, anti-features, constraints, integration boundaries |
| 3 | `00-overview/20-success-metrics.md` | DONE | User outcomes, business outcomes, leading/failure indicators, ecosystem health |

---

## Phase 2: Research & Service Design

### Design Foundation Checkpoint requirement: At least 1 completed interview + journeys/JTBD/moments exist — MET

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 4 | `01-research/10-interviews/01-interview-self.md` | DONE | Self-interview (product owner interviews themselves as primary user) |
| 5 | `02-service-design/30-jtbd.md` | DONE | Jobs to be done across all personas |
| 6 | `02-service-design/20-journey-maps.md` | DONE | Personas, journey narrative, struggling moments, emotional arc |
| 7 | `02-service-design/40-moments-that-matter.md` | DONE | Critical moments with success/failure criteria |
| 8 | `02-service-design/10-service-blueprint.md` | DONE | Frontstage, backstage, support processes |

---

--- CHECKPOINT: Design Foundation — PASSED ---

- [x] Vision + scope + success metrics complete (#1-3)
- [x] At least 1 completed interview (#4)
- [x] Journeys, JTBD, and Moments That Matter complete (#5-7)

---

## SOUL.md — RATIFIED v1.1

| # | Document | Status | Notes |
|---|----------|--------|-------|
| — | `../../SOUL.md` (project root — not in docs/) | DONE | RATIFIED v1.1: soul statement, IS/IS-NOT table, design principles with rejection tests, named anti-patterns, Feature Filter gates. See `skills/REF-soul-file.md` |

---

## Phase 3: Requirements

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 9 | `03-requirements/10-user-stories.md` | DONE | User stories grouped by persona, prioritized |
| 10 | `03-requirements/20-use-cases-and-scenarios.md` | DONE | E2E scenarios, edge cases, critical view scenarios |
| 11 | `03-requirements/30-acceptance-criteria.md` | DONE | Given/When/Then, performance, quality criteria |

---

## Phase 4: Experience Design

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 12 | `04-experience-design/50-ux-design.md` | DONE | IA, task flows, interaction patterns, responsive, accessibility |
| 13 | `04-experience-design/60-ui-design.md` | DONE | Visual direction, design tokens, component patterns |
| 14 | `04-experience-design/70-copy-voice.md` | DONE | Voice character, speech patterns, key UI copy, banned language |

---

## Phase 5: Design Challenge

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 15 | `05-design-challenge/00-brief.md` | DONE | Critical views, creative direction, concepts per view, evaluation criteria |

---

--- CHECKPOINT: Design Complete — PASSED ---

- [x] All requirements documents complete (#9-11)
- [x] UX, UI, and copy documents complete (#12-14)
- [x] Design challenge brief written and approved (#15)
- [x] Critical views list confirmed

---

## Phase 6: Prototype — NOT STARTED (deferred — the build phase)

Choose ONE output format. See `06-prototype/README.md` for guidance.

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 16 | `06-prototype/[chosen-output].md` | NOT STARTED | User chooses format: Figma, Design Spec, Storybook, or Next.js |

**Chosen format:** _Not yet decided_

---

## Reference

| File | Purpose |
|------|---------|
| `01-research/10-interviews/00-interview-template.md` | Generic interview template — copy and rename for additional interviews |
| `06-prototype/README.md` | Guidance on choosing the right prototype format |
</content>
