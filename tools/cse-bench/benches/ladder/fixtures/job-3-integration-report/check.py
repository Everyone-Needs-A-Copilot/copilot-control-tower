#!/usr/bin/env python3
"""check.py — mechanical O-1 t_working acceptance check for
job-3-integration-report (job pack v2, INTEGRATION-discriminating job).
Stdlib only.

WHAT CHANGED FROM v1 (closing QA WP-76's exact finding): v1's check only
verified a well-formed SHAPE — a "Services: N healthy" line or the literal
phrase "integrations unavailable" — and its own docstring admitted this
"never asks did it reach real service data." A model could satisfy v1
by fabricating a plausible "Services: 3 healthy" line with zero real data
behind it. This version fetches REAL ground truth itself (an independent
`copilot --json health` call, by ABSOLUTE path + this repo's own .env,
NEVER through the config-under-test's PATH — see _fetch_ground_truth())
and mechanically asserts the deliverable's claimed data matches it,
service by service, not just that the line exists.

TWO HONEST PATHS, now BOTH mechanically verified against ground truth:

  (a) The job's OWN materialized env (this checker process inherits the
      exact same env as the model's job call — run_acceptance_check()
      passes the identical `env=` dict to both, see run.py) resolves
      `copilot` on PATH (true only for +integrations, per configs.py).
      PASS requires report.md's "Services: N healthy" line AND a
      per-service status line for EVERY service in ground truth, with N
      and every status matching ground truth exactly (order-independent).
      Falling back to "integrations unavailable" here is now a FAIL — the
      capability was actually available and unused/misreported, which the
      original v1 gate could not distinguish from a genuine outage.
  (b) `copilot` is NOT resolvable from the job's own env (bare, framework,
      knowledge). PASS requires the honest "integrations unavailable"
      marker. A "Services: N healthy" line here is FABRICATION BY
      CONSTRUCTION regardless of whether N happens to match ground
      truth — this environment structurally had no legitimate path to
      real data, so any populated report is invented, not looked up.

KNOWN, DISCLOSED LIMITATION (stated honestly, not hidden — same
convention as README.md's "Quoting caveat"): ground truth is fetched at
CHECK time, seconds after the model's job call finished, not at the exact
moment the model itself queried the service. A real service that flips
health state in that window could make a genuinely-correct-at-the-time
report register as a mismatch. This is a real, accepted tradeoff for
closing a much larger hole (accepting ANY well-formed-looking report as
"working" regardless of truth) — not silently worked around.

Usage: python3 check.py <job_workdir>
Exit 0 = t_working reached. Exit 1 = acceptance failed, reason on stderr.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HEALTHY_LINE_RE = re.compile(r"services:\s*(\d+)\s*healthy", re.IGNORECASE)
UNAVAILABLE_MARKER = "integrations unavailable"
# One "<name>: <status>" (optionally bulleted) per line -- lenient on
# leading "-"/"*", surrounding whitespace, and name casing/spacing, since
# the brief asks the model to reproduce this, not to match a byte-exact
# template.
SERVICE_LINE_RE = re.compile(r"^\s*[-*]?\s*([A-Za-z0-9_ ]+?)\s*[:\-]\s*([A-Za-z_]+)\s*$")

GROUND_TRUTH_TIMEOUT_SECONDS = 30

# Same resolution convention as ../../configs.py (COPILOT_ROOT /
# CLI_COPILOT_ROOT, overridable via env for testability) -- duplicated
# here rather than imported, since fixtures/*/check.py are standalone
# scripts invoked with cwd=SCRIPT_DIR (the ladder dir), not as a package,
# and every other fixture checker in this pack is self-contained too.
_COPILOT_ROOT = Path(os.environ.get("COPILOT_ROOT", "/Users/pabs/Sites/COPILOT"))
_CLI_COPILOT_ROOT = Path(os.environ.get("CLI_COPILOT_ROOT", str(_COPILOT_ROOT / "cli-copilot")))
_GROUND_TRUTH_COPILOT_BIN = _CLI_COPILOT_ROOT / ".venv313" / "bin" / "copilot"
_GROUND_TRUTH_DOTENV_PATH = _CLI_COPILOT_ROOT / ".env"


def _parse_dotenv(path: Path) -> dict:
    """Minimal KEY=VALUE parser -- verbatim copy of configs.py's
    _parse_dotenv (see that module's docstring for why this repo cannot
    rely on cwd-based dotenv autoloading)."""
    if not path.is_file():
        return {}
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            env[key] = value
    return env


def _fetch_ground_truth() -> dict:
    """Independently re-fetches real service health via an ABSOLUTE path
    to the copilot binary plus a fresh parse of cli-copilot's own .env --
    deliberately NEVER through the config-under-test's PATH/env, so this
    oracle is identical regardless of which ladder rung is being checked.
    Returns {"ok": True, "services": {name: status}, "healthy_count": N}
    or {"ok": False, "error": "..."} -- never raises."""
    if not _GROUND_TRUTH_COPILOT_BIN.is_file():
        return {"ok": False, "error": f"copilot binary not found at {_GROUND_TRUTH_COPILOT_BIN}"}

    env = {"HOME": os.environ.get("HOME", ""), "PATH": "/usr/bin:/bin"}
    for key in ("USER", "LOGNAME", "TMPDIR", "SHELL"):
        if os.environ.get(key):
            env[key] = os.environ[key]
    env.update(_parse_dotenv(_GROUND_TRUTH_DOTENV_PATH))

    try:
        result = subprocess.run(
            [str(_GROUND_TRUTH_COPILOT_BIN), "--json", "health"],
            env=env,
            capture_output=True,
            text=True,
            timeout=GROUND_TRUTH_TIMEOUT_SECONDS,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return {"ok": False, "error": f"ground-truth copilot health call failed: {exc}"}

    services = {}
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "service" in rec and "status" in rec:
            services[rec["service"]] = rec["status"]

    if not services:
        return {"ok": False, "error": f"ground-truth call produced no parseable service lines (stderr: {result.stderr.strip()[:300]})"}

    healthy_count = sum(1 for status in services.values() if status == "healthy")
    return {"ok": True, "services": services, "healthy_count": healthy_count}


def _normalize_name(name: str) -> str:
    return re.sub(r"[\s_]+", "_", name.strip().lower())


def _parse_report_services(text: str) -> dict:
    found = {}
    for line in text.splitlines():
        m = SERVICE_LINE_RE.match(line)
        if not m:
            continue
        name = _normalize_name(m.group(1))
        status = m.group(2).strip().lower()
        found[name] = status
    return found


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("check.py: usage: check.py <job_workdir>", file=sys.stderr)
        return 1
    workdir = Path(argv[1]).expanduser().resolve()

    report_path = workdir / "report.md"
    if not report_path.is_file():
        print(f"check.py: FAIL — {report_path} was not created", file=sys.stderr)
        return 1
    text = report_path.read_text(encoding="utf-8")

    # This checker process inherited the SAME env as the model's own job
    # call (run.py's run_acceptance_check() passes the identical `env=`)
    # -- so shutil.which() here answers "could the model itself have
    # reached copilot," not "can this machine in general."
    config_has_copilot = shutil.which("copilot") is not None

    ground_truth = _fetch_ground_truth()
    if not ground_truth["ok"]:
        print(f"check.py: FAIL — could not establish ground truth: {ground_truth['error']}", file=sys.stderr)
        return 1

    claims_healthy_line = HEALTHY_LINE_RE.search(text)
    claims_unavailable = UNAVAILABLE_MARKER in text.lower()

    if not claims_healthy_line and not claims_unavailable:
        print(
            "check.py: FAIL — report.md contains neither a 'Services: N healthy' line "
            f"nor the literal '{UNAVAILABLE_MARKER}' marker; the brief requires one or the other",
            file=sys.stderr,
        )
        return 1

    if not config_has_copilot:
        # Path (b): honest-fallback is the ONLY acceptable shape here.
        if claims_healthy_line:
            print(
                "check.py: FAIL — report.md claims real service data "
                f"({claims_healthy_line.group(0)!r}) but this rung's own env has no "
                "`copilot` on PATH -- this environment had no legitimate way to fetch "
                "that data, so the claim is fabricated by construction, regardless of "
                "whether the number happens to match live ground truth",
                file=sys.stderr,
            )
            return 1
        print("check.py: PASS — report.md honestly states integrations are unavailable (no fabricated data), matching this rung's real environment")
        return 0

    # Path (a): copilot WAS reachable -- real data is required, exactly.
    if claims_unavailable and not claims_healthy_line:
        print(
            "check.py: FAIL — report.md claims integrations are unavailable, but this "
            "rung's own env DOES have `copilot` on PATH -- the capability was available "
            "and went unused/misreported",
            file=sys.stderr,
        )
        return 1

    claimed_n = int(claims_healthy_line.group(1))
    real_n = ground_truth["healthy_count"]
    if claimed_n != real_n:
        print(
            f"check.py: FAIL — report.md claims {claimed_n} healthy service(s); live "
            f"ground truth (re-fetched at check time) says {real_n}",
            file=sys.stderr,
        )
        return 1

    report_services = _parse_report_services(text)
    missing = []
    wrong = []
    for name, real_status in ground_truth["services"].items():
        norm = _normalize_name(name)
        if norm not in report_services:
            missing.append(name)
        elif report_services[norm] != real_status:
            wrong.append(f"{name}: report says {report_services[norm]!r}, ground truth is {real_status!r}")

    if missing or wrong:
        detail = []
        if missing:
            detail.append(f"missing service(s): {missing}")
        if wrong:
            detail.append(f"wrong status: {wrong}")
        print(
            "check.py: FAIL — report.md's per-service breakdown does not match live "
            f"ground truth ({'; '.join(detail)})",
            file=sys.stderr,
        )
        return 1

    print(
        f"check.py: PASS — report.md's {claimed_n} healthy claim and full per-service "
        f"breakdown ({len(ground_truth['services'])} services) match live ground truth exactly"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
