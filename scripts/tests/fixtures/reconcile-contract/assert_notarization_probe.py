#!/usr/bin/env python3
"""Require upstream Finder reconciliation evidence for a helper release."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: assert_notarization_probe.py NOTARIZATION.json")
    path = Path(sys.argv[1])
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit("upstream notarization evidence is unreadable") from exc
    if not isinstance(payload, dict):
        raise SystemExit("upstream notarization evidence is not an object")
    if payload.get("finder_reconciliation_probe") != "passed":
        raise SystemExit(
            "upstream helper did not pass the Finder-environment reconciliation probe"
        )


if __name__ == "__main__":
    main()
