# Delegation-capable harness mode — making the agent layer measurable

> Claim: `ladder-cannot-measure-framework-agent-layer` (`claims.yaml`, passing).
> This memo is written and committed **before** `delegation_harness.py`'s
> live 8-cell comparison (§2) is run — §0–§2 are pre-registration; §3
> ("Results") is appended and committed separately, after the harness runs,
> per this program's own "no number may be quoted before its definition is
> committed" rule (the same discipline `phase-4-cross-harness-behavior.md`
> already used for t6).

## 0. Why this exists

`ladder-cannot-measure-framework-agent-layer` records a real, mechanically
verified fact: across the v2 ladder's 72 cells — including the 3 rungs
(framework/knowledge/integrations) where the full 13-agent roster was
materialized and available — the model invoked the delegation tool **zero**
times. That claim's own evidence already names the next step: "a valid
framework-layer test requires a harness mode where delegation actually
fires." This memo pre-registers that mode; `delegation_harness.py`
implements it.

## 1. Feasibility investigation (done BEFORE this memo's §2 was written —
same pattern `phase-4-cross-harness-behavior.md` Sec 1 used for t6: a
feasibility check may look at live data before the *comparison itself* is
pre-registered and run)

Four things were tested live, cheaply (3 single-cell probes, real
`claude -p` calls, isolated HOME/workdir, `configs.materialize_framework()`
reused verbatim — no reimplementation of the ladder's own isolation
mechanism):

**(a) Tool-name mismatch found and checked against the real 72-cell corpus.**
The delegation tool is named **`Agent`** in this machine's installed Claude
Code CLI, not `Task` — confirmed by `tools/cse-audit/session_metrics.py`'s
own `AGENT_TOOL_NAMES = {"Agent", "Task"}` (its comment: "'Agent' is what
this corpus actually uses... 'Task' is included defensively"). The existing
claim's `check:` field filters `name=="Task"` only. Re-running that same
check against the actual 72-cell transcript corpus (still on disk under
`/var/folders/.../T/cse-bench-ladder-*/`, per that claim's own "while these
ephemeral temp directories persist on this machine" caveat) but scanning
for **either** `Agent` or `Task` still finds **zero** hits — the full set of
distinct `tool_use.name` values across all 72 cells remains exactly `{Bash,
Edit, Read, Write}`. The original "zero" finding is NOT an artifact of the
tool-name mismatch; it reproduces under the broader, correct definition.
(The check field's narrowness is nonetheless a real, if inert-in-this-case,
fragility — noted here so a future re-run on a differently-named Claude Code
version doesn't silently mis-measure.)

**(b) Explicit forcing works.** A single probe cell (framework rung, 13
agents present, sonnet), given a brief that explicitly instructed "invoke
the Task tool now, delegating to the 'qa' subagent, to write a file" —
produced a real `Agent` tool_use call, a real subagent turn, and the
correctly-delegated file. **This proves the delegation mechanism is
available and functional under headless `claude -p`** — the tool is not
hidden, gated, or absent in non-interactive mode. (1 cell, $0.178,
duration_ms 21,483, num_turns 2.)

**(c) Job complexity alone, without routing framing, is not sufficient.** A
second probe cell ran a genuinely multi-domain brief — three separate named
concerns (secure credential handling, CLI onboarding UX, CSV→JSON data
migration), each requiring a distinct file and an explicit per-part review —
with **no** forcing instruction and **no** `/protocol` prefix. 12 internal
turns, all 3 parts (plus a completion report) correctly delivered — entirely
by the main session itself, via `Bash`/`Read`/`Write` only. **Zero**
delegation. (1 cell, $0.369, duration_ms 68,446, num_turns 12.)

**(d) `/protocol` prefix — the real framework entry point — reliably
induces natural delegation.** The IDENTICAL brief from (c), with the SAME
framework rung, changed in exactly one way: prefixed with `/protocol ` (the
project slash command `materialize_framework()` already copies into every
framework-rung workdir from claude-copilot's own `VERSION.json` roster — not
a benchmark-specific instruction). Result: **5** real `Agent` tool_use
calls, delegating to `me`, `sec`, `cw`, `qa`, `me` in that order, with the
model's own result text explaining its routing judgment ("I skipped the
service-design/visual-design/brand agents... routed it as a Technical build
with the three reviews (sec, cw, qa) the task actually called for"). All 5
deliverables produced correctly. (1 cell, $1.070, duration_ms 95,321,
num_turns 3 -- fewer top-level turns than (c) because delegated work happens
inside subagent turns, which `num_turns` on the main envelope does not
count.)

**(e) Corroborating evidence from real production sessions**
(`tools/cse-audit/output/session_metrics.csv`, n=113 real sessions, no new
cost — pure read): sessions with ≥1 real delegation (56/113) average **21
turns / 249 main-session assistant messages**; sessions with zero
delegation average **4 turns / 51 messages** — an order-of-magnitude gap in
session depth. This is consistent with, but does not by itself explain, (c)
vs (d): (c) already reached 12 internal turns within one `-p` shot without
delegating, so raw turn/message count alone is not sufficient either — what
distinguishes real delegating sessions is that they are near-universally
launched via `/protocol` (or an equivalent routing-first entry point),
which (d) reproduces directly and mechanically, not by proxy.

**Conclusion:** delegation does NOT fail to fire because `-p` mode lacks
the tool, and does NOT fail to fire merely because ladder jobs are "too
small" or "too single-domain" (12-turn, 3-domain brief still didn't
delegate). It fails to fire because **the ladder's job briefs bypass the
framework's own routing entry point.** `/protocol <brief>` is both the
mechanism real sessions actually use and a mechanically reproducible,
scriptable harness mode — this is the delegation-capable mode this memo
registers.

## 2. The delegation-capable mode (pre-registered, V-2)

### 2.1 What changes vs. the existing ladder

Exactly one thing: the brief text passed to `claude -p` is prefixed with
the fixed, job-agnostic string `/protocol ` (`delegation_harness.py`'s
`PROTOCOL_PREFIX`) before the job's own unmodified `job_pack.py` brief.
Nothing else changes:

- **Rungs**: `configs.materialize_framework()` and
  `configs.materialize_framework_minus_agents()`, reused **verbatim** — the
  same 13-agent roster (or its deliberate absence, QA WP-79's ablation
  rung) the existing ladder already uses. `bare`/`knowledge`/`integrations`
  are **not** run under this mode (see §2.4 scope).
- **Job pack**: all 4 jobs from `job_pack.py` v2, **unmodified** briefs,
  `acceptance_check`s, and `protected_files` lists.
- **Model call**: `claude -p <prefixed brief> --model sonnet
  --output-format json --dangerously-skip-permissions --setting-sources
  project --max-budget-usd 3.0`, identical to `run.py`'s own
  `build_claude_command()` (reused, not reimplemented).
- **Isolation**: same per-run `HOME` override, same `--setting-sources
  project`, same PATH levers as every other ladder rung.

### 2.2 What is measured per cell (`delegation_harness.py`)

- `t_working` (bool): the job's own unmodified mechanical `acceptance_check`
  AND `protected_files` check — identical definition to the rest of the
  ladder.
- `n_agent_delegations` / `delegated_agent_types` (ordered list): every
  `Agent`/`Task` `tool_use` block in the main session transcript, and its
  `input.subagent_type`.
- `main_tool_use_names`: every tool the MAIN session itself invoked (not
  subagent-internal tools), for a full behavioral record.
- Token accounting, split two ways (NOT conflated, per this bench's own
  `marginal_spend`/`billed_volume` precedent, QA WP-23 finding 1): main-
  session usage via `run.py`'s existing `extract_usage()` (unchanged), and
  **subagent** usage summed across every sibling
  `<sessionId>/subagents/agent-*.jsonl` file's own `message.usage` blocks
  (deduped by `message.id`, same convention `extract_turn_breakdown()`
  already uses for the main session) — so "tokens spent in subagents vs
  main," as this task's own instruction asks for, is a first-class,
  separately-reported figure, not inferred.
- Wall-clock seconds, `total_cost_usd` (list-price-equivalent — see §2.6).

### 2.3 The comparison (the actual "does the agent layer help" test)

For each job `J`, both rungs run under the SAME delegation-capable mode
(same `/protocol`-prefixed brief, same acceptance check). Per-job verdict:

- **`helps`** iff `t_working(framework, J) == True` AND
  `t_working(framework_minus_agents, J) == False`.
- **`hurts`** iff the reverse (`framework_minus_agents` passes,
  `framework` fails).
- **`no_effect`** iff both agree (both pass or both fail) — this is a real,
  reportable outcome, not a null result to be explained away; per this
  register's own "quoting caveat" convention (README.md), a `no_effect`
  reading is reported plainly, not spun.

**Pack-level reporting**: per-job results are shown individually (never
collapsed into a single pass-rate number alone, matching the existing
ladder's own "Quoting caveat" rule) alongside each cell's
`n_agent_delegations` — a job where `framework_minus_agents` ALSO shows
`n_agent_delegations > 0` would be a structural anomaly worth flagging (it
should be mechanically impossible, since `.claude/agents/` is absent at
that rung, but this is checked, not assumed).

### 2.4 Explicitly NOT tested (stated here so it cannot be read as tested
later)

- `t_loveable` / MLP-rubric equivalence — blocked by DEC-6 (unratified);
  this comparison uses `t_working` only, exactly like `cross_harness.py`
  before it.
- `bare`, `knowledge`, or `integrations` rungs under delegation mode.
- Multiple reps per cell (reps=1, cost-bounded — see §2.6; a single
  divergent rep in a future re-run is a real finding, not something this
  result rules out).
- Whether `/protocol`'s own routing CHOICE (which agent(s) it picks) is
  optimal — only whether having agents available to delegate to, vs not,
  changes the mechanical PASS/FAIL outcome.
- Any claim that this is "the" delegation-capable mode in some universal
  sense — it is *a* mode that reproduces the mechanism real sessions use;
  a stricter multi-turn/interactive-equivalent harness (chained `--resume`
  calls) is a distinct, harder build explicitly out of scope here.

### 2.5 Job-level expectations, named up front (not discovered after)

Per `phase-4-cross-harness-behavior.md`'s own precedent (job-2 at
`+framework` is expected-unreachable regardless of harness, since
`CC_KNOWLEDGE_REPO` is an empty tree at this rung): **job-2-house-voice's
correct answer is knowledge-gated, not agent-gated** — neither rung
materializes real knowledge content here, so both rungs failing job-2 is an
EXPECTED `no_effect` agreement, not evidence the agent layer doesn't help;
a `cw` (copywriter) agent delegation may still fire on this job (as it did
in the probe, §1(d)) even though the underlying knowledge gap makes the
deliverable itself un-passable at this rung. This is named before the run,
not rationalized after seeing a result.

### 2.6 Cost ceiling (stated up front, per this task's instruction)

**$3.00 per cell** (native `--max-budget-usd`, same default the rest of
this bench already uses) and **900s wall-clock timeout per cell**. 4 jobs ×
2 rungs × 1 rep = **8 live cells**, absolute worst case 8 × $3.00 = $24.
Real observed per-cell cost from the 3 feasibility probes in §1 ranged
$0.18–$1.07 (probe (d), the one structurally closest to this comparison's
actual cells, cost $1.07) — so a realistic expectation is roughly
$4–$9 for the 8-cell run, not the $24 worst case. **Every dollar figure in
this memo (§1 and any real number in §3) is Claude Code's own computed
list-price-equivalent `total_cost_usd`, drawn against the owner's Claude
Code SUBSCRIPTION usage/rate-limit budget — never an amount separately
billed** — per the standing convention `phase-4-cross-harness-behavior.md`
§6 already established (`ladder_config_materialization`'s
`cost_accounting_convention` in `claims.yaml`); not re-derived here, only
cited. Total investigation cost across §1's 3 probes plus §2's 8-cell run:
bounded at 3×$3 + 8×$3 = $33 worst case; real total reported in §3.

## 3. This memo's own status

Committed **before** `delegation_harness.py`'s 8-cell live comparison (§2.3)
is run. §1's three feasibility probes were run and their real numbers
recorded ABOVE this line (matching `phase-4-cross-harness-behavior.md`'s own
precedent of a feasibility check preceding the comparison's own
pre-registration) — but the comparison itself, and the register's own
`claims.yaml` entries about the agent layer's marginal value, are written
**after** this commit, never before.

## 4. Results (appended after the definition above was committed)

