"""
product_usage.py — usage archaeology for two products: CLI Copilot (the
`copilot`/`cli_copilot` binary, repo `cli-copilot`) and Knowledge Copilot
(the knowledge repo, canonically `knowledge-copilot-internal/`, aliased as
`shared-docs` and `~/.claude/knowledge`).

Question under investigation: are these products *actually used* in real
Claude Code sessions, empirically, from the transcript corpus? This module
makes NO recommendations — it only counts and classifies.

===========================================================================
DISAMBIGUATION (read before trusting any number this module produces)
===========================================================================

Four programs share two command names on this machine (verified 2026-07-12,
cross-checked against `cli-copilot/pyproject.toml [project.scripts]` and
`claude-copilot/tools/cc/pyproject.toml [project.scripts]`, and consistent
with prior working memory `four-programs-two-names.md`):

    | Typed name                  | Resolves to                          | Product                |
    |------------------------------|--------------------------------------|-------------------------|
    | `copilot` (interactive shell)| shell alias -> `cd .../COPILOT`      | NOT a program           |
    | `/opt/homebrew/bin/copilot`  | copilot_cli.main:app                 | CLI Copilot             |
    | `cli_copilot`                | copilot_cli.main:app                 | CLI Copilot             |
    | `cc` (`~/.local/bin/cc`)     | cc.main:app (claude-copilot/tools/cc)| claude-copilot framework|
    | `/usr/bin/cc`                | the C compiler                       | NOT a copilot product   |

CLI Copilot's own `pyproject.toml` registers exactly two console scripts —
`copilot` and `cli_copilot` — and NOTHING named `cc`. `cc` is a wholly
separate product (claude-copilot's memory/skill/config/docs/eval/env CLI).
Conflating "cc memory search" or "cc env" calls with CLI Copilot usage would
be a serious over-count of a product that was never actually invoked.
Consequently: **this module counts `cc ...` invocations SEPARATELY, labeled
`cc_framework`, and never adds them into the CLI Copilot numbers.**

Within Bash commands, a bare `copilot` token is ambiguous on this machine:
because of the shell alias, a bare `copilot <verb>` typed in an interactive
shell would `cd` rather than invoke the binary. Whether the *Bash tool's*
non-interactive shell sources that alias is not something we can determine
from the transcript alone (it depends on `.bashrc`/`.zshrc` sourcing, which
varies by shell invocation flags) — so bare-`copilot` occurrences are kept
in a separate `cli_copilot_bare` bucket from unambiguous absolute-path /
`cli_copilot`-named invocations, with the tool_result's `is_error` flag and
a text excerpt captured as corroborating evidence for a manual read.

`gh copilot` (GitHub's own Copilot CLI extension) is excluded entirely by
checking for a preceding `gh` token.

===========================================================================
Knowledge Copilot path aliasing
===========================================================================

`shared-docs` and `~/.claude/knowledge` are both **symlinks** to the same
`knowledge-copilot-internal/` directory (verified via `ls -la` / `readlink`;
the mature content was renamed from bare `knowledge-copilot` to
`knowledge-copilot-internal` — a new, thin, generic public-base repo now
occupies the bare `knowledge-copilot` name):

    /Volumes/Dev/Sites/COPILOT/shared-docs -> knowledge-copilot-internal
    ~/.claude/knowledge -> /Volumes/Dev/Sites/COPILOT/knowledge-copilot-internal

`cc config get paths.knowledge_repo` (machine config,
`~/.claude/cc/config.json`) additionally lists a second, much smaller repo:
`/Volumes/Dev/Sites/COPILOT/claude-copilot-private/knowledge` (4 files on
disk at scan time). Both are treated as "Knowledge Copilot" content but
counted under separate canonical buckets so the (much larger) primary repo
isn't diluted by the near-empty second one.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

from jsonl_utils import iter_jsonl_records

# ---------------------------------------------------------------------------
# CLI Copilot operational definitions
# ---------------------------------------------------------------------------

# The 22 service subgroups actually registered in copilot_cli/main.py via
# app.add_typer(..., name=X) as of the version on disk at scan time, plus
# the one bare top-level command (`health`). Verified by grep, not assumed.
CLI_COPILOT_SERVICES = {
    "git", "docker", "shell", "fireflies", "discord", "fs", "services",
    "db", "crm", "brevo", "n8n", "docs", "bi", "monitoring", "coolify",
    "infisical", "insights", "project", "conv", "skill", "reddit", "uspto",
}
CLI_COPILOT_TOP_LEVEL = {"health"}

# claude-copilot's `cc` subcommand groups (tools/cc/src/cc/commands/*.py).
# Used only to positively identify `cc <x>` as the framework tool, never as
# evidence of CLI Copilot usage.
CC_FRAMEWORK_SUBCOMMANDS = {
    "memory", "skill", "config", "env", "docs", "eval", "mcp", "doctor", "usage",
    # Ecosystem/materialize verbs confirmed present by direct sample
    # inspection (not in tools/cc/README.md's command reference, which only
    # documents memory/skill/config/docs/usage/eval/env/mcp/doctor — these
    # additional verbs appear repeatedly in real `cc <verb>` Bash calls and
    # match the CLI-contract verb list Control Tower's own code expects of
    # `cc`, per prior working memory four-programs-two-names.md: "doctor,
    # resolve, freshness, repair, update, deprovision, env, eval, memory").
    "resolve", "freshness", "repair", "update", "deprovision", "derive",
    "auth", "layers", "self-update", "version",
}

# A first-pass over raw transcripts (see module CHANGELOG note below) showed
# that matching `copilot`/`cc` ANYWHERE in a Bash command string is far too
# permissive: it fires on prose in commit messages ("chore: set up Claude +
# Codex Copilot..."), on `grep -n "copilot\|..."` search patterns, on `alias
# copilot` / `type copilot` / `which copilot` introspection (real, but NOT an
# invocation), and — critically — on an entirely SEPARATE path,
# `~/.claude/copilot/...`, which is claude-copilot's own local materialize/
# mirror directory (holding cached `.claude/agents`, `.claude/commands`,
# `tools/cc`), not the CLI Copilot binary at all. Anchoring the match to the
# START of a shell pipeline segment (i.e. "this token is the command being
# run", not "this token appears somewhere in the arguments/prose") removes
# essentially all of that noise, because none of the false positives above
# ever occur in command position — "copilot" there is always someone's
# argument, not someone's command.
_SEGMENT_SPLIT_RE = re.compile(r"&&|\|\||[|;`\n]|\$\(")
_LEADING_PREFIX_RE = re.compile(
    r"^\s*(?:[A-Za-z_][\w]*=\S+\s+)*(?:sudo\s+|env\s+(?:\S+=\S+\s+)*|command\s+|time\s+)*"
)

# Lookahead excludes a following `/` (not just word-char/hyphen) so a path
# where `cc`/`copilot` is a MIDDLE segment — e.g.
# `.../claude-copilot/tools/cc/.venv/bin/python` (a venv-relative interpreter
# path, not an invocation of `cc` itself) — does not match just because the
# optional leading-path group could absorb everything before it.
CLI_COPILOT_BIN_RE = re.compile(r"^(?P<path>(?:/[\w.-]+)*/)?(?P<bin>copilot|cli_copilot)(?![\w/-])")
CC_BIN_RE = re.compile(r"^(?P<path>(?:/[\w.-]+)*/)?(?P<bin>cc)(?![\w/-])")

# `cc` invocations plausibly the C compiler: a compiler-style flag or a
# `.c`/`.o`/`.a`/`.so` source/object argument immediately following, or a
# `CC=` env-var assignment anywhere on the line (cargo/make idiom).
_CC_COMPILER_HINT_RE = re.compile(
    r"^\s*(-[a-zA-Z]|-o\b|\S*\.(c|o|a|so)\b)|CC=|cargo\s|clang\b|gcc\b"
)

_LEADING_FLAG_RE = re.compile(r"^-\S+\s*")


def _segments(cmd: str) -> list[tuple[int, str]]:
    """Split a command string into pipeline segments on shell control
    operators, returning (offset_in_original, segment_text) so the segment's
    START can be tested against the binary regexes — this is what makes the
    match "command position" rather than "appears anywhere"."""
    out = []
    last = 0
    for m in _SEGMENT_SPLIT_RE.finditer(cmd):
        out.append((last, cmd[last:m.start()]))
        last = m.end()
    out.append((last, cmd[last:]))
    return out


def _extract_verb(tail: str) -> Optional[str]:
    """First non-flag word after the binary name, skipping up to 3 leading
    `-x`/`--flag[=val]` tokens (covers `copilot --json health`, `cc
    --version`, etc.). Stops at end of segment."""
    t = tail
    for _ in range(3):
        t = t.lstrip()
        if not t or t[0] in "|&;`)":
            return None
        if t.startswith("-"):
            t = _LEADING_FLAG_RE.sub("", t, count=1)
            continue
        m = re.match(r"[A-Za-z][\w-]*", t)
        return m.group(0) if m else None
    return None


@dataclass
class BashClassification:
    engine: str          # cli_copilot_unambiguous | cli_copilot_bare | cc_framework | cc_compiler | cc_ambiguous | gh_copilot
    verb: Optional[str]
    raw_match: str


def classify_bash_command(cmd: str) -> list[BashClassification]:
    """Return one BashClassification per copilot/cc token found in COMMAND
    POSITION in `cmd` (start of the string or start of a pipeline segment
    after &&/||/|/;/backtick/$(/(/newline) — never for a token that merely
    appears inside an argument, path, grep pattern, or prose. A single
    command string can contain more than one segment (chained with `&&`
    etc.), so this returns a list, possibly empty."""
    if not cmd:
        return []
    out: list[BashClassification] = []

    for offset, seg in _segments(cmd):
        stripped = _LEADING_PREFIX_RE.match(seg)
        prefix_len = stripped.end() if stripped else 0
        body = seg[prefix_len:]
        prefix_text = seg[:prefix_len]

        m = CLI_COPILOT_BIN_RE.match(body)
        if m:
            if prefix_text.rstrip().endswith("gh") or seg.lstrip().startswith("gh "):
                out.append(BashClassification("gh_copilot", None, m.group(0)))
                continue
            has_path = bool(m.group("path"))
            is_cli_copilot_name = m.group("bin") == "cli_copilot"
            engine = "cli_copilot_unambiguous" if (has_path or is_cli_copilot_name) else "cli_copilot_bare"
            verb = _extract_verb(body[m.end():])
            out.append(BashClassification(engine, verb, seg.strip()[:160]))
            continue

        m = CC_BIN_RE.match(body)
        if m:
            tail = body[m.end():]
            verb = _extract_verb(tail)
            tail_stripped = tail.lstrip()
            if verb in CC_FRAMEWORK_SUBCOMMANDS or (
                verb is None and ("--version" in tail_stripped[:20] or "--help" in tail_stripped[:20])
            ):
                out.append(BashClassification("cc_framework", verb, seg.strip()[:160]))
            elif _CC_COMPILER_HINT_RE.search(tail_stripped) or "CC=" in prefix_text:
                out.append(BashClassification("cc_compiler", verb, seg.strip()[:160]))
            else:
                out.append(BashClassification("cc_ambiguous", verb, seg.strip()[:160]))

    return out


# ---------------------------------------------------------------------------
# Knowledge Copilot path classification
# ---------------------------------------------------------------------------

KNOWLEDGE_PRIMARY_MARKERS = re.compile(
    r"/shared-docs(?:/|$)|/knowledge-copilot(?:-internal)?(?:/|$)|/\.claude/knowledge(?:/|$)"
)
KNOWLEDGE_SECONDARY_MARKERS = re.compile(r"claude-copilot-private/knowledge(?:/|$)")


def classify_knowledge_path(path: str) -> Optional[str]:
    """Return 'primary' (knowledge-copilot-internal / shared-docs /
    ~/.claude/knowledge — these are the SAME directory via symlinks,
    verified by readlink; the bare `knowledge-copilot` name also matches,
    since it is checked without the `-internal` suffix too),
    'secondary' (claude-copilot-private/knowledge, a distinct much smaller
    repo also registered in paths.knowledge_repo), or None."""
    if not path:
        return None
    if KNOWLEDGE_SECONDARY_MARKERS.search(path):
        return "secondary"
    if KNOWLEDGE_PRIMARY_MARKERS.search(path):
        return "primary"
    return None


def normalize_knowledge_relpath(path: str) -> Optional[str]:
    """Strip whichever alias prefix was used and return the path relative to
    the knowledge-copilot-internal repo root, for cross-referencing against
    the real on-disk file inventory. Returns None if not a knowledge path."""
    for marker in ("/shared-docs/", "/knowledge-copilot-internal/", "/knowledge-copilot/", "/.claude/knowledge/"):
        idx = path.find(marker)
        if idx != -1:
            return path[idx + len(marker):]
    return None


# ---------------------------------------------------------------------------
# Corpus walking (main + subagent files; every *.jsonl under projects_dir)
# ---------------------------------------------------------------------------

def find_all_session_files(projects_dir: Path) -> list[Path]:
    return sorted(projects_dir.glob("**/*.jsonl"))


def session_id_for(path: Path, projects_dir: Path) -> str:
    """Main file: <project>/<sessionId>.jsonl -> sessionId = stem.
    Subagent file: <project>/<sessionId>/subagents/agent-*.jsonl ->
    sessionId = parent-of-parent dir name."""
    rel = path.relative_to(projects_dir)
    parts = rel.parts
    if len(parts) == 2:
        return path.stem
    if len(parts) >= 4 and parts[-2] == "subagents":
        return parts[-3]
    # Unrecognized layout (e.g. memory/ or tool-results/ siblings) — bucket
    # under the file's own stem so it's still counted, just not merged.
    return path.stem


def is_subagent_file(path: Path, projects_dir: Path) -> bool:
    rel = path.relative_to(projects_dir)
    return len(rel.parts) >= 4 and rel.parts[-2] == "subagents"


# ---------------------------------------------------------------------------
# Main scan
# ---------------------------------------------------------------------------

@dataclass
class SessionUsage:
    session_id: str
    project_slug: str
    cwd: Optional[str] = None
    start_ts: Optional[str] = None

    cli_copilot_calls: int = 0          # unambiguous + bare, combined
    cli_copilot_unambiguous_calls: int = 0
    cli_copilot_bare_calls: int = 0
    cli_copilot_verbs: Counter = field(default_factory=Counter)
    cli_copilot_errors: int = 0             # is_error=True, either bucket
    cli_copilot_unambiguous_errors: int = 0  # is_error=True, path/cli_copilot-named calls only
    cli_copilot_bare_errors: int = 0         # is_error=True, bare `copilot` calls only

    cc_framework_calls: int = 0
    cc_framework_verbs: Counter = field(default_factory=Counter)
    cc_compiler_calls: int = 0
    cc_ambiguous_calls: int = 0
    gh_copilot_calls: int = 0

    knowledge_primary_reads: int = 0
    knowledge_secondary_reads: int = 0
    knowledge_primary_files: set = field(default_factory=set)

    tool_name_counts: Counter = field(default_factory=Counter)


_KNOWLEDGE_MARKER_RE = re.compile(
    r"knowledge-copilot|shared[-_]docs|knowledge_repo|knowledge-manifest", re.IGNORECASE
)


def scan_corpus(projects_dir: Path, verbose: bool = False):
    files = find_all_session_files(projects_dir)
    sessions: dict[str, SessionUsage] = {}

    ambiguous_cc_samples: list[str] = []
    bare_copilot_samples: list[str] = []
    knowledge_injection_hits: list[dict] = []  # SessionStart / hook_additional_context scan
    skill_listing_seen_sessions: set[str] = set()
    skill_tool_invocations: Counter = Counter()  # Skill tool_use name -> count
    agent_delegations_all: Counter = Counter()

    n_files = 0
    for f in files:
        n_files += 1
        if verbose and n_files % 50 == 0:
            print(f"  ...{n_files}/{len(files)} files", file=sys.stderr)

        sid = session_id_for(f, projects_dir)
        rel_parts = f.relative_to(projects_dir).parts
        project_slug = rel_parts[0]
        su = sessions.setdefault(sid, SessionUsage(session_id=sid, project_slug=project_slug))

        # Track tool_use id -> classification list, to correlate the *next*
        # user record's tool_result (is_error) back to a classified Bash
        # call without a second file pass.
        pending_classification: dict[str, list[BashClassification]] = {}

        for rec in iter_jsonl_records(f):
            if su.cwd is None and rec.get("cwd"):
                su.cwd = rec["cwd"]
            if su.start_ts is None and rec.get("timestamp"):
                su.start_ts = rec["timestamp"]

            rtype = rec.get("type")

            if rtype == "assistant":
                msg = rec.get("message") or {}
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for b in content:
                    if not isinstance(b, dict) or b.get("type") != "tool_use":
                        continue
                    name = b.get("name")
                    su.tool_name_counts[name] += 1
                    tool_input = b.get("input") or {}

                    if name == "Bash":
                        cmd = tool_input.get("command") or ""
                        classifications = classify_bash_command(cmd)
                        if classifications:
                            tid = b.get("id")
                            if tid:
                                pending_classification[tid] = classifications
                            for c in classifications:
                                if c.engine == "cli_copilot_unambiguous":
                                    su.cli_copilot_calls += 1
                                    su.cli_copilot_unambiguous_calls += 1
                                    su.cli_copilot_verbs[c.verb or "(none)"] += 1
                                elif c.engine == "cli_copilot_bare":
                                    su.cli_copilot_calls += 1
                                    su.cli_copilot_bare_calls += 1
                                    su.cli_copilot_verbs[c.verb or "(none)"] += 1
                                    if len(bare_copilot_samples) < 200:
                                        bare_copilot_samples.append(c.raw_match)
                                elif c.engine == "cc_framework":
                                    su.cc_framework_calls += 1
                                    su.cc_framework_verbs[c.verb or "(none)"] += 1
                                elif c.engine == "cc_compiler":
                                    su.cc_compiler_calls += 1
                                elif c.engine == "cc_ambiguous":
                                    su.cc_ambiguous_calls += 1
                                    if len(ambiguous_cc_samples) < 200:
                                        ambiguous_cc_samples.append(c.raw_match)
                                elif c.engine == "gh_copilot":
                                    su.gh_copilot_calls += 1

                    elif name == "Read":
                        fp = tool_input.get("file_path") or ""
                        kind = classify_knowledge_path(fp)
                        if kind == "primary":
                            su.knowledge_primary_reads += 1
                            rel = normalize_knowledge_relpath(fp)
                            if rel:
                                su.knowledge_primary_files.add(rel)
                        elif kind == "secondary":
                            su.knowledge_secondary_reads += 1

                    elif name in ("Grep", "Glob"):
                        p = tool_input.get("path") or tool_input.get("pattern") or ""
                        kind = classify_knowledge_path(p)
                        if kind == "primary":
                            su.knowledge_primary_reads += 1
                        elif kind == "secondary":
                            su.knowledge_secondary_reads += 1

                    elif name == "Skill":
                        skill_name = tool_input.get("name") or tool_input.get("skill") or json.dumps(tool_input)[:60]
                        skill_tool_invocations[str(skill_name)] += 1

                    elif name in ("Agent", "Task"):
                        atype = tool_input.get("subagent_type")
                        if atype:
                            agent_delegations_all[atype] += 1

            elif rtype == "user":
                msg = rec.get("message") or {}
                content = msg.get("content")
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            tid = b.get("tool_use_id")
                            if tid and tid in pending_classification:
                                is_err = bool(b.get("is_error"))
                                if is_err:
                                    for c in pending_classification[tid]:
                                        if c.engine == "cli_copilot_unambiguous":
                                            su.cli_copilot_errors += 1
                                            su.cli_copilot_unambiguous_errors += 1
                                        elif c.engine == "cli_copilot_bare":
                                            su.cli_copilot_errors += 1
                                            su.cli_copilot_bare_errors += 1
                                del pending_classification[tid]

            elif rtype == "attachment":
                att = rec.get("attachment") or {}
                atype = att.get("type")
                if atype == "skill_listing":
                    skill_listing_seen_sessions.add(sid)
                    txt = att.get("content") or ""
                    if "knowledge-copilot" in txt or "knowledge_copilot" in txt:
                        knowledge_injection_hits.append({
                            "session_id": sid, "kind": "skill_listing_mentions_kc",
                        })
                elif atype == "hook_additional_context":
                    for block in att.get("content") or []:
                        if not isinstance(block, str):
                            continue
                        km = _KNOWLEDGE_MARKER_RE.search(block)
                        if km:
                            knowledge_injection_hits.append({
                                "session_id": sid,
                                "kind": "hook_additional_context",
                                "hookName": att.get("hookName"),
                                "excerpt": block[max(0, km.start() - 60):km.start() + 180],
                            })
                elif atype == "hook_success" and (att.get("hookName") or "").startswith("SessionStart"):
                    stdout = att.get("stdout") or ""
                    km = _KNOWLEDGE_MARKER_RE.search(stdout)
                    if km:
                        knowledge_injection_hits.append({
                            "session_id": sid, "kind": "session_start_stdout",
                            "excerpt": stdout[max(0, km.start() - 60):km.start() + 180],
                        })

    return {
        "sessions": sessions,
        "ambiguous_cc_samples": ambiguous_cc_samples,
        "bare_copilot_samples": bare_copilot_samples,
        "knowledge_injection_hits": knowledge_injection_hits,
        "skill_listing_seen_sessions": skill_listing_seen_sessions,
        "skill_tool_invocations": skill_tool_invocations,
        "agent_delegations_all": agent_delegations_all,
        "n_files": n_files,
    }


# ---------------------------------------------------------------------------
# Knowledge repo file inventory (for the never-read comparison)
# ---------------------------------------------------------------------------

def inventory_knowledge_repo(repo_root: Path, exclude_dirs=(".git", ".obsidian", "node_modules")) -> set[str]:
    out = set()
    for p in repo_root.rglob("*"):
        if not p.is_file():
            continue
        if any(part in exclude_dirs for part in p.relative_to(repo_root).parts):
            continue
        out.add(str(p.relative_to(repo_root)))
    return out


def _parse_ts(ts: str) -> datetime:
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def print_report(result: dict, knowledge_repo: Path) -> None:
    sessions = result["sessions"]
    n = len(sessions)

    def header(t):
        print("\n" + "=" * 78)
        print(t)
        print("=" * 78)

    header("0. CORPUS")
    ts = [s.start_ts for s in sessions.values() if s.start_ts]
    if ts:
        ts_sorted = sorted(ts)
        print(f"Sessions: {n}  (main + subagent files scanned: {result['n_files']})")
        print(f"Date range: {_parse_ts(ts_sorted[0]).date()} .. {_parse_ts(ts_sorted[-1]).date()}")

    header("1. CLI COPILOT")
    n_any = sum(1 for s in sessions.values() if s.cli_copilot_calls > 0)
    n_unambig = sum(1 for s in sessions.values() if s.cli_copilot_unambiguous_calls > 0)
    n_bare_only = sum(1 for s in sessions.values() if s.cli_copilot_bare_calls > 0 and s.cli_copilot_unambiguous_calls == 0)
    print(f"Sessions with >=1 CLI Copilot call (any bucket):      {n_any}/{n} ({n_any/n*100:.1f}%)")
    print(f"  - via absolute path or `cli_copilot` (unambiguous): {n_unambig}/{n}")
    print(f"  - bare `copilot` ONLY (alias-shadowed, ambiguous):  {n_bare_only}/{n}")

    total_unambig = sum(s.cli_copilot_unambiguous_calls for s in sessions.values())
    total_bare = sum(s.cli_copilot_bare_calls for s in sessions.values())
    err_unambig = sum(s.cli_copilot_unambiguous_errors for s in sessions.values())
    err_bare = sum(s.cli_copilot_bare_errors for s in sessions.values())
    print(f"\nCall-level counts: unambiguous={total_unambig} (errors={err_unambig}, "
          f"{err_unambig/total_unambig*100 if total_unambig else 0:.1f}%)  "
          f"bare={total_bare} (errors={err_bare}, {err_bare/total_bare*100 if total_bare else 0:.1f}%)")

    verb_counter = Counter()
    for s in sessions.values():
        verb_counter.update(s.cli_copilot_verbs)
    print("\nVerbs used (ranked, all sessions):")
    for verb, cnt in verb_counter.most_common(30):
        registered = "" if (verb in CLI_COPILOT_SERVICES or verb in CLI_COPILOT_TOP_LEVEL or verb == "(none)") else "  [not a registered service — likely --flag/typo/probe]"
        print(f"  {verb:20s} {cnt:4d}{registered}")
    n_registered_verbs_used = len({v for v in verb_counter if v in CLI_COPILOT_SERVICES})
    print(f"\n{n_registered_verbs_used}/{len(CLI_COPILOT_SERVICES)} registered CLI Copilot service groups were ever invoked.")

    header("2. cc (claude-copilot framework tool) — NOT CLI Copilot, reported for disambiguation")
    n_cc = sum(1 for s in sessions.values() if s.cc_framework_calls > 0)
    print(f"Sessions with >=1 `cc` framework call: {n_cc}/{n} ({n_cc/n*100:.1f}%)")
    cc_verb_counter = Counter()
    for s in sessions.values():
        cc_verb_counter.update(s.cc_framework_verbs)
    print("Verbs used (ranked):")
    for verb, cnt in cc_verb_counter.most_common(20):
        print(f"  {verb:15s} {cnt}")
    print(f"\ncc_ambiguous calls (mostly heredoc/PR-body prose containing the string 'cc' at a "
          f"line start — a known false-positive source of this regex-based approach, NOT counted "
          f"as usage above): {sum(s.cc_ambiguous_calls for s in sessions.values())}")

    header("3. KNOWLEDGE COPILOT")
    n_kn = sum(1 for s in sessions.values() if (s.knowledge_primary_reads + s.knowledge_secondary_reads) > 0)
    print(f"Sessions with >=1 Read/Grep/Glob into a knowledge repo: {n_kn}/{n} ({n_kn/n*100:.1f}%)")

    own_repo_slugs = {
        "-Volumes-Dev-Sites-COPILOT-shared-docs",
        "-Volumes-Dev-Sites-COPILOT-knowledge-copilot-internal",
        "-Volumes-Dev-Sites-COPILOT-knowledge-copilot",  # pre-rename slug, kept for historical transcripts
    }
    kn_sessions = [s for s in sessions.values() if (s.knowledge_primary_reads + s.knowledge_secondary_reads) > 0]
    n_own = sum(1 for s in kn_sessions if s.project_slug in own_repo_slugs)
    n_cross = len(kn_sessions) - n_own
    print(f"  - sessions IN the knowledge repo itself (building/maintaining it): {n_own}")
    print(f"  - sessions in ANOTHER project reaching into it (consuming it):     {n_cross}")

    proj_counter = Counter(s.project_slug for s in kn_sessions)
    print("\nBy project:")
    for p, c in proj_counter.most_common(15):
        print(f"  {c:3d}  {p}")

    if knowledge_repo.is_dir():
        inv = inventory_knowledge_repo(knowledge_repo)
        read_files: set = set()
        for s in sessions.values():
            read_files |= s.knowledge_primary_files
        never = inv - read_files
        print(f"\nFile inventory (excl. .git/.obsidian/node_modules): {len(inv)} files")
        print(f"Distinct files ever Read in this corpus:              {len(read_files)} ({len(read_files)/len(inv)*100:.1f}%)")
        print(f"Never read even once:                                 {len(never)} ({len(never)/len(inv)*100:.1f}%)")

        file_counter = Counter()
        for s in sessions.values():
            file_counter.update(s.knowledge_primary_files)
        print("\nTop files by #sessions reading them:")
        for f, c in file_counter.most_common(15):
            print(f"  {c:2d}  {f}")

    print(f"\n`/knowledge-copilot` / Skill(name=knowledge-copilot) invocations: "
          f"{result['skill_tool_invocations'].get('knowledge-copilot', 0)}")
    print(f"Sessions where the skill LISTING (available-skills boilerplate injected at\n"
          f"session start) merely NAMES 'knowledge-copilot' as available (not proof of use): "
          f"{len(result['skill_listing_seen_sessions'])}/{n}")

    header("4. SILENT INJECTION CHECK (hook_additional_context / SessionStart stdout)")
    hits = result["knowledge_injection_hits"]
    genuine = [h for h in hits if h["kind"] != "skill_listing_mentions_kc"]
    print(f"Total attachment-record hits mentioning a knowledge marker: {len(hits)}")
    print(f"  - skill_listing boilerplate only (names the skill, not its content): "
          f"{len(hits) - len(genuine)}")
    print(f"  - hook_additional_context / SessionStart stdout genuinely containing a "
          f"knowledge marker: {len(genuine)}")
    for h in genuine[:8]:
        print(f"    [{h['kind']}] session={h['session_id'][:8]} excerpt={h.get('excerpt','')!r}")
    if not genuine:
        print("  -> NO evidence found of knowledge CONTENT being silently injected via hooks.")
        print("     (Every observed knowledge touch in this corpus was a visible Read/Grep/Glob")
        print("     tool call, not an invisible context injection.)")

    header("5. BASELINE — tool usage across the whole corpus (denominator context)")
    tool_sessions = Counter()
    tool_calls = Counter()
    for s in sessions.values():
        for name, cnt in s.tool_name_counts.items():
            tool_sessions[name] += 1
            tool_calls[name] += cnt
    print(f"{'tool':30s} {'sessions':>10s} {'calls':>10s}")
    for name, sc in tool_sessions.most_common(20):
        print(f"{name:30s} {sc:>10d} {tool_calls[name]:>10d}")
    mcp_sessions = sum(1 for s in sessions.values() if any(nm.startswith("mcp__") for nm in s.tool_name_counts))
    print(f"\nSessions using ANY mcp__* tool: {mcp_sessions}/{n} ({mcp_sessions/n*100:.1f}%)")
    print(f"Sessions using the Skill tool (any skill):  {tool_sessions.get('Skill', 0)}/{n}")
    print(f"Skill tool invocations by name: {dict(result['skill_tool_invocations'])}")

    header("6. WEEKLY TREND")
    buckets: dict = defaultdict(lambda: {"total": 0, "cli": 0, "cc": 0, "kn": 0})
    for s in sessions.values():
        if not s.start_ts:
            continue
        key = _parse_ts(s.start_ts).date().isocalendar()[:2]
        b = buckets[key]
        b["total"] += 1
        if s.cli_copilot_unambiguous_calls > 0:
            b["cli"] += 1
        if s.cc_framework_calls > 0:
            b["cc"] += 1
        if (s.knowledge_primary_reads + s.knowledge_secondary_reads) > 0:
            b["kn"] += 1
    print(f"{'week':10s} {'n':>4s} {'cli_copilot':>12s} {'cc_fw':>7s} {'knowledge':>10s}")
    for key in sorted(buckets):
        b = buckets[key]
        print(f"{key[0]}-W{key[1]:02d}   {b['total']:>4d} {b['cli']:>12d} {b['cc']:>7d} {b['kn']:>10d}")


def write_csv_outputs(result: dict, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    sessions = result["sessions"]

    with (out_dir / "product_usage_sessions.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow([
            "session_id", "project_slug", "cwd", "start_ts",
            "cli_copilot_unambiguous_calls", "cli_copilot_bare_calls", "cli_copilot_errors",
            "cc_framework_calls", "cc_ambiguous_calls",
            "knowledge_primary_reads", "knowledge_secondary_reads", "knowledge_distinct_files",
        ])
        for s in sorted(sessions.values(), key=lambda s: s.start_ts or ""):
            w.writerow([
                s.session_id, s.project_slug, s.cwd, s.start_ts,
                s.cli_copilot_unambiguous_calls, s.cli_copilot_bare_calls, s.cli_copilot_errors,
                s.cc_framework_calls, s.cc_ambiguous_calls,
                s.knowledge_primary_reads, s.knowledge_secondary_reads, len(s.knowledge_primary_files),
            ])

    verb_counter = Counter()
    for s in sessions.values():
        verb_counter.update(s.cli_copilot_verbs)
    with (out_dir / "product_usage_cli_copilot_verbs.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["verb", "call_count", "is_registered_service"])
        for verb, cnt in verb_counter.most_common():
            w.writerow([verb, cnt, verb in CLI_COPILOT_SERVICES or verb in CLI_COPILOT_TOP_LEVEL])

    file_counter = Counter()
    for s in sessions.values():
        file_counter.update(s.knowledge_primary_files)
    with (out_dir / "product_usage_knowledge_files.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["relpath", "n_sessions_reading_it"])
        for f, c in file_counter.most_common():
            w.writerow([f, c])


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--projects-dir", default=str(Path.home() / ".claude" / "projects"))
    ap.add_argument("--knowledge-repo", default="/Volumes/Dev/Sites/COPILOT/knowledge-copilot-internal")
    ap.add_argument("--out", default=str(Path(__file__).parent / "output"))
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    result = scan_corpus(Path(args.projects_dir), verbose=args.verbose)
    print(f"Scanned {result['n_files']} jsonl files -> {len(result['sessions'])} distinct sessions", file=sys.stderr)

    print_report(result, Path(args.knowledge_repo))
    write_csv_outputs(result, Path(args.out))
    print(f"\nArtifacts written to {args.out}", file=sys.stderr)
