#!/usr/bin/env python3
"""check.py — mechanical O-1 t_working acceptance check for
job-3-integration-report (TASK-125 / W-3 ladder harness). Stdlib only.

This job (PRD phase-4-outcome-program-prd.md par.3 W-3: "a data-pull-and-
report task that exercises integrations") is deliberately reachable from
EVERY rung of the ladder, not just +integrations: the brief instructs the
model to write report.md stating integrations are unavailable, rather than
fabricate service data, when `copilot` is not on PATH. That honest-fallback
path is itself part of what the MLP rubric's "error help" dimension scores
— see ../../rubric.md. t_working (this check) only asks "did the job reach
SOME honest, well-formed conclusion," never "did it reach real service
data" — the ladder's O-1..O-4 deltas across rungs are what reveal whether
+integrations actually produced a materially better report, not this
mechanical gate.

Usage: python3 check.py <job_workdir>
Exit 0 = t_working reached (report.md exists and is one of the two honest
shapes below). Exit 1 = acceptance failed, reason on stderr.
"""
import re
import sys
from pathlib import Path

HEALTHY_RE = re.compile(r"services:\s*\d+\s*healthy", re.IGNORECASE)
UNAVAILABLE_MARKER = "integrations unavailable"


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

    if HEALTHY_RE.search(text):
        print("check.py: PASS — report.md contains a 'Services: N healthy' summary line")
        return 0
    if UNAVAILABLE_MARKER in text.lower():
        print("check.py: PASS — report.md honestly states integrations are unavailable (no fabricated data)")
        return 0

    print(
        "check.py: FAIL — report.md contains neither a 'Services: N healthy' line "
        f"nor the literal '{UNAVAILABLE_MARKER}' marker; the brief requires one or the other",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
