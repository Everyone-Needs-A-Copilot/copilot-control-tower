# cse-bench

Measurement harness for the CSE Verification & Benchmark Program
(PRD-9, `01-cse-auditability`). Runs collectors that scan real CSE
artifacts on this machine and emit schema-versioned, timestamped JSON —
the raw material for the P1 adoption dashboard (B-8) and every claim
this program registers in `claims.yaml` (B-2). Practices what Phase 1's
finding F-15 preached: every collector output carries a `schema_version`,
not just a doc claiming one exists.

Serves tasks **B-4** (`collectors/tasksdb.py` — Task Copilot store
collector) and **B-7** (`cse_bench.py` — the single entry point below).

## Usage

```bash
# Run every registered collector, write to the default output/ dir
python3 cse_bench.py collect

# Run one collector only
python3 cse_bench.py collect --only tasksdb

# Run the golden-set eval collector (needs claude-copilot's cc on this machine)
python3 cse_bench.py collect --only evals

# Run a subset, write elsewhere
python3 cse_bench.py collect --only tasksdb,transcripts --out /tmp/cse-bench-out

# List what's registered
python3 cse_bench.py list

# Render the web-view dashboard (B-8) from whatever collector output +
# claims.yaml currently exist, then open it — no server, no network
open output/dashboard.html   # after: python3 cse_bench.py collect && python3 cse_bench.py render
```

Run from `tools/cse-bench/` (the script adds its own directory to
`sys.path` implicitly via Python's normal script-directory behavior, so
the `collectors` package resolves without installation). Stdlib only —
no virtualenv, no pip install.

## Output contract

Every collector writes two files per run into `output/` (gitignored —
regenerated, not source):

- `output/<collector>-<UTCstamp>.json` — one stamped file per run, kept
  for history/trend analysis.
- `output/<collector>-latest.json` — stable pointer, always the most
  recent run for that collector. This is what the dashboard (B-8) reads.

Every file is the same envelope:

```json
{
  "schema_version": "cse-bench/1",
  "collector": "tasksdb",
  "generated_at": "2026-07-12T15:48:18Z",
  "host_scope": "single-machine-single-user",
  "metrics": { "...": "collector-specific" },
  "errors": [ { "repo": "...", "path": "...", "error": "..." } ]
}
```

`errors` is always present (empty array if nothing failed) — a
collector partially failing (e.g. one locked/corrupt store) never
crashes the run; it degrades to a per-item error entry instead. Bump
`schema_version` (`cse-bench/2`, ...) on any breaking change to the
envelope or to a collector's `metrics` shape; consumers should read the
version before assuming a field exists.

## Collectors

- **`tasksdb`** (B-4) — scans every Task Copilot SQLite store matching
  `/Volumes/Dev/Sites/COPILOT/*/.copilot/tasks.db` read-only (WAL-safe
  `file:...?mode=ro` URI). Emits per-repo and total task counts by
  status, completion rate, a cancelled/reopened rework signal, work
  products by type, PRD counts, agent-assignment mix, a created/
  completed-per-ISO-month trend since the earliest activity, and
  per-repo + overall activity date ranges. Symlinked product
  directories that resolve to the same physical store (e.g.
  `shared-docs -> knowledge-copilot`) are de-duplicated and reported
  under `aliases_detected`, not double-counted. Full operational
  definitions (completion rate, the reopened-count proxy, etc.) are
  restated in the output's own `metrics.definitions` block so no
  consumer has to read this file to know what a number means.
- **`evals`** (TASK-95/B-12 groundwork) — runs `cc eval --agent <agent>
  --json` (claude-copilot's `~/.local/bin/cc`) for every agent that has a
  golden set under `<claude-copilot>/.claude/evals/<agent>/*.yaml`, and
  reports `agents_total` (from `<claude-copilot>/.claude/agents/*.md`),
  `agents_with_evals`, `coverage_ratio`, and a `per_agent` pass-rate
  breakdown. The eval runner itself is a pure-Python deterministic
  assertion engine (no LLM call, no network) — this collector always
  performs a real, complete suite run. `cc` missing, or either directory
  missing, degrades to an `errors` entry, never a crash.
- **`solutions`** (TASK-123/W-1, Phase 4 outcome program) — the Outcome
  Ledger collector. Scans the same `tasksdb` glob (de-duped the same way)
  for the `solutions` table `tc solution` (claude-copilot `tools/tc/`)
  writes, and emits O-1 (TTFLS: the t_working -> t_loveable gap), O-2
  (Completeness: sessions/tokens-to-done and post-ship fix-vs-feature
  share, for solutions shipped against a locked brief), O-3 (Speed,
  OBSERVED ONLY — started_at -> t_working / t_loveable / closed_at elapsed
  seconds; no bare-harness counterfactual, that's O-6/the W-3 ladder
  harness), and O-5 (Survival: started -> shipped -> in_use counts and
  ratios). A store with no `solutions` table yet (`ledger_present: false`)
  is the honest pre-adoption state, not an error; every aggregate is
  `null`, not `0`, when there's no data to compute it from — an empty
  ledger is the honest state. Feeds claims `outcome-ttfls`,
  `outcome-completeness`, `outcome-speed-observed`, `outcome-survival`
  (`../../docs/40-initiatives/01-cse-auditability/claims.yaml`). Its
  output also feeds the **Outcome Ledger card** in the dashboard's
  ecosystem scoreboard (`render/dashboard.py::render_outcome_ledger_card`)
  — an empty ledger renders as an honest "0 solutions, awaiting data"
  state, not fabricated numbers and not an absent section.

## Dashboard (`render` — TASK-91/B-8 original build, reorganized by
component/SOUL in TASK-111/S-5)

```bash
python3 cse_bench.py collect   # refresh output/*-latest.json
python3 cse_bench.py render    # writes output/dashboard.html
open output/dashboard.html     # no server, no network — opens straight from file://
```

`render` reads every `output/<collector>-latest.json` this machine has
produced, plus the claims register (`../../docs/40-initiatives/01-cse-auditability/claims.yaml`,
via `render/`'s reuse of `check_claims.py`'s PyYAML-or-fallback loader),
and writes ONE self-contained `output/dashboard.html` — everything
rendered server-side in Python, nothing fetched client-side. Same
invariant as the rest of Control Tower: the collectors compute, this
view only renders.

Per the 2026-07-12 owner-directed SOUL-alignment revision
(`../../docs/40-initiatives/01-cse-auditability/phases/phase-2-prd.md` §2.5),
the dashboard is organized around exactly **three components**, each
measured against its own ratified SOUL promise — no "instruction layer"
section, no "voice content" component:

- **Ecosystem scoreboard** (header) — work finished/week, rework rate, a
  "days start → done" tile that is honestly reported as not computable
  (tasksdb has no `completed_at` column), tokens/task (approx, sourced
  from `framework_soul`'s token trend once it has run), the permanent
  single-author caveat, and a "ladder test: not yet run" card — "more
  work done, faster" is an ecosystem-level claim (B-13/B-14), never a
  single component's.
- **Development framework** (`claude-copilot` & `codex-copilot` SOUL —
  "disciplined, resumable, inspectable work... without burning the token
  budget rebuilding context," explicitly never speed/quality) — Task
  Copilot throughput, delegation/protocol discipline, golden-set eval
  coverage, the S-1 resume-cost bench, and the S-2 framework-SOUL
  collector (externalization ratio vs. the SOUL's own "~94%" claim, agent
  return-size frugality, main-session token trend, QA-gate/ARTIFACT-marker
  adherence). Codex parity survives only as a small "sync plumbing" chip
  in this section's footer; commit velocity is dropped from the
  measurement story entirely.
- **Knowledge framework** (`knowledge-copilot` SOUL — accurate
  understanding for good decisions; never a stale dump, marketing
  narrative, or quietly contradictory facts) — the B-9 private-fact Q&A
  bench, the S-3 knowledge-SOUL collector (registry/cross-link integrity,
  contradictory facts, staleness/archive honesty, orphan rate, own-content
  voice-lint), knowledge read-coverage, and the B-10 voice-conformance
  bench (with the "distilled rules beat raw prose" finding called out).
- **Integration framework** (`cli-copilot` SOUL — one binary, one
  grammar; client, never server; honest, hint-bearing failure) — the S-4
  per-service conformance scorecard (chips grid against the SOUL's own
  mechanical non-negotiables), live integration health, and the
  MCP-twin bench reframed as a doc-claim check (token advantage requires
  shipping usage prose up front — the doc claim is reworded, not a
  product verdict).
- **Trust ledger** (bottom, unchanged mechanics) — the claims register
  rendered live: every claim's status chip, statement, check command, and
  `last_checked`, plus the permanent "adoption metrics are single-author
  data" banner (T8 open).

Every collector card is LIVE the moment its collector has written
`output/<name>-latest.json`; until then it renders a quiet "not yet run"
placeholder — safe to run `render` before every collector has run at
least once. `bench_resume_cost` (S-1), `framework_soul` (S-2),
`knowledge_soul` (S-3), and `cli_soul` (S-4, owned by `cli-copilot`) are
matched against their real, observed shapes as of this reorg; every
renderer keeps `first()`/`dig()` fallback candidates from its original
pre-landing guesses in case a shape changes later. An unrecognized shape
degrades to a raw-JSON details block, never a crash or an invented
number.

`render/dashboard.py`'s per-collector renderers are written against each
collector's real, observed `metrics` shape (see each function's
docstring for which `output/*-latest.json` it was verified against); an
unrecognized future shape change degrades to an in-page notice with the
raw JSON in a `<details>`, never a crash — see that file's module
docstring for the full schema-tolerance contract.

## Adding a collector

Drop a module into `collectors/` that exposes `COLLECTOR_NAME` (str)
and `collect(**kwargs) -> {"metrics": {...}, "errors": [...]}`; `cse_bench.py`
auto-discovers it via `pkgutil` — no registry edits needed.

## claims.yaml — the claims register (TASK-85 / B-2)

The register itself lives at
[`../../docs/40-initiatives/01-cse-auditability/claims.yaml`](../../docs/40-initiatives/01-cse-auditability/claims.yaml),
not here — it's initiative documentation, not tooling. See its own header
comment for the schema and
[`../../docs/40-initiatives/01-cse-auditability/README.md`](../../docs/40-initiatives/01-cse-auditability/README.md)
("Validation Contract V-2") for why it exists: it is this program's
pre-registration mechanism. No metric this program quotes (including
values emitted by the collectors above) may be reported without a
`claims.yaml` entry (phase-2-prd.md §7).

### `check_claims.py` — the structural validator

```bash
tools/cse-bench/check_claims.py
# or, explicitly:
python3 tools/cse-bench/check_claims.py docs/40-initiatives/01-cse-auditability/claims.yaml
```

Validates, and only validates, structure:

- every claim has a unique, non-empty `id`
- every claim has `statement`, `check`, `status`, `evidence`
- every `definition_refs` entry resolves to a key under `definitions:`
- `status` is one of `passing | failing | unchecked | gated`
- `last_checked` is present and ISO-dated (`YYYY-MM-DD`) whenever
  `status != unchecked`

It does **not** re-run each claim's own `check` command — most of those
touch `~/.claude/projects` or sibling repos outside this one, which is too
slow and too environment-dependent for a commit-time hook. Re-running the
checks themselves is a separate, manual or CI concern; run the command
named in a claim's `check:` field directly.

Exit 0 with a one-line summary on success; exit 1 with every violation
listed on failure. Stdlib-only — no PyYAML required, though it's used when
importable (see "YAML loading" below).

### YAML loading

`check_claims.py` prefers `import yaml` (PyYAML) when available — the
common case, confirmed present on this machine (`python3 -c "import
yaml"` succeeds via the Homebrew Python site-packages). When PyYAML is
NOT importable, it falls back to a small vendored strict-subset parser
(inlined in the script) that supports exactly the YAML `claims.yaml`
itself uses: block mappings, flat-mapping block sequences (`- key:
value` + continuation keys), flow sequences (`[a, b]`), quoted/bare
scalars, and folded/literal block scalars (`>`, `>-`, `|`, `|-`). It is
deliberately not a general-purpose YAML parser. Both loaders were checked
to produce byte-identical parsed structures for the actual register file
during this tool's own verification.

### Pre-commit wiring

`install-claims-hook.sh` appends a second, independently-marked managed
block to `.git/hooks/pre-commit`, **chained onto** (never replacing)
whatever is already there — the same pattern
`scripts/initiatives/install-initiatives-hook.sh` uses for the
initiatives-standard check. Re-running either installer only touches its
own `BEGIN`/`END`-marked block.

```bash
tools/cse-bench/install-claims-hook.sh
```

This has already been run in this repo; `.git/hooks/pre-commit` now runs
both the initiatives-standard check and `check_claims.py` on every commit.
`.git/hooks/` is not version-controlled, so a fresh clone needs this
script (or `scripts/initiatives`'s own installer pattern extended to call
it) run once — this is the same bootstrap gap the initiatives hook already
has, not a new one introduced here.
