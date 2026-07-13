#!/usr/bin/env python3
"""benches/resume_cost/run.py — S-1 resume-cost bench (TASK-107).

Measures the CSE framework's core job per claude-copilot's SOUL.md §1:
"keep decisions, process, and context from evaporating every time a
session ends — without burning their token budget rebuilding it." Success
signal: "/continue picked up exactly where I left off — no re-explaining."

Two arms, both invoked via headless `claude -p <prompt> --model <model>
--output-format json` (the JSON envelope carries `usage` token counts —
see README.md "Probe call" for the fields this bench reads):

  without — cwd is a fresh, EMPTY tempfile.TemporaryDirectory, no injected
            state. The prompt alone ("You are resuming work on this
            project after a break...") is all the model gets.
  with    — identical empty cwd; the prompt is prefixed with
            fixture/state_block.txt, the REAL, captured `tc progress` +
            `cc memory list --type {context,decision,lesson} --json`
            output from a throwaway store (see build_state.sh) — i.e.
            what .claude/commands/continue.md's "Load Context (Slim)"
            step actually injects, not invented prose.

Both arms get an EMPTY cwd rather than a copy of fixture/invoice_tools/'s
source files. This is a deliberate deviation from a first-draft design
that copied the fixture project's .py files into cwd for both arms: a
live dry run showed the without-arm scoring 3/3 by simply reading those
files with tools — invoice_tools' code (module docstrings, function
names) narrates its own history and plan clearly enough that "no
injected state" was never actually tested; the ablation was measuring
"can Claude read three short files," not "does persisted state matter."
Using an empty cwd for both arms isolates exactly the intended variable
(does the injected state block change the answer) from a confound (can
the model read the codebase) — the same contamination-immunity mechanism
../knowledge_qa/run.py already uses for its empty-cwd without-arm. See
README.md "Design decisions" for the full account, including the actual
without-arm transcript that exposed the leak.

Scoring is deterministic contains-checks (normalized: lowercase, strip
non-alphanumeric, collapse whitespace — same normalize() knowledge_qa's
run.py uses) against three ground-truth elements per response: does it
name (a) the right task, (b) the right completed step, (c) the right next
action. See GROUND_TRUTH below for the accepted variants and
fixture/invoice_tools/*.py's docstrings for why each variant is
"in the code" the fixture represents.

Usage:
    python3 run.py                       # both arms, 3 reps each (default)
    python3 run.py --reps 5              # more reps for tighter CIs
    python3 run.py --arm without --reps 1
    python3 run.py --dry-run             # build prompts, spend no calls

Stdlib only.
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
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

SCHEMA_VERSION = "cse-bench/1"
COLLECTOR_NAME = "bench_resume_cost"
HOST_SCOPE = "single-machine-single-user"

SCRIPT_DIR = Path(__file__).resolve().parent  # .../benches/resume_cost
BENCH_ROOT = SCRIPT_DIR.parent.parent  # .../tools/cse-bench
DEFAULT_FIXTURE_PROJECT_DIR = SCRIPT_DIR / "fixture" / "invoice_tools"
DEFAULT_STATE_BLOCK_PATH = SCRIPT_DIR / "fixture" / "state_block.txt"
DEFAULT_OUT_DIR = BENCH_ROOT / "output"

CLAUDE_BIN = "claude"
DEFAULT_MODEL = "sonnet"
DEFAULT_TIMEOUT_SECONDS = 240  # the without-arm can burn several tool turns exploring cwd
DEFAULT_REPS = 3
DEFAULT_CONCURRENCY = 2

BASE_PROMPT = (
    "You are resuming work on this project after a break. State: "
    "(a) what the current task is, (b) what was already completed, "
    "(c) the next concrete action. Be specific. No tools."
)
# "No tools." is appended to the brief's literal prompt text, mirroring
# ../knowledge_qa/run.py's contamination-immunity convention. A first live
# probe (empty cwd, tools allowed, no "No tools" clause) showed why: given
# the with-arm's state block naming real identifiers ("invoice_tools",
# "utils.py"), the model spent 9 turns / 133s / ~206K tokens searching this
# actual machine's filesystem and found the REAL fixture/invoice_tools/
# this bench ships — this dev machine is not a clean room, the fixture
# really does exist on disk at a discoverable path, so an empty cwd alone
# does not stop a tool-enabled model from reaching it. That run was
# measuring "can Claude find and read the real fixture," not "does the
# injected state block change the answer" — the intended ablation. "No
# tools" closes that path for both arms and also keeps the bench fast and
# low-variance enough for "3 repetitions for stability" to mean something
# (single closed-book inference per call, not an open-ended filesystem
# hunt with highly variable turn count/duration/cost).

# ---------------------------------------------------------------------------
# Ground truth — what a response must contain to count as correct for each
# of the three elements the SOUL success signal names ("picked up exactly
# where I left off"). Every variant is drawn straight from the fixture:
# fixture/invoice_tools/*.py's docstrings and fixture/state_block.txt's
# captured Memory Copilot content name these exact identifiers.
# ---------------------------------------------------------------------------
GROUND_TRUTH: dict[str, list[str]] = {
    "task": ["invoice_tools", "invoice tools", "invoice-tools"],
    "completed": ["validators.py", "validate_invoice_row", "normalize_currency"],
    "next": ["transformers.py", "aggregate_totals", "dedupe_invoices"],
}
ELEMENT_ORDER = ("task", "completed", "next")


# ---------------------------------------------------------------------------
# Scoring — normalized containment match (same convention as
# ../knowledge_qa/run.py's normalize()/score_response()).
# ---------------------------------------------------------------------------


def normalize(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def score_response(text: str) -> dict:
    normalized_response = normalize(text)
    hits = {}
    for element, variants in GROUND_TRUTH.items():
        hits[element] = any(normalize(v) in normalized_response for v in variants)
    hits["score"] = sum(1 for e in ELEMENT_ORDER if hits[e])
    return hits


# ---------------------------------------------------------------------------
# Prompt construction
# ---------------------------------------------------------------------------


def build_prompt(arm: str, state_block: str) -> str:
    if arm == "without":
        return BASE_PROMPT
    if arm == "with":
        return f"{state_block}\n\n---\n\n{BASE_PROMPT}"
    raise ValueError(f"unknown arm: {arm!r}")


# ---------------------------------------------------------------------------
# Claude invocation
# ---------------------------------------------------------------------------


def run_claude(claude_bin: str, prompt: str, model: str, cwd: Path, timeout: int) -> dict:
    import time

    start = time.monotonic()
    try:
        result = subprocess.run(
            [claude_bin, "-p", prompt, "--model", model, "--output-format", "json"],
            cwd=str(cwd),
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
            "error": f"failed to start {claude_bin}: {exc}",
            "duration_seconds": round(time.monotonic() - start, 2),
            "envelope": None,
            "stderr_tail": "",
        }

    duration = round(time.monotonic() - start, 2)
    if result.returncode != 0:
        return {
            "status": "error",
            "text": "",
            "error": f"{claude_bin} exited {result.returncode}: {result.stderr.strip()[:500]}",
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


# ---------------------------------------------------------------------------
# Token/cost extraction — see README.md "Probe call" for field provenance.
# usage.input_tokens is only the NEW (uncached) input for this call; a
# call's real total input also includes cache_creation_input_tokens
# (written fresh into the cache this call) and cache_read_input_tokens
# (served from a prior call's cache). All three are real tokens the API
# processed for this call. total_cost_usd is the API's own dollar figure
# and already accounts for cache read/write being priced differently from
# fresh input, so it is reported alongside the token counts as the single
# most honest "cost" number.
# ---------------------------------------------------------------------------


def extract_usage(envelope: Optional[dict]) -> dict:
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
# Aggregation
# ---------------------------------------------------------------------------


def _mean(values: list) -> Optional[float]:
    vals = [v for v in values if v is not None]
    return round(sum(vals) / len(vals), 2) if vals else None


def aggregate(records: list[dict]) -> dict:
    arms = sorted(set(r["arm"] for r in records))
    by_arm: dict[str, dict] = {}
    for arm in arms:
        arm_records = [r for r in records if r["arm"] == arm]
        scored = [r for r in arm_records if r["status"] == "ok"]
        n = len(arm_records)
        by_arm[arm] = {
            "reps": n,
            "ok": len(scored),
            "errors": n - len(scored),
            "correctness_rate": _mean([r["score"] / len(ELEMENT_ORDER) for r in scored]),
            "full_match_rate": round(
                sum(1 for r in scored if r["score"] == len(ELEMENT_ORDER)) / len(scored), 4
            )
            if scored
            else None,
            "by_element": {
                element: (
                    round(sum(1 for r in scored if r[element]) / len(scored), 4) if scored else None
                )
                for element in ELEMENT_ORDER
            },
            "mean_input_tokens_total": _mean([r["usage"]["input_tokens_total"] for r in scored]),
            "mean_output_tokens": _mean([r["usage"]["output_tokens"] for r in scored]),
            "mean_total_tokens": _mean([r["usage"]["total_tokens"] for r in scored]),
            "mean_total_cost_usd": _mean([r["usage"]["total_cost_usd"] for r in scored]),
            "mean_duration_ms": _mean([r["usage"]["duration_ms"] for r in scored]),
            "mean_num_turns": _mean([r["usage"]["num_turns"] for r in scored]),
        }

    headline: dict[str, Any] = {}
    with_stats = by_arm.get("with")
    without_stats = by_arm.get("without")
    if with_stats and without_stats:
        headline["correctness_with"] = with_stats["correctness_rate"]
        headline["correctness_without"] = without_stats["correctness_rate"]
        headline["correctness_delta"] = (
            round(with_stats["correctness_rate"] - without_stats["correctness_rate"], 4)
            if with_stats["correctness_rate"] is not None and without_stats["correctness_rate"] is not None
            else None
        )
        headline["full_match_rate_with"] = with_stats["full_match_rate"]
        headline["full_match_rate_without"] = without_stats["full_match_rate"]
        headline["mean_total_tokens_with"] = with_stats["mean_total_tokens"]
        headline["mean_total_tokens_without"] = without_stats["mean_total_tokens"]
        headline["token_delta_with_minus_without"] = (
            round(with_stats["mean_total_tokens"] - without_stats["mean_total_tokens"], 2)
            if with_stats["mean_total_tokens"] is not None and without_stats["mean_total_tokens"] is not None
            else None
        )
        headline["mean_cost_usd_with"] = with_stats["mean_total_cost_usd"]
        headline["mean_cost_usd_without"] = without_stats["mean_total_cost_usd"]
        headline["mean_num_turns_with"] = with_stats["mean_num_turns"]
        headline["mean_num_turns_without"] = without_stats["mean_num_turns"]

    return {"headline": headline, "by_arm": by_arm}


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
    payload = json.dumps(envelope, indent=2, sort_keys=True) + "\n"
    stamped.write_text(payload, encoding="utf-8")
    latest.write_text(payload, encoding="utf-8")
    return stamped


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run.py",
        description="S-1 resume-cost bench: with-state vs bare-resume ablation via headless claude -p --output-format json.",
    )
    parser.add_argument("--fixture-dir", default=str(DEFAULT_FIXTURE_PROJECT_DIR), help="Fixture project directory (copied into a fresh cwd per call).")
    parser.add_argument("--state-block", default=str(DEFAULT_STATE_BLOCK_PATH), help="Captured with-arm state block (see build_state.sh).")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Envelope output directory.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Model passed to claude -p (default: {DEFAULT_MODEL}).")
    parser.add_argument("--reps", type=int, default=DEFAULT_REPS, help=f"Repetitions per arm (default: {DEFAULT_REPS}).")
    parser.add_argument("--arm", choices=["with", "without", "both"], default="both", help="Which arm(s) to run.")
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY, help=f"Max concurrent claude calls (default: {DEFAULT_CONCURRENCY}).")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS, help=f"Per-call timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS}).")
    parser.add_argument("--dry-run", action="store_true", help="Build the job list and prompts but never invoke claude.")
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    fixture_dir = Path(args.fixture_dir).expanduser().resolve()
    if not fixture_dir.is_dir():
        print(f"run.py: fixture project dir not found: {fixture_dir}", file=sys.stderr)
        return 1
    fixture_files = sorted(p.name for p in fixture_dir.glob("*.py"))
    if not fixture_files:
        print(f"run.py: no .py files found under {fixture_dir}", file=sys.stderr)
        return 1

    state_block_path = Path(args.state_block).expanduser().resolve()
    try:
        state_block = state_block_path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"run.py: failed to read state block {state_block_path}: {exc}", file=sys.stderr)
        return 1

    arms = ["without", "with"] if args.arm == "both" else [args.arm]
    claude_bin = shutil.which(CLAUDE_BIN)
    if claude_bin is None and not args.dry_run:
        print(f"run.py: '{CLAUDE_BIN}' not found on PATH", file=sys.stderr)
        return 1

    jobs = [(arm, rep) for arm in arms for rep in range(1, args.reps + 1)]
    print(
        f"run.py: fixture={fixture_dir} ({len(fixture_files)} files); "
        f"running {len(arms)} arm(s) x {args.reps} rep(s) = {len(jobs)} calls "
        f"(model={args.model}, concurrency={args.concurrency}, timeout={args.timeout}s)"
    )

    stamp = _utc_stamp()
    out_dir = Path(args.out_dir).expanduser().resolve()
    run_dir = out_dir / f"{COLLECTOR_NAME}-runs" / stamp

    print_lock = threading.Lock()
    completed = 0

    def do_job(job: tuple[str, int]) -> dict:
        nonlocal completed
        arm, rep = job
        prompt = build_prompt(arm, state_block)

        if args.dry_run:
            raw = {"status": "ok", "text": "DRY-RUN", "error": None, "duration_seconds": 0, "envelope": None, "stderr_tail": ""}
        else:
            # Empty cwd for both arms — see module docstring "Both arms get
            # an EMPTY cwd..." for why the fixture's .py files are NOT
            # copied in here (contamination-immunity, not an oversight).
            with tempfile.TemporaryDirectory(prefix="cse-bench-resume-cost-") as tmp:
                raw = run_claude(claude_bin, prompt, args.model, Path(tmp), args.timeout)

        verdict = score_response(raw["text"]) if not args.dry_run else {**{e: False for e in ELEMENT_ORDER}, "score": 0}
        usage = extract_usage(raw["envelope"]) if not args.dry_run else extract_usage(None)

        record = {
            "arm": arm,
            "rep": rep,
            "status": raw["status"],
            "prompt_chars": len(prompt),
            "response_text": raw["text"],
            "error": raw["error"],
            "duration_seconds": raw["duration_seconds"],
            "usage": usage,
            "score": verdict["score"],
            **{e: verdict[e] for e in ELEMENT_ORDER},
        }

        if not args.dry_run:
            run_dir.mkdir(parents=True, exist_ok=True)
            record_path = run_dir / f"{arm}__rep{rep}.json"
            full_record = {**record, "envelope": raw["envelope"], "stderr_tail": raw["stderr_tail"]}
            record_path.write_text(json.dumps(full_record, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        with print_lock:
            completed += 1
            print(f"run.py: [{completed}/{len(jobs)}] {arm} rep{rep} -> score={verdict['score']}/3 status={raw['status']}", flush=True)
        return record

    results: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as pool:
        for record in pool.map(do_job, jobs):
            results.append(record)

    if args.dry_run:
        print(f"run.py: dry-run complete, {len(results)} prompts built, nothing invoked, nothing written to output/.")
        return 0

    aggregated = aggregate(results)
    errors = [
        {"arm": r["arm"], "rep": r["rep"], "error": r["error"]}
        for r in results
        if r["status"] != "ok"
    ]

    state_block_chars = len(state_block)
    metrics = {
        "fixture": {
            "project_dir": str(fixture_dir),
            "files": fixture_files,
            "state_block_path": str(state_block_path),
            "state_block_chars": state_block_chars,
            "state_block_tokens_est": round(state_block_chars / 4),
        },
        "run_params": {
            "model": args.model,
            "arm_filter": args.arm,
            "reps": args.reps,
            "concurrency": args.concurrency,
            "timeout_seconds": args.timeout,
            "calls_made": len(jobs),
            "base_prompt": BASE_PROMPT,
        },
        "ground_truth": GROUND_TRUTH,
        "results": aggregated,
        "run_dir": str(run_dir),
        "definitions": {
            "correctness_rate": "mean(score/3) across an arm's reps, where score counts how many of {task, completed, next} the response's normalized text contains a ground-truth variant for",
            "full_match_rate": "fraction of an arm's reps that scored 3/3 (named the task, the completed step, AND the next action)",
            "by_element": "per-element hit rate (task/completed/next), each independently — a response can get 'next' right while missing 'task', etc.",
            "input_tokens_total": "usage.input_tokens + usage.cache_creation_input_tokens + usage.cache_read_input_tokens — all input tokens the API actually processed for the call, cached or not (usage.input_tokens alone undercounts: prompt-cache hits/writes are real tokens with real, if lower, cost). See README.md 'Probe call'.",
            "state_block_tokens_est": "len(state_block.txt) / 4 — a rough, non-authoritative scale reference only. The authoritative cost of the state block is already inside the with-arm's own input_tokens_total, since the state block is literally prepended to that arm's prompt; this field exists so the overhead isn't hidden, not as a second cost source to add on top.",
            "token_delta_with_minus_without": "headline.mean_total_tokens_with - mean_total_tokens_without. Positive means the injected state cost more tokens than the bare-resume arm spent (right or wrong); negative means the bare-resume arm's tool-call exploration (or verbose hedging) cost MORE than just being told the state upfront — this is the 'token budget rebuilding it' cost SOUL.md describes.",
            "scoring": "normalized containment match: lowercase, strip non-alphanumeric, collapse whitespace, then check whether any of GROUND_TRUTH[element]'s variants is a substring of the normalized response text",
        },
    }

    stamped_path = write_envelope(metrics, errors, out_dir)
    print(f"run.py: wrote {stamped_path}")
    print(f"run.py: wrote {out_dir / (COLLECTOR_NAME + '-latest.json')}")
    print(f"run.py: raw per-call records in {run_dir}")
    headline = aggregated["headline"]
    print(
        "run.py: headline "
        f"correctness_with={headline.get('correctness_with')} "
        f"correctness_without={headline.get('correctness_without')} "
        f"correctness_delta={headline.get('correctness_delta')} "
        f"mean_total_tokens_with={headline.get('mean_total_tokens_with')} "
        f"mean_total_tokens_without={headline.get('mean_total_tokens_without')}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
