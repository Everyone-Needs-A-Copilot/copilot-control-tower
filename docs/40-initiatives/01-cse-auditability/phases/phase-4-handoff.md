# HANDOFF — CSE Verification, Remediation & Outcome Program

> For: the developer taking this program over · Prepared 2026-07-13
> Owner: Pablo Alejo · Working repo: `copilot-control-tower` (branch `app-build`)
> **You should be able to finish everything from this document alone.** Every
> claim here is backed by a committed artifact; nothing lives in anyone's head.

---

## 1. The mission (ratified, not negotiable)

The Copilot Solutioning Ecosystem (CSE) has **one goal**: *support people in
creating solutions they love — quickly, efficiently, and intuitively.*

Your job has three strands, in this priority order:

1. **Build the outcome instrumentation** that proves (or refutes) that goal —
   the Outcome Ledger, the token joins, the 4-config ladder test, the external
   pilot. This is the main event ([`phase-4-outcome-program-prd.md`](phase-4-outcome-program-prd.md)).
2. **Keep the hygiene floor green** — the SOUL-conformance remediation
   ([`phase-3-soul-remediation.md`](phase-3-soul-remediation.md)).
3. **Feed the owner's decision queue** — several fixes are decisions, not
   work; your job is to make each decision one-click (evidence attached),
   never to make it for him. (§6)

Two rules override everything else:
- **Performance over efficiency.** Loveable solutions, fast, is the objective;
  token efficiency is a constraint pushed as hard as possible (aspiration 90%
  reduction vs bare harness, 60% floor) but *never* at performance's expense.
- **The removal rule.** Surface that moves no outcome bar in its review window
  gets mechanically nominated for deletion. Deletions are the owner's call.

## 2. Day one — setup and self-verification

**The machine layout.** Everything lives under `/Volumes/Dev/Sites/COPILOT/`
(note: `/Users/pabs/Sites` is a symlink to the same tree — never count both):

| Repo | Branch | What it is |
|---|---|---|
| `copilot-control-tower` | `app-build` | This program's home: `docs/40-initiatives/01-cse-auditability/` + `tools/cse-bench/` |
| `claude-copilot` | `docs/40-initiatives-migration` | Development framework (agents, hooks, `cc`, `tc` in `tools/`) |
| `codex-copilot` | `main` | Same framework, Codex harness (downstream mirror) |
| `knowledge-copilot` | `main` | Knowledge framework (aka shared-docs) |
| `cli-copilot` | `feat/convoco-launch-readiness` | Integration framework (`copilot` binary) |

**Traps that will waste your day if you skip this:**
- Interactive `copilot` is a **shell alias for `cd`**. Always call binaries by
  absolute path: `/opt/homebrew/bin/copilot` (CLI Copilot, an editable pip
  install of the repo) and `~/.local/bin/cc` (claude-copilot's tool — a
  *different product*; and `/usr/bin/cc` is the C compiler).
- cli-copilot's `.venv` is dead. Run everything via
  `uv run --extra dev pytest -q` (and `uv run ruff check .`).
- Cargo builds in control-tower need `CC=/usr/bin/cc PATH=/usr/bin:$PATH`.
- launchd cannot read `/Volumes/Dev` (TCC): the retention installer deploys a
  runtime copy under `~/Library/Application Support/` — re-run
  `tools/cse-bench/retention/install.sh` after editing the retention script.

**Verify your setup (all must pass before you write a line):**

```bash
cd /Volumes/Dev/Sites/COPILOT/copilot-control-tower
python3 tools/cse-bench/check_claims.py                      # register valid (38 claims)
cd tools/cse-bench && python3 cse_bench.py collect           # 9 collectors, errors: []
python3 cse_bench.py render && open output/dashboard.html    # 3 component sections + trust ledger
cd benches/knowledge_qa && python3 run.py --dry-run          # bench harness intact
tc progress                                                  # Task Copilot store readable (PRD-9, PRD-10)
launchctl print gui/$UID/com.copilot.cse.transcript-retention | head -3   # retention alive
```

## 3. What you're inheriting (the system, in one page)

**The measurement stack** (all in `tools/cse-bench/`, all committed):
`claims.yaml` (the pre-registered register — 11 definitions, 38 claims, the
single source of truth for every quotable number; pre-commit-enforced) →
**collectors** (tasksdb, transcripts, velocity, parity, integrations, evals,
framework_soul, knowledge_soul, cli_soul — each emits the
`cse-bench/1` JSON envelope) → **benches** (knowledge_qa, voice_lint,
mcp_twin, resume_cost — live model runs with audit trails) → **render**
(the dashboard: ecosystem scoreboard, three component sections each headed by
its SOUL promise, trust ledger).

**Proven and safe to cite** (each with a re-run command in its claim):
knowledge +98pp private-fact accuracy; resume-with-state 100% vs 0% at +3.9%
tokens; voice rules-format beats prose-format; qa eval 10/10; CLI conformance
now a 138-case test (125 passing, 13 tracked gaps).

**Falsified — never quote:** "~94% less context" (inverted: agent returns
median 658 tokens vs WP median 217); "Sonnet for ~94% of work"; CLI-vs-MCP
token advantage (negative unless usage prose ships); "extensions load
automatically" (now true, but only since `70de3d3`); the 208-command count
(it's 439).

**Read-in-order list** for full context: phase-4 PRD §1 has it. Minimum:
the three SOUL files → `claims.yaml` → phase-4 PRD → phase-3 plan.

## 4. The work, in execution order

Task IDs are live in this repo's Task Copilot (`tc task get <id>`). Done means
**the task's claim flips in `claims.yaml`** — never merely "code exists."

### Wave 1 — the keystone (do first, in order)
| Task | What | Flips |
|---|---|---|
| **TASK-123 (W-1)** | **Outcome Ledger**: `tc solution` entity + verbs (`create/lock-brief/mark-working/mark-loveable/log-usage/close`) in claude-copilot `tools/tc/`, + `collectors/solutions.py`. Spec: phase-4 PRD §3 W-1. Start tracking the owner's next real solution immediately. | `outcome-ttfls`, `outcome-completeness`, `outcome-survival` → checkable |
| **TASK-124 (W-2)** | Per-solution token accounting, two independent methods, tolerance registered first. | `outcome-token-efficiency` → checkable |
| **TASK-125 (W-3)** | **Ladder harness** (4 configs × 3-job pack) + MLP rubric — rubric goes to the owner for sign-off BEFORE first scoring. | `outcome-counterfactual-delta` → first number |

### Wave 2 — parallel with Wave 1 (no dependencies, all mechanical)
| Task | What |
|---|---|
| TASK-115 (R-6) | Fix 124 broken knowledge cross-links (28 wrong-depth batch first) + link-check pre-commit in knowledge-copilot |
| TASK-116 (R-7) | Freshness frontmatter (`last_updated`+`status`) backfill + pre-commit |
| TASK-117 (R-8) | Rewrite `02-tone-of-voice.md` to pass its own linter; convert `cw` extension to distilled-rules format |
| TASK-119 (R-10) | Fix contradictory product versions (start: insights-copilot 2.7.0 vs 2.6.0) |
| TASK-120 (R-11) | Close the 13 CLI conformance gaps → suite reads 138/138 |
| TASK-121 (R-12) | Two residual doc-truth lines in cli-copilot |

### Wave 3 — after the first ladder run
| Task | What |
|---|---|
| TASK-127 (W-5) | Efficiency wave: attack measured waste (agent return sizes, enforcement cost, knowledge format, CLI prose). Every change re-laddered; tokens ↓ with O-1/O-3 flat-or-better, else revert. |
| TASK-128 (W-6) | `collectors/value_density.py` + first removal review → nominations to the owner |
| TASK-126 (W-4) | External pilot: 2–3 non-author users (owner picks recruits), install-as-a-stranger measured, O-7/O-8 collected. **Nothing else can de-confound the data; treat as urgent, not last.** |

### Staged (readiness-gated, run alongside)
| Task | What |
|---|---|
| TASK-103 (C-3) | Enforcement/observability hook rollout beyond claude-copilot — per-repo readiness checks in claude-copilot `docs/10-architecture/06-hook-deadlock-root-cause-2026-07.md`. The deadlock fix is proven (`77f5cdb0`); do not roll out the pre-fix hook anywhere. |
| TASK-105 (C-5) | Golden-set evals for the next agents (me, ta, doc, sd, uxd), each baselined before merge |
| TASK-100 (B-17) | Delete-or-defend list per product, fed by W-6 nominations |

(TASK-95/96/97 are cancelled as superseded — don't resurrect them.)

## 5. How to work (non-negotiable operating rules)

1. **Register first (V-2).** Definition into `claims.yaml` before you look at
   data; claim entry before you quote a number. The pre-commit hook blocks
   invalid registers; corrections are new commits, never silent rewrites.
2. **Done = claim flip.** Every task ends with its `check` command passing and
   the status honestly updated (`last_checked` bumped).
3. **SOUL gates.** Any product change runs through that repo's SOUL feature
   filter before implementation. Additive, tested, scoped commits. Commit
   messages end with your model's `Co-Authored-By:` line. Push the branch you
   found checked out.
4. **Honesty style.** Negative results are findings — report them plainly, no
   silver linings. Single-author data carries its caveat until W-4 lands. No
   time estimates anywhere (phases/priority/complexity only).
5. **Envelope contract.** Collectors/benches emit
   `{schema_version:"cse-bench/1", collector, generated_at, host_scope,
   metrics, errors}` + a `-latest.json` pointer; the dashboard consumes only
   that. Raw bench responses are saved under `output/` for audit.
6. **Use Task Copilot.** Statuses maintained as you go (`tc task update <id>
   --status in_progress|completed`); work products stored via `tc wp`; the
   owner reads `tc progress`.
7. **The owner communicates via Discord** when away — the bridge hooks handle
   it; an active handoff thread exists ("CSE benchmark program", started
   2026-07-12). Post major milestones there; questions that block you go there
   too.

## 6. The owner's decision queue (make one-click; never decide for him)

| # | Decision | Evidence to attach |
|---|---|---|
| 1 | R-1 (TASK-112): enforce the ~100-token agent-return bar vs amend the SOUL bar | `framework_soul-latest.json` distribution (median 658, p90 2,749, 86.2% >300) |
| 2 | R-3 (TASK-113): protocol at 0.9% — enforce, simplify, or retire | decision memo (task deliverable) |
| 3 | R-5 (TASK-114): ratify the SOUL §3 correction (falsified ~94%) | framework_soul verdict; README already corrected (`7274e6b`) |
| 4 | R-9 (TASK-118) deletions: stale clones `conversations-copilot`, `shared-docs` dirs | knowledge_soul registry block |
| 5 | R-13 (TASK-122) / B-17: configure-or-cut fireflies, reddit, metabase, method; then each W-6 nomination | cli_soul + usage ledger + value_density |
| 6 | W-3 MLP rubric sign-off; W-4 pilot recruits | rubric draft; candidate list |

## 7. Definition of done for this engagement

From phase-4 PRD §6, verbatim in spirit: the Outcome Ledger tracks real
solutions end-to-end; one full ladder run has produced honest O-1..O-4
numbers; ≥2 external pilots have generated O-7/O-8 data; the efficiency trend
is measured against the 60→90% band with performance non-degraded; the first
removal review has owner rulings; **all nine outcome claims are passing,
failing, or retired — none gated.** Plus: the hygiene floor (R-series) green,
and the decision queue empty or escalated.

When that's true, the owner's founding question — *"how do I prove any of
this is useful?"* — has an evidence-backed answer either way, and the CSE is
ready to be handed to another organization with a straight face.

## 8. Quick reference

```bash
# The register (the law)
python3 tools/cse-bench/check_claims.py
# Refresh all metrics + dashboard
cd tools/cse-bench && python3 cse_bench.py collect && python3 cse_bench.py render
# Benches (each README has details)
python3 benches/knowledge_qa/run.py            # +98pp knowledge ablation
python3 benches/voice_lint/run.py              # 3-arm voice conformance
python3 benches/resume_cost/run.py             # resume value (run build_state.sh first)
python3 benches/mcp_twin/run.py                # CLI-vs-MCP economics
# CLI conformance scorecard (in cli-copilot)
CC=/usr/bin/cc PATH=/usr/bin:$PATH uv run --extra dev pytest tests/test_soul_conformance.py -v --tb=no -rxX
# Codex parity (sync plumbing, not a measurement)
python3 /Volumes/Dev/Sites/COPILOT/codex-copilot/scripts/check-upstream-parity.py --content --json
# Agent evals
~/.local/bin/cc eval --agent qa --json         # run from claude-copilot
```

Key documents (this directory unless noted): `phase-4-outcome-program-prd.md`
(the program) · `phase-3-soul-remediation.md` (hygiene) · `../claims.yaml` (the
law) · `phase-1-findings.md` + `phase-1-reaudit-report.html` (how we got here)
· the three SOUL files (each component's promise).
