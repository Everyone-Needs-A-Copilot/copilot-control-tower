# resume_cost — S-1 resume-cost bench (TASK-107)

Measures the CSE development framework's CORE job, stated directly in
claude-copilot's `SOUL.md` §1: "keep decisions, process, and context from
evaporating every time a session ends — without burning their token budget
rebuilding it." Success signal (also `SOUL.md` §1): "/continue picked up
exactly where I left off — no re-explaining."

This is a direct measurement, not a proxy: does the state the framework
persists (a Task Copilot task record + Memory Copilot entries) actually
change whether a resumed session gets the right answer, and at what token
cost?

## Design

**Fixture** (`fixture/`, committed): `invoice_tools/`, a 3-file Python
utility (`main.py`, `utils.py`, `validators.py`) frozen mid-refactor. Step
1 of a 3-step plan is done (validation logic extracted from `utils.py`
into a new `validators.py`, with a real bug fix along the way — the old
code mutated rows in place); step 2 (extracting `aggregate_totals()` /
`dedupe_invoices()` into a new `transformers.py`) is next. The fixture
files are realistic but deliberately do NOT narrate the refactor plan in
comments (see "Design decisions" below for why that matters) — they show
what step 1 produced, not what step 2 will be called.

**Two prompt-context arms**, both closed-book, both a single `claude -p`
call:

- **without** — the bare prompt, no injected state, empty cwd.
- **with** — `fixture/state_block.txt` prepended to the same prompt.
  `state_block.txt` is REAL captured CLI output, not invented prose:
  `tc progress` (exactly what `.claude/commands/continue.md`'s "Load
  Context (Slim)" step runs) plus three `cc memory list --type <T> --json`
  entries (`context`, `decision`, `lesson`) written in the same
  `"Focus: <what>. Next: TASK-xxx — <next step>"` format `continue.md`'s
  "End of Session" section specifies. `build_state.sh` regenerates it from
  a throwaway `tc init` + `cc memory store` instance in an isolated temp
  git repo (never touches this repo's or `~/.claude`'s real stores — see
  that script's header for the isolation mechanism). Re-run it with
  `./build_state.sh`.

**Prompt** (both arms, from the task brief, verbatim except for one
addition — see "Design decisions"):

> You are resuming work on this project after a break. State: (a) what
> the current task is, (b) what was already completed, (c) the next
> concrete action. Be specific. No tools.

**Run**: `claude -p <prompt> --model sonnet --output-format json`, 3
repetitions per arm (6 calls total). The JSON envelope's `usage` block
carries token counts; `result` carries the answer text. See "Probe call"
below for the exact fields.

**Scoring** (deterministic): three ground-truth elements per response —
does the normalized text (lowercase, strip non-alphanumeric, collapse
whitespace) contain a variant naming (a) the task (`invoice_tools`), (b)
the completed step (`validators.py` / `validate_invoice_row` /
`normalize_currency`), (c) the next action (`transformers.py` /
`aggregate_totals` / `dedupe_invoices`). Every variant is a real
identifier that exists in the fixture or the captured state block, not an
invented rubric.

**Cost**: `input_tokens_total = usage.input_tokens +
cache_creation_input_tokens + cache_read_input_tokens` (all three are
real tokens the API processed — `usage.input_tokens` alone undercounts,
see "Probe call"), plus `output_tokens`, `total_cost_usd`, `duration_ms`,
`num_turns`. The state block's own size (`state_block_chars` /
`state_block_tokens_est`, a rough `len/4` heuristic) is reported
separately for transparency, but it is not a second cost to add — it's
already inside the with-arm's own `input_tokens_total` because it's
literally prepended to that arm's prompt.

## Probe call — verifying the envelope's field names first

Before writing the harness, a manual probe (`claude -p "What is 2+2?
Answer in one word." --model sonnet --output-format json`) confirmed the
JSON envelope's shape:

```json
{
  "result": "4",
  "usage": {
    "input_tokens": 2,
    "cache_creation_input_tokens": 12849,
    "cache_read_input_tokens": 23288,
    "output_tokens": 3
  },
  "total_cost_usd": 0.0841314,
  "duration_ms": 2033,
  "num_turns": 1
}
```

`usage.input_tokens` is only the NEW (uncached) input for that call — the
bulk of a call's real input volume, even for "what is 2+2," is cache
creation/read (system prompt, tool schemas, global skills). Reporting
`usage.input_tokens` alone would make every call look nearly free and
hide the real token volume; `input_tokens_total` (input + cache_creation +
cache_read) is the honest figure this bench reports.

## Design decisions (and two things the first live run got wrong)

This bench went through two rounds of empirical correction — recorded
here rather than silently fixed, per the "trace to the consumer, existing
data is the contract" discipline: a plausible-sounding design was run
live, produced a result that didn't hold up, and was fixed based on what
the transcript actually showed.

**1. Fixture files must not narrate the refactor plan in comments.** The
first draft of `utils.py`/`validators.py` had `TODO(step 2): move to
transformers.py`-style comments and a docstring literally titled "Step 1
(DONE) / Step 2 (NEXT) / Step 3 (LATER)". A live without-arm run (cwd = a
copy of the fixture's `.py` files, tools allowed) scored a perfect 3/3
with ZERO injected state, and said so explicitly: *"the code itself
documents the plan explicitly."* The ablation was measuring "can Claude
read three short files," not "does persisted state matter." Fixed by
rewriting the fixture files to show only what step 1 produced (a real,
readable diff) without narrating what comes next — completed work is
naturally visible in code; the plan for what's next is not, which is the
actual, honest distinction between "what git shows you" and "what Task
Copilot / Memory Copilot remembers for you."

**2. Both arms need an EMPTY cwd, and the prompt needs "No tools."** Even
with the fixture-comment fix above, a second live run (empty cwd, tools
still allowed, no "No tools" instruction) showed the WITH arm spending 9
turns / 133 seconds / ~206K tokens searching the filesystem — and finding
the REAL, committed `fixture/invoice_tools/` this bench ships, because the
state block named real identifiers (`invoice_tools`, `utils.py`) and this
is a real development machine where that fixture really exists on disk at
a discoverable path. An empty cwd alone doesn't stop a tool-enabled model
from reaching a file that exists somewhere else on the same host.
`../knowledge_qa/run.py` had already solved exactly this problem for its
own empty-cwd ablation with an explicit `"No tools."` clause in its
prompt template; this bench adopts the same fix (appended to the brief's
literal prompt text, which did not otherwise include it) and keeps a
uniformly empty cwd for both arms. This also makes the bench fast and
low-variance enough for "3 repetitions for stability" to mean something —
closed-book single inference per call (`num_turns: 1` for every one of
the 6 live-run calls below), not an open-ended, highly variable
filesystem hunt.

Both fixes are visible in `run.py`'s module docstring and inline comments
at the exact points they apply, not just here.

## Results — 2026-07-13 live run

Model: `sonnet`. 3 reps/arm, 6 calls, all `status: ok`, zero errors,
`num_turns: 1` for every call. Full envelope:
[`../../output/bench_resume_cost-latest.json`](../../output/bench_resume_cost-latest.json).
Raw per-call responses (prompt char count, full JSON envelope, scored
verdict) in `../../output/bench_resume_cost-runs/20260713T001935Z/`.

| Arm | Correctness (elements) | Full match (3/3) | Mean total tokens | Mean cost (USD) | Mean duration |
|-----|------------------------|-------------------|--------------------|-------------------|----------------|
| **without** (no state, empty cwd, no tools) | **0%** (0/9 element-hits across 3 reps) | 0/3 reps | 36,292 | $0.09 | 12.4s |
| **with** (state block prepended) | **100%** (9/9) | 3/3 reps | 37,721 | $0.10 | 9.7s |

**Headline: correctness delta = +1.00 (0% → 100%), for a token overhead of
+1,429 tokens (+3.9%) and +$0.01 mean cost per call.** The injected state
block itself is 2,617 characters (~654 tokens, `state_block_tokens_est`);
that's the entire marginal cost of "picking up exactly where I left off"
in this fixture — a rounding error next to the ~36K-token constant
overhead every `claude -p` call carries regardless of arm (system prompt,
tool schemas, global skills — see "Probe call" above), and negligible
next to the correctness swing it buys.

**The without-arm did not "burn tokens being wrong" here** — with "No
tools" and an empty cwd, there is nothing to explore, so it answered
directly and honestly (typical response: *"I don't actually have any
prior context to resume from... Current task: Unknown... I need you to
tell me what task we were resuming"*) rather than hallucinating or
padding. That is itself a finding worth stating plainly: this fixture's
without-arm cost is dominated by the correctness loss (0%), not by
token/turn waste — the "burns token budget rebuilding it" half of the
SOUL claim is real (see Limits below, and Design decisions #2's 9-turn/
206K-token/133s run, which is exactly that cost, just excluded from the
final measurement by the "No tools" fix that made the *scoring* clean).
A follow-on bench that explicitly allows tools on an empty-but-writable
cwd (so a resuming agent can actually reconstruct state by working, not
just searching for the real fixture on the host) would isolate that
second cost honestly; this bench does not attempt it.

## Limits (stated honestly)

- **Synthetic fixture.** `invoice_tools` is a small, hand-authored 3-file
  project chosen to be realistic but is not a real in-flight task from
  this ecosystem. Ground truth is unambiguous by construction, which
  makes the bench's contains-check scoring possible but also makes the
  task easier than a messier real one.
- **Single-turn, closed-book probe — not a full session.** `"No tools"`
  and a single `claude -p` call test whether the injected text changes
  the answer; they do not test a full `/continue` session (interactive,
  tool-using, multi-turn, potentially resuming a real repo). The
  contamination risks documented in "Design decisions" are evidence this
  simplification was necessary for a clean signal on this machine, not
  free of cost — a full-session variant would need a different isolation
  strategy (e.g., a sandboxed filesystem with no real fixture reachable
  outside cwd) to stay valid.
- **One fixture, one scenario.** 3 reps/arm establishes this fixture is
  not a fluke (0/3 vs 3/3, not 1/3 vs 2/3), not that the effect
  generalizes across task types, refactor sizes, or longer-elapsed
  "forgetting."
- **Single-author measurement**, same caveat every `cse-bench` collector
  and bench in this program carries (see `../../README.md` and the
  claims register's permanent Trust-panel banner).

## Re-run it

```bash
cd tools/cse-bench/benches/resume_cost

# Regenerate fixture/state_block.txt from real tc/cc CLI output
# (isolated in a throwaway temp git repo — see build_state.sh's header)
./build_state.sh

# Full bench: both arms, 3 reps each = 6 claude -p calls
python3 run.py

# Fewer/more reps, one arm only, preview prompts without spending calls
python3 run.py --reps 5
python3 run.py --arm without --reps 1
python3 run.py --dry-run

# Different model / concurrency / timeout
python3 run.py --model sonnet --concurrency 2 --timeout 240
```

Requires the `claude` CLI on `PATH`, and `tc`/`cc` on `PATH` for
`build_state.sh` (not needed for `run.py` itself — `state_block.txt` is
committed, already generated).
