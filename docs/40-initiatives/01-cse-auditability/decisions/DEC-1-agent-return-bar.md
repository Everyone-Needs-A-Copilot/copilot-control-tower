# DEC-1 — Agent-return bar: enforce vs amend

> **RULED 2026-07-14: AMEND (a third path, per-class ratchet at measured
> reality — offered in §5 as a variant of Option B, not pure enforce).**
> SOUL §6's flat ~100-token bar (met by zero agent classes when measured)
> is replaced by a per-class bar set at each class's current measured
> reality (`me` ~854, `doc` ~490, `sd` ~3,786, `uxd` ~5,089, `uids` ~4,118,
> `sec` ~3,556; all other classes ~893 overall median), framed explicitly
> as a ratchet that tightens as the return-contract work lands. EXECUTED in
> `claude-copilot@9359505`. Does not touch `.claude/agents/*.md` — the
> return contracts themselves are a separate, concurrently-owned
> workstream; this ruling only amends the bar they're measured against.
> **Honest status of `framework-agent-frugality`:** the amended bars equal
> today's measured class medians, so the *restated* claim (each class's
> median ≤ its own bar) is trivially true today — a legitimate but
> tautological pass by construction, not evidence of improved behavior. The
> collector's mechanical `check` (`threshold_tokens=300`, a proxy for the
> OLD flat 100-token bar) is unchanged and still reports 95%+ of returns
> "over 300" — that specific sub-check is now vestigial against the new
> per-class bars, not evidence the claim still fails. See the session
> report's PROPOSED REGISTER PATCH for the restatement this implies
> (`claims.yaml` not edited here per this session's hard constraint).

> tc task: **TASK-112** (R-1, `phases/phase-3-soul-remediation.md`) · Claim:
> `framework-agent-frugality` (`claims.yaml`) · Status: prepared, **not
> ruled** — owner decides.

## 1. The decision, in one sentence

Claude Copilot's SOUL §6 says agents must return **~100 tokens** to the main
session; real agents return roughly **10x** that — decide whether to build
mechanical enforcement toward the existing bar, or replace the bar with a
number the measured distribution actually supports.

## 2. Context, in plain language

SOUL.md (claude-copilot) states this as a non-negotiable: agents do the work,
externalize the detail to a work product, and hand back a short summary so
the main conversation's token budget stays cheap. "~100 tokens" is the
number written down for that summary. Nobody has ever checked whether agents
actually do this — until this program built a collector that reads every
subagent's final return message across the full session-transcript corpus.
They don't. The gap isn't small, and it isn't shrinking.

## 3. The evidence (real numbers, quoted with source)

**Source:** `tools/cse-bench/output/framework_soul-latest.json`,
`generated_at: 2026-07-13T18:26:30Z`, `metrics.agent_frugality` block.
Regenerated in this session via `cse_bench.py collect --only framework_soul`
against the live `~/.claude/projects` transcript corpus (n=104 subagent
invocation files, 4 excluded for no final text, 100 scored).

| Statistic | Today's real number (2026-07-13) | Previously registered (`claims.yaml`, last checked 2026-07-12) |
|---|---|---|
| n (scored returns) | 100 | not stated |
| Median | **1,032 tokens** | 658 tokens |
| Mean | 1,602.68 tokens | not stated |
| p90 | **3,921.8 tokens** | 2,749 tokens |
| % over 300-token threshold | **95.0%** | 86.2% |
| IQR (Q1–Q3) | 638.25 – 1,711.75 | not stated |

The SOUL bar is ~100 tokens; the 300-token `threshold_tokens` this collector
flags against is already **3x** that bar, and 95% of returns still exceed
it. **The gap has widened, not narrowed, in the one day since the register
was last checked** — this is not a stale number improving; the corpus has
grown and the distribution has gotten worse under every measure (median,
p90, and threshold breach rate all moved up). Whether that's a real trend or
noise from a small, growing sample cannot be told apart from one snapshot.

By agent type (same run, `metrics.agent_frugality.by_agent_type`), the
worst offenders are the design-chain agents: `uxd` median 5,089 (n=3), `sd`
median 3,786 (n=5), `uids` median 4,118 (n=1), `sec` median 3,556 (n=5). The
most frequent agent, `me` (n=32), still runs a median of 860 — nowhere near
100. Only `doc` (median 402, n=10) gets close to the same order of magnitude
as the bar, and even that is 4x over it.

**Caveat:** this is single-author data (one person's session corpus on one
machine); no external-pilot data exists yet to say whether this pattern
generalizes (W-4, still pending recruits — see DEC-4/DEC-5 sibling memos and
the pilot kit).

## 4. Options and consequences

**Option A — Enforce.** Tighten the agent return-format instructions in
each agent definition, and add a `SubagentStop` hook check that warns above
a threshold and denies above a harder one. *Consequence:* agents that
currently return detailed synthesis (design rationale, architecture
tradeoffs) will be forced to compress it into work products more
aggressively; if the ~100 bar really is unrealistic for design-chain work,
this creates real friction and possibly information loss without a rewrite
of what those agents are asked to produce. Requires actual implementation
work in claude-copilot (agent instruction edits + a new hook) before the
claim can flip to `passing`.

**Option B — Amend the SOUL bar.** Propose a SOUL §6 amendment (via §10
Evolution) that replaces "~100 tokens" with an evidence-based number derived
from this distribution — e.g. a bar stated as a target range or as
"proportional to a fixed unit + agent-class multiplier," with the measured
distribution attached as the justification. *Consequence:* the bar becomes
honest and checkable again, but the underlying token-budget problem SOUL §3
("Context Is the Budget") is written to solve is left unaddressed — main
sessions keep paying 1,000+ tokens per delegated call, ~10x the design
intent, just with a bar that no longer calls it out as a violation.

**Option C — Do nothing.** Leave the SOUL bar at ~100 tokens, unenforced,
with the claim `failing`. *Consequence:* the claim register keeps recording
an honest failure (which is itself compliant with this initiative's own
rule that failing claims must be shown, not hidden) — but no forward
progress against R-1 happens, TASK-112 stays open, and W-5 (the efficiency
wave, which explicitly starts from this exact gap) has no direction to
build against.

## 5. Recommendation (advice, not a ruling)

This is advice: given the size and consistency of the gap (every agent type
sampled exceeds the bar, including the highest-volume one), Option A alone
risks failing without a companion move — a hook that denies over-threshold
returns will just get bypassed or will start blocking legitimate design-chain
handoffs. A **combined path** (amend the bar for design-chain agents whose
job is inherently more token-dense, per §10's own criteria for "we learn
something durable that contradicts a current principle"; enforce a stricter
version of the original ~100 bar for the high-frequency, low-complexity
agents like `me` and `doc` where it's closest to already achievable) fits
the evidence better than picking purely A or purely B — but that
combined path is not one of the two the task frames, so it is offered here
as a third path for the owner to accept, reject, or split into two separate
rulings.

## 6. Exact one-line actions

- **Option A (enforce):** `tc task update 112 --status in_progress --metadata '{"decision":"enforce"}'` then hand TASK-112 to `me` to implement the `SubagentStop` size check in claude-copilot.
- **Option B (amend):** `tc task update 112 --status in_progress --metadata '{"decision":"amend"}'` then hand TASK-112 to `ta`/`doc` to draft the SOUL §10 amendment with this memo's distribution attached.
- **Option C (do nothing):** `tc task update 112 --status blocked --metadata '{"decision":"deferred"}'` (no further action; claim stays `failing` in `claims.yaml`).
- **Re-run this evidence:** `cd tools/cse-bench && python3 cse_bench.py collect --only framework_soul`
