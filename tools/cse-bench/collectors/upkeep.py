"""collectors/upkeep.py — O-9 Upkeep Tax (Phase 4 outcome program,
phase-4-outcome-program-prd.md par.2: "Time + tokens spent maintaining the
CSE itself (registry, links, freshness, parity sweeps, claim upkeep) per
unit period. Net value = outcomes - upkeep.").

Implements the operational definitions registered in claims.yaml
definitions.upkeep_tax BEFORE this module was written (V-2). Reads the
maintenance-session tagging tables `tc upkeep` writes (claude-copilot
tools/tc/, upkeep_tags / prd_upkeep_flags / upkeep_sessions -- see
tools/tc/src/tc/services/upkeep.py) and emits TWO independent methods,
never conflated:

  - task_count_heuristic: upkeep-tagged tasks / all tasks, in a repo's
    Task Copilot store. Coarse (a share of task COUNT, not of tokens) but
    RETROSPECTIVE -- computable today, over task/PRD history that already
    exists, because `tc upkeep tag-prd` bulk-tags every task already
    filed under a flagged PRD. This is what makes O-9 measurable without
    waiting for anyone to have prospectively tagged sessions as they
    happened.
  - session_token_exact: the token-accountable method. Every DISTINCT
    session_id `tc upkeep tag-task` recorded (upkeep_sessions), joined to
    that session's own transcript (main + subagent files, WHOLE session,
    not windowed -- see module docstring's "windowing" note below for
    why), summed with the SAME marginal_spend/billed_volume formulas
    collectors/economy.py registers (reused directly, not re-implemented,
    so the two collectors can never silently diverge on what "a token"
    means). Netted against the same-shaped figure for solution_sessions
    (the Outcome Ledger's own session touches, W-2) to produce
    upkeep_tax_ratio = upkeep / (upkeep + outcome). Prospective only: a
    session can only be tagged from the moment this feature exists
    onward, so this method is honestly empty until someone runs `tc
    upkeep tag-task` inside a live session.

WINDOWING: unlike W-2's per-solution accounting (collectors/economy.py),
which windows a session's tokens to a solution's own touch span because
one session can be shared across several solutions, one `tc upkeep
tag-task` call is a single whole-session judgment ("this session was
upkeep work") -- there is no shared-session ambiguity to window away, so
this collector sums each tagged session's FULL transcript.

OVERLAP: a session_id present in BOTH upkeep_sessions and solution_sessions
(tagged upkeep AND touched a solution) is ambiguous -- excluded from both
sides of the ratio, reported separately as `overlap_sessions_excluded`,
never silently assigned to either side.

CORPUS: reuses collectors/economy.py's session-by-id index and token
formulas directly (not copied) -- same corpus (archive UNION live), same
provenance/dedup rules.

Honesty note: a repo with no `upkeep_tags`/`upkeep_sessions` tables yet (no
`tc upkeep` command has run there), zero tagged tasks, or zero tagged
sessions all produce `null`/empty, never a fabricated 0% or 100%. No
threshold is registered for either method -- O-9 is a measurement bar, not
a pass/fail bound (unlike O-4's 60/90% band); a high number is a finding
to act on, not a defined failure. See claims.yaml definitions.upkeep_tax.
"""
from __future__ import annotations

import shutil
import sqlite3
from pathlib import Path
from typing import Optional

from collectors.economy import TokenTotals, _billed_volume, _index_sessions_by_id, _marginal_spend
from collectors.solutions import _table_exists
from collectors.tasksdb import DEFAULT_GLOB, _dedupe_by_real_path
from collectors.transcripts import (
    DEFAULT_ARCHIVE_ROOT,
    DEFAULT_LIVE_ROOT,
    _build_merged_corpus,
    _index_jsonl_files,
    _merge_indexes,
    iter_jsonl_records,
)

COLLECTOR_NAME = "upkeep"


def _full_file_totals(path: Path) -> TokenTotals:
    """Sum usage across EVERY assistant message in `path` -- no window (see
    module docstring's WINDOWING note: one tagged session is a single
    whole-session judgment, not a shared/intermittent touch)."""
    totals = TokenTotals()
    for rec in iter_jsonl_records(path):
        if rec.get("type") != "assistant":
            continue
        usage = (rec.get("message") or {}).get("usage")
        if isinstance(usage, dict):
            totals.add(usage)
    return totals


# ---------------------------------------------------------------------------
# Store discovery (same convention as collectors/solutions.py)
# ---------------------------------------------------------------------------


def _empty_repo_result(total_tasks: int = 0) -> dict:
    return {
        "upkeep_instrumentation_present": False,
        "total_tasks": total_tasks,
        "upkeep_tasks": 0,
        "task_count_share": None,
        "by_kind": {},
        "by_method": {},
        "prds_flagged": 0,
        "upkeep_session_ids": [],
        "outcome_session_ids": [],
    }


def _scan_repo_upkeep(db_path: Path) -> dict:
    """Read one repo's tasks.db (read-only) for its upkeep tags + the
    session ids the exact method needs. Returns the pre-adoption honest-
    empty shape (not an error) when `tc upkeep` has never run there."""
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA query_only = 1")
        if not _table_exists(conn, "tasks"):
            return _empty_repo_result()

        total_tasks = conn.execute("SELECT COUNT(*) AS n FROM tasks").fetchone()["n"]

        if not _table_exists(conn, "upkeep_tags"):
            return _empty_repo_result(total_tasks)

        upkeep_tasks = conn.execute("SELECT COUNT(*) AS n FROM upkeep_tags").fetchone()["n"]
        by_kind = {
            row["kind"]: row["n"]
            for row in conn.execute(
                "SELECT kind, COUNT(*) AS n FROM upkeep_tags GROUP BY kind"
            ).fetchall()
        }
        by_method = {
            row["method"]: row["n"]
            for row in conn.execute(
                "SELECT method, COUNT(*) AS n FROM upkeep_tags GROUP BY method"
            ).fetchall()
        }
        prds_flagged = (
            conn.execute("SELECT COUNT(*) AS n FROM prd_upkeep_flags").fetchone()["n"]
            if _table_exists(conn, "prd_upkeep_flags")
            else 0
        )
        upkeep_session_ids = sorted(
            {
                row["session_id"]
                for row in conn.execute(
                    "SELECT DISTINCT session_id FROM upkeep_sessions"
                ).fetchall()
            }
        ) if _table_exists(conn, "upkeep_sessions") else []
        outcome_session_ids = sorted(
            {
                row["session_id"]
                for row in conn.execute(
                    "SELECT DISTINCT session_id FROM solution_sessions"
                ).fetchall()
            }
        ) if _table_exists(conn, "solution_sessions") else []

        return {
            "upkeep_instrumentation_present": True,
            "total_tasks": total_tasks,
            "upkeep_tasks": upkeep_tasks,
            "task_count_share": (upkeep_tasks / total_tasks) if total_tasks else None,
            "by_kind": by_kind,
            "by_method": by_method,
            "prds_flagged": prds_flagged,
            "upkeep_session_ids": upkeep_session_ids,
            "outcome_session_ids": outcome_session_ids,
        }
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# session_token_exact: join tagged session ids to the transcript corpus
# ---------------------------------------------------------------------------


def _sum_sessions(ids: list[str], session_index: dict) -> dict:
    billed = marginal = 0
    matched: list[str] = []
    unmatched: list[str] = []
    for sid in ids:
        entry = session_index.get(sid)
        if not entry or entry["main"] is None:
            unmatched.append(sid)
            continue
        matched.append(sid)
        combined = _full_file_totals(entry["main"])
        for sub_path in entry["subagents"]:
            combined = combined.merge(_full_file_totals(sub_path))
        billed += _billed_volume(combined)
        marginal += _marginal_spend(combined)
    return {
        "sessions_matched": matched,
        "sessions_unmatched": unmatched,
        "tokens_billed_volume": billed if matched else None,
        "tokens_marginal_spend": marginal if matched else None,
    }


def _empty_exact_method() -> dict:
    return {
        "overlap_sessions_excluded": [],
        "upkeep": {"sessions_matched": [], "sessions_unmatched": [], "tokens_billed_volume": None, "tokens_marginal_spend": None},
        "outcome": {"sessions_matched": [], "sessions_unmatched": [], "tokens_billed_volume": None, "tokens_marginal_spend": None},
        "upkeep_tax_ratio_marginal_spend": None,
    }


def _exact_method_for_repo(entry: dict, session_index: dict) -> dict:
    upkeep_ids = set(entry["upkeep_session_ids"])
    outcome_ids = set(entry["outcome_session_ids"])
    overlap = sorted(upkeep_ids & outcome_ids)
    pure_upkeep = sorted(upkeep_ids - outcome_ids)
    pure_outcome = sorted(outcome_ids - upkeep_ids)

    upkeep_totals = _sum_sessions(pure_upkeep, session_index)
    outcome_totals = _sum_sessions(pure_outcome, session_index)

    u = upkeep_totals["tokens_marginal_spend"]
    o = outcome_totals["tokens_marginal_spend"]
    denom = (u or 0) + (o or 0)
    ratio = (u or 0) / denom if denom else None

    return {
        "overlap_sessions_excluded": overlap,
        "upkeep": upkeep_totals,
        "outcome": outcome_totals,
        "upkeep_tax_ratio_marginal_spend": ratio,
    }


_DEFINITIONS_NOTE = {
    "task_count_share": (
        "as registered under claims.yaml definitions.upkeep_tax.methods.task_count_heuristic "
        "-- upkeep_tasks / total_tasks in a repo's Task Copilot store. A share of TASK COUNT, "
        "not of tokens; retrospective (computable over pre-existing task/PRD history via "
        "`tc upkeep tag-prd`)."
    ),
    "session_token_exact": (
        "as registered under claims.yaml definitions.upkeep_tax.methods.session_token_exact "
        "-- upkeep_tax_ratio_marginal_spend = upkeep_tokens / (upkeep_tokens + outcome_tokens), "
        "both sides computed identically (whole-session marginal_spend, collectors/economy.py's "
        "formula, reused not re-implemented). overlap_sessions_excluded lists any session tagged "
        "BOTH upkeep and touched by a solution -- ambiguous, excluded from both sides, never "
        "silently assigned. Prospective-only: null until a `tc upkeep tag-task` call has run "
        "inside a live session."
    ),
}


def collect(
    glob_pattern: str = DEFAULT_GLOB,
    archive_root: Optional[str] = None,
    live_root: Optional[str] = None,
) -> dict:
    """Scan every Task Copilot store for upkeep tags (W-1-style additive
    tables `tc upkeep` writes), compute the task-count heuristic
    everywhere, and -- only for repos with at least one tagged or
    outcome-touched session -- join to the transcript corpus for the
    exact, token-accountable method.

    Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    import glob as glob_mod

    errors: list[dict] = []
    raw_paths = sorted(Path(p) for p in glob_mod.glob(glob_pattern))
    deduped = _dedupe_by_real_path(raw_paths)

    per_repo: dict[str, dict] = {}
    for db_path, repo_name, _aliases in deduped:
        try:
            per_repo[repo_name] = _scan_repo_upkeep(db_path)
        except sqlite3.Error as exc:
            errors.append({"repo": repo_name, "path": str(db_path), "error": f"{type(exc).__name__}: {exc}"})
        except Exception as exc:  # a single bad store must never crash the run
            errors.append(
                {"repo": repo_name, "path": str(db_path), "error": f"unexpected {type(exc).__name__}: {exc}"}
            )

    total_tasks_all = sum(r["total_tasks"] for r in per_repo.values())
    total_upkeep_all = sum(r["upkeep_tasks"] for r in per_repo.values())

    needs_corpus = any(
        r["upkeep_session_ids"] or r["outcome_session_ids"] for r in per_repo.values()
    )

    per_repo_out: dict[str, dict] = {}
    for name, entry in per_repo.items():
        per_repo_out[name] = {**entry, "session_token_exact": _empty_exact_method()}

    if needs_corpus:
        archive_root_p = Path(archive_root).expanduser() if archive_root else DEFAULT_ARCHIVE_ROOT
        live_root_p = Path(live_root).expanduser() if live_root else DEFAULT_LIVE_ROOT
        archive_files = _index_jsonl_files(archive_root_p)
        live_files = _index_jsonl_files(live_root_p)
        winners, provenance = _merge_indexes(archive_files, live_files)

        if not winners:
            errors.append({"error": "no .jsonl transcripts found under either the archive or live corpus root"})
        else:
            merged_dir = _build_merged_corpus(winners)
            try:
                session_index = _index_sessions_by_id(merged_dir)
                for name, entry in per_repo.items():
                    if entry["upkeep_session_ids"] or entry["outcome_session_ids"]:
                        per_repo_out[name]["session_token_exact"] = _exact_method_for_repo(
                            entry, session_index
                        )
            finally:
                shutil.rmtree(merged_dir, ignore_errors=True)

    # Ecosystem-wide session_token_exact totals -- summed across repos, same
    # formula, never re-derived from the per-repo ratios (a ratio-of-ratios
    # would misweight repos with different session counts).
    agg_upkeep_marginal = 0
    agg_outcome_marginal = 0
    any_exact_data = False
    for entry in per_repo_out.values():
        u = entry["session_token_exact"]["upkeep"]["tokens_marginal_spend"]
        o = entry["session_token_exact"]["outcome"]["tokens_marginal_spend"]
        if u is not None:
            agg_upkeep_marginal += u
            any_exact_data = True
        if o is not None:
            agg_outcome_marginal += o
            any_exact_data = True
    agg_denom = agg_upkeep_marginal + agg_outcome_marginal

    metrics = {
        "source_glob": glob_pattern,
        "repos_scanned": sorted(per_repo.keys()),
        "per_repo": per_repo_out,
        "totals": {
            "task_count_heuristic": {
                "total_tasks": total_tasks_all,
                "upkeep_tasks": total_upkeep_all,
                "task_count_share": (total_upkeep_all / total_tasks_all) if total_tasks_all else None,
            },
            "session_token_exact": {
                "upkeep_tokens_marginal_spend": agg_upkeep_marginal if any_exact_data else None,
                "outcome_tokens_marginal_spend": agg_outcome_marginal if any_exact_data else None,
                "upkeep_tax_ratio_marginal_spend": (
                    (agg_upkeep_marginal / agg_denom) if agg_denom else None
                ),
            },
        },
        "definitions": _DEFINITIONS_NOTE,
    }
    return {"metrics": metrics, "errors": errors}
