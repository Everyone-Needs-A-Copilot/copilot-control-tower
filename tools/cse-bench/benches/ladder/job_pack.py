"""job_pack.py — Ladder bench job pack v2 (TASK-125 follow-on / QA WP-76 fix).

WHY v2 EXISTS: QA WP-76 (adversarial verification of the first live ladder
run, 20260714T135253Z) proved v1 was an INSTRUMENT that could not detect a
framework advantage even if one existed — job-3's own check.py docstring
admitted it "never asks did it reach real service data," and job-1/job-2
required zero org knowledge or live integration data to solve correctly
from ANY rung. The v1 run's 12/12 t_working tie across all rungs was
therefore not evidence of "no advantage" — it was evidence of an
instrument with no discriminating power on that axis, by construction.
v2 fixes this directly: every non-control job's correct answer is now
UNREACHABLE from a lower rung, and every job's check.py mechanically
verifies the discriminating property rather than merely a well-formed
shape (see each job's own check.py docstring for its specific fabrication
guard). See ladder_job_pack_v2 in the register
(`docs/40-initiatives/01-cse-auditability/claims.yaml`) for the
pre-registered definition and the "v1 could not discriminate" finding —
that register entry is a PROPOSED PATCH pending the register's own
single-writer agent landing it; do not quote any v2 run before it is
committed (see this bench's README.md "Job pack v2" section).

THE 4 JOBS, one per role:
  - job-1-bugfix          CONTROL — unchanged from v1. Any rung can solve
                           it; a rung's failure to beat bare here is
                           itself a meaningful (not noisy) null result,
                           since it requires no knowledge/integration/
                           decomposition advantage to pass.
  - job-2-house-voice      KNOWLEDGE-discriminating — NEW. Correct output
                           requires knowledge-copilot's real, org-specific
                           voice glossary (01-company/02-voice/
                           06-glossary.md), which exists ONLY in the real
                           knowledge tree (+knowledge/+integrations), not
                           in this project's CLAUDE.md (+framework's
                           pointer-only materialization) and not anywhere
                           a generic model would plausibly guess. See
                           fixtures/job-2-house-voice/check.py.
  - job-3-integration-report  INTEGRATION-discriminating — brief mostly
                           unchanged from v1, but check.py now
                           independently re-fetches REAL service health
                           (by absolute path, never through the
                           config-under-test's own PATH) and mechanically
                           asserts the deliverable's claims match it,
                           service by service — closing exactly the gap
                           QA WP-76 found. See
                           fixtures/job-3-integration-report/check.py.
  - job-4-toolkit          FRAMEWORK-discriminating — NEW. 6 independent,
                           equally-sized functions in one brief; t_working
                           requires ALL 6 (17 assertions) to pass at once
                           — a completeness-across-parts bar big enough
                           that decomposition/systematic checklisting
                           should matter, not a task any single-shot
                           free-write reliably nails end to end. See
                           fixtures/job-4-toolkit/test_toolkit.py.

Register-first (V-2): this file IS the job-pack definition the register
(`docs/40-initiatives/01-cse-auditability/claims.yaml`, definition
`ladder_job_pack_v2`) points at — write/extend it before any ladder data
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

JOB_PACK_VERSION = "v2"

JOBS: list[dict] = [
    {
        "id": "job-1-bugfix",
        "title": "Fix the average() off-by-one bug in calc.py",
        "size": "small",
        "exercises_integrations": False,
        "discriminates": "control",
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
        "id": "job-2-house-voice",
        "title": "Write a client-facing 'About' paragraph in the org's house voice",
        "size": "medium",
        "exercises_integrations": False,
        "discriminates": "knowledge",
        "fixture_dir": None,
        "protected_files": [],
        "brief": (
            "Write a short paragraph (roughly 80-180 words) for our organization's "
            "website 'About' section, describing what we do for a client team that "
            "has been putting off a hard organizational choice. Before writing, check "
            "whether this project has any house voice/tone guidance reachable from "
            "here (for example, under the directory named by the CC_KNOWLEDGE_REPO "
            "environment variable, if it is set) and follow it if you find it — do "
            "not invent or guess at house-specific terminology you have not actually "
            "found in reachable project documentation; if you find no such guidance, "
            "write in your own best professional judgment instead. Save your final "
            "paragraph to about.md, with no other files and no meta-commentary about "
            "your process — about.md should contain only the finished paragraph."
        ),
        "acceptance_check": {
            "mode": "external_checker",
            "command": ["python3", str(FIXTURES_DIR / "job-2-house-voice" / "check.py")],
        },
    },
    {
        "id": "job-3-integration-report",
        "title": "Pull a service-health report via the copilot CLI",
        "size": "large",
        "exercises_integrations": True,
        "discriminates": "integrations",
        "fixture_dir": None,
        "protected_files": [],
        "brief": (
            "Using the copilot CLI (check whether it is on PATH first), run "
            "its health check (`copilot --json health`) and write a "
            "markdown report to report.md. For EVERY service line the health check "
            "printed, add one line to report.md in the exact form "
            "'- <service_name>: <status>' (service_name and status exactly as the "
            "health check printed them, e.g. '- docker: healthy'), then a final "
            "summary line in the exact form 'Services: N healthy' (N = the integer "
            "count of services whose status is exactly 'healthy'). If the "
            "copilot CLI is NOT available on PATH, do not fabricate service "
            "data — instead write report.md stating plainly that integrations "
            "are unavailable (include the literal phrase 'integrations "
            "unavailable') and explain what a person would need to do to "
            "enable them. Only use the 'Services: N healthy' summary form if you "
            "actually ran the health check and are reporting its real output."
        ),
        "acceptance_check": {
            "mode": "external_checker",
            "command": ["python3", str(FIXTURES_DIR / "job-3-integration-report" / "check.py")],
        },
    },
    {
        "id": "job-4-toolkit",
        "title": "Build a 6-function utility toolkit (completeness across parts)",
        "size": "large",
        "exercises_integrations": False,
        "discriminates": "framework",
        "fixture_dir": FIXTURES_DIR / "job-4-toolkit",
        "protected_files": ["test_toolkit.py"],
        "brief": (
            "Create a file called toolkit.py implementing 6 independent functions, "
            "described below. A test suite (test_toolkit.py, already in this "
            "directory) checks all 6 — do not modify test_toolkit.py. When you "
            "believe all 6 are complete and correct, verify with: "
            "python3 test_toolkit.py\n\n"
            "1. is_prime(n) -> bool: True if n is a prime number, False otherwise "
            "(0, 1, and negative numbers are not prime).\n"
            "2. reverse_words(s) -> str: reverse the order of words in s, "
            "collapsing any run of whitespace between words to a single space and "
            "stripping leading/trailing whitespace. reverse_words('the sky is "
            "blue') == 'blue is sky the'.\n"
            "3. flatten(nested) -> list: flatten an arbitrarily nested list of "
            "lists into a single flat list, preserving left-to-right order. "
            "flatten([1, [2, 3], [4, [5, 6]]]) == [1, 2, 3, 4, 5, 6].\n"
            "4. run_length_encode(s) -> str: compress consecutive repeated "
            "characters into '<char><count>' pairs. "
            "run_length_encode('aaabbc') == 'a3b2c1'.\n"
            "5. most_common_word(text) -> str: given free text, return the single "
            "most frequent word, case-insensitive, ignoring punctuation/digits "
            "(words are maximal runs of ASCII letters). Break ties alphabetically "
            "ascending.\n"
            "6. caesar_cipher(s, shift) -> str: shift each alphabetic character by "
            "shift positions (wrapping a-z and A-Z separately, shift may be "
            "negative), leaving non-alphabetic characters unchanged, preserving "
            "case. caesar_cipher('abcXYZ', 3) == 'defABC'."
        ),
        "acceptance_check": {"mode": "run_in_workdir", "command": ["python3", "test_toolkit.py"]},
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
