#!/usr/bin/env python3
"""benches/knowledge_qa/run.py — B-9 private-fact Q&A bench (TASK-92).

Measures whether Knowledge Copilot's product dossiers change what Claude
answers about a product's private facts (version numbers, internal module
names, canonical config values, former names, internal domains, counts —
see bank.yaml). This is the bench that overturned Phase 1's F-12
"unmeasurable" verdict: F-12's three objections were (1) retrieval isn't
influence, (2) the brand-voice ground truth is prose with no rubric, and
(3) the base model is contaminated on brand voice. None of those objections
apply to closed-book private-fact recall — the correct answer is an
objectively checkable string, and a base model run in an EMPTY directory
has no way to produce it by chance.

Two arms, both invoked via headless `claude -p <prompt> --model <model>`:

  without — cwd is a fresh empty temp directory, prompt has no reference
            material. This is the contamination-immunity mechanism: an
            empty cwd means no CLAUDE.md, no repo file, nothing on disk
            for the CLI to read even if it wanted to reach for a tool
            (the prompt also says "No tools").
  with    — same empty cwd, but the prompt is prefixed with the full text
            of the ONE dossier file bank.yaml's `source` field cites for
            that question ("Using this reference document: ...").

Both arms answer in <=10 words or say UNKNOWN. Scoring is normalized
containment: lowercase, strip punctuation, then check whether the
question's `answer` (or any `accept` variant) appears as a substring of
the normalized response. See score_response()/normalize() below and
README.md "Scoring" for the known false-positive risk on short numeric
answers and how the bank tries to avoid it.

Usage:
    python3 run.py                          # full bank, both arms
    python3 run.py --limit 30                # balanced subset, both arms
    python3 run.py --arm without --limit 10   # one arm only
    python3 run.py --model sonnet --concurrency 4

Stdlib only: PyYAML is used when importable (common on this machine, same
convention as ../../check_claims.py) but a small vendored fallback parser
below covers exactly the flat bank.yaml shape this bench uses, so the
script never hard-requires a pip install.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
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
COLLECTOR_NAME = "bench_knowledge_qa"
HOST_SCOPE = "single-machine-single-user"

SCRIPT_DIR = Path(__file__).resolve().parent  # .../tools/cse-bench/benches/knowledge_qa
BENCH_ROOT = SCRIPT_DIR.parent.parent  # .../tools/cse-bench
DEFAULT_BANK_PATH = SCRIPT_DIR / "bank.yaml"
DEFAULT_OUT_DIR = BENCH_ROOT / "output"
DEFAULT_DOSSIER_ROOT = (
    Path(os.environ.get("CC_KNOWLEDGE_REPO", "/Volumes/Dev/Sites/COPILOT/knowledge-copilot"))
    / "02-products"
    / "04-applications"
)

CLAUDE_BIN = "claude"
DEFAULT_MODEL = "sonnet"
DEFAULT_TIMEOUT_SECONDS = 120
DEFAULT_CONCURRENCY = 4

WITHOUT_PROMPT_TEMPLATE = (
    "Answer this question about the product {dossier} in <=10 words. "
    "If you do not know, say UNKNOWN. No tools. Question: {question}"
)
WITH_PROMPT_TEMPLATE = (
    "Using this reference document:\n\n{reference}\n\n"
    "Answer this question about the product {dossier} in <=10 words. "
    "If you do not know, say UNKNOWN. No tools. Question: {question}"
)

UNKNOWN_MARKERS = (
    "unknown",
    "do not know",
    "dont know",
    "not sure",
    "no idea",
    "cannot determine",
    "cant determine",
    "not specified",
    "not provided",
    "not stated",
)

_SOURCE_RE = re.compile(r"^(?P<dossier>[^/]+)/(?P<relpath>.+):(?P<line>\d+)$")


# ---------------------------------------------------------------------------
# YAML loading — PyYAML if importable, else a small vendored fallback that
# covers exactly bank.yaml's shape (same convention as ../../check_claims.py,
# reimplemented standalone here so this bench has no file dependency on
# tooling another workstream owns).
# ---------------------------------------------------------------------------


def load_bank(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(text)
    except ImportError:
        data = _fallback_load_bank_yaml(text)
    if not isinstance(data, dict) or "questions" not in data:
        raise ValueError(f"{path}: expected a top-level 'questions' key")
    questions = data["questions"]
    if not isinstance(questions, list):
        raise ValueError(f"{path}: 'questions' must be a list")
    for q in questions:
        if not isinstance(q, dict):
            raise ValueError(f"{path}: every question entry must be a mapping")
        for required in ("id", "dossier", "question", "answer", "source"):
            if not q.get(required):
                raise ValueError(f"{path}: question missing required field {required!r}: {q}")
        q.setdefault("accept", [])
        if q["accept"] is None:
            q["accept"] = []
    return questions


def _fallback_load_bank_yaml(text: str) -> dict:
    """Vendored strict-subset parser for exactly bank.yaml's shape:
    a top-level 'questions:' block sequence of flat mappings whose values
    are quoted/bare scalars, except 'accept' which is a flow list ([] or
    [a, b]) or a block list of scalar '- item' lines. Raises ValueError on
    anything outside that subset — it is deliberately not general-purpose.
    """
    lines = text.split("\n")
    i = 0
    n = len(lines)

    def strip_comment(s: str) -> str:
        in_q: Optional[str] = None
        out = []
        for idx, ch in enumerate(s):
            if in_q:
                out.append(ch)
                if ch == in_q:
                    in_q = None
                continue
            if ch in ("'", '"'):
                in_q = ch
                out.append(ch)
                continue
            if ch == "#" and (idx == 0 or s[idx - 1] in " \t"):
                break
            out.append(ch)
        return "".join(out)

    def parse_scalar(tok: str) -> Any:
        tok = tok.strip()
        if tok == "":
            return None
        if len(tok) >= 2 and tok[0] == '"' and tok[-1] == '"':
            return tok[1:-1].replace('\\"', '"')
        if len(tok) >= 2 and tok[0] == "'" and tok[-1] == "'":
            return tok[1:-1].replace("''", "'")
        return tok

    def parse_flow_list(tok: str) -> list:
        inner = tok.strip()[1:-1].strip()
        if inner == "":
            return []
        return [parse_scalar(p) for p in inner.split(",")]

    def next_content_index(start: int) -> Optional[int]:
        j = start
        while j < n:
            s = lines[j].strip()
            if s and not s.startswith("#"):
                return j
            j += 1
        return None

    def indent_of(line: str) -> int:
        return len(line) - len(line.lstrip(" "))

    j = next_content_index(0)
    if j is None or strip_comment(lines[j]).strip() != "questions:":
        raise ValueError("bank.yaml: expected top-level 'questions:' key (fallback parser)")
    i = j + 1

    questions: list[dict] = []
    j = next_content_index(i)
    if j is None:
        return {"questions": questions}
    list_indent = indent_of(lines[j])

    while True:
        j = next_content_index(i)
        if j is None:
            break
        line = lines[j]
        if indent_of(line) != list_indent:
            break
        content = strip_comment(line).strip()
        if not content.startswith("- "):
            break
        body = content[2:]
        key, _, rest = body.partition(":")
        key = key.strip()
        rest = rest.strip()
        entry: dict[str, Any] = {}
        entry_indent = list_indent + 2
        i = j + 1
        entry[key] = _fallback_parse_value(rest, lines, entry_indent, lambda k: (i for i in [None]))
        # Parse continuation keys (including nested 'accept:' block lists).
        while True:
            k = next_content_index(i)
            if k is None:
                break
            kline = lines[k]
            if indent_of(kline) != entry_indent:
                break
            kcontent = strip_comment(kline).strip()
            if kcontent.startswith("- "):
                break
            fkey, _, frest = kcontent.partition(":")
            fkey = fkey.strip()
            frest = frest.strip()
            i = k + 1
            if frest == "":
                # Nested block list (only 'accept' uses this in bank.yaml).
                items: list[str] = []
                while True:
                    m = next_content_index(i)
                    if m is None:
                        break
                    mline = lines[m]
                    if indent_of(mline) <= entry_indent:
                        break
                    mcontent = strip_comment(mline).strip()
                    if not mcontent.startswith("- "):
                        break
                    items.append(parse_scalar(mcontent[2:]))
                    i = m + 1
                entry[fkey] = items
            elif frest.startswith("["):
                entry[fkey] = parse_flow_list(frest)
            else:
                entry[fkey] = parse_scalar(frest)
        questions.append(entry)

    return {"questions": questions}


def _fallback_parse_value(rest: str, lines: list[str], indent: int, _unused) -> Any:
    if rest.startswith("["):
        inner = rest.strip()[1:-1].strip()
        return [] if inner == "" else [p.strip().strip("'\"") for p in inner.split(",")]
    if len(rest) >= 2 and rest[0] == '"' and rest[-1] == '"':
        return rest[1:-1]
    if len(rest) >= 2 and rest[0] == "'" and rest[-1] == "'":
        return rest[1:-1]
    return rest


# ---------------------------------------------------------------------------
# Bank selection
# ---------------------------------------------------------------------------


def select_balanced(questions: list[dict], limit: int) -> list[dict]:
    """Round-robin across dossiers so a --limit run stays balanced instead
    of draining one dossier before touching the next."""
    by_dossier: dict[str, list[dict]] = {}
    order: list[str] = []
    for q in questions:
        d = q["dossier"]
        if d not in by_dossier:
            by_dossier[d] = []
            order.append(d)
        by_dossier[d].append(q)

    selected: list[dict] = []
    idx = 0
    while len(selected) < limit:
        progressed = False
        for d in order:
            bucket = by_dossier[d]
            if idx < len(bucket):
                selected.append(bucket[idx])
                progressed = True
                if len(selected) == limit:
                    break
        if not progressed:
            break
        idx += 1
    return selected


# ---------------------------------------------------------------------------
# Prompt construction
# ---------------------------------------------------------------------------


def resolve_source_file(dossier_root: Path, source: str) -> Path:
    m = _SOURCE_RE.match(source.strip())
    if not m:
        raise ValueError(f"malformed source citation: {source!r}")
    return dossier_root / m.group("dossier") / m.group("relpath")


def build_prompt(
    question: dict,
    arm: str,
    dossier_root: Path,
    reference_cache: dict[Path, str],
    cache_lock: threading.Lock,
) -> str:
    if arm == "without":
        return WITHOUT_PROMPT_TEMPLATE.format(dossier=question["dossier"], question=question["question"])
    if arm == "with":
        source_path = resolve_source_file(dossier_root, question["source"])
        with cache_lock:
            content = reference_cache.get(source_path)
            if content is None:
                content = source_path.read_text(encoding="utf-8")
                reference_cache[source_path] = content
        return WITH_PROMPT_TEMPLATE.format(
            reference=content, dossier=question["dossier"], question=question["question"]
        )
    raise ValueError(f"unknown arm: {arm!r}")


# ---------------------------------------------------------------------------
# Claude invocation
# ---------------------------------------------------------------------------


def run_claude(claude_bin: str, prompt: str, model: str, cwd: Path, timeout: int) -> dict:
    import time

    start = time.monotonic()
    try:
        result = subprocess.run(
            [claude_bin, "-p", prompt, "--model", model],
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
            "returncode": None,
            "stderr_tail": (exc.stderr or "")[-2000:] if isinstance(exc.stderr, str) else "",
        }
    except OSError as exc:
        return {
            "status": "error",
            "text": "",
            "error": f"failed to start {claude_bin}: {exc}",
            "duration_seconds": round(time.monotonic() - start, 2),
            "returncode": None,
            "stderr_tail": "",
        }

    duration = round(time.monotonic() - start, 2)
    if result.returncode != 0:
        return {
            "status": "error",
            "text": "",
            "error": f"{claude_bin} exited {result.returncode}: {result.stderr.strip()[:500]}",
            "duration_seconds": duration,
            "returncode": result.returncode,
            "stderr_tail": result.stderr[-2000:],
        }
    return {
        "status": "ok",
        "text": result.stdout.strip(),
        "error": None,
        "duration_seconds": duration,
        "returncode": result.returncode,
        "stderr_tail": result.stderr[-2000:] if result.stderr else "",
    }


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------


def normalize(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def score_response(raw: dict, question: dict) -> dict:
    if raw["status"] != "ok":
        return {"verdict": "error", "matched_variant": None}
    normalized_response = normalize(raw["text"])
    if not normalized_response:
        return {"verdict": "error", "matched_variant": None}

    variants = [question["answer"], *question.get("accept", [])]
    for variant in variants:
        nv = normalize(str(variant))
        if nv and nv in normalized_response:
            return {"verdict": "correct", "matched_variant": variant}

    for marker in UNKNOWN_MARKERS:
        if marker in normalized_response:
            return {"verdict": "unknown", "matched_variant": None}

    return {"verdict": "incorrect", "matched_variant": None}


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------


def _bucket(records: list[dict]) -> dict:
    total = len(records)
    correct = sum(1 for r in records if r["verdict"] == "correct")
    incorrect = sum(1 for r in records if r["verdict"] == "incorrect")
    unknown = sum(1 for r in records if r["verdict"] == "unknown")
    error = sum(1 for r in records if r["verdict"] == "error")
    scored = total - error
    return {
        "total": total,
        "correct": correct,
        "incorrect": incorrect,
        "unknown": unknown,
        "error": error,
        "accuracy": round(correct / total, 4) if total else None,
        "accuracy_excl_errors": round(correct / scored, 4) if scored else None,
        "unknown_rate": round(unknown / total, 4) if total else None,
        "error_rate": round(error / total, 4) if total else None,
    }


def aggregate(records: list[dict]) -> dict:
    arms = sorted(set(r["arm"] for r in records))
    dossiers = sorted(set(r["dossier"] for r in records))

    by_arm = {arm: _bucket([r for r in records if r["arm"] == arm]) for arm in arms}

    by_dossier: dict[str, dict] = {}
    for dossier in dossiers:
        by_dossier[dossier] = {
            arm: _bucket([r for r in records if r["dossier"] == dossier and r["arm"] == arm])
            for arm in arms
            if any(r["dossier"] == dossier and r["arm"] == arm for r in records)
        }

    headline: dict[str, Any] = {}
    acc_with = by_arm.get("with", {}).get("accuracy")
    acc_without = by_arm.get("without", {}).get("accuracy")
    headline["accuracy_with"] = acc_with
    headline["accuracy_without"] = acc_without
    headline["delta"] = round(acc_with - acc_without, 4) if acc_with is not None and acc_without is not None else None
    headline["unknown_rate_with"] = by_arm.get("with", {}).get("unknown_rate")
    headline["unknown_rate_without"] = by_arm.get("without", {}).get("unknown_rate")

    return {"headline": headline, "by_arm": by_arm, "by_dossier": by_dossier}


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
        description="B-9 private-fact Q&A bench: with-knowledge vs empty-tree ablation via headless claude -p.",
    )
    parser.add_argument("--bank", default=str(DEFAULT_BANK_PATH), help="Path to bank.yaml.")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Envelope output directory.")
    parser.add_argument(
        "--dossier-root",
        default=str(DEFAULT_DOSSIER_ROOT),
        help="Root directory containing <dossier>/<file> paths cited by bank.yaml's 'source' field.",
    )
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Model passed to claude -p (default: {DEFAULT_MODEL}).")
    parser.add_argument("--limit", type=int, default=None, help="Cap the number of questions (balanced across dossiers).")
    parser.add_argument("--arm", choices=["with", "without", "both"], default="both", help="Which arm(s) to run.")
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY, help=f"Max concurrent claude calls (default: {DEFAULT_CONCURRENCY}).")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS, help=f"Per-call timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS}).")
    parser.add_argument("--dry-run", action="store_true", help="Build the job list and prompts but never invoke claude.")
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    bank_path = Path(args.bank).expanduser().resolve()
    try:
        all_questions = load_bank(bank_path)
    except (ValueError, OSError) as exc:
        print(f"run.py: failed to load bank {bank_path}: {exc}", file=sys.stderr)
        return 1

    bank_size = len(all_questions)
    bank_dossiers = sorted(set(q["dossier"] for q in all_questions))

    questions = all_questions
    if args.limit is not None and args.limit < len(questions):
        questions = select_balanced(questions, args.limit)

    arms = ["without", "with"] if args.arm == "both" else [args.arm]
    dossier_root = Path(args.dossier_root).expanduser().resolve()

    claude_bin = shutil.which(CLAUDE_BIN)
    if claude_bin is None and not args.dry_run:
        print(f"run.py: '{CLAUDE_BIN}' not found on PATH", file=sys.stderr)
        return 1

    jobs = [(q, arm) for q in questions for arm in arms]
    print(
        f"run.py: bank={bank_size} questions ({', '.join(bank_dossiers)}); "
        f"running {len(questions)} questions x {len(arms)} arm(s) = {len(jobs)} calls "
        f"(model={args.model}, concurrency={args.concurrency}, timeout={args.timeout}s)"
    )

    stamp = _utc_stamp()
    out_dir = Path(args.out_dir).expanduser().resolve()
    run_dir = out_dir / "bench_knowledge_qa-runs" / stamp

    reference_cache: dict[Path, str] = {}
    cache_lock = threading.Lock()
    print_lock = threading.Lock()
    completed = 0

    def do_job(job: tuple[dict, str]) -> dict:
        nonlocal completed
        question, arm = job
        prompt = build_prompt(question, arm, dossier_root, reference_cache, cache_lock)

        if args.dry_run:
            raw = {"status": "ok", "text": "DRY-RUN", "error": None, "duration_seconds": 0, "returncode": 0, "stderr_tail": ""}
        else:
            with tempfile.TemporaryDirectory(prefix="cse-bench-knowledge-qa-") as tmp:
                raw = run_claude(claude_bin, prompt, args.model, Path(tmp), args.timeout)

        verdict = score_response(raw, question) if not args.dry_run else {"verdict": "dry-run", "matched_variant": None}
        record = {
            "id": question["id"],
            "dossier": question["dossier"],
            "arm": arm,
            "question": question["question"],
            "answer": question["answer"],
            "accept": question.get("accept", []),
            "source": question["source"],
            "prompt_chars": len(prompt),
            "response": raw,
            "verdict": verdict["verdict"],
            "matched_variant": verdict["matched_variant"],
        }

        if not args.dry_run:
            run_dir.mkdir(parents=True, exist_ok=True)
            record_path = run_dir / f"{question['id']}__{arm}.json"
            record_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        with print_lock:
            completed += 1
            print(f"run.py: [{completed}/{len(jobs)}] {question['id']} ({arm}) -> {verdict['verdict']}", flush=True)
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
        {"id": r["id"], "dossier": r["dossier"], "arm": r["arm"], "error": r["response"].get("error")}
        for r in results
        if r["verdict"] == "error"
    ]

    metrics = {
        "bank": {
            "path": str(bank_path),
            "size": bank_size,
            "dossiers": bank_dossiers,
        },
        "run_params": {
            "model": args.model,
            "arm_filter": args.arm,
            "limit": args.limit,
            "concurrency": args.concurrency,
            "timeout_seconds": args.timeout,
            "questions_run": len(questions),
            "calls_made": len(jobs),
            "dossier_root": str(dossier_root),
        },
        "results": aggregated,
        "run_dir": str(run_dir),
        "definitions": {
            "accuracy": "correct / total for the arm (errors count against the denominator)",
            "accuracy_excl_errors": "correct / (total - error) — accuracy among calls that actually returned a response",
            "unknown_rate": "fraction of an arm's answers that were the literal UNKNOWN or an unknown-equivalent phrase (see UNKNOWN_MARKERS in run.py)",
            "delta": "headline.accuracy_with - headline.accuracy_without; positive means the reference document made answers more accurate",
            "scoring": "normalized containment match: lowercase, strip non-alphanumeric, then check whether the question's answer or any accept[] variant is a substring of the normalized response",
        },
    }

    stamped_path = write_envelope(metrics, errors, out_dir)
    print(f"run.py: wrote {stamped_path}")
    print(f"run.py: wrote {out_dir / (COLLECTOR_NAME + '-latest.json')}")
    print(f"run.py: raw per-call responses in {run_dir}")
    headline = aggregated["headline"]
    print(
        "run.py: headline "
        f"accuracy_with={headline.get('accuracy_with')} "
        f"accuracy_without={headline.get('accuracy_without')} "
        f"delta={headline.get('delta')} "
        f"unknown_rate_without={headline.get('unknown_rate_without')}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
