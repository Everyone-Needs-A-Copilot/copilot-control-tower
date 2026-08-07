"""Allowlisted, secret-free broker audit events."""

from __future__ import annotations

import json
import logging
from collections.abc import Iterable
from datetime import UTC, datetime

logger = logging.getLogger("control_tower_access_broker.audit")


def emit(
    *,
    event: str,
    outcome: str,
    source_ip: str,
    login: str | None = None,
    machine_id: str | None = None,
    scopes: Iterable[str] = (),
    reason_code: str | None = None,
    threshold: int | None = None,
) -> None:
    payload = {
        "timestamp": datetime.now(UTC).isoformat(),
        "event": event,
        "outcome": outcome,
        "source_ip": source_ip,
        "login": login.casefold() if login else None,
        "machine_id": machine_id,
        "scopes": sorted(set(scopes)),
        "reason_code": reason_code,
        "threshold": threshold,
    }
    logger.info(json.dumps(payload, separators=(",", ":"), sort_keys=True))
