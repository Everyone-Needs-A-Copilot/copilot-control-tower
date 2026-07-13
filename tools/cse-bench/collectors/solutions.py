"""collectors/solutions.py — the Outcome Ledger collector (W-1, Phase 4
outcome program, `docs/40-initiatives/01-cse-auditability/phases/
phase-4-outcome-program-prd.md`).

Scans every Task Copilot SQLite store on this machine (same glob/dedup
convention as collectors/tasksdb.py, reused directly rather than
re-implemented) read-only for the `solutions` table `tc solution`
(claude-copilot tools/tc/) writes, and emits the three outcome bars the
Outcome Ledger unblocks:

  - O-1 (TTFLS): t_working / t_loveable timestamps -> the working-to-loveable
    gap that isolates the design chain's value.
  - O-2 (Completeness, observed): sessions/tokens to done and the post-ship
    fix-vs-feature ratio, for solutions that reached a shipped-or-beyond
    status against a *locked* brief.
  - O-3 (Speed, OBSERVED ONLY -- no counterfactual): elapsed wall-clock time
    from started_at to t_working / t_loveable / closed_at. This is real
    elapsed time on real solutions, not a comparison against a bare-harness
    counterfactual -- that comparison is O-6's job (the W-3 ladder harness).
    Labelled "observed" throughout so it's never mistaken for O-3's full
    definition.
  - O-5 (Survival): started -> shipped -> in_use counts and ratios.

Honesty note: a store with no `solutions` table yet (the common case until
`tc solution create` is first run there -- see db/connection.py's
ensure_solutions_schema()) is NOT an error; it contributes zero solutions,
same as an existing-but-empty ledger. Every aggregate is `null`, not `0` or
a fabricated number, when there is no data to compute it from -- an empty
ledger is the honest state (phase-4-outcome-program-prd.md §5.4).
"""
from __future__ import annotations

import sqlite3
import statistics
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from collectors.tasksdb import DEFAULT_GLOB, _dedupe_by_real_path

COLLECTOR_NAME = "solutions"

# tasks.db stores timestamps as SQLite's `datetime('now')` output: naive
# "YYYY-MM-DD HH:MM:SS" strings, always UTC (no offset in the string) --
# same convention collectors/tasksdb.py documents and relies on.
_SQLITE_TS_FORMAT = "%Y-%m-%d %H:%M:%S"

_SHIPPED_OR_BEYOND = ("shipped", "in_use", "retired")


def _parse_sqlite_ts(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.strptime(value.strip(), _SQLITE_TS_FORMAT).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _seconds_between(start: Optional[str], end: Optional[str]) -> Optional[float]:
    start_dt = _parse_sqlite_ts(start)
    end_dt = _parse_sqlite_ts(end)
    if start_dt is None or end_dt is None:
        return None
    return (end_dt - start_dt).total_seconds()


def _stats(values: list[float]) -> dict:
    """Honest summary stats: null fields (not 0) when there's no data."""
    if not values:
        return {"count": 0, "median": None, "mean": None, "min": None, "max": None}
    return {
        "count": len(values),
        "median": statistics.median(values),
        "mean": statistics.fmean(values),
        "min": min(values),
        "max": max(values),
    }


def _table_exists(conn: sqlite3.Connection, table: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
    ).fetchone()
    return row is not None


def _empty_repo_result() -> dict:
    return {
        "ledger_present": False,
        "solutions_total": 0,
        "by_status": {},
        "shipped_or_beyond": 0,
        "in_use": 0,
        "abandoned": 0,
        "_raw": {
            "ttfls_seconds": [],
            "sessions_to_done": [],
            "tokens_to_done": [],
            "post_ship_feature_share": [],
            "started_to_working_seconds": [],
            "started_to_loveable_seconds": [],
            "started_to_shipped_seconds": [],
        },
    }


def _scan_repo(db_path: Path) -> dict:
    """Query a single Task Copilot store's Outcome Ledger. Returns per-repo
    counts plus the raw per-solution values (`_raw`) that both the per-repo
    stats and the cross-repo totals are computed from -- one source of
    numbers, no re-derivation.

    Any sqlite3.Error other than "table doesn't exist yet" propagates to
    the caller, which turns it into a per-repo error entry -- same
    contract as collectors/tasksdb.py._scan_repo.
    """
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5)
    try:
        conn.execute("PRAGMA query_only = 1")

        if not _table_exists(conn, "solutions"):
            # Pre-W-1 store, or W-1 landed but `tc solution create` hasn't
            # run here yet. Zero solutions is the honest state -- not an
            # error.
            return _empty_repo_result()

        cur = conn.cursor()
        cur.execute(
            """SELECT status, started_at, t_working, t_loveable, closed_at,
                      sessions_count, tokens_total,
                      post_ship_fixes, post_ship_features, brief_locked_at
               FROM solutions"""
        )
        rows = cur.fetchall()

        by_status: dict[str, int] = {}
        ttfls_gaps: list[float] = []
        sessions_to_done: list[float] = []
        tokens_to_done: list[float] = []
        feature_shares: list[float] = []
        started_to_working: list[float] = []
        started_to_loveable: list[float] = []
        started_to_shipped: list[float] = []

        shipped_or_beyond = 0
        in_use = 0
        abandoned = 0

        for (
            status, started_at, t_working, t_loveable, closed_at,
            sessions_count, tokens_total, fixes, features, brief_locked_at,
        ) in rows:
            by_status[status or "unknown"] = by_status.get(status or "unknown", 0) + 1

            gap = _seconds_between(t_working, t_loveable)
            if gap is not None:
                ttfls_gaps.append(gap)

            # O-3 (observed): raw elapsed time from first prompt (started_at)
            # to each milestone. No counterfactual comparison here -- see
            # module docstring.
            wtw = _seconds_between(started_at, t_working)
            if wtw is not None:
                started_to_working.append(wtw)
            wtl = _seconds_between(started_at, t_loveable)
            if wtl is not None:
                started_to_loveable.append(wtl)

            if status in _SHIPPED_OR_BEYOND:
                shipped_or_beyond += 1
                wts = _seconds_between(started_at, closed_at)
                if wts is not None:
                    started_to_shipped.append(wts)
                # O-2 only makes sense against a brief actually locked at
                # start (the intent contract); `tc solution close --status
                # shipped` already enforces this, but re-check honestly
                # rather than assume the write-side rule always held.
                if brief_locked_at is not None:
                    sessions_to_done.append(float(sessions_count or 0))
                    tokens_to_done.append(float(tokens_total or 0))
                    total_post_ship = (fixes or 0) + (features or 0)
                    if total_post_ship > 0:
                        feature_shares.append((features or 0) / total_post_ship)
            if status == "in_use":
                in_use += 1
            if status == "abandoned":
                abandoned += 1

        return {
            "ledger_present": True,
            "solutions_total": len(rows),
            "by_status": by_status,
            "shipped_or_beyond": shipped_or_beyond,
            "in_use": in_use,
            "abandoned": abandoned,
            "_raw": {
                "ttfls_seconds": ttfls_gaps,
                "sessions_to_done": sessions_to_done,
                "tokens_to_done": tokens_to_done,
                "post_ship_feature_share": feature_shares,
                "started_to_working_seconds": started_to_working,
                "started_to_loveable_seconds": started_to_loveable,
                "started_to_shipped_seconds": started_to_shipped,
            },
        }
    finally:
        conn.close()


def _repo_public_view(entry: dict) -> dict:
    """The per-repo dict actually written to output: summary stats derived
    from `_raw`, with `_raw` itself dropped (aggregation-only, not part of
    the public per-repo contract)."""
    raw = entry["_raw"]
    view = {k: v for k, v in entry.items() if k != "_raw"}
    view["ttfls_seconds"] = _stats(raw["ttfls_seconds"])
    view["completeness"] = {
        "sessions_to_done": _stats(raw["sessions_to_done"]),
        "tokens_to_done": _stats(raw["tokens_to_done"]),
        "post_ship_feature_share": _stats(raw["post_ship_feature_share"]),
    }
    view["speed_observed_seconds"] = {
        "started_to_working": _stats(raw["started_to_working_seconds"]),
        "started_to_loveable": _stats(raw["started_to_loveable_seconds"]),
        "started_to_shipped": _stats(raw["started_to_shipped_seconds"]),
    }
    total = view["solutions_total"]
    view["survival"] = {
        "pct_shipped_or_beyond": (view["shipped_or_beyond"] / total) if total else None,
        "pct_in_use_of_shipped_or_beyond": (
            (view["in_use"] / view["shipped_or_beyond"]) if view["shipped_or_beyond"] else None
        ),
    }
    return view


def _aggregate_totals(per_repo_raw: dict) -> dict:
    by_status: dict[str, int] = {}
    total = shipped_or_beyond = in_use = abandoned = 0
    all_ttfls: list[float] = []
    all_sessions: list[float] = []
    all_tokens: list[float] = []
    all_feature_shares: list[float] = []
    all_started_to_working: list[float] = []
    all_started_to_loveable: list[float] = []
    all_started_to_shipped: list[float] = []

    for entry in per_repo_raw.values():
        total += entry["solutions_total"]
        for status, count in entry["by_status"].items():
            by_status[status] = by_status.get(status, 0) + count
        shipped_or_beyond += entry["shipped_or_beyond"]
        in_use += entry["in_use"]
        abandoned += entry["abandoned"]

        raw = entry["_raw"]
        all_ttfls.extend(raw["ttfls_seconds"])
        all_sessions.extend(raw["sessions_to_done"])
        all_tokens.extend(raw["tokens_to_done"])
        all_feature_shares.extend(raw["post_ship_feature_share"])
        all_started_to_working.extend(raw["started_to_working_seconds"])
        all_started_to_loveable.extend(raw["started_to_loveable_seconds"])
        all_started_to_shipped.extend(raw["started_to_shipped_seconds"])

    pct_shipped = (shipped_or_beyond / total) if total else None
    pct_in_use = (in_use / shipped_or_beyond) if shipped_or_beyond else None

    return {
        "solutions_total": total,
        "by_status": by_status,
        "ttfls_seconds": _stats(all_ttfls),
        "completeness": {
            "shipped_or_beyond_count": shipped_or_beyond,
            "sessions_to_done": _stats(all_sessions),
            "tokens_to_done": _stats(all_tokens),
            "post_ship_feature_share": _stats(all_feature_shares),
        },
        "speed_observed_seconds": {
            "started_to_working": _stats(all_started_to_working),
            "started_to_loveable": _stats(all_started_to_loveable),
            "started_to_shipped": _stats(all_started_to_shipped),
        },
        "survival": {
            "started": total,
            "shipped_or_beyond": shipped_or_beyond,
            "pct_shipped_or_beyond": pct_shipped,
            "in_use": in_use,
            "pct_in_use_of_shipped_or_beyond": pct_in_use,
            "abandoned": abandoned,
        },
    }


def collect(glob_pattern: str = DEFAULT_GLOB) -> dict:
    """Scan every Task Copilot store matching glob_pattern for its Outcome
    Ledger.

    Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    import glob as glob_mod

    errors: list[dict] = []
    per_repo_raw: dict = {}

    raw_paths = sorted(Path(p) for p in glob_mod.glob(glob_pattern))
    deduped = _dedupe_by_real_path(raw_paths)
    aliases_detected = {name: aliases for _, name, aliases in deduped if aliases}

    for db_path, repo_name, aliases in deduped:
        try:
            scanned = _scan_repo(db_path)
            entry = {"path": str(db_path), **scanned}
            if aliases:
                entry["aliases"] = aliases
            per_repo_raw[repo_name] = entry
        except sqlite3.Error as exc:
            errors.append(
                {
                    "repo": repo_name,
                    "path": str(db_path),
                    "error": f"{type(exc).__name__}: {exc}",
                }
            )
        except Exception as exc:  # a single bad store must never crash the run
            errors.append(
                {
                    "repo": repo_name,
                    "path": str(db_path),
                    "error": f"unexpected {type(exc).__name__}: {exc}",
                }
            )

    totals = _aggregate_totals(per_repo_raw)
    per_repo = {name: _repo_public_view(entry) for name, entry in per_repo_raw.items()}
    repos_with_ledger = sorted(name for name, entry in per_repo.items() if entry["ledger_present"])

    metrics = {
        "source_glob": glob_pattern,
        "repos_matched": len(raw_paths),
        "repos_found": len(deduped),
        "repos_scanned": sorted(per_repo.keys()),
        "repos_with_ledger": repos_with_ledger,
        "repos_skipped": sorted(e["repo"] for e in errors),
        "aliases_detected": aliases_detected,
        "totals": totals,
        "per_repo": per_repo,
        "definitions": {
            "ledger_present": "true once a store's tasks.db has the solutions table (first `tc solution create` run there); false is the honest pre-adoption state, not an error",
            "ttfls_seconds": "O-1: t_loveable - t_working, in seconds, for solutions where both timestamps are set. count=0/median=null when no such solution exists yet -- not fabricated as 0.",
            "completeness.shipped_or_beyond_count / sessions_to_done / tokens_to_done": "O-2: solutions.sessions_count / tokens_total for solutions with status in (shipped, in_use, retired) AND a locked brief (the intent contract completeness is measured against)",
            "completeness.post_ship_feature_share": "post_ship_features / (post_ship_fixes + post_ship_features) per solution, only where post-ship activity exists (denominator > 0)",
            "speed_observed_seconds": "O-3, OBSERVED ONLY (no counterfactual): started_at -> t_working / t_loveable / closed_at (closed_at only for shipped-or-beyond solutions), in seconds. This is real elapsed time on real solutions, not a comparison against a bare-harness counterfactual -- that's O-6 (the W-3 ladder harness). count=0/median=null when no such solution exists yet.",
            "survival.pct_shipped_or_beyond": "shipped_or_beyond / started (solutions_total); null if started == 0",
            "survival.pct_in_use_of_shipped_or_beyond": "in_use / shipped_or_beyond; null if shipped_or_beyond == 0",
        },
    }
    return {"metrics": metrics, "errors": errors}
