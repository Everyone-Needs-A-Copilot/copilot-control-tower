"""collectors/velocity.py — repo velocity collector.

Runs `git -C <repo> log --since=90.days` class plumbing against every CSE
repo under /Volumes/Dev/Sites/COPILOT/ and reports commits in the last 90
days, the last-commit ISO timestamp, the current branch, and a dirty-tree
flag (count of changed/untracked paths only -- never filenames, which
could carry sensitive path fragments into a shared benchmark output).

Serves PRD-9 (CSE Verification & Benchmark Program), task B-6.

Design notes
------------
- Each repo is scanned independently; a repo that is missing, not a git
  checkout, or whose git invocation fails produces a per-repo entry in
  the returned ``errors`` list -- it never raises out of ``collect()``
  and never aborts the scan of the remaining repos (same contract as
  ``collectors/tasksdb.py``).
- "Commits in the last 90 days" is reachable-from-HEAD history on
  whatever branch is currently checked out, matching the literal
  `git log --since=90.days --oneline | wc -l` the task specifies -- it
  is not a cross-branch or all-refs count.
- The dirty-tree flag is a count derived from `git status --porcelain`
  line count; the porcelain output itself (which contains filenames) is
  never retained or returned.
"""
from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Optional

from collectors.paths import resolve_copilot_root

COLLECTOR_NAME = "velocity"

COPILOT_ROOT = resolve_copilot_root()
REPOS = [
    "claude-copilot",
    "codex-copilot",
    "knowledge-copilot",
    "cli-copilot",
    "copilot-control-tower",
]
WINDOW_DAYS = 90
_GIT_TIMEOUT_SECONDS = 30


def _git(repo_path: Path, *args: str) -> str:
    """Run a git subcommand against repo_path. Raises RuntimeError (with
    the repo path and git's own stderr) on any non-zero exit or timeout;
    the caller turns that into a per-repo error entry.
    """
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_path), *args],
            capture_output=True,
            text=True,
            timeout=_GIT_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"git {' '.join(args)} timed out after {_GIT_TIMEOUT_SECONDS}s") from exc
    except OSError as exc:
        raise RuntimeError(f"git {' '.join(args)} failed to start: {exc}") from exc

    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} exited {result.returncode}: {result.stderr.strip()}")
    return result.stdout


def _scan_repo(repo_path: Path) -> dict:
    """Collect velocity metrics for a single repo. Any RuntimeError
    propagates to the caller, which turns it into a per-repo error entry
    rather than crashing the run.
    """
    if not repo_path.is_dir():
        raise RuntimeError(f"not a directory: {repo_path}")

    # Fail fast with a clear message if this isn't a git checkout at all,
    # rather than letting every subsequent git call fail obscurely.
    _git(repo_path, "rev-parse", "--is-inside-work-tree")

    log_output = _git(repo_path, "log", f"--since={WINDOW_DAYS}.days", "--oneline")
    commits_90d = sum(1 for line in log_output.splitlines() if line.strip())

    last_commit_raw = _git(repo_path, "log", "-1", "--format=%cI").strip()
    last_commit_at: Optional[str] = last_commit_raw or None

    branch = _git(repo_path, "rev-parse", "--abbrev-ref", "HEAD").strip()

    status_output = _git(repo_path, "status", "--porcelain")
    changed_count = sum(1 for line in status_output.splitlines() if line.strip())

    return {
        "path": str(repo_path),
        "commits_90d": commits_90d,
        "last_commit_at": last_commit_at,
        "branch": branch,
        "dirty": {
            "is_dirty": changed_count > 0,
            "changed_path_count": changed_count,
        },
    }


def collect(repos: list[str] = REPOS, copilot_root: Path = COPILOT_ROOT) -> dict:
    """Scan every repo in `repos` under `copilot_root`.

    Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []
    per_repo: dict = {}

    for repo_name in repos:
        repo_path = copilot_root / repo_name
        try:
            per_repo[repo_name] = _scan_repo(repo_path)
        except RuntimeError as exc:
            errors.append({"repo": repo_name, "path": str(repo_path), "error": str(exc)})
        except Exception as exc:  # a single bad repo must never crash the run
            errors.append(
                {
                    "repo": repo_name,
                    "path": str(repo_path),
                    "error": f"unexpected {type(exc).__name__}: {exc}",
                }
            )

    total_commits_90d = sum(r["commits_90d"] for r in per_repo.values())
    dirty_repos = sorted(name for name, r in per_repo.items() if r["dirty"]["is_dirty"])

    metrics = {
        "copilot_root": str(copilot_root),
        "window_days": WINDOW_DAYS,
        "repos_requested": list(repos),
        "repos_scanned": sorted(per_repo.keys()),
        "repos_skipped": sorted(e["repo"] for e in errors),
        "totals": {
            "commits_90d": total_commits_90d,
            "dirty_repo_count": len(dirty_repos),
            "dirty_repos": dirty_repos,
        },
        "per_repo": per_repo,
        "definitions": {
            "commits_90d": "count of `git log --since=90.days --oneline` lines reachable from the currently checked-out HEAD (not all-refs, not all-branches)",
            "last_commit_at": "ISO 8601 committer date (`git log -1 --format=%cI`) of HEAD; null for a repo with no commits",
            "branch": "`git rev-parse --abbrev-ref HEAD`; literal 'HEAD' for a detached-HEAD checkout",
            "dirty.is_dirty": "true if `git status --porcelain` produced any output",
            "dirty.changed_path_count": "line count of `git status --porcelain` (staged + unstaged + untracked); filenames are never retained or returned",
        },
    }
    return {"metrics": metrics, "errors": errors}
