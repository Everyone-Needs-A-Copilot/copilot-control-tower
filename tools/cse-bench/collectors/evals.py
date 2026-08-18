"""collectors/evals.py — cc eval golden-set coverage collector.

Runs `cc eval --agent <agent> --json` (claude-copilot's tools/cc) for every
agent that has a golden set under
<claude-copilot>/.claude/evals/<agent>/*.yaml, and reports each agent's
pass-rate alongside the ecosystem's total agent count (from
<claude-copilot>/.claude/agents/*.md), so a coverage ratio like "1 of 16
agents have evals" is a MEASURED number, not a quoted one.

Serves PRD-9 (CSE Verification & Benchmark Program), TASK-95/B-12
groundwork + TASK-91 (B-8) Efficacy-panel follow-through, and the T3
program truth condition ("every specialist agent has a passing golden-set
eval" — phase-2-prd.md). This is the instruction layer's only
rubric-scored quality metric today.

Design notes
------------
- The eval runner itself (claude-copilot's tools/cc/src/cc/core/
  eval_runner.py, LocalPythonRunner) is a pure-Python deterministic
  assertion engine — no LLM call, no network, no Node.js dependency.
  Running it here is always a real, complete suite run, not a mock or a
  replay.
- `cc eval --agent X --json` exits 1 when pass_rate < threshold OR a P0
  case regresses, but STILL prints a complete JSON result on stdout in
  that case — a non-zero return code is therefore not itself treated as
  a collector error; only a missing/unparseable stdout is.
- Which agents to run is discovered from the evals directory itself
  (mirrors `cc eval --list-agents`'s own directory scan), never
  hardcoded — a future agent gaining a golden set is picked up on the
  next collect() with no code change here.
- `cc` missing/unreachable, or claude-copilot's evals/agents directories
  missing, degrade to a per-item entry in ``errors`` and null/partial
  metrics fields — never a crash (same contract as every other collector
  in this package, e.g. collectors/parity.py, collectors/integrations.py).
"""
from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from collectors.paths import resolve_cse_root

COLLECTOR_NAME = "evals"

CLAUDE_ROOT = resolve_cse_root() / "claude-copilot"
AGENTS_DIR = CLAUDE_ROOT / ".claude" / "agents"
EVALS_DIR = CLAUDE_ROOT / ".claude" / "evals"

# ~/.local/bin/cc is claude-copilot's own tool entry point; /opt/homebrew/bin/cc
# is the machine-wide mirror. Both are absolute paths, deliberately not a bare
# `cc` PATH lookup (this machine's `cc` name collides with the C compiler in
# some shells/build contexts — see the repo's own cc-name-collision note).
CC_BIN_CANDIDATES = [
    str(Path.home() / ".local" / "bin" / "cc"),
    "/opt/homebrew/bin/cc",
]

_EVAL_TIMEOUT_SECONDS = 60


def _resolve_cc_bin(errors: list[dict]) -> Optional[str]:
    for candidate in CC_BIN_CANDIDATES:
        if Path(candidate).exists():
            return candidate
    errors.append(
        {
            "item": "cc_binary",
            "error": f"cc binary not found at any of {CC_BIN_CANDIDATES}",
        }
    )
    return None


def _discover_agents_total(errors: list[dict]) -> Optional[int]:
    if not AGENTS_DIR.exists():
        errors.append({"item": "agents_total", "path": str(AGENTS_DIR), "error": "directory not found"})
        return None
    return len(list(AGENTS_DIR.glob("*.md")))


def _discover_agents_with_evals(errors: list[dict]) -> list[str]:
    if not EVALS_DIR.exists():
        errors.append({"item": "agents_with_evals", "path": str(EVALS_DIR), "error": "directory not found"})
        return []
    return sorted(d.name for d in EVALS_DIR.iterdir() if d.is_dir() and list(d.glob("*.yaml")))


def _run_agent_eval(cc_bin: str, agent: str, errors: list[dict]) -> Optional[dict]:
    """Run `cc eval --agent <agent> --json` from claude-copilot's repo root
    (cc's own repo-root resolution walks up from cwd looking for .git, so
    cwd must be inside that repo). Returns the parsed result dict, or None
    on any failure (which is also appended to errors) — never raises.
    """
    try:
        result = subprocess.run(
            [cc_bin, "eval", "--agent", agent, "--json"],
            cwd=CLAUDE_ROOT,
            capture_output=True,
            text=True,
            timeout=_EVAL_TIMEOUT_SECONDS,
        )
    except FileNotFoundError as exc:
        errors.append({"item": agent, "error": f"could not start {cc_bin!r}: {exc}"})
        return None
    except subprocess.TimeoutExpired as exc:
        errors.append({"item": agent, "error": f"timed out after {_EVAL_TIMEOUT_SECONDS}s: {exc}"})
        return None
    except OSError as exc:
        errors.append({"item": agent, "error": f"unexpected OSError: {exc}"})
        return None

    stdout = result.stdout.strip()
    if not stdout:
        errors.append(
            {
                "item": agent,
                "error": f"empty stdout (returncode={result.returncode}); stderr={result.stderr.strip()[:300]}",
            }
        )
        return None

    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        errors.append({"item": agent, "error": f"invalid JSON output: {exc}; stdout[:300]={stdout[:300]!r}"})
        return None


def collect() -> dict:
    """Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    agents_total = _discover_agents_total(errors)
    agents_with_evals = _discover_agents_with_evals(errors)
    cc_bin = _resolve_cc_bin(errors) if agents_with_evals else None

    per_agent: dict = {}
    for agent in agents_with_evals:
        if cc_bin is None:
            per_agent[agent] = {
                "cases": None,
                "passed": None,
                "failed": None,
                "pass_rate": None,
                "last_run": None,
                "error": "cc binary unavailable — see top-level errors",
            }
            continue

        result = _run_agent_eval(cc_bin, agent, errors)
        if result is None:
            per_agent[agent] = {
                "cases": None,
                "passed": None,
                "failed": None,
                "pass_rate": None,
                "last_run": None,
                "error": "eval run failed — see top-level errors",
            }
            continue

        per_agent[agent] = {
            "cases": result.get("total"),
            "passed": result.get("passed"),
            "failed": result.get("failed"),
            "pass_rate": result.get("pass_rate"),
            "p0_regression": result.get("p0_regression"),
            "threshold": result.get("threshold"),
            "overall_pass": result.get("overall_pass"),
            "last_run": now,
        }

    coverage_ratio = (len(agents_with_evals) / agents_total) if agents_total else None

    metrics = {
        "claude_copilot_root": str(CLAUDE_ROOT),
        "cc_binary": cc_bin,
        "agents_with_evals": agents_with_evals,
        "agents_total": agents_total,
        "coverage_ratio": coverage_ratio,
        "per_agent": per_agent,
        "definitions": {
            "agents_with_evals": "subdirectories of <claude-copilot>/.claude/evals/ that contain at least one *.yaml case file (mirrors `cc eval --list-agents`'s own scan)",
            "agents_total": "count of *.md files under <claude-copilot>/.claude/agents/ — the ecosystem's specialist-agent roster; null if that directory could not be read",
            "coverage_ratio": "len(agents_with_evals) / agents_total; null if agents_total could not be determined",
            "per_agent.cases/passed/failed/pass_rate/p0_regression/threshold/overall_pass": "verbatim fields from `cc eval --agent <agent> --json` (claude-copilot tools/cc/src/cc/core/eval_runner.py, LocalPythonRunner — pure-Python deterministic assertions: contains/not-contains/regex/regex-not; no LLM call, no network)",
            "per_agent.last_run": "UTC timestamp of THIS collector run (cc eval's own JSON output carries no timestamp field)",
        },
    }
    return {"metrics": metrics, "errors": errors}
