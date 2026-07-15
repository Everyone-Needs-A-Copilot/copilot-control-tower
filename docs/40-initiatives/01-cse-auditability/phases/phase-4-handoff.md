# HANDOFF — CSE Verification, Remediation & Outcome Program

> For: the developer taking this program over — or the owner, in six months.
> Refreshed 2026-07-14 (QA pass; supersedes the 2026-07-13 version).
> Owner: Pablo Alejo · Working repo: `copilot-control-tower` (branch `main`)
> **You should be able to finish everything from this document alone.** Every
> claim here is backed by a committed artifact; nothing lives in anyone's head.

---

## 1. The mission (ratified, not negotiable)

The Copilot Solutioning Ecosystem (CSE) has **one goal**: *support people in
creating solutions they love — quickly, efficiently, and intuitively.*

Two rules override everything else:
- **Performance over efficiency.** Loveable solutions, fast, is the objective;
  token efficiency is a constraint pushed as hard as possible (aspiration 90%
  reduction vs bare harness, 60% floor) but *never* at performance's expense.
- **The removal rule.** Surface that moves no outcome bar in its review window
  gets mechanically nominated for deletion. Deletions are the owner's call.

**Where this stands today, in one sentence:** the measuring instrument is
built, proven correct, and running; the ecosystem it measures has not yet
been allowed to run on real work — the register is 62 claims (34 passing /
14 failing / 8 unchecked / 3 gated / 3 retired), and the honest floor is
**two acts only the owner can perform** (§4). Everything else this program
could do without him, it has done.

## 2. Day one — setup and self-verification

**The machine layout.** Every collector tries both known workspace roots
(`/Volumes/Dev/Sites/COPILOT` first, then `/Users/pabs/Sites/COPILOT`) and
uses whichever exists (`tools/cse-bench/collectors/paths.py`,
`resolve_copilot_root()`). On a machine where `/Volumes/Dev` isn't mounted —
confirmed still true, re-verified 2026-07-14 (`mkdir /Volumes/Dev` →
`Permission denied`) — `/Users/pabs/Sites/COPILOT` is the real, only tree.
This affects `tools/cse-bench/` uniformly; it does **not** yet extend to the
product itself — `claude-copilot`'s `.claude/agents/kc.md` and
`.claude/commands/knowledge-copilot.md` still hardcode
`/Volumes/Dev/Sites/COPILOT/knowledge-copilot` and will fail the same way on
a stranger's machine (confirmed live 2026-07-14, walking the pilot kit — see
`phase-4-w4-external-pilot-kit.md` §1a). Reported to the owner, not fixed
this session (a different lane has both files open).

**Traps that will waste your day if you skip this:**
- Interactive `copilot` is a **shell alias for `cd`** on this machine (the
  owner's personal `.zshrc`, not shipped by the framework). Always call
  binaries by absolute path. `/opt/homebrew/bin/copilot` does **not** exist
  here; the real dev binary is `cli-copilot/.venv313/bin/copilot`.
- `alias which='type -all'` (also personal, not shipped) reproducibly breaks
  bare `which` under zsh. Re-confirmed 2026-07-14: it does **not** break any
  shipped script (`setup.md`/`setup-project.md` both already resolve
  `cc`/`tc` via `command -v`) — it is a trap for a human debugging manually,
  not a pilot-blocking defect.
- `cc config init --project` requires the target directory to **already be a
  git repository** — nothing in `SETUP.md` or `setup-project.md` says so.
  Confirmed live 2026-07-14: a fresh, non-git project directory hits `Error:
  Not inside a git repository.` with no earlier warning. `git init` first.
- Cargo builds in control-tower need `CC=/usr/bin/cc PATH=/usr/bin:$PATH`.

**Verify your setup (all must pass before you write a line):**

```bash
cd /Users/pabs/Sites/COPILOT/copilot-control-tower
python3 tools/cse-bench/check_claims.py          # 62 claims, 23 definitions, 0 violations (2026-07-14)
cd tools/cse-bench && python3 cse_bench.py collect   # 14 collectors; integrations still errors honestly (/opt/homebrew/bin/copilot absent)
python3 cse_bench.py render && open output/dashboard.html
tc progress                                       # 33 completed / 4 blocked / 3 cancelled tasks (2026-07-14)
```

## 3. Where the program actually stands (2026-07-14)

- **The register.** 62 claims, `check_claims.py` reports 0 violations. 34
  passing / 14 failing / 8 unchecked / 3 gated / 3 retired. Nothing is
  un-triaged; every failing/unchecked row has a named reason and, where
  applicable, a named blocker (§4, §5).
- **The ten decision memos are ruled and executed**, except one held on
  purpose: DEC-1, DEC-2, DEC-3, DEC-5, DEC-6, DEC-8, DEC-9, DEC-10 are ruled
  (`decisions/DEC-*.md` headers) and their tasks `completed`. **DEC-7 is
  held** — its own recommendation was "run one real Claude Code session in
  `claude-copilot` first, then rule" (TASK-103 stays `blocked` on this, on
  purpose, not on neglect). DEC-4's own claim effect
  (`knowledge-registry-completeness`, still `failing`, re-checked 2026-07-14)
  turned out to be mostly mechanical, non-owner-gated work (the missing
  `copilot-control-tower`/`knowledge-copilot` `ECOSYSTEM.md` rows landed
  independently of the ruling) — 10 top-level dirs remain uncovered, not
  gated on any decision here.
- **The ladder has run twice, live, for real money and real tokens.** v1
  (TASK-125, 4 configs × 3 jobs = 12 cells) and v2 (TASK-142, the
  discriminating job pack, 72 cells). Two outcome bars now have a first real
  number, both **FAILING**:
  - **O-4 (`outcome-token-efficiency`): FAILING, and not narrowly.** Every
    rung measured costs *more* tokens than bare, never fewer — v1: 9/9
    non-bare cells negative vs bare, mean −24.2%; v2's in-situ ablation
    isolates a ~3,000-token/job fixed entry fee for `+framework`, paid
    entirely in turn 1 before any tool result exists, 76.5% attributed to
    `CLAUDE.md` + the agent roster. The one mitigation shipped so far (the
    `CLAUDE.md` payload trim, `claude-copilot@0c73f65`) recovers only
    ~8–12% of that premium and does not flip the sign.
  - **O-6 (`outcome-counterfactual-delta`): FAILING, mixed per-component —
    read the components separately, not averaged.** Knowledge and
    integrations show a **real, positive, mechanically-verified**
    contribution (byte-matched against real service data / a real private
    glossary, independently re-checked). **Framework shows none — but is
    explicitly UNMEASURED, not disproven**: `ladder-cannot-measure-framework-
    agent-layer` found **zero** Task-tool invocations across all 72 cells,
    including the rungs where the full 13-agent roster was materialized and
    available. The harness's headless, single-shot `claude -p` mode never
    gives the agent-delegation layer a chance to fire at all. The honest
    reading is "we could not construct a job on which the agent layer was
    even invoked" — never "agents add nothing." Do not let anyone round this
    down to a disproof.
- **[`retrospectives/value.md`](../retrospectives/value.md)** is the
  **"what can I honestly say"
  document** — the load-bearing artifact for anyone about to quote this
  program externally. Read it before you cite a single number outside this
  initiative.

## 4. The two acts nothing else can substitute for

Everything else in this program that could be done without the owner has
been done. These two are not decisions — they are the only things that put
real data into an honestly empty ledger.

### Act A — track your next real solution end-to-end

`tc solution create` → `lock-brief` → `mark-working` → `mark-loveable` →
`log-usage` → `close`, used as you actually work, spread across real elapsed
time (not a burst at the end — see the windowing note below).

**The machinery is proven ready — verified 2026-07-14, QA pass, in a
disposable scratch store, never the production ledger.** Three solutions were
walked through the full lifecycle in a temp store (`tc init` in a scratch
directory, deleted afterward), with realistic elapsed gaps engineered into
the ledger's own timestamps, then run through
`cse_bench.py collect --only solutions,economy,upkeep`. Every number was
hand-checked against the timestamps that produced it and matched exactly, to
the decimal, in every case: O-1 (TTFLS), O-2 (completeness), O-3 (speed,
observed), O-5 (survival), and O-9's netting. **No bug was found or needed
fixing.** The one thing worth re-stating for whoever tracks the real
solution:

- **Windowing is real and correctly discriminating.** A solution touched
  once, within a 10-second span, attributed ~2.6K marginal-spend tokens from
  its session; a second solution in the *same session* but touched across
  ~7.5 real minutes attributed ~505K — the per-(solution, session) window,
  not the whole session, drives the number, confirmed on real transcript
  data, not a fixture.
- **O-9's netting flip is real and was reproduced.** `outcome-upkeep-tax` is
  currently `unchecked` in production specifically because clause 2
  ("netted against outcome value") can't hold with zero outcome-session
  tokens anywhere — the production `session_token_exact` ratio sits at
  **100% upkeep** for exactly that reason (verified this session,
  `claims.yaml` `outcome-upkeep-tax` evidence). In the scratch test, tagging
  one real historical session as upkeep and touching a solution in a
  *different* real session dropped that ratio from 100% to **0.45%** —
  the netting mechanism works exactly as designed the moment outcome tokens
  exist. Nothing further needs building; it needs a real solution.
- **`tc solution` records the session id correctly** — every mutating call,
  every time, joined against the real live transcript, confirmed by hand
  against the raw `solution_sessions` rows.
- **One pre-existing, already-documented limitation, re-confirmed, not
  newly found:** the waste-decomposition heuristic's literal
  `<promise>COMPLETE</promise>` check doesn't recognize other agents' own
  completion vocabulary (e.g. `qa`'s `VERDICT`/`ARTIFACT` markers), so it
  likely over-counts `failed_direction` in a normal multi-role session — see
  `token-accounting-dual-method-agreement`'s evidence in `claims.yaml`. Not
  fixed this session (out of this pass's scope; flagged, not silently
  patched, same as the prior QA pass that first found it).
- **The production ledger is confirmed empty** in all five repos
  (`copilot-control-tower`, `claude-copilot`, `knowledge-copilot`,
  `cli-copilot`, `codex-copilot`) as of the end of this session
  (`tc solution list --json` → `[]` everywhere).

What flips the moment a real solution ships: `outcome-ttfls`,
`outcome-completeness`, `outcome-speed-observed`, `outcome-survival`,
`token-accounting-dual-method-agreement`, `outcome-upkeep-tax`, and the
real-solution half of `outcome-token-efficiency` (the ladder half is already
in, and failing — see §3).

### Act B — pick 2–3 external pilots

Kit: [`phase-4-w4-external-pilot-kit.md`](phase-4-w4-external-pilot-kit.md).
**Walked literally as a stranger this session** (fresh `git clone` of
`claude-copilot@main` into a scratch directory, no shortcuts) — see the
kit's own new §1a for the full findings. The most material one: `cc config
init --project` needs an already-`git init`'d project directory and nothing
upstream says so (facilitator note added; not fixed in `claude-copilot`
itself this session). Everything else checked (`/opt/homebrew/bin/copilot`
absence, the `which`/`copilot` shell aliases, the `/Volumes/Dev`
`knowledge-copilot` hardcode) is confirmed **non-blocking** for the kit's
own required steps 1–5.

The pre-registered **O-8 tolerance is intact and untouched** this session
(`claims.yaml` `definitions.outcome_transfer_tolerance`, drafted 2026-07-14,
pending owner ratification — kit §2). Ratify it before looking at any
pilot's data (V-2); nothing else blocks recruiting.

Recruits: empty slot, kit §4. Owner's call — 2–3 people, at least one
non-developer, genuinely external, bringing a real problem of their own.
**Urgent, not last** — nothing else can de-confound the single-author caveat
that sits on every panel this program has produced.

## 5. What's left that isn't one of the two acts

- **TASK-103 (C-3 hook rollout)** — held on DEC-7 by design: run one real
  Claude Code session in `claude-copilot`, check `.claude/hooks/state/
  streak-*.json` for sane values and no unexpected `hook-deny`, then rule.
- **TASK-132 (`t2-no-claim-outlives-its-check`)** — the CSE-wide claim-sweep
  mechanism exists and runs pre-commit in all 5 repos (re-confirmed firing
  live this session, §6); the claim itself stays `failing` until the
  remaining artifact-without-mechanism instances are driven to zero.
- **TASK-127 (W-5 efficiency wave)** — blocked, and its job has changed
  shape: with O-4 negative everywhere measured, this is no longer "optimize
  a passing constraint," it's "find any mitigation that moves O-4 toward
  less-negative without degrading O-1/O-3."

## 6. Loose ends closed this session (2026-07-14, QA pass)

- **cli-copilot's unpushed commit `03cb4e0`** ("add canonical launch
  readiness command") is **not** part of this program. Reviewed: Convoco
  conversations-launch feature work, fails closed on production auth (never
  falls back to agent-auth in prod), no secrets or credentials embedded.
  **Not pushed.** Owner's call whether to push, amend, or drop it.
- **27 untracked `.claude/memory/entries/*.md` files** in this repo —
  **committed** this session. This repo's own convention already had 74
  tracked entries and a tracked `.gitkeep`, with no repo-local `.gitignore`
  rule against them, matching `SETUP.md`'s documented project layout
  (`.claude/memory/entries/` — "committed to git"). Spot-checked for secrets
  first (none found).
- **Pre-commit hooks confirmed installed and firing in every repo that
  should have them:** claim-sweep (all 5 repos — fired live, twice, via two
  real commits in this session, both `OK`); crosslinks + freshness
  (`knowledge-copilot` — both run clean); parity-drift-warn
  (`claude-copilot` → `codex-copilot`'s `warn-parity-drift.sh` — runs clean,
  no drift on the currently-staged tree).
- **All 5 repos clean and pushed** as of the end of this session — see §7.

## 7. Repo status (end of session, 2026-07-14)

| Repo | Branch | HEAD | `git status -sb` |
|---|---|---|---|
| `copilot-control-tower` | `main` | `660bb14` | clean, pushed |
| `claude-copilot` | `docs/40-initiatives-migration` | `0c73f65` | 2 files modified by a concurrent lane (`.claude/agents/kc.md`, `.claude/commands/knowledge-copilot.md`) — not this session's, left alone |
| `knowledge-copilot` | `main` | `716bae10` | clean, pushed |
| `cli-copilot` | `main` | `03cb4e0` | ahead 1 (unpushed, not ours — §6); local `.copilot/tasks.db` drift pre-existing, not touched |
| `codex-copilot` | `main` | `7f7d6f6` | clean, pushed |

## 8. How to work (non-negotiable operating rules, condensed)

1. **Register first (V-2).** Definition into `claims.yaml` before you look at
   data; claim entry before you quote a number. Pre-commit-enforced.
2. **Done = claim flip**, with `last_checked` bumped — never merely "code
   exists."
3. **Honesty style.** Negative results are findings — report them plainly.
   Single-author data carries its caveat until Act B lands.
4. **Envelope contract.** Collectors/benches emit `{schema_version:
   "cse-bench/1", collector, generated_at, host_scope, metrics, errors}` +
   a `-latest.json` pointer.
5. **Use Task Copilot.** Statuses maintained as you go; work products stored
   via `tc wp`; the owner reads `tc progress`.

## 9. Quick reference

```bash
# The register (the law)
python3 tools/cse-bench/check_claims.py
# Refresh all metrics + dashboard
cd tools/cse-bench && python3 cse_bench.py collect && python3 cse_bench.py render
# Track a real solution (Act A)
tc solution create --title "..." --brief "..."
tc solution lock-brief <id>
tc solution mark-working <id>
tc solution mark-loveable <id>
tc solution close <id> --status shipped
tc solution log-usage <id> --kind usage|fix|feature --tokens N --sessions N
# CLI conformance scorecard
CC=/usr/bin/cc PATH=/usr/bin:$PATH uv run --extra dev pytest tests/test_soul_conformance.py -v --tb=no -rxX
```

Key documents (this directory unless noted): [`retrospectives/value.md`](../retrospectives/value.md) (what
can honestly be said, externally) · `phase-4-outcome-program-prd.md` (the
program) · `phase-4-w4-external-pilot-kit.md` (Act B, with 2026-07-14's
stranger-dry-run findings) · `../claims.yaml` (the law) ·
`decisions/ruling-agenda.md` (the ten memos, ruled) · `phase-3-soul-
remediation.md` (hygiene, complete) · the three SOUL files (each
component's promise).
