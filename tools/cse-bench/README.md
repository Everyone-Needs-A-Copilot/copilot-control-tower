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

# Run a subset, write elsewhere
python3 cse_bench.py collect --only tasksdb,transcripts --out /tmp/cse-bench-out

# List what's registered
python3 cse_bench.py list
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
