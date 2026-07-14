#!/usr/bin/env python3
"""delegation_harness.py -- the delegation-capable ladder mode.

THE PRE-REGISTERED DEFINITION THIS SCRIPT IMPLEMENTS (V-2, committed BEFORE
this script's first live comparison result was viewed) lives at
../../../../docs/40-initiatives/01-cse-auditability/phases/
phase-4-delegation-capable-harness.md -- read that file first.

WHY THIS EXISTS: `ladder-cannot-measure-framework-agent-layer` (claims.yaml)
found the existing ladder's headless, single-shot `claude -p <brief>`
invocation invokes the Agent/Task tool ZERO times across 72 cells, including
the 3 rungs where the full 13-agent roster was present and available. Three
things were verified live, cheaply, BEFORE this script was written (see the
memo Sec 1 for the full record):

  1. The delegation tool DOES exist and DOES fire under `claude -p` -- when
     explicitly forced ("invoke the Task tool now"), a real Agent tool_use
     call fired and a real subagent (qa) did the work. The tool is named
     "Agent" in this Claude Code CLI version, not "Task" (matching
     tools/cse-audit/session_metrics.py's own AGENT_TOOL_NAMES = {"Agent",
     "Task"} finding) -- so the existing claim's check (name=="Task" only)
     is narrower than the mechanism, though it happens to still report the
     correct zero-count for the actual 72-cell corpus (re-verified: zero
     "Agent" calls too, not just zero "Task" calls).
  2. A genuinely multi-domain brief (security + UX + data-migration, 3
     named specialist concerns, 12 internal turns), with NO explicit
     forcing instruction and NO `/protocol` prefix, still did NOT delegate
     -- job complexity/turn-count alone, within one un-routed `-p` shot,
     is not sufficient.
  3. The SAME multi-domain brief, prefixed with `/protocol ` (the real,
     already-shipped project slash command materialize_framework() already
     copies to every framework-rung workdir -- not a benchmark-specific
     hack), delegated NATURALLY: 5 real Agent tool_use calls (subagent
     types me, sec, cw, qa, me), sensible routing reasoning in the result
     text, all deliverables produced correctly. This isolates the actual
     mechanism: real sessions delegate because they are launched through
     the framework's own routing entry point, which the ladder's raw job
     briefs never invoke.

THIS SCRIPT: reuses configs.py's `framework` / `framework_minus_agents`
rungs VERBATIM (not reimplemented) and job_pack.py's job pack VERBATIM
(same briefs, same acceptance_check, same protected_files) -- the ONE
change is that the brief text handed to `claude -p` is prefixed with a
single, fixed, job-agnostic `/protocol ` string (never tuned per job, never
naming a specific agent). Everything else (model, --dangerously-skip-
permissions, --setting-sources project, timeout, cost ceiling) is identical
to run.py's own existing invocation.

Two invocation modes, matching cross_harness.py's own convention:

    python3 delegation_harness.py --dry-run
        Materializes both rungs for every job, validates job_pack.py and
        acceptance-check wiring. Invokes `claude` ZERO times. Writes
        nothing to output/.

    python3 delegation_harness.py
        The live run. 2 rungs x N jobs x reps cells, each a real `claude -p`
        call. Cost ceiling: --max-budget-usd (native flag, same $3.00/cell
        default as run.py) and --timeout (wall-clock).

No DEC-6 sign-off gate applies here -- this script never scores t_loveable
or touches rubric.md; only each job's own pre-existing mechanical
acceptance_check runs, exactly as the existing ladder's `bare`/`+framework`/
etc. rungs already do.

Stdlib only (see job_pack.py's own docstring for why).
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import configs
import job_pack
import run as ladder_run

SCHEMA_VERSION = "cse-bench/1"
COLLECTOR_NAME = "delegation_harness"

SCRIPT_DIR = Path(__file__).resolve().parent  # .../tools/cse-bench/benches/ladder
BENCH_ROOT = SCRIPT_DIR.parent.parent  # .../tools/cse-bench
DEFAULT_OUT_DIR = BENCH_ROOT / "output"

DEFAULT_MODEL = "sonnet"
DEFAULT_TIMEOUT_SECONDS = 900
DEFAULT_REPS = 1
DEFAULT_MAX_BUDGET_USD = 3.0  # same per-call native ceiling run.py/cross_harness.py already use

PROTOCOL_PREFIX = "/protocol "  # the ONE change vs. the existing ladder's job invocation -- see module docstring

RUNGS = ("framework", "framework_minus_agents")

# Tool names that represent "delegate to a subagent" in a transcript. "Agent"
# is what this Claude Code CLI version actually emits (verified live -- see
# module docstring finding 1); "Task" is the generic/other-version name,
# included defensively, matching tools/cse-audit/session_metrics.py's own
# AGENT_TOOL_NAMES convention (not imported directly, to keep this bench
# self-contained the same way cross_harness.py/codex_harness.py already are).
AGENT_TOOL_NAMES = {"Agent", "Task"}


def _utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def materialize_rung(rung: str, run_root: Path, job_id: str, rep: int) -> configs.MaterializedConfig:
    if rung == "framework":
        return configs.materialize_framework(run_root, job_id, rep)
    if rung == "framework_minus_agents":
        return configs.materialize_framework_minus_agents(run_root, job_id, rep)
    raise ValueError(f"unknown rung {rung!r} -- delegation_harness.py only supports {RUNGS}")


def _sum_usage_dedup(path: Path) -> dict:
    """Sum message.usage across one transcript file's assistant records,
    deduping by message.id the same way run.py's extract_turn_breakdown()
    dedupes the main session (Claude Code re-writes the same message
    multiple times as tool calls stream in)."""
    totals = {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0}
    seen_ids: set = set()
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("type") != "assistant":
                continue
            message = rec.get("message") or {}
            usage = message.get("usage")
            msg_id = message.get("id")
            if not usage or not msg_id or msg_id in seen_ids:
                continue
            seen_ids.add(msg_id)
            for key in totals:
                totals[key] += usage.get(key) or 0
    except OSError:
        pass
    return totals


def extract_delegation_info(home_dir: Path) -> dict:
    """Reads the main session transcript (via run.py's own
    extract_turn_breakdown() for path resolution -- not reimplemented) for
    Agent/Task tool_use blocks, and sums token usage across the sibling
    `<sessionId>/subagents/agent-*.jsonl` files (same corpus-layout
    convention tools/cse-audit/session_metrics.py's own docstring
    documents), so a cell's MAIN-session spend and SUBAGENT spend are
    reported separately, not conflated into one number."""
    tb = ladder_run.extract_turn_breakdown(home_dir)
    empty_tokens = {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0}
    if not tb.get("ok"):
        return {
            "ok": False,
            "error": tb.get("error"),
            "n_agent_delegations": 0,
            "delegated_agent_types": [],
            "main_tool_use_names": [],
            "n_subagent_files": 0,
            "subagent_tokens": empty_tokens,
        }

    transcript_path = Path(tb["transcript_path"])
    main_tool_use_names: list = []
    delegated_agent_types: list = []
    try:
        for line in transcript_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("type") != "assistant":
                continue
            content = (rec.get("message") or {}).get("content") or []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    name = block.get("name")
                    main_tool_use_names.append(name)
                    if name in AGENT_TOOL_NAMES:
                        delegated_agent_types.append((block.get("input") or {}).get("subagent_type"))
    except OSError as exc:
        return {
            "ok": False,
            "error": f"could not read {transcript_path}: {exc}",
            "n_agent_delegations": 0,
            "delegated_agent_types": [],
            "main_tool_use_names": [],
            "n_subagent_files": 0,
            "subagent_tokens": empty_tokens,
        }

    session_id = transcript_path.stem
    subagents_dir = transcript_path.parent / session_id / "subagents"
    subagent_tokens = dict(empty_tokens)
    n_subagent_files = 0
    if subagents_dir.is_dir():
        for sub_path in sorted(subagents_dir.glob("agent-*.jsonl")):
            n_subagent_files += 1
            sub_totals = _sum_usage_dedup(sub_path)
            for key in subagent_tokens:
                subagent_tokens[key] += sub_totals[key]

    return {
        "ok": True,
        "transcript_path": str(transcript_path),
        "main_tool_use_names": main_tool_use_names,
        "n_agent_delegations": len(delegated_agent_types),
        "delegated_agent_types": delegated_agent_types,
        "n_subagent_files": n_subagent_files,
        "subagent_tokens": subagent_tokens,
    }


def run_one_cell(job: dict, rung: str, run_root: Path, model: str, timeout: int, max_budget_usd: Optional[float], rep: int) -> dict:
    cfg = materialize_rung(rung, run_root, job["id"], rep)
    ladder_run.materialize_job_fixture(job, cfg.workdir)
    protected_pre = ladder_run.capture_protected_hashes(job, cfg.workdir)

    brief = PROTOCOL_PREFIX + job["brief"]
    raw = ladder_run.run_claude_job(brief, model, cfg.workdir, cfg.env, cfg.claude_flags, timeout, max_budget_usd)
    usage = ladder_run.extract_usage(raw["envelope"])
    acceptance = ladder_run.run_acceptance_check(job, cfg.workdir, cfg.env)
    protected = ladder_run.check_protected_files(job, cfg.workdir, protected_pre)
    delegation = extract_delegation_info(cfg.home_dir)

    t_working = bool(acceptance["passed"] and protected["clean"])
    return {
        "rung": rung,
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
        "delegation": delegation,
        "workdir": str(cfg.workdir),
        "stderr_tail": raw["stderr_tail"],
        "model": model,
        "brief_prefix": PROTOCOL_PREFIX,
    }


def validate_dry_run(job: dict, run_root: Path, rep: int) -> dict:
    notes = {}
    for rung in RUNGS:
        cfg = materialize_rung(rung, run_root, job["id"], rep)
        ladder_run.materialize_job_fixture(job, cfg.workdir)
        wiring = ladder_run.validate_acceptance_check_wiring(job)
        notes[rung] = {"config_notes": cfg.notes, "config_warnings": cfg.warnings, "wiring_problems": wiring}
    return {"job_id": job["id"], **notes}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Envelope output directory.")
    parser.add_argument("--run-root", default=None, help="Root dir for config/job materialization (default: a fresh tempfile.mkdtemp()).")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Model passed to claude -p (default: {DEFAULT_MODEL}).")
    parser.add_argument("--job", choices=job_pack.JOB_IDS, default=None, help="Restrict to one job (default: all in the pack).")
    parser.add_argument("--rung", choices=RUNGS, default=None, help="Restrict to one rung (default: both framework and framework_minus_agents).")
    parser.add_argument("--reps", type=int, default=DEFAULT_REPS, help=f"Repetitions per (job, rung) (default: {DEFAULT_REPS}).")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS, help=f"Per-call wall-clock timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS}).")
    parser.add_argument("--max-budget-usd", type=float, default=DEFAULT_MAX_BUDGET_USD, help=f"Per-call dollar cap, natively enforced by claude -p's own --max-budget-usd flag (default: {DEFAULT_MAX_BUDGET_USD}).")
    parser.add_argument("--dry-run", action="store_true", help="Materialize both rungs' configs/fixtures and validate wiring, but never invoke claude. Nothing written to output/.")
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    pack_problems = job_pack.validate_job_pack()
    if pack_problems:
        print("delegation_harness.py: job_pack.py FAILED structural validation:", file=sys.stderr)
        for p in pack_problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    jobs = [job_pack.get_job(args.job)] if args.job else job_pack.JOBS
    rungs = [args.rung] if args.rung else list(RUNGS)
    print(f"delegation_harness.py: job_pack.py OK ({len(jobs)} job(s) selected: {', '.join(j['id'] for j in jobs)})")
    n_cells = len(jobs) * len(rungs) * args.reps
    print(f"delegation_harness.py: {len(jobs)} job(s) x {len(rungs)} rung(s) x {args.reps} rep(s) = {n_cells} cell(s) "
          f"(model={args.model}, timeout={args.timeout}s, max_budget_usd={args.max_budget_usd}, "
          f"brief_prefix={PROTOCOL_PREFIX!r})")

    run_root = Path(args.run_root).expanduser().resolve() if args.run_root else Path(tempfile.mkdtemp(prefix="cse-bench-delegation-harness-"))
    run_root.mkdir(parents=True, exist_ok=True)
    print(f"delegation_harness.py: run_root={run_root}")

    if args.dry_run:
        results = []
        for job in jobs:
            for rep in range(1, args.reps + 1):
                record = validate_dry_run(job, run_root, rep)
                results.append(record)
                problems = record["framework"]["wiring_problems"] or record["framework_minus_agents"]["wiring_problems"]
                flag = "OK" if not problems else f"WIRING PROBLEMS: {problems}"
                print(f"delegation_harness.py: [dry-run] {job['id']} rep{rep} -> {flag}")
        print(f"delegation_harness.py: dry-run complete, {len(results)} job(s) materialized on BOTH rungs and validated, "
              f"0 claude invocations, nothing written to output/.")
        return 0

    stamp = _utc_stamp()
    out_dir = Path(args.out_dir).expanduser().resolve()
    run_dir = out_dir / f"{COLLECTOR_NAME}-runs" / stamp
    run_dir.mkdir(parents=True, exist_ok=True)

    summary_rows = []
    for job in jobs:
        for rep in range(1, args.reps + 1):
            cell_results = {}
            for rung in rungs:
                print(f"delegation_harness.py: [{job['id']} rep{rep}] running {rung} (protocol-prefixed)...", flush=True)
                result = run_one_cell(job, rung, run_root, args.model, args.timeout, args.max_budget_usd, rep)
                cell_results[rung] = result
                print(f"delegation_harness.py: [{job['id']} rep{rep}] {rung} t_working={result['t_working']} "
                      f"n_agent_delegations={result['delegation']['n_agent_delegations']} "
                      f"agents={result['delegation']['delegated_agent_types']} "
                      f"({result['duration_seconds']}s, status={result['call_status']})", flush=True)

            record = {
                "schema_version": SCHEMA_VERSION,
                "collector": COLLECTOR_NAME,
                "job_id": job["id"],
                "job_title": job["title"],
                "job_discriminates": job.get("discriminates"),
                "rep": rep,
                "brief_prefix": PROTOCOL_PREFIX,
                **cell_results,
            }
            out_path = run_dir / f"{job['id']}__rep{rep}.json"
            out_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")

            row = {"job_id": job["id"], "discriminates": job.get("discriminates")}
            for rung in rungs:
                row[f"{rung}_t_working"] = cell_results[rung]["t_working"]
                row[f"{rung}_n_delegations"] = cell_results[rung]["delegation"]["n_agent_delegations"]
            if "framework" in cell_results and "framework_minus_agents" in cell_results:
                fw = cell_results["framework"]["t_working"]
                fwma = cell_results["framework_minus_agents"]["t_working"]
                row["agent_layer_effect"] = "helps" if (fw and not fwma) else ("hurts" if (fwma and not fw) else "no_effect")
            summary_rows.append(row)
            print(f"delegation_harness.py: [{job['id']} rep{rep}] -> {out_path}", flush=True)

    print("")
    print("delegation_harness.py: SUMMARY")
    header = f"{'job':<24} {'discriminates':<12}"
    for rung in rungs:
        header += f" {rung + '_t_working':<28} {rung + '_ndeleg':<18}"
    if "framework" in rungs and "framework_minus_agents" in rungs:
        header += f" {'agent_layer_effect':<18}"
    print(header)
    for row in summary_rows:
        line = f"{row['job_id']:<24} {str(row['discriminates']):<12}"
        for rung in rungs:
            line += f" {str(row[f'{rung}_t_working']):<28} {str(row[f'{rung}_n_delegations']):<18}"
        if "agent_layer_effect" in row:
            line += f" {row['agent_layer_effect']:<18}"
        print(line)
    print(f"delegation_harness.py: audit records written to {run_dir}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
