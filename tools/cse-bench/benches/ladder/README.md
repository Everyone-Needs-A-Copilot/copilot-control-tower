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

1. **Mechanically, in code.** `run.py`'s `check_signoff()` requires DEC-6's
   header to contain EXACTLY ONE `Status:` field whose value starts with
   `**ratified**`. Absent that, any invocation of `run.py` without
   `--dry-run` exits 1 and refuses to call `claude` at all — see
   "Dry-run output" below for what this actually prints today. QA WP-23
   found two bypasses in an earlier version (a false positive from an
   unrelated second `Status:` line, and from a `Status: **ratified**`
   string hidden inside an HTML comment); both are now closed by
   construction (HTML comments are stripped first, matching is per single
   line — never spanning a line break — and the gate fails CLOSED,
   i.e. NOT ratified, whenever it finds zero or more than one `Status:`
   field rather than guessing which one is canonical). Regression tests
   for both bypasses (plus the fix) live in `test_signoff_gate.py` — run
   `python3 test_signoff_gate.py -v`.
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

**The actual isolation lever is the per-run `HOME` override, not
`--setting-sources project` (corrected per QA WP-23 finding 5 — an earlier
draft of this doc, and of `configs.py`'s own docstring, over-credited the
flag).** This dev machine already has claude-copilot installed at the user
level (`~/.claude/agents/`, `~/.local/bin/{tc,cc}`), so a merely-empty
directory would still risk inheriting that content the same way
[`../resume_cost/run.py`](../resume_cost/run.py)'s own design notes
describe a tool-enabled model reaching a real fixture that happened to
exist elsewhere on the same host ("this dev machine is not a clean room").
Claude Code auto-discovers user-level CLAUDE.md/agents/skills relative to
`$HOME/.claude/` — every rung materializes a **fresh, empty, per-run**
`HOME` (`configs.py`'s `_fresh_home()`), so there is no real `~/.claude/`
to discover, structurally, not by instruction. `--setting-sources project`
(a real flag, verified against `claude --help`) is kept as a SECONDARY,
narrower restriction on which `settings.json`-style permission/hook
sources merge — it does not, by itself, control CLAUDE.md/agent-file
discovery, which is `HOME`'s job. Do not remove the `HOME` override
thinking `--setting-sources` alone covers isolation.

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

A welcome side effect of the same `HOME` override: a live run's `claude -p`
transcripts land under the isolated `~/.claude/projects/` rather than this
machine's REAL transcript corpus — several other `cse-bench` collectors
(`framework_soul`'s agent-frugality distribution, `transcripts.py`) already
treat that corpus as production data, and mixing synthetic ladder-bench
sessions into it would silently contaminate those other claims.

**Auth-under-isolation (closed, DEC-6 live-run pre-flight, 2026-07-14):**
this was flagged above as untested; it was tested, found broken, and
fixed before the first live run. A fresh isolated `HOME` reported
`claude auth status` as `loggedIn: false` for two independent reasons,
both verified live with `env -i`, not assumed: (1) `claude`'s keychain
lookup resolves the OS keychain SEARCH LIST from files under
`$HOME/Library/...`, so a brand-new `HOME` has no keychain to find, and
(2) even with the keychain reachable, `claude` also needs `USER`/`LOGNAME`
set (subprocess.run(env=...) REPLACES the whole environment, and the
account-name match fails silently without them) plus the account/session
state normally cached at `$HOME/.claude.json`. `configs.py`'s
`_seed_home_for_auth()` now symlinks `<home>/Library/Keychains` to the
REAL user's keychain (read-only reuse — no secret is copied into any file
this bench writes) and copies (never symlinks, so writes stay isolated)
the real `~/.claude.json` into the fresh home; `_base_env()` now passes
`USER`/`LOGNAME`/`TMPDIR`/`SHELL` through from the real environment (none
of these four are part of the ladder's deliberate isolation levers).
Verified end-to-end against the REAL harness, not just a manual probe:
`python3 run.py --i-know-this-is-blocked-on-signoff --judge-mode human
--config bare --job job-1-bugfix` reached `status=ok t_working=True` with
a real `total_cost_usd` in the audit record.

**`bare`'s own PATH couldn't reach `claude` (closed, same pre-flight):** on
this machine `claude` is co-located with `tc`/`cc` at `LOCAL_BIN`
(`~/.local/bin`), so `bare`'s original isolation — exclude `LOCAL_BIN`
entirely to hide `tc`/`cc` — also hid `claude` itself, and `bare` could not
invoke the model at all. `--dry-run` could never catch this (it never
calls `shutil.which`/`subprocess` for claude). Fixed by
`_claude_only_bin_dir()`: a run-scoped directory containing ONLY a symlink
named `claude` (resolved once, at import time, against the operator's own
real PATH) goes on `bare`'s PATH instead of the whole `LOCAL_BIN`
directory — `tc`/`cc`/`copilot` stay unreachable from `bare`, `claude`
itself is reachable everywhere.

**Rep independence (QA WP-23 finding 4, fixed):** every workdir and `HOME`
is keyed on `(job_id, config_name, rep)` — `--reps > 1` used to silently
reuse the same directory across reps with no cleanup, contaminating rep 2
with rep 1's leftover files. Verified: `python3 run.py --dry-run --reps 3
--job job-1-bugfix --config bare` now materializes three fully distinct
`rep1/rep2/rep3` directory trees.

**`protected_files` enforcement (QA WP-23 finding 6, fixed — mechanical,
cheap):** every job_pack.py `protected_files` entry is sha256-hashed right
after fixture materialization and re-hashed after the job call
(`capture_protected_hashes()` / `check_protected_files()`); a mismatch (the
model modified or deleted a file its brief explicitly said not to touch)
now FAILS that cell's `t_working`, not just a footnote — recorded in the
audit trail under `protected_files_check`.

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

Per job-config cell: wall-clock seconds (O-3) and TWO token figures (O-4) —
**`marginal_spend`** (input + cache_creation + output, EXCLUDING
cache_read — the PRIMARY O-4 metric) and **`billed_volume`** (the same
plus cache_read — reported only as a labeled, transparency-only
secondary), from the `claude -p --output-format json` job call's `usage`
block. **QA WP-23 finding 1 (fixed):** an earlier version computed only
billed_volume and used it as the sole O-4 figure — the exact F-8-class
conflation `collectors/economy.py` already had to correct (claims.yaml
`solution_token_accounting`, commit `26a3dd7`): a single `claude -p` job
call here enables tools and can span many internal turns, so its
`usage.cache_read_input_tokens` is the same kind of cumulative-across-turns
figure that made economy.py's raw sum misleading. `extract_usage()` now
uses the EXACT SAME two formulas as `collectors/economy.py`'s
`_marginal_spend`/`_billed_volume`, so a ladder number and a ledger number
are commensurable, not just similarly named (this paragraph described the
intended fix before the DEC-6 live-run pre-flight, 2026-07-14, discovered
`extract_usage()`/`aggregate()` had never actually been updated to compute
either field — the documentation had outrun the code; both are now
genuinely wired, verified against a real `claude -p` job call's `usage`
block, not just unit-checked against `economy.py`'s formulas in isolation)
— see `aggregate()`'s
`o4_token_reduction_pct_vs_bare` (primary, marginal_spend) vs
`..._billed_volume_secondary` (secondary) fields.

`t_working` (O-1's mechanical half) from the job's acceptance check AND
the mechanical `protected_files` check (see above — a protected-file
violation now fails `t_working` too). `t_loveable` (O-1's judged half) is
built and dry-run-validated but blocked from live execution (see above).
Every live cell's config manifest, full model-call JSON envelope,
acceptance-check stdout/stderr, and protected-files hash comparison are
written to
`output/bench_ladder-runs/<UTC stamp>/<job_id>__<config>__rep<N>.json` for
audit — this never happens during `--dry-run` (nothing is written to
`output/` in that mode, matching every other bench in this directory).

## Cost ceilings (QA WP-23 finding 3, fixed)

Two REAL, natively-enforced ceilings, both now with safe non-`None`
defaults (previously `--max-budget-usd` defaulted to `None` — no cap at
all): **`--timeout`** (wall-clock, default 900s / 15 min — kills a hung
call outright) and **`--max-budget-usd`** (dollar spend, default `$3.00`
per job call — `claude -p`'s own native flag, verified via `claude --help`;
~30x [`../resume_cost/run.py`](../resume_cost/run.py)'s ~$0.10
single-inference probe, enough headroom for a real multi-turn coding job
without being unbounded — a full 12-cell run's absolute worst case is
capped at 12 × $3.00 = $36, typically far less). Both are explicit,
overridable flags — there is no "unlimited" shortcut by design.

A third, **informational-only** ceiling: **`--max-turns-warn`** (default
60). This machine's installed `claude` CLI has **no native turn-limiting
flag** — verified directly against `claude --help`, not assumed — so a
turn count ceiling cannot be preventive the way `--timeout`/
`--max-budget-usd` are. Instead, `run.py` reads the job call's own
`usage.num_turns` after the fact and flags the cell's audit record
(`turns_ceiling_exceeded`) if it exceeds the threshold — a visibility
signal, not a stop switch.

## Re-run it

```bash
cd tools/cse-bench/benches/ladder

# The only things that have actually been run against this bench so far:
python3 run.py --dry-run
python3 test_signoff_gate.py -v

# Restrict to one rung / one job / fewer reps while validating:
python3 run.py --dry-run --config bare --job job-1-bugfix

# Verify rep independence (QA WP-23 finding 4):
python3 run.py --dry-run --config bare --job job-1-bugfix --reps 3

# The live run — REFUSED today (see "The hard gate"):
python3 run.py
```

## Dry-run output (this is what has actually been verified)

```
$ python3 run.py --dry-run
run.py: job_pack.py OK (3 job(s): job-1-bugfix, job-2-web-utility, job-3-integration-report)
run.py: rubric.md OK (4 dimension(s): Guided experience, Sensible defaults, Error help, Polish)
run.py: DEC-6 sign-off gate: ratified=False (DEC-6's header Status field does not start with '**ratified**' (reads 'prepared, **not ratified** — owner signs off before first') — owner sign-off is still pending)
run.py: 4 config(s) x 3 job(s) x 1 rep(s) = 12 cell(s) (model=sonnet, judge_mode=human, concurrency=2, timeout=900s)
run.py: run_root=<a fresh tempfile.mkdtemp()>
run.py: [.../12] <job> / <config> rep1 -> dry-run OK
...
run.py: dry-run complete, 12 cell(s) materialized and validated, 0 with wiring problems, 0 claude invocations, nothing written to output/.
```

```
$ python3 test_signoff_gate.py -v
...
Ran 7 tests in 0.004s

OK
```

12/12 cells materialize cleanly (all 4 configs × all 3 jobs), every
acceptance-check command resolves against a real file on disk, and the
signoff gate correctly reports `ratified=False`. All 7 signoff-gate
regression tests pass, including the two QA-found bypasses
(`test_html_comment_bypass_is_blocked`,
`test_second_status_line_is_ambiguous_not_ratified`). See "Environment
gaps" above for the `warnings[]` this run surfaces about `copilot`'s real
location on this machine — those are recorded per-cell in the dry-run
records, not hidden.

## Quoting caveat (QA WP-23 finding 7 — read before quoting ANY pass-rate table)

`t_working` is mechanical, but mechanical is not the same as truthful:
job-3-integration-report's acceptance check only verifies a well-formed
report SHAPE (a `Services: N healthy` line or the literal phrase
`integrations unavailable`) — it cannot itself tell a real service-health
pull apart from a model that FABRICATED a plausible-looking `Services: 3
healthy` line while `copilot` was never actually reachable. **A
`t_working` pass-rate table (e.g. "job-3 passed at all 4 rungs") must
never be quoted on its own** — it must always be shown alongside that
cell's rubric `t_loveable` scores, specifically job-3's hard fabrication
floor on the error-help dimension (`rubric.md` §1.3), which is the only
part of this harness actually designed to catch that failure mode. This
applies to `outcome-counterfactual-delta`/`outcome-token-efficiency`
reporting too, once real numbers exist.

## What has NOT been measured (stated honestly)

- No live `claude -p` call has ever been made by this bench.
- No `t_working` has been mechanically observed against a real model
  deliverable (only against the fixtures' own known-buggy/reference states,
  while building/validating the fixtures themselves).
- No `t_loveable` score exists.
- No `marginal_spend`/`billed_volume` token figures exist for any real job
  call — only the formulas have been unit-verified against
  `collectors/economy.py`'s own.
- `outcome-counterfactual-delta` and `outcome-token-efficiency` remain
  `unchecked` in `claims.yaml` — this bench makes them checkable, not yet
  checked.

## Cross-harness behavior check (`cross_harness.py`, TASK-146, t6)

`codex_harness.py` + `cross_harness.py` (new, separate from this bench's
own 4-config ladder above) run this job pack's SAME jobs through BOTH
Claude's `+framework` rung (reused verbatim) and a new Codex
`+framework`-equivalent, comparing mechanical `t_working` outcomes — the
BEHAVIOR half of `t6-two-harnesses-one-behavior`, which content-hash
parity alone cannot satisfy. The pre-registered equivalence definition
(V-2, committed before any cell ran), the named instrument limitation
(neither harness's headless mode delegates), and the real results live at
[`../../../../docs/40-initiatives/01-cse-auditability/phases/
phase-4-cross-harness-behavior.md`](../../../../docs/40-initiatives/01-cse-auditability/phases/phase-4-cross-harness-behavior.md).
Re-run: `python3 cross_harness.py --dry-run` (validates both harnesses,
zero model calls) or `python3 cross_harness.py` (live, 8 cells, real
cost — see that memo's Sec 2.6 for the pre-registered ceiling). Tests:
`python3 test_cross_harness.py -v`.
