"""codex_harness.py -- the Codex-side of the cross-harness behavior check
(t6-two-harnesses-one-behavior). See
../../../../docs/40-initiatives/01-cse-auditability/phases/
phase-4-cross-harness-behavior.md for the pre-registered equivalence
definition (V-2, committed BEFORE any cell in this bench ran).

This module materializes codex-copilot's own root `AGENTS.md` as the
Codex-side "+framework" equivalent of the Claude ladder's `+framework` rung
(see that memo Sec 2.1 for why AGENTS.md, not a per-project agents/skills
copy, is the fair, honest comparison point -- codex-copilot's own parity
contract documents that the per-agent roster is mirrored via the plugin
marketplace install, not per-project files, so there is no 1:1 file set to
replicate into an isolated job workdir the way configs.py's
_copy_framework_files() does for Claude) and invokes `codex exec`
non-interactively against the SAME job brief and the SAME
job_pack.py acceptance_check the Claude harness uses.

ISOLATION (verified live, 2026-07-14, BEFORE writing this file -- not
assumed): this machine already has codex-copilot's own plugin registered
GLOBALLY for every project via `~/.codex/config.toml`'s
`[plugins."codex-copilot@codex-copilot-local"]` entry -- an exact
Codex-side analogue of configs.py's own documented finding that
claude-copilot is already installed at the user level on this machine
(`~/.claude/agents/`, `~/.local/bin/{tc,cc}`). Three flags close that
leakage path, each verified with a real `codex exec` call before being
relied on here (not merely read from --help):
  --ignore-user-config    Skips `$CODEX_HOME/config.toml` entirely (per
                           `codex exec --help`: "auth still uses
                           CODEX_HOME"). Verified live: a workdir containing
                           only an AGENTS.md with a synthetic "magic word"
                           was correctly discovered and followed with this
                           flag set, while the globally-registered
                           codex-copilot plugin/marketplace/project list
                           from config.toml is excluded.
  --ephemeral              No session/rollout persistence -- avoids
                           contaminating `~/.codex`'s real history/session
                           corpus with synthetic bench calls, the Codex-side
                           analogue of the ladder's own isolated-HOME
                           transcript-hygiene rationale (configs.py module
                           docstring, "a welcome side effect").
  -C <workdir>             Scopes the agent's working root to the isolated
                           job workdir (never this repo, never a real
                           project).
Additionally: --skip-git-repo-check (the isolated job workdir is never a
git repo) and --sandbox workspace-write (file writes scoped to -C's root,
verified live with a real file-creation smoke test -- no interactive
approval was required, no bypass flag was needed).

No isolated CODEX_HOME copy/symlink dance is needed here (unlike Claude's
configs.py::_seed_home_for_auth()): auth.json is read ONLY (never written)
from the real, default CODEX_HOME, and --ignore-user-config already
removes the actual leakage surface -- verified live rather than assumed,
per this repo's own "check the real installed CLI before trusting a flag's
--help description" rule.

Stdlib only, matching every other file in this bench (no PyYAML
importable on this machine -- see job_pack.py's own docstring).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

SCRIPT_DIR = Path(__file__).resolve().parent  # .../tools/cse-bench/benches/ladder
BENCH_ROOT = SCRIPT_DIR.parent.parent  # .../tools/cse-bench
REPO_ROOT = BENCH_ROOT.parent.parent  # copilot-control-tower

COPILOT_ROOT = Path(os.environ.get("COPILOT_ROOT", "/Users/pabs/Sites/COPILOT"))
CODEX_COPILOT_ROOT = Path(os.environ.get("CODEX_COPILOT_ROOT", str(COPILOT_ROOT / "codex-copilot")))

CODEX_BIN = "codex"


@dataclass
class CodexConfig:
    name: str
    workdir: Path
    env: dict
    notes: list = field(default_factory=list)
    warnings: list = field(default_factory=list)

    def env_summary(self) -> dict:
        return {
            "CC_KNOWLEDGE_REPO": self.env.get("CC_KNOWLEDGE_REPO"),
            "workdir": str(self.workdir),
        }


def materialize_codex_framework(run_root: Path, job_id: str, rep: int = 1) -> CodexConfig:
    """The Codex-side equivalent of configs.materialize_framework(). See
    module docstring Sec-by-sec for why AGENTS.md alone (codex-copilot's
    own, verbatim) is the fair comparison point, and why no isolated
    CODEX_HOME is required."""
    workdir = run_root / "codex-jobs" / job_id / "framework" / f"rep{rep}"
    workdir.mkdir(parents=True, exist_ok=True)
    warnings: list = []

    agents_md = CODEX_COPILOT_ROOT / "AGENTS.md"
    if agents_md.is_file():
        shutil.copy2(agents_md, workdir / "AGENTS.md")
    else:
        warnings.append(f"CODEX_COPILOT_ROOT/AGENTS.md not found at {agents_md}; Codex framework materialization skipped")

    # Same isolation intent as the Claude side's +framework rung: an EMPTY
    # knowledge tree (not unset), and no cli-copilot `copilot` entry point
    # on PATH -- this is the framework rung, never +integrations.
    empty_knowledge = run_root / "empty-knowledge-tree"
    empty_knowledge.mkdir(parents=True, exist_ok=True)

    env = dict(os.environ)
    env["CC_KNOWLEDGE_REPO"] = str(empty_knowledge)

    return CodexConfig(
        name="framework",
        workdir=workdir,
        env=env,
        notes=[
            "AGENTS.md materialized from codex-copilot's own repo root (verbatim, the file real users get)",
            f"CC_KNOWLEDGE_REPO points at an EMPTY tree ({empty_knowledge}), matching the Claude side's +framework rung",
            "no per-project .claude/agents-equivalent materialized -- codex-copilot's parity contract mirrors that "
            "roster via the plugin marketplace install, not per-project files (see module docstring)",
        ],
        warnings=warnings,
    )


def build_codex_command(brief: str, workdir: Path, model: Optional[str]) -> list:
    cmd = [
        CODEX_BIN,
        "exec",
        "--ignore-user-config",
        "--ephemeral",
        "-C",
        str(workdir),
        "--skip-git-repo-check",
        "--sandbox",
        "workspace-write",
        "--json",
    ]
    if model:
        cmd += ["-m", model]
    cmd.append(brief)
    return cmd


def run_codex_job(brief: str, workdir: Path, env: dict, timeout: int, model: Optional[str] = None) -> dict:
    """Codex-side equivalent of run.py's run_claude_job(). Returns the same
    shape (status/text/error/duration_seconds/envelope/stderr_tail) so the
    cross-harness comparator can treat both harnesses uniformly; `envelope`
    here is a synthesized {"events": [...], "usage": {...}} built from the
    JSONL event stream (`codex exec --json` prints one JSON object per
    line: thread.started, turn.started, item.* , turn.completed) rather
    than a single JSON blob the way `claude -p --output-format json`
    returns -- codex exec has no single-envelope output mode (verified via
    `codex exec --help`), so this function does the reassembly."""
    command = build_codex_command(brief, workdir, model)
    start = time.monotonic()
    try:
        result = subprocess.run(
            command,
            cwd=str(workdir),
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        return {
            "status": "timeout",
            "text": "",
            "error": f"timed out after {timeout}s",
            "duration_seconds": round(time.monotonic() - start, 2),
            "envelope": None,
            "stderr_tail": (exc.stderr or "")[-2000:] if isinstance(exc.stderr, str) else "",
        }
    except OSError as exc:
        return {
            "status": "error",
            "text": "",
            "error": f"failed to start {command[0]}: {exc}",
            "duration_seconds": round(time.monotonic() - start, 2),
            "envelope": None,
            "stderr_tail": "",
        }

    duration = round(time.monotonic() - start, 2)

    events = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue  # a non-JSON stray line (should not happen with --json) -- skip, don't crash the harness

    if result.returncode != 0 and not events:
        return {
            "status": "error",
            "text": "",
            "error": f"{command[0]} exited {result.returncode}: {result.stderr.strip()[:500]}",
            "duration_seconds": duration,
            "envelope": None,
            "stderr_tail": result.stderr[-2000:],
        }

    final_text = ""
    for event in events:
        if event.get("type") == "item.completed" and event.get("item", {}).get("type") == "agent_message":
            final_text = event["item"].get("text", "")

    usage_totals = {"input_tokens": 0, "cached_input_tokens": 0, "output_tokens": 0, "reasoning_output_tokens": 0}
    turn_count = 0
    for event in events:
        if event.get("type") == "turn.completed":
            turn_count += 1
            usage = event.get("usage") or {}
            for key in usage_totals:
                usage_totals[key] += usage.get(key) or 0

    envelope = {"events": events, "usage": usage_totals, "num_turns": turn_count, "final_text": final_text}

    return {
        "status": "ok" if result.returncode == 0 else "error",
        "text": final_text,
        "error": None if result.returncode == 0 else f"exited {result.returncode}",
        "duration_seconds": duration,
        "envelope": envelope,
        "stderr_tail": result.stderr[-2000:] if result.stderr else "",
    }


def extract_codex_usage(envelope: Optional[dict]) -> dict:
    """Codex-side equivalent of run.py's extract_usage(). Codex's own
    `turn.completed` usage block already reports `input_tokens` as
    NEW-input-only (cache reads are reported separately as
    `cached_input_tokens`, not folded in) -- verified live against a real
    call's JSON (see phase-4-cross-harness-behavior.md Sec 1's smoke-test
    quote). This mirrors run.py's extract_usage() field names as closely as
    the two providers' actual schemas allow so a human comparing the two
    result rows doesn't have to remember two different vocabularies, but
    does NOT claim marginal_spend/billed_volume are commensurable in
    dollar terms across providers -- no USD figure exists on the Codex
    side at all (see phase-4-cross-harness-behavior.md Sec 1's billing-model
    caveat)."""
    if not envelope:
        return {
            "input_tokens_new": None,
            "cached_input_tokens": None,
            "output_tokens": None,
            "reasoning_output_tokens": None,
            "total_tokens": None,
            "num_turns": None,
        }
    usage = envelope.get("usage") or {}
    input_new = usage.get("input_tokens") or 0
    cached = usage.get("cached_input_tokens") or 0
    output = usage.get("output_tokens") or 0
    reasoning = usage.get("reasoning_output_tokens") or 0
    return {
        "input_tokens_new": input_new,
        "cached_input_tokens": cached,
        "output_tokens": output,
        "reasoning_output_tokens": reasoning,
        "total_tokens": input_new + cached + output + reasoning,
        "num_turns": envelope.get("num_turns"),
    }
