# Phase 4 — W-5: The Efficiency Wave

> Initiative: `01-cse-auditability` · Phase 4 · TASK-127 · Prepared 2026-07-13
> Input: `phases/phase-4-outcome-program-prd.md` §3 W-5; DEC-1, DEC-2, DEC-6,
> DEC-7 (`decisions/`). Does NOT touch `benches/ladder/` or `decisions/` —
> those paths are owned by the concurrent DEC-6 lane per this task's own
> binding constraints.

## 0. The governing sentence (quoted, not paraphrased)

`phase-4-outcome-program-prd.md` §3 W-5 states, verbatim:

> "Every efficiency change must show: tokens down AND O-1/O-3 flat-or-better
> on the ladder re-run. A change that saves tokens but slows loveable
> delivery is reverted per ratified decision §0.4."

This applies to **every** efficiency change with no bench-only carve-out —
there is no sentence anywhere in W-5 (or elsewhere in the PRD) that permits
skipping the ladder for a change verified only by a named bench (e.g.
re-running `bench_voice_lint` or `bench_mcp_twin` alone). The ladder's first
scored run is itself blocked on DEC-6 (owner MLP-rubric sign-off — see
`decisions/DEC-6-mlp-rubric-signoff.md`, `Status: prepared, **not ratified**`
as of this writing). **Consequence: no W-5 change can be verified — and
therefore none can merge — until DEC-6 is ratified and a first ladder run
exists**, with one exception surfaced below (R-8, already merged by a
different, earlier-sequenced lane under Phase 3's own rule, not W-5's).

Two of the four named waste classes carry a second, independent gate: DEC-1
(agent-return-bar: enforce vs amend) and DEC-2 (protocol: enforce/simplify/
retire) are both **OPEN owner decisions**. Per this task's binding
constraints, nothing touching those two waste classes may be merged —
analysis and prepared patches only, regardless of the ladder.

## 1. Measured waste (from real artifacts, this session)

| # | Waste target | Baseline (source · `generated_at`) | Headline number |
|---|---|---|---|
| 1 | Agent return sizes (R-1) | `tools/cse-bench/output/framework_soul-latest.json`, `generated_at: 2026-07-13T19:22:53Z` (`metrics.agent_frugality`) | median **940** tokens (n=116), p90 **3,671**, **94.8%** over the 300-token threshold, vs the SOUL §6 ~100-token bar |
| 2 | Enforcement cost (hook rollout) | `decisions/DEC-7-c3-hook-rollout-gate.md` §3 (claude-copilot commits `77f5cdb0`, `8608e24`) | Verified (48/49 scripted assertions) but **rolled out to 0 of 3 eligible consumer repos**, including this one |
| 3 | Protocol declaration cost (DEC-2) | `tools/cse-bench/output/transcripts-latest.json`, `generated_at: 2026-07-13T19:22:54Z` (`metrics.global`) | Loose median **0.0%** (mean 6.2%, n=24), strict median **0.0%** (n=16) — but the per-turn injected cost is already 861 tokens once-per-session, not per-turn (SOUL-compliant); the heavy ~7,978-token `/protocol.md` payload is paid only when explicitly invoked, which is ~never |
| 4 | Knowledge delivery format (R-8) | `claims.yaml` `knowledge-voice-self-conformance` (registered baseline 2.74 violations/100w, `last_checked: 2026-07-12`) vs a **fresh re-run this session** of the deterministic linter against the live file | Registered: 2.74/100w. **Fresh, this session: 0.0/100w** (re-run below) — the fix is already merged, see §3 |
| 5 | CLI grammar prose (MCP-twin) | `claims.yaml` `cli-mcp-net-token-advantage`, evidence quoting `tools/cse-bench/output/bench_mcp_twin-latest.json` run `20260712T175500Z` | Net advantage **negative** under probe-everything grammar cost (crm -780, db -1894 tokens); **positive only for crm (+1238)** once shipped prose is read up front |
| 6 | economy.py waste-decomposition limitation (not a fix target — a measurement caveat) | `claims.yaml` `token-accounting-dual-method-agreement` evidence | `failed_direction`'s `<promise>COMPLETE</promise>` check does not recognize other roles' own completion vocabulary (e.g. qa's `VERDICT`/`ARTIFACT` markers) — likely **over-counts** `failed_direction` in any normal multi-role session. Flagged, not corrected here (out of this task's scope; a measurement-tool fix, not a CSE efficiency change) |

**Honesty notes on #1:** the corpus is live and growing *during this very
session* (concurrent agents on this machine keep appending subagent
transcripts) — three snapshots taken roughly 25 minutes apart show the same
directional gap with slightly different absolute numbers: DEC-1's own
citation (`18:26:30Z`, n=100) had median 1,032 / p90 3,921.8 / 95.0% over;
mid-session (`19:08:24Z`, n=111) had median 960 / p90 3,786 / 95.5%; this
plan's canonical citation (`19:22:53Z`, n=116) has median 940 / p90 3,671 /
94.8%. The by-agent-type breakdown for the design-chain agents (`sd`, `uxd`,
`uids`, `sec`) was **identical** across all three snapshots (no new
design-chain invocations landed in that window) — only the high-frequency
types' counts grew, pulling the aggregate down slightly. Single-machine,
single-author data; no external-pilot signal (W-4 pending).

**Honesty note on economy.py / knowledge_soul.py path resolution:** an
earlier snapshot this session (`economy-latest.json`, `19:08:23Z`) showed
`repos_scanned: []` because its default glob resolved against
`/Volumes/Dev/Sites/COPILOT/*/.copilot/tasks.db`, not mounted on this
machine (this task's own binding note). Between then and this writing, a
concurrent lane landed `collectors/paths.py` (`resolve_copilot_root()`,
tries `/Volumes/Dev/Sites/COPILOT` then falls back to
`/Users/pabs/Sites/COPILOT`) and wired it into `tasksdb`/`economy` (among
others per its own docstring) — a fresher re-run (`19:27:47Z`) now shows
`repos_scanned` with 10 real repos and, importantly, **`solutions_total` is
still 0** even with repos successfully found: genuinely zero production
solutions exist yet (W-1's own honest-empty state, confirmed independently
in `claims.yaml`'s `outcome-token-efficiency` evidence), not an artifact of
the mount issue. `collectors/knowledge_soul.py`, however, still hardcodes
`COPILOT_ROOT = Path("/Volumes/Dev/Sites/COPILOT")` directly — per
`paths.py`'s own docstring it is one of the collectors meant to migrate to
the shared resolver but has not yet — so it still errors
(`"not a directory / not found"`) here, and its `voice_self_conformance`
block is empty this session. That is why waste target #4 above is verified
via a **direct linter re-run** (`benches/voice_lint/lint.py`, deterministic,
no live model) instead. Not fixed here: a concurrent lane is visibly
mid-migration on `paths.py` already, and this is a collector-plumbing bug,
not a W-5 token-waste target — touching it risks colliding with that lane's
own work and is out of this task's scope (CLAUDE.md: "never refactor
unrelated code").

## 2. Per-target detail

### 2.1 Agent return sizes (R-1 / DEC-1)

- **Baseline:** see §1 row 1.
- **Proposed change (two alternatives, owner picks one per DEC-1):**
  - **Option A (enforce):** add a warn-only return-size check to
    claude-copilot's `SubagentStop` hook (`subagent-stop.sh`), scoped to
    `me`/`doc` only (DEC-1's own recommended enforce-first set), opt-in via
    `COPILOT_RETURN_SIZE_ENFORCE=warn` (off by default). Staged:
    [`w5-staged-patches/w5-01-agent-return-enforce.patch`](w5-staged-patches/w5-01-agent-return-enforce.patch).
  - **Option B (amend):** replace SOUL.md §6's flat "~100 tokens" bar with a
    class-proportional budget (~150 for `me`/`doc`, ~2,000 for design-chain
    agents), plus a §10 Evolution changelog entry. Staged:
    [`w5-staged-patches/w5-01-agent-return-amend.patch`](w5-staged-patches/w5-01-agent-return-amend.patch).
- **Expected token effect (ESTIMATE, unverified):** Option A could plausibly
  cut `me`/`doc` returns toward the 300-token warn line from their current
  854.5/490 medians — call it an *estimated* 30-45% reduction for those two
  types specifically, **not** measured, **not** claimed as real. Option B
  produces zero token change by itself (it is a documentation/bar change);
  any token effect would come from a *later*, separate enforcement pass
  built against the new bar.
- **Verification path:** decision-gated (DEC-1, OPEN) **and** ladder-gated
  (§0). Neither patch may merge before DEC-1 rules; even after DEC-1 rules,
  the PRD's own text still requires a ladder re-run before merge.
- **Status:** **staged, blocked on DEC-1 + DEC-6/ladder.**

### 2.2 Enforcement cost — hook rollout (C-3 / DEC-7)

- **Baseline:** see §1 row 2. `decisions/DEC-7-c3-hook-rollout-gate.md`
  recommends **hold** (Option B): the scripted verification is thorough but
  Rollout Readiness condition 1 ("a full real working session, no
  unexpected denials") has not been cleared by an actual owner-driven
  session, only by synthetic replay.
- **Proposed change:** create `.claude/settings.json` in
  `copilot-control-tower` (this repo currently registers **zero** hooks —
  one of the 26/27 repos DEC-2's own evidence names), mirroring
  claude-copilot's own file verbatim (absolute paths into claude-copilot's
  shared hook scripts — the framework's existing shared-hooks pattern, not
  a local copy). Staged:
  [`w5-staged-patches/w5-02-enforcement-rollout-control-tower.patch`](w5-staged-patches/w5-02-enforcement-rollout-control-tower.patch).
- **Expected token effect (ESTIMATE):** none directly — this is a
  *governance* cost (delegation enforcement), not a token-reduction move by
  itself. Its relevance to W-5 is the PRD's own framing: "enforcement
  context cost (pays once, never per-turn)" — the `SessionStart` hook
  payload (`protocol-injection.md`, ~861 tokens) already respects that rule;
  rolling out the `PreToolUse`/`SubagentStop` hooks adds no *new* per-turn
  cost, only a one-time `SessionStart` cost already paid where hooks exist.
- **Verification path:** DEC-7 ruling (OPEN, "hold" recommended) **and**
  ladder-gated (§0, this is a named W-5 waste item).
- **Status:** **staged, blocked on DEC-7 + DEC-6/ladder.**

### 2.3 Protocol declaration cost (R-3 / DEC-2)

- **Baseline:** see §1 row 3. DEC-2 is an OPEN owner decision (enforce /
  simplify / retire the `[PROTOCOL: ...]` declaration requirement).
- **Proposed change:** **none staged.** Per this task's binding
  constraints, DEC-2 is explicitly out of scope for any merge — "analysis
  and prepared patches only" — and unlike R-1, no concrete token-saving code
  change was identified here: the per-turn cost is already zero (0.0%
  adoption means the ~7,978-token `/protocol.md` payload is essentially
  never paid), and the once-per-session injection is already the cheap,
  SOUL-compliant path. The actual DEC-2 question (adopt vs retire the
  declaration) is a governance question, not a waste-reduction one — W-5
  has nothing to attack here beyond what DEC-2's own memo already covers.
- **Verification path:** decision-gated (DEC-2, OPEN). N/A for the ladder
  since no change is proposed.
- **Status:** **no action — correctly blocked on DEC-2; nothing to stage.**

### 2.4 Knowledge delivery format (R-8)

- **Baseline:** `claims.yaml` `knowledge-voice-self-conformance` still reads
  2.74 violations/100w (`last_checked: 2026-07-12`).
- **What actually happened:** knowledge-copilot commit `b1f99719`
  ("R-8: voice guidance passes its own linter (distilled-rules rewrite)",
  2026-07-13T15:06:38-04:00 = `19:06:38Z`) already rewrote
  `01-company/01-brand/02-tone-of-voice.md` and restructured
  `.claude/extensions/cw.extension.md` to carry the distilled rules — **this
  predates this session and this task.** Re-run this session, live, against
  the current file:
  ```
  cd tools/cse-bench/benches/voice_lint && python3 lint.py \
    /Users/pabs/Sites/COPILOT/knowledge-copilot/01-company/01-brand/02-tone-of-voice.md --json
  ```
  Result: `"total_violations": 0`, `"total_violations_per_100_words": 0.0`
  (word_count 1,573, sentence_count 120, Flesch-Kincaid grade 6.5,
  in-band). Down from the registered 2.74.
- **Expected token effect:** none claimed here beyond the already-registered
  `voice-conformance-deltas` finding (rules-format 0.10 violations/100w vs
  bare-prompting 2.77) — R-8 makes the *reference document itself* conform
  to what that finding already proved works; it does not by itself change
  agent-return or main-session token counts.
- **Verification path:** bench-verifiable (`benches/voice_lint/lint.py`,
  deterministic, re-run above) — **this was Phase 3's own rule** ("a
  mechanical check that proves the fix"), not W-5's ladder rule. Phase 3
  predates the outcome-bars ratification and the ladder harness (W-3);
  applying W-5's *retroactive* ladder requirement to an already-merged
  Phase-3 fix is not this task's call to make, and reverting a real,
  verified, passing fix to satisfy a rule that postdates it would be an
  honesty regression, not an improvement. Flagged for the owner, not acted
  on.
- **Status:** **merged — by a different, earlier lane, before this task
  started, verified by bench (not the ladder).** See §4 for the proposed
  claim flip.

### 2.5 CLI grammar prose (MCP-twin fix)

- **Baseline:** see §1 row 5.
- **Proposed change:** add a short "Using a service (for agents)" section to
  `cli-copilot/CLAUDE.md` instructing agents to read
  `docs/services/XX-<name>.md` the first time they use a command group in a
  session, instead of reconstructing the grammar by walking `--help`. Staged:
  [`w5-staged-patches/w5-03-cli-prose-mcp-twin.patch`](w5-staged-patches/w5-03-cli-prose-mcp-twin.patch).
- **Expected token effect (ESTIMATE, unverified):** per the mcp_twin bench's
  own numbers, this is what turns `crm`'s net advantage from -780 to +1238
  (a swing of ~2,018 tokens per session where `crm` is used) — that number
  is real (bench-measured), but whether it holds in a full agentic session
  (not just the schema-vs-prose comparison) is an *estimate*, not verified.
  `db`'s prose-based net advantage was not computed as positive in the
  cited run; this patch would need the bench re-run after landing to know
  if `db` also improves.
- **Verification path:** ladder-gated only (§0) — no open DEC blocks this
  specific change; the ladder is the sole named gate, and it is closed
  (DEC-6).
- **Status:** **staged, blocked on DEC-6/ladder.**

## 3. Staged patches (this commit)

All four live under
[`w5-staged-patches/`](w5-staged-patches/), each a real, `git apply --check`-verified
unified diff against the current state of its target file in its target
repo (verified this session; not applied there):

| Patch | Target repo · file | Un-gated by |
|---|---|---|
| `w5-01-agent-return-enforce.patch` | claude-copilot · `.claude/hooks/subagent-stop.sh` | DEC-1 (enforce) + ladder |
| `w5-01-agent-return-amend.patch` | claude-copilot · `SOUL.md` | DEC-1 (amend) + ladder |
| `w5-02-enforcement-rollout-control-tower.patch` | copilot-control-tower · `.claude/settings.json` (new file) | DEC-7 + ladder |
| `w5-03-cli-prose-mcp-twin.patch` | cli-copilot · `CLAUDE.md` | ladder only |

No feature branches were created in `claude-copilot` or `cli-copilot` for
these — they are prepared here as patch files per this task's instructions.

## 4. Proposed claim flips (do NOT edit `claims.yaml` — another lane owns
reconciliation)

- `knowledge-voice-self-conformance`: registered 2.74 violations/100w
  (`last_checked: 2026-07-12`) is **stale**. A direct re-run this session
  against the current file (knowledge-copilot `b1f99719`) shows **0.0
  violations/100w**. Propose: flip `status: failing` → `passing`, update
  `evidence` to cite the fresh `lint.py --json` run above (or, once the
  `/Volumes/Dev` mount issue is separately resolved, a fresh
  `knowledge_soul` collector run) and the `b1f99719` commit.
- `framework-agent-frugality`: registered median 658 / p90 2,749 / 86.2%
  over (`last_checked: 2026-07-12`) is stale relative to this session's
  `19:22:53Z` snapshot (median 940, p90 3,671, 94.8% over, n=116). Propose:
  refresh the evidence citation to the newer `generated_at` and numbers —
  the claim's `status: failing` does not change (the gap is still large),
  only the cited figures should move to the freshest honest snapshot.
- `framework-externalization-94pct`: same staleness note applies (its
  evidence also cites the pre-session `framework_soul-latest.json`); no
  status change proposed, only a fresher citation if the reconciling lane
  wants one.

## 5. What merged vs what stayed staged (the honest answer)

**Nothing new merged in this task.** Per §0's quoted PRD sentence, every
efficiency change in the W-5 waste list is ladder-gated, and the ladder is
closed pending DEC-6. Two of the four waste classes (R-1, and the hook
rollout tied to "enforcement cost") carry an *additional* OPEN-decision gate
(DEC-1, DEC-7) that independently blocks merge regardless of the ladder. The
one item that IS merged (R-8, knowledge format) was merged by a different
lane, before this task, under Phase 3's own (non-ladder) rule — not
something this task did or could revert/re-verify against a rule that
postdates it.

**This is the acceptable, honest outcome the task anticipated.** An empty
merged-set for this session's own work, with four real, reviewable, staged
patches and one accurately-attributed pre-existing merge, is more honest
than forcing a merge that the PRD's own text does not license today.

## 6. What actually unblocks the wave

In priority order: (1) DEC-6 ratification (rubric.md sign-off) — unblocks
the ladder itself, the single gate common to every remaining staged patch;
(2) a first live ladder run — produces the O-1/O-3 baseline every staged
patch needs a delta against; (3) DEC-1 ruling — unblocks the two
return-size patches specifically; (4) DEC-7 ruling — unblocks the
enforcement-rollout patch specifically. None of these four are this task's
to decide or force.
