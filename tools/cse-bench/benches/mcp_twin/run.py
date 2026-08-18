#!/usr/bin/env python3
"""benches/mcp_twin/run.py — B-11 MCP-twin bench (TASK-94).

An honest, bounded measurement of CLI Copilot's core claimed advantage
("one CLI instead of a bespoke MCP server per service") against the only
two real MCP servers that exist on this machine and have direct CLI
twins, per phase-1-findings.md finding F-17:

    | MCP server     | CLI twin      |
    | -------------- | ------------- |
    | nocodb-mcp     | copilot crm   |
    | postgresql-mcp | copilot db    |

F-17's honest quantity is NOT "MCP schema tokens saved" — Claude Code
reportedly auto-defers (does not load upfront) MCP tool schemas above
~10% of the context window, so the CLI's advantage is a *bounded
constant*, not a number that scales with more MCP servers. And that
constant is offset by a previously uncounted cost: the tokens a model
needs to spend learning the CLI's own verb grammar (CLAUDE.md-style
prose, and/or `--help` probing). This bench measures both sides:

    net_advantage_tokens = min(mcp_schema_tokens, 10% * context_window)
                            - cli_grammar_cost

This is a standalone bench script (TASK-94 / B-11), deliberately NOT
wired into cse_bench.py's collector registry (that machinery is owned by
other tasks) — run it directly:

    python3 tools/cse-bench/benches/mcp_twin/run.py

Design notes
------------
- **MCP schema tokens are measured live, not guessed**, when it is
  trivially safe to do so: this script spawns each MCP server's own
  `src/index.js` (the exact entry point its own `.mcp.json` config
  points at, found by scanning `.mcp.json` files on this machine) with
  throwaway, non-functional credentials (a syntactically-valid but
  unreachable local URL/short string) and performs a real MCP
  `initialize` + `tools/list` JSON-RPC handshake over stdio. Both
  servers' client constructors are lazy (connection pools / HTTP clients
  are configured but never used until a tool is actually called), so
  listing tools never touches the network — verified by reading
  `nocodb-client.js` / `database-client.js` before relying on it. The
  process is killed immediately after the handshake; no tool is ever
  invoked. If this handshake fails for any reason (missing `node_modules`,
  protocol change, timeout), this falls back to a partial reconstruction
  from the server's own source (`ListToolsRequestSchema` handler, tool
  `name`/`description` pairs only — NOT a full inputSchema reconstruction,
  so it undercounts), and if that also fails, falls back to Phase 1's
  hand-estimated figures with provenance `"phase-1-estimate"`. Every
  number in the output carries its own `provenance` field — never
  presented as more certain than it was obtained.
- **No secrets are ever read into or emitted by this script.** The
  `.mcp.json` scan reports server names, command/args (file paths, not
  secrets), and env VAR NAMES only — never env values. The live-handshake
  credentials are throwaway strings this script invents itself; the
  real credentials in each server's `.mcp.json` are never opened for
  this purpose (this script does not need them, since it never queries
  the underlying service).
- **CLI grammar cost (upper bound)** is measured by recursively walking
  `copilot crm --help` / `copilot db --help` and every subcommand's
  `--help` (Typer/Click renders a `Usage: ... COMMAND [ARGS]...` line for
  a command group and a plain `Usage: ... [OPTIONS]` line for a leaf —
  that distinction drives the recursion; subcommand names are parsed out
  of the Rich-rendered "Commands" box). This is the "probe everything"
  upper bound named in the task, not a claim about what a model actually
  reads.
- **CLI grammar cost (prose)** token-counts whatever CLAUDE.md-style
  service-reference doc cli-copilot ships for that command group
  (`docs/services/07-nocodb.md`, `docs/services/06-postgresql.md`, found
  by grepping cli-copilot's docs tree for the command name). Both exist
  on this machine today — this is itself a finding worth stating plainly,
  since F-17 raised the possibility that no such prose exists anywhere.
- **Token counting** prefers `tiktoken` (`o200k_base`) when importable,
  falling back to a `chars/4` heuristic; every count in the output states
  which method produced it. `tiktoken` is OpenAI's tokenizer, not
  Anthropic's — used here only as a widely-available proxy; this caveat
  is stated once in `metrics.token_counting` rather than repeated per
  field.
- **CLI-side latency only.** Three timed, read-only, `--json` invocations
  per twin (`copilot --json crm health`, `copilot --json db health`) —
  the same real network/auth health-check pattern
  `collectors/integrations.py` already uses for `copilot health`, chosen
  per the task's own allowance ("`copilot health`'s crm/db checks count
  if direct ops need creds"). MCP-side latency is explicitly marked
  `"status": "pending"` with no invented number — the task is explicit
  that faking this is worse than omitting it.
"""
from __future__ import annotations

import json
import re
import select
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

SCHEMA_VERSION = "cse-bench/1"
COLLECTOR_NAME = "bench_mcp_twin"
HOST_SCOPE = "single-machine-single-user"

SCRIPT_DIR = Path(__file__).resolve().parent
OUT_DIR = SCRIPT_DIR.parent.parent / "output"  # tools/cse-bench/output/

COPILOT_BIN = "/opt/homebrew/bin/copilot"
# Two roots: cli-copilot is one of the 20 framework/product repos that
# moved to CSE; other .mcp.json-bearing project repos scanned below did
# not move and still live under COPILOT. See collectors/paths.py's "TWO
# ROOTS" note for the fuller rationale (this script is a standalone
# bench, not a collectors/ module, so it keeps its own copy rather than
# importing across the benches/ <-> collectors/ boundary).
# Each root keeps the same two-spelling candidate list as
# collectors/paths.py: primary machine (/Volumes/Dev, where
# /Users/pabs/Sites symlinks to it) first, then secondary machines where
# /Volumes/Dev is never mounted. Resolved separately per root and never
# falling back from one to the other -- the two roots hold disjoint repo
# sets, so a silent cross-root fallback would resolve a lookup against an
# unrelated top level instead of failing loudly.
_COPILOT_ROOT_CANDIDATES = [
    Path("/Volumes/Dev/Sites/COPILOT"),
    Path("/Users/pabs/Sites/COPILOT"),
]
_CSE_ROOT_CANDIDATES = [
    Path("/Volumes/Dev/Sites/CSE"),
    Path("/Users/pabs/Sites/CSE"),
]


def _resolve_root(candidates: list[Path]) -> Path:
    """First candidate that exists as a directory, else the first
    (historical) candidate unchanged."""
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    return candidates[0]


COPILOT_ROOT = _resolve_root(_COPILOT_ROOT_CANDIDATES)
CSE_ROOT = _resolve_root(_CSE_ROOT_CANDIDATES)
CLI_COPILOT_DOCS = CSE_ROOT / "cli-copilot" / "docs" / "services"

CONTEXT_WINDOW_TOKENS_ASSUMED = 200_000
MCP_DEFER_THRESHOLD_FRACTION = 0.10  # changelog-sourced, unverified -- see f17_caveats
MCP_DEFER_THRESHOLD_TOKENS = int(CONTEXT_WINDOW_TOKENS_ASSUMED * MCP_DEFER_THRESHOLD_FRACTION)

_HELP_TIMEOUT_SECONDS = 15
_LATENCY_TIMEOUT_SECONDS = 30
_MCP_HANDSHAKE_TIMEOUT_SECONDS = 12
_MAX_HELP_DEPTH = 6

# Phase 1's hand-estimated figures (phase-1-findings.md F-17), used ONLY as a
# last-resort fallback if neither the live handshake nor source
# reconstruction succeeds.
PHASE1_ESTIMATES = {
    "nocodb-mcp": {"tool_count": 19, "schema_tokens": 3322},
    "postgresql-mcp": {"tool_count": 13, "schema_tokens": 2726},
}

# The two known real MCP servers with CLI twins (F-17). Their .mcp.json
# location is discovered on this machine (see discover_mcp_configs), not
# hardcoded here -- these names are just what we're looking for.
TWIN_SPECS = [
    {
        "twin_id": "crm",
        "cli_group_args": ["crm"],
        "mcp_server_name": "nocodb-mcp",
        "prose_doc": CLI_COPILOT_DOCS / "07-nocodb.md",
        "dummy_env": {
            "NOCODB_API_KEY": "bench-dummy-key-not-real-0000",
            "NOCODB_URL": "http://127.0.0.1:1",
            "LOG_LEVEL": "error",
        },
        "latency_args": ["--json", "crm", "health"],
    },
    {
        "twin_id": "db",
        "cli_group_args": ["db"],
        "mcp_server_name": "postgresql-mcp",
        "prose_doc": CLI_COPILOT_DOCS / "06-postgresql.md",
        "dummy_env": {
            "DATABASE_URL": "postgresql://bench:dummy@127.0.0.1:1/bench_dummy_not_real",
            "LOG_LEVEL": "error",
        },
        "latency_args": ["--json", "db", "health"],
    },
]


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


# ---------------------------------------------------------------------------
# Token counting
# ---------------------------------------------------------------------------

_TIKTOKEN_ENCODING = None
_TIKTOKEN_UNAVAILABLE_REASON: Optional[str] = None


def _get_tiktoken_encoding():
    global _TIKTOKEN_ENCODING, _TIKTOKEN_UNAVAILABLE_REASON
    if _TIKTOKEN_ENCODING is not None or _TIKTOKEN_UNAVAILABLE_REASON is not None:
        return _TIKTOKEN_ENCODING
    try:
        import tiktoken  # type: ignore

        _TIKTOKEN_ENCODING = tiktoken.get_encoding("o200k_base")
    except Exception as exc:  # ImportError or a tiktoken-internal failure
        _TIKTOKEN_UNAVAILABLE_REASON = f"{type(exc).__name__}: {exc}"
    return _TIKTOKEN_ENCODING


def count_tokens(text: str) -> dict:
    """Returns {"count": int, "method": str}. Prefers tiktoken (o200k_base)
    when importable; falls back to a chars/4 heuristic otherwise. Every
    caller keeps the method tag alongside the number rather than assuming
    one globally, in case tiktoken becomes available/unavailable between
    twins (it won't, but the contract is per-value, not per-run).
    """
    encoding = _get_tiktoken_encoding()
    if encoding is not None:
        return {"count": len(encoding.encode(text)), "method": "tiktoken:o200k_base"}
    return {"count": max(1, round(len(text) / 4)), "method": "heuristic:chars/4"}


# ---------------------------------------------------------------------------
# Step 1 -- find the MCP server configs on this machine
# ---------------------------------------------------------------------------

def _redact_mcp_server(name: str, cfg: dict) -> dict:
    """name/command/args (paths) survive; env values never do -- only the
    env VAR NAMES a server depends on (useful provenance, not a secret)."""
    env = cfg.get("env", {}) if isinstance(cfg, dict) else {}
    return {
        "name": name,
        "command": cfg.get("command") if isinstance(cfg, dict) else None,
        "args": cfg.get("args") if isinstance(cfg, dict) else None,
        "env_var_names": sorted(env.keys()) if isinstance(env, dict) else [],
        "type": cfg.get("type") if isinstance(cfg, dict) else None,  # e.g. remote "url" servers
    }


def discover_mcp_configs(errors: list[dict]) -> dict:
    """Scans .mcp.json across /Volumes/Dev/Sites/CSE/*/ and
    /Volumes/Dev/Sites/COPILOT/*/ (one level each, per the task's own
    search scope, covering both the moved and unmoved repo trees) plus
    ~/.claude.json's mcpServers block (top-level and per-project),
    redacting all env values. Returns the full inventory (for
    provenance/transparency) plus, separately, the resolved location of
    the two twin servers this bench cares about.
    """
    found_by_server: dict[str, list[dict]] = {}
    all_servers: list[dict] = []

    scanned_mcp_jsons = sorted(set(CSE_ROOT.glob("*/.mcp.json")) | set(COPILOT_ROOT.glob("*/.mcp.json")))
    for mcp_json in scanned_mcp_jsons:
        try:
            data = json.loads(mcp_json.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            errors.append({"item": "mcp_json_scan", "path": str(mcp_json), "error": f"{type(exc).__name__}: {exc}"})
            continue
        servers = data.get("mcpServers", {})
        if not isinstance(servers, dict):
            continue
        for name, cfg in servers.items():
            entry = _redact_mcp_server(name, cfg)
            entry["source_file"] = str(mcp_json)
            all_servers.append(entry)
            found_by_server.setdefault(name, []).append(entry)

    claude_json_path = Path.home() / ".claude.json"
    claude_json_summary: Optional[dict] = None
    try:
        data = json.loads(claude_json_path.read_text())
        top_level = data.get("mcpServers", {})
        top_level_entries = [_redact_mcp_server(n, c) for n, c in top_level.items()] if isinstance(top_level, dict) else []
        for e in top_level_entries:
            e["source_file"] = f"{claude_json_path} (top-level mcpServers)"
        projects = data.get("projects", {})
        per_project_nonempty = 0
        per_project_total = 0
        if isinstance(projects, dict):
            per_project_total = len(projects)
            for proj_cfg in projects.values():
                if isinstance(proj_cfg, dict) and proj_cfg.get("mcpServers"):
                    per_project_nonempty += 1
        claude_json_summary = {
            "readable": True,
            "top_level_servers": top_level_entries,
            "projects_scanned": per_project_total,
            "projects_with_nonempty_mcpServers": per_project_nonempty,
            "note": (
                "per-project mcpServers blocks are session-local caches, not config; "
                "an empty block here does not mean the project's .mcp.json (if any) is unused, "
                "only that no Claude Code session in this file's history recorded servers for it"
            ),
        }
        for e in top_level_entries:
            all_servers.append(e)
            found_by_server.setdefault(e["name"], []).append(e)
    except (OSError, json.JSONDecodeError) as exc:
        errors.append({"item": "claude_json_scan", "path": str(claude_json_path), "error": f"{type(exc).__name__}: {exc}"})
        claude_json_summary = {"readable": False, "error": f"{type(exc).__name__}: {exc}"}

    twin_locations: dict[str, Optional[dict]] = {}
    for spec in TWIN_SPECS:
        matches = found_by_server.get(spec["mcp_server_name"], [])
        twin_locations[spec["mcp_server_name"]] = matches[0] if matches else None
        if len(matches) > 1:
            errors.append(
                {
                    "item": "mcp_config_ambiguous",
                    "server": spec["mcp_server_name"],
                    "error": f"found in {len(matches)} .mcp.json files; using the first: {matches[0]['source_file']}",
                }
            )
        if not matches:
            errors.append({"item": "mcp_config_missing", "server": spec["mcp_server_name"], "error": "no .mcp.json defines this server on this machine"})

    return {
        "search_scope": [
            str(CSE_ROOT / "*" / ".mcp.json"),
            str(COPILOT_ROOT / "*" / ".mcp.json"),
            str(claude_json_path),
        ],
        "servers_found_total": len(all_servers),
        "servers_found": all_servers,
        "claude_json": claude_json_summary,
        "twin_locations": twin_locations,
    }


# ---------------------------------------------------------------------------
# Step 1b -- live MCP tools/list handshake (primary), with fallbacks
# ---------------------------------------------------------------------------

def _mcp_live_tools_list(entry_point: Path, env_extra: dict, errors: list[dict]) -> Optional[dict]:
    """Spawns `node <entry_point>`, performs a real MCP initialize +
    tools/list JSON-RPC handshake over stdio with throwaway env vars, and
    returns the raw {"tools": [...]} result verbatim -- or None on any
    failure (caller falls back). Never invokes a tool; kills the process
    immediately after tools/list responds. Skips non-JSON stdout lines
    (some servers print startup banners via console.log instead of
    console.error, polluting the JSON-RPC stream -- observed live on
    nocodb-mcp; recorded as a note in the caller, not treated as fatal).
    """
    import os

    if not entry_point.is_file():
        errors.append({"item": "mcp_live_handshake", "path": str(entry_point), "error": "entry point not found"})
        return None

    env = dict(os.environ)
    env.update(env_extra)
    env["NODE_ENV"] = "test"

    try:
        proc = subprocess.Popen(
            ["node", str(entry_point)],
            cwd=str(entry_point.parent.parent),  # server package root, one level above src/
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
    except (FileNotFoundError, OSError) as exc:
        errors.append({"item": "mcp_live_handshake", "path": str(entry_point), "error": f"could not spawn node: {exc}"})
        return None

    skipped_stdout_lines: list[str] = []

    def send(msg: dict) -> None:
        assert proc.stdin is not None
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()

    def read_response(expected_id: int, deadline_s: float) -> Optional[dict]:
        assert proc.stdout is not None
        end = time.monotonic() + deadline_s
        while time.monotonic() < end:
            remaining = max(0.0, end - time.monotonic())
            ready, _, _ = select.select([proc.stdout], [], [], remaining)
            if not ready:
                break
            line = proc.stdout.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                skipped_stdout_lines.append(line)
                continue
            if isinstance(data, dict) and data.get("id") == expected_id:
                return data
            skipped_stdout_lines.append(line)
        return None

    result: Optional[dict] = None
    try:
        send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "cse-bench-mcp-twin", "version": "0.1"},
                },
            }
        )
        init_resp = read_response(1, _MCP_HANDSHAKE_TIMEOUT_SECONDS)
        if init_resp is None:
            errors.append({"item": "mcp_live_handshake", "path": str(entry_point), "error": "no initialize response within timeout"})
            return None

        send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        list_resp = read_response(2, _MCP_HANDSHAKE_TIMEOUT_SECONDS)
        if list_resp is None:
            errors.append({"item": "mcp_live_handshake", "path": str(entry_point), "error": "no tools/list response within timeout"})
            return None

        tools = list_resp.get("result", {}).get("tools")
        if not isinstance(tools, list) or not tools:
            errors.append({"item": "mcp_live_handshake", "path": str(entry_point), "error": "tools/list response had no tools array"})
            return None

        result = {"tools": tools, "stdout_pollution": skipped_stdout_lines}
    except Exception as exc:  # never let a probe failure crash the run
        errors.append({"item": "mcp_live_handshake", "path": str(entry_point), "error": f"{type(exc).__name__}: {exc}"})
        result = None
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except Exception:
            proc.kill()

    return result


_JS_NAME_DESC_RE = re.compile(
    r"name:\s*'([^']+)'\s*,\s*description:\s*'([^']*)'", re.MULTILINE
)


def _mcp_source_reconstruction(entry_point: Path, errors: list[dict]) -> Optional[dict]:
    """Fallback tier 2: best-effort extraction of tool name/description
    pairs from the server's own source via regex. Deliberately does NOT
    attempt to reconstruct full inputSchema (JS object literals with
    unquoted keys, single-quoted strings, and dynamic expressions like
    `enum: Object.keys(databaseConfigs)` are not safely convertible to
    JSON by regex) -- so any schema_tokens computed from this tier is a
    known UNDERCOUNT, labeled as such by the caller's provenance string.
    """
    try:
        text = entry_point.read_text()
    except OSError as exc:
        errors.append({"item": "mcp_source_reconstruction", "path": str(entry_point), "error": f"{type(exc).__name__}: {exc}"})
        return None

    pairs = _JS_NAME_DESC_RE.findall(text)
    if not pairs:
        errors.append({"item": "mcp_source_reconstruction", "path": str(entry_point), "error": "no name/description pairs matched"})
        return None

    tools = [{"name": n, "description": d} for n, d in pairs]
    return {"tools": tools, "undercount_warning": "name+description only; inputSchema not reconstructed"}


def get_mcp_schema(spec: dict, config_location: Optional[dict], errors: list[dict]) -> dict:
    server_name = spec["mcp_server_name"]

    if config_location is None:
        estimate = PHASE1_ESTIMATES[server_name]
        return {
            "provenance": "phase-1-estimate",
            "provenance_note": "no .mcp.json config found on this machine for this server; using Phase 1's hand estimate verbatim",
            "tool_count": estimate["tool_count"],
            "schema_tokens_compact": {"count": estimate["schema_tokens"], "method": "phase-1-hand-estimate"},
            "schema_tokens_pretty": None,
            "notes": [],
        }

    args = config_location.get("args") or []
    entry_point = Path(args[0]) if args else None

    live = _mcp_live_tools_list(entry_point, spec["dummy_env"], errors) if entry_point else None
    if live is not None:
        tools = live["tools"]
        notes = []
        if live.get("stdout_pollution"):
            notes.append(
                f"{server_name}'s startup path writes {len(live['stdout_pollution'])} non-JSON-RPC line(s) to "
                "stdout (console.log instead of console.error) ahead of the actual handshake responses -- "
                "this bench's reader tolerates it (skips non-JSON lines), but a naive stdio client would not."
            )
        compact = json.dumps(tools, separators=(",", ":"))
        pretty = json.dumps(tools, indent=2)
        return {
            "provenance": "live-list-tools-handshake",
            "provenance_note": (
                "real MCP initialize + tools/list JSON-RPC handshake against the server's own entry point, "
                "using throwaway/unreachable dummy credentials; no tool was ever invoked, no network was touched "
                "(both servers' DB pool / HTTP client construction is lazy)"
            ),
            "entry_point": str(entry_point),
            "tool_count": len(tools),
            "schema_tokens_compact": count_tokens(compact) | {"chars": len(compact)},
            "schema_tokens_pretty": count_tokens(pretty) | {"chars": len(pretty)},
            "notes": notes,
        }

    reconstructed = _mcp_source_reconstruction(entry_point, errors) if entry_point else None
    if reconstructed is not None:
        tools = reconstructed["tools"]
        compact = json.dumps(tools, separators=(",", ":"))
        return {
            "provenance": "source-reconstruction-partial",
            "provenance_note": (
                "live handshake failed; fell back to regex-extracted name+description pairs from source -- "
                f"{reconstructed['undercount_warning']}; treat schema_tokens as a floor, not an estimate"
            ),
            "entry_point": str(entry_point),
            "tool_count": len(tools),
            "schema_tokens_compact": count_tokens(compact) | {"chars": len(compact)},
            "schema_tokens_pretty": None,
            "notes": ["schema_tokens is an undercount: inputSchema fields were not reconstructed"],
        }

    estimate = PHASE1_ESTIMATES[server_name]
    return {
        "provenance": "phase-1-estimate",
        "provenance_note": "both live handshake and source reconstruction failed; using Phase 1's hand estimate verbatim",
        "tool_count": estimate["tool_count"],
        "schema_tokens_compact": {"count": estimate["schema_tokens"], "method": "phase-1-hand-estimate"},
        "schema_tokens_pretty": None,
        "notes": [],
    }


# ---------------------------------------------------------------------------
# Step 3a -- CLI grammar cost, upper bound (recursive --help probing)
# ---------------------------------------------------------------------------

_GROUP_USAGE_RE = re.compile(r"Usage:\s+\S.*\bCOMMAND\b")
_BOX_TOP_RE = re.compile(r"^\W*Commands\W*$|^╭─+\W*Commands")


def _run_help(args: list[str], errors: list[dict]) -> Optional[str]:
    try:
        result = subprocess.run(
            [COPILOT_BIN, *args, "--help"],
            capture_output=True,
            text=True,
            timeout=_HELP_TIMEOUT_SECONDS,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        errors.append({"item": "help_probe", "args": args, "error": f"{type(exc).__name__}: {exc}"})
        return None
    return result.stdout


def _extract_subcommands(help_text: str) -> list[str]:
    """Parses Typer/Rich's boxed "Commands" section for subcommand names.
    The box is drawn with Unicode box characters; each entry line looks
    like '│ name    description text ...    │'. Only the box for the
    (single) top-level "Commands" table is present per --help page.

    Long descriptions wrap onto continuation lines that repeat the box
    border but leave the name column blank (e.g. `copilot db dump`'s
    description wraps to a 2nd line). A real entry line has exactly one
    padding space between the border and the name; a continuation line's
    "name" column is blank, so its first non-space character starts much
    further right (past the name column's width). Distinguishing on that
    leading-space count (rather than "first token on the line") is what
    keeps wrapped description text from being misread as a subcommand.
    """
    lines = help_text.splitlines()
    in_box = False
    names: list[str] = []
    for line in lines:
        if not in_box:
            stripped = line.strip()
            if "Commands" in stripped and "─" in stripped:
                in_box = True
            continue
        if line.strip().startswith("╰"):
            break
        if not (line.startswith("│") and line.rstrip().endswith("│")):
            continue
        inner = line[1:-1] if line.rstrip().endswith("│") else line[1:]
        leading_spaces = len(inner) - len(inner.lstrip(" "))
        if leading_spaces > 1:
            continue  # wrapped description continuation line, not a new entry
        content = inner.strip()
        if not content:
            continue
        names.append(content.split()[0])
    return names


def probe_help_tree(base_args: list[str], errors: list[dict]) -> dict:
    """Recursively walks `copilot <base_args...> --help` and every
    subcommand's --help. Returns {"invocations": [{"args", "text"}, ...],
    "concatenated_text": str}. Depth-bounded as a safety net against an
    unexpected cycle; this CLI's tree is 2-3 levels deep in practice.
    """
    invocations: list[dict] = []
    visited: set[tuple] = set()

    def walk(args: list[str], depth: int) -> None:
        key = tuple(args)
        if key in visited or depth > _MAX_HELP_DEPTH:
            return
        visited.add(key)
        text = _run_help(args, errors)
        if text is None:
            return
        invocations.append({"args": ["copilot", *args, "--help"], "text": text})
        if _GROUP_USAGE_RE.search(text):
            for sub in _extract_subcommands(text):
                walk(args + [sub], depth + 1)

    walk(base_args, 0)
    concatenated = "\n".join(inv["text"] for inv in invocations)
    return {"invocations": invocations, "concatenated_text": concatenated}


def get_cli_grammar_cost_upper(spec: dict, errors: list[dict]) -> dict:
    probe = probe_help_tree(spec["cli_group_args"], errors)
    tokens = count_tokens(probe["concatenated_text"])
    return {
        "method": "help-probing (probe-everything upper bound: every --help page under `copilot "
        + " ".join(spec["cli_group_args"])
        + "`, recursively)",
        "invocation_count": len(probe["invocations"]),
        "commands_probed": [" ".join(inv["args"]) for inv in probe["invocations"]],
        "concatenated_chars": len(probe["concatenated_text"]),
        "tokens": tokens,
    }


# ---------------------------------------------------------------------------
# Step 3b -- CLI grammar cost, prose (CLAUDE.md-style docs, if they exist)
# ---------------------------------------------------------------------------

def get_cli_grammar_cost_prose(spec: dict, errors: list[dict]) -> dict:
    doc_path: Path = spec["prose_doc"]
    if not doc_path.is_file():
        errors.append({"item": "grammar_cost_prose", "path": str(doc_path), "error": "no service-reference doc found"})
        return {
            "exists": False,
            "source_files": [],
            "tokens": None,
            "note": (
                "no CLAUDE.md-style usage prose ships anywhere in cli-copilot's docs for this command group -- "
                "the grammar must be learned by --help probing instead; see cli_grammar_cost_upper"
            ),
        }
    text = doc_path.read_text()
    return {
        "exists": True,
        "source_files": [str(doc_path)],
        "chars": len(text),
        "tokens": count_tokens(text),
        "note": "cli-copilot ships a purpose-built service-reference doc for this command group; found by grepping docs/ for the command name",
    }


# ---------------------------------------------------------------------------
# Step 4 -- CLI-side latency (MCP-side explicitly not faked)
# ---------------------------------------------------------------------------

def measure_cli_latency(spec: dict, errors: list[dict], samples: int = 3) -> dict:
    args = spec["latency_args"]
    results = []
    for i in range(samples):
        start = time.perf_counter()
        try:
            proc = subprocess.run(
                [COPILOT_BIN, *args],
                capture_output=True,
                text=True,
                timeout=_LATENCY_TIMEOUT_SECONDS,
            )
            elapsed = time.perf_counter() - start
            results.append({"seconds": round(elapsed, 4), "returncode": proc.returncode})
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
            elapsed = time.perf_counter() - start
            errors.append({"item": "cli_latency", "args": args, "iteration": i, "error": f"{type(exc).__name__}: {exc}"})
            results.append({"seconds": round(elapsed, 4), "returncode": None, "error": str(exc)})

    seconds = [r["seconds"] for r in results]
    return {
        "command": " ".join(["copilot", *args]),
        "note": (
            "real, read-only health-check invocation with this machine's actually-configured credentials -- "
            "same network/auth pattern as collectors/integrations.py's `copilot health`; NOT a credential-free "
            "offline call (no credential-free direct crm/db read op exists), per the task's own allowance for "
            "using health checks when direct ops need creds"
        ),
        "samples_seconds": seconds,
        "mean_seconds": round(sum(seconds) / len(seconds), 4) if seconds else None,
        "min_seconds": round(min(seconds), 4) if seconds else None,
        "max_seconds": round(max(seconds), 4) if seconds else None,
    }


MCP_LATENCY_PLACEHOLDER = {
    "status": "pending",
    "reason": "pending an MCP client driver -- not measured, not estimated, not faked (explicit task instruction)",
    "samples_seconds": [],
}


# ---------------------------------------------------------------------------
# Net advantage (bounded per F-17)
# ---------------------------------------------------------------------------

def compute_net_advantage(schema_tokens_compact: Optional[int], grammar_upper: int, grammar_prose: Optional[int]) -> dict:
    if schema_tokens_compact is None:
        return {"available": False}
    bounded_schema = min(schema_tokens_compact, MCP_DEFER_THRESHOLD_TOKENS)
    result = {
        "available": True,
        "formula": "min(mcp_schema_tokens, 0.10 * context_window) - cli_grammar_cost",
        "bounded_schema_component_tokens": bounded_schema,
        "conservative_using_probe_everything_grammar_cost": bounded_schema - grammar_upper,
    }
    if grammar_prose is not None:
        result["optimistic_using_prose_grammar_cost"] = bounded_schema - grammar_prose
    else:
        result["optimistic_using_prose_grammar_cost"] = None
        result["optimistic_note"] = "no prose exists for this twin; optimistic variant is not computable (see cli_grammar_cost_prose)"
    return result


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------

F17_CAVEATS = [
    "Claude Code auto-defers (does not load upfront) MCP tool schemas above ~10% of the context window -- this is changelog-sourced and UNVERIFIED by this bench; do not present it as a confirmed platform behavior.",
    "The CLI's token advantage over MCP is therefore a bounded constant capped at 10% of the context window, not a value that scales with the number of MCP servers avoided -- adding a 3rd or 30th hypothetical MCP twin would not change net_advantage_tokens once mcp_schema_tokens already exceeds the cap.",
    "Only two real MCP servers with direct CLI twins exist on this machine (nocodb-mcp <-> copilot crm; postgresql-mcp <-> copilot db). This bench cannot speak to hypothetical additional twins, and both terms of the true quantity (MCP schema tokens, CLI grammar cost) live outside CLI Copilot's own repo -- consistent with F-17's own framing that this product's core advantage cannot be measured by looking at this product alone.",
    "cli_grammar_cost_upper is a 'probe everything' upper bound (every --help page), not a claim about what a model actually reads before its first successful crm/db invocation -- the true grammar-acquisition cost for a given session is unmeasured and is somewhere between cli_grammar_cost_prose (if the doc was in context) and cli_grammar_cost_upper.",
    "MCP-side latency is not measured in this bench (pending an MCP client driver); only CLI-side latency is sampled. A CLI-latency-only number is not itself an MCP-vs-CLI latency comparison.",
    "Single-machine, single-author measurement (same confound as the rest of the CSE Verification & Benchmark Program) -- not independently reproduced.",
]


def main() -> int:
    errors: list[dict] = []

    mcp_discovery = discover_mcp_configs(errors)

    twins: dict[str, dict] = {}
    for spec in TWIN_SPECS:
        twin_id = spec["twin_id"]
        config_location = mcp_discovery["twin_locations"].get(spec["mcp_server_name"])

        mcp_schema = get_mcp_schema(spec, config_location, errors)
        grammar_upper = get_cli_grammar_cost_upper(spec, errors)
        grammar_prose = get_cli_grammar_cost_prose(spec, errors)
        latency_cli = measure_cli_latency(spec, errors)

        schema_tokens_compact = None
        if mcp_schema.get("schema_tokens_compact"):
            schema_tokens_compact = mcp_schema["schema_tokens_compact"]["count"]
        grammar_prose_tokens = grammar_prose["tokens"]["count"] if grammar_prose.get("tokens") else None

        net_advantage = compute_net_advantage(
            schema_tokens_compact,
            grammar_upper["tokens"]["count"],
            grammar_prose_tokens,
        )

        twins[twin_id] = {
            "cli_group": "copilot " + " ".join(spec["cli_group_args"]),
            "mcp_server_name": spec["mcp_server_name"],
            "mcp_config_source": config_location["source_file"] if config_location else None,
            "mcp_schema_tokens": mcp_schema,
            "cli_grammar_cost_upper": grammar_upper,
            "cli_grammar_cost_prose": grammar_prose,
            "net_advantage_tokens": net_advantage,
            "latency_samples_cli": latency_cli,
            "latency_samples_mcp": MCP_LATENCY_PLACEHOLDER,
        }

    metrics = {
        "task": "TASK-94 (B-11 MCP-twin bench v1, per finding F-17)",
        "context_window_tokens_assumed": CONTEXT_WINDOW_TOKENS_ASSUMED,
        "mcp_defer_threshold_fraction": MCP_DEFER_THRESHOLD_FRACTION,
        "mcp_defer_threshold_tokens": MCP_DEFER_THRESHOLD_TOKENS,
        "token_counting": {
            "preferred_method": "tiktoken:o200k_base" if _get_tiktoken_encoding() is not None else "heuristic:chars/4",
            "fallback_method": "heuristic:chars/4",
            "caveat": "tiktoken is OpenAI's tokenizer, not Anthropic's -- used as a widely-available proxy since no public Claude tokenizer runs locally; every count also states its own method",
        },
        "mcp_config_discovery": mcp_discovery,
        "twins": twins,
        "f17_caveats": F17_CAVEATS,
        "definitions": {
            "mcp_schema_tokens": "token count of the MCP server's own tools/list JSON-RPC response (compact, no whitespace -- the actual wire bytes), plus a pretty-printed variant for comparison; provenance field states how it was obtained (live-list-tools-handshake > source-reconstruction-partial > phase-1-estimate, in order of trust)",
            "cli_grammar_cost_upper": "token count of every `--help` page under the CLI group, probed recursively -- an upper bound on what a model would need to read to learn the grammar via trial-and-error, not a measurement of what it actually reads",
            "cli_grammar_cost_prose": "token count of cli-copilot's own shipped service-reference doc for the command group, if one exists on this machine; null/exists=false if none does (itself a finding, not an error)",
            "net_advantage_tokens": "bounded per F-17: min(mcp_schema_tokens, 10% of context_window_tokens_assumed) minus a grammar cost. Reported as two variants (conservative = probe-everything grammar cost; optimistic = prose grammar cost) rather than one number, since the task does not license picking one -- see f17_caveats",
            "latency_samples_cli": "wall-clock seconds for 3 real, read-only `copilot --json <group> health` invocations against this machine's actually-configured service credentials (network+auth included, same pattern as collectors/integrations.py)",
            "latency_samples_mcp": "explicitly unmeasured -- pending an MCP client driver; never estimated or faked",
        },
    }

    envelope = {
        "schema_version": SCHEMA_VERSION,
        "collector": COLLECTOR_NAME,
        "generated_at": _utc_now_iso(),
        "host_scope": HOST_SCOPE,
        "metrics": metrics,
        "errors": errors,
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stamped_path = OUT_DIR / f"{COLLECTOR_NAME}-{_utc_stamp()}.json"
    latest_path = OUT_DIR / f"{COLLECTOR_NAME}-latest.json"
    payload = json.dumps(envelope, indent=2, sort_keys=True) + "\n"
    stamped_path.write_text(payload, encoding="utf-8")
    latest_path.write_text(payload, encoding="utf-8")

    print(f"bench_mcp_twin: wrote {stamped_path}")
    print(f"bench_mcp_twin: wrote {latest_path}")
    if errors:
        print(f"bench_mcp_twin: {len(errors)} error(s) recorded in output (non-fatal, see errors[])", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
