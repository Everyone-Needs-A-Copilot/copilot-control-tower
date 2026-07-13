# PRD — CSE Verification & Benchmark Program (Phase 2)

> Initiative: `01-cse-auditability` · Prepared: 2026-07-12
> Basis: [`phase-1-findings.md`](phase-1-findings.md) + [`phase-1-reaudit-report.html`](phase-1-reaudit-report.html)
> Owner intent: *"I want to be able to prove that this thing actually works, so I need it
> working for me so I can take the benefit of it and improve how we use it, and share it
> with other organizations so they can get the benefit of it."*

## 1. Context

Phase 1 falsified most of the CSE's headline claims; the 2026-07-12 adversarial re-audit
upheld that result (13/18 findings), corrected two numbers (F-11, F-16), and overturned the
one verdict that blocked progress (F-12 — knowledge efficacy IS benchmarkable). The
re-audit also found that the raw material for a credible benchmark mostly already exists:
Task Copilot stores back to 2026-03, Codex telemetry back to 2025-11, a live
`copilot health` verb, an eval harness seed (`cc eval`), and an uncompiled voice rubric.

This PRD converts that evidence into a program: make the CSE **observable**, then
**measured**, then **provably valuable**, with a web-view benchmark app rendering it all.

## 2. What must be true for the CSE to live up to its vision

These eight truth conditions are the program's definition of success. Every workstream
below exists to make one or more of them true; anything that serves none of them is out
of scope.

| # | Truth condition | Today (from the audits) |
|---|---|---|
| **T1** | **The ecosystem can see itself.** Every component leaves durable, queryable usage evidence as a side effect of normal work — transcripts retained, tool events logged at source, CLI invocations recorded (opt-in). | Corpus self-deletes (113→108 sessions in ~24h); CLI records nothing; Codex data exists but is unparsed. |
| **T2** | **No claim outlives its check.** Every public claim in CSE docs maps to a pre-registered, runnable check; unverifiable claims are deleted. The F-18 "artifact without mechanism" count is zero, enforced on commit. | 7+4 known artifact-without-mechanism instances; definitions chosen after seeing data (V-2 violated). |
| **T3** | **The instruction layer demonstrably changes behavior.** Enforcement fires where the docs say it does (or the docs stop saying it); delegation/protocol adoption measured at source; every specialist agent has a passing golden-set eval. | Enforcement wired in 1 of ~26 repos, Bash-only; protocol rate 0.9%; evals exist for 1 of 16 agents. |
| **T4** | **The knowledge layer demonstrably changes output.** With-knowledge beats without on private-fact accuracy; voice conformance shows a delta attributable to the repo rather than to prompting. | Never measured (was wrongly declared unmeasurable); ~67% of knowledge never read. |
| **T5** | **The integration layer pays its way, and the surface matches reality.** Live integrations authenticate; retained commands show usage; dead surface is pruned or revived; the CLI-vs-MCP advantage is measured and honestly bounded. | ~23% of 439 commands plausibly alive; 14 terminal invocations in 1.47y; stated email/calendar/Slack mission has no first-class implementation. |
| **T6** | **Two harnesses, one behavior.** Claude/Codex parity is checked at content and behavior level; drift is bounded and alarmed. "Same solution, different harness" is a tested property, not a slogan. | Parity check covers 3 version strings only; 8× content compression unverified; ~15% commit velocity. |
| **T7** | **The inheritance ladder exists in practice.** At least one real Foundation→Org→Personal chain syncs through Control Tower, entitlement by repo access, secrets outside git. | Single-tier, single-machine today. Delivered by the Control Tower build program ([PRD](../../../02-prd/prd.md)); tracked here as a dependency and verified by this program's trust panel. |
| **T8** | **The value transfers beyond its author.** A person who is not the owner, using a persona task pack (the accountant story), completes representative tasks measurably better with the CSE than without. | Every number in existence is single-author. |

## 2.5 SOUL-alignment revision (2026-07-12, owner-directed)

Each component is measured against **its own ratified SOUL promise** — not against
generic "faster/cheaper/better" claims its SOUL explicitly refuses.

- **Development framework** (claude-copilot SOUL): promises **process discipline**
  (enforced, not advisory) and **context efficiency** (resumable work without
  burning tokens rebuilding context). Gate 3 strikes speed/quality claims.
  Measures: resume cost (S-1), main-session token trend, the "~94% externalized
  work-product" figure (measure or strike — required by the SOUL's own taste
  test), delegation/QA-gate/protocol adherence, agent ~100-token frugality (S-2).
  Claude↔Codex comparison is dropped as a measurement (same framework, two
  harnesses); the content parity check remains as sync plumbing only.
- **Knowledge framework** (knowledge-copilot SOUL): promises **accurate
  understanding for good decisions**, and to never be a stale dump / marketing
  narrative / home of quietly contradictory facts. Measures: private-fact
  accuracy delta (built), registry & cross-link integrity, contradictory-facts
  detection, staleness/archive honesty, orphan rate, company-voice preservation
  of its own content (S-3).
- **Integration framework** (cli-copilot SOUL): promises **one binary, one
  grammar** — uniform look/config/failure per service, `.env`-only portability,
  client-never-server, honest hint-bearing failure, lazy & mockable. Measures:
  per-service conformance scorecard against the SOUL's seven non-negotiables +
  portability test (S-4); live health (built); utilization ledger (built, now a
  ratified SOUL exception). The MCP-twin token bench measured an overview-DOC
  claim, not a SOUL claim — result feeds B-17 (reword/delete the doc claim),
  not the product verdict.
- **Ecosystem level**: "more work done, faster" lives HERE (the ladder test +
  always-on scoreboard), never as a single component's claim, and cannot be
  quoted until the ladder produces data.

### S-series tasks (this revision)
- **S-1 Resume-cost bench** — tokens/correctness resuming work with vs without
  Memory/Task state (the framework's core job, measured).
- **S-2 Framework-SOUL collector** — externalization %, agent return-size
  frugality, main-session token trend, QA-gate/ARTIFACT adherence.
- **S-3 Knowledge-SOUL collector** — registry/cross-link integrity, version
  contradictions, staleness/archive hygiene, orphan rate, voice-lint of the
  repo's own company content.
- **S-4 CLI conformance scorecard** — mechanical check of the SOUL quality bar
  per service (in cli-copilot, enforced as a test) + portability test + doc
  truth fixes (service counts, MCP claim rewording).
- **S-5 Dashboard reorganization** — three component sections, each headed by
  its SOUL promise, showing adoption + SOUL-aligned measures; ecosystem
  scoreboard + trust ledger.

## 3. Scope

**In scope** — measurement, benchmark harnesses, the claims register, retention, a local
web-view dashboard, **and building the capabilities the truth conditions require where
they are missing** (owner directive, 2026-07-12: *"if we're missing capability, build
that into the implementation"*). Measurement infrastructure lives in
`copilot-control-tower` (`tools/cse-bench/`) plus user-level artifacts it installs
(LaunchAgent, archive dir). Capability builds (the C-series below) land in the owning
product repo — additive, tested, committed with scoped messages, never force-pushed.

**Staged, not skipped (sequenced behind a prerequisite, per audit evidence):**
- **Enforcement-hook rollout across the ~24 unwired consumer repos** is staged behind
  C-6 (redesign the PreToolUse hook so it can fire on Read/Edit/Agent without the
  April deadlock, proven in `claude-copilot` first). Rolling out the current hook
  as-is would replicate the F-1 failure at ecosystem scale. Observability-only
  (non-blocking, logging) hooks are NOT gated and roll out in C-3.
- **Pruning dead CLI services / deleting doc claims** remain owner decisions (B-17
  produces the delete-or-defend list); deletion is destructive to product surface.

**Non-goals:** building org/department tiers (Control Tower program's scope);
marketing collateral.

## 4. Workstreams and tasks

### P0 — Preserve & see (serves T1, T2) — *nothing else is trustworthy until this runs*
- **B-1 Transcript retention job.** rsync-style append-only archive of
  `~/.claude/projects` (and `~/.codex/sessions`) on a LaunchAgent schedule; never
  deletes; install/uninstall scripts; verified by an automatic run. *The only task in
  the program where delay is irreversible.*
- **B-2 Claims register v1 (`claims.yaml` + checker).** Pre-register operational
  definitions for every metric this program quotes (turn, delegation event-share AND
  tool-share, protocol declaration, knowledge read incl. Bash channel, CLI invocation,
  parity, liveness classes). Checker validates structure and re-runs cheap checks;
  wired to the initiative's pre-commit pattern. Retires the V-2 violation.
- **B-3 Warp-gap probe.** Determine whether Warp holds terminal history that changes
  the F-16 numbers; fold result into the register.

### P1 — Adoption dashboard (serves T1, T3, T5, T6) — *render what already exists*
- **B-4 Collector: Task Copilot stores.** Scan `*/.copilot/tasks.db` (read-only) →
  throughput, completion/rework, WP-per-task, agent mix, monthly trend since 2026-03.
- **B-5 Collector: transcript adoption metrics.** Delegation, protocol rate, agent mix,
  model mix, knowledge read-coverage (both channels) — run-stamped, register-conformant;
  fixes the probe's known blind spots (Fable-class model bucket, rename tracking).
- **B-6 Collector: parity, velocity, integrations.** Codex parity + content-hash diff,
  commit velocity, `copilot health --json` live-integration count.
- **B-7 `cse-bench` CLI.** One entry point running all collectors, emitting
  **schema-versioned, timestamped JSON** (practice what F-15 preaches) into a local
  metrics store with history.
- **B-8 Web-view dashboard.** Local static page rendering the metrics store: Adoption /
  Efficacy / Trust panels. Trust panel = the claims register with live pass/fail —
  the permanent F-18 antidote. CLI computes; the view renders (CT invariant #1).

### P2 — Efficacy benches (serves T3, T4, T5) — *each produces a delta a skeptic can re-run*
- **B-9 Private-fact Q&A bench.** Generate closed-book questions from product dossiers;
  score with-knowledge vs empty-tree. Contamination-immune by construction.
- **B-10 Voice-conformance bench.** Compile the existing rubric material (banned words,
  em-dash ban, AI-cliché list, terminology table, rhythm, FK grade) into a deterministic
  linter; score outputs across knowledge-repo / rules-in-prompt / neither arms.
- **B-11 MCP-twin bench.** `copilot crm`/`db` vs the two live MCP twins: tokens, latency,
  success rate; report honestly bounded per F-17.
- **B-12 Proposal: per-agent `cc eval` expansion** (owner-gated; drafts golden sets +
  measures baseline for the existing `qa` eval as evidence).

### P3 — Ablation & transfer (serves T4, T8) — *the benchmark you can show another org*
- **B-13 Layered ablation harness.** Same task suite at four configs: bare harness →
  +instruction → +knowledge → +integrations; rubric + exemplar-anchored judge scoring;
  persona task packs pluggable (software-build pack first, accountant pack as the
  transfer proof).
- **B-14 External pilot protocol.** Design + run doc for a non-author pilot; the
  de-confounding step every earlier metric is annotated as needing.

### C-series — Capability builds (make the truth conditions TRUE, not just measured)
Owner directive 2026-07-12: missing capability gets built. Each build is additive,
tested in its owning repo, and paired with the register check that proves it stays true.
- **C-1 CLI usage ledger + health completion** (`cli-copilot`, serves T1/T5). Opt-in
  append-only JSONL (command path, timestamp, exit code, duration — args stripped),
  plus registering the 4 service groups missing from `copilot health`. Makes
  utilization directly observable and the live-integration count complete.
- **C-2 Knowledge extension loader + glossary fix** (`knowledge-copilot` +
  `claude-copilot` sync script, serves T4/T2). Make *"extensions load automatically"*
  a true sentence: the sync path actually installs extension content where agents
  read it; fix the manifest's broken glossary reference. Converts F-9/F-10 from
  falsified claims into working mechanisms.
- **C-3 Observability hook rollout** (consuming repos, serves T1/T3). Non-blocking
  logging hooks (SessionStart/PostToolUse-class) registered beyond the single wired
  repo — capture without enforcement, so no deadlock surface.
- **C-4 Content-level parity check** (`codex-copilot`, serves T6). Extend
  `check-upstream-parity.py` beyond 3 version strings to content hashes of agents/
  commands/skills, so drift is visible the day it happens.
- **C-5 Golden-set evals beyond `qa`** (`claude-copilot`, serves T3). Extend `cc eval`
  coverage agent by agent; each new set baselined before merge.
- **C-6 Enforcement that doesn't deadlock** (`claude-copilot`, serves T3). Diagnose
  the April F-1 deadlock, redesign PreToolUse to fire on Read/Edit/Agent safely,
  prove it in `claude-copilot` — the prerequisite for enforcement rollout.

### Owner-decision inputs (serve T2)
- **B-15 (superseded by C-1)** — retained in the register as the charter analysis.
- **B-16 (superseded by C-3/C-6)** — enforcement rollout plan ships with C-6's proof.
- **B-17 Claim-deletion list** — claims with no possible check, per product, for the
  owner to delete or defend.

## 5. Acceptance criteria

- **P0 done:** archive receives an automatic run with file counts logged; `claims.yaml`
  validates in pre-commit; every number quoted by this program has a registered
  definition; Warp gap resolved or documented closed.
- **P1 done:** `cse-bench collect` runs end-to-end; JSON carries `schema_version` +
  run timestamp; dashboard renders all three panels from the store on this machine.
- **P2 done:** each bench emits a reproducible delta (command + inputs + score) recorded
  in the trust panel; Q&A bench covers ≥3 dossiers; linter covers all rubric rule
  classes; MCP-twin reports all three measures.
- **P3 done:** ablation suite completes 4 configs on ≥1 task pack with scored output;
  pilot protocol executed by ≥1 non-author (T8 evidence or a documented null result).
- **C-series done:** each capability is merged additive-and-tested in its owning repo,
  the claim it makes true is re-worded to match reality, and a register check exists
  that will catch regression. Enforcement rollout beyond `claude-copilot` happens only
  after C-6's no-deadlock proof.
- **Program done when the eight truth conditions each have a live, passing check — or a
  ratified decision that the corresponding claim is deleted instead.**

## 6. Risks

- **Single-author confound** — every pre-P3 metric measures the owner; mitigated only
  by B-14. All dashboard panels must carry this caveat until then.
- **Owner-gated dependencies** — T1 is only fully true if B-15/B-16 are ratified;
  the program can reach "observable-by-harness" without them but not
  "observable-by-default."
- **Judge validity in P2/P3** — LLM-judged scores must stay anchored to the exemplar
  pairs and rubric; deterministic checks are always reported alongside.
- **Null results are results.** If a layer shows no delta, that is a product decision
  trigger (fix or cut), not a benchmark failure. Do not soften.

## 7. Measurement definitions

`claims.yaml` (B-2) is the single authoritative source for every operational definition.
No metric may be quoted from this program without a register entry — including in the
dashboard, in docs, and in future audit phases.
