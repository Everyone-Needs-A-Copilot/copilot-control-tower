"""
framework_registry.py — classify a project's *current* framework-install
status by inspecting its .claude/ directory on disk.

IMPORTANT LIMITATION (read before trusting this): this is a snapshot of
TODAY's filesystem state, not a historical record of what was installed at
the time any given session ran. A project could have had hooks installed
and later removed them, or vice versa. We do not have a way to reconstruct
historical .claude/settings.json contents for arbitrary projects (only
claude-copilot itself is a git repo we can walk with `git log`). Treat the
resulting labels as "as of 2026-07-11", and treat any pre/post inference
drawn across dates as a weaker claim than the within-date comparison.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# How many parent directories to walk up looking for a .claude/ dir, since
# some recorded `cwd` values are subdirectories of a repo (e.g.
# .../convoco/backend has no .claude of its own; .../convoco/.claude is the
# real one).
MAX_CLIMB = 5


@dataclass
class FrameworkStatus:
    cwd: str
    claude_dir: Optional[str]
    agents_present: bool
    mechanical_hooks_registered: bool
    hook_matcher_covers_read_edit: Optional[bool]  # None if hooks absent entirely
    registered_pretool_hook_path: Optional[str]


def _find_claude_dir(cwd: str) -> Optional[Path]:
    p = Path(cwd)
    for _ in range(MAX_CLIMB):
        candidate = p / ".claude"
        if candidate.is_dir():
            return candidate
        if p.parent == p:
            break
        p = p.parent
    return None


def classify_project(cwd: str) -> FrameworkStatus:
    claude_dir = _find_claude_dir(cwd)
    if claude_dir is None:
        return FrameworkStatus(cwd, None, False, False, None, None)

    agents_present = (claude_dir / "agents").is_dir()

    settings_path = claude_dir / "settings.json"
    mechanical_hooks_registered = False
    covers_read_edit: Optional[bool] = None
    pretool_path: Optional[str] = None

    if settings_path.is_file():
        try:
            settings = json.loads(settings_path.read_text())
        except (json.JSONDecodeError, OSError):
            settings = {}
        pretool_hooks = settings.get("hooks", {}).get("PreToolUse", [])
        for entry in pretool_hooks:
            matcher = entry.get("matcher", "")
            for h in entry.get("hooks", []):
                cmd = h.get("command", "")
                if "pretool-check.sh" in cmd or "pretool_check" in cmd:
                    mechanical_hooks_registered = True
                    pretool_path = cmd
                    covers_read_edit = ("Read" in matcher) and ("Edit" in matcher)

    return FrameworkStatus(
        cwd=cwd,
        claude_dir=str(claude_dir),
        agents_present=agents_present,
        mechanical_hooks_registered=mechanical_hooks_registered,
        hook_matcher_covers_read_edit=covers_read_edit,
        registered_pretool_hook_path=pretool_path,
    )


def classify_projects(cwds: set[str]) -> dict[str, FrameworkStatus]:
    return {cwd: classify_project(cwd) for cwd in cwds}
