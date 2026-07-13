"""collectors/cli_soul.py — CLI Copilot SOUL.md §6 conformance scorecard.

Runs cli-copilot's own mechanical enforcement of its SOUL.md §6 "Quality
Bar" (`tests/test_soul_conformance.py`, TASK-110/S-4) and reports the
per-service x per-criterion result as data, not a computed verdict —
this collector renders the scorecard cli-copilot's test suite already
produced; it does not re-derive conformance itself (that would duplicate
logic that belongs in the CLI's own repo, the same "parse, never
compute" invariant this control tower holds everywhere else).

The suite has no `--json` mode, so this collector runs it with
`pytest -v --tb=no -rxX` (verbose per-test lines + a short summary that
restates every xfail/failure with its reason) and parses that text --
both flags are stdlib-adjacent pytest output, not a new dependency. Each
parametrized case id is `<service>` under a criterion-named test class
(`TestHealthRegistered`, `TestConfigDocumented`, ...); the class name is
mapped to the SOUL criterion key it exercises. Cases that aren't
per-service (the shared --json cleanliness test, the portability suite,
two structural meta-tests) are reported separately under `suite_checks`.

Serves PRD-9 (CSE Verification & Benchmark Program) / TASK-110 (S-4).

Design notes
------------
- The subprocess call, its timeout, and every parse step are wrapped;
  a missing `uv` binary, a missing test file, a pytest crash, or
  unparseable output each degrade to an `errors` entry and an
  `available: false` metrics block rather than raising out of
  `collect()` (same contract as `collectors/tasksdb.py` and
  `collectors/parity.py`).
- `xfail` (a tracked, known SOUL gap) and `xpass` (a tracked gap that
  silently started passing -- cli-copilot's suite runs those with
  `strict=True`, so an xpass there is actually a suite *failure*, and
  this collector's own `returncode`/`failed` count will reflect that)
  are both reported as non-`pass` in `gaps`, so a stale tracking marker
  shows up here even before someone re-reads cli-copilot's test file.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Optional

COLLECTOR_NAME = "cli_soul"

CLI_COPILOT_ROOT = Path("/Volumes/Dev/Sites/COPILOT/cli-copilot")
TEST_RELATIVE_PATH = Path("tests") / "test_soul_conformance.py"

_SUBPROCESS_TIMEOUT_SECONDS = 120

# Maps the pytest test-class name in tests/test_soul_conformance.py to the
# SOUL.md §6 criterion key it exercises. A class not in this table (or a
# module-level test with no class) is reported under suite_checks instead
# of the per-service scorecard -- see module docstring.
CLASS_TO_CRITERION = {
    "TestHealthRegistered": "health_registered",
    "TestDedicatedTestFileExists": "test_file_exists",
    "TestCopilotErrorHierarchy": "copilot_error_hierarchy",
    "TestLazyImport": "lazy_import",
    "TestConfigDocumented": "config_documented",
    "TestDocsEntryExists": "docs_entry",
}

_NODEID_RE = re.compile(
    r"^(?P<file>[^:]+)::(?:(?P<cls>\w+)::)?(?P<test>\w+)(?:\[(?P<param>[^\]]*)\])?$"
)
_RESULT_LINE_RE = re.compile(
    r"^(?P<nodeid>\S+::\S+)\s+(?P<status>PASSED|FAILED|XFAIL|XPASS|SKIPPED|ERROR)\b"
)
_SUMMARY_REASON_RE = re.compile(
    r"^(?P<status>XFAIL|XPASS|FAILED|ERROR|SKIPPED)\s+(?P<nodeid>\S+)(?:\s+-\s+(?P<reason>.*))?$"
)
_TOTALS_RE = re.compile(r"(\d+)\s+(passed|failed|xfailed|xpassed|skipped|error(?:s)?)")


def _parse_nodeid(nodeid: str) -> tuple[Optional[str], str, Optional[str]]:
    """Return (class_name_or_None, test_name, param_or_None)."""
    match = _NODEID_RE.match(nodeid)
    if not match:
        return None, nodeid, None
    return match.group("cls"), match.group("test"), match.group("param")


def _parse_pytest_output(stdout: str) -> dict:
    """Parse `pytest -v --tb=no -rxX` output into per-test results plus a
    totals summary line. Never raises -- an unparseable line is simply
    skipped, and totals default to zero rather than crashing the run.
    """
    per_test: dict[str, str] = {}
    reasons: dict[str, str] = {}
    summary_line: Optional[str] = None

    for line in stdout.splitlines():
        stripped = line.strip()

        result_match = _RESULT_LINE_RE.match(stripped)
        if result_match:
            per_test[result_match.group("nodeid")] = result_match.group("status")
            continue

        reason_match = _SUMMARY_REASON_RE.match(stripped)
        if reason_match and reason_match.group("nodeid") in per_test:
            reason = reason_match.group("reason")
            if reason:
                reasons[reason_match.group("nodeid")] = reason
            continue

        if _TOTALS_RE.search(stripped) and (
            "passed" in stripped or "failed" in stripped or "error" in stripped
        ):
            # pytest's final summary line, e.g. "125 passed, 13 xfailed in 1.20s"
            summary_line = stripped

    totals = {key: 0 for key in ("passed", "failed", "xfailed", "xpassed", "skipped", "errors")}
    if summary_line:
        for count, label in _TOTALS_RE.findall(summary_line):
            key = "errors" if label.startswith("error") else label
            if key in totals:
                totals[key] = int(count)

    return {
        "per_test": per_test,
        "reasons": reasons,
        "summary_line": summary_line,
        "totals": totals,
    }


def _build_scorecard(per_test: dict[str, str], reasons: dict[str, str]) -> dict:
    scorecard: dict[str, dict[str, dict]] = {}
    suite_checks: list[dict] = []

    for nodeid, status in sorted(per_test.items()):
        cls, _test, param = _parse_nodeid(nodeid)
        criterion = CLASS_TO_CRITERION.get(cls) if cls else None
        entry = {"status": status.lower(), "reason": reasons.get(nodeid)}

        if criterion and param:
            scorecard.setdefault(param, {})[criterion] = entry
        else:
            suite_checks.append({"nodeid": nodeid, **entry})

    return scorecard, suite_checks


# "pass" means the criterion is actually met today. A tracked xfail is
# NOT a pass -- it is a real, currently-existing SOUL gap that cli-copilot's
# suite happens to track (via xfail(strict=True)) so it doesn't break CI.
# The scorecard's job is to surface every gap, tracked or not; "is this
# gap tracked (won't break the suite) or untracked (will)" is the
# separate `tracked` field on each gap entry below.
_PASS_STATUSES = {"passed"}
_TRACKED_GAP_STATUSES = {"xfail"}  # known, documented, suite stays green
# Anything else (xpass, failed, error, skipped) is an untracked gap and
# makes suite_green False -- see gaps[].tracked below.


def _summarize(scorecard: dict) -> tuple[dict, dict, list[dict]]:
    services = sorted(scorecard)
    criteria = sorted({c for entries in scorecard.values() for c in entries})

    by_service: dict[str, dict] = {}
    by_criterion: dict[str, dict] = {c: {"pass": 0, "gap": 0} for c in criteria}
    gaps: list[dict] = []

    for service in services:
        entries = scorecard[service]
        counts = {"pass": 0, "gap": 0}
        for criterion, entry in entries.items():
            status = entry["status"]
            if status in _PASS_STATUSES:
                counts["pass"] += 1
                by_criterion.setdefault(criterion, {"pass": 0, "gap": 0})["pass"] += 1
            else:
                counts["gap"] += 1
                by_criterion.setdefault(criterion, {"pass": 0, "gap": 0})["gap"] += 1
                gaps.append(
                    {
                        "service": service,
                        "criterion": criterion,
                        "status": status,
                        "tracked": status in _TRACKED_GAP_STATUSES,
                        "reason": entry.get("reason"),
                    }
                )
        by_service[service] = counts

    return by_service, by_criterion, gaps


def collect() -> dict:
    """Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []
    test_path = CLI_COPILOT_ROOT / TEST_RELATIVE_PATH

    if not CLI_COPILOT_ROOT.is_dir():
        errors.append(
            {
                "item": "cli_copilot_root",
                "path": str(CLI_COPILOT_ROOT),
                "error": "cli-copilot checkout not found at the expected path",
            }
        )
        return {"metrics": {"available": False, "cli_copilot_root": str(CLI_COPILOT_ROOT)}, "errors": errors}

    if not test_path.is_file():
        errors.append(
            {
                "item": "test_soul_conformance",
                "path": str(test_path),
                "error": "tests/test_soul_conformance.py not found -- the SOUL conformance "
                "suite has not been added (or was moved/renamed) in cli-copilot",
            }
        )
        return {
            "metrics": {
                "available": False,
                "cli_copilot_root": str(CLI_COPILOT_ROOT),
                "test_path": str(test_path),
            },
            "errors": errors,
        }

    command = [
        "uv",
        "run",
        "--extra",
        "dev",
        "pytest",
        str(TEST_RELATIVE_PATH),
        "-v",
        "--tb=no",
        "-rxX",
        "-p",
        "no:cacheprovider",
    ]

    try:
        result = subprocess.run(
            command,
            cwd=str(CLI_COPILOT_ROOT),
            capture_output=True,
            text=True,
            timeout=_SUBPROCESS_TIMEOUT_SECONDS,
        )
    except FileNotFoundError as exc:
        errors.append({"item": "pytest_run", "error": f"could not start 'uv': {exc}"})
        return {
            "metrics": {
                "available": False,
                "cli_copilot_root": str(CLI_COPILOT_ROOT),
                "test_path": str(test_path),
                "command": command,
            },
            "errors": errors,
        }
    except subprocess.TimeoutExpired as exc:
        errors.append(
            {
                "item": "pytest_run",
                "error": f"timed out after {_SUBPROCESS_TIMEOUT_SECONDS}s: {exc}",
            }
        )
        return {
            "metrics": {
                "available": False,
                "cli_copilot_root": str(CLI_COPILOT_ROOT),
                "test_path": str(test_path),
                "command": command,
            },
            "errors": errors,
        }

    stdout = result.stdout or ""
    if not stdout.strip():
        errors.append(
            {
                "item": "pytest_run",
                "error": f"empty stdout (returncode={result.returncode}); "
                f"stderr={(result.stderr or '').strip()[:500]}",
            }
        )
        return {
            "metrics": {
                "available": False,
                "cli_copilot_root": str(CLI_COPILOT_ROOT),
                "test_path": str(test_path),
                "command": command,
                "returncode": result.returncode,
            },
            "errors": errors,
        }

    parsed = _parse_pytest_output(stdout)
    if not parsed["per_test"]:
        errors.append(
            {
                "item": "pytest_output_parse",
                "error": "pytest ran but no per-test result lines were parsed -- output shape "
                "may have changed (e.g. a pytest version dropped/renamed the -v line format)",
            }
        )

    scorecard, suite_checks = _build_scorecard(parsed["per_test"], parsed["reasons"])
    by_service, by_criterion, gaps = _summarize(scorecard)

    if result.returncode not in (0, 1):
        errors.append(
            {
                "item": "pytest_run",
                "error": f"unexpected returncode {result.returncode} "
                f"(0=all pass, 1=pytest reported a failure); stderr="
                f"{(result.stderr or '').strip()[:500]}",
            }
        )

    metrics = {
        "available": True,
        "cli_copilot_root": str(CLI_COPILOT_ROOT),
        "test_path": str(test_path),
        "command": command,
        "returncode": result.returncode,
        "suite_green": result.returncode == 0,
        "summary_line": parsed["summary_line"],
        "totals": parsed["totals"],
        "services": sorted(scorecard),
        "criteria": sorted({c for entries in scorecard.values() for c in entries}),
        "scorecard": scorecard,
        "totals_by_service": by_service,
        "totals_by_criterion": by_criterion,
        "gaps": gaps,
        "suite_checks": suite_checks,
        "definitions": {
            "scorecard": "per-service map of criterion -> {status, reason}, parsed from "
            "cli-copilot's tests/test_soul_conformance.py -v --tb=no -rxX output. status is "
            "one of pytest's own outcomes lowercased: passed, xfail, xpass, failed, error, skipped",
            "gaps": "every scorecard entry whose status is not 'passed' -- i.e. the criterion "
            "is not actually met today, tracked or not. gaps[].tracked is true for status=="
            "'xfail' (a known, documented SOUL violation that cli-copilot's suite tracks via "
            "xfail(strict=True) so it doesn't break CI) and false for status in "
            "{xpass, failed, error, skipped} (an untracked regression or a stale xfail that "
            "started passing again -- either makes suite_green false)",
            "suite_checks": "test cases in the suite that are not per-service (the shared "
            "--json cleanliness check, the foreign-cwd portability suite, and two structural "
            "meta-tests) -- SOUL criterion (g) plus Part 2's portability requirement live here",
            "suite_green": "true iff pytest's own returncode was 0 -- xfail(strict=True) cases "
            "count as green (tracked, expected) even though they appear in gaps above; an XPASS "
            "on a strict xfail, or any untracked failure, makes this false",
        },
    }
    return {"metrics": metrics, "errors": errors}
