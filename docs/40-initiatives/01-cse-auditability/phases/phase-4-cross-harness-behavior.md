# Cross-harness behavior equivalence — closing t6 the honest way

> tc task: **TASK-146** (see `tc task get 146`). Claim: `t6-two-harnesses-one-behavior`
> (`claims.yaml`). This memo is written and committed **before** any
> cross-harness cell is run (V-2 discipline) — §1–§3 are pre-registration;
> §4 ("Results") is appended and committed separately, after the harness
> runs, per this program's own "no number may be quoted before its
> definition is committed" rule.

## 0. Why this exists

Content-hash parity between claude-copilot and codex-copilot is clean
(`check-upstream-parity.py --content --json`: `status: pass`, 68 files, 0
drift, codex-copilot commit `ce087be1`/`7f7d6f6`). But `t6`'s own statement
requires content **and** behavior: *"same solution, different harness is a
tested property, not a slogan."* No behavior-level check has ever existed
in this codebase — `codex-copilot/scripts/run-agent-evals.sh` only runs
`cc eval run` against codex's own contracts and its own golden sets; it
never compares an outcome against claude-copilot's. A content check alone
cannot satisfy a claim whose statement names two separate levels — that is
exactly this program's own "check weaker than statement" defect class
(seven other instances already found and corrected this session; this memo
exists so `t6` is not the eighth).

## 1. Feasibility verdict (Task 1)

**YES — the Codex CLI can be driven headlessly on this machine.** Evidence,
not assumption:

- `codex --version` → `codex-cli 0.144.4`, installed via `brew`
  (`/opt/homebrew/bin/codex`).
- `codex doctor` reports 16 ok / 1 idle / 1 note / 1 warn / 0 fail:
  `stored auth mode: chatgpt`, `stored ChatGPT tokens: true`, websocket
  reachability `HTTP 101 Switching Protocols`, active-provider endpoint
  reachable (`HTTP 404` on the base URL, i.e. a real response, not a
  connection failure). The one `warn` (`rollout files are missing from the
  state DB`) and the one `note` (background app-server not running,
  ephemeral mode) are both inert for a one-shot `codex exec` call.
- A real, live, non-interactive invocation succeeded:
  `codex exec --sandbox read-only --skip-git-repo-check --json "Reply with
  exactly the text: SMOKE_TEST_OK. Do not run any commands."` returned
  `returncode 0` in 22.7s, with a well-formed JSONL event stream ending in
  `{"type":"turn.completed","usage":{"input_tokens":16820,
  "cached_input_tokens":9984,"output_tokens":8,"reasoning_output_tokens":0}}`
  and the exact expected `agent_message` text.
- No script in codex-copilot invokes `codex exec` anywhere today
  (`grep -rl "codex exec"` across the repo returns nothing) — the harness
  built below (§2) is genuinely new instrumentation, not a rewire of
  something that already existed.

**Billing model caveat (stated honestly, not glossed over):** Codex is
authenticated via a ChatGPT subscription (`auth mode: chatgpt`), not a
metered Anthropic-style API key. `codex exec --help` (0.144.4, checked
live) has **no `--max-budget-usd` or any dollar-cap flag** — verified, not
assumed, matching this repo's own "check the real installed --help before
citing a flag" rule. The only preventive ceiling available on the Codex
side is wall-clock (`subprocess.run(..., timeout=...)`, self-enforced by
the harness, same mechanism the ladder already uses for Claude). Real
per-cell cost is therefore reported in **tokens** (as returned by
`turn.completed`'s `usage` block) for Codex, and in both tokens and
`total_cost_usd` for Claude (which does have a native `--max-budget-usd`
and a metered API key) — this asymmetry is a real environment fact, not a
harness bug, and is carried into every result row rather than papered over
with a fabricated USD figure for Codex.

## 2. What "two harnesses, one behavior" means here (pre-registered, V-2)

### 2.1 The two harnesses compared

- **Claude harness**: `tools/cse-bench/benches/ladder/`'s existing
  `+framework` rung (`configs.materialize_framework`), **reused verbatim,
  not reimplemented** — fresh isolated `HOME`, `.claude/{agents,commands,
  skills}/` + `CLAUDE.md` copied from claude-copilot's own `VERSION.json`
  roster, `CC_KNOWLEDGE_REPO` pointed at an empty tree, `tc`/`cc` on PATH,
  cli-copilot's `copilot` entry point **excluded** from PATH (same as every
  other `+framework` ladder run). Job call: `claude -p <brief> --model
  sonnet --output-format json --dangerously-skip-permissions
  --setting-sources project`, `run_claude_job()`/`extract_usage()` reused
  from `run.py` unmodified.
- **Codex harness** (new, `tools/cse-bench/benches/ladder/codex_harness.py`):
  a fresh isolated workdir + `CODEX_HOME`, with codex-copilot's own root
  `AGENTS.md` (verbatim, the file real codex-copilot users get — parity
  contract's own "Implemented" list, item 1: "`AGENTS.md` project
  instructions") copied into the job workdir as the framework-rung
  material. `CC_KNOWLEDGE_REPO` points at the same empty tree as the
  Claude side (job-2's brief references that env var by name, harness-
  agnostically). `copilot` CLI excluded from PATH (parity with the Claude
  side's `+framework`, not `+integrations`). Job call:
  `codex exec -C <workdir> --sandbox workspace-write --skip-git-repo-check
  --json <brief>`, non-interactive.

**Named asymmetry, not hidden:** codex-copilot's parity contract
(`docs/05-reference/03-parity-contract.md`) documents that Claude's
per-agent `.claude/agents/*.md` roster is mirrored via
`plugins/codex-copilot/skills/*/SKILL.md` + `agent-catalog.json`, delivered
through the Codex **plugin marketplace install**, not as per-project files
copied into a target repo the way `.claude/agents/` is. There is no 1:1
file-for-file equivalent to replicate into an isolated job workdir the way
`configs._copy_framework_files()` does for Claude. Materializing only
`AGENTS.md` for the Codex side is therefore the fair, honest apples-to-
apples point: both `CLAUDE.md` and `AGENTS.md` are each harness's
official "read this before working" project-instructions primitive, and —
critically — **this asymmetry does not under-test the comparison**,
because of the next paragraph.

### 2.2 The known instrument limitation (stated up front, not discovered after)

The ladder's headless `claude -p` mode has separately been observed to
invoke the Task tool (subagent delegation) **zero times across 72 cells**
in this program's existing data. Codex's `codex exec` single-shot mode has
no equivalent delegation mechanism invoked automatically either. **This
cross-harness check therefore tests whether the presence of a project-
instructions file (`CLAUDE.md` vs `AGENTS.md`) changes a single-shot,
tools-enabled model's outcome on a job — it does NOT test, and must never
be reported as testing, multi-agent orchestration/delegation equivalence
between the two frameworks.** Given neither harness's headless mode
delegates, comparing `CLAUDE.md`-only vs `AGENTS.md`-only materialization
is the actual, honest scope of "framework rung" on both sides — not a
narrowing introduced by this check, but a fact about what both harnesses'
non-interactive modes exercise regardless of what gets materialized on
disk.

### 2.3 The job pack (reused verbatim, not reinvented)

All 4 jobs from `job_pack.py` v2 (mechanically-checkable, fabrication-
resistant per-job, per the ladder's own README "Quoting caveat"):
`job-1-bugfix` (control), `job-2-house-voice` (knowledge-discriminating —
expected to be UNSOLVABLE correctly by either harness at `+framework`,
since neither materializes real knowledge content at this rung — a
`t_working` miss here is not evidence of a harness defect),
`job-3-integration-report` (integration-discriminating — the `copilot` CLI
is excluded from PATH on both harnesses at this rung, so the CORRECT
answer on both sides is the honest "integrations unavailable" fallback,
not fabricated service data), `job-4-toolkit` (framework-discriminating).
Each job's own `acceptance_check` (its `check.py`/`test_*.py`, exit 0 =
`t_working`) is run **unmodified, identically** against whichever
harness's workdir just ran — this is what makes "same acceptance check"
literally true rather than aspirational: it is the same Python file,
invoked the same way, reading the same protected-files list.

### 2.4 The equivalence criterion (the precise definition asked for)

For a given job `J`, let `claude_result = t_working(claude_workdir_after_J)`
and `codex_result = t_working(codex_workdir_after_J)`, both booleans from
`J`'s own `acceptance_check` exit code (0 = pass), plus each harness's
`protected_files` check (a violated "do not modify X" instruction fails
`t_working` too, exactly as the existing ladder already treats it).

**`J` is BEHAVIOR-EQUIVALENT across harnesses iff `claude_result ==
codex_result`** — both harnesses reach the same PASS/FAIL outcome under
the identical mechanical acceptance check. This is deliberately the
narrowest defensible reading of "same solution, different harness is a
tested property": it does not require byte-identical deliverables (a
`t_loveable`-style qualitative match), and it does not require identical
token counts or wall-clock time (those are recorded per §2.5 for
transparency but are NOT part of the pass/fail equivalence test) — only
that the same job, given the same acceptance bar, resolves the same way on
both sides. A future, stricter definition (e.g. requiring rubric-level
qualitative match) is explicitly out of scope here and would need its own
separate V-2 pre-registration; this one is not silently substituted for
that harder claim.

**The pack-level claim** ("two harnesses, one behavior," matching t6's own
statement) is TRUE iff **all 4 jobs are behavior-equivalent** by the
per-job definition above, reps=1 (cost-bounded — see §2.6). A single
job-level divergence is a genuine, named finding, not grounds to redefine
equivalence after the fact.

**Explicitly NOT tested, stated here so it cannot be claimed as tested
later:**
- `t_loveable` / MLP-rubric equivalence (out of scope; would need a
  second, separately-registered blind-judging protocol run twice).
- Multi-agent delegation/orchestration equivalence (§2.2 — neither
  harness's headless mode delegates).
- Equivalence at any rung other than `+framework` (`bare`/`+knowledge`/
  `+integrations` are not run cross-harness here).
- Byte-level or stylistic equivalence of the produced deliverable.

### 2.5 What is measured and recorded per cell (both harnesses)

`t_working` (bool, mechanical), wall-clock seconds, `protected_files`
check result, and tokens — Claude: `marginal_spend`/`billed_volume`
(`run.py`'s existing `extract_usage()`, unmodified) plus `total_cost_usd`;
Codex: `input_tokens`/`cached_input_tokens`/`output_tokens`/
`reasoning_output_tokens` summed across the call's `turn.completed`
event(s) (no native USD figure — see §1's billing-model caveat). Every
cell's full raw envelope (Claude JSON / Codex JSONL) is written to
`tools/cse-bench/benches/ladder/output/cross_harness-runs/<UTC stamp>/` for
audit, matching the ladder's own "nothing written to output/ during
--dry-run, everything written during a live run" convention.

### 2.6 Cost ceiling (stated up front, per this task's instruction)

**$3.00 per Claude job call** (native `--max-budget-usd`, same default this
repo's ladder already uses) and a **900s wall-clock timeout per call on
both harnesses** (same default as the ladder; Codex has no dollar-cap
flag — see §1). 4 jobs × 2 harnesses × 1 rep = **8 live cells**, absolute
worst case 4 × $3.00 = $12 on the Claude side; Codex side bounded by
wall-clock and token volume only, reported in §4 once real, not estimated
in advance beyond noting the smoke-test call above cost 16,820 input
tokens (9,984 cached) / 8 output tokens for a trivial one-line reply —
real coding jobs will cost materially more, reported honestly in §4, not
projected here.

## 3. This memo's own status

Committed **before** `cross_harness.py` (§2's harness) is run against any
job. §4 is appended in a **separate commit**, after real cells run, so the
git history itself shows the definition preceded the data — no number
above this line at the time of the first commit; §4 below (once appended)
is the only section quoting real results.

## 4. Results (appended after the definition above was committed)

Built: `tools/cse-bench/benches/ladder/codex_harness.py` (new, the
Codex-side materializer/job-runner) and `tools/cse-bench/benches/ladder/
cross_harness.py` (new, the comparator — reuses `configs.py`/`run.py`
verbatim for the Claude side, per §2.1). `test_cross_harness.py` (12
tests, pure-function coverage, no live calls) and `--dry-run` (validated
4/4 jobs on both harnesses, 0 wiring problems, 0 model calls) both pass.
One throwaway pipeline-verification cell (job-1-bugfix, scratch out-dir,
never under `output/`) was run first to confirm the mechanism itself
works end-to-end, matching this bench's own established precedent
(`ladder_config_materialization`'s "verify on one throwaway cell before a
full live run" caveat, `ladder_job_pack_v2`'s "6 throwaway
pipeline-verification cells... run first" note) — not a violation of §2's
pre-registration, since only the harness's mechanics were being checked,
not a job's outcome.

The full, real, 4-job × 2-harness × 1-rep = 8-cell pack then ran live
(`python3 cross_harness.py --timeout 600`), writing every cell's full raw
envelope to `tools/cse-bench/output/cross_harness-runs/20260714T155309Z/`.

| job | discriminates | claude `t_working` | claude cost | codex `t_working` | codex tokens | behavior-equivalent |
|---|---|---|---|---|---|---|
| job-1-bugfix | control | **True** | $0.1547 (18.6s) | **True** | 342,650 (55.8s) | **True** |
| job-2-house-voice | knowledge | **False** | $0.2553 (36.0s) | **False** | 170,009 (38.2s) | **True** |
| job-3-integration-report | integrations | **True** | $0.1534 (18.8s) | **True** | 179,557 (31.2s) | **True** |
| job-4-toolkit | framework | **True** | $0.2148 (33.8s) | **True** | 302,427 (62.1s) | **True** |

**Pack-level result: `behavior_equivalent = True`, 4/4 jobs agree**
(`cross_harness.py`'s own printed summary, reproduced verbatim above from
its audit JSON, not hand-transcribed).

**Reading the two "False" cells correctly (job-2, both harnesses):** this
is the EXPECTED, CORRECT outcome at `+framework`, not a defect either
harness's own report should be read as — §2.3 pre-registered that job-2's
correct answer is unreachable at this rung (both harnesses materialize an
EMPTY `CC_KNOWLEDGE_REPO`), so both harnesses honestly failing it is
itself an agreement, exactly as behavior-equivalence is defined (§2.4:
`claude_result == codex_result`, not `both True`). No `protected_files`
violation and no acceptance-check error occurred on either side for any
of the 8 cells (`config_warnings: []` on all 8, `call_status: "ok"` on
all 8) — every divergence-or-agreement result reflects the model's actual
work product, not a harness malfunction.

**Cost, real, not projected:** Claude side **$0.7781 total** (8× under
the pre-registered $12 worst case; 908,473 total tokens across 4 calls).
Codex side **994,643 total tokens** across 4 calls — no USD figure exists
(§1's billing-model caveat: ChatGPT-subscription auth, no metered API
key, no `--max-budget-usd` equivalent). No cell approached the 600s
timeout (longest: Codex job-4-toolkit, 62.1s).

**What this proves, precisely, and no more:** at the `+framework` rung,
for these 4 jobs, on this run (reps=1 — a second rep was not run; a single
divergent rep in a future re-run would be a real finding, not something
this result rules out), Claude's and Codex's single-shot, non-delegating
harnesses reach the SAME mechanical PASS/FAIL outcome under the SAME
acceptance check. It does not show (and this memo does not claim) that
the two harnesses' deliverables are qualitatively equivalent, that
multi-agent delegation behaves equivalently (§2.2 — neither harness's
headless mode delegates at all), or that this holds at any other rung.

## 5. PROPOSED PATCH to `claims.yaml` (t6) — NOT applied by this memo

`claims.yaml` is off-limits to this session (a concurrent register-patch
pass may be in flight — see TASK-146's own instructions). The exact patch,
for the next serialized register-patch pass:

```yaml
- id: t6-two-harnesses-one-behavior
  statement: "Claude/Codex parity is checked at content and behavior level; drift is bounded and alarmed — 'same solution, different harness' is a tested property, not a slogan."
  definition_refs: [parity, two_harness_behavior_equivalence]   # NEW definition ref added
  check: "cd /Users/pabs/Sites/COPILOT/codex-copilot && python3 scripts/check-upstream-parity.py --content --json (content level); cd copilot-control-tower/tools/cse-bench/benches/ladder && python3 cross_harness.py (behavior level, +framework rung, 4-job pack, see phase-4-cross-harness-behavior.md for the pre-registered equivalence definition)"
  status: passing   # was: failing
  evidence: >-
    RE-RUN 2026-07-14 (TASK-146, this task): BOTH levels now hold.
    Content: check-upstream-parity.py --content --json reports
    status: pass, 68 files, 0 drift (codex-copilot commit 7f7d6f6, which
    also lands Task 3's --update-baseline port guard -- see below).
    Behavior (NEW this task -- no check existed before it):
    cross_harness.py ran the SAME 4-job job_pack.py v2 pack through BOTH
    harnesses at the +framework rung (Claude: configs.materialize_framework,
    reused verbatim; Codex: codex_harness.py, new, AGENTS.md-equivalent
    materialization) and found ALL 4 jobs behavior-equivalent
    (claude_t_working == codex_t_working per job, the V-2 pre-registered
    definition in phase-4-cross-harness-behavior.md Sec 2.4, committed
    BEFORE this run): job-1-bugfix True/True, job-2-house-voice
    False/False (EXPECTED at this rung -- both harnesses materialize an
    empty CC_KNOWLEDGE_REPO, so both correctly cannot reach the org fact;
    an agreement, per the definition, not a defect), job-3-integration-report
    True/True, job-4-toolkit True/True. Real, not simulated: Claude cost
    $0.7781 total (8 live calls' worth across the two harnesses,
    908,473 tokens); Codex 994,643 total tokens (no USD figure exists --
    ChatGPT-subscription auth, no metered key, stated honestly rather than
    fabricated). EXPLICITLY NOT TESTED, stated so this claim can never be
    read as covering more than it does: t_loveable/MLP-rubric equivalence;
    multi-agent delegation equivalence (neither harness's headless mode
    delegates -- the ladder's own separately-documented 0-Task-tool-calls-
    across-72-cells finding applies to both harnesses' non-interactive
    modes, not just Claude's); equivalence at bare/+knowledge/+integrations
    rungs; byte-level deliverable equivalence. Also landed this task (Task
    3, the trust-based-baseline defect): codex-copilot's
    --update-baseline could previously "resolve" real upstream drift with
    zero verification that the corresponding port had landed; a port
    guard (codex-copilot commit 7f7d6f6) now refuses the update unless
    codex-copilot's own working tree has a live uncommitted change outside
    parity/, or the caller explicitly attests nothing needed porting --
    proven firing in a scratch clone (refuse-then-succeed-then-attest, all
    3 paths), 2 new regression tests, 38/38 tests pass.
  source: "tools/cse-bench/benches/ladder/cross_harness.py; codex_harness.py; phase-4-cross-harness-behavior.md; tools/cse-bench/output/cross_harness-runs/20260714T155309Z/*.json (raw envelopes); codex-copilot commit 7f7d6f6"
  last_checked: "2026-07-14"
```

**One new `definitions:` entry is also proposed** (referenced by
`definition_refs` above), `two_harness_behavior_equivalence`, whose text
is §2 of this memo verbatim (description + levels: the criterion, the
named instrument limitation, what is/isn't tested) — not re-typed here to
avoid the two copies drifting; the register-patch pass should copy §2's
prose (or reference this file by path, matching how `ladder_job_pack_v2`
already references its own design doc) rather than re-summarizing it.

**No number in §4 was quoted before this file's §1–§3 were committed**
(commit `36721e3`, prior to any `cross_harness.py` file existing).

## 6. CORRECTION (2026-07-14, appended, not rewriting §1/§4 above)

§1's billing-model caveat asserted Claude "does have a native
`--max-budget-usd` and a metered API key" — the first half is true, the
second is not on this machine. `configs.py`'s `_seed_home_for_auth()`
seeds every isolated ladder/cross-harness `HOME` with the owner's real
credentials (symlinked `~/Library/Keychains` + copied `~/.claude.json`),
so every `claude -p` cell in §4 authenticated under the owner's Claude
Code **subscription**, exactly like his interactive sessions — never a
separate metered key. Every dollar figure in §4 (Claude side: $0.7781,
per-job $0.1547/$0.2553/$0.1534/$0.2148) is Claude Code's own computed
**list-price-equivalent** (`total_cost_usd`, the figure a metered account
would have been charged for the same token volume), not an amount
actually billed to anyone. The Codex side's own framing in §1
("Codex is authenticated via a ChatGPT subscription... not a metered
Anthropic-style API key... no dollar figure for Codex") was already
correct and did not need this correction — only the Claude-side
"metered API key" clause did. Token counts in §4 (908,473 total on the
Claude side, 994,643 on the Codex side) are unaffected and remain the
primary, unambiguous figures; see
`docs/40-initiatives/01-cse-auditability/claims.yaml`'s
`ladder_config_materialization.cost_accounting_convention` for the
standing rule this correction establishes for every future run.
