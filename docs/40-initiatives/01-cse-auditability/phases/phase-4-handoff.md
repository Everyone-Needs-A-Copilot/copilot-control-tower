# HANDOFF — CSE Verification, Remediation & Outcome Program

> For: the developer taking this program over · Prepared 2026-07-13
> Owner: Pablo Alejo · Working repo: `copilot-control-tower` (branch `main`
> **[Corrected 2026-07-13: was `app-build`, now 18 commits behind `main`;
> check out `main`]**)
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

**The machine layout.** **[Corrected 2026-07-13]** The prior version of this
doc assumed everything lives under `/Volumes/Dev/Sites/COPILOT/` with
`/Users/pabs/Sites` as a symlink to the same tree. That holds on the owner's
*primary* machine only. On the machine this correction was made from,
`/Volumes/Dev` is **not mounted at all** and `/Users/pabs/Sites/COPILOT` is
the real, only tree — not a symlink. Every collector now tries BOTH known
roots and uses whichever exists (`tools/cse-bench/collectors/paths.py`,
`resolve_copilot_root()` / `COPILOT_ROOT_CANDIDATES`); do not assume either
path a priori, and never count both if you ever work across two machines.

| Repo | Branch | What it is |
|---|---|---|
| `copilot-control-tower` | `main` **[Corrected 2026-07-13: was `app-build`, now 18 commits behind `main` — all program work lands on `main`; check out `main`]** | This program's home: `docs/40-initiatives/01-cse-auditability/` + `tools/cse-bench/` |
| `claude-copilot` | `docs/40-initiatives-migration` | Development framework (agents, hooks, `cc`, `tc` in `tools/`) |
| `codex-copilot` | `main` | Same framework, Codex harness (downstream mirror) |
| `knowledge-copilot` | `main` | Knowledge framework (aka shared-docs) |
| `cli-copilot` | `main` **[Corrected 2026-07-13: `feat/r11-r12-soul-remediation` (R-11/R-12, TASK-120/121) merged to `main` this session, commits 21e7c61+4f90d7b; `feat/convoco-launch-readiness` was already merged to `main` earlier (1b90cb7)]** | Integration framework (`copilot` binary) |

**Traps that will waste your day if you skip this:**
- Interactive `copilot` is a **shell alias for `cd`**. Always call binaries by
  absolute path. **[Corrected 2026-07-13]** `/opt/homebrew/bin/copilot` does
  **not exist on this machine** — the integrations collector errors on it
  honestly rather than silently degrading (`tools/cse-bench/output/
  integrations-latest.json`); the real, working dev binary is cli-copilot's
  own venv, `cli-copilot/.venv313/bin/copilot` (verified live via `--help`),
  which is what the W-3 ladder harness's `+integrations` config uses
  explicitly (`benches/ladder/configs.py`). Also use `~/.local/bin/cc`
  (claude-copilot's tool — a *different product*; `/usr/bin/cc` is the C
  compiler).
- cli-copilot's `.venv` is dead. Run everything via
  `uv run --extra dev pytest -q` (and `uv run ruff check .`).
- Cargo builds in control-tower need `CC=/usr/bin/cc PATH=/usr/bin:$PATH`.
- launchd cannot read `/Volumes/Dev` (TCC): the retention installer deploys a
  runtime copy under `~/Library/Application Support/` — re-run
  `tools/cse-bench/retention/install.sh` after editing the retention script.
  **[Corrected 2026-07-13]** On this machine the retention `launchd` service
  is not installed at all (`launchctl print` reports "Could not find
  service") — this is a per-machine install step, not a global fact; run
  `tools/cse-bench/retention/install.sh` here before relying on it.

**Verify your setup (all must pass before you write a line):**

```bash
cd /Users/pabs/Sites/COPILOT/copilot-control-tower   # or /Volumes/Dev/Sites/COPILOT/... on the owner's primary machine — both resolve, see collectors/paths.py
python3 tools/cse-bench/check_claims.py                      # register valid (42 claims, 17 definitions as of 2026-07-13 — was 38/11)
cd tools/cse-bench && python3 cse_bench.py collect           # 12 collectors as of 2026-07-13 (was 9); errors: [] on 11 of them — integrations errors honestly (/opt/homebrew/bin/copilot absent on this machine, see Traps above)
python3 cse_bench.py render && open output/dashboard.html    # 3 component sections + trust ledger
cd benches/knowledge_qa && python3 run.py --dry-run          # bench harness intact
tc progress                                                  # Task Copilot store readable (PRD-9, PRD-10; 23 tasks total as of 2026-07-13 — the store was found empty this session and rebuilt same-day with the original task IDs)
launchctl print gui/$UID/com.copilot.cse.transcript-retention | head -3   # retention alive — NOT installed on this machine as of 2026-07-13 (see Traps above); install it here first if you need it live
```

## 3. What you're inheriting (the system, in one page)

**The measurement stack** (all in `tools/cse-bench/`, all committed):
`claims.yaml` (the pre-registered register — **[Corrected 2026-07-13: 17
definitions, 42 claims, was 11/38]**, the single source of truth for every
quotable number; pre-commit-enforced) →
**collectors** (tasksdb, transcripts, velocity, parity, integrations, evals,
framework_soul, knowledge_soul, cli_soul, economy, solutions, value_density —
12 total as of 2026-07-13, was 9 — each emits the
`cse-bench/1` JSON envelope) → **benches** (knowledge_qa, voice_lint,
mcp_twin, resume_cost, ladder — live model runs with audit trails) →
**render** (the dashboard: ecosystem scoreboard, three component sections
each headed by its SOUL promise, trust ledger).

**Proven and safe to cite** (each with a re-run command in its claim):
knowledge +98pp private-fact accuracy; resume-with-state 100% vs 0% at +3.9%
tokens; voice rules-format beats prose-format; **[Corrected 2026-07-13]**
golden-set evals now cover 6 of 16 agents (qa, me, ta, doc, sd, uxd), each
10/10 (was qa only); CLI conformance now a 138-case test, **135 passing, 3
tracked gaps** (was 125/13), all 3 remaining gaps scoped to the
fireflies/reddit removal candidates (DEC-5); knowledge cross-link integrity
70.99% resolving with the remainder baselined as non-decision content (was
52.5%); knowledge freshness frontmatter 100% coverage (was 0%/1.3%); the
tone-of-voice reference doc itself now passes its own linter at 0.0
violations/100w (was 2.74).

**Falsified — never quote:** "~94% less context" (inverted; **[Corrected
2026-07-13, fresh collect]** agent returns median 893 tokens vs WP content
median 353, n=124/126 — was median 658 vs 217, n=1099 WPs/658 returns; the
old numbers were measured against a since-fixed path-resolution bug that
silently missed this machine's real, smaller tree, not a real corpus
shrinkage — see `collectors/paths.py`); "Sonnet for ~94% of work"; CLI-vs-MCP
token advantage (negative unless usage prose ships); "extensions load
automatically" (now true, but only since `70de3d3`); the 208-command count
(it's 439); protocol-declaration rate (**[Corrected 2026-07-13]** median is
**0.0%** under both the loose and strict definitions on this machine's fresh
collect, not "0.9%" — see the R-3 decision-queue row in §6).

**Read-in-order list** for full context: phase-4 PRD §1 has it. Minimum:
the three SOUL files → `claims.yaml` → phase-4 PRD → phase-3 plan.

## 4. The work, in execution order

Task IDs are live in this repo's Task Copilot (`tc task get <id>`). Done means
**the task's claim flips in `claims.yaml`** — never merely "code exists."

### Wave 1 — the keystone (do first, in order)
| Task | What | Flips | Status (2026-07-13) |
|---|---|---|---|
| **TASK-123 (W-1)** | **Outcome Ledger**: `tc solution` entity + verbs (`create/lock-brief/mark-working/mark-loveable/log-usage/close`) in claude-copilot `tools/tc/`, + `collectors/solutions.py`. Spec: phase-4 PRD §3 W-1. Start tracking the owner's next real solution immediately. | `outcome-ttfls`, `outcome-completeness`, `outcome-survival` → checkable | **completed** |
| **TASK-124 (W-2)** | Per-solution token accounting, two independent methods, tolerance registered first. | `outcome-token-efficiency` → checkable | **completed** |
| **TASK-125 (W-3)** | **Ladder harness** (4 configs × 3-job pack) + MLP rubric — rubric goes to the owner for sign-off BEFORE first scoring. | `outcome-counterfactual-delta` → first number | **blocked** (dry-run validated; live scoring gated on DEC-6 sign-off) |

### Wave 2 — parallel with Wave 1 (no dependencies, all mechanical)
| Task | What | Status (2026-07-13) |
|---|---|---|
| TASK-115 (R-6) | Fix 124 broken knowledge cross-links (28 wrong-depth batch first) + link-check pre-commit in knowledge-copilot | **completed** |
| TASK-116 (R-7) | Freshness frontmatter (`last_updated`+`status`) backfill + pre-commit | **completed** |
| TASK-117 (R-8) | Rewrite `02-tone-of-voice.md` to pass its own linter; convert `cw` extension to distilled-rules format | **completed** |
| TASK-119 (R-10) | Fix contradictory product versions (start: insights-copilot 2.7.0 vs 2.6.0) | **completed** |
| TASK-120 (R-11) | Close the CLI conformance gaps — **scoped by the relevance rule:** skip removal-candidate services (fireflies/reddit/metabase/method) until R-13 is ruled; close the rest (infisical tests, error-hierarchy migration, kept-service env docs) now | **completed** (merged to cli-copilot `main` 2026-07-13) |
| TASK-121 (R-12) | Two residual doc-truth lines in cli-copilot | **completed** (merged to cli-copilot `main` 2026-07-13) |

> **Relevance rule (phase-3 §Sequencing):** never polish surface the removal
> rule may delete. It also scopes R-6 (fix the 28-link batch + actively-read
> files first; orphan-candidate links wait) and C-5 (eval agents that survive
> the W-6 relevance pass, not all 15 blanket).

### Wave 3 — after the first ladder run
| Task | What | Status (2026-07-13) |
|---|---|---|
| TASK-127 (W-5) | Efficiency wave: attack measured waste (agent return sizes, enforcement cost, knowledge format, CLI prose). Every change re-laddered; tokens ↓ with O-1/O-3 flat-or-better, else revert. | **blocked** (plan + staged patches landed, honestly empty merge — nothing yet re-laddered) |
| TASK-128 (W-6) | `collectors/value_density.py` + first removal review → nominations to the owner | **completed** (DEC-8 memo) |
| TASK-126 (W-4) | External pilot: 2–3 non-author users (owner picks recruits), install-as-a-stranger measured, O-7/O-8 collected. **Nothing else can de-confound the data; treat as urgent, not last.** | **blocked** (owner recruits pending) |

### Staged (readiness-gated, run alongside)
| Task | What | Status (2026-07-13) |
|---|---|---|
| TASK-103 (C-3) | Enforcement/observability hook rollout beyond claude-copilot — per-repo readiness checks in claude-copilot `docs/10-architecture/06-hook-deadlock-root-cause-2026-07.md`. The deadlock fix is proven (`77f5cdb0`); do not roll out the pre-fix hook anywhere. | **blocked** |
| TASK-105 (C-5) | Golden-set evals for the next agents (me, ta, doc, sd, uxd), each baselined before merge | **completed** (all 5 landed at 10/10; agent-eval-coverage is now 6/16, see claims.yaml) |
| TASK-100 (B-17) | Delete-or-defend list per product, fed by W-6 nominations | **blocked** (deliverable: DEC-9, the consolidated per-product delete-or-defend list; DEC-8, the W-6 first-removal-review memo, also cites TASK-100 in its own header as the decision-queue task it feeds — a QA nit flagged that DEC-8 referenced TASK-100 before TASK-100's `blocked` status had actually landed in the Task Copilot store; both are now consistent) |

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
| 1 | R-1 (TASK-112): enforce the ~100-token agent-return bar vs amend the SOUL bar | `framework_soul-latest.json` distribution — **[Corrected 2026-07-13, fresh collect]** median 893, p90 3,474, 95.97% >300 (was median 658, p90 2,749, 86.2% >300 — worse, not better; see `framework-agent-frugality` in claims.yaml) |
| 2 | R-3 (TASK-113): protocol at **0.0%** — enforce, simplify, or retire **[Corrected 2026-07-13: was stated as "0.9%"; a fresh transcripts collect shows the median is 0.0% under BOTH the loose and strict protocol-declaration definitions]** | decision memo (task deliverable) |
| 3 | R-5 (TASK-114): ratify the SOUL §3 correction (falsified ~94%, now measured at -153%, i.e. further inverted — see `framework-externalization-94pct`) | framework_soul verdict; README already corrected (`7274e6b`) |
| 4 | R-9 (TASK-118) deletions: stale clones `conversations-copilot`, `shared-docs` dirs; registry gaps (copilot-control-tower absent, knowledge-copilot's own path missing) | knowledge_soul registry block — **[Corrected 2026-07-13]** the registry_integrity metric itself had a path-prefix bug (silently vacuous 0/0 forward check, over-flagged reverse check) fixed this session; honest post-fix numbers are in `knowledge-registry-completeness` (claims.yaml) |
| 5 | R-13 (TASK-122) / B-17: configure-or-cut fireflies, reddit, metabase, method; then each W-6 nomination | cli_soul + usage ledger + value_density — **[Corrected 2026-07-13]** cli-copilot's conformance scorecard is now 135/138 (was 125/138); the 3 remaining gaps are entirely fireflies/reddit, i.e. exactly what this decision is about |
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
python3 codex-copilot/scripts/check-upstream-parity.py --content --json   # path is relative to whichever COPILOT root resolves on your machine — see collectors/paths.py
# Agent evals — [Corrected 2026-07-13] 6 agents now have a golden set, not just qa
~/.local/bin/cc eval --agent qa --json         # run from claude-copilot; also: --agent me|ta|doc|sd|uxd
```

Key documents (this directory unless noted): `phase-4-outcome-program-prd.md`
(the program) · `phase-3-soul-remediation.md` (hygiene) · `../claims.yaml` (the
law) · `phase-1-findings.md` + `phase-1-reaudit-report.html` (how we got here)
· the three SOUL files (each component's promise).
