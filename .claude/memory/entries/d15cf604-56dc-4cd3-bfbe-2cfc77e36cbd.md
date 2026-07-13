---
id: d15cf604-56dc-4cd3-bfbe-2cfc77e36cbd
type: decision
tags: []
created: 2026-07-12T17:55:50Z
updated: 2026-07-12T17:55:50Z
scope: project
---

cse-bench evals collector (TASK-95/B-12 groundwork): runs cc eval --agent <agent> --json (LocalPythonRunner, pure-Python deterministic assertions, no LLM/network) for every subdir of <claude-copilot>/.claude/evals/ with *.yaml cases, discovered dynamically not hardcoded. agents_total counted from <claude-copilot>/.claude/agents/*.md (=16). Real run 2026-07-12: qa 10/10 cases pass, pass_rate=1.0, coverage_ratio=1/16=0.0625. cc resolved via absolute path candidates (~/.local/bin/cc, /opt/homebrew/bin/cc), never bare 'cc' (PATH collision with C compiler on this machine).
