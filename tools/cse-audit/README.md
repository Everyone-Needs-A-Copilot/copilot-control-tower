# delegation-rate falsification probe

Reusable tool to test claude-copilot's April-2026-restructure claims
("hooks closed the 94%/6% delegation-rate gap") against real session
transcripts. Built as a falsification probe, not a validation — see the
calling agent's final report for the verdict.

## Run it

```bash
python3 run_probe.py \
  --projects-dir ~/.claude/projects \
  --stats-cache ~/.claude/stats-cache.json \
  --out ./output
```

Prints a 9-section console report and writes `output/session_metrics.csv`
(one row per session, all raw + derived metrics) and
`output/framework_registry.json` (per-project framework/hook install status).

## Files

- `jsonl_utils.py` — streaming line-by-line JSONL parsing + the
  `is_real_user_turn`, `model_family`, `first_text_block`, `tool_use_blocks`
  primitives. No file is ever loaded whole into memory.
- `session_metrics.py` — `compute_session_metrics(path)` walks one main
  session file plus its sibling `subagents/agent-*.jsonl` files and returns
  a `SessionMetrics` with delegation rate (two definitions), protocol-
  declaration rate (two definitions), turns, token totals, model mix.
- `framework_registry.py` — inspects a project's *current* `.claude/`
  directory to classify it as hooks-active / agents-only / no-framework.
  Snapshot of today's filesystem, not a historical record — see docstring.
- `corpus_scan.py` — standalone CSV/JSON dump of the corpus (used by
  `run_probe.py`, also runnable on its own).
- `stats_cache_analysis.py` — parses `~/.claude/stats-cache.json`, the only
  local artifact that spans the pre/post hook-ship boundary (raw JSONL
  transcripts on this machine do not go back that far).
- `run_probe.py` — orchestrates everything, prints the report.

## Key operational definitions (see final report for full rationale)

- **Turn** = a `type: "user"` record with `isSidechain != true`, `isMeta !=
  true`, and content that is not purely a `tool_result` echo. Reverse-
  engineered to match what fires Claude Code's `UserPromptSubmit` hook
  (`.claude/hooks/user-prompt-submit.sh` in claude-copilot).
- **Delegation rate (primary)** = subagent-executed tool calls / (main +
  subagent tool calls) for a session. Ground truth for "which context
  executed this tool call" is the corpus's own file layout: subagent
  invocations are written to sibling `<sessionId>/subagents/agent-*.jsonl`
  files, distinct from the main `<sessionId>.jsonl`.
- **Protocol declaration** = an assistant message whose first `text`-type
  content block (skipping `thinking` blocks) starts with `[PROTOCOL`.
- **Framework-installed** = `.claude/agents/` exists at or above the
  session's recorded `cwd`. **Mechanical-hooks-active** = that project's
  `.claude/settings.json` registers `PreToolUse -> pretool-check.sh`.
  These are DIFFERENT things — see report section 8 for how much they
  diverge in this corpus.

## Known limitation baked into every number here

The raw JSONL corpus on this machine starts 2026-06-09 — 48 days after the
2026-04-22 hook-ship date (confirmed via `git log` in claude-copilot). There
are no pre-intervention transcripts to recompute the April diagnostic's 6%
delegation-rate / 3.5% protocol-rate baseline against. Every delegation-rate
and protocol-rate number this tool produces from raw transcripts describes
the POST-hook period only.
