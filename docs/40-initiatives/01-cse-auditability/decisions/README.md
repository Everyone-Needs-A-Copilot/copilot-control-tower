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
| DEC-1 | [`DEC-1-agent-return-bar.md`](DEC-1-agent-return-bar.md) | TASK-112 (R-1) | Enforce the ~100-token agent-return bar, or amend the SOUL bar to match measured reality? |
| DEC-2 | [`DEC-2-protocol-adoption.md`](DEC-2-protocol-adoption.md) | TASK-113 (R-3) | Protocol-declaration adoption is ~0%: enforce it, simplify it, or retire the requirement? |
| DEC-3 | [`DEC-3-soul-94pct-correction.md`](DEC-3-soul-94pct-correction.md) | TASK-114 (R-5) | Ratify the SOUL §3 correction replacing the falsified "~94% less context" figure? |
| DEC-4 | [`DEC-4-stale-clones.md`](DEC-4-stale-clones.md) | TASK-118 (R-9) | Delete or keep the stale `shared-docs`/`conversations-copilot` clone artifacts? |
| DEC-5 | [`DEC-5-configure-or-cut-services.md`](DEC-5-configure-or-cut-services.md) | TASK-122 (R-13) | Configure or cut: fireflies, reddit, metabase, method? |
| DEC-7 | [`DEC-7-c3-hook-rollout-gate.md`](DEC-7-c3-hook-rollout-gate.md) | TASK-103 (C-3) | The `claude-copilot` hook-path defect is fixed and scripted-reverified — does that satisfy Rollout Readiness condition 1, or does the owner still need to run one real session before C-3 widens to consumer repos? |

*(DEC-6 number is reserved/in flight elsewhere; not yet present in this
directory as of this index update.)*

## Status

DEC-1 through DEC-5 tasks are `blocked` in Task Copilot — the honest status
for "preparable work complete, ruling not made yet." DEC-7's task
(TASK-103) is also `blocked`, pending the owner's ruling on whether one real
`claude-copilot` session is still required. Each task will move to
`completed` (or whatever the owner's chosen option's own follow-up task is)
once the owner picks and someone executes the corresponding one-line
command.

## Related, not yet decided

- **W-3 MLP rubric sign-off** and **W-4 pilot recruits** are also owner-queue
  items (`phase-4-handoff.md` §6 row 6) but are not decision memos in this
  format — W-4's recruit slot is prepared in
  [`../phases/phase-4-w4-external-pilot-kit.md`](../phases/phase-4-w4-external-pilot-kit.md)
  with an empty slot for the owner's 2–3 picks.
