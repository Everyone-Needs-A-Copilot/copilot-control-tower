#!/usr/bin/env python3
"""check_pre_restructure_transcripts.py — verifies claim
`framework-april-2026-diagnostic-unrecoverable`: zero session transcripts
predating the 2026-04-22 hook-enforcement cutover survive in either the
archive or live transcript corpus roots.

WHY: claude-copilot's docs/10-architecture/04-framework-restructure-2026-04.md
and README.md quote a one-time April 2026 diagnostic (15 sessions, Apr
17-22: 94% main-session work, 6% delegation, 3.5% protocol declarations,
671 turns/session, etc.). Those figures cannot be independently re-derived
today: April's own counting script no longer exists (see claims.yaml's
`turn-definition-incompatible-with-april`, evidence: phase-1-findings.md
F-6), and this script proves the OTHER half of why -- the raw session data
itself is gone too, not just the script.

Exit code 0 always (a report, not a threshold gate).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

CUTOVER = "2026-04-22"


def _corpus_roots() -> list[Path]:
    script_dir = Path(__file__).resolve().parent
    sys.path.insert(0, str(script_dir))
    from collectors.paths import resolve_copilot_root  # noqa: E402

    root = resolve_copilot_root()
    home = Path.home()
    return [
        home / ".claude" / "transcript-archive" / "claude-projects",
        home / ".claude" / "projects",
    ]


def main() -> int:
    roots = _corpus_roots()
    earliest: str | None = None
    earliest_file: str | None = None
    pre_cutover = 0
    scanned = 0

    for root in roots:
        if not root.is_dir():
            continue
        for f in root.rglob("*.jsonl"):
            scanned += 1
            try:
                with open(f, encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            rec = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        ts = rec.get("timestamp")
                        if isinstance(ts, str) and len(ts) >= 10:
                            if earliest is None or ts < earliest:
                                earliest = ts
                                earliest_file = str(f)
                            if ts[:10] < CUTOVER:
                                pre_cutover += 1
                            break
            except OSError:
                continue

    result = {
        "roots": [str(r) for r in roots],
        "files_scanned": scanned,
        "earliest_timestamp": earliest,
        "earliest_file": earliest_file,
        "cutover": CUTOVER,
        "sessions_with_first_record_before_cutover": pre_cutover,
        "zero_pre_cutover_survives": pre_cutover == 0,
    }
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
