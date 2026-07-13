#!/usr/bin/env python3
"""benches/ladder/run.py — W-3 counterfactual ladder harness (TASK-125).

Runs `job_pack.py`'s job pack (v1: 3 real-software jobs of graduated size)
at each of `configs.py`'s 4 ladder rungs (bare -> +framework -> +knowledge
-> +integrations), per phases/phase-4-outcome-program-prd.md par.3 W-3:
"run one job pack at the 4 configs ... Scoring: O-3/O-4 mechanical; O-1
t_working mechanical (acceptance tests per job); t_loveable scored against
a written MLP expectation rubric ... that goes to the owner for sign-off
BEFORE first scoring."

THE HARD GATE (enforced mechanically, not just by operator care — see
check_signoff() and main()): this script REFUSES to run a live (non
--dry-run) job whose scoring path would touch t_loveable's MLP rubric
(rubric.md) until docs/40-initiatives/01-cse-auditability/decisions/
DEC-6-mlp-rubric-signoff.md literally contains the string
"Status: **ratified**". This mirrors the register's own "a rule that isn't
checked mechanically ... is not a rule" convention
(../../check_claims.py's own docstring) applied to an owner-decision gate
instead of a register-shape gate.

Two invocation modes:

    python3 run.py --dry-run
        Materializes all 4 configs x N jobs (real, side-effect-scoped
        directory operations under a temp run-root — safe, no model
        calls), builds every job's brief prompt and the acceptance-check
        command line, structurally validates job_pack.py (job_pack.
        validate_job_pack()) and rubric.md (validate_rubric_doc()), and
        reports the signoff gate's current state. Invokes `claude`
        ZERO times. Writes nothing to output/.

    python3 run.py
        The live run. BLOCKED today (see above) — will print the signoff
        gate's refusal reason and exit 1 rather than run, exactly as
        instructed for TASK-125 ("build everything, dry-run-validate
        everything, but do NOT execute a live scored ladder run").

Measurement capture per job-config cell (O-1..O-4, mechanical halves):
    - wall-clock seconds for the `claude -p` job call (O-3, this cell's
      contribution to the ladder's counterfactual-vs-bare comparison)
    - usage tokens from the JSON envelope (input/cache_creation/
      cache_read/output — same convention as ../resume_cost/run.py's
      extract_usage(), O-4)
    - t_working: pass/fail from the job's mechanical acceptance_check
      (job_pack.py), timestamped (O-1's mechanical half)
    - t_loveable: NOT computed by this script until the rubric is
      ratified (see above) — the scoring hook (score_t_loveable()) is
      built and dry-run-validated, never invoked live today.

Audit trail: every cell's config manifest (env summary, materialization
notes/warnings), the model call's full JSON envelope, and the acceptance
check's stdout/stderr are written to
output/bench_ladder-runs/<UTC stamp>/<job_id>__<config>__rep<N>.json for a
LIVE run — never during --dry-run, matching every other bench in this
directory's "nothing written to output/ during --dry-run" convention.

Stdlib only (see job_pack.py's docstring for why the job pack is a Python
module rather than a bank.yaml/rules.yaml-style file: no PyYAML importable
on this machine, verified live while building this bench).
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import configs
import job_pack

SCHEMA_VERSION = "cse-bench/1"
COLLECTOR_NAME = "bench_ladder"
HOST_SCOPE = "single-machine-single-user"

SCRIPT_DIR = Path(__file__).resolve().parent  # .../tools/cse-bench/benches/ladder
BENCH_ROOT = SCRIPT_DIR.parent.parent  # .../tools/cse-bench
REPO_ROOT = BENCH_ROOT.parent.parent  # copilot-control-tower
DEFAULT_OUT_DIR = BENCH_ROOT / "output"
RUBRIC_PATH = SCRIPT_DIR / "rubric.md"
DEC6_PATH = (
    REPO_ROOT / "docs" / "40-initiatives" / "01-cse-auditability" / "decisions" / "DEC-6-mlp-rubric-signoff.md"
)

CLAUDE_BIN = "claude"
DEFAULT_MODEL = "sonnet"
DEFAULT_TIMEOUT_SECONDS = 900  # real agentic coding jobs, not a closed-book Q&A probe
DEFAULT_REPS = 1
DEFAULT_CONCURRENCY = 2

SIGNOFF_MARKER_RE = re.compile(r"Status:\s*\*\*ratified\*\*")

RUBRIC_DIMENSIONS = ["Guided experience", "Sensible defaults", "Error help", "Polish"]


# ---------------------------------------------------------------------------
# The hard gate
# ---------------------------------------------------------------------------


def _extract_header_block(text: str) -> str:
    """Every DEC-N memo (DEC-1..5, 7, this one) states its Status in the
    leading blockquote (lines starting with '>' directly under the H1),
    exactly like this file's own header. Scanning ONLY that block — not
    the whole document — for the ratified marker avoids a false positive
    from this same file's own "Exact one-line actions" section, which
    necessarily shows the literal string 'Status: **ratified**' as the
    instruction text for HOW to ratify it, not as a ratification itself."""
    lines = text.splitlines()
    block: list[str] = []
    started = False
    for line in lines:
        if line.startswith(">"):
            started = True
            block.append(line)
        elif started:
            break
    return "\n".join(block)


def check_signoff(dec6_path: Path = DEC6_PATH) -> dict:
    """Mechanical check for the W-3 hard gate: DEC-6's header blockquote
    must literally contain "Status: **ratified**" before any live
    t_loveable scoring runs. Returns {"ratified": bool, "detail": str,
    "path": str} — never raises; a missing DEC-6 file is reported as NOT
    ratified, not an error, since "the memo doesn't exist yet" is exactly
    as blocking as "exists but not ratified.\""""
    if not dec6_path.is_file():
        return {"ratified": False, "detail": f"{dec6_path} does not exist", "path": str(dec6_path)}
    header = _extract_header_block(dec6_path.read_text(encoding="utf-8"))
    if SIGNOFF_MARKER_RE.search(header):
        return {"ratified": True, "detail": "DEC-6's header contains 'Status: **ratified**'", "path": str(dec6_path)}
    return {
        "ratified": False,
        "detail": "DEC-6's header does not contain the literal marker 'Status: **ratified**' — owner sign-off is still pending",
        "path": str(dec6_path),
    }


def validate_rubric_doc(rubric_path: Path = RUBRIC_PATH) -> list[str]:
    """Structural check tying rubric.md to run.py's own RUBRIC_DIMENSIONS
    list, so the code and the reviewable document can't silently drift:
    every dimension name must appear as a '### N.M <Dimension>' heading."""
    problems: list[str] = []
    if not rubric_path.is_file():
        return [f"{rubric_path} does not exist"]
    text = rubric_path.read_text(encoding="utf-8")
    for dim in RUBRIC_DIMENSIONS:
        if dim not in text:
            problems.append(f"rubric.md: no heading found for dimension {dim!r}")
    return problems


# ---------------------------------------------------------------------------
# Fixture materialization (per job, on top of configs.py's per-config
# workdir/env materialization)
# ---------------------------------------------------------------------------


def materialize_job_fixture(job: dict, workdir: Path) -> None:
    fixture_dir = job.get("fixture_dir")
    if fixture_dir is None:
        return
    shutil.copytree(Path(fixture_dir), workdir, dirs_exist_ok=True)
    # The external-checker script (check.py) lives in fixtures/ for
    # auditor-side invocation (job_pack.py's "external_checker" mode) and
    # is not part of the job's own materials — remove it from the copy so
    # it can't leak into the model's view of "files already in this repo."
    stray_checker = workdir / "check.py"
    if stray_checker.is_file() and job["acceptance_check"]["mode"] == "external_checker":
        stray_checker.unlink()


# ---------------------------------------------------------------------------
# Claude invocation — the job call (tools ENABLED, unlike ../knowledge_qa
# and ../resume_cost's closed-book probes: these are real coding jobs)
# ---------------------------------------------------------------------------


def build_claude_command(brief: str, model: str, claude_flags: list, max_budget_usd: Optional[float]) -> list:
    cmd = [
        CLAUDE_BIN,
        "-p",
        brief,
        "--model",
        model,
        "--output-format",
        "json",
        # Verified real flags (`claude --help`, checked live before writing
        # this bench): bypasses interactive permission prompts, which would
        # otherwise hang a headless call the moment the model tries to
        # Write/Edit/Bash inside the job workdir. Safe here because every
        # config's workdir is a disposable, isolated temp directory (see
        # configs.py) — never this repo, never a real project.
        "--dangerously-skip-permissions",
        *claude_flags,
    ]
    if max_budget_usd is not None:
        cmd += ["--max-budget-usd", str(max_budget_usd)]
    return cmd


def run_claude_job(
    brief: str, model: str, workdir: Path, env: dict, claude_flags: list, timeout: int, max_budget_usd: Optional[float]
) -> dict:
    claude_bin = shutil.which(CLAUDE_BIN, path=env.get("PATH"))
    command = build_claude_command(brief, model, claude_flags, max_budget_usd)
    if claude_bin:
        command[0] = claude_bin

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
    if result.returncode != 0:
        return {
            "status": "error",
            "text": "",
            "error": f"{command[0]} exited {result.returncode}: {result.stderr.strip()[:500]}",
            "duration_seconds": duration,
            "envelope": None,
            "stderr_tail": result.stderr[-2000:],
        }

    try:
        envelope = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        return {
            "status": "error",
            "text": "",
            "error": f"failed to parse --output-format json stdout: {exc}",
            "duration_seconds": duration,
            "envelope": None,
            "stderr_tail": result.stderr[-2000:] if result.stderr else "",
        }

    return {
        "status": "ok",
        "text": envelope.get("result", ""),
        "error": envelope.get("is_error") and envelope.get("subtype"),
        "duration_seconds": duration,
        "envelope": envelope,
        "stderr_tail": result.stderr[-2000:] if result.stderr else "",
    }


def extract_usage(envelope: Optional[dict]) -> dict:
    """Same convention as ../resume_cost/run.py's extract_usage()."""
    if not envelope:
        return {
            "input_tokens_new": None,
            "cache_creation_input_tokens": None,
            "cache_read_input_tokens": None,
            "input_tokens_total": None,
            "output_tokens": None,
            "total_tokens": None,
            "total_cost_usd": None,
            "duration_ms": None,
            "num_turns": None,
        }
    usage = envelope.get("usage") or {}
    input_new = usage.get("input_tokens") or 0
    cache_creation = usage.get("cache_creation_input_tokens") or 0
    cache_read = usage.get("cache_read_input_tokens") or 0
    output = usage.get("output_tokens") or 0
    input_total = input_new + cache_creation + cache_read
    return {
        "input_tokens_new": input_new,
        "cache_creation_input_tokens": cache_creation,
        "cache_read_input_tokens": cache_read,
        "input_tokens_total": input_total,
        "output_tokens": output,
        "total_tokens": input_total + output,
        "total_cost_usd": envelope.get("total_cost_usd"),
        "duration_ms": envelope.get("duration_ms"),
        "num_turns": envelope.get("num_turns"),
    }


# ---------------------------------------------------------------------------
# O-1 t_working — mechanical acceptance check
# ---------------------------------------------------------------------------


def run_acceptance_check(job: dict, workdir: Path, env: dict, timeout: int = 60) -> dict:
    check = job["acceptance_check"]
    if check["mode"] == "run_in_workdir":
        command = list(check["command"])
        run_cwd = workdir
    elif check["mode"] == "external_checker":
        command = list(check["command"]) + [str(workdir)]
        run_cwd = SCRIPT_DIR
    else:
        raise ValueError(f"unknown acceptance_check mode {check['mode']!r}")

    start = time.monotonic()
    try:
        result = subprocess.run(
            command, cwd=str(run_cwd), env=env, capture_output=True, text=True, timeout=timeout
        )
        duration = round(time.monotonic() - start, 2)
        return {
            "passed": result.returncode == 0,
            "returncode": result.returncode,
            "stdout_tail": result.stdout[-2000:],
            "stderr_tail": result.stderr[-2000:],
            "duration_seconds": duration,
            "command": command,
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "passed": False,
            "returncode": None,
            "stdout_tail": "",
            "stderr_tail": f"acceptance check timed out after {timeout}s: {exc}",
            "duration_seconds": round(time.monotonic() - start, 2),
            "command": command,
        }
    except OSError as exc:
        return {
            "passed": False,
            "returncode": None,
            "stdout_tail": "",
            "stderr_tail": f"could not run acceptance check: {exc}",
            "duration_seconds": round(time.monotonic() - start, 2),
            "command": command,
        }


def validate_acceptance_check_wiring(job: dict) -> list[str]:
    """--dry-run's structural stand-in for run_acceptance_check(): confirms
    the check command is invocable and well-formed WITHOUT running it
    against a (nonexistent, since no model call happened) deliverable — a
    dry-run failure here means the harness is broken, not that a job
    hasn't been attempted yet, so this deliberately does NOT execute the
    check.py the way a live run would."""
    problems: list[str] = []
    check = job["acceptance_check"]
    command = check.get("command", [])
    if check["mode"] == "external_checker":
        checker_path = Path(command[-1])
        if not checker_path.is_file():
            problems.append(f"external checker script missing: {checker_path}")
    elif check["mode"] == "run_in_workdir":
        fixture_dir = job.get("fixture_dir")
        script_name = command[-1] if command else None
        if fixture_dir is None or script_name is None or not (Path(fixture_dir) / script_name).is_file():
            problems.append(f"run_in_workdir script {script_name!r} not found under fixture_dir {fixture_dir}")
    if not shutil.which(command[0]) and command[0] not in ("python3",):
        problems.append(f"acceptance check interpreter {command[0]!r} not resolvable on PATH")
    return problems


# ---------------------------------------------------------------------------
# t_loveable — MLP rubric scoring hook (blind, exemplar-anchored; see
# rubric.md). NEVER invoked live until check_signoff() reports ratified=True
# — see main()'s gate.
# ---------------------------------------------------------------------------


def collect_deliverable_bundle(workdir: Path, max_bytes: int = 20_000) -> str:
    """Concatenates every regular file under workdir (deterministic path
    order) into a single text bundle for the judge, truncated to
    max_bytes total so a runaway job can't blow out a judge prompt.
    Binary/undecodable files are noted, not included verbatim."""
    parts: list[str] = []
    total = 0
    for path in sorted(workdir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(workdir)
        try:
            content = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            parts.append(f"--- {rel} ---\n[binary or unreadable file, {path.stat().st_size} bytes, omitted]\n")
            continue
        header = f"--- {rel} ---\n"
        chunk = header + content + "\n"
        if total + len(chunk) > max_bytes:
            parts.append(f"--- {rel} ---\n[omitted: bundle size cap {max_bytes} bytes reached]\n")
            break
        parts.append(chunk)
        total += len(chunk)
    return "".join(parts)


def build_blind_judge_prompt(job: dict, deliverable_bundle: str, rubric_text: str) -> str:
    """Builds the model-judge prompt with NO config name, ladder rung, or
    job-cell identifier anywhere in the text — see rubric.md §2 "Blind."
    The caller (score_t_loveable) is responsible for keeping the mapping
    from (config, job, rep) to this prompt OUT of the prompt itself."""
    return (
        "You are scoring a coding deliverable against a rubric. You do not "
        "know, and must not guess or ask about, what tool or process produced "
        "this deliverable — score only what you can see below.\n\n"
        f"## The brief the deliverable was created to satisfy\n\n{job['brief']}\n\n"
        f"## The rubric\n\n{rubric_text}\n\n"
        f"## The deliverable (all files produced)\n\n{deliverable_bundle}\n\n"
        "Score each of the 4 dimensions 0-3 per the rubric's exemplar anchors. "
        "Respond as JSON: "
        '{"guided_experience": {"score": N, "rationale": "..."}, '
        '"sensible_defaults": {"score": N, "rationale": "..."}, '
        '"error_help": {"score": N, "rationale": "..."}, '
        '"polish": {"score": N, "rationale": "..."}}'
    )


def score_t_loveable(
    judge_mode: str,
    job: dict,
    workdir: Path,
    rubric_text: str,
    dry_run: bool,
    judge_fn=None,
) -> dict:
    """judge_mode: "model" or "human". Returns a record that NEVER
    fabricates a score:
      - dry_run=True: builds/validates the prompt or worksheet, invokes
        nothing, returns {"mode": ..., "status": "dry-run", "prompt_preview"
        or "worksheet_path": ...}.
      - judge_mode="human": always writes a worksheet and returns
        {"status": "pending-human-score", ...} — no live/dry-run
        distinction changes this, since no model call is involved either
        way (see rubric.md §2, --ingest-scores is not yet built).
      - judge_mode="model", dry_run=False: requires a real judge_fn
        (a callable(prompt) -> raw text); this is called by main() only
        after check_signoff() confirms ratified=True — score_t_loveable
        itself does not re-check signoff, that is main()'s gate, so this
        function stays a pure, independently-testable hook.
    """
    bundle = collect_deliverable_bundle(workdir)

    if judge_mode == "human":
        worksheet = {
            "job_id": job["id"],
            "brief": job["brief"],
            "rubric_dimensions": RUBRIC_DIMENSIONS,
            "deliverable_bundle": bundle,
            "scores": {dim: {"score": None, "rationale": None} for dim in RUBRIC_DIMENSIONS},
        }
        if dry_run:
            return {"mode": "human", "status": "dry-run", "worksheet_preview_chars": len(json.dumps(worksheet))}
        return {"mode": "human", "status": "pending-human-score", "worksheet": worksheet}

    if judge_mode == "model":
        prompt = build_blind_judge_prompt(job, bundle, rubric_text)
        if dry_run:
            return {"mode": "model", "status": "dry-run", "prompt_chars": len(prompt), "prompt_preview": prompt[:500]}
        if judge_fn is None:
            # A live run reaching here means main() invoked the model-judge
            # path without a real judge caller wired in yet — this is the
            # honest "not built out further, blocked" state TASK-125 leaves
            # this in (see run.py's module docstring), NOT the same thing
            # as --dry-run; kept distinct so the two are never conflated in
            # an audit-trail record.
            return {"mode": "model", "status": "not-wired", "prompt_chars": len(prompt), "reason": "no judge_fn provided to score_t_loveable"}
        raw = judge_fn(prompt)
        try:
            parsed = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            return {"mode": "model", "status": "error", "error": "judge response was not valid JSON", "raw": raw}
        return {"mode": "model", "status": "scored", "scores": parsed}

    raise ValueError(f"unknown judge_mode {judge_mode!r}")


# ---------------------------------------------------------------------------
# Envelope I/O (same contract as ../../cse_bench.py's run_collector())
# ---------------------------------------------------------------------------


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def write_envelope(metrics: dict, errors: list[dict], out_dir: Path) -> Path:
    envelope = {
        "schema_version": SCHEMA_VERSION,
        "collector": COLLECTOR_NAME,
        "generated_at": _utc_now_iso(),
        "host_scope": HOST_SCOPE,
        "metrics": metrics,
        "errors": errors,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    stamped = out_dir / f"{COLLECTOR_NAME}-{_utc_stamp()}.json"
    latest = out_dir / f"{COLLECTOR_NAME}-latest.json"
    payload = json.dumps(envelope, indent=2, sort_keys=True, default=str) + "\n"
    stamped.write_text(payload, encoding="utf-8")
    latest.write_text(payload, encoding="utf-8")
    return stamped


# ---------------------------------------------------------------------------
# Aggregation — O-6 (per-rung deltas vs bare), written for a live run to
# consume; exercised structurally by --dry-run's own smoke path, never
# fed real numbers today.
# ---------------------------------------------------------------------------


def aggregate(records: list[dict]) -> dict:
    by_job: dict[str, dict] = {}
    for job_id in sorted(set(r["job_id"] for r in records)):
        job_records = {r["config"]: r for r in records if r["job_id"] == job_id}
        bare = job_records.get("bare")
        by_config = {}
        for config_name, rec in job_records.items():
            usage = rec.get("usage") or {}
            by_config[config_name] = {
                "t_working_reached": rec.get("acceptance", {}).get("passed"),
                "elapsed_seconds": rec.get("duration_seconds"),
                "total_tokens": usage.get("total_tokens"),
            }
            if bare is not None and config_name != "bare":
                bare_seconds = bare.get("duration_seconds")
                bare_tokens = (bare.get("usage") or {}).get("total_tokens")
                this_seconds = rec.get("duration_seconds")
                this_tokens = usage.get("total_tokens")
                by_config[config_name]["o3_speed_delta_seconds_vs_bare"] = (
                    round(bare_seconds - this_seconds, 2)
                    if bare_seconds is not None and this_seconds is not None
                    else None
                )
                by_config[config_name]["o4_token_reduction_pct_vs_bare"] = (
                    round((bare_tokens - this_tokens) / bare_tokens * 100, 2)
                    if bare_tokens
                    else None
                )
        by_job[job_id] = by_config
    return {"by_job": by_job}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run.py",
        description="W-3 counterfactual ladder harness: 4 configs x the job pack, O-1..O-4 mechanical + MLP-rubric t_loveable.",
    )
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Envelope output directory.")
    parser.add_argument("--run-root", default=None, help="Root dir for config/job materialization (default: a fresh tempfile.mkdtemp()).")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Model passed to claude -p (default: {DEFAULT_MODEL}).")
    parser.add_argument("--judge-model", default=DEFAULT_MODEL, help="Model passed to the blind judge's claude -p call (model judge-mode only).")
    parser.add_argument("--config", choices=configs.CONFIG_NAMES, default=None, help="Restrict to one ladder rung (default: all 4).")
    parser.add_argument("--job", choices=job_pack.JOB_IDS, default=None, help="Restrict to one job (default: all in the pack).")
    parser.add_argument("--reps", type=int, default=DEFAULT_REPS, help=f"Repetitions per (config, job) cell (default: {DEFAULT_REPS}).")
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY, help=f"Max concurrent claude calls (default: {DEFAULT_CONCURRENCY}).")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS, help=f"Per-job-call timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS}).")
    parser.add_argument("--max-budget-usd", type=float, default=None, help="Optional per-call --max-budget-usd safety cap passed straight to claude -p.")
    parser.add_argument("--judge-mode", choices=["model", "human"], default="human", help="t_loveable scoring mode (default: human — see rubric.md §2).")
    parser.add_argument("--dry-run", action="store_true", help="Materialize configs/fixtures and build every prompt, but never invoke claude. Nothing written to output/.")
    parser.add_argument("--i-know-this-is-blocked-on-signoff", action="store_true", help="Required in addition to omitting --dry-run; still refused if DEC-6 is not ratified. Exists so a live invocation can never be accidental.")
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    pack_problems = job_pack.validate_job_pack()
    rubric_problems = validate_rubric_doc()
    signoff = check_signoff()

    if pack_problems:
        print("run.py: job_pack.py FAILED structural validation:", file=sys.stderr)
        for p in pack_problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    if rubric_problems:
        print("run.py: rubric.md FAILED structural validation:", file=sys.stderr)
        for p in rubric_problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    print(f"run.py: job_pack.py OK ({len(job_pack.JOBS)} job(s): {', '.join(job_pack.JOB_IDS)})")
    print(f"run.py: rubric.md OK ({len(RUBRIC_DIMENSIONS)} dimension(s): {', '.join(RUBRIC_DIMENSIONS)})")
    print(f"run.py: DEC-6 sign-off gate: ratified={signoff['ratified']} ({signoff['detail']})")

    if not args.dry_run:
        if not (signoff["ratified"] and args.i_know_this_is_blocked_on_signoff):
            print(
                "run.py: REFUSING to run live — the MLP rubric (rubric.md) is not yet owner-ratified "
                f"(DEC-6: {signoff['path']}). Per TASK-125's hard gate, no scored ladder run may execute "
                "before sign-off. Use --dry-run to validate the pipeline instead.",
                file=sys.stderr,
            )
            return 1

    config_names = [args.config] if args.config else configs.CONFIG_NAMES
    jobs = [job_pack.get_job(args.job)] if args.job else job_pack.JOBS

    cells = [(config_name, job, rep) for config_name in config_names for job in jobs for rep in range(1, args.reps + 1)]
    print(
        f"run.py: {len(config_names)} config(s) x {len(jobs)} job(s) x {args.reps} rep(s) = {len(cells)} cell(s) "
        f"(model={args.model}, judge_mode={args.judge_mode}, concurrency={args.concurrency}, timeout={args.timeout}s)"
    )

    run_root = Path(args.run_root).expanduser().resolve() if args.run_root else Path(tempfile.mkdtemp(prefix="cse-bench-ladder-"))
    run_root.mkdir(parents=True, exist_ok=True)
    print(f"run.py: run_root={run_root}")

    rubric_text = RUBRIC_PATH.read_text(encoding="utf-8")

    stamp = _utc_stamp()
    out_dir = Path(args.out_dir).expanduser().resolve()
    run_dir = out_dir / f"{COLLECTOR_NAME}-runs" / stamp

    print_lock = threading.Lock()
    completed = 0

    def do_cell(cell: tuple) -> dict:
        nonlocal completed
        config_name, job, rep = cell
        cfg = configs.materialize(config_name, run_root / job["id"], job["id"])
        materialize_job_fixture(job, cfg.workdir)

        record: dict = {
            "job_id": job["id"],
            "config": config_name,
            "rep": rep,
            "config_notes": cfg.notes,
            "config_warnings": cfg.warnings,
        }

        if args.dry_run:
            check_wiring_problems = validate_acceptance_check_wiring(job)
            judge_preview = score_t_loveable(args.judge_mode, job, cfg.workdir, rubric_text, dry_run=True)
            record.update(
                {
                    "status": "dry-run",
                    "env_summary": cfg.env_summary(),
                    "brief_chars": len(job["brief"]),
                    "acceptance_check_wiring_problems": check_wiring_problems,
                    "t_loveable_scoring_preview": judge_preview,
                }
            )
            with print_lock:
                completed += 1
                flag = "OK" if not check_wiring_problems else f"WIRING PROBLEMS: {check_wiring_problems}"
                print(f"run.py: [{completed}/{len(cells)}] {job['id']} / {config_name} rep{rep} -> dry-run {flag}", flush=True)
            return record

        raw = run_claude_job(job["brief"], args.model, cfg.workdir, cfg.env, cfg.claude_flags, args.timeout, args.max_budget_usd)
        usage = extract_usage(raw["envelope"])
        acceptance = run_acceptance_check(job, cfg.workdir, cfg.env)

        judge_fn = None  # wired to a real headless judge call once ratified; not built out further here (blocked)
        t_loveable_record = score_t_loveable(args.judge_mode, job, cfg.workdir, rubric_text, dry_run=False, judge_fn=judge_fn)

        record.update(
            {
                "status": raw["status"],
                "duration_seconds": raw["duration_seconds"],
                "usage": usage,
                "acceptance": acceptance,
                "t_loveable": t_loveable_record,
                "error": raw["error"],
            }
        )

        run_dir.mkdir(parents=True, exist_ok=True)
        full_record = {**record, "envelope": raw["envelope"], "model_stderr_tail": raw["stderr_tail"]}
        record_path = run_dir / f"{job['id']}__{config_name}__rep{rep}.json"
        record_path.write_text(json.dumps(full_record, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")

        with print_lock:
            completed += 1
            print(
                f"run.py: [{completed}/{len(cells)}] {job['id']} / {config_name} rep{rep} -> "
                f"status={raw['status']} t_working={acceptance['passed']}",
                flush=True,
            )
        return record

    results: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as pool:
        for record in pool.map(do_cell, cells):
            results.append(record)

    if args.dry_run:
        problems_found = sum(1 for r in results if r.get("acceptance_check_wiring_problems"))
        print(
            f"run.py: dry-run complete, {len(results)} cell(s) materialized and validated, "
            f"{problems_found} with wiring problems, 0 claude invocations, nothing written to output/."
        )
        return 1 if problems_found else 0

    aggregated = aggregate(results)
    errors = [
        {"job_id": r["job_id"], "config": r["config"], "rep": r["rep"], "error": r["error"]}
        for r in results
        if r["status"] != "ok"
    ]

    metrics = {
        "task": "TASK-125 (W-3 ladder harness + MLP rubric)",
        "job_pack_version": job_pack.JOB_PACK_VERSION,
        "jobs": [{"id": j["id"], "title": j["title"], "size": j["size"]} for j in jobs],
        "configs_run": config_names,
        "run_params": {
            "model": args.model,
            "judge_mode": args.judge_mode,
            "reps": args.reps,
            "concurrency": args.concurrency,
            "timeout_seconds": args.timeout,
            "cells_run": len(cells),
        },
        "signoff_gate": signoff,
        "results": aggregated,
        "run_dir": str(run_dir),
        "definitions": {
            "t_working": "acceptance_check (job_pack.py) exits 0 in the job's materialized workdir; mechanical, no judge involved",
            "t_loveable": "first (config, job, rep) whose rubric.md scoring reaches >=2 ('Adequate') on ALL 4 dimensions; null if none qualifies. NOT computed in any run before DEC-6 ratification (see signoff_gate above).",
            "o3_speed_delta_seconds_vs_bare": "bare.duration_seconds - this_config.duration_seconds for the same job; positive means this rung was faster than bare",
            "o4_token_reduction_pct_vs_bare": "(bare.total_tokens - this_config.total_tokens) / bare.total_tokens * 100 for the same job; positive means this rung used fewer tokens than bare",
        },
    }

    stamped_path = write_envelope(metrics, errors, out_dir)
    print(f"run.py: wrote {stamped_path}")
    print(f"run.py: wrote {out_dir / (COLLECTOR_NAME + '-latest.json')}")
    print(f"run.py: raw per-cell records in {run_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
