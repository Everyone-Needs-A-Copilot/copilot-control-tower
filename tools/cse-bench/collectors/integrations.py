"""collectors/integrations.py — live integrations collector.

Runs `/opt/homebrew/bin/copilot --json health`, which performs real
network/auth calls against every registered service, and reports which
ones are healthy. Only {name, healthy} survives per service -- no URLs,
error strings, or other payload fields, since those can carry
configuration or credential fragments (e.g. the CLI's own `fireflies`
failure message includes a partial bearer-header value).

Serves PRD-9 (CSE Verification & Benchmark Program), task B-6.

Design notes
------------
- The health check performs real network auth per service and can take
  a while; it is run with a generous (180s) timeout rather than the
  collector's usual short subprocess timeout, and a timeout is reported
  as a per-item error rather than crashing the run.
- `copilot --json health`'s stdout is not a single JSON document -- it
  prints a human-readable header line followed by one JSON object per
  service (JSON Lines), observed directly against this machine's
  install. Parsing tolerates that shape (and would also tolerate a
  future single-JSON-array shape, since each line is parsed
  independently and non-JSON lines are simply skipped).
- The binary may be an editable/local install where a formal `version`
  subcommand doesn't exist; the version probe tries `copilot version`
  first, then falls back to `copilot --version`, and reports whichever
  succeeds.
"""
from __future__ import annotations

import json
import subprocess

COLLECTOR_NAME = "integrations"

COPILOT_BIN = "/opt/homebrew/bin/copilot"
_VERSION_TIMEOUT_SECONDS = 15
_HEALTH_TIMEOUT_SECONDS = 180


def _get_cli_version(errors: list[dict]) -> str | None:
    for args in (["version"], ["--version"]):
        try:
            result = subprocess.run(
                [COPILOT_BIN, *args],
                capture_output=True,
                text=True,
                timeout=_VERSION_TIMEOUT_SECONDS,
            )
        except FileNotFoundError as exc:
            errors.append({"item": "cli_version", "error": f"binary not found: {exc}"})
            return None
        except subprocess.TimeoutExpired as exc:
            errors.append({"item": "cli_version", "args": args, "error": f"timed out: {exc}"})
            continue

        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()

    errors.append({"item": "cli_version", "error": "neither 'version' nor '--version' produced output"})
    return None


def _run_health(errors: list[dict]) -> dict:
    empty = {"healthy_count": None, "total_services": None, "services": []}

    try:
        result = subprocess.run(
            [COPILOT_BIN, "--json", "health"],
            capture_output=True,
            text=True,
            timeout=_HEALTH_TIMEOUT_SECONDS,
        )
    except FileNotFoundError as exc:
        errors.append({"item": "health", "error": f"binary not found: {exc}"})
        return empty
    except subprocess.TimeoutExpired as exc:
        errors.append({"item": "health", "error": f"timed out after {_HEALTH_TIMEOUT_SECONDS}s: {exc}"})
        return empty
    except OSError as exc:
        errors.append({"item": "health", "error": f"unexpected OSError: {exc}"})
        return empty

    services: list[dict] = []
    unparsed_lines = 0
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            unparsed_lines += 1
            continue
        name = entry.get("service")
        if name is None:
            continue
        services.append({"name": name, "healthy": entry.get("status") == "healthy"})

    if not services:
        errors.append(
            {
                "item": "health",
                "error": f"no service entries parsed (returncode={result.returncode}); stderr={result.stderr.strip()[:300]}",
            }
        )
    elif unparsed_lines:
        errors.append({"item": "health", "error": f"{unparsed_lines} output line(s) failed JSON parsing and were skipped"})

    services.sort(key=lambda s: s["name"])
    healthy_count = sum(1 for s in services if s["healthy"])
    return {
        "healthy_count": healthy_count,
        "total_services": len(services),
        "services": services,
    }


def collect() -> dict:
    """Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []

    cli_version = _get_cli_version(errors)
    health = _run_health(errors)

    metrics = {
        "cli_path": COPILOT_BIN,
        "cli_version": cli_version,
        "healthy_count": health["healthy_count"],
        "total_services": health["total_services"],
        "services": health["services"],
        "definitions": {
            "cli_version": "output of `copilot version`, falling back to `copilot --version` if the former subcommand doesn't exist; null if neither succeeded",
            "healthy_count / total_services": "counts derived from parsing `copilot --json health`'s per-service JSON Lines output; null if the run failed entirely (binary missing, timeout, no parseable output)",
            "services[].healthy": "true iff that service's reported status == 'healthy'; no other payload fields (URLs, error text, details) are retained, since those can carry configuration/credential fragments",
        },
    }
    return {"metrics": metrics, "errors": errors}
