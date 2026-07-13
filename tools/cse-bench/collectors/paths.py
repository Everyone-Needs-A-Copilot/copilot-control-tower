"""collectors/paths.py — shared COPILOT-workspace-root resolution.

WHY: several collectors (``tasksdb``, ``transcripts``, ``parity``,
``framework_soul``, ``evals``, ``velocity``, ``cli_soul``,
``knowledge_soul``) each need the absolute path to the shared workspace
root that contains every sibling CSE repo (``knowledge-copilot``,
``cli-copilot``, ``claude-copilot``, ``codex-copilot``,
``copilot-control-tower``, ...). That root was hardcoded, independently,
in each of those modules as ``/Volumes/Dev/Sites/COPILOT`` — the owner's
primary machine. On a machine where ``/Volumes/Dev`` is not mounted (this
one), the real, only copy of the tree lives at
``/Users/pabs/Sites/COPILOT`` instead (phase-4-outcome-program-prd.md §1:
"``/Users/pabs/Sites`` symlinks to ``/Volumes/Dev/Sites`` — never
double-count" — true on the primary machine; on a secondary machine there
is no ``/Volumes/Dev`` mount at all and ``/Users/pabs/Sites`` is the real
tree). Every affected collector errored (or, worse, silently degraded to
an empty result with no ``errors`` entry at all — see ``tasksdb.py``'s
glob pattern) on this machine before this fix.

``resolve_copilot_root()`` tries each candidate, in order, and returns
the first that exists as a directory. If neither exists (a genuinely
unconfigured machine), it returns the first (historical) candidate
unchanged — callers already check ``.is_dir()``/glob-match-count
themselves and log a normal ``errors`` entry when nothing resolves, so
this helper never raises and never needs its own error-reporting path.
"""
from __future__ import annotations

from pathlib import Path

# Order matters: the owner's primary machine first (where /Users/pabs/Sites
# is itself a symlink to this same path — see the module docstring), then
# this/other secondary machines where /Volumes/Dev is never mounted and
# /Users/pabs/Sites/COPILOT is the real, only tree.
COPILOT_ROOT_CANDIDATES: list[Path] = [
    Path("/Volumes/Dev/Sites/COPILOT"),
    Path("/Users/pabs/Sites/COPILOT"),
]


def resolve_copilot_root() -> Path:
    """Returns the first candidate root that exists as a directory on this
    machine, or the first (historical) candidate if none exist yet."""
    for candidate in COPILOT_ROOT_CANDIDATES:
        if candidate.is_dir():
            return candidate
    return COPILOT_ROOT_CANDIDATES[0]
