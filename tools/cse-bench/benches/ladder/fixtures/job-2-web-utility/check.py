#!/usr/bin/env python3
"""check.py — mechanical O-1 t_working acceptance check for job-2-web-utility
(TASK-125 / W-3 ladder harness). Stdlib only.

Runs `python3 wordfreq.py sample.txt` inside the job's materialized workdir
(the model is expected to have created wordfreq.py there; sample.txt was
copied in as part of job materialization) and compares stdout, line for
line after stripping trailing whitespace, against expected_output.txt
(precomputed once, offline, from sample.txt's real content — see
job_pack.py's docstring for how expected_output.txt was generated).

Usage: python3 check.py <job_workdir>
Exit 0 = t_working reached. Exit 1 = acceptance failed (mismatch, missing
file, non-zero exit, or timeout) — always with a reason printed to stderr
so a failed run is diagnosable from the audit trail, never a silent 1.
"""
import subprocess
import sys
from pathlib import Path

FIXTURE_DIR = Path(__file__).resolve().parent
EXPECTED_PATH = FIXTURE_DIR / "expected_output.txt"
TIMEOUT_SECONDS = 30


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("check.py: usage: check.py <job_workdir>", file=sys.stderr)
        return 1
    workdir = Path(argv[1]).expanduser().resolve()

    script = workdir / "wordfreq.py"
    if not script.is_file():
        print(f"check.py: FAIL — {script} was not created", file=sys.stderr)
        return 1

    try:
        result = subprocess.run(
            [sys.executable, str(script), "sample.txt"],
            cwd=str(workdir),
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        print(f"check.py: FAIL — wordfreq.py timed out after {TIMEOUT_SECONDS}s", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"check.py: FAIL — could not run wordfreq.py: {exc}", file=sys.stderr)
        return 1

    if result.returncode != 0:
        print(
            f"check.py: FAIL — wordfreq.py exited {result.returncode}; stderr: {result.stderr.strip()[:500]}",
            file=sys.stderr,
        )
        return 1

    expected = EXPECTED_PATH.read_text(encoding="utf-8").strip("\n").splitlines()
    actual = result.stdout.strip("\n").splitlines()
    actual_normalized = [line.rstrip() for line in actual]
    expected_normalized = [line.rstrip() for line in expected]

    if actual_normalized != expected_normalized:
        print(
            "check.py: FAIL — output mismatch\n"
            f"  expected: {expected_normalized}\n"
            f"  actual:   {actual_normalized}",
            file=sys.stderr,
        )
        return 1

    print("check.py: PASS — wordfreq.py output matches expected_output.txt exactly")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
