"""job_pack.py — Ladder bench job pack v1 (TASK-125 / W-3).

Register-first (V-2): this file IS the job-pack definition the register
(`docs/40-initiatives/01-cse-auditability/claims.yaml`, definition
`ladder_job_pack_v1`) points at — write/extend it before any ladder data
exists, never after looking at a run's results.

WHY A PYTHON MODULE, NOT bank.yaml/rules.yaml LIKE THE OTHER BENCHES: this
machine's default `python3` has no importable PyYAML (`python3 -c "import
yaml"` fails with ModuleNotFoundError, verified live while building this
bench) — `benches/knowledge_qa/run.py` and `benches/voice_lint/lint.py`
carry their own hand-rolled vendored fallback parsers to cope with exactly
this. A job pack's shape (nested acceptance-test lists, per-job fixture
dirs, config-requirement flags) is more structured than bank.yaml's flat
rows, so this bench sidesteps re-implementing a YAML subset parser for a
shape that would need a bigger one: a plain, stdlib, directly-importable
Python module IS the pack, and "pack format is pluggable" (PRD par.3 W-3 —
"the accountant pack comes later, same harness") is satisfied by
`run.py --job-pack <dotted.module.path>` (default: this file) rather than
by a file-format promise. A future pack can equally well be YAML if some
future machine has PyYAML; nothing in run.py assumes Python source.

JOB PACK SCHEMA (each entry in JOBS):
    id                    unique slug
    title                 short human title
    size                  "small" | "medium" | "large" — the PRD's
                          "graduated size" requirement
    exercises_integrations  bool — True only for the job the PRD names as
                          exercising integrations (job-3); used nowhere to
                          gate execution (every job runs at every config —
                          the ladder's whole point is measuring what each
                          rung does or doesn't add), only to annotate
                          results for readability.
    fixture_dir           path (relative to this file) copied VERBATIM into
                          the job's materialized workdir before the brief
                          is given to the model. Starter files the model
                          may edit (job-1) or read-only inputs it must not
                          need to alter (job-2's sample.txt); job-3 ships
                          no fixture (a from-scratch job).
    protected_files       filenames under fixture_dir the brief instructs
                          the model NOT to modify (the acceptance test's
                          own ground truth) — advisory to the model and to
                          a human auditor; not mechanically enforced (no
                          sandboxed diff-lock exists in this v1 harness).
    brief                 the LOCKED brief text handed to the model
                          verbatim (echoing O-2's "brief locked at the
                          start" ethos even though this ladder measures
                          O-1/O-3/O-4/O-6, not O-2).
    acceptance_check       {"mode": ..., "command": [argv...]} for the
                          mechanical O-1 t_working check (see run.py's
                          run_acceptance_check() for the exact dispatch):
                            "run_in_workdir"  — run `command` with
                              cwd=job_workdir, no extra argv appended.
                              Used when the check must execute FROM INSIDE
                              the materialized workdir (job-1: test_calc.py
                              imports calc.py via a relative import, so it
                              only works run in-place).
                            "external_checker" — run
                              `command + [str(job_workdir)]` with
                              cwd=SCRIPT_DIR. Used when the checker is an
                              independent auditor script that takes the
                              workdir as an argument rather than running
                              inside it (job-2, job-3's fixtures/*/check.py).
                          Both modes run with the job's own materialized
                          env (see configs.py) and exit 0 = t_working
                          reached. Every job's check prints its PASS/FAIL
                          reason to stderr (see fixtures/*/check.py, or
                          unittest's own output for job-1) so a failed run
                          is diagnosable from the audit trail alone.
"""
from __future__ import annotations

from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURES_DIR = SCRIPT_DIR / "fixtures"

JOB_PACK_VERSION = "v1"

JOBS: list[dict] = [
    {
        "id": "job-1-bugfix",
        "title": "Fix the average() off-by-one bug in calc.py",
        "size": "small",
        "exercises_integrations": False,
        "fixture_dir": FIXTURES_DIR / "job-1-bugfix",
        "protected_files": ["test_calc.py"],
        "brief": (
            "The file calc.py has a bug in its average() function: it produces "
            "the wrong result (or crashes with ZeroDivisionError) for some "
            "inputs. Fix the bug so every test in test_calc.py passes. Do not "
            "modify test_calc.py. When you believe it is fixed, verify with: "
            "python3 test_calc.py"
        ),
        "acceptance_check": {"mode": "run_in_workdir", "command": ["python3", "test_calc.py"]},
    },
    {
        "id": "job-2-web-utility",
        "title": "Build a command-line word-frequency utility",
        "size": "medium",
        "exercises_integrations": False,
        "fixture_dir": FIXTURES_DIR / "job-2-web-utility",
        "protected_files": ["sample.txt"],
        "brief": (
            "Build a command-line utility called wordfreq.py that takes one "
            "argument (a path to a text file) and prints the 5 most frequent "
            "words in the file, one per line, in the exact format "
            "'word: count'. Words are case-insensitive and defined as maximal "
            "runs of ASCII letters (a-z); strip everything else (punctuation, "
            "digits, whitespace). Order results by count descending, then "
            "alphabetically ascending as a tiebreaker. If the file has fewer "
            "than 5 distinct words, print all of them in the same order. Test "
            "it against the provided sample.txt in this directory. Do not "
            "modify sample.txt."
        ),
        "acceptance_check": {
            "mode": "external_checker",
            "command": ["python3", str(FIXTURES_DIR / "job-2-web-utility" / "check.py")],
        },
    },
    {
        "id": "job-3-integration-report",
        "title": "Pull a service-health report via the copilot CLI",
        "size": "large",
        "exercises_integrations": True,
        "fixture_dir": None,
        "protected_files": [],
        "brief": (
            "Using the copilot CLI (check whether it is on PATH first), run "
            "its health check (e.g. `copilot health --json`) and write a "
            "markdown report to report.md that lists each service's name and "
            "status from the health check output, plus a one-line summary in "
            "the exact form 'Services: N healthy' (N = an integer). If the "
            "copilot CLI is NOT available on PATH, do not fabricate service "
            "data — instead write report.md stating plainly that integrations "
            "are unavailable (include the literal phrase 'integrations "
            "unavailable') and explain what a person would need to do to "
            "enable them."
        ),
        "acceptance_check": {
            "mode": "external_checker",
            "command": ["python3", str(FIXTURES_DIR / "job-3-integration-report" / "check.py")],
        },
    },
]

JOB_IDS = [job["id"] for job in JOBS]


def get_job(job_id: str) -> dict:
    for job in JOBS:
        if job["id"] == job_id:
            return job
    raise KeyError(f"job_pack.py: unknown job id {job_id!r} (known: {JOB_IDS})")


REQUIRED_FIELDS = (
    "id", "title", "size", "exercises_integrations", "fixture_dir",
    "protected_files", "brief", "acceptance_check",
)
VALID_SIZES = {"small", "medium", "large"}
VALID_CHECK_MODES = {"run_in_workdir", "external_checker"}


def validate_job_pack(jobs: list[dict] = JOBS) -> list[str]:
    """Structural, dependency-free validation used by run.py's --dry-run
    (and safe to call any other time): every job has the required fields,
    a real size, a well-formed acceptance_check, and fixture/checker paths
    that actually exist on disk. Returns a list of problems (empty = OK) —
    never raises, so one malformed job doesn't stop the rest from being
    reported."""
    problems: list[str] = []
    seen_ids: set[str] = set()

    for idx, job in enumerate(jobs):
        loc = f"JOBS[{idx}]"
        for field_name in REQUIRED_FIELDS:
            if field_name not in job:
                problems.append(f"{loc}: missing required field {field_name!r}")
        job_id = job.get("id")
        if job_id:
            loc = f"JOBS[id={job_id}]"
            if job_id in seen_ids:
                problems.append(f"{loc}: duplicate job id")
            seen_ids.add(job_id)

        if job.get("size") not in VALID_SIZES:
            problems.append(f"{loc}: size {job.get('size')!r} not in {sorted(VALID_SIZES)}")

        fixture_dir = job.get("fixture_dir")
        if fixture_dir is not None and not Path(fixture_dir).is_dir():
            problems.append(f"{loc}: fixture_dir {fixture_dir} does not exist")

        for protected in job.get("protected_files", []) or []:
            if fixture_dir is not None and not (Path(fixture_dir) / protected).is_file():
                problems.append(f"{loc}: protected_files entry {protected!r} not found under {fixture_dir}")

        check = job.get("acceptance_check")
        if not isinstance(check, dict) or "mode" not in check or "command" not in check:
            problems.append(f"{loc}: acceptance_check must be a {{mode, command}} mapping")
            continue
        if check["mode"] not in VALID_CHECK_MODES:
            problems.append(f"{loc}: acceptance_check.mode {check['mode']!r} not in {sorted(VALID_CHECK_MODES)}")
        command = check.get("command")
        if not isinstance(command, list) or not command:
            problems.append(f"{loc}: acceptance_check.command must be a non-empty list")
        elif check["mode"] == "external_checker":
            checker_path = Path(command[-1])
            if not checker_path.is_file():
                problems.append(f"{loc}: external checker {checker_path} does not exist")
        elif check["mode"] == "run_in_workdir" and fixture_dir is not None:
            script_name = command[-1]
            if not (Path(fixture_dir) / script_name).is_file():
                problems.append(f"{loc}: run_in_workdir command {script_name!r} not found under fixture_dir {fixture_dir}")

    return problems
