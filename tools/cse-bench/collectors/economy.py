"""collectors/economy.py — per-solution token accounting + waste
decomposition (W-2, Phase 4 outcome program, `docs/40-initiatives/
01-cse-auditability/phases/phase-4-outcome-program-prd.md` §3 W-2).

Implements the operational definitions registered in claims.yaml
BEFORE this module was written (V-2), and CORRECTED 2026-07-13 per QA
WP-17 (APPROVED-WITH-MINOR-FIXES) before any O-4 number was ever
quoted -- both fixes registered in claims.yaml's correction commit
BEFORE this code:

  1. Attribution windowing (definitions.solution_token_accounting.
     windowing): a session shared across solutions -- or touched
     intermittently over a long session -- previously had its WHOLE
     transcript total attributed to EVERY solution sharing it. Every
     figure below is now windowed to [min(logged_at), max(logged_at)]
     per (solution, session_id) pair, using solution_sessions' own
     touch timestamps.
  2. Billed-volume vs marginal-spend split (methods.
     transcripts_billed_volume / transcripts_marginal_spend, F-8
     precedent): cumulative-summing cache_read_input_tokens across a
     long session conflates billed API volume with tokens actually
     spent on new work -- the same error class as the falsified "~94%
     less context" figure. Both numbers are now emitted, each labeled;
     the tolerance applies PRIMARILY to marginal_spend.

TWO INDEPENDENT METHODS
------------------------
  - ledger: solutions.tokens_total (claude-copilot tools/tc/, a
    self-reported figure a person types in via `tc solution
    log-usage --tokens N`).
  - transcripts (billed_volume + marginal_spend): for every DISTINCT
    session_id recorded against a solution in the new solution_sessions
    join table (captured automatically by `tc solution` -- see
    tools/tc/src/tc/services/solutions.py's _record_session_touch),
    windowed to that solution's own touch span in that session, the
    sum of billed tokens (billed_volume: input + cache_creation_input +
    cache_read_input + output) and, separately, marginal spend
    (marginal_spend: input + cache_creation_input + output, EXCLUDING
    cache_read_input) across that session's own main + subagent
    transcript files.

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
0 or a guessed percentage. Likewise a solution touched only once (or
whose touches all land in the same instant) yields a near-zero-width
window and near-zero attributed tokens -- disclosed, not padded away
(see definitions.solution_token_accounting.windowing's known
limitation).
"""
from __future__ import annotations

import re
import shutil
import sqlite3
import sys
from datetime import datetime, timezone
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
    find_all_session_files,
    is_subagent_file,
    iter_jsonl_records,
    session_id_for,
    tool_use_blocks,
)

COLLECTOR_NAME = "economy"

# claims.yaml definitions.solution_token_accounting.tolerance -- registered
# BEFORE any real two-method comparison was computed (V-2, TASK-124).
# UNCHANGED by the 2026-07-13 correction commit (QA WP-17): only the
# windowing and the billed_volume/marginal_spend split were added.
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

# solution_sessions.logged_at is SQLite's datetime('now') output: naive
# "YYYY-MM-DD HH:MM:SS", always UTC -- same convention every other
# collector in this package relies on (see collectors/tasksdb.py).
_SQLITE_TS_FORMAT = "%Y-%m-%d %H:%M:%S"


# ---------------------------------------------------------------------------
# Timestamp parsing (both sides of the window comparison: solution_sessions'
# SQLite timestamps and the transcript JSONL's ISO8601 timestamps)
# ---------------------------------------------------------------------------


def _parse_sqlite_ts(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.strptime(value.strip(), _SQLITE_TS_FORMAT).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _parse_jsonl_ts(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _in_window(ts: Optional[datetime], window_start: datetime, window_end: datetime) -> bool:
    return ts is not None and window_start <= ts <= window_end


# ---------------------------------------------------------------------------
# Store discovery (same convention as collectors/solutions.py)
# ---------------------------------------------------------------------------


def _scan_repo_solutions(db_path: Path) -> list[dict]:
    """Read one repo's tasks.db (read-only) for its solutions + their
    joined session TOUCH WINDOWS. Returns [] (not an error) when the store
    predates W-1/W-2 -- an honestly-empty pre-adoption state.

    session_windows: {session_id: {"first_touch": ..., "last_touch": ...}}
    -- min/max solution_sessions.logged_at per (solution, session_id) pair,
    the correction commit's windowing fix (QA WP-17 finding 1).
    """
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA query_only = 1")
        if not _table_exists(conn, "solutions"):
            return []

        session_windows: dict[int, dict[str, dict]] = {}
        if _table_exists(conn, "solution_sessions"):
            for row in conn.execute(
                """SELECT solution_id, session_id,
                          MIN(logged_at) AS first_touch, MAX(logged_at) AS last_touch
                   FROM solution_sessions
                   GROUP BY solution_id, session_id"""
            ).fetchall():
                session_windows.setdefault(row["solution_id"], {})[row["session_id"]] = {
                    "first_touch": row["first_touch"],
                    "last_touch": row["last_touch"],
                }

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
                "session_windows": session_windows.get(row["id"], {}),
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


def _billed_volume(totals: TokenTotals) -> int:
    """input + cache_creation + cache_read + output -- billed API VOLUME,
    what the API metered. See claims.yaml
    definitions.solution_token_accounting.methods.transcripts_billed_volume."""
    return totals.total_context_tokens + totals.output_tokens


def _marginal_spend(totals: TokenTotals) -> int:
    """input + cache_creation + output -- EXCLUDING cache_read (tokens
    re-read from an existing cache, not newly spent). QA WP-17 finding 2,
    F-8 precedent (phase-1-findings.md): billed_volume alone conflates
    cumulative cache-read re-reads with actual new work. See claims.yaml
    definitions.solution_token_accounting.methods.transcripts_marginal_spend."""
    return totals.input_tokens + totals.cache_creation_input_tokens + totals.output_tokens


def _windowed_file_totals(path: Path, window_start: datetime, window_end: datetime) -> TokenTotals:
    """Sum usage across every assistant message in `path` whose OWN
    timestamp falls within [window_start, window_end] -- the per-
    (solution, session) touch window (claims.yaml correction,
    QA WP-17 finding 1)."""
    totals = TokenTotals()
    for rec in iter_jsonl_records(path):
        if rec.get("type") != "assistant":
            continue
        if not _in_window(_parse_jsonl_ts(rec.get("timestamp")), window_start, window_end):
            continue
        usage = (rec.get("message") or {}).get("usage")
        if isinstance(usage, dict):
            totals.add(usage)
    return totals


def _file_touches_window(path: Path, window_start: datetime, window_end: datetime) -> bool:
    """True iff `path` has at least one assistant message timestamped
    inside the window -- used to decide whether a subagent file belongs
    to this solution's windowed delegation history at all."""
    for rec in iter_jsonl_records(path):
        if rec.get("type") != "assistant":
            continue
        if _in_window(_parse_jsonl_ts(rec.get("timestamp")), window_start, window_end):
            return True
    return False


# ---------------------------------------------------------------------------
# Waste decomposition (claims.yaml definitions.waste_decomposition_heuristics)
# ---------------------------------------------------------------------------


def _last_real_assistant_text(path: Path) -> str:
    """Concatenated text blocks of the LAST assistant-role message in the
    FULL transcript file (NOT windowed -- completion is a structural/
    qualitative property of the whole delegated conversation, not a token
    count) -- used to check the completion marker."""
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


def _first_record_timestamp(path: Path) -> str:
    for rec in iter_jsonl_records(path):
        ts = rec.get("timestamp")
        if ts:
            return ts
    return ""


def _windowed_agent_delegation_order(
    main_path: Path, window_start: datetime, window_end: datetime
) -> list[str]:
    """Ordered (chronological, file order) list of subagent_type for every
    Agent/Task tool_use call the main session made WITHIN THE WINDOW."""
    order: list[str] = []
    for rec in iter_jsonl_records(main_path):
        if rec.get("type") != "assistant":
            continue
        if not _in_window(_parse_jsonl_ts(rec.get("timestamp")), window_start, window_end):
            continue
        for b in tool_use_blocks((rec.get("message") or {}).get("content")):
            if b.get("name") in _AGENT_TOOL_NAMES:
                order.append(str((b.get("input") or {}).get("subagent_type") or ""))
    return order


def _waste_for_session(
    main_path: Optional[Path],
    subagent_paths: list[Path],
    window_start: datetime,
    window_end: datetime,
) -> dict:
    """failed_direction/rework token totals for one (solution, session)
    window. See claims.yaml definitions.waste_decomposition_heuristics.categories."""
    delegation_order = (
        _windowed_agent_delegation_order(main_path, window_start, window_end) if main_path else []
    )
    # Only subagent files that actually touch this window belong to this
    # solution's delegation history (QA WP-17 finding 1: an out-of-window
    # subagent file is not this solution's work).
    included = [p for p in subagent_paths if _file_touches_window(p, window_start, window_end)]
    ordered_files = sorted(included, key=_first_record_timestamp)

    failed_direction_tokens = 0
    rework_tokens = 0
    seen_types: set[str] = set()

    for i, path in enumerate(ordered_files):
        subagent_type = delegation_order[i] if i < len(delegation_order) else ""
        tokens = _billed_volume(_windowed_file_totals(path, window_start, window_end))
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


def _re_explaining_tokens(main_path: Path, window_start: datetime, window_end: datetime) -> int:
    """Tokens of every main-session assistant message, WITHIN THE WINDOW,
    that is the first reply to a real user turn whose normalized text
    exactly repeats an earlier real user turn's normalized text in the
    SAME session (the earlier turn need not itself be inside the window --
    the repeat is tracked across the whole session, but only attributed to
    this solution if the resulting reply falls inside its window) -- see
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
            if not _in_window(_parse_jsonl_ts(rec.get("timestamp")), window_start, window_end):
                continue
            usage = (rec.get("message") or {}).get("usage")
            if isinstance(usage, dict):
                tt = TokenTotals()
                tt.add(usage)
                total += _billed_volume(tt)

    return total


# ---------------------------------------------------------------------------
# Per-solution join: ledger vs transcripts (billed_volume + marginal_spend)
# ---------------------------------------------------------------------------


def _empty_waste() -> dict:
    return {
        "failed_direction_tokens": 0,
        "rework_tokens": 0,
        "re_explaining_tokens": 0,
        "waste_total_tokens": 0,
        "waste_share_of_transcript_tokens": None,
    }


def _empty_comparison() -> dict:
    empty = {"delta": None, "delta_pct": None, "agrees_within_tolerance": None}
    return {"vs_marginal_spend": dict(empty), "vs_billed_volume": dict(empty)}


def _solution_transcript_view(session_windows: dict[str, dict], session_index: dict) -> dict:
    billed_total = 0
    marginal_total = 0
    found_any = False
    failed_direction = rework = re_explaining = 0
    sessions_matched: list[str] = []
    sessions_unmatched: list[str] = []
    mismatch_sessions: list[str] = []

    for sid in sorted(session_windows.keys()):
        window = session_windows[sid]
        window_start = _parse_sqlite_ts(window.get("first_touch"))
        window_end = _parse_sqlite_ts(window.get("last_touch"))
        entry = session_index.get(sid)
        if not entry or entry["main"] is None or window_start is None or window_end is None:
            sessions_unmatched.append(sid)
            continue

        sessions_matched.append(sid)
        found_any = True

        combined = _windowed_file_totals(entry["main"], window_start, window_end)
        for sub_path in entry["subagents"]:
            combined = combined.merge(_windowed_file_totals(sub_path, window_start, window_end))
        billed_total += _billed_volume(combined)
        marginal_total += _marginal_spend(combined)

        waste = _waste_for_session(entry["main"], entry["subagents"], window_start, window_end)
        failed_direction += waste["failed_direction_tokens"]
        rework += waste["rework_tokens"]
        if waste["mismatch"]:
            mismatch_sessions.append(sid)
        re_explaining += _re_explaining_tokens(entry["main"], window_start, window_end)

    waste_total = failed_direction + rework + re_explaining
    return {
        "transcripts_billed_volume": billed_total if found_any else None,
        "transcripts_marginal_spend": marginal_total if found_any else None,
        "sessions_matched": sessions_matched,
        "sessions_unmatched": sessions_unmatched,
        "mismatch_sessions": mismatch_sessions,
        "waste": {
            "failed_direction_tokens": failed_direction,
            "rework_tokens": rework,
            "re_explaining_tokens": re_explaining,
            "waste_total_tokens": waste_total,
            "waste_share_of_transcript_tokens": (
                waste_total / billed_total if found_any and billed_total else (0.0 if found_any else None)
            ),
        },
    }


def _compare_one(ledger_tokens: int, value: Optional[int]) -> dict:
    if value is None or value == 0:
        return {"delta": None, "delta_pct": None, "agrees_within_tolerance": None}
    delta = abs((ledger_tokens or 0) - value)
    delta_pct = delta / value
    return {"delta": delta, "delta_pct": delta_pct, "agrees_within_tolerance": delta_pct <= TOLERANCE}


def _compare(ledger_tokens: int, billed_volume: Optional[int], marginal_spend: Optional[int]) -> dict:
    """claims.yaml definitions.solution_token_accounting.tolerance -- applies
    PRIMARILY to vs_marginal_spend (the figure comparable to a person's
    hand-typed estimate); vs_billed_volume is transparency-only and is NOT
    expected to agree at the same order of magnitude (the F-8 conflation
    this correction exists to avoid quoting as the same kind of finding)."""
    return {
        "vs_marginal_spend": _compare_one(ledger_tokens, marginal_spend),
        "vs_billed_volume": _compare_one(ledger_tokens, billed_volume),
    }


_DEFINITIONS_NOTE = {
    "ledger_tokens / transcripts_billed_volume / transcripts_marginal_spend / comparison": (
        "as registered under claims.yaml definitions.solution_token_accounting "
        "(methods.ledger / methods.transcripts_billed_volume / "
        "methods.transcripts_marginal_spend / tolerance). Both transcript figures "
        "are windowed to each solution's own touch span per session "
        "(definitions.solution_token_accounting.windowing). comparison.vs_marginal_spend "
        "is the PRIMARY tolerance check; comparison.vs_billed_volume is transparency-only "
        "and not expected to agree at the same order of magnitude. Both are null when "
        "the corresponding transcript figure is null or 0 -- not a fabricated pass/fail."
    ),
    "waste": (
        "as registered under claims.yaml definitions.waste_decomposition_heuristics "
        "(failed_direction / rework / re_explaining), windowed identically. Summed per "
        "solution across every joined session; waste_share_of_transcript_tokens is null "
        "when transcripts_billed_volume itself is null (no matched session data)."
    ),
    "sessions_unmatched / mismatch_sessions": (
        "sessions_unmatched: a solution_sessions session_id with no matching main "
        "transcript file found in the archive-union-live corpus (not yet synced, "
        "or pruned before the retention job ran), OR whose touch window could not "
        "be parsed. mismatch_sessions: a session where the main file's windowed "
        "Agent/Task tool_use call count did not equal its windowed subagents/ file "
        "count -- the chronological-order attribution "
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
        "transcripts_billed_volume_sum": None,
        "transcripts_marginal_spend_sum": None,
        "waste": _empty_waste(),
    }


def collect(
    glob_pattern: str = DEFAULT_GLOB,
    archive_root: Optional[str] = None,
    live_root: Optional[str] = None,
) -> dict:
    """Scan every Task Copilot store for solutions with joined sessions
    (W-2), independently sum their WINDOWED transcript token usage (both
    billed_volume and marginal_spend), and compare against the
    self-reported ledger figure.

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
    with_sessions = [s for s in all_solutions if s["session_windows"]]

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
        billed_sum_parts: list[int] = []
        marginal_sum_parts: list[int] = []
        agg_failed = agg_rework = agg_re_explain = 0
        n_with_transcript = 0
        n_compared = 0
        n_agree = 0

        for sol in all_solutions:
            if not sol["session_windows"]:
                per_solution_out.append(
                    {
                        **sol,
                        "transcripts_billed_volume": None,
                        "transcripts_marginal_spend": None,
                        "sessions_matched": [],
                        "sessions_unmatched": [],
                        "mismatch_sessions": [],
                        "comparison": _empty_comparison(),
                        "waste": _empty_waste(),
                    }
                )
                continue

            joined = _solution_transcript_view(sol["session_windows"], session_index)
            comparison = _compare(
                sol["ledger_tokens"],
                joined["transcripts_billed_volume"],
                joined["transcripts_marginal_spend"],
            )
            per_solution_out.append({**sol, **joined, "comparison": comparison})

            if joined["transcripts_billed_volume"] is not None:
                n_with_transcript += 1
                ledger_sum_parts.append(sol["ledger_tokens"] or 0)
                billed_sum_parts.append(joined["transcripts_billed_volume"])
                marginal_sum_parts.append(joined["transcripts_marginal_spend"] or 0)
                agg_failed += joined["waste"]["failed_direction_tokens"]
                agg_rework += joined["waste"]["rework_tokens"]
                agg_re_explain += joined["waste"]["re_explaining_tokens"]
                agree = comparison["vs_marginal_spend"]["agrees_within_tolerance"]
                if agree is not None:
                    n_compared += 1
                    if agree:
                        n_agree += 1

        billed_sum = sum(billed_sum_parts) if billed_sum_parts else None
        marginal_sum = sum(marginal_sum_parts) if marginal_sum_parts else None
        waste_total = agg_failed + agg_rework + agg_re_explain
        totals = {
            "solutions_total": len(all_solutions),
            "solutions_with_joined_sessions": len(with_sessions),
            "solutions_with_transcript_match": n_with_transcript,
            "solutions_compared": n_compared,
            "solutions_agreeing_within_tolerance": n_agree,
            "tolerance": TOLERANCE,
            "ledger_tokens_sum": sum(ledger_sum_parts) if ledger_sum_parts else None,
            "transcripts_billed_volume_sum": billed_sum,
            "transcripts_marginal_spend_sum": marginal_sum,
            "waste": {
                "failed_direction_tokens": agg_failed,
                "rework_tokens": agg_rework,
                "re_explaining_tokens": agg_re_explain,
                "waste_total_tokens": waste_total,
                "waste_share_of_transcript_tokens": (waste_total / billed_sum) if billed_sum else None,
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
