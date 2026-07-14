# Ruling Agenda — clearing the CSE decision queue

> Initiative: `01-cse-auditability` · Repo: `copilot-control-tower` (`main`) · Prepared 2026-07-13
> **For the owner.** Ten prepared memos (`DEC-1`..`DEC-10`) plus two acts no ruling can substitute for.
> Every recommendation below is **advice, carried forward from its memo** — this document rules on nothing.
> Every number is cited to the file it came from. Where a memo's recommendation conflicts with what the
> claims graph implies, §5 and §6 say so plainly.
>
> **Updated 2026-07-14** — factual tallies in §1.2 and §5 refreshed after the serialized register pass
> (t4's falsification, the cli-test-suite-verified flip, DEC-10's projection row); no analysis or
> recommendation below was rewritten.

---

## 1. The state in five lines

1. **The instrument is built; the ecosystem is not yet proven.** 42 claims registered, `check_claims.py` reports **0 violations** (verified this session); 12 collectors and 5 benches run clean ([`../phases/phase-4-handoff.md`](../phases/phase-4-handoff.md) §3).
2. **The scorecard reads 13 passing / 17 failing / 8 unchecked / 4 gated** ([`../claims.yaml`](../claims.yaml), tallied directly, 2026-07-14). That is the honest shape of a program that finished building its measuring equipment and has not yet been allowed to measure.
3. **The red is not breakage.** Six of the seventeen `failing` claims are *findings* — falsified figures the program went and disproved on purpose (`framework-externalization-94pct`, `cli-mcp-net-token-advantage`, `turn-definition-incompatible-with-april`). A clean scorecard produced by the party being scored would be evidence of a bad auditor, not a good ecosystem.
4. **The program has run out of work it can do without you.** Of 23 tasks in the store, 10 are `completed`, 3 are `cancelled`, and **all 10 that remain open are `blocked` — every one of them on you** (`tc task list`: TASK-100, 103, 112, 113, 114, 118, 122, 125, 126, 127). Zero are blocked on engineering.
5. **One ruling is mechanically enforced.** `benches/ladder/run.py`'s `check_signoff()` physically refuses a scored run until [`DEC-6`](DEC-6-mlp-rubric-signoff.md)'s header reads `Status: **ratified**` ([`../claims.yaml`](../claims.yaml), `ladder_mlp_rubric.note`). The gate is code, not etiquette.

---

## 2. The critical path

**DEC-6 was expected to be the keystone. It is — verified against the graph, not assumed.** The evidence: [`../phases/phase-4-w5-efficiency-wave.md`](../phases/phase-4-w5-efficiency-wave.md) §6 states verbatim that DEC-6 is *"the single gate common to every remaining staged patch"*; TASK-125's `blocked_on` metadata reads `"owner rubric sign-off, DEC-6"`; TASK-127's reads `"DEC-6 rubric sign-off (ladder gate) + DEC-1 + DEC-7"`; and both `outcome-counterfactual-delta` and `outcome-token-efficiency` name the DEC-6 gate in their own evidence fields ([`../claims.yaml`](../claims.yaml)).

**One caveat about the keystone, stated up front:** DEC-6 is the keystone by *unblock count*, not by scoreboard. It converts two `unchecked` claims into real numbers — which may be red. The only ruling in this queue that produces a *certain* green is DEC-5.

---

### ① DEC-6 — Ratify the MLP expectation rubric

**The decision.** Review `tools/cse-bench/benches/ladder/rubric.md`'s 4 dimensions (guided experience, sensible defaults, error help, polish; each 0–3 against a written exemplar anchor; `t_loveable` = all four ≥2) and ratify it, ratify it with edits, or send it back.

**The recommendation (advice, from [`DEC-6`](DEC-6-mlp-rubric-signoff.md) §5).** Option A or B, not C. The 4 dimensions are the PRD's own named list ([`../phases/phase-4-outcome-program-prd.md`](../phases/phase-4-outcome-program-prd.md) §3 W-3), not invented by the builder. The likeliest productive edit is the `t_loveable` threshold (all-4-≥2 vs. a weighted score) and the default `--judge-mode` (currently `human`).

**The action.** Edit [`DEC-6`](DEC-6-mlp-rubric-signoff.md)'s header to read `Status: **ratified**`, then:
```
tc task update 125 --status in_progress --metadata '{"decision":"ratified"}'
```

**What it unblocks.**

| Unblocks | Detail |
|---|---|
| **Tasks** | **TASK-125** (W-3, `blocked` → live). **TASK-127** (W-5) — DEC-6 is gate #1 of its three. |
| **All four staged W-5 patches** | `w5-01-agent-return-enforce`, `w5-01-agent-return-amend`, `w5-02-enforcement-rollout-control-tower`, `w5-03-cli-prose-mcp-twin` — the ladder is the common gate on every one. `w5-03` is gated on **DEC-6 alone** (no other open decision touches it), so this ruling fully un-gates one patch by itself. |
| **Claims** (after the run, not at the ruling) | `outcome-counterfactual-delta` `unchecked` → passing-or-failing (the first O-6 number). `outcome-token-efficiency` `unchecked` → passing-or-failing (the ladder is the bare-harness *denominator* the 60/90% figure has no meaning without). |
| **Other decisions** | **DEC-1**. The ladder's O-4 waste decomposition is the only thing that answers whether ~10x agent-return bloat actually costs an outcome bar — i.e. whether "enforce" buys anything or is friction for nothing. |
| **Program acceptance** | PRD §6 item 2 (*"One full ladder run has produced honest O-1..O-4 numbers"*). |

**Honest note.** A bad ladder number is a finding, not a failure ([`../phases/phase-4-outcome-program-prd.md`](../phases/phase-4-outcome-program-prd.md) §3 W-3, verbatim). And per DEC-6 §7: a `t_working` pass-rate table must **never** be quoted without that cell's `t_loveable` scores beside it — job-3's acceptance check cannot distinguish a real service-health pull from a fabricated one; only the rubric's hard fabrication floor can.

---

### ② DEC-7 — C-3 hook rollout: widen now, or run one real session first?

**Placed second because its recommended path has a lead-in act.** If you take the recommendation, the act (one real session) can start immediately and run alongside every other ruling in this sitting.

**The decision.** The hook-path defect that made `claude-copilot`'s deadlock fix non-executable on this machine is fixed and passes 48/49 scripted assertions ([`DEC-7`](DEC-7-c3-hook-rollout-gate.md) §3). Does that satisfy Rollout Readiness condition 1 (*"a full real working session, no unexpected denials"*), or must you actually run one?

**The recommendation (advice, from [`DEC-7`](DEC-7-c3-hook-rollout-gate.md) §5).** **Hold (Option B).** Given this hook system's own history — a fix that looked complete on 2026-04-22 and silently wasn't, for two months — clear the bar as written rather than argue it's close enough.

**The action.** Start one real Claude Code session in `/Users/pabs/Sites/COPILOT/claude-copilot`, do ordinary work, then check `.claude/hooks/state/streak-*.json` for sane values and no unexpected `hook-deny`. Then rule:
```
tc task update 103 --status in_progress
```
(Or, to waive: `tc task update 103 --status in_progress --metadata '{"condition_1":"waived-by-scripted-verification"}'` → hand to `@agent-do` for `knowledge-copilot`, `cli-copilot`, `copilot-control-tower`.)

**What it unblocks.**

| Unblocks | Detail |
|---|---|
| **Tasks** | **TASK-103** (`blocked` → live). **TASK-127**'s `w5-02` patch (DEC-7 + ladder). |
| **Two whole measurement channels currently NULL** | **Skills:** usage evidence is `null` for all 37 skills because *"the same C-3 hook rollout that would carry this signal is staged to claude-copilot only"* ([`../claims.yaml`](../claims.yaml), `value_density.usage_evidence_by_surface.skill`). Until C-3 lands, no skill can ever be nominated *or* defended on evidence. **Tool events:** `solution_token_accounting.methods.event_ledger_c3` is registered as *"NOT YET BUILT... C-3 has not landed anywhere"* — it is the third token-accounting method that would make the W-2 join machine-exact and let the 20% tolerance tighten. |
| **Claims** | `t1-ecosystem-sees-itself` (`failing`) — C-3 is one of its three clauses. `framework-qa-gate-adherence` (`failing`) — the hook state file now exists but is empty (`{}`, 0 sessions tracked): *installed, unfired*. Neither flips at the ruling; both need the hook to actually fire in real sessions and be re-measured. |

**⚠ A green that turns red for a good reason.** `enforcement-hook-wiring-ratio` is currently **passing** — its statement is *"Exactly 1 of 27 repos… registers a PreToolUse hook."* Rolling out to three consumer repos makes that statement **false** (4 of 27), so the claim flips **passing → failing, in the desired direction**. The register already has this exact precedent: `delegation-hook-matcher-scope` sits at `failing` with the evidence note *"This statement is now FALSE — the desired direction."* **The naive tally will lose a green while the ecosystem gets better.** A V-2 restatement commit is owed when C-3 lands. Do not let this show up as a regression.

---

### ③ DEC-8 — First removal review: `cpa` / `cs` / `kc` / `04-shared-systems`

**Placed third because it finalizes the roster, and the roster gates the longest execution tail in the program.**

**The decision.** Of 75 CSE surfaces traced, 4 show a *measured* zero-usage-and-no-outcome-trace signal: agents `cpa`, `cs`, `kc` (0 subagent invocations each) and knowledge area `04-shared-systems` (68.8% of its 16 files orphaned) — `tools/cse-bench/output/value_density-latest.json`, `generated_at: 2026-07-13T19:39:55Z`, `errors: []`.

**The recommendation (advice, from [`DEC-8`](DEC-8-first-removal-review.md) §5).** `cpa`, `cs`: **cut** (zero usage, no measurement caveat, reversible via git). `kc`: **investigate first** — its own frontmatter says it is invoked via the `/knowledge-copilot` slash command, which runs *inline* in the main session and may never produce an `attributionAgent=="kc"` delegation, so the collector may be structurally undercounting it. `04-shared-systems`: **re-link or cut the `design-system/` build-phase summary docs specifically**, not the whole area — `platform/`'s 4 files are ordinary setup docs and the weakest candidate on the merits.

**The actions** ([`DEC-8`](DEC-8-first-removal-review.md) §6):
```
tc task update 100 --status in_progress --metadata '{"cpa":"cut"}'
tc task update 100 --status in_progress --metadata '{"cs":"cut"}'
tc task update 100 --status in_progress --metadata '{"kc":"investigate"}'
tc task update 100 --status in_progress --metadata '{"shared-systems-design-docs":"cut"}'
```

**What it unblocks.**

| Unblocks | Detail |
|---|---|
| **Tasks** | **TASK-100** (B-17). Satisfies W-6's acceptance criterion *"at least one owner ruling recorded"* ([`../phases/phase-4-outcome-program-prd.md`](../phases/phase-4-outcome-program-prd.md) §3 W-6). |
| **The C-5 second eval wave** | The relevance rule ([`../phases/phase-4-handoff.md`](../phases/phase-4-handoff.md) §4) forbids polishing surface the removal rule may delete — TASK-105's own metadata scopes C-5 to *"agents that survive the W-6 relevance pass."* Ruling DEC-8 tells the eval wave exactly which agents to cover: **7 survivors** (`cco`, `do`, `sec`, `uid`, `cw`, `ind`, `uids`) instead of 10 unknowns. |
| **Claims** | `agent-eval-coverage` (`failing`, 6/16 = 37.5%) — **the ruling alone does NOT flip it.** Cutting `cpa`/`cs`/`kc` moves the ratio to 6/13 (46.2%); the claim's statement requires **every** framework agent. It flips only after a C-5 wave evals the 7 survivors. |

**⚠ DEC-8's own evidence is stale on one point.** DEC-8 §3a states *"only `qa` has one today (claim `agent-eval-coverage`: 1/16)."* The register now reads **6 of 16** (`qa`, `me`, `ta`, `doc`, `sd`, `uxd`, each 10/10) — TASK-105 landed after the memo was written ([`../claims.yaml`](../claims.yaml), `agent-eval-coverage`, `last_checked: 2026-07-13`). This does **not** change any nomination (`cpa`/`cs`/`kc` still have zero usage and no eval), but it does change the arithmetic: the remaining eval surface is 7 agents, not 15.

---

### ④ DEC-5 — Configure-or-cut: fireflies, reddit, metabase, method (+ `notion`)

**The only ruling in this queue whose execution turns a red claim green with certainty.**

**The decision.** Four CLI service surfaces are structurally dead in different ways. Live pytest run, 2026-07-13 ([`DEC-5`](DEC-5-configure-or-cut-services.md) §3): `135 passed, 3 xfailed` — and **all 3 remaining `xfail` cases are fireflies/reddit**, i.e. exactly this decision's subject. Per DEC-5 §2: *"Closing this one decision is now the only thing standing between CLI Copilot and a fully green conformance suite."*

**The recommendation (advice, from [`DEC-5`](DEC-5-configure-or-cut-services.md) §5, service by service).** **fireflies, reddit: cut** (no credentials, no usage signal, not currently usable). **metabase: finish the cut already ruled on 2026-06-29** (commit `c8a682c5` removed the code and called it "unused"; the empty directory and the un-revoked `METABASE_API_KEY` remain). **method: cut the unused credentials** rather than build a service with no measured demand. Plus, from [`DEC-9`](DEC-9-delete-or-defend-list.md) §5: **`notion` — same treatment as `metabase`** (a 5th orphan credential of identical shape, found while preparing DEC-9; fold into TASK-122 rather than opening a parallel decision).

**The actions** ([`DEC-5`](DEC-5-configure-or-cut-services.md) §6, [`DEC-9`](DEC-9-delete-or-defend-list.md) §6):
```
tc task update 122 --status in_progress --metadata '{"fireflies":"cut","reddit":"cut","metabase":"finish-cut","method":"cut-creds","notion":"finish-cut"}'
```

**What it unblocks.**

| Unblocks | Detail |
|---|---|
| **Tasks** | **TASK-122** (R-13). Releases TASK-120 (R-11)'s deliberately-skipped scope. Feeds **TASK-100** (B-17). |
| **Claims** | **`cli-soul-conformance`: `failing` → `passing`** — once executed. Either direction closes the 3 gaps: the register's own evidence says *"the gaps close either by configuring them for real or by the owner's R-13 cut ruling, whichever comes first"* ([`../claims.yaml`](../claims.yaml)). |
| **Security surface** | Removes three sets of provisioned, unconsumed credentials from `.env` (`METABASE_API_KEY`, `METHOD_COPILOT_*`, `NOTION_API_KEY`/`NOTION_N8N_ID`). |

**Honest note.** The ruling un-gates; the **execution** flips the claim. Someone still has to run the cut. And `t5-integration-layer-pays-its-way` does **not** flip: it also requires *"retained CLI commands show usage,"* and no CLI usage evidence exists anywhere (see §6).

---

### ⑤ DEC-1 — Agent-return bar: enforce vs amend

**Sequenced behind DEC-6, deliberately.** You *can* rule it today — the memo is complete and its evidence is independent of the ladder. But **both** staged patches are ladder-gated regardless ([`../phases/phase-4-w5-efficiency-wave.md`](../phases/phase-4-w5-efficiency-wave.md) §2.1), so ruling early buys only the removal of one future round-trip — while the ladder's O-4 decomposition is the one thing that would tell you whether the token gap actually costs an outcome bar. W-5's own priority order puts DEC-1 third, after the first ladder run (§6).

**The decision.** SOUL §6 says agents return **~100 tokens**; they return roughly **10x** that. Build enforcement toward the existing bar, or replace the bar with a number the measured distribution supports.

**The evidence, current.** `framework-agent-frugality` ([`../claims.yaml`](../claims.yaml), `last_checked: 2026-07-13`, QA WP-28 refresh): median **893** tokens (n=124), p90 **3,474**, **95.97%** of returns exceed 300 tokens. By type ([`DEC-1`](DEC-1-agent-return-bar.md) §3, and the amend patch's own baseline block): `me` 854.5 (n=36), `doc` 490 (n=11), `sd` 3,786, `uxd` 5,089, `uids` 4,118, `sec` 3,556.

**The recommendation (advice, from [`DEC-1`](DEC-1-agent-return-bar.md) §5).** Neither pure A nor pure B — a **combined path**: amend the bar for design-chain agents whose job is inherently token-dense, enforce a stricter version of the ~100 bar for high-frequency, low-complexity agents (`me`, `doc`). Offered as a third path to accept, reject, or split into two rulings.

**The actions** ([`DEC-1`](DEC-1-agent-return-bar.md) §6):
```
tc task update 112 --status in_progress --metadata '{"decision":"enforce"}'   # → me, implement the SubagentStop check
tc task update 112 --status in_progress --metadata '{"decision":"amend"}'     # → ta/doc, draft the SOUL §10 amendment
```

**⚠ THE CONFLICT — the memo's options and the claims graph do not agree, and you should know this before you rule.**

Neither staged option produces a green claim.

- **Option A (enforce), as staged** (`w5-01-agent-return-enforce.patch`): the hook is **warn-only**, **opt-in** (`COPILOT_RETURN_SIZE_ENFORCE=off` by default), and **scoped to `me`/`doc` only**. It cannot deny — a `SubagentStop` hook cannot re-open an already-stopped subagent. So it changes no behavior on merge; `framework-agent-frugality` stays `failing` until agents actually get shorter and are re-measured.
- **Option B (amend), as staged** (`w5-01-agent-return-amend.patch`): the proposed bar is **~150 tokens for `me`/`doc`, ~2,000 for design-chain agents**. Measured today: `me` **854.5** and `doc` **490** (vs ~150); `sd` **3,786**, `uxd` **5,089**, `uids` **4,118**, `sec` **3,556** (vs ~2,000). **Every single class still misses its own proposed amended bar.** The staged numbers are *targets*, not the measured distribution — so ratifying Option B as written **retires one red claim and registers a new one that also fails on day one.**

That is not an argument against amending. It is an argument that "amend" is not a shortcut to green, and that if a green claim is what you want from this ruling, the bar must be set at or above the measured distribution — which arguably defeats the purpose of having a bar. **This trade-off is yours; the graph just refuses to pretend it isn't there.**

---

## 3. The independent rulings

These four are rulable in **any order**, in this sitting or later. None gates another; none is gated by DEC-6.

### DEC-3 — Ratify the SOUL §3 correction (strike the falsified "~94%")

**The decision.** `claude-copilot/SOUL.md` still quotes *"~94% less context"* in three places (lines 84, 178, 231 — [`DEC-3`](DEC-3-soul-94pct-correction.md) §3). The measurement is falsified **and inverted**: agent returns median **893** tokens vs work-product content median **353**, `savings_ratio_median −1.53` (−153%) — returns are ~2.5x *larger* than the artifacts they externalize ([`../claims.yaml`](../claims.yaml), `framework-externalization-94pct`). The README was already corrected (commit `7274e6b`). SOUL was not.

**The recommendation (advice, from [`DEC-3`](DEC-3-soul-94pct-correction.md) §5).** **Option B** — rewrite to state the *mechanism* and defer to the register for the *number*, rather than hard-coding a new percentage into SOUL text. This avoids the exact failure mode that put SOUL here: a number frozen in a document that measurement later moved past.

**The action.**
```
tc task update 114 --status in_progress --metadata '{"decision":"ratify-rewrite"}'   # → doc, draft the mechanism-only restatement
```

**What it unblocks.** **TASK-114.** **Claim:** `framework-externalization-94pct` `failing` → **retired-by-ratification** (DEC-3 §4 names this outcome explicitly). This is the cheapest red-to-retired in the queue — and it closes a live contradiction: **README and SOUL currently disagree with each other in production**, which DEC-3 §4 rightly calls *worse* than SOUL never having been corrected. It does **not** flip `t2` (see §6).

---

### DEC-2 — Protocol declaration: enforce, simplify, or retire

**The decision.** Every main-session reply is supposed to open with `[PROTOCOL: ...]`. Fresh collect (`transcripts-latest.json`, `generated_at: 2026-07-13T18:23:39Z`): **0.0% median under the loose definition, 0.0% under the strict definition** — flat zero across all 15 sessions measured strictly. **Why, verified against the code:** `.claude/hooks/user-prompt-submit.sh` (258 lines) contains **zero** references to "protocol." Nothing checks. It is unenforced, not too heavy ([`DEC-2`](DEC-2-protocol-adoption.md) §3).

**The recommendation (advice, from [`DEC-2`](DEC-2-protocol-adoption.md) §5).** **Option C — retire the declaration-prefix requirement** (not the underlying routing discipline). The declaration was a proxy for "is routing discipline active"; the program already has a directly-measured, `passing` proxy for that — `delegation-rate-baseline`, tool-share median ~40.5–40.9%.

**The action.**
```
tc task update 113 --status in_progress --metadata '{"decision":"retire"}'   # → doc, strike the obligation, cite delegation-rate as the retained signal
```

**What it unblocks.** **TASK-113** — and, honestly, **nothing else**. W-5 staged **no patch** against DEC-2 (*"no action — correctly blocked on DEC-2; nothing to stage"* — [`../phases/phase-4-w5-efficiency-wave.md`](../phases/phase-4-w5-efficiency-wave.md) §2.3), because the per-turn cost is already zero: the ~7,978-token `/protocol.md` payload is only paid when explicitly invoked, which is ~never.

**Claim effect — read this carefully.** `protocol-declaration-rate-baseline` is currently **`passing`**. Its statement asserts that adoption *never recovered* — and it didn't. **There is no red here to clear.** Under Option C the claim becomes a measurement of a requirement that no longer exists → **retired-by-deletion**, and the tally loses a green while the ecosystem loses a dead obligation. That is green-by-removal working exactly as the removal rule intends.

**V-2 debt owed regardless of how you rule:** the register still cites *"median ~0.8–0.9% under the all-messages definition"*; the fresh collect says **0.0%**. The registered figure no longer reproduces. A correction commit is owed either way.

---

### DEC-4 — Delete or keep the stale clones

**The decision.** `conversations-copilot` **does not exist** on this machine — cleanly migrated, nothing to delete. A real stale clone *does* exist: a registered git worktree at `/Users/pabs/.claude-worktrees/shared-docs/frosty-perlman`, last commit **2026-01-15** against a `main` HEAD of 2026-07-13 (~6 months stale), **clean working tree**, **6.3M** ([`DEC-4`](DEC-4-stale-clones.md) §3).

**The recommendation (advice, from [`DEC-4`](DEC-4-stale-clones.md) §5).** **Option A** — remove it via `git worktree remove` (a raw `rm -rf` would orphan metadata in `.git/worktrees/`). Confirmed stale, confirmed clean, low cost.

**The action.**
```
git -C /Users/pabs/Sites/COPILOT/knowledge-copilot worktree remove /Users/pabs/.claude-worktrees/shared-docs/frosty-perlman
```

**⚠ What it unblocks: no claim.** `knowledge-registry-completeness` (`failing`) fails because **ECOSYSTEM.md still omits `copilot-control-tower` and never lists `knowledge-copilot`'s own path** — not because of the worktree. DEC-4 §3 says so itself: the registry fix *"is the non-owner-gated part of R-9 and is not this memo's subject."*

**So: the claim attached to this decision moves on mechanical work that nobody is blocked on.** Somebody can add the missing Local-path rows to `ECOSYSTEM.md` today without asking you anything. That is worth knowing before you spend a ruling here.

---

### DEC-9 — Consolidated delete-or-defend, per product

**Mostly a roll-up.** DEC-9 cross-references DEC-4/DEC-5/DEC-8 rather than duplicating them — ruling those three answers most of it. Two genuinely new items remain:

1. **`notion` orphan credential** — same shape as `metabase`/`method`: `NOTION_API_KEY`/`NOTION_N8N_ID` present and non-empty in `.env`, `copilot_cli/services/notion/` contains only a stale `__pycache__`, not among the 22 registered service groups. **Recommendation (advice):** fold into DEC-5/TASK-122 and cut (already folded into ④'s one-liner above).
2. **Three dormant repos the registry itself already recommends archiving** — `workflow-copilot`, `ops-copilot`, `ops-copilot-platform` (the last is an empty repo). **Recommendation (advice, [`DEC-9`](DEC-9-delete-or-defend-list.md) §5):** *"the lowest-risk, zero-new-analysis item in this entire memo"* — execute the registry's own already-made call:
```
gh repo archive Everyone-Needs-A-Copilot/workflow-copilot && gh repo archive Everyone-Needs-A-Copilot/ops-copilot && gh repo archive Everyone-Needs-A-Copilot/ops-copilot-platform
```

**DEC-9's single largest finding, and it is not a deletion.** **13 of the ecosystem's registered products have zero usage/outcome instrumentation of any kind** (convoco, insights-copilot, method-copilot, codex-copilot, pipeline-copilot, and nine others). They all **defend by default** — because the removal rule nominates only on a *measured* zero, never on a missing measurement. That is an honest statement about the state of W-1/W-2/W-4, **not** a statement about whether anyone uses these products. Nothing you rule changes it. Only §4 does.

---

### DEC-10 — Retire the unverifiable April turn-comparison claim

**The cheapest ruling on the page.** No `tc task` gates it — it surfaced as a register-hygiene finding, not a workstream deliverable.

**The decision.** `turn-definition-incompatible-with-april` (`failing`) can never pass: its own `check` field reads *"April's original counting script does not exist; nothing to re-run"* ([`../claims.yaml`](../claims.yaml)). Retire it per `t2`'s own rule (*"unverifiable claims are deleted"*, `t2-no-claim-outlives-its-check`), or keep it as a claim that is permanently red by construction?

**The recommendation (advice, from [`DEC-10`](DEC-10-retire-unverifiable-turn-claim.md) §5).** **Retire**, as `retired-by-unverifiability`. The underlying finding (April's number doesn't reproduce under today's `turn` definition — a ~90–112x gap the re-audit already corroborated as definitional, not behavioral, F-6) stays fully on record in `phase-1-findings.md`/`phase-1-reaudit-report.html` and in `definitions.turn`'s own caveat; only the claim row's bookkeeping status changes. This is the narrowest of the three retirement reasons already in use in this register (unlike DEC-3's retired-by-ratification or DEC-2's retired-by-deletion, nothing here is a corrected fact or a removed obligation — the measurement itself is simply impossible).

**The action.** Held for the serialized register-patch pass (this session may not edit `claims.yaml`); once applied: `status: failing` → `status: retired-by-unverifiability` on `turn-definition-incompatible-with-april`.

**What it unblocks.** No task, no other claim — this is pure register hygiene. It does not touch `t2` itself, which stays open on its own separate, much larger CSE-wide sweep.

---

## 4. The two acts no ruling can substitute for

These are not decisions. They are the only things that put real data into an honestly empty ledger. **Every claim below is blocked on one of these two acts and on nothing else — no ruling in §2 or §3 touches any of them.**

### Act A — `tc solution create` on your next real piece of work

The Outcome Ledger is built, live, and runs clean (`errors: []`). It contains **zero solutions**. Every one of these claims carries the same evidence sentence in [`../claims.yaml`](../claims.yaml): *"an honestly empty ledger, not a measured result."*

| Claim | Status | Moves ONLY when a real solution is tracked end-to-end |
|---|---|---|
| `outcome-ttfls` | `unchecked` | O-1 needs `t_working` **and** `t_loveable` on a real solution |
| `outcome-completeness` | `unchecked` | O-2 needs a brief locked at the start (`tc solution lock-brief`) |
| `outcome-speed-observed` | `unchecked` | O-3's observed half is pure ledger timestamps |
| `outcome-survival` | `unchecked` | O-5 needs started → shipped, then an in-use check at N weeks |
| `token-accounting-dual-method-agreement` | `unchecked` | Registered explicitly: *"a real completed solution, not a verification scratch-DB"* |
| `outcome-token-efficiency` (real-solution half) | `unchecked` | The ladder (DEC-6) supplies the denominator; a real solution supplies the numerator |

**The one thing to know before you start:** the token join is only informative for a solution whose `tc solution` calls are **genuinely spread across real elapsed work**. A solution touched once, or whose touches land in the same instant, yields a near-zero-width window and near-zero attributed tokens ([`../claims.yaml`](../claims.yaml), `solution_token_accounting.windowing`, KNOWN LIMITATION). Use the verbs as you actually work, not in a burst at the end.

### Act B — Pick 2–3 W-4 pilot recruits

The kit is complete and the recruit slot is empty ([`../phases/phase-4-w4-external-pilot-kit.md`](../phases/phase-4-w4-external-pilot-kit.md) §4). Criteria: 2–3 people, **at least one non-developer** (required for the "intuitive" bar), genuinely external, **bringing a real problem of their own**, willing to be logged.

| Claim | Status | Moves ONLY with external pilots |
|---|---|---|
| `outcome-return-rate` (O-7) | `gated` | *"After a first solution, users choose the CSE for their next problem unprompted"* — cannot be faked |
| `outcome-transfer` (O-8) | `gated` | Requires **≥2** non-author users. *"A single pilot is evidence toward O-8, not O-8 itself."* |
| `t8-value-transfers-beyond-author` | `unchecked` | *"Every number in existence is single-author"* |

**And this act — and only this act — lifts the single-author caveat from every panel it touches.** Every number DEC-1 through DEC-9 rests on is one person's corpus on one machine. Each memo says so in its own caveat.

**One prerequisite nobody is blocked on:** the **O-8 tolerance must be pre-registered in `claims.yaml` before any pilot data is looked at** (V-2 — [`../phases/phase-4-w4-external-pilot-kit.md`](../phases/phase-4-w4-external-pilot-kit.md) §2, §5). A transfer coefficient computed against a tolerance chosen *after* seeing the numbers is not a measurement. Somebody should register that number now, while it is still costless to do honestly.

---

## 5. Projected register after a full ruling session

**Assumptions, stated so you can discount them:** you rule all ten per the memos' recommendations; the follow-on execution lands (the cuts, the SOUL edit, the C-3 rollout, one ladder run); and **neither Act A nor Act B has happened yet**. Ruling-only effects are separated from execution-dependent ones.

| # | Claim | Now | After the recommended ruling | Flip type |
|---|---|---|---|---|
| 1 | `cli-soul-conformance` | failing | **passing** | ✅ genuine green (DEC-5, once executed) |
| 2 | `framework-externalization-94pct` | failing | **retired** | ♻️ retired-by-ratification (DEC-3) |
| 3 | `protocol-declaration-rate-baseline` | **failing** (2026-07-14: the register's own V-2 correction, independent of DEC-2 — see `../claims.yaml`) | **retired** | ♻️ retired-by-deletion (DEC-2 Option C) — *already failing outside this ruling; retiring it removes a red, not a green* |
| 4 | `enforcement-hook-wiring-ratio` | **passing** | **failing** (desired direction) | ⚠️ *tally loses a green; ecosystem improves* (DEC-7) |
| 5 | `framework-agent-frugality` | failing | **retired**, replaced by a **new failing** claim | ⚠️ red-by-restatement, not green (DEC-1 Option B as staged) |
| 6 | `outcome-counterfactual-delta` | unchecked | **passing or failing** — first O-6 number | 🎲 unknown until it runs (DEC-6) |
| 7 | `outcome-token-efficiency` | unchecked | **passing or failing** — first O-4 number | 🎲 unknown until it runs (DEC-6) |
| 8 | `agent-eval-coverage` | failing | **failing** (6/16 → 6/13) | ⛔ ruling un-gates only; flips after the C-5 wave evals the 7 survivors |
| 9 | `knowledge-registry-completeness` | failing | **failing** | ⛔ the two 2026-07-13-named defects are already fixed (2026-07-14, `../claims.yaml`); 10 top-level dirs remain uncovered — not on any ruling |
| 10 | `framework-qa-gate-adherence` | failing | **failing** | ⛔ hook is *installed, unfired*; needs real sessions + re-measure |
| 11 | `t1-ecosystem-sees-itself` | failing | **failing** | ⛔ DEC-7 closes one of three clauses |
| 12 | `t3-instruction-layer-changes-behavior` | failing | **failing** | ⛔ needs DEC-2 + DEC-7 + DEC-8 + the C-5 wave, all four |
| 13 | `t5-integration-layer-pays-its-way` | failing | **failing** | ⛔ DEC-5 prunes dead surface; the usage clause stays open |
| 14 | `removal-review-first-pass` | passing | passing | — (any DEC-8/9 ruling satisfies W-6's acceptance) |
| 15 | `t4-knowledge-layer-changes-output` | **failing** (2026-07-14, checked directly this session — clause B, voice conformance, falsified) | failing | 🔴 genuine falsification, register-hygiene not ruling-dependent — no ruling in this document touches it |
| 16 | `cli-copilot-test-suite-verified` | **passing** (2026-07-14: cli-copilot commit `be895d6` fixed the Ruff-format break; live CI run `29333615840` green on both matrix jobs) | passing | ✅ genuine green, register-hygiene not ruling-dependent — no ruling in this document touches it |
| 17 | `turn-definition-incompatible-with-april` | failing | **retired** | ♻️ retired-by-unverifiability (DEC-10 Option A) — the cheapest ruling on the page; no task gates it |
| — | the other 25 claims | — | **unchanged by any ruling** | — |

### Projected tally

**Now (2026-07-14):** 13 passing / 17 failing / 8 unchecked / 4 gated — **42 claims**.

**After a full ruling session + execution:** **13–15 passing / 14–16 failing / 6 unchecked / 4 gated** — **39 live claims** (4 retired: DEC-3, DEC-2 Option C, DEC-1 Option B, DEC-10; 1 newly registered). The range depends entirely on which way the first ladder run lands.

**Read that number honestly: the scorecard barely moves, and it may move down.** That is not a failure of the queue — it is what the queue actually is. What a full ruling session buys is:

- **10 blocked tasks → live**, with zero remaining owner-blocked work in the store
- **the ladder open** (the single gate on all four staged W-5 patches, and on two of the nine outcome bars)
- **the agent roster final** (which is what lets the eval wave start at all)
- **four dead claims retired** — green-by-removal, exactly as the removal rule intends
- **two null measurement channels opened** (skills usage; the tool-event ledger)

**Greenness comes from §4 and from the execution waves the rulings release — not from the rulings.** Anyone who promises you a greener scorecard from a decision-clearing session is selling you something.

---

## 6. What stays red no matter what you rule

The honest floor. **No ruling in this document touches anything below.**

**Only real solution data closes these** (Act A): `outcome-ttfls`, `outcome-completeness`, `outcome-speed-observed`, `outcome-survival`, `token-accounting-dual-method-agreement`.

**Only external pilots close these** (Act B): `outcome-return-rate` (O-7), `outcome-transfer` (O-8), `t8-value-transfers-beyond-author`.

**Only someone else's build program closes this:** `t7-inheritance-ladder-in-practice` (`gated`) — delivered by Control Tower's own PRD (`docs/02-prd/prd.md`); this program only verifies it. It will sit `gated` until Control Tower ships.

**Only a small piece of instrumentation nobody has built closes this:** `outcome-upkeep-tax` (O-9, `gated` on maintenance-session tagging). Not a ruling — a build. It is the last of the nine outcome bars, and PRD §6 item 6 requires **none of the nine left gated**.

**Permanently unfixable — and should be retired, not carried:** `turn-definition-incompatible-with-april` (`failing`). Its own `check` field reads: *"April's original counting script does not exist; nothing to re-run."* It can never pass. And `t2`'s own rule — *"unverifiable claims are deleted"* — licenses retiring it. **A tenth item for your queue, and the cheapest one on the page.**

**Needs engineering, not a decision:**
- `knowledge-never-read-rate` (`failing`) — the collector's `knowledge_md` figure (80.8%) does not reproduce the registered ~67%; the register itself says *"Needs reconciliation against the original manual figure, out of scope for this task."* The `all_files` denominator reproduces almost exactly (88.7% vs ~88%), which is evidence this is matching-conservatism in the narrower denominator, not a corpus error.
- `t2-no-claim-outlives-its-check` (`failing`) — needs the full CSE-wide ~40-claim sweep the register's own SCOPE NOTE says it is *not yet*, plus F-18's 7 artifact-without-mechanism instances driven to zero, enforced on commit.
- `cli-mcp-net-token-advantage` (`failing`) — the `w5-03` patch swings `crm` from −780 to **+1238**, but `db` was **not** positive in the cited run. The claim as stated (*"the token advantage is positive"*) very likely **stays failing even after the fix merges and the bench re-runs**. The real move is restating the claim honestly, not chasing it green.
- **`framework-agent-frugality`** — stays red under **both** DEC-1 options as staged (see §2⑤).

**No CLI-service or skill surface can be nominated *or* defended on evidence today.** `usage_evidence` is `null` ecosystem-wide for all 22 CLI service groups and all 37 skills — the opt-in usage ledger `copilot_cli/shared/usage_ledger.py` **exists** (verified) but has **never been enabled** (`~/.copilot-cli/usage.jsonl` does not exist — verified). The nomination rule never nominates on a null signal, by design: *absence of instrumentation is not evidence of non-use.* **Enabling `COPILOT_USAGE_LOG=1` is a one-line act, not a decision — and it starts a clock that nothing else can start.** Every review cycle it stays off is a cycle where the CLI cannot be honestly reviewed at all.

---

### Register-hygiene items nobody is blocked on (free moves — no ruling required)

Found while building this graph. Each is a claim whose *registered evidence has gone stale relative to work that has since landed*. None needs you.

- **`t6-two-harnesses-one-behavior`** (`failing`, evidence: *"Parity check covers 3 version strings only"*) — **stale. C-4 has landed.** `codex-copilot/scripts/check-upstream-parity.py --content` exists and runs. Live run this session: version tuple **pass**; content **drift**, **2 of 70 files** changed — and they are **`.claude/agents/kc.md`** and **`.claude/commands/knowledge-copilot.md`**, precisely the surface DEC-8's `kc` nomination is about. The mechanism exists and is alarming correctly. t6 likely stays `failing` on its *behavior-level* clause, but for a vastly smaller and more honest reason than the one on file. Also note: if you cut `kc`, this drift resolves itself.
- **`t4-knowledge-layer-changes-output`** (`unchecked`, evidence: *"pending B-9 and B-10"*) — **stale. Both benches exist and both pass** (`knowledge-factual-accuracy-delta` +98pp; `voice-conformance-deltas`). t4 is checkable **today**. Which way it lands is a genuine question: `voice_lint`'s own finding is that *compiled rules-in-prompt outperform raw repo-as-context* — so t4's second clause (*"a delta attributable to the knowledge repo rather than to prompting alone"*) may well come back **falsified**. Worth checking precisely *because* the answer isn't obvious.
- **`t1-ecosystem-sees-itself`** — its evidence says *"CLI invocation logging (C-1) does not exist yet."* It does exist; it has just never been switched on (above).
- **`protocol-declaration-rate-baseline`** — registered at ~0.8–0.9%; fresh collect reads **0.0%**. V-2 correction commit owed regardless of DEC-2.
- **`knowledge-registry-completeness`** — the `ECOSYSTEM.md` row additions are unblocked mechanical work (§3, DEC-4). Caveat: the forward check reads **11/17** on this machine because 6 repos are not cloned here — a machine-inventory artifact, not a registry defect on your primary machine.

---

> **The one-line summary.** Rule **DEC-6** and the ladder opens — it is the only gate on all four staged patches and on two of the nine outcome bars. Start **DEC-7**'s one real session, because its recommended path has a lead-in act. Rule **DEC-8** and the eval wave can finally start. Rule **DEC-5** and the CLI conformance suite goes green — the only certain green in the queue. Everything else is cheap, independent, and can be cleared in any order. **But the scorecard will not turn green from this document. It turns green from your next real solution in the ledger and from two people who are not you.**
