#!/usr/bin/env python3
"""claim_sweep.py — the CSE-wide claim sweep (t2-no-claim-outlives-its-check).

WHY: docs/40-initiatives/01-cse-auditability/README.md's Phase-0 vision was
"one machine-readable table of every claim across all four products"; the
SCOPE NOTE at the top of claims.yaml says that full sweep "is still open
work." decisions/RULING-AGENDA.md §6 names the exact gap: t2 "needs the full
CSE-wide ~40-claim sweep the register's own SCOPE NOTE says it is *not yet*,
plus F-18's 7 artifact-without-mechanism instances driven to zero, enforced
on commit." This script is that mechanism.

WHAT IT DOES: scans each CSE product's self-description surface (see SCOPE
below for the exact, principled rule) for VERIFIABLE ASSERTIONS: quantified
claims (percentages, counts, "N of M", version numbers, ratios) and
mechanism-guarantee claims ("automatically", "ensures", "guarantees"). Each
assertion found is classified BACKED or UNBACKED:

  BACKED   — an `<!-- claim-check: <id> -->` annotation backs it (see
             BINDING below for exactly which annotations count) AND <id>
             resolves to a real entry in claims.yaml. This is the "backing
             is explicit and cheap" convention this tool is built around,
             chosen over trying to be clever at parsing English (see the
             "Precision" section below and README.md).
  UNBACKED  — no such annotation, or the annotation's <id> does not resolve
             (a DANGLING annotation — reported as its own sub-count, not
             silently treated as backed).

BINDING (tightened 2026-07-14, QA WP-47): an annotation backs an assertion
only if:
  (a) the annotation is on the assertion's OWN line (a trailing comment), or
  (b) the annotation sits ALONE on its own line (nothing else on that line
      once the comment is stripped) and is the line IMMEDIATELY BEFORE the
      assertion's line (annotation precedes assertion, one direction only).
There is no "line after" reach and no backward bleed from a trailing
same-line annotation onto a neighboring line. The prior ±1-either-direction
rule let one annotation nominally "back" an unrelated adjacent table row
(e.g. a model-tier annotation trailing one markdown-table row also
backing the UNRELATED row directly above it, purely because both rows sit
one line apart) — a real over-backing bug QA found and this binding closes.
Every doc using the old backward-reach convention has been updated to a
same-line trailing annotation instead (see git history around this date).

SCOPE (tightened 2026-07-14, QA WP-47 — the old SCAN_TARGETS was 19
hand-picked files, an implicit allowlist that missed a live unbacked
assertion in copilot-control-tower's own CLAUDE.md). The scope is now a
FORMULA, not a hand-picked list, so it stays honest as docs are added:

  1. Root self-description files, whichever of these the repo actually has:
     README.md, SOUL.md, PURPOSE.md, ECOSYSTEM.md, CLAUDE.md, AGENTS.md.
  2. docs/ DEPTH-1 markdown files only — immediate children of docs/, not
     the recursive tree (glob docs/*.md, never docs/**/*.md). This is the
     repo's own doc ROOT, the layer a reader lands on first; it deliberately
     excludes deep initiative/product/decision trees (see EXCLUDED below).
  3. A small set of EXPLICIT, NAMED additions — deeper architecture docs
     F-18's own findings cite by path (see _EXTRA_TARGETS). Every exception
     is listed by name in this file, reviewable, not a hidden allowlist.

  EXCLUDED, explicitly (not an oversight — a deliberate, disclosed
  boundary): anything below docs/ depth-1 except the _EXTRA_TARGETS names
  (this is what keeps knowledge-copilot's 900+-file content corpus, every
  product's docs/40-initiatives/ tree, and this program's own
  benches/decisions/phases dirs out of scope); non-.md files; fenced code
  blocks and inline code spans (see PRECISION); CLAUDE.md/SOUL.md/etc. for
  a repo that does not have one at its root (silently absent, not an
  error — see resolve_scan_targets).

PRECISION (stated plainly): this is a regex/heuristic scanner over
markdown. It WILL have false positives (e.g. a version-looking decimal that
is not actually a claim, a count noun used in a non-claim sentence) and
false negatives (an assertion phrased without a matched pattern, or one that
lives outside scope, or inside a fenced code block or inline code
span — both are skipped on purpose, since they're overwhelmingly commands/
paths, not prose claims). The tool does not try to resolve this by parsing
English better; it resolves it by making the ANNOTATION the ground truth for
"is this backed," and reporting every unannotated verifiable-looking
assertion for a human to triage (annotate, correct, or delete the prose).

STAGED-CONTENT SCANNING (TOCTOU fix, 2026-07-14, QA WP-47): `--check` (the
pre-commit mode) now reads each target file's content from the GIT INDEX
(`git show :<path>`), not the working tree, and enumerates which files are
in scope from the index too (`git ls-files`) rather than a filesystem glob.
Before this fix, `scan_file` always read the working tree: staging a bad
assertion, then editing the working-tree copy back to something clean
WITHOUT re-staging, made the hook scan the (clean-looking) working tree
while the actual commit — built from the index — still carried the bad,
unbacked assertion. The hook now scans exactly what is about to be
committed. `cmd_report`/`cmd_update_baseline` (human-invoked, not a commit
gate) still read the working tree — that's the right content for "what does
the repo look like right now," and neither of those commands makes a
pass/fail decision about a commit.

ESCAPE HATCH, stated plainly: `git commit --no-verify` skips this hook like
it skips every pre-commit hook — that is standard git behavior, not a gap
in this tool, and this script does not attempt to prevent it (no tool can,
short of a server-side check). Treat `--no-verify` on a doc-touching commit
as something to notice in review, not something this script can stop.

Usage:
    tools/cse-bench/claim_sweep.py                    # human-readable report, exit 0
    tools/cse-bench/claim_sweep.py --json              # machine-readable report, exit 0
    tools/cse-bench/claim_sweep.py --check              # pre-commit mode: exit 1 on NEW unbacked (scans the git index)
    tools/cse-bench/claim_sweep.py --check --repo NAME  # scope --check to one repo
    tools/cse-bench/claim_sweep.py --update-baseline [--repo NAME]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent  # copilot-control-tower/

sys.path.insert(0, str(SCRIPT_DIR))
from collectors.paths import resolve_copilot_root  # noqa: E402

DEFAULT_CLAIMS_PATH = REPO_ROOT / "docs" / "40-initiatives" / "01-cse-auditability" / "claims.yaml"
BASELINE_PATH = SCRIPT_DIR / "claim-sweep-baseline.json"

# ---------------------------------------------------------------------------
# Scope: see module docstring "SCOPE" for the full, principled rule and why
# it replaced the old hand-picked SCAN_TARGETS list.
# ---------------------------------------------------------------------------
REPOS: list[str] = [
    "copilot-control-tower",
    "claude-copilot",
    "knowledge-copilot",
    "cli-copilot",
    "codex-copilot",
]

_ROOT_SELF_DESCRIPTION_NAMES: list[str] = [
    "README.md",
    "SOUL.md",
    "PURPOSE.md",
    "ECOSYSTEM.md",
    "CLAUDE.md",
    "AGENTS.md",
]

# Explicit, named additions beyond the formula (root self-description files +
# docs/ depth-1) -- deeper architecture docs F-18's own findings cite by
# path. Every entry here is a reviewable exception, not a hidden allowlist.
_EXTRA_TARGETS: dict[str, list[str]] = {
    "claude-copilot": [
        "docs/10-architecture/04-framework-restructure-2026-04.md",
        "docs/10-architecture/06-hook-deadlock-root-cause-2026-07.md",
    ],
    "codex-copilot": [
        "docs/05-reference/03-parity-contract.md",
        "docs/03-developer-guides/03-specialist-chain-evaluation.md",
    ],
}


def _docs_depth1_worktree(repo_dir: Path) -> list[str]:
    docs_dir = repo_dir / "docs"
    if not docs_dir.is_dir():
        return []
    return sorted(f"docs/{p.name}" for p in docs_dir.iterdir() if p.is_file() and p.suffix == ".md")


def _worktree_listing(repo_dir: Path) -> list[str]:
    names = [n for n in _ROOT_SELF_DESCRIPTION_NAMES if (repo_dir / n).is_file()]
    names += _docs_depth1_worktree(repo_dir)
    return names


def _git_ls_files(repo_dir: Path, pathspecs: list[str]) -> list[str]:
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo_dir), "ls-files", "--"] + pathspecs,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except OSError:
        return []
    if proc.returncode != 0:
        return []
    return [line for line in proc.stdout.splitlines() if line]


def _staged_listing(repo_dir: Path) -> list[str]:
    # Root self-description files: ask git directly (index-based) so a
    # staged-but-not-yet-flushed-to-disk file is still counted.
    root_hits = [f for f in _git_ls_files(repo_dir, _ROOT_SELF_DESCRIPTION_NAMES) if "/" not in f]
    # docs/ depth-1: git's own pathspec globbing for "docs/*.md" matches
    # ACROSS directory boundaries (its `*` is not path-bounded the way a
    # shell glob is), so ask for everything under docs/ and filter to
    # depth-1 .md files ourselves.
    docs_all = _git_ls_files(repo_dir, ["docs/"])
    docs_depth1 = sorted(f for f in docs_all if f.endswith(".md") and f.count("/") == 1)
    return sorted(set(root_hits) | set(docs_depth1))


def resolve_scan_targets(root: Path, repo: str, staged: bool = False) -> list[str]:
    """The list of relpaths in scope for one repo. See module docstring
    SCOPE. `staged=True` resolves against the git INDEX (what `--check`
    guards); `staged=False` resolves against the working tree (what
    `--json`/`--show-unbacked`/`--update-baseline` report on)."""
    repo_dir = root / repo
    base = _staged_listing(repo_dir) if staged else _worktree_listing(repo_dir)
    return sorted(set(base) | set(_EXTRA_TARGETS.get(repo, [])))


# ---------------------------------------------------------------------------
# Assertion detection
# ---------------------------------------------------------------------------
# Priority order matters: earlier patterns claim a span before later, less
# specific patterns get a chance at it (see _line_assertions).
_ASSERTION_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("PERCENT", re.compile(r"-?\d+(?:\.\d+)?\s?%")),
    ("N_OF_M", re.compile(r"\b\d+(?:\.\d+)?\s+of\s+\d+(?:\.\d+)?\b", re.IGNORECASE)),
    (
        "COUNT_UNIT",
        re.compile(
            r"\b\d+(?:,\d{3})*\b\s+"
            r"(?:agents?|services?|commands?|files?|repos?|claims?|tests?|cases?|"
            r"sessions?|projects?|specialists?|skills?|hooks?|extensions?|"
            r"words?|turns?|checks?|definitions?|findings?|rows?|instances?)\b",
            re.IGNORECASE,
        ),
    ),
    ("FRACTION", re.compile(r"\b\d+/\d+\b")),
    ("VERSION", re.compile(r"\bv?\d+\.\d+(?:\.\d+)?\b")),
    ("RATIO_X", re.compile(r"\b\d+(?:\.\d+)?x\b", re.IGNORECASE)),
    ("MECHANISM_CLAIM", re.compile(r"\b(?:automatically|guarantees?|ensures?)\b", re.IGNORECASE)),
]

_FENCE_RE = re.compile(r"^\s*```")
_INLINE_CODE_RE = re.compile(r"`[^`]*`")
_TABLE_SEP_RE = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")
_ANNOTATION_RE = re.compile(r"<!--\s*claim-check:\s*([A-Za-z0-9._-]+)\s*-->")

# The SOUL.md template convention (control-tower, claude-copilot, cli-copilot,
# codex-copilot all share it) opens with a "STATUS: RATIFIED vX.Y" banner and
# closes with a "### Changelog" table of the document's OWN revision
# history ("Revised to v1.3 ...", "| 2026-07-07 | v1.2 RATIFIED | ..."). These
# version numbers describe the DOCUMENT's own version, not a claim about the
# product — verifiably true by definition the moment the doc is edited, so
# they are not the kind of assertion this sweep exists to catch. Lines that
# look like this are exempted from VERSION-category detection only (other
# categories on the same line — e.g. a real count embedded in a changelog
# entry — are still scanned normally).
_CHANGELOG_LINE_RE = re.compile(
    r"RATIFIED|Revised to\s+v?\d|^\s*>?\s*\*{0,2}STATUS:|^\s*\|\s*\d{4}-\d{2}-\d{2}\s*\|",
    re.IGNORECASE,
)


def _strip_line_for_scanning(line: str) -> str:
    """Remove inline code spans (paths/commands, not prose claims) and any
    claim-check annotation comment itself before running assertion regexes,
    so the annotation's own text can never masquerade as an assertion."""
    line = _INLINE_CODE_RE.sub(" ", line)
    line = _ANNOTATION_RE.sub(" ", line)
    return line


def _line_assertions(line: str) -> list[tuple[str, str]]:
    """Return non-overlapping (category, matched_text) pairs for one line,
    scanned in _ASSERTION_PATTERNS priority order."""
    is_changelog_line = bool(_CHANGELOG_LINE_RE.search(line))
    claimed: list[tuple[int, int]] = []
    found: list[tuple[int, str, str]] = []  # (start, category, text)
    for category, pattern in _ASSERTION_PATTERNS:
        if category == "VERSION" and is_changelog_line:
            continue
        for m in pattern.finditer(line):
            start, end = m.span()
            if any(start < c_end and end > c_start for c_start, c_end in claimed):
                continue
            claimed.append((start, end))
            found.append((start, category, m.group(0)))
    found.sort(key=lambda t: t[0])
    return [(cat, text) for _, cat, text in found]


def _iter_scan_lines(text: str) -> list[tuple[int, str]]:
    """Yield (1-based line_no, scannable_line) for every line NOT inside a
    fenced code block and not a markdown table separator row."""
    out: list[tuple[int, str]] = []
    in_fence = False
    for i, raw in enumerate(text.split("\n"), start=1):
        if _FENCE_RE.match(raw):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if _TABLE_SEP_RE.match(raw):
            continue
        out.append((i, raw))
    return out


def _annotations_by_line(lines: list[tuple[int, str]]) -> tuple[dict[int, set[str]], set[int]]:
    """Map line_no -> set of annotation ids found on that raw line, plus the
    set of line numbers that are STANDALONE (the annotation comment, and
    nothing else, once stripped) -- see module docstring BINDING."""
    result: dict[int, set[str]] = {}
    standalone: set[int] = set()
    for line_no, raw in lines:
        ids = set(_ANNOTATION_RE.findall(raw))
        if ids:
            result[line_no] = ids
            if _ANNOTATION_RE.sub("", raw).strip() == "":
                standalone.add(line_no)
    return result, standalone


def _line_annotation_ids(annotations: dict[int, set[str]], standalone: set[int], line_no: int) -> set[str]:
    """An assertion is backed by (a) an annotation trailing its OWN line, or
    (b) a standalone annotation-only line immediately BEFORE it. No other
    adjacency counts -- see module docstring BINDING for why the old
    ±1-either-direction rule was tightened."""
    ids: set[str] = set(annotations.get(line_no, set()))
    prev = line_no - 1
    if prev in standalone:
        ids |= annotations.get(prev, set())
    return ids


def _read_worktree_text(root: Path, repo: str, relpath: str) -> tuple[str | None, str | None]:
    path = root / repo / relpath
    if not path.is_file():
        return None, "file not found"
    return path.read_text(encoding="utf-8", errors="replace"), None


def _read_staged_text(root: Path, repo: str, relpath: str) -> tuple[str | None, str | None]:
    repo_dir = root / repo
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo_dir), "show", f":{relpath}"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except OSError as e:
        return None, f"git show failed: {e}"
    if proc.returncode != 0:
        return None, "not present in the git index (untracked, deleted, or never staged)"
    return proc.stdout, None


def scan_file(repo: str, relpath: str, root: Path, known_claim_ids: set[str], staged: bool = False) -> dict:
    """Scan one file. Returns a dict with 'findings' (list) and 'errors'
    (list) — a missing file is an error entry, never a crash. `staged=True`
    reads the file's content from the git INDEX (see module docstring
    STAGED-CONTENT SCANNING), not the working tree."""
    if staged:
        text, err = _read_staged_text(root, repo, relpath)
    else:
        text, err = _read_worktree_text(root, repo, relpath)
    if text is None:
        return {"findings": [], "errors": [{"repo": repo, "file": relpath, "error": err}]}

    lines = _iter_scan_lines(text)
    annotations, standalone = _annotations_by_line(lines)

    findings = []
    for line_no, raw in lines:
        scannable = _strip_line_for_scanning(raw)
        for category, matched_text in _line_assertions(scannable):
            nearby = _line_annotation_ids(annotations, standalone, line_no)
            resolved = nearby & known_claim_ids
            dangling = nearby - known_claim_ids
            if resolved:
                status = "BACKED"
            elif dangling:
                status = "DANGLING"
            else:
                status = "UNBACKED"
            findings.append(
                {
                    "repo": repo,
                    "file": relpath,
                    "line": line_no,
                    "category": category,
                    "text": matched_text,
                    "status": status,
                    "annotation_ids": sorted(nearby) if nearby else [],
                }
            )
    return {"findings": findings, "errors": []}


# ---------------------------------------------------------------------------
# claims.yaml id loading (reuses check_claims.py's loader — no second parser)
# ---------------------------------------------------------------------------


def _load_known_claim_ids(claims_path: Path) -> set[str]:
    if not claims_path.exists():
        return set()
    import check_claims  # local module, same directory

    data = check_claims.load_yaml(claims_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return set()
    claims = data.get("claims") or []
    ids = set()
    for c in claims:
        if isinstance(c, dict) and isinstance(c.get("id"), str):
            ids.add(c["id"])
    return ids


# ---------------------------------------------------------------------------
# Sweep + baseline
# ---------------------------------------------------------------------------


def run_sweep(
    root: Path,
    claims_path: Path = DEFAULT_CLAIMS_PATH,
    only_repo: str | None = None,
    staged: bool = False,
) -> dict:
    known_ids = _load_known_claim_ids(claims_path)
    all_findings: list[dict] = []
    errors: list[dict] = []
    repos = [only_repo] if only_repo else REPOS
    files_scanned = 0
    for repo in repos:
        relpaths = resolve_scan_targets(root, repo, staged=staged)
        files_scanned += len(relpaths)
        for relpath in relpaths:
            result = scan_file(repo, relpath, root, known_ids, staged=staged)
            all_findings.extend(result["findings"])
            errors.extend(result["errors"])

    n_backed = sum(1 for f in all_findings if f["status"] == "BACKED")
    n_unbacked = sum(1 for f in all_findings if f["status"] == "UNBACKED")
    n_dangling = sum(1 for f in all_findings if f["status"] == "DANGLING")

    per_repo: dict[str, dict] = {}
    for f in all_findings:
        r = per_repo.setdefault(f["repo"], {"scanned": 0, "backed": 0, "unbacked": 0, "dangling": 0})
        r["scanned"] += 1
        r[f["status"].lower()] += 1

    return {
        "metrics": {
            "known_claim_ids": len(known_ids),
            "files_scanned": files_scanned,
            "assertions_total": len(all_findings),
            "assertions_backed": n_backed,
            "assertions_unbacked": n_unbacked,
            "assertions_dangling_annotation": n_dangling,
            "per_repo": per_repo,
            "findings": all_findings,
        },
        "errors": errors,
    }


def _baseline_key(f: dict) -> str:
    raw = f'{f["repo"]}|{f["file"]}|{f["category"]}|{f["text"]}'
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _load_baseline() -> dict[str, dict]:
    if not BASELINE_PATH.exists():
        return {}
    entries = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    return {e["key"]: e for e in entries}


def _write_baseline(unbacked: list[dict]) -> None:
    existing = _load_baseline()
    entries = []
    for f in unbacked:
        key = _baseline_key(f)
        reason = existing.get(key, {}).get("reason", "unreviewed — please annotate a reason")
        entries.append(
            {
                "key": key,
                "repo": f["repo"],
                "file": f["file"],
                "category": f["category"],
                "text": f["text"],
                "reason": reason,
            }
        )
    entries.sort(key=lambda e: (e["repo"], e["file"], e["category"], e["text"]))
    BASELINE_PATH.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")


def cmd_report(args: argparse.Namespace) -> int:
    root = resolve_copilot_root()
    result = run_sweep(root, only_repo=args.repo)
    if args.json:
        print(json.dumps({"schema_version": "cse-bench/claim-sweep/1", **result}, indent=2, sort_keys=True))
        return 0

    m = result["metrics"]
    print(f"claim_sweep: root={root}")
    print(f"claim_sweep: {m['files_scanned']} file(s) scanned across {len(m['per_repo'])} repo(s), {m['known_claim_ids']} known claim id(s)")
    print(
        f"claim_sweep: {m['assertions_total']} verifiable assertion(s) found — "
        f"{m['assertions_backed']} BACKED, {m['assertions_unbacked']} UNBACKED, "
        f"{m['assertions_dangling_annotation']} DANGLING annotation(s)"
    )
    for repo, r in sorted(m["per_repo"].items()):
        print(f"  {repo}: {r['scanned']} scanned, {r['backed']} backed, {r['unbacked']} unbacked, {r['dangling']} dangling")
    if result["errors"]:
        print(f"claim_sweep: {len(result['errors'])} error(s):", file=sys.stderr)
        for e in result["errors"]:
            print(f"  - {e}", file=sys.stderr)
    if args.show_unbacked:
        print("\nUnbacked / dangling assertions:")
        for f in m["findings"]:
            if f["status"] in ("UNBACKED", "DANGLING"):
                print(f"  [{f['status']}] {f['repo']}/{f['file']}:{f['line']} ({f['category']}) {f['text']!r}")
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    root = resolve_copilot_root()
    # Pre-commit mode scans the git INDEX (staged content), not the working
    # tree -- see module docstring STAGED-CONTENT SCANNING (the TOCTOU fix).
    result = run_sweep(root, only_repo=args.repo, staged=True)
    unbacked = [f for f in result["metrics"]["findings"] if f["status"] in ("UNBACKED", "DANGLING")]
    baseline = _load_baseline()
    baseline_keys = set(baseline.keys())

    new_violations = [f for f in unbacked if _baseline_key(f) not in baseline_keys]

    if new_violations:
        print(
            f"claim_sweep --check: {len(new_violations)} NEW unbacked verifiable assertion(s) not in the baseline:",
            file=sys.stderr,
        )
        for f in new_violations:
            print(f"  {f['repo']}/{f['file']}:{f['line']} ({f['category']}) {f['text']!r}", file=sys.stderr)
        print(
            "\nBack it with a registered claims.yaml entry + "
            "<!-- claim-check: <id> --> annotation, correct the prose if it's "
            "false, delete it if unverifiable, or (after review) run "
            "--update-baseline to accept it as a known gap.",
            file=sys.stderr,
        )
        return 1

    # Scope the "now backed" note to the same repo(s) --check just ran
    # against — comparing against the WHOLE baseline file when --repo is
    # given would count every OTHER repo's untouched baseline entries as
    # "gone" too, which is misleading, not just imprecise.
    scoped_baseline_keys = (
        {k for k, e in baseline.items() if e["repo"] == args.repo} if args.repo else baseline_keys
    )
    now_backed = len(scoped_baseline_keys - {_baseline_key(f) for f in unbacked})
    if now_backed:
        print(
            f"claim_sweep --check: note — {now_backed} previously-baselined assertion(s) are now "
            "backed/gone; consider --update-baseline to shrink the baseline."
        )
    print(
        f"claim_sweep --check: OK ({len(unbacked)} known/baselined unbacked, 0 new)"
        + (f" [scope: {args.repo}]" if args.repo else "")
    )
    return 0


def cmd_update_baseline(args: argparse.Namespace) -> int:
    root = resolve_copilot_root()
    if args.repo:
        # Preserve baseline entries for OTHER repos untouched; only refresh
        # this repo's slice.
        existing = list(_load_baseline().values())
        others = [e for e in existing if e["repo"] != args.repo]
        result = run_sweep(root, only_repo=args.repo)
        unbacked = [f for f in result["metrics"]["findings"] if f["status"] in ("UNBACKED", "DANGLING")]
        _write_baseline(unbacked)
        # merge back the other repos' untouched entries
        mine = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
        merged = others + mine
        merged.sort(key=lambda e: (e["repo"], e["file"], e["category"], e["text"]))
        BASELINE_PATH.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
        print(f"claim_sweep: wrote {len(merged)} baseline entries ({len(mine)} for {args.repo}) to {BASELINE_PATH}")
        return 0

    result = run_sweep(root)
    unbacked = [f for f in result["metrics"]["findings"] if f["status"] in ("UNBACKED", "DANGLING")]
    _write_baseline(unbacked)
    print(f"claim_sweep: wrote {len(unbacked)} baseline entries to {BASELINE_PATH}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="claim_sweep.py", description=__doc__.splitlines()[0])
    parser.add_argument("--repo", help="Scope to one repo (see REPOS).")
    parser.add_argument("--json", action="store_true", help="Machine-readable report.")
    parser.add_argument("--show-unbacked", action="store_true", help="List every unbacked/dangling finding.")
    parser.add_argument("--check", action="store_true", help="Pre-commit mode: exit 1 on NEW unbacked assertions (scans the git index).")
    parser.add_argument("--update-baseline", action="store_true", help="Regenerate the baseline from current findings.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.repo and args.repo not in REPOS:
        if args.check:
            # Pre-commit mode, installed generically: a repo outside REPOS
            # has nothing this sweep covers yet — vacuously OK, never a
            # hook failure (mirrors check_claims.py's own "register does not
            # exist yet in this repo" no-op).
            print(f"claim_sweep --check: OK — '{args.repo}' is not in REPOS, nothing to check.")
            return 0
        print(f"claim_sweep: unknown --repo '{args.repo}' (known: {', '.join(sorted(REPOS))})", file=sys.stderr)
        return 1
    if args.update_baseline:
        return cmd_update_baseline(args)
    if args.check:
        return cmd_check(args)
    return cmd_report(args)


if __name__ == "__main__":
    sys.exit(main())
