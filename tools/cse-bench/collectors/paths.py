"""collectors/paths.py — shared workspace-root resolution.

WHY: several collectors (``tasksdb``, ``transcripts``, ``parity``,
``framework_soul``, ``evals``, ``velocity``, ``cli_soul``,
``knowledge_soul``) each need the absolute path to a shared workspace
root that contains sibling repos. That root was hardcoded, independently,
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

TWO ROOTS (2026-08 directory migration): 20 framework/product repos
(``claude-copilot``, ``cli-copilot``, ``codex-copilot``,
``knowledge-copilot``, ``knowledge-copilot-internal``,
``copilot-control-tower``, and their ``-private``/``-accounting``/
``-internal`` siblings, plus ``copilot-bench`` and
``product-creation-copilot``) moved from ``.../Sites/COPILOT/<name>`` to
``.../Sites/CSE/<name>``. Roughly a dozen other product repos
(``convoco``, ``pipeline-copilot``, ``insights-copilot``, ...) did
**not** move and still live under ``.../Sites/COPILOT/<name>``. There is
therefore no longer a single "shared workspace root" — a collector that
needs a moved repo must resolve against the CSE root; a collector that
needs an unmoved repo, or that scans across the *whole* ecosystem
(both moved and unmoved), must resolve against (or merge across) both.
``resolve_cse_root()`` is the CSE-root counterpart of
``resolve_copilot_root()``, with the identical candidate-list /
first-that-exists / historical-fallback contract. This is deliberately a
**second function**, not a longer candidate list on the original one:
the two roots hold disjoint repo sets, so a single list that tried both
directories in some order would silently resolve a moved-repo lookup
against the (still-existing) COPILOT root's unrelated top level, or vice
versa, instead of failing loudly. Callers must pick the resolver that
matches what they actually look up, and a caller that needs both must
call both explicitly and merge/report per-root, never fall back silently
from one root to the other.
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

# Same two-spelling contract as COPILOT_ROOT_CANDIDATES above, for the CSE
# root that the 20 framework/product repos moved to (see the module
# docstring's "TWO ROOTS" section).
CSE_ROOT_CANDIDATES: list[Path] = [
    Path("/Volumes/Dev/Sites/CSE"),
    Path("/Users/pabs/Sites/CSE"),
]


def resolve_copilot_root() -> Path:
    """Returns the first candidate root that exists as a directory on this
    machine, or the first (historical) candidate if none exist yet."""
    for candidate in COPILOT_ROOT_CANDIDATES:
        if candidate.is_dir():
            return candidate
    return COPILOT_ROOT_CANDIDATES[0]


def resolve_cse_root() -> Path:
    """CSE-root counterpart of ``resolve_copilot_root()`` — same contract:
    returns the first candidate that exists as a directory on this
    machine, or the first (historical) candidate if none exist yet."""
    for candidate in CSE_ROOT_CANDIDATES:
        if candidate.is_dir():
            return candidate
    return CSE_ROOT_CANDIDATES[0]
