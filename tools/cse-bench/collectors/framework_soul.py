"""collectors/framework_soul.py — the framework-SOUL collector.

Measures the development framework (claude-copilot) against its OWN
ratified promises in `claude-copilot/SOUL.md` (STATUS: RATIFIED v1.0,
2026-06-28): context efficiency (Principle 3, "Context Is the Budget")
and process discipline (Principle 2, "Mechanical Enforcement Over Polite
Advice"; Quality Bar's QA-gate non-negotiable).

Serves PRD-9 (CSE Verification & Benchmark Program), task S-2
(TASK-108). Directly answers Phase-1 finding F-8: SOUL §3 Principle 3
(quoted verbatim in SOUL's own Case Law and Language-Rules tables) claims
"~94% less context for externalized work products" with **no measurement
behind it anywhere in the codebase** — this collector is that
measurement. Per SOUL §6's own taste test ("If a claim in a doc or agent
output can't name what measures it, it fails"), this file is what now
measures it.

METRICS
-------
1. ``externalization_ratio`` — the ~94% claim. What WOULD have entered
   main context if a work product's content had been inlined instead
   (token-estimate of every ``work_products.content`` row across every
   ``*/.copilot/tasks.db`` on this machine) vs. what ACTUALLY enters main
   context today (the token-estimate distribution of subagent FINAL-return
   messages, reused unmodified from metric 2). ``savings_ratio = 1 -
   (median_agent_return_tokens / median_wp_tokens)``. See
   ``_build_externalization_ratio`` for the explicit, inspectable
   verdict band and the population-level joining caveat (this is NOT a
   per-work-product before/after — no transcript record links a specific
   agent return to the specific work product it was (or wasn't) stored
   as, so the two distributions are compared as populations, not paired).
2. ``agent_frugality`` — SOUL Quality Bar: "Agents return ~100 tokens to
   the main session; details go to work products." Token-estimate
   distribution (median/mean/p90/% over 300) of every subagent's own
   FINAL assistant message across the merged transcript corpus, plus a
   per-agent-type breakdown.
3. ``main_session_token_trend`` — SOUL drift signal "The Context
   Glutton": "Main-session token use rises release over release."
   Per-ISO-week main-session input+output token totals and per-session
   medians. Primary source is the transcript corpus (has per-session
   granularity, back to 2026-06-09); ``~/.claude/stats-cache.json`` fills
   in weeks the transcript corpus does not cover (it spans back to
   2026-01), at coarser granularity (see that block's own caveat: total
   tokens across all models, not input/output split, and no per-session
   median).
4. ``qa_gate_adherence`` — SOUL Quality Bar non-negotiable: "No
   implementation ships without a @agent-qa pass that carries an
   ARTIFACT: marker (a bare VERDICT: APPROVED does not unblock the
   gate)." Fraction of 'qa'-attributed subagent final returns whose text
   matches the exact marker grammar
   ``claude-copilot/.claude/hooks/subagent-stop.sh``'s ``has_artifact_marker``
   already enforces at runtime (reused as a Python regex, not
   reinvented), plus whatever ``.claude/hooks/state/qa-gate.json`` hook
   state exists to read (claude-copilot's own copy, plus an ecosystem-wide
   scan for the same file in every sibling repo).
5. ``discipline_snapshot`` — re-emitted, not recomputed. Delegation-rate
   and protocol-declaration-rate numbers are collectors/transcripts.py's
   job (register: docs/40-initiatives/01-cse-auditability/claims.yaml);
   this collector reads output/transcripts-latest.json (if that collector
   has already been run) and cites it as a reference, per this program's
   single-source-of-truth rule (README.md "no metric ... may be reported
   without a claims.yaml entry" -- recomputing the same numbers a second
   way here would risk exactly the kind of definitional drift that rule
   exists to prevent).

TOKEN-ESTIMATE METHOD
----------------------
``chars/4`` heuristic throughout (this collector's brief asks for this
method explicitly, not tiktoken -- see ``_token_estimate``). Same
fallback tag tools/cse-bench/benches/mcp_twin/run.py's ``count_tokens``
uses when tiktoken is unavailable (``"heuristic:chars/4"``), used here as
the primary (only) method rather than a fallback, so every number this
module emits carries the same, stated method rather than mixing two.

REUSE (imported via sys.path insertion, not copied -- see
collectors/transcripts.py's own module docstring for why this is the
established pattern in this package)
----------------------------------------------------------------------
  - collectors/tasksdb.py: ``DEFAULT_GLOB`` (the canonical
    ``*/.copilot/tasks.db`` glob) and ``_dedupe_by_real_path`` (the
    symlinked-product-directory dedup this collector would otherwise have
    to reimplement to avoid double-counting a store like
    shared-docs/knowledge-copilot).
  - collectors/transcripts.py: ``DEFAULT_ARCHIVE_ROOT``,
    ``DEFAULT_LIVE_ROOT``, ``_index_jsonl_files``, ``_merge_indexes``,
    ``_build_merged_corpus`` (the archive-UNION-live corpus merge, and
    its rename/staleness handling -- re-deriving this independently would
    risk exactly the F-6 bug that machinery was built to fix) and
    ``_iso_week_key`` (so this collector's ISO-week buckets use the
    identical definition transcripts.py's own weekly aggregation uses).
  - tools/cse-audit/jsonl_utils.py: ``iter_jsonl_records``.
  - tools/cse-audit/session_metrics.py: ``compute_session_metrics``
    (main-session token/turn extraction -- reused unmodified) and
    ``median_iqr``.
  - tools/cse-audit/corpus_scan.py: ``find_main_session_files``.
  - tools/cse-audit/product_usage.py: ``find_all_session_files``,
    ``session_id_for``, ``is_subagent_file``.

NEW LOGIC (not sourced from cse-audit or collectors/transcripts.py)
---------------------------------------------------------------------
  - Subagent FINAL-return extraction (``_extract_final_return``): the
    text of the LAST ``type == "assistant"`` record in a subagent's own
    ``subagents/agent-*.jsonl`` file (all its text-type content blocks
    joined), plus that record's ``attributionAgent`` field (the subagent
    role -- e.g. ``"me"``, ``"qa"``, ``"ta"``). Verified by direct
    inspection (2026-07-13) against a real session: this text matches
    (modulo the small wrapper Claude Code's own tool_result framing
    adds) the ``tool_result`` content the MAIN session actually received
    for that ``Agent``/``Task`` tool call, and it is exactly the
    ``last_assistant_message`` field
    ``claude-copilot/.claude/hooks/subagent-stop.sh``'s SubagentStop hook
    receives on stdin and gates the QA state machine on -- i.e. this is
    what actually enters the parent's context, not a proxy for it.
  - ``ARTIFACT_MARKER_RE``: a direct Python port of
    ``claude-copilot/.claude/hooks/subagent-stop.sh``'s
    ``has_artifact_marker`` grep pattern
    (``^[[:space:]]*ARTIFACT:[[:space:]]+(test-run|file-check|diff-check|adversarial-run)\\|.+$``,
    case-insensitive), so this collector's "does the marker appear" check
    is the same grammar the runtime hook enforces, not an approximation
    of it.
"""
from __future__ import annotations

import glob
import json
import re
import shutil
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Optional

COLLECTOR_NAME = "framework_soul"

# ---------------------------------------------------------------------------
# Reuse tools/cse-audit's corpus-walking code directly, exactly the way
# collectors/transcripts.py does (see that module's own docstring) --
# inserted independently here too so this module works regardless of
# collector import order under cse_bench.py's pkgutil-based discovery.
# ---------------------------------------------------------------------------
_CSE_AUDIT_DIR = Path(__file__).resolve().parents[2] / "cse-audit"
if str(_CSE_AUDIT_DIR) not in sys.path:
    sys.path.insert(0, str(_CSE_AUDIT_DIR))

from corpus_scan import find_main_session_files  # noqa: E402
from jsonl_utils import iter_jsonl_records  # noqa: E402
from product_usage import (  # noqa: E402
    find_all_session_files,
    is_subagent_file,
    session_id_for,
)
from session_metrics import compute_session_metrics, median_iqr  # noqa: E402

from collectors.paths import resolve_copilot_root  # noqa: E402
from collectors.tasksdb import DEFAULT_GLOB as TASKSDB_GLOB  # noqa: E402
from collectors.tasksdb import _dedupe_by_real_path  # noqa: E402
from collectors.transcripts import DEFAULT_ARCHIVE_ROOT  # noqa: E402
from collectors.transcripts import DEFAULT_LIVE_ROOT  # noqa: E402
from collectors.transcripts import _build_merged_corpus  # noqa: E402
from collectors.transcripts import _index_jsonl_files  # noqa: E402
from collectors.transcripts import _iso_week_key  # noqa: E402
from collectors.transcripts import _merge_indexes  # noqa: E402

DEFAULT_STATS_CACHE_PATH = Path.home() / ".claude" / "stats-cache.json"
DEFAULT_QA_GATE_STATE_PATH = (
    resolve_copilot_root() / "claude-copilot" / ".claude" / "hooks" / "state" / "qa-gate.json"
)
DEFAULT_QA_GATE_ECOSYSTEM_GLOB = str(resolve_copilot_root() / "*" / ".claude" / "hooks" / "state" / "qa-gate.json")
DEFAULT_TRANSCRIPTS_LATEST_PATH = Path(__file__).resolve().parents[1] / "output" / "transcripts-latest.json"

TOKEN_ESTIMATE_METHOD = "heuristic:chars/4"

# Direct port of claude-copilot/.claude/hooks/subagent-stop.sh's
# has_artifact_marker: `grep -qiE '^[[:space:]]*ARTIFACT:[[:space:]]+(test-run|file-check|diff-check|adversarial-run)\|.+$'`
# -- re.MULTILINE so `^`/`$` match per line, matching grep's per-line semantics.
ARTIFACT_MARKER_RE = re.compile(
    r"^[ \t]*ARTIFACT:[ \t]+(test-run|file-check|diff-check|adversarial-run)\|.+$",
    re.IGNORECASE | re.MULTILINE,
)

FRUGALITY_THRESHOLD_TOKENS = 300  # SOUL quality bar quotes "~100 tokens"; 300 = 3x that.


def _token_estimate(text: Optional[str]) -> int:
    """chars/4 heuristic token estimate. 0 for empty/None text; otherwise
    at least 1 (mirrors tools/cse-bench/benches/mcp_twin/run.py's
    count_tokens fallback convention of never reporting a non-empty text
    as zero tokens)."""
    n = len(text) if text else 0
    if n == 0:
        return 0
    return max(1, round(n / 4))


def _percentile(sorted_values: list[int], pct: float) -> Optional[float]:
    """Linear-interpolation percentile (numpy's default method) over an
    already-sorted list. None for an empty list; the single value for a
    1-element list."""
    n = len(sorted_values)
    if n == 0:
        return None
    if n == 1:
        return float(sorted_values[0])
    k = (pct / 100.0) * (n - 1)
    f = int(k)
    c = min(f + 1, n - 1)
    if f == c:
        return float(sorted_values[f])
    d = k - f
    return sorted_values[f] + (sorted_values[c] - sorted_values[f]) * d


# ---------------------------------------------------------------------------
# Metric 1 (half): work-product token-estimate distribution, across every
# */.copilot/tasks.db on this machine (same store set & symlink-dedup
# collectors/tasksdb.py's own totals use).
# ---------------------------------------------------------------------------


def _scan_work_products(glob_pattern: str, errors: list[dict]) -> dict:
    raw_paths = sorted(Path(p) for p in glob.glob(glob_pattern))
    deduped = _dedupe_by_real_path(raw_paths)

    wp_tokens: list[int] = []
    wp_tokens_by_type: dict[str, list[int]] = defaultdict(list)
    per_repo: dict[str, dict] = {}
    n_total = 0
    n_with_content = 0
    n_content_null_with_file_path = 0
    n_content_null_no_file_path = 0

    for db_path, repo_name, _aliases in deduped:
        uri = f"file:{db_path}?mode=ro"
        try:
            conn = sqlite3.connect(uri, uri=True, timeout=5)
            try:
                conn.execute("PRAGMA query_only = 1")
                cur = conn.cursor()
                cur.execute("SELECT type, content, file_path FROM work_products")
                rows = cur.fetchall()
            finally:
                conn.close()
        except sqlite3.Error as exc:
            errors.append(
                {"repo": repo_name, "path": str(db_path), "error": f"{type(exc).__name__}: {exc}"}
            )
            continue
        except Exception as exc:  # a single bad store must never crash the run
            errors.append(
                {"repo": repo_name, "path": str(db_path), "error": f"unexpected {type(exc).__name__}: {exc}"}
            )
            continue

        repo_tokens: list[int] = []
        for wp_type, content, file_path in rows:
            n_total += 1
            if content:
                tok = _token_estimate(content)
                wp_tokens.append(tok)
                wp_tokens_by_type[wp_type or "unknown"].append(tok)
                repo_tokens.append(tok)
                n_with_content += 1
            elif file_path:
                n_content_null_with_file_path += 1
            else:
                n_content_null_no_file_path += 1

        per_repo[repo_name] = {
            "n_work_products": len(rows),
            "n_with_inline_content": len(repo_tokens),
            "token_estimate": median_iqr([float(t) for t in repo_tokens]),
        }

    return {
        "source_glob": glob_pattern,
        "repos_scanned": sorted(per_repo.keys()),
        "n_total_work_products": n_total,
        "n_with_inline_content": n_with_content,
        "n_content_null_with_file_path": n_content_null_with_file_path,
        "n_content_null_no_file_path": n_content_null_no_file_path,
        "token_estimate": {
            "method": TOKEN_ESTIMATE_METHOD,
            "overall": median_iqr([float(t) for t in wp_tokens]),
            "by_type": {t: median_iqr([float(v) for v in vals]) for t, vals in sorted(wp_tokens_by_type.items())},
        },
        "per_repo": per_repo,
        "_wp_tokens": wp_tokens,  # stripped before this dict is emitted; internal use only
    }


# ---------------------------------------------------------------------------
# Metric 1 (other half) + Metric 2: subagent FINAL-return extraction.
# Shared corpus walk -- both metrics, and the QA-gate-adherence session
# sets (metric 4), come from one pass over the merged transcript corpus.
# ---------------------------------------------------------------------------


def _joined_text_blocks(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def _extract_final_return(path: Path) -> tuple[Optional[str], Optional[str], int]:
    """Stream one subagent transcript file once. Returns (final_text,
    attribution_agent, n_assistant_msgs): the text of the LAST
    type=="assistant" record (all its text-type content blocks joined)
    and that record's attributionAgent field -- see module docstring's
    NEW LOGIC section for why this is the actual thing the parent session
    receives, not a proxy for it."""
    last_text: Optional[str] = None
    last_agent: Optional[str] = None
    n_assistant = 0
    for rec in iter_jsonl_records(path):
        if rec.get("type") != "assistant":
            continue
        n_assistant += 1
        msg = rec.get("message") or {}
        last_text = _joined_text_blocks(msg.get("content"))
        last_agent = rec.get("attributionAgent")
    return last_text, last_agent, n_assistant


def _scan_subagent_returns(merged_dir: Path, errors: list[dict]) -> dict:
    all_files = find_all_session_files(merged_dir)
    sub_files = [f for f in all_files if is_subagent_file(f, merged_dir)]

    return_tokens: list[int] = []
    tokens_by_agent: dict[str, list[int]] = defaultdict(list)
    n_no_final_text = 0

    qa_returns: list[dict] = []
    sessions_with_me: set[str] = set()
    sessions_with_qa: set[str] = set()

    for f in sub_files:
        try:
            text, agent, n_asst = _extract_final_return(f)
            sid = session_id_for(f, merged_dir)
        except Exception as exc:  # one bad transcript must never crash the run
            errors.append({"session_file": str(f), "error": f"{type(exc).__name__}: {exc}"})
            continue

        if agent == "me":
            sessions_with_me.add(sid)
        elif agent == "qa":
            sessions_with_qa.add(sid)

        if n_asst == 0 or not text:
            n_no_final_text += 1
            continue

        tok = _token_estimate(text)
        return_tokens.append(tok)
        tokens_by_agent[agent or "unknown"].append(tok)

        if agent == "qa":
            qa_returns.append(
                {
                    "session_id": sid,
                    "tokens": tok,
                    "has_artifact_marker": bool(ARTIFACT_MARKER_RE.search(text)),
                }
            )

    sorted_tokens = sorted(return_tokens)
    frugality = median_iqr([float(t) for t in return_tokens])
    frugality.update(
        {
            "p90": _percentile(sorted_tokens, 90),
            "pct_over_threshold": (
                sum(1 for t in return_tokens if t > FRUGALITY_THRESHOLD_TOKENS) / len(return_tokens) * 100.0
                if return_tokens
                else None
            ),
            "threshold_tokens": FRUGALITY_THRESHOLD_TOKENS,
        }
    )

    return {
        "n_subagent_files": len(sub_files),
        "n_no_final_text": n_no_final_text,
        "agent_frugality": frugality,
        "by_agent_type": {
            agent: median_iqr([float(v) for v in vals]) for agent, vals in sorted(tokens_by_agent.items())
        },
        "qa_returns": qa_returns,
        "sessions_with_me_activity": sessions_with_me,
        "sessions_with_qa_activity": sessions_with_qa,
        "_return_tokens": return_tokens,  # stripped before emission; internal use only
    }


def _build_externalization_ratio(wp_scan: dict, sub_scan: dict) -> dict:
    """The ~94% claim (SOUL §3 Principle 3 / Case Law / Language Rules),
    finally measured. See module docstring, metric 1."""
    wp_tokens_stats = wp_scan["token_estimate"]["overall"]
    return_tokens_stats = sub_scan["agent_frugality"]

    median_wp = wp_tokens_stats["median"]
    median_return = return_tokens_stats["median"]
    mean_wp = wp_tokens_stats["mean"]
    mean_return = return_tokens_stats["mean"]

    savings_ratio_median = 1 - (median_return / median_wp) if median_wp and median_return is not None else None
    savings_ratio_mean = 1 - (mean_return / mean_wp) if mean_wp and mean_return is not None else None

    if savings_ratio_median is None:
        verdict = "unmeasurable (insufficient data in one or both distributions)"
    else:
        pct = savings_ratio_median * 100.0
        if pct >= 89.0:  # within 5 points of the ~94% claim
            verdict = f"holds (measured {pct:.1f}%, claim ~94%)"
        elif pct > 0:
            verdict = f"does not hold as stated (measured {pct:.1f}%, claim ~94%) — directionally correct only"
        else:
            verdict = f"falsified (measured {pct:.1f}%) — agent returns are LARGER than work products on this population comparison, not smaller"

    return {
        "claim": "~94% less context for externalized work products (claude-copilot/SOUL.md §3 Principle 3, Case Law, Language Rules)",
        "wp_tokens": {"median": median_wp, "mean": mean_wp, "n": wp_tokens_stats["n"]},
        "agent_return_tokens": {"median": median_return, "mean": mean_return, "n": return_tokens_stats["n"]},
        "savings_ratio_median": savings_ratio_median,
        "savings_ratio_mean": savings_ratio_mean,
        "verdict": verdict,
        "verdict_band": "holds: savings_ratio_median >= 0.89 (within 5pp of 94%); directionally correct: 0 < ratio < 0.89; falsified: ratio <= 0",
        "caveat": (
            "Population-level comparison, not a per-work-product join: no transcript record links a "
            "specific agent's final return to the specific work product (if any) that return's content "
            "was or wasn't stored as. wp_tokens is the token-estimate distribution of every "
            "work_products.content row across every */.copilot/tasks.db on this machine (what WOULD "
            "have entered main context if that content had been inlined instead of externalized); "
            "agent_return_tokens is the token-estimate distribution of every subagent's own final "
            "return message across the merged transcript corpus (what ACTUALLY enters main context "
            "today, reused unmodified from the agent_frugality metric). The two populations are not "
            "drawn from the same underlying work items, are not the same size, and are not date-aligned "
            "(work products persist indefinitely; the transcript corpus has retention limits -- see "
            "collectors/transcripts.py's CORPUS section). This is the best measurement obtainable "
            "without a per-call join key that does not currently exist in either data source."
        ),
        "token_estimate_method": TOKEN_ESTIMATE_METHOD,
    }


# ---------------------------------------------------------------------------
# Metric 3: main-session token trend, per ISO week.
# ---------------------------------------------------------------------------


def _main_session_weekly_from_transcripts(main_files: list[Path], errors: list[dict]) -> dict:
    week_sessions: dict[tuple[int, int], list] = defaultdict(list)
    for mf in main_files:
        try:
            sm = compute_session_metrics(mf)
        except Exception as exc:  # one bad transcript must never crash the run
            errors.append({"session_file": str(mf), "error": f"{type(exc).__name__}: {exc}"})
            continue
        key = _iso_week_key(sm.start_ts)
        if key:
            week_sessions[key].append(sm)

    weekly: dict[str, dict] = {}
    for key, sms in sorted(week_sessions.items()):
        per_session_totals = [float(sm.main_tokens.input_tokens + sm.main_tokens.output_tokens) for sm in sms]
        weekly[f"{key[0]}-W{key[1]:02d}"] = {
            "source": "transcripts",
            "n_sessions": len(sms),
            "input_plus_output_total": sum(int(v) for v in per_session_totals),
            "per_session_input_plus_output": median_iqr(per_session_totals),
        }
    return weekly


def _main_session_weekly_from_stats_cache(stats_cache_path: Path, errors: list[dict]) -> dict:
    if not stats_cache_path.is_file():
        errors.append({"error": f"stats-cache not found at {stats_cache_path}"})
        return {}
    try:
        cache = json.loads(stats_cache_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append({"path": str(stats_cache_path), "error": f"{type(exc).__name__}: {exc}"})
        return {}

    daily_activity = {row.get("date"): row for row in cache.get("dailyActivity", []) if row.get("date")}

    week_token_totals: dict[tuple[int, int], int] = defaultdict(int)
    week_day_counts: dict[tuple[int, int], int] = defaultdict(int)
    week_activity_day_sessions: dict[tuple[int, int], int] = defaultdict(int)

    for row in cache.get("dailyModelTokens", []):
        ds = row.get("date")
        if not ds:
            continue
        try:
            d = datetime.strptime(ds, "%Y-%m-%d").date()
        except ValueError:
            continue
        key = d.isocalendar()[:2]
        week_token_totals[key] += sum(row.get("tokensByModel", {}).values())
        week_day_counts[key] += 1
        week_activity_day_sessions[key] += daily_activity.get(ds, {}).get("sessionCount", 0)

    weekly: dict[str, dict] = {}
    for key, total in sorted(week_token_totals.items()):
        weekly[f"{key[0]}-W{key[1]:02d}"] = {
            "source": "stats_cache",
            "total_tokens_all_models": total,
            "n_days_with_data": week_day_counts[key],
            "activity_day_session_count_sum": week_activity_day_sessions[key],
        }
    return weekly


def _build_main_session_token_trend(main_files: list[Path], stats_cache_path: Path, errors: list[dict]) -> dict:
    from_transcripts = _main_session_weekly_from_transcripts(main_files, errors)
    from_cache = _main_session_weekly_from_stats_cache(stats_cache_path, errors)

    weekly = dict(from_transcripts)
    n_cache_weeks_used = 0
    for wk, entry in from_cache.items():
        if wk not in weekly:
            weekly[wk] = entry
            n_cache_weeks_used += 1

    return {
        "weekly": dict(sorted(weekly.items())),
        "n_weeks_from_transcripts": len(from_transcripts),
        "n_weeks_from_stats_cache_fallback": n_cache_weeks_used,
        "stats_cache_path": str(stats_cache_path),
        "definitions": {
            "transcripts-sourced weeks": (
                "input_plus_output_total / per_session_input_plus_output are sm.main_tokens.input_tokens + "
                "sm.main_tokens.output_tokens per main session (tools/cse-audit/session_metrics.py, reused "
                "unmodified), summed/median'd across sessions whose start_ts ISO-week falls in that week. "
                "Cache-read/cache-creation tokens are excluded (this metric is 'input+output token totals' "
                "as specified, not total billed context)."
            ),
            "stats_cache-sourced weeks": (
                "Used only for ISO weeks with zero main sessions in the merged transcript corpus (the "
                "corpus's raw retention floor -- see collectors/transcripts.py CORPUS docstring -- means "
                "no weeks before ~2026-06-09 have transcript coverage; stats-cache.json spans back to "
                "2026-01). total_tokens_all_models is dailyModelTokens summed for the week and is NOT "
                "split input/output (stats-cache does not record that split) -- it is a coarser, "
                "differently-shaped number than the transcripts-sourced weeks and should not be averaged "
                "into the same series without noting the source field. activity_day_session_count_sum is "
                "dailyActivity.sessionCount summed across that week's days -- per "
                "tools/cse-audit/stats_cache_analysis.py's own documented caveat this is an activity-DAY "
                "count (a session active across N days is counted N times), not a per-session token median; "
                "no per-session median is computable from stats-cache at all, which is why that field is "
                "absent from stats_cache-sourced weeks rather than populated with a misleading proxy."
            ),
        },
    }


# ---------------------------------------------------------------------------
# Metric 4: QA-gate adherence.
# ---------------------------------------------------------------------------


def _build_qa_gate_adherence(sub_scan: dict, errors: list[dict]) -> dict:
    qa_returns = sub_scan["qa_returns"]
    n_qa_returns = len(qa_returns)
    n_with_marker = sum(1 for r in qa_returns if r["has_artifact_marker"])
    artifact_marker_rate = (n_with_marker / n_qa_returns) if n_qa_returns else None

    sessions_with_me = sub_scan["sessions_with_me_activity"]
    sessions_with_qa = sub_scan["sessions_with_qa_activity"]

    return {
        "artifact_marker_rate": artifact_marker_rate,
        "n_qa_returns": n_qa_returns,
        "n_qa_returns_with_artifact_marker": n_with_marker,
        "n_sessions_with_me_activity": len(sessions_with_me),
        "n_sessions_with_qa_activity": len(sessions_with_qa),
        "n_sessions_with_me_or_qa_activity": len(sessions_with_me | sessions_with_qa),
        "n_sessions_with_me_activity_but_no_qa_activity": len(sessions_with_me - sessions_with_qa),
        "marker_grammar": r"^[ \t]*ARTIFACT:[ \t]+(test-run|file-check|diff-check|adversarial-run)\|.+$ (case-insensitive, per line)",
        "marker_grammar_source": "claude-copilot/.claude/hooks/subagent-stop.sh has_artifact_marker (ported verbatim, not reimplemented independently)",
        "hook_state": _scan_qa_gate_state(errors),
        "definitions": {
            "artifact_marker_rate": (
                "of every subagent final-return whose attributionAgent == 'qa' in the merged transcript "
                "corpus, the fraction whose text matches the ARTIFACT: marker grammar above. This is the "
                "SAME text and the SAME grammar claude-copilot's own SubagentStop hook "
                "(.claude/hooks/subagent-stop.sh) evaluates at runtime to decide whether to unblock the "
                "QA gate -- not an approximation of it."
            ),
        },
    }


def _scan_qa_gate_state(errors: list[dict]) -> dict:
    def _summarize(path: Path) -> Optional[dict]:
        if not path.is_file():
            return None
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append({"path": str(path), "error": f"{type(exc).__name__}: {exc}"})
            return None
        if not isinstance(data, dict):
            return {"n_sessions_tracked": None, "n_history_events": None}
        n_history = 0
        n_pending = 0
        for session_data in data.values():
            if isinstance(session_data, dict):
                n_history += len(session_data.get("history") or [])
                n_pending += len(session_data.get("pending_tasks") or [])
        return {"n_sessions_tracked": len(data), "n_history_events": n_history, "n_pending_tasks_total": n_pending}

    primary_summary = _summarize(DEFAULT_QA_GATE_STATE_PATH)
    ecosystem_hits = []
    for p in sorted(Path(m) for m in glob.glob(DEFAULT_QA_GATE_ECOSYSTEM_GLOB)):
        summary = _summarize(p)
        # repo name is 4 path components up from the state file:
        # <repo>/.claude/hooks/state/qa-gate.json
        repo_name = p.parents[3].name
        ecosystem_hits.append({"repo": repo_name, "path": str(p), "summary": summary})

    return {
        "primary_path": str(DEFAULT_QA_GATE_STATE_PATH),
        "primary_exists": DEFAULT_QA_GATE_STATE_PATH.is_file(),
        "primary_summary": primary_summary,
        "ecosystem_glob": DEFAULT_QA_GATE_ECOSYSTEM_GLOB,
        "ecosystem_repos_with_state_file": ecosystem_hits,
        "note": (
            "qa-gate.json is written by claude-copilot/.claude/hooks/subagent-stop.sh's SubagentStop "
            "hook, per repo, only where that hook is installed AND has fired at least once. Absence "
            "(primary_exists == false / an empty ecosystem_repos_with_state_file list) is itself a "
            "finding, not a collector gap -- see memory 'framework-enforcement-not-wired' (the "
            "delegation hook is installed in 1 of 27 repos on this machine as of this program's Phase-1 "
            "audit); this metric reports that same gap for the QA-gate hook specifically, from live "
            "state rather than from the earlier grep-based Phase-1 audit."
        ),
    }


# ---------------------------------------------------------------------------
# Metric 5: discipline snapshot -- re-emitted reference, not recomputed.
# ---------------------------------------------------------------------------


def _read_discipline_snapshot(path: Path, errors: list[dict]) -> dict:
    if not path.is_file():
        return {
            "source_path": str(path),
            "available": False,
            "note": "not yet generated -- run `python3 cse_bench.py collect --only transcripts` first",
        }
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append({"path": str(path), "error": f"{type(exc).__name__}: {exc}"})
        return {"source_path": str(path), "available": False}

    global_scope = ((data.get("metrics") or {}).get("global")) or {}
    return {
        "source_path": str(path),
        "available": True,
        "source_collector": data.get("collector"),
        "source_generated_at": data.get("generated_at"),
        "delegation_rate_tool_share": global_scope.get("delegation_rate_tool_share"),
        "delegation_rate_event_share": global_scope.get("delegation_rate_event_share"),
        "protocol_declaration_rate_loose": global_scope.get("protocol_declaration_rate_loose"),
        "protocol_declaration_rate_strict": global_scope.get("protocol_declaration_rate_strict"),
        "note": (
            "Re-emitted as a reference from collectors/transcripts.py's own latest run, per this "
            "program's single-source-of-truth rule -- NOT recomputed here. See that collector's output "
            "(and docs/40-initiatives/01-cse-auditability/claims.yaml, the operational definitions of "
            "record) for methodology."
        ),
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def collect(
    tasksdb_glob: str = TASKSDB_GLOB,
    archive_root: Optional[str] = None,
    live_root: Optional[str] = None,
    stats_cache_path: Optional[str] = None,
    transcripts_latest_path: Optional[str] = None,
) -> dict:
    """Run the framework-SOUL collector.

    Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []
    archive_root_p = Path(archive_root).expanduser() if archive_root else DEFAULT_ARCHIVE_ROOT
    live_root_p = Path(live_root).expanduser() if live_root else DEFAULT_LIVE_ROOT
    stats_cache_p = Path(stats_cache_path).expanduser() if stats_cache_path else DEFAULT_STATS_CACHE_PATH
    transcripts_latest_p = (
        Path(transcripts_latest_path).expanduser() if transcripts_latest_path else DEFAULT_TRANSCRIPTS_LATEST_PATH
    )

    # --- work products (metric 1, first half) -----------------------------
    wp_scan = _scan_work_products(tasksdb_glob, errors)

    # --- merged transcript corpus (metrics 1-second-half, 2, 3, 4) --------
    archive_files = _index_jsonl_files(archive_root_p)
    live_files = _index_jsonl_files(live_root_p)
    winners, provenance = _merge_indexes(archive_files, live_files)

    corpus_metrics = {
        "archive_root": str(archive_root_p),
        "live_root": str(live_root_p),
        "archive_jsonl_files": len(archive_files),
        "live_jsonl_files": len(live_files),
        "provenance": provenance,
        "merged_distinct_jsonl_files": len(winners),
    }

    if not winners:
        errors.append({"error": "no .jsonl transcripts found under either the archive or live corpus root"})
        metrics = {
            "corpus": corpus_metrics,
            "externalization_ratio": None,
            "agent_frugality": None,
            "main_session_token_trend": None,
            "qa_gate_adherence": None,
            "discipline_snapshot": _read_discipline_snapshot(transcripts_latest_p, errors),
        }
        return {"metrics": metrics, "errors": errors}

    merged_dir = _build_merged_corpus(winners)
    try:
        main_files = find_main_session_files(merged_dir)
        sub_scan = _scan_subagent_returns(merged_dir, errors)

        externalization_ratio = _build_externalization_ratio(wp_scan, sub_scan)
        main_session_token_trend = _build_main_session_token_trend(main_files, stats_cache_p, errors)
        qa_gate_adherence = _build_qa_gate_adherence(sub_scan, errors)
        discipline_snapshot = _read_discipline_snapshot(transcripts_latest_p, errors)

        # Strip internal-only fields before emission.
        wp_scan.pop("_wp_tokens", None)
        agent_frugality = dict(sub_scan["agent_frugality"])
        agent_frugality["n_subagent_files"] = sub_scan["n_subagent_files"]
        agent_frugality["n_no_final_text"] = sub_scan["n_no_final_text"]
        agent_frugality["by_agent_type"] = sub_scan["by_agent_type"]
        agent_frugality["definitions"] = {
            "agent_frugality": (
                "token-estimate (chars/4) of every subagent's own FINAL type=='assistant' record "
                "(all its text-type content blocks joined) across the merged transcript corpus -- one "
                "value per subagent invocation (per subagents/agent-*.jsonl file), regardless of "
                "agent type. threshold_tokens=300 is 3x the SOUL quality bar's stated '~100 tokens'; "
                "pct_over_threshold is the share of returns exceeding it. n_no_final_text counts "
                "subagent files with zero assistant records or an empty final text (excluded from the "
                "distribution, not counted as zero)."
            ),
        }

        metrics = {
            "corpus": corpus_metrics,
            "work_products": wp_scan,
            "externalization_ratio": externalization_ratio,
            "agent_frugality": agent_frugality,
            "main_session_token_trend": main_session_token_trend,
            "qa_gate_adherence": qa_gate_adherence,
            "discipline_snapshot": discipline_snapshot,
        }
        return {"metrics": metrics, "errors": errors}
    finally:
        shutil.rmtree(merged_dir, ignore_errors=True)
