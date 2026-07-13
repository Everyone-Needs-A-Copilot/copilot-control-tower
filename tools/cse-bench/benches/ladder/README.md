# ladder — W-3 counterfactual ladder harness + MLP rubric (TASK-125)

Runs one **job pack** (`job_pack.py`, v1: 3 real-software jobs of graduated
size) at each of **4 ladder rungs** (`configs.py`: bare → +framework →
+knowledge → +integrations), per
[`phases/phase-4-outcome-program-prd.md`](../../../../docs/40-initiatives/01-cse-auditability/phases/phase-4-outcome-program-prd.md)
par.3 W-3 and par.2 O-6 ("Counterfactual Delta"). This is the bench that
would give `outcome-counterfactual-delta` and `outcome-token-efficiency`
their first honest numbers — **not yet run**, deliberately: see "The hard
gate" below.

## The hard gate (read this first)

Per TASK-125's own instructions and
[`phases/phase-4-handoff.md`](../../../../docs/40-initiatives/01-cse-auditability/phases/phase-4-handoff.md)
§6 row 6: the MLP rubric that scores `t_loveable` must be **owner-ratified
before the first scored run**, full stop. This is enforced two ways, not
just by operator discipline:

1. **Mechanically, in code.** `run.py`'s `check_signoff()` reads
   [`../../../../docs/40-initiatives/01-cse-auditability/decisions/DEC-6-mlp-rubric-signoff.md`](../../../../docs/40-initiatives/01-cse-auditability/decisions/DEC-6-mlp-rubric-signoff.md)
   for the literal string `Status: **ratified**`. Absent that string, any
   invocation of `run.py` without `--dry-run` exits 1 and refuses to call
   `claude` at all — see "Dry-run output" below for what this actually
   prints today.
2. **In the register.** `claims.yaml`'s `outcome-counterfactual-delta` and
   `outcome-token-efficiency` stay `unchecked` (not `passing`/`failing`)
   until a live run produces real numbers — see the register entries
   themselves for the exact evidence text.

This bench was built, and its full pipeline dry-run-validated, WITHOUT
ever executing a live scored run — that is the correct, deliberate
end-state of TASK-125, not an unfinished task.

## The 4 configs (`configs.py`)

| Rung | What's materialized | Isolation mechanism |
|---|---|---|
| `bare` | Fresh empty workdir. No `.claude/`, no CLAUDE.md. | `PATH` excludes `tc`/`cc` (`~/.local/bin`) and cli-copilot's venv bin. |
| `+framework` | `.claude/{agents,commands,skills}/` + `CLAUDE.md`, copied directly from claude-copilot's own `VERSION.json` roster (the same files `/setup-project`'s FULL-mode flow would copy — replicated in Python rather than run live, so the ladder measures a job's MARGINAL cost with the framework already installed, not the one-time setup cost). `CC_KNOWLEDGE_REPO` points at an **empty** directory (not unset). | `tc`/`cc` restored to `PATH`; cli-copilot venv bin still excluded. |
| `+knowledge` | Same as `+framework`, but `CC_KNOWLEDGE_REPO` points at the real `knowledge-copilot` repo. | Same PATH as `+framework`. |
| `+integrations` | Same as `+knowledge`, plus cli-copilot's `copilot` entry point on `PATH` (its own `.venv313/bin`, since no `copilot` binary is installed anywhere else on this machine — see "Environment gaps" below) and every `KEY=VALUE` pair from cli-copilot's own `.env` exported into the job's process env. | Full PATH. |

Every rung also passes `claude`'s real `--setting-sources project` flag
(verified against `claude --help` on this machine before writing any of
this) — the actual isolation lever, not cwd alone: this dev machine
already has claude-copilot installed at the user level
(`~/.claude/`, `~/.local/bin/{tc,cc}`), so a merely-empty directory would
still risk inheriting USER-scope settings the same way
[`../resume_cost/run.py`](../resume_cost/run.py)'s own design notes
describe a tool-enabled model reaching a real fixture that happened to
exist elsewhere on the same host ("this dev machine is not a clean room").
`--setting-sources project` closes that path structurally for every rung,
including `bare`.

**Environment gaps found while building this bench (recorded honestly, not
worked around):** `/opt/homebrew/bin/copilot` — the path this repo's own
README and `../mcp_twin/run.py` name — **does not exist on this machine**.
`copilot` is also a **shell alias for `cd`** interactively (per
`phases/phase-4-handoff.md`'s own "Environment traps"). The only real,
working `copilot` entry points found are inside cli-copilot's own venvs
(`cli-copilot/.venv313/bin/copilot`, verified live via `--help`). `configs.py`
uses that path and records a `warnings[]` entry if it's ever missing, so a
`+integrations` run on a machine without it produces an honest environment
warning rather than a silent no-op.

**Open risk before the first live run (stated, not solved here):** every
config also overrides `HOME` to a fresh per-run temp directory, so a live
run's `claude -p` transcripts land under an isolated `~/.claude/projects/`
rather than this machine's REAL transcript corpus — several other
`cse-bench` collectors (`framework_soul`'s agent-frugality distribution,
`transcripts.py`) already treat that corpus as production data, and mixing
synthetic ladder-bench sessions into it would silently contaminate those
other claims. What this bench does **not** verify: whether an isolated
`HOME` still resolves Anthropic auth (OAuth token / keychain) the same way
the real `HOME` does. Untested — verify this on a throwaway single cell
before trusting a full 12-cell live run.

## The job pack (`job_pack.py`, v1)

Format is a plain Python module, not YAML — see `job_pack.py`'s own
docstring for why (no PyYAML importable on this machine, verified live).
"Pack format is pluggable" (PRD par.3 W-3) is satisfied by
`run.py --job <id>` / a future `--job-pack <module>` flag, not by a file
format promise.

| Job | Size | What it tests | Mechanical `t_working` check |
|---|---|---|---|
| `job-1-bugfix` | small | An R-series-style bugfix (`fixtures/job-1-bugfix/calc.py` has a real off-by-one bug) | `python3 test_calc.py` (stdlib `unittest`, not pytest — this machine's default `python3` has no pytest importable, verified live) exits 0 |
| `job-2-web-utility` | medium | Building a small CLI utility from scratch (`wordfreq.py`, a word-frequency counter) | `fixtures/job-2-web-utility/check.py` runs the model's own `wordfreq.py` against `sample.txt` and diffs stdout against a precomputed `expected_output.txt` |
| `job-3-integration-report` | large, **exercises integrations** | Pulling and reporting on live service health via the `copilot` CLI, with an explicit honest-fallback path when integrations aren't reachable | `fixtures/job-3-integration-report/check.py`: `report.md` must contain either a `Services: N healthy` line or the literal phrase `integrations unavailable` — never fabricated data either way |

job-3 is deliberately reachable (mechanically `t_working`-passable) from
EVERY rung, including `bare` — the brief instructs an honest "integrations
unavailable" fallback instead of fabrication. The ladder's O-1..O-4 deltas
across rungs are what should reveal whether `+integrations` produces a
materially better report, not a rigged pass/fail gate.

## The MLP rubric (`rubric.md`)

4 dimensions, each scored 0–3 against a written exemplar anchor (not a bare
"good/bad" scale): **guided experience, sensible defaults, error help,
polish** — the PRD's own list, par.3 W-3. `t_loveable` = the first
(config, job, rep) whose scores are ALL ≥2 ("Adequate"), not an averaged
total — see `rubric.md` §§1–3 for the full anchors and the blind,
exemplar-anchored judging protocol. **Status: DRAFT, not ratified** — see
"The hard gate" above and
[`DEC-6-mlp-rubric-signoff.md`](../../../../docs/40-initiatives/01-cse-auditability/decisions/DEC-6-mlp-rubric-signoff.md).

## Measurement capture

Per job-config cell: wall-clock seconds and token usage
(`input`/`cache_creation`/`cache_read`/`output`, same convention as
[`../resume_cost/run.py`](../resume_cost/run.py)'s `extract_usage()`) from
the `claude -p --output-format json` job call — O-3/O-4's mechanical
halves. `t_working` (O-1's mechanical half) from the job's acceptance
check. `t_loveable` (O-1's judged half) is built and dry-run-validated but
blocked from live execution (see above). Every live cell's config
manifest, full model-call JSON envelope, and acceptance-check
stdout/stderr are written to
`output/bench_ladder-runs/<UTC stamp>/<job_id>__<config>__rep<N>.json` for
audit — this never happens during `--dry-run` (nothing is written to
`output/` in that mode, matching every other bench in this directory).

## Re-run it

```bash
cd tools/cse-bench/benches/ladder

# The only thing that has actually been run against this bench so far:
python3 run.py --dry-run

# Restrict to one rung / one job / fewer reps while validating:
python3 run.py --dry-run --config bare --job job-1-bugfix

# The live run — REFUSED today (see "The hard gate"):
python3 run.py
```

## Dry-run output (this is what has actually been verified)

```
$ python3 run.py --dry-run
run.py: job_pack.py OK (3 job(s): job-1-bugfix, job-2-web-utility, job-3-integration-report)
run.py: rubric.md OK (4 dimension(s): Guided experience, Sensible defaults, Error help, Polish)
run.py: DEC-6 sign-off gate: ratified=False (DEC-6 exists but does not contain the literal marker 'Status: **ratified**' — owner sign-off is still pending)
run.py: 4 config(s) x 3 job(s) x 1 rep(s) = 12 cell(s) (model=sonnet, judge_mode=human, concurrency=2, timeout=900s)
run.py: run_root=<a fresh tempfile.mkdtemp()>
run.py: [.../12] <job> / <config> rep1 -> dry-run OK
...
run.py: dry-run complete, 12 cell(s) materialized and validated, 0 with wiring problems, 0 claude invocations, nothing written to output/.
```

12/12 cells materialize cleanly (all 4 configs × all 3 jobs), every
acceptance-check command resolves against a real file on disk, and the
signoff gate correctly reports `ratified=False`. See "Environment gaps"
above for the `warnings[]` this run surfaces about `copilot`'s real
location on this machine — those are recorded per-cell in the dry-run
records, not hidden.

## What has NOT been measured (stated honestly)

- No live `claude -p` call has ever been made by this bench.
- No `t_working` has been mechanically observed against a real model
  deliverable (only against the fixtures' own known-buggy/reference states,
  while building/validating the fixtures themselves).
- No `t_loveable` score exists.
- `outcome-counterfactual-delta` and `outcome-token-efficiency` remain
  `unchecked` in `claims.yaml` — this bench makes them checkable, not yet
  checked.
