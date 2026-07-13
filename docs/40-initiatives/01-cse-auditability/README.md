---
initiative: 01-cse-auditability
title: CSE Auditability — Make Every Claim Falsifiable
status: active
status_note: Phase 1 + adversarial re-audit done (13/18 upheld, F-12 overturned). Register live (claims.yaml, 38 claims, pre-commit enforced); retention live; cse-bench harness + benches + dashboard shipped; capabilities built (usage ledger, extension loader, deadlock-free enforcement, content parity, conformance suite). Outcome bars O-1..O-9 ratified 2026-07-13. Next: Outcome Program (phases/phase-4-handoff.md).
owner: Pablo Alejo
created: 2026-07-11
execution_context:
  prd: "tc PRD-9 (verification & benchmark program) + PRD-10 (outcome program)"
  tasks: "tc tasks under PRD-9/PRD-10; open work inventoried in phases/phase-4-handoff.md par.4"
superseded_by: null
---

# CSE Auditability — Make Every Claim Falsifiable

> Mode: Initiative
> Status: Execution — outcome program (Phase 4)
> Execution context: tc PRD-9 + PRD-10 in this repo.
> **Taking this over? Start at [`phases/phase-4-handoff.md`](phases/phase-4-handoff.md)** — the
> single entry point: setup, full work inventory, operating rules, decision queue.

## Goal

The Copilot Solutioning Ecosystem (CSE) makes roughly forty claims about itself
across four products. Almost none of them can currently be shown to be false.
That is the problem this initiative exists to fix.

Produce a **claims register** and an **audit harness** that assign every CSE
claim exactly one of four verdicts — `proven`, `falsified`,
`unmeasurable-as-stated`, `not-yet-measured` — and that can be re-run on demand.
A claim with no falsification condition is not a claim; it gets rewritten or
deleted.

The success condition is not a good scorecard. It is a **trustworthy** one. A
report that lands with rows in `falsified` and `not-yet-measured` has done its
job. A report with no such rows would be evidence the instrument is broken.

### Why now — what the claim-surface investigation found

The CSE's claim surface sorts into four tiers:

| Tier | Count | State |
| --- | --- | --- |
| **Conformance** — mechanical, verifiable by inspection | ~20 | Mostly true, cheaply provable, never actually proven |
| **Efficacy** — the actual product pitch | ~10 | **None of it is measured** |
| **Field / economic** | ~6 | Unmeasured |
| **Unfalsifiable as written** | ~6 | Cannot be measured without a rewrite |

The specifics, which this initiative is answerable to:

- `claude-copilot/README.md:45` already admits it: *"We measure process and
  context efficiency, not output quality; there is no defect/rework data yet."*
  The honest disclaimer is there. The instrument behind it is not.
- The **"~94% less context"** figure (`claude-copilot/README.md:114`) has **no
  provenance** anywhere in the codebase. No script, no dataset, no run.
- The CSE's central value statement
  (`copilot-solutioning-ecosystem.md:64-68`, the section literally titled *"The
  value"*) is **entirely unfalsifiable**: "amplifies them as an individual,"
  "effortless," "effectively." Zero operational definitions. This is the pitch,
  and none of it can be wrong.
- **CLI Copilot** asserts exactly one testable clause in total
  (`cli-copilot/docs/00-overview.md:11`).
- **Knowledge Copilot's** consumption contract contains **zero** benefit
  statements. Its implied "single source of truth" claim is never written down
  anywhere, so it can neither be tested nor retired.
- **Codex Copilot** claims *parity* — refreshingly testable, and
  `codex-copilot/parity/claude-baseline.json` is a real manifest. But
  `evals/specialist-chain/scorecard-template.json` is an **empty template**: all
  scores `0.0`, every evidence field reading "Replace with…". Nobody has run it.
- The April 2026 restructure
  (`claude-copilot/docs/10-architecture/04-framework-restructure-2026-04.md`)
  **measured the problem and never measured the fix.** Baseline delegation rate
  6%, protocol-declaration rate 3.5% across 15 sessions. Hooks shipped. The
  "After" column contains zero measurements. Line 334 asserts the hooks "close
  the gap." Nobody checked.

That last one is the shape of the whole problem: the ecosystem is good at
diagnosis and has never once run the follow-up.

### What already exists (extend it; do not rebuild it)

- **~766 session transcripts, 531 MB, 51 projects** in
  `~/.claude/projects/**/*.jsonl`. Every message carries `usage` and `model`.
  This is a large, real, already-collected corpus.
- **`~/.claude/stats-cache.json`** — daily counts back to January 2026.
- **`cc eval`** (`claude-copilot/tools/cc/src/cc/commands/eval.py`) — 10 YAML
  cases, pluggable `--runner`. A harness skeleton already ships.
- **`cc memory check`** — 0–100 drift score.
- **`copilot doctor --json`** — the authoritative ecosystem-state computation.
- **`codex-copilot/parity/claude-baseline.json`** — a real parity manifest.

**Missing, and the cheapest high-value instrumentation win available:** any
**append-only hook event log**. The hooks fire on every session and record
nothing durable.

## Scope

- All four CSE products: **Claude Copilot**, **Codex Copilot**, **CLI Copilot**,
  **Knowledge Copilot** — plus the CSE model document itself
  (`docs/reference/copilot-solutioning-ecosystem.md`), whose "The value" section
  is the single largest unfalsifiable surface in the ecosystem.
- All four inheritance layers — Foundation, Org, Dept, Personal — exercised via a
  **synthetic fixture** (see D-3), because Org and Dept do not exist as real
  repos today.
- The claims register (`claims.yaml`), the audit engine, the conformance suite,
  the efficacy harness, the field-telemetry collector, and the final report.
- **Rewriting or deleting CSE claims** that survive Phase 0 without a
  falsification condition. This initiative has standing to change the marketing
  copy of the products it audits. That is the point.

## Non-Goals

- **Not a general-purpose LLM eval framework.** If promptfoo or braintrust fit
  the Tier-B need, use them. Building a fifth eval framework to audit four
  copilots would be its own punchline.
- **Not a measurement of Claude's raw capability.** The subject is the CSE's
  **marginal contribution over baseline Claude**. "Claude did well" is not a
  finding. "Claude did better *with the framework than without it*" is.
- **Not a marketing asset — until the Phase-5 gate opens.** Per D-2, the report
  is an internal honesty instrument first. Any use of it as an external artifact
  before Phases 1–3 have run and their negative findings have been absorbed is a
  violation of this initiative, not an acceleration of it.
- **No new ecosystem-state computation.** Reuse `copilot doctor --json`,
  `cc eval`, `cc memory check`. If the harness starts re-deriving ecosystem
  state, it has become a second source of truth and must be stopped.
- **Not a live task tracker.** Live status, assignments, and blockers stay in the
  authoritative task system. This README is the durable spine, not the standup.
- **Not a per-session productivity surveillance tool.** Telemetry serves claim
  verification. It does not become a dashboard about the human.

## Target Outcomes

- **Every CSE claim is enumerated in one machine-readable table**, each with a
  source `file:line`. Nothing is claimed anywhere in the CSE that is not in
  `claims.yaml`. Observable: a grep-based sweep finds no benefit statement in
  product docs that lacks a register entry.
- **Every claim in the register has a falsification condition, or is deleted.**
  Observable: the register contains no row where `falsification_condition` is
  empty and `verdict` is not `deleted`.
- **The April hook claim has a verdict.** Observable: an interrupted-time-series
  result on the 766-transcript corpus, published whether it confirms or refutes
  `04-framework-restructure-2026-04.md:334`.
- **The conformance tier is fully resolved.** Observable: zero Tier-A claims sit
  in `not-yet-measured` after Phase 2.
- **The top efficacy claims have an experimental result with an effect size and
  an honest confidence statement** — including "underpowered, inconclusive" where
  that is the truth.
- **The report can fail its own subject.** Observable: a named, rerunnable check
  in which a deliberately false fixture claim is correctly marked `FALSIFIED`.
- **The "~94% less context" figure either gets provenance or gets deleted.** No
  third option.

## Phase Index

| Phase | Goal | Complexity | Depends on | Status |
| --- | --- | --- | --- | --- |
| Phase 1 | **The Falsification Probe** — did the April hooks actually work? | Medium | (ran early — see below) | **First pass complete** — [`phases/phase-1-findings.md`](phases/phase-1-findings.md) |
| Phase 0 | **The Claims Register** — one machine-readable table of every claim | Medium | — | Next |
| Phase 2 | **Conformance Suite (Tier A)** — deterministic fitness functions | Medium | Phase 0 | Proposed |
| Phase 3 | **Efficacy Harness (Tier B)** — framework-on vs framework-off | High | Phase 0, Phase 1 | Proposed |
| Phase 4 | **Field Telemetry (Tier C)** — longitudinal, observational | Low | Phase 0 | Proposed |
| Phase 5 | **The Designed Report** — **GATED** | Medium | Phases 1, 2, 3 absorbed | Blocked by gate |

Phases 2 and 4 are parallelizable once Phase 0 lands. Phase 3 is the long pole.
Phase 5 is deliberately not startable early.

**Phase 1 ran ahead of Phase 0, and this was a deviation.** It was run as an
opportunistic probe because the evidence it depends on was actively being
destroyed (see F-6). Its findings are therefore **not pre-registered** and
violate V-2 — they carry the weakest evidentiary status this initiative accepts,
and must be re-run against `claims.yaml` before being quoted anywhere. This is
recorded rather than tidied away: an audit that quietly exempts its own first run
from its own rules has already failed.

Its four falsified findings — the delegation hook was disabled the day it
shipped, enforcement exists in 1 of 27 repos, the model-tier claim is false under
every denominator, and the protocol rate never recovered — are what make Phase 0
urgent rather than academic.

### Phase 0 — The Claims Register

Extract every claim across all four products and the CSE model document into
**one** machine-readable table, `claims.yaml`:

```yaml
- id: cc-context-reduction
  claim: "~94% less context per specialist invocation"
  source: claude-copilot/README.md:114
  product: claude-copilot
  layers: [foundation]
  tier: efficacy
  operational_definition: null     # ← must be filled or the claim dies
  falsification_condition: null    # ← must be filled or the claim dies
  threshold: null
  verdict: not-yet-measured
```

**Exit criterion:** every claim either has a falsification condition, or is
marked for deletion.

This phase **is allowed and expected to delete claims.** That is its purpose, not
a side effect. The six unfalsifiable claims — "effortless," "amplifies them as
an individual," "effectively" — will not survive contact with a
`falsification_condition:` field. Either someone writes down what would make
them false, or they come out of the docs. Knowledge Copilot's unwritten "single
source of truth" claim gets the reverse treatment: it is written down so it can
be tested, or it is abandoned as a positioning line.

`claims.yaml` **is the spec the harness consumes.** Nothing downstream may
measure a claim that is not in it. This is what stops the audit from quietly
growing new, friendlier claims mid-flight.

### Phase 1 — The Falsification Probe

Re-run the April diagnostic against the current 766-transcript corpus as an
**interrupted time series** around the hook-ship date. Same two metrics —
delegation rate (baseline 6%) and protocol-declaration rate (baseline 3.5%) —
same extraction method, ten months more data.

Two secondary jobs:

1. Identify **framework-absent projects** in the 51-project corpus. These are a
   possible accidental control group and the only free path to Phase 3's hardest
   requirement.
2. Produce a **reusable transcript-mining library**. Phases 3 and 4 both depend
   on it; writing it once here is the whole reason this phase comes early.

**Exit criterion:** a published verdict on the flagship claim, **even if it is
bad news.** If the hooks did not close the gap, `04-framework-restructure-2026-04.md:334`
gets corrected, and the correction ships.

*(A probe against this corpus is already running as of 2026-07-11; its output
seeds this phase rather than replacing it.)*

### Phase 2 — Conformance Suite (Tier A)

A deterministic fitness function over the ~20 mechanical claims — propagation,
override precedence, one-way inheritance, no-secret-leakage, structure, wiring.
These are true-or-false by inspection, and they are the cheap tier. There is no
excuse for any of them sitting in `not-yet-measured`.

Includes the **synthetic 4-layer fixture** (D-3): throwaway
Foundation/Org/Dept/Personal repos used as a conformance target. Also revives
Codex Copilot's abandoned `evals/specialist-chain/scorecard-template.json` — a
real parity manifest exists; the scorecard has simply never been run.

**Extends `cc eval` and `copilot doctor --json`.** Does not rebuild them.

**Exit criterion:** no conformance-tier claim is left in `not-yet-measured`.

### Phase 3 — Efficacy Harness (Tier B)

The hard one, and the one the product actually rests on.

A task suite run under two arms — **framework-on** and **framework-off** — with
judged output. Effect size on the claims that matter: context efficiency, output
quality, rework rate.

The hard problem is stated plainly: **the control arm does not exist and cannot
be found.** Every transcript on this machine is framework-on. The hooks exist
*specifically to prevent framework-off behavior*. The control arm therefore has
to be **deliberately constructed** — a clean environment with the framework
uninstalled, running the same task suite. There is no shortcut, and Phase 1's
framework-absent-project scan is the only chance of a cheaper one.

**Exit criterion:** the top efficacy claims have an experimental result with an
effect size and an honest confidence statement. "Underpowered" is an acceptable
result. "We didn't run it" is not.

### Phase 4 — Field Telemetry (Tier C)

Longitudinal and observational: transcripts plus `stats-cache.json`. Cheap,
because the data has been accumulating for months already.

Adds the **missing append-only hook event log** — the single highest
value-per-unit-of-effort instrumentation available. Every future phase gets
better data for free once it exists, which is an argument for building it early
even though the phase that consumes it is late.

### Phase 5 — The Designed Report (GATED)

The scorecard. Four verdicts, no fifth:

| Verdict | Meaning |
| --- | --- |
| `proven` | Falsification condition tested; claim survived |
| `falsified` | Falsification condition tested; claim did not survive |
| `unmeasurable-as-stated` | No falsification condition can be written; claim needs rewriting or deletion |
| `not-yet-measured` | In the register, not yet run |

**Rendered by Control Tower — parse-only.** The app reads the engine's `--json`
and displays it. It computes nothing. (Invariant #1; see D-1.)

**The gate:** this phase does not begin until Phases 1–3 have run **and their
negative findings have been absorbed** — meaning the failing claims have actually
been fixed or deleted in the products' docs, not merely noted. Per D-2.

Shipping the report with rows in `falsified` or `not-yet-measured` is a
**success condition, not a failure.** A scorecard with no bad rows, produced by
the person whose system is being scored, is not evidence of a good system. It is
evidence of a bad auditor.

## Decisions

`decisions/` does not exist yet — the three decisions below were ratified by the
owner on 2026-07-11 and are recorded here. They get promoted to ADRs under
`decisions/` when the first phase document needs to cite one formally.

### D-1 — Harness home: Control Tower repo, outside the signed app binary

**Decision.** The audit engine lives in the Copilot Control Tower repo as a
**standalone executable** (e.g. under `tools/`). The SwiftUI app may only ever
**render its `--json`**.

**Why.** Control Tower's invariant #1 is *parse, never compute*. An audit engine
is a computation engine. Embedding it in the app would put ecosystem-state
reasoning inside the signed binary — exactly the thing the invariant exists to
prevent — and would make the harness un-runnable from CI, which defeats
rerunnability.

**Consequence.** The app gains a report view and nothing else. The engine is
independently runnable, independently testable, and independently versioned.

**Bound.** Compiling the engine into the app is **explicitly out of bounds
without a further owner decision.**

### D-2 — Report purpose: both, honesty first, externalization gated

**Decision.** Build the internal honesty instrument. Run it. Absorb the bad news.
Fix or delete the claims that fail. **Only then** harden it into an externally
publishable artifact.

**Why.** A measurement instrument built with an audience in mind measures the
audience. The order is the guarantee.

**Consequence.** Phase 5 is gated on Phases 1–3 having actually run and their
results having been acted on. The gate is not advisory.

**Alternative rejected.** Building the external report first and back-filling the
measurements. This is how the "~94% less context" figure came to exist without
provenance, and it is not being repeated.

### D-3 — Layer dimension: synthetic 4-layer fixture as a conformance target

**Decision.** Build a **synthetic 4-layer fixture** — throwaway
Foundation/Org/Dept/Personal repos — and use it as the conformance target for all
layer-related claims.

**Why.** Org and Dept **do not exist today.** Org has no overlay repo (it is
fused into knowledge-copilot), and `cse-alignment-decisions.md:78` states plainly
that Dept "none exists today." Waiting for real Org and Dept repos would block
Tier A indefinitely.

Propagation, override precedence, one-way inheritance, and no-secret-leakage are
**mechanical properties**. They are testable on a fixture. No efficacy work is
required to prove them, and no real org is required either.

**Consequence.** Tier A can complete without waiting on the ecosystem's own
adoption curve. The fixture's realism is a known limitation and is stated in the
report rather than papered over.

**Alternative rejected.** Auditing only the layers that exist (Foundation,
Personal) and marking the rest `not-yet-measured` indefinitely — which would
leave the inheritance model, one of the CSE's strongest and most checkable
claims, permanently unverified.

## Validation Contract

The audit's own auditability. Every item is a rerunnable check, not a review
step.

### V-1 — The standard's own gate passes

```bash
scripts/initiatives/check-initiatives.sh
```

Installed in this repo as part of this initiative, wired to the pre-commit hook.
This document is subject to the same mechanical enforcement it demands of
everything else. R1–R12 pass, including the generated index (R7).

### V-2 — Pre-registration: the benchmark cannot be retrofitted

`claims.yaml` is **committed and git-tagged before any efficacy run.**

The report tool **must refuse to score** a claim whose `falsification_condition`
or `threshold` was introduced *after* the run it is scoring. The tool compares
the register's tagged commit against the run's recorded register hash and hard-
fails on a mismatch.

This is the structural guarantee that the benchmark cannot be quietly turned into
marketing. A threshold moved after seeing the result is not a threshold. Without
this check, every other item in this contract is a promise rather than a
property.

### V-3 — The auditor must be able to fail its own subject

A named, rerunnable check — `test_auditor_reports_falsified` — in which a
**fixture containing a deliberately false claim** is run through the full report
pipeline, and the report is **required** to mark it `FALSIFIED`. If the report
marks it anything else, the check fails and the report does not build.

Without this test, "the report is capable of printing FALSIFIED" is itself just
another unfalsifiable claim — and this entire initiative would have reproduced
the defect it was created to eliminate.

### V-4 — Total accounting: no claim goes missing

Every claim in `claims.yaml` resolves to **exactly one** of the four verdicts.
The report **fails to build** if any claim is unaccounted for, if any claim
carries two verdicts, or if any claim in a product's docs is absent from the
register.

There is no "other" bucket. There is no silent drop.

### V-5 — Provenance is machine-checkable

Every `proven` verdict links to the run that produced it: the commit of the
register, the commit of the harness, the input corpus, and the raw output. A
`proven` row with no reachable provenance fails the build — which is precisely
the condition the "~94% less context" figure is in today.

## Current Summary

**Status: active.** The claim-surface investigation is done, owner decisions D-1,
D-2 and D-3 are ratified, and the Phase 1 falsification probe has run — producing
four `FALSIFIED` verdicts against this ecosystem's own claims on its first
execution, before any tool was built. See [`phases/phase-1-findings.md`](phases/phase-1-findings.md).

`claims.yaml` still does not exist, so no claim can yet be *scored* — only
probed.

**The next actions, in causal order:**

1. **Transcript retention.** The only item where delay is irreversible. F-6
   established that the hooks' before/after comparison is permanently closed
   because the evidence was pruned. Every day without retention forecloses
   another question.
2. **`test_pretool_hook_fires_on_read`.** One check. It would have caught F-1 on
   2026-04-22 and every day since. The matcher rotted for exactly one reason:
   nothing tested that it fired.
3. **Phase 0 — the register.** F-5 (delegation rate is 3.1% or 40.5% depending
   on which defensible definition you pick) and F-8 (the "~94%" figure may be a
   misattributed cache-read statistic) are both unanswerable without it.

The single thing most likely to go wrong remains: **Phase 0 gets written as an
inventory instead of a cull.** If it produces forty rows and deletes none of
them, it has failed, and every later phase will be measuring claims that should
never have survived.

Live task state — assignments, in-flight status, blockers — belongs in the
authoritative task system, not here.
