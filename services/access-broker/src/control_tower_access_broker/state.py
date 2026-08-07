"""Bounded replay, rate, and circuit-breaker state."""

from __future__ import annotations

import math
import secrets
import sqlite3
import threading
import time
from collections import defaultdict, deque
from contextlib import closing
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path


@dataclass(frozen=True)
class Nonce:
    nonce_id: str
    value: str
    login: str
    machine_id: str
    expires_at: float


class NonceStore:
    def __init__(self, ttl_seconds: int) -> None:
        self.ttl_seconds = ttl_seconds
        self._items: dict[str, Nonce] = {}
        self._lock = threading.Lock()

    def create(self, login: str, machine_id: str, *, now: float | None = None) -> Nonce:
        current = time.time() if now is None else now
        item = Nonce(
            nonce_id=secrets.token_urlsafe(24),
            value=secrets.token_urlsafe(32),
            login=login.casefold(),
            machine_id=machine_id,
            expires_at=current + self.ttl_seconds,
        )
        with self._lock:
            self._items = {
                key: value for key, value in self._items.items() if value.expires_at >= current
            }
            self._items[item.nonce_id] = item
        return item

    def consume(
        self,
        nonce_id: str,
        nonce: str,
        login: str,
        machine_id: str,
        *,
        now: float | None = None,
    ) -> Nonce | None:
        current = time.time() if now is None else now
        with self._lock:
            item = self._items.pop(nonce_id, None)
        if item is None or item.expires_at < current:
            return None
        if not secrets.compare_digest(item.value, nonce):
            return None
        if item.login != login.casefold() or item.machine_id != machine_id:
            return None
        return item


class SlidingWindowLimiter:
    def __init__(self, limit: int, window_seconds: int = 60) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, key: str, *, now: float | None = None) -> bool:
        current = time.monotonic() if now is None else now
        cutoff = current - self.window_seconds
        with self._lock:
            events = self._events[key]
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= self.limit:
                return False
            events.append(current)
            return True


class IssueLedger:
    """Count-only SQLite ledger for the global issuance circuit breaker."""

    def __init__(self, path: Path, *, daily_floor: int) -> None:
        self.path = path
        self.daily_floor = daily_floor
        self._lock = threading.Lock()
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with closing(self._connect()) as connection:
            connection.execute(
                "CREATE TABLE IF NOT EXISTS issue_events "
                "(issued_at INTEGER NOT NULL, count INTEGER NOT NULL)"
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS issue_events_time ON issue_events(issued_at)"
            )
            connection.commit()
        try:
            self.path.chmod(0o600)
        except OSError:
            pass

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.path, timeout=5, isolation_level="IMMEDIATE")

    @staticmethod
    def _day_start(now: float) -> int:
        current = datetime.fromtimestamp(now, tz=UTC)
        return int(current.replace(hour=0, minute=0, second=0, microsecond=0).timestamp())

    def allow_and_record(self, count: int, *, now: float | None = None) -> tuple[bool, int]:
        current = time.time() if now is None else now
        today = self._day_start(current)
        week_start = today - 7 * 86_400
        with self._lock, closing(self._connect()) as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("DELETE FROM issue_events WHERE issued_at < ?", (week_start,))
            previous = connection.execute(
                "SELECT COALESCE(SUM(count), 0) FROM issue_events "
                "WHERE issued_at >= ? AND issued_at < ?",
                (week_start, today),
            ).fetchone()[0]
            today_count = connection.execute(
                "SELECT COALESCE(SUM(count), 0) FROM issue_events WHERE issued_at >= ?",
                (today,),
            ).fetchone()[0]
            trailing_average = previous / 7
            threshold = max(self.daily_floor, math.ceil(trailing_average * 5))
            if today_count + count > threshold:
                return False, threshold
            connection.execute(
                "INSERT INTO issue_events (issued_at, count) VALUES (?, ?)",
                (int(current), count),
            )
            connection.commit()
            return True, threshold
