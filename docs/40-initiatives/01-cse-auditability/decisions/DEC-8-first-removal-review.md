# DEC-8 — First removal review: mechanical nominations (W-6)

> tc task: **TASK-100** (B-17, `phases/phase-4-outcome-program-prd.md` §3
> W-6) · Source task: **TASK-128** (W-6, `collectors/value_density.py`) ·
> Claim: `removal-review-first-pass`, `agent-eval-coverage` (`claims.yaml`) ·
> Status: prepared, **not ruled**. **Nothing has been deleted, disabled, or
> cut on the basis of this memo.** Nominations here are MECHANICAL
> (computed by `collectors/value_density.py` per the definition registered
> in `claims.yaml` before this review ran); rulings are the owner's.

## 1. The decision, in one sentence

Of 75 CSE surfaces traced this review (16 claude-copilot agents, 22 CLI
Copilot service groups, 10 knowledge-copilot top-level areas, 37
`.claude/skills` leaf skills), 4 show a **measured** zero-usage-and-no-
outcome-trace signal per the registered nomination rule — 3 agents
(`cpa`, `cs`, `kc`) and 1 knowledge area (`04-shared-systems`) — decide,
per nomination, keep / cut / (for the one case with a real measurement
caveat) investigate-first.

## 2. Context, in plain language

The removal rule (phase-4-outcome-program-prd.md §0.5): *"surface that
does not move an outcome bar within its review window is a removal
candidate... nominations are mechanical; deletions are the owner's."*
`collectors/value_density.py` (TASK-128) operationalizes this for the
first time: per surface, it asks two questions — is there ANY measured
usage signal, and is there ANY measured outcome-bar trace (a passing
eval, a passing conformance check)? A surface is nominated **only** when
usage is a **measured zero** (not merely unmeasured) and the outcome
trace is anything other than a measured `true`. This is deliberately a
higher bar than "no evidence of use": absence of instrumentation (no CLI
usage ledger, no skill-invocation event ledger) is explicitly **not**
evidence of non-use, so — as registered, before this collector computed
anything — the CLI-service and skill surfaces produce **zero**
nominations this review, not because they're all fine, but because
today's instrumentation genuinely cannot tell.

## 3. The evidence (real, verified today, `tools/cse-bench/output/value_density-latest.json`, `generated_at: 2026-07-13T19:39:55Z`, `errors: []`)

### 3a. Agents (16 traced, 3 nominated)

Usage = subagent invocations attributed to that agent (`attributionAgent`
field) across the full archive-UNION-live transcript corpus
(`framework_soul-latest.json`'s `agent_frugality.by_agent_type`). Outcome
trace = a passing golden-set eval (`evals-latest.json`); only `qa` has
one today (claim `agent-eval-coverage`: 1/16).

| Agent | Usage (n invocations) | Eval | Nominated |
|---|---|---|---|
| me | 40 | none | no |
| cco | 13 | none | no |
| qa | 13 | **passing** (10/10) | no |
| ta | 12 | none | no |
| doc | 11 | none | no |
| do | 8 | none | no |
| sd | 5 | none | no |
| sec | 5 | none | no |
| uid | 3 | none | no |
| uxd | 3 | none | no |
| cw | 2 | none | no |
| ind | 1 | none | no |
| uids | 1 | none | no |
| **cpa** | **0** | none | **yes** |
| **cs** | **0** | none | **yes** |
| **kc** | **0** | none | **yes** |

**`cpa` (financial analysis, tax strategy) and `cs` (sales strategy,
discovery calls)** — both are plain domain-specialist agents with the
same invocation mechanism as every other agent in this table (verified:
identical frontmatter shape — `tools:`, `model:`, no special invocation
note). Zero measured invocations is a straightforward reading here: this
corpus is single-author software-engineering work (the CSE build/audit
itself); there is no sales or finance work in it to delegate. Not a
measurement artifact.

**`kc` (Knowledge Copilot repo setup) carries a real measurement
caveat** the other two don't: its own frontmatter says *"invoked via
`/knowledge-copilot` command"*, and that command
(`claude-copilot/.claude/commands/knowledge-copilot.md`) is a **thin
bootstrapper that runs inline in the main session** ("hydrate env vars,"
"locate the repo," "hand off to the methodology") — it does not
obviously delegate to the `kc` agent via an `Agent`/`Task` tool call
carrying `attributionAgent=="kc"`. If the KMS-building workflow is
invoked through that slash command rather than an explicit subagent
delegation, `framework_soul`'s subagent-invocation-count channel would
**structurally undercount `kc`'s real usage**, independent of whether
anyone actually ran the workflow. This review reports the measured
number honestly (0) but flags the caveat rather than treating `kc` as
equivalent evidence to `cpa`/`cs`.

**Cross-check against TASK-105 (C-5, "golden-set evals for me, ta, doc,
sd, uxd"):** none of TASK-105's five agents are in this review's
nomination list — all five show real, measured usage (40/12/11/5/3
invocations respectively). TASK-105's eval scope is **not invalidated**
by this review. One honest aside, not a correction to TASK-105: this
review's usage ranking would put `cco` (13) and `do` (8) ahead of `uxd`
(3) by raw invocation count alone; TASK-105's five were evidently chosen
by some other, non-mechanical judgment before this collector existed.
Worth a look when C-5 is actually executed, but re-scoping C-5 is that
task's call, not this memo's.

### 3b. Knowledge areas (10 traced, 1 nominated)

Usage proxy = % of a top-level `knowledge-copilot/` directory's files
that are referenced (by path or basename) anywhere else in the knowledge
corpus or its manifest — `knowledge_soul-latest.json`'s `orphan_rate`
metric, re-grouped by directory (a FLOOR on true orphan rate per that
metric's own documented caveat, not "read by an agent in a session";
see `claims.yaml`'s `value_density.usage_evidence_by_surface.knowledge_area`
for why the latter isn't sliceable per-area without re-deriving the
corpus scan a second way). Nomination-eligible only at ≥10 files;
nominated at ≥50% orphaned (a literal majority — chosen as a
non-arbitrary bright line before this run, not fitted to any area's
number).

| Area | Files | Orphaned | Eligible | Nominated |
|---|---|---|---|---|
| 03-ai-enabling | 418 | 11.2% | yes | no |
| 02-products | 119 | 10.9% | yes | no |
| 01-company | 90 | 40.0% | yes | no |
| 00-best-practices | 55 | 5.5% | yes | no |
| .claude | 38 | 10.5% | yes | no |
| **04-shared-systems** | **16** | **68.8% (11/16)** | yes | **yes** |
| docs | 11 | 0.0% | yes | no |
| (root loose files) | 9 | 0.0% | no (<10) | no |
| openclaw | 7 | 0.0% | no (<10) | no |
| config | 1 | 0.0% | no (<10) | no |

**`04-shared-systems`** contains two subtrees:
`04-shared-systems/design-system/` — a Storybook/Vite design-system app
whose markdown is mostly internal build-phase notes
(`PHASE-2-NAVIGATION-LAYOUT.md`, `PHASE-5-SUMMARY.md`,
`PHASE-6B-SUMMARY.md`) — and `04-shared-systems/platform/` (4 files: dev
setup + a Notion-integration doc). 11 of its 16 files are unreferenced
anywhere else in the corpus. `01-company` (40.0%) is notably close to the
50% line but does not cross it, and — per the registered rule — is
correctly **not** nominated.

### 3c. CLI service groups (22 traced, 0 nominated) — see DEC-5, not duplicated here

Usage evidence is **null** for all 22 registered services: the opt-in CLI
usage ledger (`COPILOT_USAGE_LOG`) has never been enabled on this machine
(`~/.copilot-cli/usage.jsonl` does not exist — reconfirmed today, same
finding DEC-5 already recorded). The registered nomination rule never
nominates on a null signal alone, so this review adds **zero** new CLI
candidates. `cli_soul-latest.json`'s conformance scorecard is fully green
(135 passed, 3 tracked xfail — fireflies × 2, reddit × 1) and every one
of those gaps is **already** DEC-5's open subject
(`decisions/DEC-5-configure-or-cut-services.md`, TASK-122/R-13:
fireflies, reddit, metabase, method). This review defers to that memo
entirely rather than re-deriving the same finding under a new name.

### 3d. Skills (37 traced, 0 nominated)

Usage evidence is **null** for every `.claude/skills/**/SKILL.md` leaf
skill: no skill-invocation event ledger exists anywhere in the ecosystem
yet (the same C-3 hook rollout that would carry this signal is staged to
`claude-copilot` only — `phases/phase-4-handoff.md` TASK-103). Per the
same nomination rule, **zero** skills are nominated this review — this is
an honest instrumentation gap, not a finding that all 37 are earning
their keep.

## 4. Options and consequences

**Agents `cpa` / `cs` (no measurement caveat):**
- *Cut:* remove `claude-copilot/.claude/agents/{cpa,cs}.md`. *Consequence:*
  shrinks the agent roster from 16 to 14 (2 fewer never-invoked
  specialists to keep in sync with framework changes); the eventual
  `agent-eval-coverage` denominator drops accordingly, and C-5's coverage
  ratio improves for free without any eval work. Reversible only via git
  history / re-authoring if a future need for financial or sales delegation
  actually arises.
- *Keep (as-is):* no action. *Consequence:* 2 more specialist agents keep
  costing maintenance attention (framework SOUL updates, protocol
  compliance, etc.) with zero measured usage across the entire corpus to
  date.
- *Keep, but flag for one real review cycle:* leave in place, revisit at
  the next removal review with fresh corpus data — appropriate if the
  owner expects sales/finance-flavored work soon (W-4's external pilots
  could plausibly exercise `cs`, e.g.) that hasn't happened yet.

**Agent `kc` (measurement caveat — see 3a):**
- *Investigate first, then rule:* check whether `/knowledge-copilot`'s
  actual execution history (this machine's shell/session history, or a
  manual re-read of the command's own steps) shows the KMS-bootstrap
  workflow being run without a `kc` subagent delegation. If so, `kc`'s
  real usage is undercounted and this nomination should be treated as
  unreliable, not acted on as-is.
- *Cut anyway:* if the bootstrap workflow itself has simply never been
  run (regardless of delegation mechanism), `kc`'s zero is real and the
  same consequences as `cpa`/`cs` apply.
- *Keep, no action:* defer any cut until the measurement gap is closed
  (e.g. once the command is updated to explicitly delegate via `Agent`
  tool, or the next review cycle can distinguish "ran inline" from
  "never ran").

**Knowledge area `04-shared-systems`:**
- *Cut the `design-system/` subtree specifically:* if its build-phase
  summary docs (`PHASE-*-SUMMARY.md`) are stale progress notes from a
  finished build rather than living reference content, archive or delete
  them (`platform/`'s 4 files are lower-orphan-risk dev-setup docs and a
  reasonable keep either way).
- *Keep, no action:* the orphan-rate proxy is a floor, not proof nobody
  ever reads this content outside the tracked corpus (e.g. via a
  browser, not an agent tool call) — plausible for setup/reference docs
  a person might read directly rather than have an agent read for them.
- *Re-link instead of cut:* if the content is still wanted, add
  cross-references from files that *are* referenced (e.g. the platform
  overview) so it stops registering as orphaned, without removing
  anything.

**Do nothing (all four):** consequence is simply that this review's
findings sit open — no maintenance burden is reduced, but nothing is
lost either; the next review cycle re-measures against a larger corpus.

## 5. Recommendation (advice, not a ruling)

- **`cpa`, `cs`: cut.** Zero usage across the entire corpus, no
  measurement caveat, no signal any real (sales/finance) work is
  imminent. Low cost, fully reversible via git history if needed later.
- **`kc`: investigate the delegation-mechanism question first**, then
  decide — this is the one nomination this review does not have full
  confidence in, and it should not be treated identically to `cpa`/`cs`.
- **`04-shared-systems`: re-link or cut `design-system/`'s build-phase
  summary docs specifically**, not the whole area — `platform/`'s 4 files
  are ordinary setup/reference content and the weakest candidate in this
  set for removal on the merits, even though the metric groups them
  together.
- **CLI services, skills: no action from this review** — defer to DEC-5
  for CLI, and treat the skill-instrumentation gap as a future-work item
  (a skill-invocation event channel), not a removal question, until real
  usage evidence exists either way.

## 6. Exact one-line actions

- **`cpa` — cut:** `tc task update 100 --status in_progress --metadata '{"cpa":"cut"}'` then hand to `me` to `rm claude-copilot/.claude/agents/cpa.md` and check for any registration elsewhere (commands, docs) referencing it.
- **`cpa` — keep:** `tc task update 100 --status in_progress --metadata '{"cpa":"keep"}'`
- **`cs` — cut:** `tc task update 100 --status in_progress --metadata '{"cs":"cut"}'` then hand to `me` to `rm claude-copilot/.claude/agents/cs.md` and check for any registration elsewhere.
- **`cs` — keep:** `tc task update 100 --status in_progress --metadata '{"cs":"keep"}'`
- **`kc` — investigate first:** `tc task update 100 --status in_progress --metadata '{"kc":"investigate"}'` then check whether `/knowledge-copilot` invocations exist in this machine's session history without a corresponding `kc` subagent transcript.
- **`kc` — cut anyway:** `tc task update 100 --status in_progress --metadata '{"kc":"cut"}'` then hand to `me` to `rm claude-copilot/.claude/agents/kc.md` and `.claude/commands/knowledge-copilot.md`'s dependency on it (if any).
- **`04-shared-systems` — cut design-system summaries:** `tc task update 100 --status in_progress --metadata '{"shared-systems-design-docs":"cut"}'` then hand to `me` to remove the stale `PHASE-*-SUMMARY.md` files under `knowledge-copilot/04-shared-systems/design-system/`.
- **`04-shared-systems` — re-link instead:** `tc task update 100 --status in_progress --metadata '{"shared-systems":"re-link"}'` then hand to `doc`/`kc` to add cross-references from referenced content.
- **Do nothing (any/all):** `tc task update 100 --status blocked --metadata '{"decision":"deferred"}'`
- **Re-run the review with fresh corpus data:** `cd tools/cse-bench && python3 cse_bench.py collect --only value_density && python3 -c "import json; print(json.load(open('output/value_density-latest.json'))['metrics']['nominations'])"`
