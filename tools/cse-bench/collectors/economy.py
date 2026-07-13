"""collectors/economy.py — per-solution token accounting + waste
decomposition (W-2, Phase 4 outcome program, `docs/40-initiatives/
01-cse-auditability/phases/phase-4-outcome-program-prd.md` §3 W-2).

Implements the operational definitions registered in claims.yaml
BEFORE this module was written (V-2):
`solution_token_accounting` (the two independent methods, their
repo+time+session-id join keys, and the 20% agreement tolerance) and
`waste_decomposition_heuristics` (failed_direction/rework/re_explaining).

TWO INDEPENDENT METHODS
------------------------
  - ledger: solutions.tokens_total (claude-copilot tools/tc/, a
    self-reported figure a person types in via `tc solution
    log-usage --tokens N`).
  - transcripts: for every DISTINCT session_id recorded against a
    solution in the new solution_sessions join table (captured
    automatically by `tc solution` -- see tools/tc/src/tc/services/
    solutions.py's _record_session_touch), the sum of billed tokens
    (input + cache_creation_input + cache_read_input + output) across
    that session's own main + subagent transcript files.

A third source -- "the PostToolUse event ledger from C-3" -- is named
by the PRD but NOT YET BUILT anywhere (see claims.yaml
definitions.solution_token_accounting.methods.event_ledger_c3). This
module compares ledger vs transcripts only.

CORPUS: reuses collectors/transcripts.py's archive-UNION-live corpus
merge machinery directly (not copied) -- same provenance/dedup rules,
same symlinked merged-corpus-directory technique so the cse-audit
corpus-walking helpers run unmodified.

Honesty note: a repo with no `solutions` or `solution_sessions` table
yet, a solution with no joined session, or a session whose transcript
cannot be found in the corpus all produce `null`, never a fabricated
0 or a guessed percentage.
"""
from __future__ import annotations

import re
import shutil
import sqlite3
import sys
from pathlib import Path
from typing import Optional

from collectors.solutions import _table_exists
from collectors.tasksdb import DEFAULT_GLOB, _dedupe_by_real_path
from collectors.transcripts import (
    DEFAULT_ARCHIVE_ROOT,
    DEFAULT_LIVE_ROOT,
    _build_merged_corpus,
    _index_jsonl_files,
    _merge_indexes,
    compute_session_metrics,
    find_all_session_files,
    is_subagent_file,
    iter_jsonl_records,
    session_id_for,
    tool_use_blocks,
)

COLLECTOR_NAME = "economy"

# claims.yaml definitions.solution_token_accounting.tolerance -- registered
# BEFORE any real two-method comparison was computed (V-2, TASK-124).
TOLERANCE = 0.20

# Same tool names session_metrics.AGENT_TOOL_NAMES uses for "delegate to a
# subagent" -- reused as a literal here rather than importing a private
# module constant across two hops.
_AGENT_TOOL_NAMES = {"Agent", "Task"}

# claims.yaml definitions.waste_decomposition_heuristics.categories.failed_direction
_COMPLETE_MARKER = "<promise>COMPLETE</promise>"

# is_real_user_turn / TokenTotals aren't re-exported by collectors.transcripts
# (it doesn't use them directly) -- reused directly from tools/cse-audit via
# the same sys.path-insertion technique transcripts.py itself documents.
_CSE_AUDIT_DIR = Path(__file__).resolve().parents[2] / "cse-audit"
if str(_CSE_AUDIT_DIR) not in sys.path:
    sys.path.insert(0, str(_CSE_AUDIT_DIR))

from jsonl_utils import is_real_user_turn  # noqa: E402
from session_metrics import TokenTotals  # noqa: E402

_WHITESPACE_RE = re.compile(r"\s+")


# ---------------------------------------------------------------------------
# Store discovery (same convention as collectors/solutions.py)
# ---------------------------------------------------------------------------


def _scan_repo_solutions(db_path: Path) -> list[dict]:
    """Read one repo's tasks.db (read-only) for its solutions + their
    joined session ids. Returns [] (not an error) when the store predates
    W-1/W-2 -- an honestly-empty pre-adoption state."""
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA query_only = 1")
        if not _table_exists(conn, "solutions"):
            return []

        session_map: dict[int, set] = {}
        if _table_exists(conn, "solution_sessions"):
            for row in conn.execute(
                "SELECT solution_id, session_id FROM solution_sessions"
            ).fetchall():
                session_map.setdefault(row["solution_id"], set()).add(row["session_id"])

        rows = conn.execute(
            "SELECT id, title, status, tokens_total, sessions_count, brief_locked_at FROM solutions"
        ).fetchall()
        return [
            {
                "solution_id": row["id"],
                "title": row["title"],
                "status": row["status"],
                "ledger_tokens": row["tokens_total"],
                "ledger_sessions_count": row["sessions_count"],
                "brief_locked_at": row["brief_locked_at"],
                "session_ids": sorted(session_map.get(row["id"], set())),
            }
            for row in rows
        ]
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Transcript corpus: index every session file by session_id (main + its
# sibling subagent files), once, for the whole run.
# ---------------------------------------------------------------------------


def _index_sessions_by_id(merged_dir: Path) -> dict[str, dict]:
    index: dict[str, dict] = {}
    for f in find_all_session_files(merged_dir):
        sid = session_id_for(f, merged_dir)
        entry = index.setdefault(sid, {"main": None, "subagents": []})
        if is_subagent_file(f, merged_dir):
            entry["subagents"].append(f)
        else:
            entry["main"] = f
    return index


def _billed_total(totals: TokenTotals) -> int:
    """input + cache_creation + cache_read + output -- every token either
    side of a `tc solution log-usage --tokens` estimate could plausibly be
    counting. See claims.yaml definitions.solution_token_accounting."""
    return totals.total_context_tokens + totals.output_tokens


# ---------------------------------------------------------------------------
# Waste decomposition (claims.yaml definitions.waste_decomposition_heuristics)
# ---------------------------------------------------------------------------


def _last_real_assistant_text(path: Path) -> str:
    """Concatenated text blocks of the LAST assistant-role message in a
    transcript file -- used to check the completion marker."""
    last_text = ""
    for rec in iter_jsonl_records(path):
        if rec.get("type") != "assistant":
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, str):
            last_text = content
        elif isinstance(content, list):
            parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
            if parts:
                last_text = "\n".join(parts)
    return last_text


def _subagent_file_tokens(path: Path) -> TokenTotals:
    """A subagent transcript file's OWN token totals -- independent of
    compute_session_metrics's session-wide aggregation, since waste
    attribution needs per-file granularity."""
    totals = TokenTotals()
    for rec in iter_jsonl_records(path):
        if rec.get("type") != "assistant":
            continue
        usage = (rec.get("message") or {}).get("usage")
        if isinstance(usage, dict):
            totals.add(usage)
    return totals


def _first_record_timestamp(path: Path) -> str:
    for rec in iter_jsonl_records(path):
        ts = rec.get("timestamp")
        if ts:
            return ts
    return ""


def _main_session_agent_delegation_order(main_path: Path) -> list[str]:
    """Ordered (chronological, file order) list of subagent_type for every
    Agent/Task tool_use call the main session made."""
    order: list[str] = []
    for rec in iter_jsonl_records(main_path):
        if rec.get("type") != "assistant":
            continue
        for b in tool_use_blocks((rec.get("message") or {}).get("content")):
            if b.get("name") in _AGENT_TOOL_NAMES:
                order.append(str((b.get("input") or {}).get("subagent_type") or ""))
    return order


def _waste_for_session(main_path: Optional[Path], subagent_paths: list[Path]) -> dict:
    """failed_direction/rework token totals for one session. See
    claims.yaml definitions.waste_decomposition_heuristics.categories."""
    delegation_order = _main_session_agent_delegation_order(main_path) if main_path else []
    ordered_files = sorted(subagent_paths, key=_first_record_timestamp)

    failed_direction_tokens = 0
    rework_tokens = 0
    seen_types: set[str] = set()

    for i, path in enumerate(ordered_files):
        subagent_type = delegation_order[i] if i < len(delegation_order) else ""
        tokens = _billed_total(_subagent_file_tokens(path))
        completed = _COMPLETE_MARKER in _last_real_assistant_text(path)

        if not completed:
            failed_direction_tokens += tokens
        elif subagent_type and subagent_type in seen_types:
            rework_tokens += tokens
        if subagent_type:
            seen_types.add(subagent_type)

    return {
        "failed_direction_tokens": failed_direction_tokens,
        "rework_tokens": rework_tokens,
        "delegation_call_count": len(delegation_order),
        "subagent_file_count": len(ordered_files),
        "mismatch": len(delegation_order) != len(ordered_files),
    }


def _normalize_user_text(text: str) -> str:
    return _WHITESPACE_RE.sub(" ", text.strip().lower())


def _user_turn_text(rec: dict) -> Optional[str]:
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        joined = "\n".join(p for p in parts if p)
        return joined or None
    return None


def _re_explaining_tokens(main_path: Path) -> int:
    """Tokens of every main-session assistant message that is the first
    reply to a real user turn whose normalized text exactly repeats an
    earlier real user turn's normalized text in the SAME session -- see
    claims.yaml definitions.waste_decomposition_heuristics.categories.re_explaining."""
    seen_user_texts: set[str] = set()
    repeat_uuids: set[str] = set()
    total = 0

    for rec in iter_jsonl_records(main_path):
        rtype = rec.get("type")
        if rtype == "user" and is_real_user_turn(rec):
            uuid = rec.get("uuid")
            text = _user_turn_text(rec)
            norm = _normalize_user_text(text) if text else None
            if norm:
                if norm in seen_user_texts and uuid:
                    repeat_uuids.add(uuid)
                seen_user_texts.add(norm)
        elif rtype == "assistant" and rec.get("parentUuid") in repeat_uuids:
            usage = (rec.get("message") or {}).get("usage")
            if isinstance(usage, dict):
                tt = TokenTotals()
                tt.add(usage)
                total += _billed_total(tt)

    return total


# ---------------------------------------------------------------------------
# Per-solution join: ledger vs transcripts
# ---------------------------------------------------------------------------


def _empty_waste() -> dict:
    return {
        "failed_direction_tokens": 0,
        "rework_tokens": 0,
        "re_explaining_tokens": 0,
        "waste_total_tokens": 0,
        "waste_share_of_transcript_tokens": None,
    }


def _solution_transcript_view(session_ids: list[str], session_index: dict) -> dict:
    total_tokens = 0
    found_any = False
    failed_direction = rework = re_explaining = 0
    sessions_matched: list[str] = []
    sessions_unmatched: list[str] = []
    mismatch_sessions: list[str] = []

    for sid in sorted(session_ids):
        entry = session_index.get(sid)
        if not entry or entry["main"] is None:
            sessions_unmatched.append(sid)
            continue

        sessions_matched.append(sid)
        found_any = True
        sm = compute_session_metrics(entry["main"])
        total_tokens += _billed_total(sm.main_tokens) + _billed_total(sm.subagent_tokens)

        waste = _waste_for_session(entry["main"], entry["subagents"])
        failed_direction += waste["failed_direction_tokens"]
        rework += waste["rework_tokens"]
        if waste["mismatch"]:
            mismatch_sessions.append(sid)
        re_explaining += _re_explaining_tokens(entry["main"])

    waste_total = failed_direction + rework + re_explaining
    return {
        "transcript_tokens": total_tokens if found_any else None,
        "sessions_matched": sessions_matched,
        "sessions_unmatched": sessions_unmatched,
        "mismatch_sessions": mismatch_sessions,
        "waste": {
            "failed_direction_tokens": failed_direction,
            "rework_tokens": rework,
            "re_explaining_tokens": re_explaining,
            "waste_total_tokens": waste_total,
            "waste_share_of_transcript_tokens": (
                waste_total / total_tokens if found_any and total_tokens else (0.0 if found_any else None)
            ),
        },
    }


def _compare(ledger_tokens: int, transcript_tokens: Optional[int]) -> dict:
    """claims.yaml definitions.solution_token_accounting.tolerance."""
    if transcript_tokens is None or transcript_tokens == 0:
        return {"delta": None, "delta_pct": None, "agrees_within_tolerance": None}
    delta = abs((ledger_tokens or 0) - transcript_tokens)
    delta_pct = delta / transcript_tokens
    return {
        "delta": delta,
        "delta_pct": delta_pct,
        "agrees_within_tolerance": delta_pct <= TOLERANCE,
    }


_DEFINITIONS_NOTE = {
    "ledger_tokens / transcript_tokens / comparison": (
        "as registered under claims.yaml definitions.solution_token_accounting "
        "(methods.ledger / methods.transcripts / tolerance). comparison is null "
        "when transcript_tokens is null or 0 -- not a fabricated pass/fail."
    ),
    "waste": (
        "as registered under claims.yaml definitions.waste_decomposition_heuristics "
        "(failed_direction / rework / re_explaining). Summed per solution across "
        "every joined session; waste_share_of_transcript_tokens is null when "
        "transcript_tokens itself is null (no matched session data)."
    ),
    "sessions_unmatched / mismatch_sessions": (
        "sessions_unmatched: a solution_sessions session_id with no matching main "
        "transcript file found in the archive-union-live corpus (not yet synced, "
        "or pruned before the retention job ran). mismatch_sessions: a session "
        "where the main file's Agent/Task tool_use call count did not equal its "
        "subagents/ file count -- the chronological-order attribution "
        "(waste_decomposition_heuristics.categories.rework) is approximate for "
        "that session; reported so the approximation stays visible, never hidden."
    ),
}


def _empty_totals(solutions_total: int, solutions_with_sessions: int) -> dict:
    return {
        "solutions_total": solutions_total,
        "solutions_with_joined_sessions": solutions_with_sessions,
        "solutions_with_transcript_match": 0,
        "solutions_compared": 0,
        "solutions_agreeing_within_tolerance": 0,
        "tolerance": TOLERANCE,
        "ledger_tokens_sum": None,
        "transcript_tokens_sum": None,
        "waste": _empty_waste(),
    }


def collect(
    glob_pattern: str = DEFAULT_GLOB,
    archive_root: Optional[str] = None,
    live_root: Optional[str] = None,
) -> dict:
    """Scan every Task Copilot store for solutions with joined sessions
    (W-2), independently sum their transcript token usage, and compare
    against the self-reported ledger figure.

    Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    import glob as glob_mod

    errors: list[dict] = []
    raw_paths = sorted(Path(p) for p in glob_mod.glob(glob_pattern))
    deduped = _dedupe_by_real_path(raw_paths)

    per_repo: dict[str, list[dict]] = {}
    for db_path, repo_name, _aliases in deduped:
        try:
            per_repo[repo_name] = _scan_repo_solutions(db_path)
        except sqlite3.Error as exc:
            errors.append({"repo": repo_name, "path": str(db_path), "error": f"{type(exc).__name__}: {exc}"})
        except Exception as exc:  # a single bad store must never crash the run
            errors.append(
                {"repo": repo_name, "path": str(db_path), "error": f"unexpected {type(exc).__name__}: {exc}"}
            )

    all_solutions = [
        {**sol, "repo": repo_name} for repo_name, sols in per_repo.items() for sol in sols
    ]
    with_sessions = [s for s in all_solutions if s["session_ids"]]

    if not with_sessions:
        metrics = {
            "source_glob": glob_pattern,
            "repos_scanned": sorted(per_repo.keys()),
            "per_solution": [],
            "totals": _empty_totals(len(all_solutions), 0),
            "definitions": _DEFINITIONS_NOTE,
        }
        return {"metrics": metrics, "errors": errors}

    archive_root_p = Path(archive_root).expanduser() if archive_root else DEFAULT_ARCHIVE_ROOT
    live_root_p = Path(live_root).expanduser() if live_root else DEFAULT_LIVE_ROOT
    archive_files = _index_jsonl_files(archive_root_p)
    live_files = _index_jsonl_files(live_root_p)
    winners, provenance = _merge_indexes(archive_files, live_files)

    if not winners:
        errors.append({"error": "no .jsonl transcripts found under either the archive or live corpus root"})
        metrics = {
            "source_glob": glob_pattern,
            "repos_scanned": sorted(per_repo.keys()),
            "per_solution": [],
            "totals": _empty_totals(len(all_solutions), len(with_sessions)),
            "definitions": _DEFINITIONS_NOTE,
        }
        return {"metrics": metrics, "errors": errors}

    merged_dir = _build_merged_corpus(winners)
    try:
        session_index = _index_sessions_by_id(merged_dir)

        per_solution_out = []
        ledger_sum_parts: list[int] = []
        transcript_sum_parts: list[int] = []
        agg_failed = agg_rework = agg_re_explain = 0
        n_with_transcript = 0
        n_compared = 0
        n_agree = 0

        for sol in all_solutions:
            if not sol["session_ids"]:
                per_solution_out.append(
                    {
                        **sol,
                        "transcript_tokens": None,
                        "sessions_matched": [],
                        "sessions_unmatched": [],
                        "mismatch_sessions": [],
                        "comparison": {"delta": None, "delta_pct": None, "agrees_within_tolerance": None},
                        "waste": _empty_waste(),
                    }
                )
                continue

            joined = _solution_transcript_view(sol["session_ids"], session_index)
            comparison = _compare(sol["ledger_tokens"], joined["transcript_tokens"])
            per_solution_out.append({**sol, **joined, "comparison": comparison})

            if joined["transcript_tokens"] is not None:
                n_with_transcript += 1
                ledger_sum_parts.append(sol["ledger_tokens"] or 0)
                transcript_sum_parts.append(joined["transcript_tokens"])
                agg_failed += joined["waste"]["failed_direction_tokens"]
                agg_rework += joined["waste"]["rework_tokens"]
                agg_re_explain += joined["waste"]["re_explaining_tokens"]
                if comparison["agrees_within_tolerance"] is not None:
                    n_compared += 1
                    if comparison["agrees_within_tolerance"]:
                        n_agree += 1

        transcript_sum = sum(transcript_sum_parts) if transcript_sum_parts else None
        waste_total = agg_failed + agg_rework + agg_re_explain
        totals = {
            "solutions_total": len(all_solutions),
            "solutions_with_joined_sessions": len(with_sessions),
            "solutions_with_transcript_match": n_with_transcript,
            "solutions_compared": n_compared,
            "solutions_agreeing_within_tolerance": n_agree,
            "tolerance": TOLERANCE,
            "ledger_tokens_sum": sum(ledger_sum_parts) if ledger_sum_parts else None,
            "transcript_tokens_sum": transcript_sum,
            "waste": {
                "failed_direction_tokens": agg_failed,
                "rework_tokens": agg_rework,
                "re_explaining_tokens": agg_re_explain,
                "waste_total_tokens": waste_total,
                "waste_share_of_transcript_tokens": (waste_total / transcript_sum) if transcript_sum else None,
            },
        }

        metrics = {
            "source_glob": glob_pattern,
            "repos_scanned": sorted(per_repo.keys()),
            "corpus": {
                "archive_root": str(archive_root_p),
                "live_root": str(live_root_p),
                "provenance": provenance,
                "merged_distinct_jsonl_files": len(winners),
            },
            "per_solution": per_solution_out,
            "totals": totals,
            "definitions": _DEFINITIONS_NOTE,
        }
        return {"metrics": metrics, "errors": errors}
    finally:
        shutil.rmtree(merged_dir, ignore_errors=True)
