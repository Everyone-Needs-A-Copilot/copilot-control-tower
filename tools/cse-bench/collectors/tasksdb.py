"""collectors/tasksdb.py — Task Copilot store collector.

Scans every Task Copilot SQLite store on this machine
(default: /Volumes/Dev/Sites/COPILOT/*/.copilot/tasks.db) read-only and
produces adoption/throughput metrics: task counts by status, completion
rate, a rework signal, work-product mix, PRD counts, agent-assignment
mix, and a created/completed-per-month trend since the corpus's earliest
activity.

Serves PRD-9 (CSE Verification & Benchmark Program), task B-4.

Design notes
------------
- Every store is opened with the read-only URI form
  (``file:<path>?mode=ro``), which SQLite honors even when the store is
  in WAL mode (the -wal/-shm siblings are read, never written).
- A store that is locked, corrupt, or otherwise unreadable produces a
  per-repo entry in the returned ``errors`` list; it never raises out of
  ``collect()`` and never aborts the scan of the remaining repos.
- Product directories in this ecosystem are sometimes symlinked to a
  canonical target (e.g. ``shared-docs -> knowledge-copilot-internal``). Two glob
  matches that resolve to the same physical ``tasks.db`` are the same
  store counted twice, not two stores -- they are de-duplicated before
  scanning, and the alias name is recorded rather than silently dropped.
"""
from __future__ import annotations

import glob
import sqlite3
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

COLLECTOR_NAME = "tasksdb"

DEFAULT_GLOB = "/Volumes/Dev/Sites/COPILOT/*/.copilot/tasks.db"

# tasks.db stores timestamps as SQLite's `datetime('now')` output: naive
# "YYYY-MM-DD HH:MM:SS" strings, always UTC (no offset in the string).
_SQLITE_TS_FORMAT = "%Y-%m-%d %H:%M:%S"
_ISO_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


def _parse_sqlite_ts(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.strptime(value.strip(), _SQLITE_TS_FORMAT).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _parse_iso_ts(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    return datetime.strptime(value, _ISO_FORMAT).replace(tzinfo=timezone.utc)


def _iso(dt: Optional[datetime]) -> Optional[str]:
    return dt.strftime(_ISO_FORMAT) if dt else None


def _month_key(dt: Optional[datetime]) -> Optional[str]:
    return dt.strftime("%Y-%m") if dt else None


def _scan_repo(db_path: Path) -> dict:
    """Query a single Task Copilot store. Any sqlite3.Error (locked,
    corrupt, unreadable) propagates to the caller, which turns it into a
    per-repo error entry rather than crashing the run.
    """
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5)
    try:
        conn.execute("PRAGMA query_only = 1")
        cur = conn.cursor()

        cur.execute("SELECT status, agent, created_at, updated_at FROM tasks")
        rows = cur.fetchall()

        by_status: Counter = Counter()
        agent_mix: Counter = Counter()
        created_by_month: Counter = Counter()
        completed_by_month: Counter = Counter()
        earliest: Optional[datetime] = None
        latest: Optional[datetime] = None

        for status, agent, created_at, updated_at in rows:
            by_status[status or "unknown"] += 1
            agent_mix[agent or "unassigned"] += 1

            created_dt = _parse_sqlite_ts(created_at)
            updated_dt = _parse_sqlite_ts(updated_at)

            if created_dt:
                created_by_month[_month_key(created_dt)] += 1
                if earliest is None or created_dt < earliest:
                    earliest = created_dt
                if latest is None or created_dt > latest:
                    latest = created_dt
            if updated_dt and (latest is None or updated_dt > latest):
                latest = updated_dt
            if status == "completed" and updated_dt:
                completed_by_month[_month_key(updated_dt)] += 1

        cancelled_count = by_status.get("cancelled", 0)

        # Rework proxy: the store keeps no status-history table, so a
        # true "reopened" transition cannot be observed directly. Proxy
        # signal: a task that agent_log recorded as completed at least
        # once, but whose *current* status is no longer 'completed' --
        # it moved away from completed after being logged as done.
        cur.execute(
            """
            SELECT COUNT(DISTINCT al.task_id)
            FROM agent_log al
            JOIN tasks t ON t.id = al.task_id
            WHERE al.action = 'completed' AND t.status != 'completed'
            """
        )
        reopened_count = cur.fetchone()[0]

        cur.execute("SELECT type FROM work_products")
        wp_by_type = Counter(row[0] or "unknown" for row in cur.fetchall())

        cur.execute("SELECT COUNT(*) FROM prds")
        prd_count = cur.fetchone()[0]

        total_tasks = len(rows)
        completed_tasks = by_status.get("completed", 0)
        completion_rate = (completed_tasks / total_tasks) if total_tasks else None

        return {
            "tasks": {
                "total": total_tasks,
                "by_status": dict(by_status),
                "completion_rate": completion_rate,
                "cancelled_count": cancelled_count,
                "reopened_count": reopened_count,
            },
            "agent_mix": dict(agent_mix),
            "work_products": {
                "total": sum(wp_by_type.values()),
                "by_type": dict(wp_by_type),
            },
            "prds": {"total": prd_count},
            "monthly_trend": {
                "created": dict(sorted(created_by_month.items())),
                "completed": dict(sorted(completed_by_month.items())),
            },
            "date_range": {
                "earliest": _iso(earliest),
                "latest": _iso(latest),
            },
        }
    finally:
        conn.close()


def _dedupe_by_real_path(db_paths: list[Path]) -> list[tuple[Path, str, list[str]]]:
    """Group glob matches by the physical file they resolve to (symlinked
    product directories, e.g. shared-docs -> knowledge-copilot-internal, otherwise
    get scanned and counted twice). Returns a list of
    (chosen_db_path, canonical_repo_name, alias_repo_names) tuples, one
    per unique physical store, sorted by canonical repo name.
    """
    groups: dict[Path, list[tuple[Path, Path]]] = {}
    for db_path in db_paths:
        repo_dir = db_path.parent.parent
        real_path = db_path.resolve()
        groups.setdefault(real_path, []).append((db_path, repo_dir))

    chosen: list[tuple[Path, str, list[str]]] = []
    for real_path, entries in groups.items():
        non_symlinked = [e for e in entries if not e[1].is_symlink()]
        candidates = non_symlinked if non_symlinked else entries
        chosen_db_path, chosen_repo_dir = sorted(candidates, key=lambda e: e[1].name)[0]
        canonical_name = chosen_repo_dir.name
        aliases = sorted({e[1].name for e in entries if e[1].name != canonical_name})
        chosen.append((chosen_db_path, canonical_name, aliases))

    return sorted(chosen, key=lambda t: t[1])


def _aggregate_totals(per_repo: dict) -> dict:
    by_status: Counter = Counter()
    agent_mix: Counter = Counter()
    wp_by_type: Counter = Counter()
    created_by_month: Counter = Counter()
    completed_by_month: Counter = Counter()
    total_tasks = total_wp = total_prds = 0
    cancelled_count = reopened_count = 0
    earliest: Optional[datetime] = None
    latest: Optional[datetime] = None

    for repo in per_repo.values():
        total_tasks += repo["tasks"]["total"]
        total_wp += repo["work_products"]["total"]
        total_prds += repo["prds"]["total"]
        cancelled_count += repo["tasks"]["cancelled_count"]
        reopened_count += repo["tasks"]["reopened_count"]

        by_status.update(repo["tasks"]["by_status"])
        agent_mix.update(repo["agent_mix"])
        wp_by_type.update(repo["work_products"]["by_type"])
        created_by_month.update(repo["monthly_trend"]["created"])
        completed_by_month.update(repo["monthly_trend"]["completed"])

        repo_earliest = _parse_iso_ts(repo["date_range"]["earliest"])
        repo_latest = _parse_iso_ts(repo["date_range"]["latest"])
        if repo_earliest and (earliest is None or repo_earliest < earliest):
            earliest = repo_earliest
        if repo_latest and (latest is None or repo_latest > latest):
            latest = repo_latest

    completion_rate = (by_status.get("completed", 0) / total_tasks) if total_tasks else None

    return {
        "tasks": total_tasks,
        "prds": total_prds,
        "work_products": total_wp,
        "by_status": dict(by_status),
        "completion_rate": completion_rate,
        "cancelled_count": cancelled_count,
        "reopened_count": reopened_count,
        "agent_mix": dict(agent_mix),
        "work_products_by_type": dict(wp_by_type),
        "monthly_trend": {
            "created": dict(sorted(created_by_month.items())),
            "completed": dict(sorted(completed_by_month.items())),
        },
        "activity_range": {
            "earliest": _iso(earliest),
            "latest": _iso(latest),
        },
    }


def collect(glob_pattern: str = DEFAULT_GLOB) -> dict:
    """Scan every Task Copilot store matching glob_pattern.

    Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []
    per_repo: dict = {}

    raw_paths = sorted(Path(p) for p in glob.glob(glob_pattern))
    deduped = _dedupe_by_real_path(raw_paths)
    aliases_detected = {name: aliases for _, name, aliases in deduped if aliases}

    for db_path, repo_name, aliases in deduped:
        try:
            scanned = _scan_repo(db_path)
            entry = {"path": str(db_path), **scanned}
            if aliases:
                entry["aliases"] = aliases
            per_repo[repo_name] = entry
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

    totals = _aggregate_totals(per_repo)

    metrics = {
        "source_glob": glob_pattern,
        "repos_matched": len(raw_paths),
        "repos_found": len(deduped),
        "repos_scanned": sorted(per_repo.keys()),
        "repos_skipped": sorted(e["repo"] for e in errors),
        "aliases_detected": aliases_detected,
        "totals": totals,
        "per_repo": per_repo,
        "definitions": {
            "repos_matched": "raw glob matches before de-duplicating symlinked product directories that resolve to the same physical tasks.db",
            "repos_found": "unique physical stores after de-duplication (see aliases_detected)",
            "completion_rate": "completed tasks / total tasks for the store; null if the store has zero tasks",
            "cancelled_count": "count of tasks.status == 'cancelled'",
            "reopened_count": "proxy: count of distinct tasks with an agent_log action='completed' entry whose current tasks.status is not 'completed'. The store keeps no status-history table, so a true reopen event cannot be observed directly.",
            "agent_mix": "count of tasks grouped by tasks.agent (null mapped to 'unassigned')",
            "monthly_trend.created": "tasks.created_at truncated to YYYY-MM, UTC",
            "monthly_trend.completed": "tasks.updated_at truncated to YYYY-MM, UTC, for rows where status == 'completed' (last-write proxy; the store has no completed_at column)",
            "date_range / activity_range": "min/max of tasks.created_at and tasks.updated_at",
        },
    }
    return {"metrics": metrics, "errors": errors}
