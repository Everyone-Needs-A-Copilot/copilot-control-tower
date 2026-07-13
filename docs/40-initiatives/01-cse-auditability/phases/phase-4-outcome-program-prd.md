# PRD — The Outcome Program

> Initiative: `01-cse-auditability` · Phase 4 · Prepared 2026-07-13
> **This is a handoff document.** A developer new to this program should be able
> to read this file, follow its pointers, and finish the work without
> reassessing what has already been done. Everything here is grounded in
> committed, pushed artifacts — no tribal knowledge required.

---

## 0. Ratified decisions (owner, 2026-07-12 → 2026-07-13)

These are settled. Do not re-litigate them; build on them.

1. **The one goal.** The entire ecosystem exists *"to support people in creating
   solutions they love; quickly, efficiently, and intuitively."* Every feature,
   measurement, and component is judged against this and nothing else.
2. **The components are exactly three.** (1) **Development framework** =
   Claude Copilot & Codex Copilot — one framework, two harnesses, containing
   Task Copilot, Memory Copilot, and the specialized agents. (2) **Knowledge
   framework** = Knowledge Copilot. (3) **Integration framework** = CLI
   Copilot. Control Tower orchestrates them. Never compare Claude vs Codex
   Copilot as a measurement (parity checking is sync plumbing only). Never
   present "voice" or "Task Copilot" as components.
3. **Components are measured against their own SOULs** for conformance
   (claude-copilot/SOUL.md, knowledge-copilot/SOUL.md, cli-copilot/SOUL.md) —
   AND against the ratified **outcome bars** (§2) for value. SOUL conformance
   is the floor; outcome bars are the goal. The claude-copilot SOUL forbids
   speed/quality claims for that component — those questions belong to the
   ecosystem-level ladder test only.
4. **Performance is the objective; efficiency is the constraint.** Loveable
   solutions, created quickly, come first. Token efficiency is pushed as high
   as possible — **aspiration 90% reduction vs bare harness, 60% is the
   "we have work to do" line** — but never traded against MLP speed/quality.
   When they conflict, performance wins and the efficiency shortfall is
   reported honestly.
5. **The removal rule.** Anything in the CSE that does not move an outcome bar
   within its review window is a removal candidate. A smaller, fully-alive
   ecosystem beats a sprawling 20%-alive one. Removal decisions are
   owner-gated; nominations are mechanical.
6. **Pre-registration is law (V-2).** No metric is quoted without a register
   entry in [`../claims.yaml`](../claims.yaml). Definitions are written before
   results are looked at. The pre-commit hook enforces register validity.
7. **No time estimates anywhere.** Phases, priorities, dependencies,
   complexity only.

---

## 1. Context a new developer needs (read in this order)

| # | Read | Why |
|---|---|---|
| 1 | `docs/10-reference/copilot-solutioning-ecosystem.md` | The canonical CSE model (components × Foundation→Org→Dept→Personal layers). |
| 2 | The three SOUL files (paths in §0.3) | Each component's ratified promise — the conformance floor. |
| 3 | `phases/phase-1-findings.md` + `phases/phase-1-reaudit-report.html` | What was claimed, what was falsified, what was corrected. The report also renders at the team's artifact link. |
| 4 | `../claims.yaml` | THE register: 30 claims + 10 definitions, statuses live. |
| 5 | `phases/phase-2-prd.md` (incl. §2.5) | The verification program: T1–T8 truth conditions, B/C/S task series. |
| 6 | `phases/phase-3-soul-remediation.md` | The gap→fix plan (R-series), what's mechanical vs owner-gated. |
| 7 | `tools/cse-bench/README.md` | The measurement harness: collectors, benches, render. |
| 8 | This file | The outcome program you are building. |

**State of the world (2026-07-13, all pushed):**

- **Instruments live:** transcript retention LaunchAgent (archive at
  `~/.claude/transcript-archive/`); claims register + pre-commit checker; 9
  collectors + 4 benches under `tools/cse-bench/`; dashboard
  (`python3 cse_bench.py render` → `output/dashboard.html`, 3 component
  sections headed by SOUL promises + trust ledger).
- **Capabilities built:** CLI usage ledger (`COPILOT_USAGE_LOG=1`, ratified
  SOUL exception) + 22-group health (cli-copilot `bed13a45`, `0ee36e3`);
  knowledge extension loader + glossary fix (knowledge-copilot `08a2d249`,
  claude-copilot `70de3d3`); deadlock-free enforcement, proven in
  claude-copilot only (`77f5cdb0` — rollout staged, see R-2); Codex
  content-hash parity (codex-copilot `740aa10`); CLI SOUL-conformance test
  suite, 125/138 with 13 tracked gaps (`0ee36e3`).
- **Falsifications recorded (do not re-quote the dead numbers):**
  "~94% less context" is inverted (struck from README `7274e6b`; SOUL §3
  correction awaits owner ratification — R-5); CLI-vs-MCP token advantage is
  negative unless usage prose ships with the CLI; knowledge never-read is
  67–88% definition-dependent; CLI terminal usage was ~12 invocations in 1.5y.
- **Proven mechanisms (safe to cite, with their checks):** knowledge
  private-fact accuracy +98pp (`bench_knowledge_qa`); resume with persisted
  state 100% vs 0% at +3.9% tokens (`bench_resume_cost`); voice rules-format
  beats prose-format (`bench_voice_lint`); qa agent eval 10/10 (`evals`).
- **Task Copilot:** this repo's `tc` store, PRD-9 = the verification program.
  Pending queues: R-series (phase 3), C-3/C-5, B-13/B-14/B-17.
- **Environment traps:** interactive `copilot` is a shell alias (`cd`); use
  absolute binaries (`/opt/homebrew/bin/copilot`, `~/.local/bin/cc`).
  `cc` also names the C compiler — cargo builds in this repo need
  `CC=/usr/bin/cc PATH=/usr/bin:$PATH`. cli-copilot tests run via
  `uv run --extra dev pytest -q` (the local venv is dead).
  `/Users/pabs/Sites` symlinks to `/Volumes/Dev/Sites` — never double-count.

---

## 2. The ratified outcome bars (the definition of success)

The unit of value is a **Solution**: a completed artifact that resolves a real
person's real problem. Not a task, not a commit, not a demo.

| # | Bar | Definition | Proves |
|---|---|---|---|
| **O-1** | **Time-to-First-Loveable-Solution (TTFLS)** | TWO timestamps per solution: `t_working` (does the job) and `t_loveable` (meets the person's expectations — intuitive, guided, delightful; MLP not MVP). Measured from first prompt. | The ecosystem pays off fast — and the `t_loveable − t_working` gap isolates the measurable value of the design chain (sd/uxd/uids). |
| **O-2** | **Solution Completeness** | Against a **brief locked at the start** (the intent contract): sessions-to-done, tokens-to-done, and post-ship **fix-vs-feature ratio** over a defined window. "Done" = matches the locked brief, and post-ship activity is dominated by new capability, not repairs. | Solutions are actually finished and exactly what was wanted — no goalpost drift, no perpetual repair. |
| **O-3** | **Speed** | Elapsed time, first prompt → finished (loveable) solution, vs the counterfactual (same job, bare harness). | The ecosystem is faster to a *final* solution, not just busier. |
| **O-4** | **Token Efficiency** | Total tokens, first prompt → finished solution, vs bare-harness counterfactual. **Constraint, not objective**: push toward 90% reduction; below 60% = "we have work to do"; never trade O-1/O-3 for it. Mechanism note: savings come from avoided waste (wrong directions, re-explaining, rework), not cheaper steps — measure accordingly. | Limits and cost: the ecosystem multiplies what a person can do within real token budgets. |
| **O-5** | **Solution Survival** | Of solutions *started*: % shipped. Of shipped: % still in active use N weeks later. Sustained use is the primary loveability evidence (stronger than any survey, immune to author enthusiasm). | We count the graveyard; what people keep using, they love. |
| **O-6** | **Counterfactual Delta (the ladder)** | Same job pack run at 4 configs — bare → +development framework → +knowledge → +integrations — scored on O-1..O-4. | Each component's causal contribution; feeds the removal rule. |
| **O-7** | **Voluntary Return Rate** | After a first solution, does the person choose the CSE for the next problem, unprompted? | The metric enthusiasm can't fake. |
| **O-8** | **Transfer Coefficient** | O-1..O-5 achieved by people who are NOT the author, unassisted, within a stated tolerance of the owner's numbers. Requires ≥2 external users. | It's a product, not a personal toolkit. |
| **O-9** | **Upkeep Tax** | Time + tokens spent maintaining the CSE itself (registry, links, freshness, parity sweeps, claim upkeep) per unit period. Net value = outcomes − upkeep. | We don't overstate value to ourselves or to adopting organizations. |

**The removal rule, operationalized:** every agent, service, command group,
knowledge area, and skill must be traceable to an outcome bar it moves. Each
review cycle, the collectors nominate the bottom slice (no usage signal AND no
outcome trace) to the owner's delete-or-defend queue (B-17). Nominations are
mechanical; deletions are the owner's.

---

## 3. What to build (workstreams)

> Register every workstream's tasks in `tc` under this PRD. Done = the
> relevant claim flips in `claims.yaml` (the outcome claims are pre-registered
> as `gated`; your job is to make them checkable, then checked).

### W-1 · The Outcome Ledger (the keystone — everything else consumes it)
Solutions become first-class records. Extend Task Copilot (`tc`, lives in
claude-copilot `tools/tc/`) with a `solution` entity:
`{id, title, brief_lock (text + locked_at), beneficiary, started_at,
t_working, t_loveable, status (in_progress|shipped|abandoned|in_use|retired),
sessions_count, tokens_total, post_ship: {fixes, features, window_days},
components_used: [framework|knowledge|integration], repo/path}`.
- CLI verbs: `tc solution create/lock-brief/mark-working/mark-loveable/
  log-usage/close` — additive, following tc's existing Typer/SQLite patterns.
- A `cse-bench` collector `solutions.py` emitting O-1/O-2/O-3(observed)/O-5
  from the ledger.
- **Acceptance:** the owner's next real solution is tracked end-to-end; the
  dashboard's scoreboard strip reads from it; claims `outcome-ttfls`,
  `outcome-completeness`, `outcome-survival` flip from gated→checkable.
- Boundary: this is instructions + local CLI — passes claude-copilot's SOUL
  Gate 1. No daemon, no cloud.

### W-2 · Token & session joins (make O-2/O-4 exact instead of approximate)
- Per-solution token accounting: join transcript usage to solutions via
  repo+time+session ids captured by the ledger (`tc solution` records the
  session id when invoked inside one; the PostToolUse event ledger from C-3
  makes this exact in every wired repo).
- Extend `collectors/transcripts.py` (or a new `collectors/economy.py`) to
  emit tokens-per-solution and waste decomposition (re-explaining, rework,
  failed-direction tokens — classify by session structure; document the
  heuristics in the register first).
- **Acceptance:** for one completed solution, tokens_total is computed two
  independent ways (ledger vs transcripts) and agrees within a stated
  tolerance recorded in the register.

### W-3 · The Ladder Harness (B-13, now with the ratified bars)
- `tools/cse-bench/benches/ladder/`: run one **job pack** at the 4 configs.
  Config isolation: bare = fresh dir, no framework files; +framework =
  claude-copilot install; +knowledge = `CC_KNOWLEDGE_REPO` populated vs empty
  tree; +integrations = cli-copilot on PATH with `.env`.
- Job pack v1: 3 real software jobs of graduated size drawn from actual
  ecosystem needs (candidates: an R-series fix implemented 4 ways; a small
  web utility; a data-pull-and-report task that exercises integrations).
  Pack format is pluggable — the accountant pack comes later, same harness.
- Scoring: O-3/O-4 mechanical; O-1 `t_working` mechanical (acceptance tests
  per job); `t_loveable` scored against a written expectation rubric locked
  with the pack (MLP rubric: guided experience, sensible defaults, error
  help, polish — judged blind, exemplar-anchored, deterministic checks
  where possible).
- **Acceptance:** one full ladder run produces per-config O-1..O-4 with raw
  artifacts preserved; claims `outcome-counterfactual-delta` and
  `outcome-token-efficiency` get their first honest numbers (whatever they
  are — a bad number is a finding, not a failure).

### W-4 · External pilot (B-14 — unblocks O-7/O-8; nothing fakes this)
- Recruit 2–3 non-author users (at least one non-developer for the intuitive
  bar). Give them the install path a stranger would get (that experience is
  itself measured — TTFLS starts at install).
- They run: onboarding → one real solution of their own → (optionally) the
  ladder job pack. Collect O-1..O-5, O-7, O-8. Author may not assist beyond
  the shipped docs; every assist is logged as a product defect.
- **Acceptance:** a pilot report per user; transfer coefficient computed;
  the single-author caveat comes off every dashboard panel fed by pilot data.

### W-5 · Efficiency program (serve O-4 without hurting O-1/O-3)
- Attack the measured waste, in order of evidence: agent return sizes
  (median 658 vs ~100 bar — R-1, owner picks enforce-vs-amend), enforcement
  context cost (pays once, never per-turn — SOUL rule), knowledge delivery
  format (distilled rules, not prose — R-8), CLI grammar prose shipped to
  agents (the MCP-twin fix).
- Every efficiency change must show: tokens ↓ AND O-1/O-3 flat-or-better on
  the ladder re-run. A change that saves tokens but slows loveable delivery
  is reverted per ratified decision §0.4.
- **Acceptance:** ladder re-run after the wave shows the O-4 trend line
  moving toward the 60%→90% band with O-1/O-3 non-degraded.

### W-6 · Removal reviews (operate the rule)
- A `collectors/value_density.py` that traces each agent / service group /
  knowledge area / skill to outcome-bar movement + usage signals, and emits
  the bottom-slice nomination list.
- Wire nominations into B-17's delete-or-defend doc for the owner. First
  candidates already known: 13 dead CLI services' surface, unread knowledge
  areas, 15 uneval'd agents (evaluate or justify), orphan configs
  (metabase/method).
- **Acceptance:** first review executed; at least one owner ruling recorded;
  removed surface reflected in the conformance/coverage denominators.

### W-7 · Hygiene floor (already planned — keep it running underneath)
- R-series per `phase-3-soul-remediation.md` (mechanical wave R-6/7/8/10/11/12
  is unblocked); staged R-2 (enforcement rollout) and R-4/C-5 (evals).
- These keep SOUL-conformance green while W-1..W-6 build the outcome layer.
  They are the floor, not the goal — do not let them crowd out W-1/W-3.

**Dependency order:** W-1 → W-2 → W-3 → W-5 (re-run) — while W-4 recruits in
parallel and W-6/W-7 run continuously. W-3 can do a first run with manual
O-1/O-2 capture before W-1 lands if sequencing demands, but the ledger is the
priority.

## 4. Owner-decision queue (do not build past these; ask)

| Decision | Context |
|---|---|
| R-1 direction | Enforce the ~100-token agent return bar vs amend it with evidence (`framework_soul` distribution attached). |
| R-3 direction | Protocol at 0.9% adoption: enforce, simplify, or retire — decision memo first. |
| R-5 ratification | SOUL §3 correction replacing the falsified ~94% figure. |
| R-9 / R-13 / B-17 | All deletions: stale clones, dead services, claim/product removals — mechanical nominations, owner rulings. |
| W-4 recruits | Who the 2–3 external pilots are. |
| Loveability rubric | The MLP expectation rubric (W-3) needs owner sign-off before first scoring — it operationalizes his bar. |

## 5. Operating rules for the developer

1. **Register first.** New metric → definition in `claims.yaml` BEFORE looking
   at data; new claim → entry with check/status/evidence. `python3
   tools/cse-bench/check_claims.py` must pass (pre-commit enforces).
2. **Done = claim flip.** A task is finished when its claim's `check` runs and
   the status honestly changes — never when code merely exists.
3. **SOUL gates per repo.** Run any product change through that repo's SOUL
   feature filter. Additive, tested, scoped commits; co-author line
   `Co-Authored-By:` your model; push the working branch.
4. **Honesty style.** Null and negative results are findings; report them
   plainly. Never quote a struck number. Single-author data carries its caveat
   until W-4 lands.
5. **Envelope contract.** Every collector/bench emits
   `{schema_version:"cse-bench/1", collector, generated_at, host_scope,
   metrics, errors}` to `tools/cse-bench/output/` with a `-latest.json`
   pointer; the dashboard consumes only that contract.
6. **Verify before declaring.** Each bench/collector ships with its re-run
   command in its README and in the claim's `check` field.
7. **Use `tc`.** Tasks live under this PRD in `.copilot/tasks.db`; statuses
   maintained as you go; work products stored, ~100-token summaries returned.

## 6. Program acceptance (when is Phase 4 done)

1. The Outcome Ledger tracks real solutions end-to-end (W-1, W-2).
2. One full ladder run has produced honest O-1..O-4 numbers (W-3).
3. At least two external pilots have generated O-7/O-8 data (W-4).
4. The efficiency trend is measured against the 60%→90% band with performance
   non-degraded — wherever it lands (W-5).
5. The first removal review has executed with owner rulings (W-6).
6. All nine outcome claims in the register are `passing`, `failing`, or
   retired-by-ratification — none left `gated`.

At that point the question this initiative was born from — *"how do I prove
any of this is useful?"* — has an evidence-backed answer, whatever it is.
