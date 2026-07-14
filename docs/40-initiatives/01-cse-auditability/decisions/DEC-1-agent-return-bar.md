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
>
> **CORRECTED 2026-07-14 (same day, coordinator review): the first cut of
> this ruling shipped a pass-by-construction trap.** Setting each class's
> bar exactly equal to its own then-measured median makes the *restated*
> claim (median ≤ bar) trivially true by definition — it can never fail,
> which is unfalsifiable, which is exactly what `t2` ("no claim outlives
> its check") exists to catch. A manufactured green is not a claim. Fixed
> by restructuring into three distinct pieces, all EXECUTED in
> `claude-copilot@b50f66a` (SOUL.md) and
> `copilot-control-tower@34e746c` (the two collectors this claim's check
> depends on):
> 1. **A falsifiable CEILING.** Truth condition, stated explicitly in SOUL
>    §6: no agent class's median return may exceed its registered ceiling.
>    A breach is a genuine regression and the claim **fails** — proven
>    live: re-running `framework_soul` this session already shows
>    `ceiling_check.verdict == "breach"` for 5 classes (`cco`, `cw`, `ind`,
>    `qa`, `ta`) whose current medians exceed the shared default ceiling.
>    This is not a tautology.
> 2. **A pre-registered, descend-only ratchet.** The ceiling drops to a
>    fresh re-measured median once that median lands at or below the
>    current ceiling (mechanical, no further SOUL edit needed — the *rule*
>    is ratified, not the number); it never rises to absorb a regression.
>    Next step pre-registered: a quarter reduction per class from the
>    current ceiling, once the return-contract work lands and a fresh
>    corpus is measured — chosen because it exceeds half of every measured
>    class's IQR (signal, not noise).
> 3. **A separate, honestly-failing aspiration claim** —
>    `framework-agent-return-aspiration` — carrying SOUL's original
>    ~100-token design intent, kept red rather than folded into the
>    ceiling (collapsing the two is exactly how the prior bar became
>    unfalsifiable).
>
> Collector fixes (additive only, nothing else in either file touched):
> `collectors/framework_soul.py` now emits `agent_frugality.ceiling_check`
> (per-class breach detection against the frozen 2026-07-13 baseline
> ceilings, the pre-registered ratchet step, and the aspiration gap);
> `collectors/transcripts.py`'s `protocol_declaration_rate_loose/strict`
> (DEC-2's retired metric) now carries an explicit
> `protocol_declaration_rate_status: {vestigial: true, ...}` marker instead
> of silently living on as a check for a dead requirement. Verified:
> `check_claims.py` 0 violations; both collectors run clean.
>
> **Honest status of `framework-agent-frugality`, corrected:** it is no
> longer a tautological pass. Under the restated ceiling semantics it is
> currently **mixed** — the 6 classes with a class-specific ceiling
> (`me`/`doc`/`sd`/`uxd`/`uids`/`sec`) pass (their ceiling was set to their
> own baseline median and no regression has been re-measured yet); classes
> falling back to the shared default ceiling (`893`) already show breaches
> in a live re-run. See PROPOSED REGISTER PATCHES below for the exact
> restatement this implies for `claims.yaml` (not edited here — off-limits
> this session).

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

## 7. Post-ruling correction — the pass-by-construction trap (2026-07-14, same day)

**What went wrong in the first cut.** The amend-path bar was set exactly at
each class's own then-measured median. A claim whose truth condition is
"X ≤ X" is unfalsifiable — it can never fail, so it isn't a claim, it's a
description wearing a claim's grammar. `t2` (`t2-no-claim-outlives-its-check`)
exists precisely to catch this shape of defect.

**The fix, in three parts (see SOUL.md §6, `claude-copilot@b50f66a`):**

1. **Ceiling, not description.** Truth condition: no agent class's median
   return may exceed its registered ceiling. Falsifiability confirmed
   live — a fresh `framework_soul` collect this session shows
   `ceiling_check.verdict == "breach"` for `cco`/`cw`/`ind`/`qa`/`ta`
   (classes without their own class-specific ceiling, falling back to the
   shared `~893` default, whose current medians already exceed it).
2. **Descend-only ratchet, pre-registered (V-2).** The ceiling drops to a
   fresh, lower re-measured median once one lands; it never rises to
   absorb a regression. Next step pre-registered: a quarter reduction per
   class, once the return-contract work lands.
3. **A separate, honestly-failing aspiration claim** —
   `framework-agent-return-aspiration` — carries the original ~100-token
   design intent forward instead of deleting it or hiding it inside a
   ceiling that already passed.

**Collector fix** (`copilot-control-tower@34e746c`,
`tools/cse-bench/collectors/framework_soul.py`): added
`agent_frugality.ceiling_check` (per-class breach detection against
frozen 2026-07-13 baseline constants — deliberately not a live recompute,
or the ceiling could never fail — plus the pre-registered ratchet step and
the aspiration gap). `pct_over_threshold`/`threshold_tokens=300` are kept,
re-attributed in the collector's `definitions` text to evidence
`framework-agent-return-aspiration` instead of the (now-restructured)
`framework-agent-frugality`. `collectors/transcripts.py` similarly gained
a `protocol_declaration_rate_status` marker (`vestigial: true`) on DEC-2's
retired metric pair, rather than leaving a live-looking check for a dead
requirement.

**PROPOSED REGISTER PATCHES (not applied — `claims.yaml` off-limits this
session):**

- `framework-agent-frugality` — restate `statement` as: *"No agent class's
  median return exceeds its registered ceiling (SOUL §6: `me` 854, `doc`
  490, `sd` 3786, `uxd` 5089, `uids` 4118, `sec` 3556, other classes 893 —
  2026-07-13 baseline, descends only per the pre-registered ratchet)."*
  Restate `check` to read `metrics.agent_frugality.ceiling_check.verdict`
  from `framework_soul-latest.json` (`"no_breach"` → passing, `"breach"`
  → failing) instead of the old `pct_over_threshold`/300 proxy. Current
  status: **mixed** in a live run — passes for the 6 explicitly-measured
  classes, fails for classes on the shared default ceiling with a higher
  natural token footprint (`cco`, `cw`, `ind`, `qa`, `ta`). The owner
  should decide whether those 5 classes need their own registered
  ceiling (closer to their actual footprint) or whether the shared
  default is itself the honest floor and the breach stands.
- **New claim** `framework-agent-return-aspiration` — statement: *"Agent
  returns approach SOUL's original design intent: ~100 tokens per return,
  flat across all classes, reflecting a summary + pointer rather than
  full reasoning."* Check: `metrics.agent_frugality.ceiling_check.aspiration.gap_by_class`
  from the same collector output. Status: **failing** — every measured
  class's gap to the 100-token target is strictly positive (smallest gap
  ~356 tokens for `doc`, largest ~4,989 for `uxd` in the latest run). This
  is the honest red the ceiling claim no longer has to carry.
