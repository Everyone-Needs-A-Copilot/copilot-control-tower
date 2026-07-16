---
initiative: 02-enac-self-onboarding
title: ENAC Self-Onboarding — Dogfood the Ecosystem on Everyone Needs A Copilot
status: active
status_note: Naming convention ratified and shipped (org layer = <C>-copilot-internal, engine + tests green, 142/142). Docs written. Not yet executed against GitHub — owner runs it with a developer next. Phase 1 (public-base extraction) is the first real work.
owner: Pablo Alejo
created: 2026-07-16
execution_context:
  prd: "This initiative's phase docs are the plan; no tc PRD yet."
  tasks: "Hand-off checklist in phases/phase-2-standup-and-rollout.md §9."
superseded_by: null
---

# ENAC Self-Onboarding — Dogfood the Ecosystem on Everyone Needs A Copilot

> Mode: Initiative
> Status: Ratified + tooling-ready; not yet run against GitHub.
> **Taking this over? Read this README, then execute
> [`phases/phase-1-public-base-extraction.md`](phases/phase-1-public-base-extraction.md)
> first, then [`phases/phase-2-standup-and-rollout.md`](phases/phase-2-standup-and-rollout.md).**

## Goal

Make **Everyone Needs A Copilot (ENAC)** the first real consumer of its own
ecosystem, on ENAC's own GitHub org, without a throwaway test company and without
risking existing work. ENAC is the publisher *and* the first customer at once — the
hardest case — so if onboarding works here, it works for any company.

The end state:

- ENAC's Mac resolves the full ecosystem it has today via a **private org layer**
  stacked on the **public foundation**, in one GitHub org.
- A single `copilot update` propagates a component change to **every** ENAC
  project (the owner's #1 pain point: today every project is updated by hand).
- The public foundation (`knowledge-copilot`, `cli-copilot`) exists as a **generic
  base** any company can adopt and grow into their own mature version — the thing
  that makes the open-source product real.

## Why this shape (the two corrections that produced it)

Two owner decisions reversed earlier assumptions and define this initiative:

1. **Dogfood ENAC directly — no `Acme-Copilot` throwaway.**
   ([`decisions/ADR-003-dogfood-enac-directly.md`](decisions/ADR-003-dogfood-enac-directly.md))
2. **One GitHub org — no second company.** Foundation vs org layer is
   distinguished by **repo name + visibility**, not by a separate org. This is
   architecturally valid because GitHub's confidentiality boundary is the
   *repository*, not the *organization*.
   ([`decisions/ADR-001-one-org-no-second-company.md`](decisions/ADR-001-one-org-no-second-company.md))

## The naming model (ratified, universal)

For `<C>` ∈ {`knowledge`, `cli`, `claude`, `codex`}:

| Layer | Repo | Visibility | Where |
|---|---|---|---|
| **Foundation** | `<C>-copilot` | public | `Everyone-Needs-A-Copilot` (bare name, never suffixed) |
| **Org** | `<C>-copilot-internal` | private | `Everyone-Needs-A-Copilot` |
| **Department** | `<C>-copilot-<dept>` | private | `Everyone-Needs-A-Copilot` |
| **Personal** | `<C>-copilot-private` (or similar) | private | each person's own account |

`internal` is a **fixed literal**, not the org name — always distinct from the
bare foundation name, so foundation and org coexist in one org. It is a **reserved
department slug**. This is universal: every customer uses these names, so ENAC
dogfoods the exact shipped path.
([`decisions/ADR-002-internal-naming-convention.md`](decisions/ADR-002-internal-naming-convention.md))

**Shipped this session:** the engine (`scripts/admin_bootstrap.sh`) and its test
suite now implement `-internal` for the org triplet; the foundation read stays
bare; `internal` is refused as a department; the undeclared-department scanner
skips it. `scripts/tests/test_admin_bootstrap.sh` → **142 passed, 0 failed**. The
contract (`docs/01-architecture/admin-standup-contract.md`) carries the normative
naming table.

## Scope

- The four CSE **tooling** components (knowledge, cli, claude, codex) and their
  layer repos — **not** ENAC's ~20 downstream products (those are *consumers* of
  the tooling; they receive a materialized `.claude/`).
- Splitting `knowledge-copilot` and `cli-copilot` into a public generic **base**
  and a private ENAC **org layer** (Phase 1).
- Standing up the org layer, wiring the manifest, validating, and rolling the
  update fan-out across ENAC's real projects (Phase 2).
- The one-way, gated act of making the base repos public (Phase 2, last step).

## Non-Goals

- **Not a second GitHub org.** Explicitly rejected (ADR-001).
- **Not a throwaway `Acme-Copilot` run.** Explicitly rejected (ADR-003).
- **Not moving ENAC's products.** Only the tooling layer is reorganized.
- **Not building `copilot promote`.** The private→public curation valve is not
  built; the first base extraction is a **manual, one-time curation**. Whether to
  build `promote` for the ongoing loop is an open decision (Phase 1).
- **Not publicizing anything as part of the *test*.** Making the base repos public
  is decoupled and deferred to the very end; the whole loop validates privately.

## Target Outcomes

- **A clean machine cloning only the public base gets a coherent, generic
  ecosystem** — structure, method, tooling — with zero ENAC business content.
- **ENAC's own machine resolves the full mature content it has today**, via the
  `-internal` org layer stacked on the public foundation.
- **One `copilot update` propagates a component change to every ENAC project.**
- **No ENAC business data or secret ever reaches a public repo** — enforced by the
  Phase 1 leak-scan gate and the never-public default.

## Phase Index

| Phase | Goal | Depends on | Status |
|---|---|---|---|
| Phase 1 | **Public-base extraction** — split `knowledge-copilot` & `cli-copilot` into public base + private `-internal`, with a per-file base-vs-internal content map | naming shipped ✓ | **Next — the first real work.** [`phases/phase-1-public-base-extraction.md`](phases/phase-1-public-base-extraction.md) |
| Phase 2 | **Stand up, wire, validate, roll out** — org standup, manifest, scratch validation, fan-out to real projects, then the gated publicize | Phase 1 | Documented runbook. [`phases/phase-2-standup-and-rollout.md`](phases/phase-2-standup-and-rollout.md) |

## Decisions

- [ADR-001 — One org, no second company](decisions/ADR-001-one-org-no-second-company.md)
- [ADR-002 — `-internal` naming convention (universal)](decisions/ADR-002-internal-naming-convention.md)
- [ADR-003 — Dogfood ENAC directly, no Acme throwaway](decisions/ADR-003-dogfood-enac-directly.md)

## Validation Contract

- **V-1 — the naming change is test-backed.** `scripts/tests/test_admin_bootstrap.sh`
  asserts the org triplet is `-internal`, departments and foundation reads are
  unchanged, and a department named `internal` is refused. 142/142.
- **V-2 — the public base carries no ENAC content.** Phase 1's acceptance: a clean
  clone of a base repo passes the leak-scan deny-list and contains no customer
  name, deal, private endpoint, or secret.
- **V-3 — never-destroy holds on rollout.** Phase 2 scratch gate: dirty a
  materialized tree, re-run `copilot update`, confirm hold-on-dirty with zero
  writes before touching any real project.
- **V-4 — the fan-out actually propagates.** Phase 2: one `copilot update` after a
  component change updates every enrolled project's `.claude/`.

## Current Summary

**Status: active, not yet run.** The naming convention is ratified, implemented,
and green (142/142); the contract and this initiative are written. Nothing has
touched GitHub yet — that is the owner's next step, with a developer.

**The next action** is Phase 1: the per-repo base-vs-`-internal` content map and
the one-time manual curation. The single thing most likely to go wrong is the
**rename-redirect hazard** (creating a new repo with the old name silently
re-points every consumer at the base skeleton) — Phase 1 and Phase 2 sequence
around it deliberately: rename first, create-new second, re-point every consumer
via the manifest third.
