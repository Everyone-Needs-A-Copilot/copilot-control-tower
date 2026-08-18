#!/usr/bin/env python3
"""run.py -- voice-conformance bench (TASK-93 / B-10).

Runs 6 realistic copywriting tasks through `claude -p ... --model sonnet`
under THREE arms:

  arm_bare            -- task prompt only, no voice guidance at all.
  arm_rules_in_prompt -- task prompt + rules.yaml serialized as plain
                          writing instructions.
  arm_knowledge       -- task prompt + the RAW knowledge-copilot content
                          (02-tone-of-voice.md + cw.extension.md, full
                          text) embedded as a "brand voice reference."

Lints every raw output with lint.py against the same compiled rubric,
aggregates per-arm scores, and writes the cse-bench envelope to
../../output/bench_voice_lint-<stamp>.json (+ -latest.json). Raw
per-call outputs are saved under ../../output/voice_lint-run-<stamp>/
for audit.

THE QUESTION THIS BENCH ANSWERS: does knowledge-copilot's voice content
change model output at all (bare vs knowledge), and does the REPO add
value over just pasting the compiled rules into the prompt (rules vs
knowledge -- the marginal value of the repo-as-context over a much
cheaper "paste the rules" approach)?

CONTAMINATION CONTROL: every `claude -p` call runs with cwd set to a
fresh, empty temp directory (deleted after the call) and `--tools ""`
(all tools disabled) so the model cannot read this repo, the knowledge
repo, or any CLAUDE.md it wouldn't otherwise have in its context window
-- the ONLY voice signal available to arm_rules_in_prompt / arm_knowledge
is what this script explicitly puts in the prompt string.

Usage:
    python3 run.py                  # run all 6 tasks x 3 arms (18 calls)
    python3 run.py --dry-run        # print the 18 prompts, make no calls
    python3 run.py --out DIR        # override output dir (default: ../../output)
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import lint  # noqa: E402

SCHEMA_VERSION = "cse-bench/1"
COLLECTOR_NAME = "bench_voice_lint"
HOST_SCOPE = "single-machine-single-user"

DEFAULT_OUT_DIR = SCRIPT_DIR.parent.parent / "output"
DEFAULT_RULES_PATH = SCRIPT_DIR / "rules.yaml"

KNOWLEDGE_REPO_ROOT = Path("/Volumes/Dev/Sites/CSE/knowledge-copilot-internal")
TONE_OF_VOICE_PATH = KNOWLEDGE_REPO_ROOT / "01-company" / "01-brand" / "02-tone-of-voice.md"
CW_EXTENSION_PATH = KNOWLEDGE_REPO_ROOT / ".claude" / "extensions" / "cw.extension.md"

CLAUDE_BIN = shutil.which("claude") or "/Users/pabs/.local/bin/claude"
MODEL = "sonnet"
TIMEOUT_SECONDS = 120
MAX_CONCURRENT = 4

COMPANY_CONTEXT = (
    "You are writing marketing copy for 'Everyone Needs a Copilot' (brand name "
    "'Copilot'), a boutique consultancy that embeds fractional operators "
    "('copilots') directly inside a client's leadership team to surface the "
    "truths internal teams can't say and drive real organizational breakthroughs, "
    "not slide decks. They contrast themselves against traditional strategy "
    "consulting (e.g. McKinsey): consultants hand you a deck, Copilot hands you a "
    "leadership team that actually executes."
)

WORD_COUNT_INSTRUCTION = (
    "Write between 100 and 180 words. Output ONLY the copy text itself -- no "
    "headers, no markdown formatting, no explanation of what you wrote, no "
    "preamble like 'Here is...'."
)

TASKS = [
    {
        "id": "homepage_intro",
        "title": "Homepage intro",
        "ask": (
            "Write the homepage intro for Everyone Needs a Copilot's website: a hero "
            "line plus a short supporting paragraph that makes a visitor understand "
            "what the company does and why it's different from a normal consulting firm."
        ),
    },
    {
        "id": "linkedin_post",
        "title": "LinkedIn product-launch post",
        "ask": (
            "Write a LinkedIn post announcing the launch of 'CoLab,' Everyone Needs a "
            "Copilot's new 1-2 day leadership alignment workshop, aimed at CEOs and "
            "founders whose leadership teams agree in meetings and then go do their own "
            "thing."
        ),
    },
    {
        "id": "cold_email_opener",
        "title": "Cold-email opener",
        "ask": (
            "Write just the opening paragraph (not a full email, no subject line, no "
            "sign-off) of a cold email from Everyone Needs a Copilot to the CEO of a "
            "mid-market manufacturing company whose leadership team has been stuck on "
            "the same strategy for three years."
        ),
    },
    {
        "id": "case_study_summary",
        "title": "Case-study summary paragraph",
        "ask": (
            "Write a one-paragraph case-study summary describing how Everyone Needs a "
            "Copilot embedded with a regional healthcare system's executive team for "
            "12 weeks, surfaced a hidden turf war between two VPs that was blocking a "
            "merger integration, and got the team to a resolution and a shared plan."
        ),
    },
    {
        "id": "service_blurb",
        "title": "Service one-pager blurb",
        "ask": (
            "Write a one-pager blurb describing Everyone Needs a Copilot's 'CoCreate "
            "Sprint,' a 5-day design sprint where the company's copilots and the "
            "client's team build a working solution together instead of handing over "
            "a report."
        ),
    },
    {
        "id": "about_us",
        "title": "About-us paragraph",
        "ask": (
            "Write the About Us paragraph for Everyone Needs a Copilot's website, "
            "explaining who the company's copilots are (former operators, not career "
            "consultants) and what they promise clients."
        ),
    },
]


def task_prompt(task: dict) -> str:
    return f"{COMPANY_CONTEXT}\n\n{task['ask']}\n\n{WORD_COUNT_INSTRUCTION}"


def render_rules_as_instructions(rules: dict) -> str:
    """Serialize the compiled rules.yaml into plain imperative writing
    instructions (NOT a YAML dump) -- this is arm_rules_in_prompt's payload.
    Generated programmatically from rules.yaml so it stays in sync with the
    compiled rubric rather than drifting as a hand-maintained duplicate."""
    lines: list[str] = ["Follow these voice rules exactly when writing:", ""]

    banned = rules.get("banned_words", {})
    category_labels = {
        "corporate_speak": "Corporate speak",
        "consultant_jargon": "Consultant jargon",
        "hedging": "Hedging language",
        "ai_cliches": "AI clichés",
    }
    lines.append("BANNED WORDS AND PHRASES -- never use any of these:")
    for cat_name, cat_rule in banned.items():
        label = category_labels.get(cat_name, cat_name)
        terms = ", ".join(cat_rule.get("terms", []))
        lines.append(f"- {label}: {terms}")
    lines.append("")

    em_dash = rules.get("em_dash_ban", {})
    lines.append(
        "EM DASHES: " + em_dash.get("rule", "Never use an em dash (—).")
    )
    lines.append("")

    terminology = rules.get("terminology", [])
    if terminology:
        lines.append("TERMINOLOGY -- use the company's preferred term instead of the generic one:")
        for entry in terminology:
            avoid = ", ".join(entry.get("avoid", []))
            use = entry.get("use", "")
            lines.append(f"- Say \"{use}\" instead of: {avoid}")
        lines.append("")

    rhythm = rules.get("rhythm", {})
    lines.append("SENTENCE RHYTHM: " + rhythm.get("rule", "Vary sentence length."))
    lines.append("")

    fk = rules.get("flesch_kincaid", {})
    lo, hi = fk.get("target_grade_min", 6), fk.get("target_grade_max", 8)
    lines.append(
        f"READABILITY: Target a Flesch-Kincaid grade level between {lo} and {hi} "
        "-- write in plain, everyday language."
    )

    return "\n".join(lines)


def build_prompts(rules: dict) -> dict[str, dict[str, str]]:
    """Returns {task_id: {arm_name: full_prompt}}."""
    rules_instructions = render_rules_as_instructions(rules)
    tone_text = TONE_OF_VOICE_PATH.read_text(encoding="utf-8")
    cw_ext_text = CW_EXTENSION_PATH.read_text(encoding="utf-8")
    knowledge_block = (
        "Follow the voice and tone described in the following two documents "
        "(the company's actual internal style guide) exactly.\n\n"
        f"=== {TONE_OF_VOICE_PATH.name} ===\n{tone_text}\n\n"
        f"=== {CW_EXTENSION_PATH.name} ===\n{cw_ext_text}"
    )

    prompts: dict[str, dict[str, str]] = {}
    for task in TASKS:
        base = task_prompt(task)
        prompts[task["id"]] = {
            "arm_bare": base,
            "arm_rules_in_prompt": f"{base}\n\n---\n{rules_instructions}",
            "arm_knowledge": f"{base}\n\n---\n{knowledge_block}",
        }
    return prompts


# ---------------------------------------------------------------------------
# Live calls
# ---------------------------------------------------------------------------


def call_claude(prompt: str) -> dict:
    """One `claude -p <prompt> --model sonnet` call in a fresh, empty,
    tool-disabled cwd. Never raises -- errors are returned in the dict."""
    tmp_dir = Path(tempfile.mkdtemp(prefix="cse-bench-voice-lint-"))
    started = time.monotonic()
    try:
        result = subprocess.run(
            [
                CLAUDE_BIN,
                "-p",
                prompt,
                "--model",
                MODEL,
                "--tools",
                "",
                "--output-format",
                "text",
                "--no-session-persistence",
            ],
            cwd=str(tmp_dir),
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
        duration = time.monotonic() - started
        if result.returncode != 0:
            return {
                "output": None,
                "error": f"non-zero exit {result.returncode}: {result.stderr.strip()[:500]}",
                "duration_s": round(duration, 2),
            }
        return {"output": result.stdout, "error": None, "duration_s": round(duration, 2)}
    except subprocess.TimeoutExpired:
        return {"output": None, "error": f"timed out after {TIMEOUT_SECONDS}s", "duration_s": TIMEOUT_SECONDS}
    except FileNotFoundError as exc:
        return {"output": None, "error": f"binary not found: {exc}", "duration_s": 0.0}
    except OSError as exc:
        return {"output": None, "error": f"unexpected OSError: {exc}", "duration_s": round(time.monotonic() - started, 2)}
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def run_all(prompts: dict[str, dict[str, str]]) -> list[dict]:
    """Runs all task x arm calls, up to MAX_CONCURRENT concurrent."""
    jobs = [
        (task_id, arm, prompt)
        for task_id, arms in prompts.items()
        for arm, prompt in arms.items()
    ]

    results: list[dict] = []
    with ThreadPoolExecutor(max_workers=MAX_CONCURRENT) as pool:
        future_to_job = {pool.submit(call_claude, prompt): (task_id, arm) for task_id, arm, prompt in jobs}
        for future in as_completed(future_to_job):
            task_id, arm = future_to_job[future]
            call_result = future.result()
            results.append({"task_id": task_id, "arm": arm, **call_result})
            status = "ERROR" if call_result["error"] else "ok"
            print(
                f"run.py: {task_id} / {arm}: {status} ({call_result['duration_s']}s)",
                file=sys.stderr,
            )
    return results


# ---------------------------------------------------------------------------
# Scoring / aggregation
# ---------------------------------------------------------------------------

CATEGORY_NAMES = ["corporate_speak", "consultant_jargon", "hedging", "ai_cliches", "em_dash", "terminology", "rhythm"]
ARM_NAMES = ["arm_bare", "arm_rules_in_prompt", "arm_knowledge"]


def score_calls(raw_results: list[dict], rules: dict) -> list[dict]:
    scored = []
    for r in raw_results:
        entry = {"task_id": r["task_id"], "arm": r["arm"], "duration_s": r["duration_s"], "error": r["error"]}
        if r["error"] or not r["output"] or not r["output"].strip():
            entry["error"] = entry["error"] or "empty output"
            entry["report"] = None
        else:
            entry["report"] = lint.lint_text(r["output"], rules)
        scored.append(entry)
    return scored


def _mean(values: list[float]) -> float | None:
    values = [v for v in values if v is not None]
    return round(sum(values) / len(values), 3) if values else None


def summarize_arm(scored: list[dict], arm: str) -> dict:
    calls = [c for c in scored if c["arm"] == arm]
    ok = [c for c in calls if c["report"] is not None]
    n_errors = len(calls) - len(ok)

    categories = {}
    for cat in CATEGORY_NAMES:
        per_100w_values = [c["report"]["categories"][cat]["per_100_words"] for c in ok]
        categories[cat] = {"mean_per_100_words": _mean(per_100w_values), "n": len(ok)}

    total_per_100w_values = [c["report"]["total_violations_per_100_words"] for c in ok]
    fk_grades = [c["report"]["flesch_kincaid"]["grade"] for c in ok if c["report"]["flesch_kincaid"]["grade"] is not None]
    fk_in_band = [c["report"]["flesch_kincaid"]["in_band_6_8"] for c in ok if c["report"]["flesch_kincaid"]["in_band_6_8"] is not None]

    return {
        "n_calls": len(calls),
        "n_ok": len(ok),
        "n_errors": n_errors,
        "mean_total_violations_per_100_words": _mean(total_per_100w_values),
        "categories": categories,
        "flesch_kincaid": {
            "mean_grade": _mean(fk_grades),
            "in_band_6_8_rate": (sum(1 for b in fk_in_band if b) / len(fk_in_band)) if fk_in_band else None,
        },
    }


def build_metrics(scored: list[dict], rules_path: Path) -> dict:
    per_arm = {arm: summarize_arm(scored, arm) for arm in ARM_NAMES}

    def total_or_none(arm: str) -> float | None:
        return per_arm[arm]["mean_total_violations_per_100_words"]

    bare, rules_arm, knowledge = total_or_none("arm_bare"), total_or_none("arm_rules_in_prompt"), total_or_none("arm_knowledge")

    headline = {
        "knowledge_vs_bare_delta_total_violations_per_100_words": (
            round(knowledge - bare, 3) if knowledge is not None and bare is not None else None
        ),
        "knowledge_vs_rules_delta_total_violations_per_100_words": (
            round(knowledge - rules_arm, 3) if knowledge is not None and rules_arm is not None else None
        ),
        "interpretation": (
            "Both deltas are (arm mean violations/100w) minus (comparison arm mean "
            "violations/100w); NEGATIVE means the first-named arm has FEWER "
            "violations per 100 words (better conformance). "
            "knowledge_vs_bare answers 'does the knowledge repo's voice content "
            "change output at all'. knowledge_vs_rules is the sharper question: "
            "the REPO's marginal value over just pasting the compiled rules.yaml "
            "rubric into the prompt -- if this delta is ~0, the repo-as-context is "
            "not earning its keep over a much cheaper rules-in-prompt approach for "
            "THIS negative-space rubric."
        ),
    }

    return {
        "rules_path": str(rules_path),
        "design": {
            "tasks": [{"id": t["id"], "title": t["title"]} for t in TASKS],
            "arms": ARM_NAMES,
            "n_tasks": len(TASKS),
            "n_arms": len(ARM_NAMES),
            "n_calls": len(TASKS) * len(ARM_NAMES),
            "model": MODEL,
            "claude_bin": CLAUDE_BIN,
            "timeout_seconds": TIMEOUT_SECONDS,
            "max_concurrent": MAX_CONCURRENT,
            "contamination_control": "each call runs with cwd=fresh empty temp dir (deleted after) and --tools \"\" (all tools disabled)",
        },
        "per_call": [
            {
                "task_id": c["task_id"],
                "arm": c["arm"],
                "duration_s": c["duration_s"],
                "error": c["error"],
                "word_count": c["report"]["word_count"] if c["report"] else None,
                "total_violations": c["report"]["total_violations"] if c["report"] else None,
                "total_violations_per_100_words": c["report"]["total_violations_per_100_words"] if c["report"] else None,
                "flesch_kincaid": c["report"]["flesch_kincaid"] if c["report"] else None,
                "categories": (
                    {cat: c["report"]["categories"][cat]["count"] for cat in CATEGORY_NAMES} if c["report"] else None
                ),
            }
            for c in scored
        ],
        "per_arm_summary": per_arm,
        "headline": headline,
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="run.py", description="Voice-conformance bench (TASK-93 / B-10).")
    parser.add_argument("--out", default=str(DEFAULT_OUT_DIR), help=f"Output directory (default: {DEFAULT_OUT_DIR}).")
    parser.add_argument("--rules", default=str(DEFAULT_RULES_PATH), help="Path to rules.yaml.")
    parser.add_argument("--dry-run", action="store_true", help="Print the 18 prompts and exit; make no live calls.")
    args = parser.parse_args(argv)

    rules_path = Path(args.rules)
    rules = lint.load_rules(rules_path)
    prompts = build_prompts(rules)

    if args.dry_run:
        for task_id, arms in prompts.items():
            for arm, prompt in arms.items():
                print(f"\n===== {task_id} / {arm} ({len(prompt)} chars) =====")
                print(prompt)
        return 0

    out_dir = Path(args.out).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = _utc_stamp()
    run_dir = out_dir / f"voice_lint-run-{stamp}"
    run_dir.mkdir(parents=True, exist_ok=True)

    print(f"run.py: launching {len(TASKS)} tasks x {len(ARM_NAMES)} arms = {len(TASKS) * len(ARM_NAMES)} calls "
          f"(max {MAX_CONCURRENT} concurrent, {TIMEOUT_SECONDS}s timeout each)", file=sys.stderr)
    raw_results = run_all(prompts)

    # Save raw per-call outputs for audit.
    manifest = []
    for r in raw_results:
        fname = f"{r['task_id']}__{r['arm']}.txt"
        (run_dir / fname).write_text(r["output"] or f"[ERROR] {r['error']}", encoding="utf-8")
        manifest.append({"task_id": r["task_id"], "arm": r["arm"], "file": fname, "error": r["error"], "duration_s": r["duration_s"]})
    (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    scored = score_calls(raw_results, rules)
    metrics = build_metrics(scored, rules_path)
    metrics["raw_run_dir"] = str(run_dir)

    errors = [{"task_id": c["task_id"], "arm": c["arm"], "error": c["error"]} for c in scored if c["error"]]

    envelope = {
        "schema_version": SCHEMA_VERSION,
        "collector": COLLECTOR_NAME,
        "generated_at": _utc_now_iso(),
        "host_scope": HOST_SCOPE,
        "metrics": metrics,
        "errors": errors,
    }

    payload = json.dumps(envelope, indent=2, sort_keys=True) + "\n"
    stamped_path = out_dir / f"{COLLECTOR_NAME}-{stamp}.json"
    latest_path = out_dir / f"{COLLECTOR_NAME}-latest.json"
    stamped_path.write_text(payload, encoding="utf-8")
    latest_path.write_text(payload, encoding="utf-8")

    print(f"run.py: wrote {stamped_path}")
    print(f"run.py: wrote {latest_path}")
    print(f"run.py: raw outputs in {run_dir}")
    print(json.dumps(metrics["headline"], indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
