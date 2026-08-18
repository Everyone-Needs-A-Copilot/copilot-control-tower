"""collectors/parity.py — Codex parity collector.

Runs codex-copilot's own `scripts/check-upstream-parity.py --json` (the
version-tuple check it already ships) and reports the result verbatim.
Additionally probes whether that script has grown a content/hash-level
parity mode (`--help` advertising a `content`/`hash`-related flag) --
task C-4 is adding one in parallel, and this collector must produce a
correct, non-crashing result whether or not that flag has landed yet.
Also surfaces the version tuple codex-copilot's own check does NOT fully
cover: `claude-copilot/VERSION.json` versions its `agents` and `commands`
components independently of the overall `framework` version, but
`codex-copilot/parity/claude-baseline.json` records only a single
`frameworkVersion` -- so an agents/commands drift can go undetected by
the upstream script alone. This collector reports both sides so that gap
is visible in the raw data, not computed or judged here.

Serves PRD-9 (CSE Verification & Benchmark Program), task B-6.

Design notes
------------
- Every external call (subprocess or file read) is individually wrapped;
  a failure anywhere produces a per-item entry in the returned ``errors``
  list and a ``None``/``"available": false`` placeholder in ``metrics``
  rather than raising out of ``collect()`` (same contract as
  ``collectors/tasksdb.py`` and ``collectors/velocity.py``).
- The content/hash-mode probe is deliberately generic: it scans the
  script's own `--help` text for a line mentioning "content" or "hash"
  and extracts whatever `--flag` token appears on that line, rather than
  hardcoding a flag name C-4 hasn't landed yet. If no such line exists,
  `metrics.content_check` is `{"available": false}` and nothing else is
  attempted -- this is the expected, non-error state today.
"""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Optional

from collectors.paths import resolve_cse_root

COLLECTOR_NAME = "parity"

CODEX_ROOT = resolve_cse_root() / "codex-copilot"
CLAUDE_ROOT = resolve_cse_root() / "claude-copilot"
PARITY_SCRIPT = CODEX_ROOT / "scripts" / "check-upstream-parity.py"
BASELINE_JSON = CODEX_ROOT / "parity" / "claude-baseline.json"
CLAUDE_VERSION_JSON = CLAUDE_ROOT / "VERSION.json"

_SCRIPT_TIMEOUT_SECONDS = 30
_CONTENT_FLAG_RE = re.compile(r"(--[a-zA-Z][\w-]*)")


def _run_json(args: list[str], item: str, errors: list[dict]) -> Optional[dict]:
    """Run a subprocess expected to print a single JSON object to stdout.
    On any failure (missing binary, timeout, non-JSON output), append a
    per-item error entry and return None instead of raising.
    """
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=_SCRIPT_TIMEOUT_SECONDS)
    except FileNotFoundError as exc:
        errors.append({"item": item, "error": f"could not start {args[0]!r}: {exc}"})
        return None
    except subprocess.TimeoutExpired as exc:
        errors.append({"item": item, "error": f"timed out after {_SCRIPT_TIMEOUT_SECONDS}s: {exc}"})
        return None
    except OSError as exc:
        errors.append({"item": item, "error": f"unexpected OSError: {exc}"})
        return None

    stdout = result.stdout.strip()
    if not stdout:
        errors.append(
            {
                "item": item,
                "error": f"empty stdout (returncode={result.returncode}); stderr={result.stderr.strip()[:300]}",
            }
        )
        return None

    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        errors.append({"item": item, "error": f"invalid JSON output: {exc}"})
        return None


def _detect_content_flag(help_text: str) -> Optional[str]:
    """Scan --help output for the OPTIONS-LIST line (not the usage summary
    line, which packs multiple flags together and would return whichever
    flag happens to appear first on that shared line) that DEFINES a flag
    mentioning content/hash-level parity, and return that flag token, e.g.
    '--content-check'. This is deliberately not tied to a specific flag
    name since C-4 (adding the mode) is landing independently of this
    collector.

    BUGFIX (found while closing t6-two-harnesses-one-behavior, 2026-07-14):
    the original version searched EVERY line (including argparse's usage
    summary, which lists several flags on one wrapped line, e.g.
    '[--json] [--content] [--update-baseline]') and returned the first
    '--flag'-shaped token on the first matching line. Since '--update-
    baseline's own description also mentions "content" ("...content
    baseline manifest...") and the usage line lists '--json' before
    '--content', this silently resolved to '--json' -- re-running the
    version-only check instead of the content-hash check, and reporting a
    false 'pass' with no content field at all. Fixed by requiring the
    matched line to be an options-list DEFINITION line (starts with the
    flag itself, i.e. '  --content            Also run content-level...'),
    which argparse's --help always renders one-flag-per-definition-line.
    """
    for line in help_text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("--"):
            continue
        lowered = stripped.lower()
        if "content" not in lowered and "hash" not in lowered:
            continue
        match = _CONTENT_FLAG_RE.match(stripped)
        if match:
            return match.group(1)
    return None


def _probe_content_check(errors: list[dict]) -> dict:
    try:
        help_result = subprocess.run(
            ["python3", str(PARITY_SCRIPT), "--help"],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except FileNotFoundError as exc:
        errors.append({"item": "content_check_probe", "error": f"could not start python3: {exc}"})
        return {"available": False}
    except subprocess.TimeoutExpired as exc:
        errors.append({"item": "content_check_probe", "error": f"--help timed out: {exc}"})
        return {"available": False}

    flag = _detect_content_flag(help_result.stdout + help_result.stderr)
    if not flag:
        return {"available": False}

    parsed = _run_json(["python3", str(PARITY_SCRIPT), flag, "--json"], "content_check", errors)
    if parsed is None:
        return {"available": True, "flag": flag, "result": None}
    return {"available": True, "flag": flag, "result": parsed}


def _collect_versions(errors: list[dict]) -> dict:
    versions: dict = {"baseline": None, "claude_copilot": None}

    try:
        baseline = json.loads(BASELINE_JSON.read_text())
        b = baseline.get("baseline", {})
        versions["baseline"] = {
            "source": b.get("source"),
            "frameworkVersion": b.get("frameworkVersion"),
            "capturedDate": b.get("capturedDate"),
            "codexParityVersion": b.get("codexParityVersion"),
        }
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(
            {
                "item": "baseline_version",
                "path": str(BASELINE_JSON),
                "error": f"{type(exc).__name__}: {exc}",
            }
        )

    try:
        claude_version = json.loads(CLAUDE_VERSION_JSON.read_text())
        components = claude_version.get("components", {})
        versions["claude_copilot"] = {
            "framework": claude_version.get("framework"),
            "agents_version": components.get("agents", {}).get("version"),
            "commands_version": components.get("commands", {}).get("version"),
        }
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(
            {
                "item": "claude_copilot_version",
                "path": str(CLAUDE_VERSION_JSON),
                "error": f"{type(exc).__name__}: {exc}",
            }
        )

    return versions


def collect() -> dict:
    """Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []

    upstream_check = _run_json(["python3", str(PARITY_SCRIPT), "--json"], "upstream_check", errors)
    content_check = _probe_content_check(errors)
    versions = _collect_versions(errors)

    metrics = {
        "script": str(PARITY_SCRIPT),
        "upstream_check": upstream_check,
        "content_check": content_check,
        "versions": versions,
        "definitions": {
            "upstream_check": "verbatim result of `python3 scripts/check-upstream-parity.py --json` run from codex-copilot: {status: pass|fail|skipped, upstream: <path>, mismatches: {framework|cc|tc: {adopted, upstream}}}",
            "content_check.available": "true only if check-upstream-parity.py's own --help advertises a content/hash-level flag (task C-4); false is the expected/current state, not an error",
            "content_check.flag": "the --flag token detected in --help and invoked, present only when available is true",
            "content_check.result": "verbatim JSON result of running the detected flag with --json, present only when available is true",
            "versions.baseline": "codex-copilot/parity/claude-baseline.json's baseline block: the single frameworkVersion codex-copilot's automated check compares against",
            "versions.claude_copilot": "claude-copilot/VERSION.json's current framework, agents, and commands versions -- agents and commands version INDEPENDENTLY of framework and of each other, and neither is covered by upstream_check's mismatch detection (the known blind spot this collector exists to surface)",
        },
    }
    return {"metrics": metrics, "errors": errors}
