"""collectors/transcripts.py — transcript adoption-metrics collector.

Implements the operational definitions registered in
docs/40-initiatives/01-cse-auditability/claims.yaml: `turn`,
`delegation_rate_tool_share`, `delegation_rate_event_share`,
`protocol_declaration`, `knowledge_read` (BOTH channels: read_tool and
bash_mediated, with the named-file command-position rule),
`knowledge_never_read_denominator` (both variants), and `cli_invocation`
(the command-position rule + entrypoint classes).

Serves PRD-9 (CSE Verification & Benchmark Program), task B-5
(phase-2-prd.md P1). Fixes two Phase-1 blind spots in scope for this
task:
  - H-2 / the register's `knowledge_read.bash_mediated` channel, marked
    "NOT YET IMPLEMENTED" until this collector landed (no native
    Grep/Glob calls exist anywhere in the corpus -- file search happens
    via Bash).
  - F-11, the "stale-join" bug: a mid-corpus repo reorg broke ~60% of
    recorded reads because a straight set-difference against today's
    file inventory silently drops any renamed/moved file. This module's
    "never read" computation is rename-robust and reports its own
    match/fallback/unmatched breakdown rather than degrading silently.
It also extends model-family bucketing with a dedicated fable-class
bucket (Sonnet 5's non-Claude-branded sibling shows up in this corpus as
`claude-fable-5` and would otherwise fall into jsonl_utils.model_family's
generic 'other' bucket).

CORPUS
------
Primary source is the retention archive
(~/.claude/transcript-archive/claude-projects/), which survives Claude
Code's own transcript pruning (see tools/cse-bench/retention/, B-1,
finding F-6: live corpus shrank 113->108 sessions in ~24h). This is
UNIONED with the live corpus (~/.claude/projects/), because the archive
is only synced hourly (retain_transcripts.sh) and can lag the newest live
sessions. The two trees mirror the same relative-path layout (the sync is
a plain `rsync -a`, no renaming), so `.jsonl` files are de-duplicated by
path relative to each root; when a relative path exists in both trees,
the LARGER file wins, then the NEWER one on a size tie -- a still-growing
live session file is more complete than its last hourly snapshot, and an
archive-only-touched copy is otherwise identical. Corpus provenance
(archive_only / live_only / both) is reported in `metrics.corpus`, never
silently collapsed.

The winning-file view is materialized as a temp directory of symlinks
mirroring ~/.claude/projects' own layout (main session files directly
under a project dir; sibling `<sessionId>/subagents/agent-*.jsonl`
files), specifically so the corpus-walking functions reused from
tools/cse-audit below can run against it completely UNMODIFIED.

REUSE (imported via sys.path insertion, not copied)
----------------------------------------------------
  - jsonl_utils: iter_jsonl_records, tool_use_blocks, model_family (the
    base this module's _model_family_ext wraps for the fable bucket).
  - session_metrics: compute_session_metrics (the actual source of the
    `turn`, `delegation_rate_tool_share`, `delegation_rate_event_share`,
    and `protocol_declaration` register entries -- reusing it, rather
    than re-implementing, is what keeps this collector's numbers the
    same definition as the register cites), median_iqr.
  - corpus_scan: find_main_session_files.
  - product_usage: classify_bash_command (cli_invocation's
    command-position rule + entrypoint classes), classify_knowledge_path,
    normalize_knowledge_relpath, inventory_knowledge_repo (the
    knowledge_never_read_denominator `all_files` variant, verbatim),
    find_all_session_files, session_id_for, is_subagent_file, and two
    "private" helpers -- `_segments` / `_LEADING_PREFIX_RE` -- reused
    because they implement the exact command-position splitting rule the
    register's `knowledge_read.bash_mediated` and `cli_invocation`
    entries both cross-reference; forking a second copy of that regex
    logic would risk the two rules drifting apart.

DIVERGENCES (new code in this module, not sourced from cse-audit)
-------------------------------------------------------------------
  - Fable-class model bucketing (`_model_family_ext`): jsonl_utils.py is
    reused, not edited; this wraps it instead.
  - `knowledge_read.bash_mediated` channel: unimplemented anywhere in
    cse-audit per the register; implemented fresh here
    (`_classify_knowledge_bash` + the Bash branch of `_scan_extra`),
    including the directory-target / tool_result-correlation rule.
  - Rename-robust "never read" matching (`_compute_knowledge_never_read`):
    cse-audit's own inventory-vs-read-files comparison
    (product_usage.print_report) is a direct set difference with no
    fallback -- the literal F-11 bug. Implemented fresh here as a
    two-tier match (exact current relpath, then unique-basename
    fallback), with match/fallback/unmatched counts always reported.
"""
from __future__ import annotations

import os
import re
import shlex
import shutil
import sys
import tempfile
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

COLLECTOR_NAME = "transcripts"

# ---------------------------------------------------------------------------
# Reuse tools/cse-audit's corpus-walking / metric-definition code directly,
# via sys.path insertion (see README.md's "Adding a collector" -- there is
# no packaging relationship between tools/cse-bench and tools/cse-audit,
# just a sibling-directory import).
# ---------------------------------------------------------------------------
_CSE_AUDIT_DIR = Path(__file__).resolve().parents[2] / "cse-audit"
if str(_CSE_AUDIT_DIR) not in sys.path:
    sys.path.insert(0, str(_CSE_AUDIT_DIR))

from corpus_scan import find_main_session_files  # noqa: E402
from jsonl_utils import (  # noqa: E402
    iter_jsonl_records,
    model_family as _base_model_family,
    tool_use_blocks,
)
from product_usage import (  # noqa: E402
    _LEADING_PREFIX_RE as _PU_LEADING_PREFIX_RE,
)
from product_usage import _segments as _pu_segments  # noqa: E402
from product_usage import (  # noqa: E402
    classify_bash_command,
    classify_knowledge_path,
    find_all_session_files,
    inventory_knowledge_repo,
    is_subagent_file,
    normalize_knowledge_relpath,
    session_id_for,
)
from session_metrics import compute_session_metrics, median_iqr  # noqa: E402

DEFAULT_ARCHIVE_ROOT = Path.home() / ".claude" / "transcript-archive" / "claude-projects"
DEFAULT_LIVE_ROOT = Path.home() / ".claude" / "projects"
DEFAULT_KNOWLEDGE_REPO_ROOT = Path("/Volumes/Dev/Sites/COPILOT/knowledge-copilot")

_FABLE_MODEL_RE = re.compile(r"fable", re.IGNORECASE)

# Same command-position-match style as product_usage's CLI_COPILOT_BIN_RE /
# CC_BIN_RE: optional absolute-path prefix, the binary name, then a
# negative lookahead so "category" doesn't match "cat".
_READ_BIN_RE = re.compile(r"^(?P<path>(?:/[\w.-]+)*/)?(?P<bin>cat|grep|rg|head|sed)(?![\w/-])")
_PATTERN_CONSUMING_BINS = {"grep", "rg", "sed"}  # first non-flag token is a pattern/script, not a target
_GREP_OUTPUT_LINE_RE = re.compile(r"^([^\n:]+):\d+:")  # grep/rg -n's "path:lineno:" prefix

# Flags that consume the FOLLOWING token as their own value (a flag's
# argument, not a target) -- e.g. `rg --glob '!node_modules/**' pattern
# dir/`: without this, the glob-exclude string is a non-flag token and
# gets misread as a candidate target, and (since it's joined against
# cwd like any relative token) can spuriously resolve to a path "under"
# the knowledge repo when cwd happens to already be inside it. Per
# binary because the same short flag can mean different things (grep
# -n prints line numbers, no value; head -n NUM does consume a value).
_VALUE_FLAGS_BY_BIN = {
    "grep": {"-e", "--regexp", "-f", "--file", "-m", "--max-count", "-A", "-B", "-C", "--context"},
    "rg": {
        "-e", "--regexp", "-f", "--file", "-g", "--glob", "--iglob", "-m", "--max-count",
        "-A", "-B", "-C", "--context", "-t", "--type", "-T", "--type-not", "-M", "--max-columns",
        "--max-depth", "-j", "--threads",
    },
    "sed": {"-e", "--expression", "-f", "--file"},
    "head": {"-n", "--lines", "-c", "--bytes"},
    "cat": set(),
}

_MD_EXCLUDE_DIRS = {".git", ".obsidian", "node_modules", "storybook-static"}

# Leading numeric ordering prefix on a knowledge-repo filename, e.g. the
# "10-" in "10-identity.md". Confirmed by direct inspection (2026-07-12)
# to be the DOMINANT rename pattern behind F-11's stale-join: a
# mid-corpus renumbering kept every file's semantic slug but changed its
# numeric prefix (01-company/02-voice/10-identity.md is gone; the
# content now lives at 01-company/02-voice/01-identity.md -- same slug,
# different prefix, same directory). An exact-basename fallback misses
# this class of rename entirely; stripping the prefix before comparing
# catches it. See _basename_key.
_NUMERIC_PREFIX_RE = re.compile(r"^\d+-")


def _basename_key(relpath: str) -> str:
    """Basename with a leading numeric ordering prefix stripped, used as
    the join key for the basename-fallback rename-robustness tier (see
    _NUMERIC_PREFIX_RE)."""
    return _NUMERIC_PREFIX_RE.sub("", Path(relpath).name)


# ---------------------------------------------------------------------------
# Corpus merge: archive (primary, never-pruned) UNION live (may be newer)
# ---------------------------------------------------------------------------


def _index_jsonl_files(root: Path) -> dict[str, Path]:
    if not root.is_dir():
        return {}
    return {str(p.relative_to(root)): p for p in root.rglob("*.jsonl")}


def _pick_winner(archive_path: Path, live_path: Path) -> Path:
    """Same relative path exists in both corpora. Prefer the larger file,
    then the newer one on a size tie -- a still-growing live session file
    is more complete than its last hourly archive snapshot; an
    archive-only-touched copy (already synced, live unchanged since) is
    otherwise identical content."""
    try:
        a_stat, l_stat = archive_path.stat(), live_path.stat()
    except OSError:
        return live_path
    if a_stat.st_size != l_stat.st_size:
        return live_path if l_stat.st_size > a_stat.st_size else archive_path
    return live_path if l_stat.st_mtime >= a_stat.st_mtime else archive_path


def _merge_indexes(archive_files: dict[str, Path], live_files: dict[str, Path]) -> tuple[dict[str, Path], dict]:
    winners: dict[str, Path] = {}
    provenance = {"archive_only": 0, "live_only": 0, "both": 0}
    for rel in set(archive_files) | set(live_files):
        a = archive_files.get(rel)
        l = live_files.get(rel)
        if a and l:
            provenance["both"] += 1
            winners[rel] = _pick_winner(a, l)
        elif a:
            provenance["archive_only"] += 1
            winners[rel] = a
        else:
            provenance["live_only"] += 1
            winners[rel] = l
    return winners, provenance


def _build_merged_corpus(winners: dict[str, Path]) -> Path:
    """Materialize the winning-file view as a temp directory of symlinks
    mirroring ~/.claude/projects' own layout, so the reused cse-audit
    corpus-walking functions (find_main_session_files,
    find_all_session_files, compute_session_metrics, session_id_for,
    is_subagent_file) run against it completely unmodified. Caller is
    responsible for shutil.rmtree'ing the returned directory."""
    tmp_root = Path(tempfile.mkdtemp(prefix="cse-bench-transcripts-"))
    for rel, src in winners.items():
        dest = tmp_root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            dest.symlink_to(src)
        except OSError:
            continue
    return tmp_root


# ---------------------------------------------------------------------------
# Fable-class model bucket (extends jsonl_utils.model_family without
# editing it -- see module DIVERGENCES)
# ---------------------------------------------------------------------------


def _model_family_ext(raw_model: Optional[str]) -> str:
    if raw_model and _FABLE_MODEL_RE.search(raw_model):
        return "fable"
    return _base_model_family(raw_model)


# ---------------------------------------------------------------------------
# knowledge_read bash_mediated channel (new -- unimplemented in cse-audit)
# ---------------------------------------------------------------------------


def _expand_bash_path(token: str, cwd: Optional[str]) -> Optional[str]:
    """Best-effort ~ / $VAR / relative-to-cwd expansion for a single
    shell-token candidate path, per the bash_mediated channel's
    named_file_match_rule. None for tokens that are clearly not a path
    (empty, or a flag)."""
    if not token or token.startswith("-"):
        return None
    expanded = os.path.expanduser(os.path.expandvars(token)).strip("'\"")
    if not expanded:
        return None
    if not expanded.startswith("/") and cwd:
        expanded = str(Path(cwd) / expanded)
    return expanded


def _extract_bash_targets(binary: str, tail_tokens: list[str]) -> list[str]:
    """Non-flag tokens after the binary name that are plausible file/dir
    targets. For grep/rg/sed the first non-flag token is the
    pattern/script (skipped, not a target). Any '-'-prefixed token is
    skipped as a flag; a flag registered in _VALUE_FLAGS_BY_BIN also
    consumes the token immediately following it (its own value, e.g. the
    glob string after `--glob`) so that value is never misread as a
    target. Any remaining short-option value glued without a space
    (`-A3`) or an unrecognized flag's value still slips through as a
    false-positive target -- harmless in practice, since it then fails
    classify_knowledge_path and is silently dropped rather than
    miscounted as a knowledge-repo read."""
    value_flags = _VALUE_FLAGS_BY_BIN.get(binary, set())
    targets: list[str] = []
    pattern_consumed = binary not in _PATTERN_CONSUMING_BINS
    skip_next = False
    for tok in tail_tokens:
        if skip_next:
            skip_next = False
            continue
        if tok.startswith("-"):
            flag_name = tok.split("=", 1)[0]
            if flag_name in value_flags and "=" not in tok:
                skip_next = True
            continue
        if not pattern_consumed:
            pattern_consumed = True
            continue
        targets.append(tok)
    return targets


def _classify_knowledge_bash(cmd: str, cwd: Optional[str]) -> list[dict]:
    """Find every cat/grep/rg/head/sed call in COMMAND POSITION (reusing
    product_usage's own segment splitter and leading-prefix stripper --
    the same rule the register's bash_mediated channel and cli_invocation
    both cite) and return [{"binary": ..., "targets": [expanded paths]}, ...]."""
    if not cmd:
        return []
    hits: list[dict] = []
    for _offset, seg in _pu_segments(cmd):
        stripped = _PU_LEADING_PREFIX_RE.match(seg)
        prefix_len = stripped.end() if stripped else 0
        body = seg[prefix_len:]
        m = _READ_BIN_RE.match(body)
        if not m:
            continue
        binary = m.group("bin")
        tail = body[m.end():]
        try:
            tail_tokens = shlex.split(tail, posix=True)
        except ValueError:
            continue  # malformed shell fragment (unbalanced quote, heredoc, ...) -- skip, don't crash
        resolved = [
            expanded
            for tok in _extract_bash_targets(binary, tail_tokens)
            if (expanded := _expand_bash_path(tok, cwd))
        ]
        if resolved:
            hits.append({"binary": binary, "targets": resolved})
    return hits


def _tool_result_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        return "\n".join(parts)
    return ""


def _extract_paths_from_grep_output(text: str) -> list[str]:
    """Heuristic extraction of file paths from a grep/rg tool_result: the
    `path:lineno:` prefix grep/rg -n emit by default, or (fallback) a
    bare path per line for -l/--files-with-matches/--files output. This
    is the named_file_match_rule's "every file named in that call's OWN
    tool_result output" -- intentionally approximate; ripgrep/grep output
    formatting has more variants (-A/-B context, --json, ...) than are
    worth chasing here, and a call that finds zero matches correctly
    yields no paths (reads nothing), per the rule."""
    paths: list[str] = []
    for line in text.splitlines():
        line = line.rstrip()
        if not line:
            continue
        m = _GREP_OUTPUT_LINE_RE.match(line)
        if m:
            paths.append(m.group(1))
        elif "/" in line and ":" not in line:
            paths.append(line.strip())
    return paths


# ---------------------------------------------------------------------------
# Per-session extraction: model family, cli_invocation, knowledge_read
# (both channels). compute_session_metrics (reused) already covers turns,
# delegation rates, protocol-declaration rates, and agent_type mix.
# ---------------------------------------------------------------------------


@dataclass
class SessionExtra:
    session_id: str
    project_slug: str = ""
    model_msgs_main: Counter = field(default_factory=Counter)
    model_msgs_sub: Counter = field(default_factory=Counter)
    cli_invocations: Counter = field(default_factory=Counter)
    knowledge_read_tool_relpaths: set = field(default_factory=set)
    knowledge_bash_relpaths: set = field(default_factory=set)


def _scan_extra(
    path: Path,
    session_id: str,
    project_slug: str,
    is_sub: bool,
    sessions: dict[str, SessionExtra],
) -> None:
    """One streaming pass per jsonl file (main OR subagent -- both are
    attributed to the same session id, mirroring
    product_usage.scan_corpus) extracting everything
    compute_session_metrics does not: fable-extended model family,
    cli_invocation classes, and both knowledge_read channels."""
    se = sessions.setdefault(session_id, SessionExtra(session_id=session_id, project_slug=project_slug))
    pending_dir_targets: dict[str, list[str]] = {}
    cwd: Optional[str] = None

    for rec in iter_jsonl_records(path):
        if cwd is None and rec.get("cwd"):
            cwd = rec["cwd"]
        rtype = rec.get("type")

        if rtype == "assistant":
            msg = rec.get("message") or {}
            fam = _model_family_ext(msg.get("model"))
            if fam not in ("synthetic", "unknown"):
                (se.model_msgs_sub if is_sub else se.model_msgs_main)[fam] += 1

            for b in tool_use_blocks(msg.get("content")):
                name = b.get("name")
                tool_input = b.get("input") or {}
                tool_id = b.get("id")

                if name == "Bash":
                    cmd = tool_input.get("command") or ""
                    for c in classify_bash_command(cmd):
                        se.cli_invocations[c.engine] += 1

                    for hit in _classify_knowledge_bash(cmd, cwd):
                        dir_targets: list[str] = []
                        for target in hit["targets"]:
                            if classify_knowledge_path(target) != "primary":
                                continue
                            if Path(target).is_dir():
                                dir_targets.append(target)
                            else:
                                rel = normalize_knowledge_relpath(target)
                                if rel:
                                    se.knowledge_bash_relpaths.add(rel)
                        if dir_targets and tool_id:
                            pending_dir_targets.setdefault(tool_id, []).extend(dir_targets)

                elif name == "Read":
                    fp = tool_input.get("file_path") or ""
                    if classify_knowledge_path(fp) == "primary":
                        rel = normalize_knowledge_relpath(fp)
                        if rel:
                            se.knowledge_read_tool_relpaths.add(rel)

                elif name in ("Grep", "Glob"):
                    p = tool_input.get("path") or tool_input.get("pattern") or ""
                    if classify_knowledge_path(p) == "primary":
                        rel = normalize_knowledge_relpath(p)
                        if rel:
                            se.knowledge_read_tool_relpaths.add(rel)

        elif rtype == "user" and pending_dir_targets:
            msg = rec.get("message") or {}
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for b in content:
                if not (isinstance(b, dict) and b.get("type") == "tool_result"):
                    continue
                tid = b.get("tool_use_id")
                if tid not in pending_dir_targets:
                    continue
                output_text = _tool_result_text(b.get("content"))
                for found in _extract_paths_from_grep_output(output_text):
                    # rg/grep print matched paths relative to the CALLER's
                    # cwd, not relative to the searched directory argument
                    # -- so re-resolve against session cwd, same as any
                    # other bash-mediated target.
                    expanded = _expand_bash_path(found, cwd)
                    if expanded and classify_knowledge_path(expanded) == "primary":
                        rel = normalize_knowledge_relpath(expanded)
                        if rel:
                            se.knowledge_bash_relpaths.add(rel)
                del pending_dir_targets[tid]


# ---------------------------------------------------------------------------
# Rename-robust knowledge-repo inventory matching (fixes F-11)
# ---------------------------------------------------------------------------


def _inventory_knowledge_md(repo_root: Path) -> set[str]:
    """*.md files under repo_root, excluding vendored/tooling directories
    -- the knowledge_md denominator variant registered in claims.yaml
    (definitions.knowledge_never_read_denominator.variants.knowledge_md).
    Deliberately NOT product_usage.inventory_knowledge_repo() -- that one
    implements the sibling all_files variant with a narrower default
    exclusion set that does not exclude storybook build output (see that
    variant's own OPEN GAP note in the register)."""
    if not repo_root.is_dir():
        return set()
    out = set()
    for p in repo_root.rglob("*.md"):
        if not p.is_file():
            continue
        rel = p.relative_to(repo_root)
        if any(part in _MD_EXCLUDE_DIRS for part in rel.parts):
            continue
        out.add(str(rel))
    return out


def _match_against_inventory(recorded: set[str], inv_all: set[str], basename_index: dict[str, list[str]]) -> dict:
    """Two-tier rename-robust match: exact relpath against today's
    inventory first, then (if not found) a unique-basename fallback
    (basename compared via _basename_key, i.e. numeric-ordering-prefix
    stripped -- see that function). A recorded path with zero or MORE
    THAN ONE same-basename candidate is `unmatched` -- ambiguity
    degrades the metric visibly (reported), it is never guessed at.
    This is the fix for F-11's silent stale-join."""
    matched_current: set[str] = set()
    matched_basename_fallback: set[str] = set()
    unmatched: set[str] = set()
    canonical: set[str] = set()  # today's relpath each recorded read maps to

    for rel in recorded:
        if rel in inv_all:
            matched_current.add(rel)
            canonical.add(rel)
            continue
        candidates = basename_index.get(_basename_key(rel), [])
        if len(candidates) == 1:
            matched_basename_fallback.add(rel)
            canonical.add(candidates[0])
        else:
            unmatched.add(rel)

    return {
        "recorded_total": len(recorded),
        "matched_current": len(matched_current),
        "matched_basename_fallback": len(matched_basename_fallback),
        "unmatched": len(unmatched),
        "unmatched_examples": sorted(unmatched)[:20],
        "_canonical_files": canonical,  # stripped before this dict is emitted (internal use only)
    }


def _compute_knowledge_never_read(
    extras: dict[str, SessionExtra],
    knowledge_repo_root: Path,
    errors: list[dict],
) -> dict:
    recorded_read_tool: set[str] = set()
    recorded_bash: set[str] = set()
    for se in extras.values():
        recorded_read_tool |= se.knowledge_read_tool_relpaths
        recorded_bash |= se.knowledge_bash_relpaths

    try:
        inv_all = inventory_knowledge_repo(knowledge_repo_root)
    except OSError as exc:
        errors.append({"error": f"knowledge repo inventory failed: {type(exc).__name__}: {exc}"})
        inv_all = set()
    inv_md = _inventory_knowledge_md(knowledge_repo_root)

    basename_index: dict[str, list[str]] = defaultdict(list)
    for rel in inv_all:
        basename_index[_basename_key(rel)].append(rel)

    m_read_tool = _match_against_inventory(recorded_read_tool, inv_all, basename_index)
    m_bash = _match_against_inventory(recorded_bash, inv_all, basename_index)
    m_union = _match_against_inventory(recorded_read_tool | recorded_bash, inv_all, basename_index)

    canonical_read_tool = m_read_tool.pop("_canonical_files")
    canonical_bash = m_bash.pop("_canonical_files")
    canonical_union = m_union.pop("_canonical_files")

    never_md = inv_md - (canonical_union & inv_md)
    never_all = inv_all - canonical_union

    return {
        "read_tool_channel": m_read_tool,
        "bash_mediated_channel": m_bash,
        "union_channel_matching": m_union,
        "distinct_files": {
            "read_tool": len(canonical_read_tool),
            "bash_mediated": len(canonical_bash),
            "bash_only": len(canonical_bash - canonical_read_tool),
            "union": len(canonical_union),
        },
        "never_read": {
            "knowledge_md": {
                "denominator": len(inv_md),
                "never_read_count": len(never_md),
                "never_read_pct": (len(never_md) / len(inv_md) * 100.0) if inv_md else None,
            },
            "all_files": {
                "denominator": len(inv_all),
                "never_read_count": len(never_all),
                "never_read_pct": (len(never_all) / len(inv_all) * 100.0) if inv_all else None,
            },
        },
    }


# ---------------------------------------------------------------------------
# Aggregation (shared by the global scope and each per-ISO-week scope)
# ---------------------------------------------------------------------------


def _share(counter: Counter) -> dict:
    total = sum(counter.values())
    return {k: v / total for k, v in counter.items()} if total else {}


def _aggregate_scope(session_ids: list[str], base_metrics: dict, extras: dict[str, SessionExtra]) -> dict:
    sms = [base_metrics[sid] for sid in session_ids if sid in base_metrics]

    model_main: Counter = Counter()
    model_combined: Counter = Counter()
    agent_types: Counter = Counter()
    cli_by_class: Counter = Counter()
    n_touching_knowledge = 0
    n_touching_read_tool = 0
    n_touching_bash_mediated = 0

    for sid in session_ids:
        se = extras.get(sid)
        if se is not None:
            model_main.update(se.model_msgs_main)
            model_combined.update(se.model_msgs_main)
            model_combined.update(se.model_msgs_sub)
            cli_by_class.update(se.cli_invocations)
            if se.knowledge_read_tool_relpaths:
                n_touching_read_tool += 1
            if se.knowledge_bash_relpaths:
                n_touching_bash_mediated += 1
            if se.knowledge_read_tool_relpaths or se.knowledge_bash_relpaths:
                n_touching_knowledge += 1
        sm = base_metrics.get(sid)
        if sm is not None:
            agent_types.update(sm.delegated_agent_types)

    n = len(session_ids)
    return {
        "n_sessions": n,
        "turns_per_session": median_iqr([float(sm.turns) for sm in sms]),
        "delegation_rate_tool_share": median_iqr(
            [sm.delegation_rate_toolshare for sm in sms if sm.delegation_rate_toolshare is not None]
        ),
        "delegation_rate_event_share": median_iqr(
            [sm.delegation_rate_eventshare for sm in sms if sm.delegation_rate_eventshare is not None]
        ),
        "protocol_declaration_rate_loose": median_iqr(
            [sm.protocol_declaration_rate_all for sm in sms if sm.protocol_declaration_rate_all is not None]
        ),
        "protocol_declaration_rate_strict": median_iqr(
            [
                sm.protocol_declaration_rate_first_of_turn
                for sm in sms
                if sm.protocol_declaration_rate_first_of_turn is not None
            ]
        ),
        "model_mix": {
            "main_session_only": {"counts": dict(model_main), "share": _share(model_main)},
            "combined": {"counts": dict(model_combined), "share": _share(model_combined)},
        },
        "agent_type_mix": {"counts": dict(agent_types), "share": _share(agent_types)},
        "cli_invocation": {"by_class": dict(cli_by_class)},
        "knowledge_read": {
            "sessions_touching": n_touching_knowledge,
            "sessions_touching_pct": (n_touching_knowledge / n * 100.0) if n else None,
            "sessions_touching_read_tool_only_channel": n_touching_read_tool,
            "sessions_touching_read_tool_only_channel_pct": (n_touching_read_tool / n * 100.0) if n else None,
            "sessions_touching_bash_mediated_channel": n_touching_bash_mediated,
            "sessions_touching_bash_mediated_channel_pct": (n_touching_bash_mediated / n * 100.0) if n else None,
        },
    }


def _iso_week_key(ts: Optional[str]) -> Optional[tuple[int, int]]:
    if not ts:
        return None
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt.date().isocalendar()[:2]


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def collect(
    archive_root: Optional[str] = None,
    live_root: Optional[str] = None,
    knowledge_repo_root: Optional[str] = None,
) -> dict:
    """Scan the merged (archive UNION live) transcript corpus.

    Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []
    archive_root_p = Path(archive_root).expanduser() if archive_root else DEFAULT_ARCHIVE_ROOT
    live_root_p = Path(live_root).expanduser() if live_root else DEFAULT_LIVE_ROOT
    knowledge_repo_root_p = Path(knowledge_repo_root) if knowledge_repo_root else DEFAULT_KNOWLEDGE_REPO_ROOT

    archive_files = _index_jsonl_files(archive_root_p)
    live_files = _index_jsonl_files(live_root_p)
    winners, provenance = _merge_indexes(archive_files, live_files)

    corpus_metrics = {
        "archive_root": str(archive_root_p),
        "live_root": str(live_root_p),
        "archive_jsonl_files": len(archive_files),
        "live_jsonl_files": len(live_files),
        "provenance": provenance,
        "merged_distinct_jsonl_files": len(winners),
    }

    if not winners:
        errors.append({"error": "no .jsonl transcripts found under either the archive or live corpus root"})
        return {"metrics": {"corpus": corpus_metrics}, "errors": errors}

    merged_dir = _build_merged_corpus(winners)
    try:
        main_files = find_main_session_files(merged_dir)
        all_files = find_all_session_files(merged_dir)

        base_metrics: dict[str, object] = {}
        for mf in main_files:
            try:
                base_metrics[mf.stem] = compute_session_metrics(mf)
            except Exception as exc:  # one bad transcript must never crash the run
                errors.append({"session_file": str(mf), "error": f"{type(exc).__name__}: {exc}"})

        extras: dict[str, SessionExtra] = {}
        for f in all_files:
            try:
                sid = session_id_for(f, merged_dir)
                is_sub = is_subagent_file(f, merged_dir)
                project_slug = f.relative_to(merged_dir).parts[0]
                _scan_extra(f, sid, project_slug, is_sub, extras)
            except Exception as exc:
                errors.append({"session_file": str(f), "error": f"{type(exc).__name__}: {exc}"})

        all_session_ids = sorted(base_metrics.keys())
        global_scope = _aggregate_scope(all_session_ids, base_metrics, extras)
        global_scope["knowledge_read"].update(
            _compute_knowledge_never_read(extras, knowledge_repo_root_p, errors)
        )

        week_buckets: dict[tuple[int, int], list[str]] = defaultdict(list)
        for sid, sm in base_metrics.items():
            key = _iso_week_key(sm.start_ts)
            if key:
                week_buckets[key].append(sid)

        weekly = {
            f"{key[0]}-W{key[1]:02d}": _aggregate_scope(week_buckets[key], base_metrics, extras)
            for key in sorted(week_buckets)
        }

        metrics = {
            "corpus": corpus_metrics,
            "knowledge_repo_root": str(knowledge_repo_root_p),
            "global": global_scope,
            "weekly": weekly,
            "definitions": {
                "turn / delegation_rate_tool_share / delegation_rate_event_share / protocol_declaration": (
                    "as registered in docs/40-initiatives/01-cse-auditability/claims.yaml `definitions:`; "
                    "reused unmodified from tools/cse-audit/session_metrics.py. "
                    "protocol_declaration_rate_loose == that register entry's `_all` denominator; "
                    "protocol_declaration_rate_strict == its `_first_of_turn` denominator."
                ),
                "model_mix": (
                    "family share of assistant messages (main-session-only and main+subagent combined). "
                    "Family bucketing extends tools/cse-audit/jsonl_utils.model_family with a dedicated "
                    "'fable' bucket (substring match on the raw model string) ahead of the 'other' catch-all "
                    "it would otherwise fall into -- this corpus's fable-class model string is 'claude-fable-5'."
                ),
                "agent_type_mix": (
                    "counts of tools/cse-audit/session_metrics.py's delegated_agent_types (subagent_type of "
                    "each main-session Agent/Task tool_use call)."
                ),
                "cli_invocation.by_class": (
                    "as registered under claims.yaml definitions.cli_invocation; reused unmodified from "
                    "tools/cse-audit/product_usage.classify_bash_command. Reports every engine class "
                    "returned (cli_copilot_unambiguous, cli_copilot_bare, cc_framework, cc_ambiguous, "
                    "cc_compiler, gh_copilot), not only the four headline classes."
                ),
                "knowledge_read": (
                    "as registered under claims.yaml definitions.knowledge_read; sessions_touching counts a "
                    "session if EITHER channel (read_tool OR bash_mediated) fired at least once."
                ),
                "knowledge_read.never_read": (
                    "as registered under claims.yaml definitions.knowledge_never_read_denominator, both "
                    "variants. Rename-robust match (fixes F-11's silent stale-join): a recorded relpath is "
                    "matched_current if it exists verbatim in today's inventory, matched_basename_fallback "
                    "if exactly one current file shares its basename, else unmatched -- an unmatched path is "
                    "excluded from the 'read' credit (so it never silently deflates never-read) AND its own "
                    "count is always reported (so it never silently inflates confidence in the match either)."
                ),
                "weekly": (
                    "same aggregate shape as `global`, minus never_read (a corpus-wide inventory comparison, "
                    "not meaningful decomposed per week), bucketed by ISO week of each session's start_ts."
                ),
            },
        }
        return {"metrics": metrics, "errors": errors}
    finally:
        shutil.rmtree(merged_dir, ignore_errors=True)
