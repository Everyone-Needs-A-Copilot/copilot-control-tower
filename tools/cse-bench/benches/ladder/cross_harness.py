#!/usr/bin/env python3
"""cross_harness.py -- the t6-two-harnesses-one-behavior BEHAVIOR check
(TASK-146). Runs the SAME job_pack.py job, with the SAME mechanical
acceptance_check, through BOTH harnesses (Claude's existing `+framework`
ladder rung, reused verbatim; Codex's new `+framework`-equivalent,
codex_harness.py) and records whether the two harnesses reach the same
PASS/FAIL outcome.

THE PRE-REGISTERED DEFINITION THIS SCRIPT IMPLEMENTS (V-2, committed
BEFORE this script existed) lives at
../../../../docs/40-initiatives/01-cse-auditability/phases/
phase-4-cross-harness-behavior.md -- read that file before reading this
one. In one line: job J is behavior-equivalent iff
claude_t_working(J) == codex_t_working(J), both booleans from J's own
job_pack.py acceptance_check (unmodified, run identically against
whichever harness's workdir just ran); the pack-level claim is true iff
every job in the pack agrees.

Explicitly NOT tested by this script (see the memo Sec 2.4 for the full
list, stated here too so it can't be silently forgotten by a future
caller): t_loveable/rubric equivalence, multi-agent delegation equivalence
(neither harness's headless mode delegates), non-framework rungs,
byte-level deliverable equivalence.

No DEC-6 sign-off gate applies here (unlike run.py's live mode) -- this
script never scores t_loveable or touches rubric.md; it only runs each
job's own pre-existing mechanical acceptance_check, exactly as --dry-run
already validates for the Claude-only ladder.

Two invocation modes, mirroring run.py's own convention:

    python3 cross_harness.py --dry-run
        Materializes both harnesses' configs for every job (real,
        side-effect-scoped directory operations under a temp run-root),
        builds every job's brief and acceptance-check wiring, validates
        job_pack.py. Invokes neither `claude` nor `codex` once. Writes
        nothing to output/.

    python3 cross_harness.py
        The live run. 2 harnesses x N jobs x reps cells, each a real model
        call. Cost ceiling: --max-budget-usd (Claude only -- Codex has no
        native dollar-cap flag, see the memo Sec 1) and --timeout
        (wall-clock, enforced on both harnesses by this script's own
        subprocess timeout).

Stdlib only (see job_pack.py's own docstring for why).
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import codex_harness
import configs
import job_pack
import run as ladder_run

SCHEMA_VERSION = "cse-bench/1"
COLLECTOR_NAME = "cross_harness"

SCRIPT_DIR = Path(__file__).resolve().parent  # .../tools/cse-bench/benches/ladder
BENCH_ROOT = SCRIPT_DIR.parent.parent  # .../tools/cse-bench
DEFAULT_OUT_DIR = BENCH_ROOT / "output"

DEFAULT_MODEL = "sonnet"  # Claude side only -- see the memo Sec 2.6 / Sec 1's model-asymmetry note
DEFAULT_TIMEOUT_SECONDS = 900
DEFAULT_REPS = 1
DEFAULT_MAX_BUDGET_USD = 3.0  # Claude side only, same convention as run.py -- Codex has no equivalent flag


def _utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def run_one_job_claude(job: dict, run_root: Path, model: str, timeout: int, max_budget_usd: Optional[float], rep: int) -> dict:
    cfg = configs.materialize_framework(run_root, job["id"], rep)
    ladder_run.materialize_job_fixture(job, cfg.workdir)
    protected_pre = ladder_run.capture_protected_hashes(job, cfg.workdir)

    raw = ladder_run.run_claude_job(job["brief"], model, cfg.workdir, cfg.env, cfg.claude_flags, timeout, max_budget_usd)
    usage = ladder_run.extract_usage(raw["envelope"])
    acceptance = ladder_run.run_acceptance_check(job, cfg.workdir, cfg.env)
    protected = ladder_run.check_protected_files(job, cfg.workdir, protected_pre)

    t_working = bool(acceptance["passed"] and protected["clean"])
    return {
        "harness": "claude",
        "config_notes": cfg.notes,
        "config_warnings": cfg.warnings,
        "call_status": raw["status"],
        "call_error": raw["error"],
        "duration_seconds": raw["duration_seconds"],
        "usage": usage,
        "acceptance": {k: v for k, v in acceptance.items() if k != "command"},
        "acceptance_command": acceptance["command"],
        "protected_files_check": protected,
        "t_working": t_working,
        "workdir": str(cfg.workdir),
        "stderr_tail": raw["stderr_tail"],
        "model": model,
    }


def run_one_job_codex(job: dict, run_root: Path, timeout: int, rep: int) -> dict:
    cfg = codex_harness.materialize_codex_framework(run_root, job["id"], rep)
    ladder_run.materialize_job_fixture(job, cfg.workdir)
    protected_pre = ladder_run.capture_protected_hashes(job, cfg.workdir)

    raw = codex_harness.run_codex_job(job["brief"], cfg.workdir, cfg.env, timeout)
    usage = codex_harness.extract_codex_usage(raw["envelope"])
    acceptance = ladder_run.run_acceptance_check(job, cfg.workdir, cfg.env)
    protected = ladder_run.check_protected_files(job, cfg.workdir, protected_pre)

    t_working = bool(acceptance["passed"] and protected["clean"])
    return {
        "harness": "codex",
        "config_notes": cfg.notes,
        "config_warnings": cfg.warnings,
        "call_status": raw["status"],
        "call_error": raw["error"],
        "duration_seconds": raw["duration_seconds"],
        "usage": usage,
        "acceptance": {k: v for k, v in acceptance.items() if k != "command"},
        "acceptance_command": acceptance["command"],
        "protected_files_check": protected,
        "t_working": t_working,
        "workdir": str(cfg.workdir),
        "stderr_tail": raw["stderr_tail"],
        "model": None,  # Codex uses its configured default (see the memo Sec 1) -- not overridden here
    }


def validate_dry_run(job: dict, run_root: Path, rep: int) -> dict:
    claude_cfg = configs.materialize_framework(run_root, job["id"], rep)
    ladder_run.materialize_job_fixture(job, claude_cfg.workdir)
    claude_wiring = ladder_run.validate_acceptance_check_wiring(job)

    codex_cfg = codex_harness.materialize_codex_framework(run_root, job["id"], rep)
    ladder_run.materialize_job_fixture(job, codex_cfg.workdir)
    codex_wiring = ladder_run.validate_acceptance_check_wiring(job)

    return {
        "job_id": job["id"],
        "claude_config_notes": claude_cfg.notes,
        "claude_config_warnings": claude_cfg.warnings,
        "codex_config_notes": codex_cfg.notes,
        "codex_config_warnings": codex_cfg.warnings,
        "acceptance_check_wiring_problems": claude_wiring or codex_wiring,  # same job_pack.py check, same result either way
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Envelope output directory.")
    parser.add_argument("--run-root", default=None, help="Root dir for config/job materialization (default: a fresh tempfile.mkdtemp()).")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Model passed to the Claude-side claude -p call (default: {DEFAULT_MODEL}). Codex side uses its own configured default -- see module docstring.")
    parser.add_argument("--job", choices=job_pack.JOB_IDS, default=None, help="Restrict to one job (default: all in the pack).")
    parser.add_argument("--reps", type=int, default=DEFAULT_REPS, help=f"Repetitions per job (default: {DEFAULT_REPS}).")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS, help=f"Per-call wall-clock timeout in seconds, enforced on BOTH harnesses (default: {DEFAULT_TIMEOUT_SECONDS}).")
    parser.add_argument("--max-budget-usd", type=float, default=DEFAULT_MAX_BUDGET_USD, help=f"Claude-side per-call dollar cap (native flag; default: {DEFAULT_MAX_BUDGET_USD}). Codex has no equivalent flag -- see module docstring / the pre-registration memo Sec 1.")
    parser.add_argument("--dry-run", action="store_true", help="Materialize both harnesses' configs/fixtures and validate wiring, but never invoke claude or codex. Nothing written to output/.")
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    pack_problems = job_pack.validate_job_pack()
    if pack_problems:
        print("cross_harness.py: job_pack.py FAILED structural validation:", file=sys.stderr)
        for p in pack_problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    jobs = [job_pack.get_job(args.job)] if args.job else job_pack.JOBS
    print(f"cross_harness.py: job_pack.py OK ({len(jobs)} job(s) selected: {', '.join(j['id'] for j in jobs)})")
    print(f"cross_harness.py: {len(jobs)} job(s) x 2 harness(es) x {args.reps} rep(s) = {len(jobs) * 2 * args.reps} cell(s) "
          f"(claude model={args.model}, codex model=configured default, timeout={args.timeout}s, "
          f"claude max_budget_usd={args.max_budget_usd}, codex has no dollar-cap flag)")

    run_root = Path(args.run_root).expanduser().resolve() if args.run_root else Path(tempfile.mkdtemp(prefix="cse-bench-cross-harness-"))
    run_root.mkdir(parents=True, exist_ok=True)
    print(f"cross_harness.py: run_root={run_root}")

    if args.dry_run:
        results = []
        for job in jobs:
            for rep in range(1, args.reps + 1):
                record = validate_dry_run(job, run_root, rep)
                results.append(record)
                flag = "OK" if not record["acceptance_check_wiring_problems"] else f"WIRING PROBLEMS: {record['acceptance_check_wiring_problems']}"
                print(f"cross_harness.py: [dry-run] {job['id']} rep{rep} -> {flag}")
        print(f"cross_harness.py: dry-run complete, {len(results)} job(s) materialized on BOTH harnesses and validated, "
              f"0 claude/codex invocations, nothing written to output/.")
        return 0

    stamp = _utc_stamp()
    out_dir = Path(args.out_dir).expanduser().resolve()
    run_dir = out_dir / f"{COLLECTOR_NAME}-runs" / stamp
    run_dir.mkdir(parents=True, exist_ok=True)

    summary_rows = []
    for job in jobs:
        for rep in range(1, args.reps + 1):
            print(f"cross_harness.py: [{job['id']} rep{rep}] running Claude (+framework)...", flush=True)
            claude_result = run_one_job_claude(job, run_root, args.model, args.timeout, args.max_budget_usd, rep)
            print(f"cross_harness.py: [{job['id']} rep{rep}] claude t_working={claude_result['t_working']} "
                  f"({claude_result['duration_seconds']}s, status={claude_result['call_status']})", flush=True)

            print(f"cross_harness.py: [{job['id']} rep{rep}] running Codex (+framework)...", flush=True)
            codex_result = run_one_job_codex(job, run_root, args.timeout, rep)
            print(f"cross_harness.py: [{job['id']} rep{rep}] codex t_working={codex_result['t_working']} "
                  f"({codex_result['duration_seconds']}s, status={codex_result['call_status']})", flush=True)

            behavior_equivalent = claude_result["t_working"] == codex_result["t_working"]
            record = {
                "schema_version": SCHEMA_VERSION,
                "collector": COLLECTOR_NAME,
                "job_id": job["id"],
                "job_title": job["title"],
                "job_discriminates": job.get("discriminates"),
                "rep": rep,
                "claude": claude_result,
                "codex": codex_result,
                "behavior_equivalent": behavior_equivalent,
                "equivalence_definition": (
                    "claude_t_working == codex_t_working, both from job_pack.py's own unmodified "
                    "acceptance_check (see phase-4-cross-harness-behavior.md Sec 2.4)"
                ),
            }
            out_path = run_dir / f"{job['id']}__rep{rep}.json"
            out_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")

            summary_rows.append({
                "job_id": job["id"],
                "discriminates": job.get("discriminates"),
                "claude_t_working": claude_result["t_working"],
                "codex_t_working": codex_result["t_working"],
                "behavior_equivalent": behavior_equivalent,
            })
            print(f"cross_harness.py: [{job['id']} rep{rep}] behavior_equivalent={behavior_equivalent} -> {out_path}", flush=True)

    print("")
    print("cross_harness.py: SUMMARY")
    print(f"{'job':<24} {'discriminates':<12} {'claude':<8} {'codex':<8} {'equivalent':<10}")
    for row in summary_rows:
        print(f"{row['job_id']:<24} {str(row['discriminates']):<12} {str(row['claude_t_working']):<8} "
              f"{str(row['codex_t_working']):<8} {str(row['behavior_equivalent']):<10}")
    all_equivalent = all(row["behavior_equivalent"] for row in summary_rows)
    print(f"cross_harness.py: pack-level behavior_equivalent = {all_equivalent} ({sum(r['behavior_equivalent'] for r in summary_rows)}/{len(summary_rows)} jobs agree)")
    print(f"cross_harness.py: audit records written to {run_dir}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
