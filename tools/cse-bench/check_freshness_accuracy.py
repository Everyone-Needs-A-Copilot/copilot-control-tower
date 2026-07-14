#!/usr/bin/env python3
"""check_freshness_accuracy.py — mechanically verifies knowledge-copilot's
`last_updated` frontmatter dates are not invented (claim
`knowledge-staleness-honesty`).

WHY: QA WP-47 found that claim's original check (`cse_bench.py collect
--only knowledge_soul`) only measures `last_updated` KEY PRESENCE
(100% coverage) — it never checks whether the DATE VALUE is real. A
fabricated date would score 100% under that check alone. This script is
the missing half: for every non-archive .md file carrying a `last_updated`
value, it asks git for every date that file was ever actually touched
(`git log --follow`) and checks the frontmatter date against that set.

WHAT "invented" means here, precisely: a `last_updated` value that does not
match ANY commit date in the file's own git history. This is deliberately a
looser test than "matches the MOST RECENT commit" — R-7's backfill script
(knowledge-copilot commit c6a6b492) computes `last_updated` from the last
commit that touched the path BEFORE its own mechanical edit, so the
backfill commit itself (and any later purely-mechanical bulk commit) is
expected to postdate a file's `last_updated` without that being dishonest.
Membership-in-history is what actually tests "not invented."

USAGE:
    tools/cse-bench/check_freshness_accuracy.py [--repo-root PATH] [--json]

Exit code 0 always (this is a report, not a pass/fail gate by itself — the
claim it backs records the honest ratio, per V-2, rather than a bare
pass/fail threshold nobody pre-registered).
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

FM_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
LU_RE = re.compile(r"^last_updated:\s*['\"]?(\d{4}-\d{2}-\d{2})", re.MULTILINE)


def _default_repo_root() -> pathlib.Path:
    script_dir = pathlib.Path(__file__).resolve().parent
    sys.path.insert(0, str(script_dir))
    from collectors.paths import resolve_copilot_root  # local import, same convention as claim_sweep.py

    return resolve_copilot_root() / "knowledge-copilot"


def collect(repo_root: pathlib.Path) -> dict:
    files = [
        p
        for p in repo_root.rglob("*.md")
        if ".git" not in p.parts and "node_modules" not in p.parts
    ]
    with_lu: list[tuple[pathlib.Path, str]] = []
    for p in files:
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        m = FM_RE.match(text)
        if not m:
            continue
        lu = LU_RE.search(m.group(1))
        if lu:
            with_lu.append((p, lu.group(1)))

    invented: list[dict] = []
    for p, lu in with_lu:
        rel = p.relative_to(repo_root)
        proc = subprocess.run(
            ["git", "-C", str(repo_root), "log", "--follow", "--format=%ad", "--date=short", "--", str(rel)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        dates = set(proc.stdout.split())
        if lu not in dates:
            invented.append({"file": str(rel), "last_updated": lu, "git_history_dates": sorted(dates)})

    n = len(with_lu)
    n_invented = len(invented)
    return {
        "repo_root": str(repo_root),
        "n_files_with_last_updated": n,
        "n_invented": n_invented,
        "n_verified_in_history": n - n_invented,
        "verified_pct": round(100.0 * (n - n_invented) / n, 2) if n else None,
        "invented": invented,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo-root", type=pathlib.Path, default=None)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    repo_root = args.repo_root or _default_repo_root()
    if not repo_root.is_dir():
        print(f"check_freshness_accuracy: repo root not found: {repo_root}", file=sys.stderr)
        return 2

    result = collect(repo_root)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"check_freshness_accuracy: root={result['repo_root']}")
        print(
            f"check_freshness_accuracy: {result['n_files_with_last_updated']} file(s) carry last_updated -- "
            f"{result['n_verified_in_history']} verified in that file's own git history "
            f"({result['verified_pct']}%), {result['n_invented']} NOT found in history"
        )
        for item in result["invented"]:
            print(f"  {item['file']}: last_updated={item['last_updated']!r} not in {item['git_history_dates']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
