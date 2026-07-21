---
initiative: 02-enac-self-onboarding
title: ENAC Self-Onboarding — Dogfood the Ecosystem on Everyone Needs A Copilot
status: active
status_note: Live on ENAC's Mac — cli-copilot (and knowledge-copilot) split into public foundation + private -internal and pushed; the CLI tier-inheritance runtime (manifest + overlay loader + layered settings) and the fail-closed credential ladder shipped; all org secrets migrated to Infisical, only the Infisical bootstrap creds + Discord bridge token in keychain (owner-ratified "everything in Infisical, only the necessary in keychain"). Verified (887+15+92+33 tests, 0 fail-closed). Tier fully locked in + cut over (Phase 4+5, 2026-07-21): config inheritance, `copilot update` mirror-sync, and the full org-`.env` migration all shipped; the org mirror is now a clean git clone with no `.env` (foundation pinned `^0.3.0`→`v0.3.0`). Next: prove install + two-machine onboarding — phases/phase-6-ecosystem-install-and-onboarding-proof.md. Public flip still gated.
owner: Pablo Alejo
created: 2026-07-16
execution_context:
  prd: "This initiative's phase docs are the plan; no tc PRD yet."
  tasks: "Hand-off checklist in phases/phase-2-standup-and-rollout.md §9."
superseded_by: null
---

# ENAC Self-Onboarding — Dogfood the Ecosystem on Everyone Needs A Copilot

> Mode: Initiative
> Status: **Tier runtime + credential ladder LIVE on ENAC's Mac**; foundations
> split and pushed. Remaining to fully lock in: config inheritance,
> `copilot update` mirror-sync, fan-out validation, then the gated public flip.
> **Taking this over? Read this README, then
> [`phases/phase-3-tier-inheritance-and-secrets.md`](phases/phase-3-tier-inheritance-and-secrets.md)
> (what's live) and
> [`phases/phase-4-tier-completion-handoff.md`](phases/phase-4-tier-completion-handoff.md)
> (what's left). The Phase 1/2 runbooks remain the reference for the GitHub
> standup + fan-out mechanics.**

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

**Shipped — naming engine:** `scripts/admin_bootstrap.sh` and its test suite
implement `-internal` for the org triplet; the foundation read stays bare;
`internal` is refused as a department; the undeclared-department scanner skips
it. `scripts/tests/test_admin_bootstrap.sh` → **142 passed, 0 failed**. The
contract (`docs/01-architecture/admin-standup-contract.md`) carries the normative
naming table.

**Shipped — tier runtime + secrets (Phase 3, live on ENAC's Mac):**
`cli-copilot` split into public foundation + private `-internal` and pushed; the
CLI now runs **base + org overlay** composed by `copilot.layers.yml`; the
fail-closed **credential ladder** (Infisical managed store → OS keychain) is
wired into both base and overlay settings; **all org secrets migrated to
Infisical**, with only the Infisical bootstrap creds + the Discord bridge token
in the keychain (owner-ratified). Verified (887 foundation + 15 overlay + 92
service + 33 ladder tests; 0 fail-closed). Full record:
[`phases/phase-3-tier-inheritance-and-secrets.md`](phases/phase-3-tier-inheritance-and-secrets.md).

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
| Phase 1 | **Public-base extraction** — split `knowledge-copilot` & `cli-copilot` into public base + private `-internal` | naming shipped ✓ | **Done** — both split and pushed. [`phases/phase-1-public-base-extraction.md`](phases/phase-1-public-base-extraction.md) |
| Phase 2 | **Stand up, wire, validate, roll out** — org standup, manifest, scratch validation, fan-out, gated publicize | Phase 1 | Runbook; the GitHub-standup + fan-out mechanics remain the reference. [`phases/phase-2-standup-and-rollout.md`](phases/phase-2-standup-and-rollout.md) |
| Phase 3 | **Tier runtime + credential ladder** — layered settings, overlay loader, fail-closed secret ladder, full secret migration to Infisical | Phase 1 | **Shipped + live on ENAC's Mac.** [`phases/phase-3-tier-inheritance-and-secrets.md`](phases/phase-3-tier-inheritance-and-secrets.md) |
| Phase 4 | **Lock the tier in fully** — config inheritance, `copilot update` mirror-sync, fan-out validation, cleanup | Phase 3 | **Done + live.** [`phases/phase-4-tier-completion-handoff.md`](phases/phase-4-tier-completion-handoff.md) |
| Phase 5 | **Org-config migration + cutover** — move all org config out of the gitignored `.env` (non-secret → committed overlay `config:`; secrets → Infisical/keychain); org mirror is now a clean git clone with no `.env` | Phase 4 | **Done + cut over live (2026-07-21).** Recorded in the `phase-5(…)` commits, WP-79, memory `phase-5-org-config-migration`. |
| Phase 6 | **Ecosystem install + two-machine onboarding proof** — Admin provisions shared Claude/Codex layers; User Setup provisions user-owned personal layers; prove `personal (10) -> organization (30) -> foundation (40)` from a cold machine | Phase 5 | **Entry-ready — implementation and proof are the next work.** [`phases/phase-6-ecosystem-install-and-onboarding-proof.md`](phases/phase-6-ecosystem-install-and-onboarding-proof.md) |

## Decisions

- [ADR-001 — One org, no second company](decisions/ADR-001-one-org-no-second-company.md)
- [ADR-002 — `-internal` naming convention (universal)](decisions/ADR-002-internal-naming-convention.md)
- [ADR-003 — Dogfood ENAC directly, no Acme throwaway](decisions/ADR-003-dogfood-enac-directly.md)
- [ADR-004 — Admin provisions shared layers; the user provisions the personal layer](decisions/ADR-004-admin-shared-user-personal-onboarding.md)

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
- **V-5 — a cold laptop inherits the tier.** Phase 6: a machine that starts with an
  empty keychain and no work SSH key onboards, `copilot update` clones both
  mirrors, and every service resolves from the inherited config + store — with no
  hand-copied secret, no copied SSH private key, and no `.env`.

## Current Summary

**Status: active — the tier is fully live and cut over; next is proving
install/onboarding.** `cli-copilot` (and `knowledge-copilot`) are split into a
public foundation and a private `-internal` org layer and pushed. The
tier-inheritance runtime, fail-closed credential ladder, config inheritance, and
the `copilot update` mirror-sync are all shipped and verified live on ENAC's Mac.
As of the 2026-07-21 cutover (Phase 5) the org `.env` is **empty** — non-secret
config lives in the committed overlay, secrets in Infisical + keychain, and
`copilot update` regenerates the org mirror from a clean git clone (foundation
pinned `^0.3.0` → `v0.3.0`).

**The next action** is Phase 6: implement and prove the ecosystem can be
*installed and onboarded* — Admin Setup on this machine, User Setup on this
machine, and a cold laptop that inherits the three-layer Claude and Codex stacks
(V-5). The real gaps are on the new-machine path (product-aware resolution and
materialization, personal provisioning, verified executable-content policy,
manifest delivery, packaged CLI installer, scoped machine-identity provisioning,
and on-device SSH-key generation), not the existing CLI tier runtime. The one-way **public flip**
of the base repos stays gated until that proof is green. Hand-off:
[`phases/phase-6-ecosystem-install-and-onboarding-proof.md`](phases/phase-6-ecosystem-install-and-onboarding-proof.md).

The original **rename-redirect hazard** (creating a new repo with the old name
silently re-points every consumer at the base skeleton) was navigated during the
split; Phase 2 remains the reference for the GitHub-standup + fan-out sequencing.
