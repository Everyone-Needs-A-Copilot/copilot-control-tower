from __future__ import annotations

from control_tower_access_broker.state import IssueLedger, NonceStore, SlidingWindowLimiter


def test_nonce_is_bound_single_use_and_expires():
    store = NonceStore(60)
    item = store.create("Pablo", "machine", now=100)
    assert store.consume(item.nonce_id, item.value, "pablo", "machine", now=120) == item
    assert store.consume(item.nonce_id, item.value, "pablo", "machine", now=121) is None
    expired = store.create("pablo", "machine", now=200)
    assert store.consume(expired.nonce_id, expired.value, "pablo", "machine", now=261) is None


def test_sliding_window_limiter_recovers_after_window():
    limiter = SlidingWindowLimiter(2, window_seconds=60)
    assert limiter.allow("key", now=0)
    assert limiter.allow("key", now=1)
    assert not limiter.allow("key", now=2)
    assert limiter.allow("key", now=61)


def test_global_circuit_breaker_records_counts_and_holds(tmp_path):
    ledger = IssueLedger(tmp_path / "events.sqlite3", daily_floor=2)
    assert ledger.allow_and_record(1, now=1_700_000_000) == (True, 2)
    assert ledger.allow_and_record(1, now=1_700_000_001) == (True, 2)
    assert ledger.allow_and_record(1, now=1_700_000_002) == (False, 2)
