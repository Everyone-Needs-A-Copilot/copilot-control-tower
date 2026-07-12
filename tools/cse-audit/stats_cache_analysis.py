"""
stats_cache_analysis.py — long-horizon (Jan-Jul 2026) daily/weekly trend from
~/.claude/stats-cache.json, which is the ONLY local artifact that spans the
April 22 2026 hook-ship date. Raw JSONL session transcripts on this machine
only go back to 2026-06-09 (verified by scanning the full corpus — see
findings), so stats-cache.json is what makes any pre/post comparison
possible at all, at the cost of much coarser metrics:

  - dailyActivity[]: {date, messageCount, sessionCount, toolCallCount}
    Cannot compute delegation rate (no main/subagent split) or protocol
    declaration rate (no message content) from this. CAN give a rough
    messages-per-session proxy for session length, and tool-calls-per-session.
  - dailyModelTokens[]: {date, tokensByModel: {model: tokens}}
    CAN give a daily Sonnet-vs-Opus token share — a real, if coarse, test of
    the "Sonnet ~94% of work" claim across the full window, unlike the raw
    corpus which only supports it for June 9 onward.

CAVEAT baked into every number this module produces: `sessionCount` is a
daily-activity count, not a count of sessions *started* that day — a session
active across N days is counted in each of those N days' sessionCount. This
inflates the denominator on multi-day sessions and biases the
messages-per-session and tool-calls-per-session ratios downward. It is a
correlated bias (not obviously worse pre or post any given date), so trend
direction is still informative, but the absolute ratio should not be quoted
as equal to the diagnostic's "turns/session" methodology.
"""
from __future__ import annotations

import json
import statistics
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Optional


@dataclass
class DayRow:
    d: date
    message_count: int
    session_count: int
    tool_call_count: int
    tokens_by_model: dict


def load(stats_cache_path: Path) -> list[DayRow]:
    data = json.loads(stats_cache_path.read_text())
    activity = {row["date"]: row for row in data.get("dailyActivity", [])}
    tokens = {row["date"]: row.get("tokensByModel", {}) for row in data.get("dailyModelTokens", [])}
    all_dates = sorted(set(activity) | set(tokens))
    out = []
    for ds in all_dates:
        a = activity.get(ds, {})
        out.append(
            DayRow(
                d=datetime.strptime(ds, "%Y-%m-%d").date(),
                message_count=a.get("messageCount", 0),
                session_count=a.get("sessionCount", 0),
                tool_call_count=a.get("toolCallCount", 0),
                tokens_by_model=tokens.get(ds, {}),
            )
        )
    return out


def model_family(model: str) -> str:
    m = model.lower()
    if "opus" in m:
        return "opus"
    if "sonnet" in m:
        return "sonnet"
    if "haiku" in m:
        return "haiku"
    return "other"


def sonnet_share(row: DayRow) -> Optional[float]:
    total = sum(row.tokens_by_model.values())
    if total == 0:
        return None
    fam_totals: dict[str, int] = {}
    for model, tok in row.tokens_by_model.items():
        fam_totals[model_family(model)] = fam_totals.get(model_family(model), 0) + tok
    return fam_totals.get("sonnet", 0) / total


def messages_per_session(row: DayRow) -> Optional[float]:
    if row.session_count == 0:
        return None
    return row.message_count / row.session_count


def tool_calls_per_session(row: DayRow) -> Optional[float]:
    if row.session_count == 0:
        return None
    return row.tool_call_count / row.session_count


def segment_pre_post(rows: list[DayRow], cutover: date) -> tuple[list[DayRow], list[DayRow]]:
    pre = [r for r in rows if r.d < cutover]
    post = [r for r in rows if r.d >= cutover]
    return pre, post


def weekly_bucket(rows: list[DayRow]) -> dict:
    """ISO (year, week) -> list[DayRow]."""
    buckets: dict = {}
    for r in rows:
        key = r.d.isocalendar()[:2]
        buckets.setdefault(key, []).append(r)
    return dict(sorted(buckets.items()))


def summarize(rows: list[DayRow], label: str) -> dict:
    mps = [v for v in (messages_per_session(r) for r in rows) if v is not None]
    tps = [v for v in (tool_calls_per_session(r) for r in rows) if v is not None]
    ss = [v for v in (sonnet_share(r) for r in rows) if v is not None]

    def stats(vals):
        if not vals:
            return {"n": 0}
        return {
            "n": len(vals),
            "median": statistics.median(vals),
            "mean": statistics.fmean(vals),
            "min": min(vals),
            "max": max(vals),
        }

    return {
        "label": label,
        "n_days": len(rows),
        "total_sessions": sum(r.session_count for r in rows),
        "total_messages": sum(r.message_count for r in rows),
        "total_tool_calls": sum(r.tool_call_count for r in rows),
        "messages_per_session": stats(mps),
        "tool_calls_per_session": stats(tps),
        "sonnet_token_share": stats(ss),
    }
