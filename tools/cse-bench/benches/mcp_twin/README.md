# mcp_twin bench (TASK-94 / B-11)

An honest, bounded measurement of CLI Copilot's core claimed advantage —
*"one CLI instead of a bespoke MCP server per service"* — against the
only two real MCP servers on this machine that have direct CLI twins,
per [`phase-1-findings.md` finding F-17](../../../../docs/40-initiatives/01-cse-auditability/phases/phase-1-findings.md):

| MCP server       | CLI twin      |
| ---------------- | ------------- |
| `nocodb-mcp`     | `copilot crm` |
| `postgresql-mcp` | `copilot db`  |

F-17's finding is that the honest quantity is **not** "MCP schema tokens
saved" — Claude Code reportedly auto-defers (doesn't load upfront) MCP
tool schemas above ~10% of the context window, so the CLI's advantage is
a *bounded constant*, not a number that scales with more MCP servers —
and that constant is offset by a previously **uncounted cost**: the
tokens a model spends learning the CLI's own verb grammar. This bench
measures both sides of:

```
net_advantage_tokens = min(mcp_schema_tokens, 10% × context_window) − cli_grammar_cost
```

## Usage

```bash
cd tools/cse-bench
python3 benches/mcp_twin/run.py
```

Writes `output/bench_mcp_twin-<UTCstamp>.json` (kept for history) and
`output/bench_mcp_twin-latest.json` (stable pointer), in the same
envelope every other collector in this program uses
(`schema_version` / `collector` / `generated_at` / `host_scope` /
`metrics` / `errors` — see `../../README.md`). This is a standalone
script, deliberately **not** wired into `cse_bench.py`'s collector
registry — that machinery belongs to other tasks; run it directly.

Stdlib only for the fallback path; uses `tiktoken` for token counting
when importable (it is, on this machine) and falls back to a `chars/4`
heuristic otherwise — every count in the output states which method
produced it.

## What it measures, and how

1. **Finds the two MCP servers.** Scans `.mcp.json` across
   `/Volumes/Dev/Sites/COPILOT/*/` (one level, matching F-17's search
   scope) plus `~/.claude.json`'s top-level and per-project `mcpServers`
   blocks. Reports server name, command, args (file paths), and env
   **variable names only** — env *values* (API keys, DB passwords) are
   never read for this purpose and never appear in output.

2. **Measures the real MCP schema, live, when it's safe to.** Spawns
   each server's own entry point (`node src/index.js`, the exact file its
   `.mcp.json` points at) with throwaway, unreachable dummy credentials
   and performs a real MCP `initialize` + `tools/list` JSON-RPC handshake
   over stdio — no tool is ever called, no network is ever touched (both
   servers' DB pool / HTTP client construction is lazy, verified by
   reading `nocodb-client.js` / `database-client.js` before relying on
   it). Falls back to a partial source-regex reconstruction
   (`name`/`description` pairs only — a known undercount, since
   `inputSchema` isn't safely regex-reconstructable), then to Phase 1's
   hand estimate, if the live handshake fails. Every number carries a
   `provenance` field naming which tier produced it.

3. **Token-counts the schema two ways** — compact JSON (the actual
   `tools/list` wire bytes) and pretty-printed (2-space indent) — since
   they differ by ~40-45%, and Phase 1's hand estimate lands closer to
   the pretty variant. `mcp_schema_tokens` uses the compact count as
   the headline figure.

4. **CLI grammar cost, upper bound**: recursively walks
   `copilot crm --help` / `copilot db --help` and every subcommand's
   `--help`, concatenates all of it, and token-counts the result. This
   is the "probe everything" ceiling, not a claim about what a model
   actually reads.

5. **CLI grammar cost, prose**: token-counts whatever CLAUDE.md-style
   service-reference doc `cli-copilot` ships for that command group
   (`docs/services/07-nocodb.md`, `docs/services/06-postgresql.md`).
   Both exist on this machine today — worth stating plainly, since F-17
   raised the possibility that no such prose exists anywhere and the
   grammar could only be probed.

6. **`net_advantage_tokens`** is reported as **two variants**, not one
   number, since the task doesn't license picking either as canonical:
   - `conservative_using_probe_everything_grammar_cost` (grammar cost =
     upper bound)
   - `optimistic_using_prose_grammar_cost` (grammar cost = prose, when
     prose exists)

7. **CLI-side latency**: 3 timed `copilot --json crm health` /
   `copilot --json db health` invocations — real, read-only, but *not*
   credential-free (no credential-free direct `crm`/`db` read op exists;
   this is the same allowance the task itself makes: "`copilot health`'s
   crm/db checks count if direct ops need creds", same network/auth
   pattern `collectors/integrations.py` already uses for `copilot
   health`). **MCP-side latency is explicitly left as
   `{"status": "pending", ...}`** — never estimated or faked; a real
   number requires an MCP client driver this program doesn't have yet.

## Every number's honesty caveats (`metrics.f17_caveats`)

The output's `f17_caveats` array restates, verbatim-reusable, the same
caveats this README states in prose: the 10% deferral threshold is
changelog-sourced and unverified by this bench; the advantage is a
bounded constant, not a scaling one; only two real twins exist on this
machine; `cli_grammar_cost_upper` is a ceiling, not a measured read
count; MCP-side latency isn't measured at all; and this is a
single-machine, single-author measurement like the rest of the program.

## Known quirk this bench surfaced

`nocodb-mcp`'s startup path writes its environment-validation banner via
`console.log` (stdout) instead of `console.error` (stderr) —
`postgresql-mcp`'s equivalent uses `console.error` correctly. This
pollutes the JSON-RPC stdio stream with non-protocol lines ahead of the
real handshake responses; this bench's reader tolerates it (skips
non-JSON lines), but a naive MCP stdio client would not. Recorded in
`metrics.twins.crm.mcp_schema_tokens.notes`, not fixed here (out of
scope — this bench owns only `benches/mcp_twin/` and `output/`).
