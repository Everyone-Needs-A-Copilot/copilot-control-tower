# Owner Decision Queue — Index

> Initiative: `01-cse-auditability` · Source: [`phases/phase-4-handoff.md`](../phases/phase-4-handoff.md) §6
> These memos are **prepared, not ruled**. Every memo in this directory ends
> in a recommendation, never a decision — the owner rules, this initiative
> never does. No deletion, config removal, or destructive action has been
> taken on the basis of any memo here.

## How to use these memos

Each memo is self-contained: one-sentence decision framing, plain-language
context, the real evidence (quoted from its source file and `generated_at`
timestamp), the options with their concrete consequences (including "do
nothing"), a labeled recommendation, and the exact one-line command to
execute each option. Pick an option, run its command yourself (or hand it to
the agent that owns the target repo) — nothing here executes automatically.

## The decisions

| # | Memo | tc task | One-line question |
|---|---|---|---|
| DEC-1 | [`DEC-1-agent-return-bar.md`](DEC-1-agent-return-bar.md) | TASK-112 (R-1) — **RULED 2026-07-14: amend, per-class ratchet — EXECUTED, `completed`** | Enforce the ~100-token agent-return bar, or amend the SOUL bar to match measured reality? |
| DEC-2 | [`DEC-2-protocol-adoption.md`](DEC-2-protocol-adoption.md) | TASK-113 (R-3) — **RULED 2026-07-14: retire — EXECUTED, `completed`** | Protocol-declaration adoption is ~0%: enforce it, simplify it, or retire the requirement? |
| DEC-3 | [`DEC-3-soul-94pct-correction.md`](DEC-3-soul-94pct-correction.md) | TASK-114 (R-5) — **RULED 2026-07-14: ratify, rewrite (Option B) — EXECUTED, `completed`** | Ratify the SOUL §3 correction replacing the falsified "~94% less context" figure? |
| DEC-4 | [`DEC-4-stale-clones.md`](DEC-4-stale-clones.md) | TASK-118 (R-9) | Delete or keep the stale `shared-docs`/`conversations-copilot` clone artifacts? |
| DEC-5 | [`DEC-5-configure-or-cut-services.md`](DEC-5-configure-or-cut-services.md) | TASK-122 (R-13) | Configure or cut: fireflies, reddit, metabase, method? |
| DEC-6 | [`DEC-6-mlp-rubric-signoff.md`](DEC-6-mlp-rubric-signoff.md) | TASK-125 (W-3) | Ratify the MLP expectation rubric (`tools/cse-bench/benches/ladder/rubric.md`) before the ladder bench's first scored run? |
| DEC-7 | [`DEC-7-c3-hook-rollout-gate.md`](DEC-7-c3-hook-rollout-gate.md) | TASK-103 (C-3) | The `claude-copilot` hook-path defect is fixed and scripted-reverified — does that satisfy Rollout Readiness condition 1, or does the owner still need to run one real session before C-3 widens to consumer repos? |
| DEC-8 | [`DEC-8-first-removal-review.md`](DEC-8-first-removal-review.md) | TASK-100 (B-17), fed by TASK-128 (W-6) | The first mechanical removal review nominates agents `cpa`/`cs`/`kc` and knowledge area `04-shared-systems` — keep, cut, or (for `kc`) investigate a measurement caveat first? |
| DEC-9 | [`DEC-9-delete-or-defend-list.md`](DEC-9-delete-or-defend-list.md) | TASK-100 (B-17) | The consolidated **per-product** delete-or-defend list (all 17 `ECOSYSTEM.md` products + shared systems + dormant repos + the 22 CLI service groups) — cites DEC-4/DEC-5/DEC-8 rather than duplicating them, and adds one new orphan-credential finding (`notion`, same shape as DEC-5's `metabase`/`method`). |
| DEC-10 | [`DEC-10-retire-unverifiable-turn-claim.md`](DEC-10-retire-unverifiable-turn-claim.md) | none (register-hygiene finding) — **RULED 2026-07-14: retire, `retired-by-unverifiability` — register patch PROPOSED, not yet applied** | `turn-definition-incompatible-with-april`'s own `check` field says April's counting script no longer exists and nothing can be re-run against it — retire the claim per `t2`'s own "unverifiable claims are deleted" rule, or keep it as a permanent red? |

## Status

**DEC-1, DEC-2, DEC-3 are ruled and executed** (2026-07-14; see each memo's
header). TASK-112, TASK-113, TASK-114 are `completed` in Task Copilot.
**DEC-10 is ruled** (retire); no `tc task` exists for it (register-hygiene
finding, not a workstream deliverable), and its `claims.yaml` edit is a
PROPOSED REGISTER PATCH held for the next serialized register-patch pass
(this session could not edit `claims.yaml` directly — concurrent edits in
progress).

DEC-4 through DEC-5, DEC-7, DEC-8, and DEC-9 tasks are `blocked` in Task
Copilot — the honest status for "preparable work complete, ruling not made
yet."
DEC-6 (TASK-125) is likewise `blocked`, and is additionally
**mechanically** enforced, not just a process convention: the ladder
bench's `run.py` refuses to execute a live (non-`--dry-run`) scored run
until DEC-6's header literally reads `Status: **ratified**` (see
`tools/cse-bench/benches/ladder/run.py`'s `check_signoff()`). Each task
will move to `completed` (or whatever the owner's chosen option's own
follow-up task is) once the owner picks and someone executes the
corresponding one-line command.

## Related, not yet decided

- **W-4 pilot recruits** is also an owner-queue item (`phase-4-handoff.md`
  §6 row 6) but is not a decision memo in this format — its recruit slot is
  prepared in
  [`../phases/phase-4-w4-external-pilot-kit.md`](../phases/phase-4-w4-external-pilot-kit.md)
  with an empty slot for the owner's 2–3 picks.
