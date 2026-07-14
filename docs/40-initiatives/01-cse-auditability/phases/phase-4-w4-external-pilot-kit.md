# W-4 External Pilot Kit

> Initiative: `01-cse-auditability` · Phase 4 · Prepared 2026-07-13
> tc task: **TASK-126** (W-4, `phase-4-outcome-program-prd.md` §3) · Status:
> prepared, **not run**. Recruiting is the owner's call — §5 below is an
> empty slot, not a roster. Marked **urgent, not last** per the handoff:
> "nothing else can de-confound the data."

## 0. Why this exists

Every outcome number this program has produced so far (DEC-1 through DEC-5,
the W-1 Outcome Ledger, W-3's planned ladder run) is **single-author data**:
one person's transcripts, one person's usage, one person's judgment of what
"loveable" means. Outcome bar **O-8 (Transfer Coefficient)** exists
specifically to test whether any of this holds for someone who is not the
author — and until it runs, every dashboard panel fed by pilot data carries
a single-author caveat that this kit is the only way to remove
(`phase-4-outcome-program-prd.md` §3 W-4 acceptance criterion).

## 1. Install-as-a-stranger procedure

**The principle:** the pilot gets exactly what a stranger finding this
project on GitHub would get — no shortcuts, no author assistance beyond
what's already shipped in docs. If the pilot needs to ask the author
anything beyond pointing at a doc, **that's a product defect**, not a
pilot failure, and it gets logged as one (§3).

**What the pilot does, step by step** (the real, current install path,
verified against `claude-copilot/README.md` "Quick Start," 2026-07-13 — not
a hypothetical):

1. **Clone.**
   ```bash
   mkdir -p ~/.claude && cd ~/.claude
   git clone https://github.com/Everyone-Needs-A-Copilot/claude-copilot.git copilot
   ```
2. **Machine setup (once).** `cd ~/.claude/copilot && claude`, then the
   pilot types: `Read @SETUP.md and set up Claude Copilot on this machine`.
3. **Project setup (per project).** In their own real project directory:
   `cd ~/their-project && claude`, then `/setup-project`.
4. **Start working.** `/protocol <their own real request>` or `/continue`
   to resume.
5. **One real solution of their own** — not a canned exercise. The
   pilot brings a real problem they actually want solved. This is
   non-negotiable: O-1/O-2/O-5 measure a *real* solution's lifecycle, and a
   synthetic task can't produce an honest loveability signal.
6. **(Optional) the ladder job pack** (W-3, once it exists) — only after
   the pilot's own solution is done, if they're willing to run more.

**What gets measured, and how (mapped to the ratified outcome bars,
`phase-4-outcome-program-prd.md` §2):**

| Bar | What's captured | How |
|---|---|---|
| O-1 (TTFLS) | `t_working`, `t_loveable` timestamps, **starting at the clone step**, not the first prompt inside the tool | `tc solution create` at the moment they start step 1 (see §3); `tc solution mark-working` / `mark-loveable` |
| O-2 (Completeness) | Sessions-to-done, tokens-to-done, post-ship fix-vs-feature ratio against a brief locked at the start | `tc solution lock-brief` before real work begins; `tc solution log-usage --kind fix\|feature` post-ship |
| O-3 (Speed, observed) | Elapsed wall-clock, first step → loveable | Same ledger timestamps as O-1 |
| O-4 (Token efficiency) | Total tokens, first step → finished solution | `tc solution log-usage --tokens N`, or the transcript-join method once W-2 lands |
| O-5 (Survival) | Shipped? Still in use N weeks later? | `tc solution close --status shipped`, then a follow-up `tc solution log-usage` check-in |
| O-7 (Voluntary return) | Do they choose this again, unprompted, for their *next* problem? | §2 below |
| O-8 (Transfer coefficient) | Does a non-author, unassisted, land within a stated tolerance of the author's own numbers? | §2 below |

**Author's role during the pilot:** none, beyond what's already shipped in
docs. No live troubleshooting, no "let me just fix that for you," no
Slack/Discord hand-holding. Every time the author *does* have to step in,
it's logged per §3 as an assist — and an assist is a finding about the
product, not a note about the pilot.

## 1a. Verified 2026-07-14 — stranger dry-run findings

A literal walk of §1's six steps was run on a **secondary machine** (the one
this session's `/Volumes/Dev` correction was made from — see
`phase-4-handoff.md` §2), as close to "clone from GitHub and follow only the
shipped docs" as one person auditing their own project can get: a fresh
`git clone` of `claude-copilot` (`main`, the default branch a real stranger
lands on) into a scratch directory, then the documented commands run
literally, not paraphrased. Findings, most-to-least material:

1. **`cc config init --project` requires the project directory to already be
   a git repository, and nothing before it says so.** Neither `SETUP.md`'s
   "Manual Setup" section nor `.claude/commands/setup-project.md` calls
   `git init` or checks `git rev-parse` before Step 7B; a pilot bringing a
   genuinely new idea into a brand-new, not-yet-`git init`'d folder (exactly
   the kind of "real problem" §4's recruit criteria asks for) hits `Error:
   Not inside a git repository.` (`tools/cc/src/cc/commands/config.py:340`)
   with no prior warning and no recovery step documented at that point.
   **Action for facilitators:** tell every pilot to `git init` their project
   directory first if it isn't one already, before running `/setup-project`.
   This is a real product gap (logged for the owner, not fixed in this
   session — it lives in `claude-copilot`'s `setup-project.md`/`SETUP.md`,
   not in this kit).
2. **`/opt/homebrew/bin/copilot` does not exist by default** (confirmed
   absent on this machine, matching `phase-4-handoff.md` §2's note) and
   `SETUP.md`'s "External Dependencies" section verify step (`copilot
   version`) will just report "command not found" for most pilots — which is
   honest and **does not block** the kit's own steps 1–5 (that binary is
   marked "Optional for: All other framework features" in `SETUP.md`, and
   nothing in this kit's install path invokes it). Not a fix needed; flagged
   so a facilitator doesn't chase a red herring if a pilot mentions it.
3. **A bare `copilot` shell alias, if a pilot happens to have one, would
   silently misbehave rather than error** — on this machine specifically it
   is aliased to `cd ~/Sites/COPILOT` (the owner's personal `.zshrc`, **not**
   shipped by the framework — confirmed not present anywhere in the cloned
   repo). No action: this is a pre-existing personal-shell-config risk any
   verify-by-running-a-bare-command step carries, not something the kit or
   `SETUP.md` introduced. Documented here only because the parent handoff
   flags it as a machine trap and this dry run is where it was
   re-confirmed.
4. **`alias which='type -all'`** (also this machine's personal `.zshrc`, not
   shipped) reproducibly breaks bare `which` (`bad option: -l` under zsh).
   Checked whether this can bite a pilot's *automated* setup: it cannot —
   `setup.md` and `setup-project.md` both already resolve `cc`/`tc` via
   `command -v` (never bare `which`), so no shipped script trips this. It
   remains a trap only for a human (or an agent) manually typing `which`
   at an interactive prompt to debug something, exactly as the parent
   handoff already frames it — not a pilot-blocking defect, downgraded from
   "landmine to fix" to "confirmed inert for the documented flow."
5. **`/Volumes/Dev/Sites/COPILOT/knowledge-copilot` is still hardcoded** in
   `claude-copilot`'s `.claude/agents/kc.md` and
   `.claude/commands/knowledge-copilot.md` (confirmed on `main`, the branch a
   stranger clones) — `mkdir`/`git clone` against that path fails with
   `Permission denied` on any machine where `/Volumes/Dev` isn't mounted,
   same class of bug the `tools/cse-bench/collectors/paths.py` fix already
   closed for the benchmark harness, **not yet ported to the product's own
   `/knowledge-copilot` command.** This does **not** block this kit's
   required steps — `/knowledge-copilot` is `SETUP.md` Step 6, explicitly
   optional, and never invoked by this kit's steps 1–5 — so it does not gate
   a pilot's O-1–O-5 data. Reported to the owner as a live defect in
   `claude-copilot` proper (his call whether/when to fix; not touched this
   session — a different lane already has both files open with an
   in-flight, unrelated edit).
6. **Two slightly different "run machine setup" instructions exist** for the
   same step: this kit's §1 step 2 ("say: `Read @SETUP.md and set up Claude
   Copilot on this machine`", matching `claude-copilot/README.md`'s own
   Quick Start) versus `SETUP.md`'s *own* "Quick Start" section, which
   recommends the `/setup` slash command directly. Both were run and both
   land in the same place — no fix needed, just noted as a minor
   documentation redundancy for whoever next does a docs pass.

None of the above required changing this kit's install-as-a-stranger
procedure (§1) or its pre-registered O-8 tolerance (§2, untouched) — they are
gaps in the underlying `claude-copilot` product docs/scripts that a
facilitator running this kit should know about going in, not a wrong step in
this file.

## 2. O-7 / O-8 collection instruments

**O-7 — Voluntary Return Rate.** Definition (§2, PRD): "After a first
solution, does the person choose the CSE for the next problem, unprompted?"

- **Instrument:** a single follow-up question, asked **without reference to
  this pilot or this program**, at a natural later point — the next time
  the pilot has *any* new problem to solve (real or research-scheduled
  check-in, whichever comes first, but not scripted to happen
  immediately after the first solution, since that would prompt the
  behavior it's trying to measure unprompted):
  > "Last time you needed to build/fix something, what did you use?"
- **Recording:** `tc solution log-usage <first-solution-id> --kind usage
  --note "O-7 check-in <date>: <verbatim answer>"` — the raw answer is
  kept verbatim, not pre-coded into yes/no, so a later reviewer can judge
  whether the answer counts as "chose it again" without the instrument
  itself deciding that.
- **What counts as a positive signal:** the pilot names Claude Copilot (or
  visibly uses `/protocol`, `tc`, or the agent roster) for a new,
  independent problem **without being asked whether they used it** — i.e.
  the question above is the *first* time this pilot round mentions the
  tool to them.
- **What breaks the instrument:** asking this question too soon (before a
  second real problem exists) or asking it in a way that implies the
  "right" answer. If no second problem has come up by the time this
  pilot's data is needed for reporting, O-7 for that pilot is `not-yet-
  measured`, not a fabricated answer.

**O-8 — Transfer Coefficient.** Definition (§2, PRD): "O-1..O-5 achieved by
people who are NOT the author, unassisted, within a stated tolerance of the
owner's numbers. Requires ≥2 external users."

- **Instrument:** compute each pilot's own O-1/O-2/O-3/O-4/O-5 from their
  `tc solution` ledger entries (same mechanism as the author's own
  solutions — no separate pilot-only measurement path, so the comparison
  is apples-to-apples), then express each bar as a ratio against the
  author's own most comparable solution (matched, where possible, by
  solution size/complexity — a stated, not silently assumed, match).
- **Tolerance:** **must be stated in `claims.yaml` before any pilot data is
  looked at** (pre-registration, V-2) — this kit does not set that number;
  it flags that the number needs to exist and be committed first. A
  transfer coefficient computed against a tolerance chosen after seeing the
  pilot's numbers is not a measurement, per this program's own V-2 rule.
- **Minimum N:** 2 external users, non-author, at least one non-developer
  (per PRD §3 W-4 and the recruit criteria below) — O-8 cannot be reported
  from fewer than 2, full stop; a single pilot is evidence toward O-8, not
  O-8 itself.
- **Recording:** each pilot gets their own `tc solution` records (their own
  ids); the transfer-coefficient computation itself is a new, small
  collector (or an extension of `collectors/solutions.py`) that reads
  every pilot's ledger plus the author's comparable solution(s) and emits
  the ratio — not a manual spreadsheet, so it's rerunnable per V-2/V-5.

### O-8 tolerance — PROPOSED, owner ratification pending

**This is a proposal, not a ruling.** Drafted 2026-07-14, before any pilot
has been recruited and before any pilot data exists — which is precisely
what makes picking a number defensible right now (V-2): nobody has seen a
result this number could be bent toward. Delivered as a
`claims.yaml` register-patch proposal (see
`docs/40-initiatives/01-cse-auditability/decisions/RULING-AGENDA.md`'s
current session notes / the PROPOSED REGISTER PATCH the owner is holding)
rather than applied directly to the register, because another workstream
holds `claims.yaml` write access as of this drafting. The owner may accept
it as-is, edit it, or replace it outright — but *some* number should be
committed before pilot data is looked at, per this section's own rule two
paragraphs up.

**Per-bar tolerance, ratio-based (O-1, O-3, O-4):**

| Bar | Metric compared | Tolerance | Direction |
|---|---|---|---|
| O-1 (TTFLS) | elapsed wall-clock, first step → `t_loveable` | pilot ≤ **2.0×** author's comparable solution | lower (faster) always clears |
| O-3 (Speed) | elapsed wall-clock, first step → finished | pilot ≤ **2.0×** author's comparable solution | lower (faster) always clears |
| O-4 (Token efficiency) | `tokens_total`, first step → finished | pilot ≤ **2.0×** author's comparable solution | lower (fewer tokens) always clears |

**Rationale for 2.0×:** a first-time, unassisted user reasonably takes
longer and spends more tokens through unfamiliarity with the tool alone,
independent of the tool's own quality — a 1.0× (exact-match) bar would
fail transfer trivially and tell us nothing. 2.0× is the loosest
widely-defensible "same order of magnitude" bound: tight enough that a
pilot who is visibly struggling (3×+) still fails, loose enough that
ordinary ramp-up variance doesn't. It is a single, consistent ratio across
all three time/token bars rather than three separately-tuned numbers,
deliberately — picking different multipliers per bar with no data to
justify the differences would itself be an unprincipled, undisclosed
design choice.

**O-2 (Completeness) — two-part, mixed tolerance:**
- Sessions-to-done: pilot ≤ **2.0×** author's comparable solution (same
  convention as above, for consistency).
- Post-ship fix-vs-feature ratio: pilot's fix-fraction must not exceed the
  author's fix-fraction by more than **20 percentage points** (absolute,
  not a ratio — a multiplicative bound is degenerate near a fix-fraction
  close to zero, e.g. an author fix-fraction of 0.05 would force a pilot
  ceiling of 0.10 under a 2.0× rule, which is far tighter than intended;
  a flat 20pp band avoids that distortion).

**O-5 (Survival) — binary, not ratio:** small-N pilot data (2–3 people)
makes a percentage meaningless. O-5 clears for a pilot if their solution
both shipped AND was confirmed still in active use at the **same N-weeks
checkpoint** used for the author's own O-5 measurement. No partial credit.

**Matching rule ("author's own most comparable solution"):** match by
`tokens_total` order of magnitude (same decade band, e.g. both in the
10k–100k token range) — the one sizing dimension every `tc solution`
record is guaranteed to carry via the ledger. If no author solution in a
comparable size band exists yet when a pilot's data is ready to score,
that bar is `not-yet-measurable` for that pilot (mirroring O-7's own
`not-yet-measured` convention above) — never a fabricated ratio against a
mismatched solution.

**Aggregate verdict:** O-8 requires ALL FIVE of O-1..O-5 to clear their
own tolerance, for **at least 2 of the ≥2 required pilots** (per the
kit's own N≥2 floor). Per-pilot, per-bar pass/fail is reported in full in
each pilot's own report (§3) regardless of the aggregate outcome — a
pilot clearing 4 of 5 bars is a real, informative partial result, not
noise to discard.

## 3. Session-logging expectations

Every pilot session is logged the same way the author's own sessions
already are — no separate, weaker standard for pilots:

- **`tc solution` is the ledger of record.** `create` at the start of the
  pilot's first real attempt (not before — starting the clock at
  recruitment would inflate elapsed time with scheduling delay, not tool
  latency); `lock-brief` once the pilot states what they actually want
  (their own words, not the author's paraphrase); `mark-working` /
  `mark-loveable` at the pilot's own judgment of each milestone, not the
  author's.
- **Every author assist is logged as a defect, not a session note.** If
  the pilot messages the author (any channel) for help with anything the
  shipped docs were supposed to cover, that's recorded as:
  `tc task create --title "Pilot assist: <what was missing>" --agent doc
  --metadata '{"phase":"phase-4","series":"W-4","kind":"pilot-assist-defect"}'`
  — filed as a documentation/product gap, because the acceptance criterion
  for this workstream is explicit: "Author may not assist beyond the
  shipped docs; every assist is logged as a product defect."
- **Transcripts are not special-cased.** The pilot's own Claude Code
  session transcripts land in their own `~/.claude/projects/` the same way
  anyone's do; no separate recording pipeline is needed for O-1–O-5 beyond
  the `tc solution` ledger, and the existing `transcripts` collector will
  pick up their corpus if/when it's pointed at their machine for a token
  cross-check (W-2's join method, once it exists).
- **A pilot report per user is the acceptance artifact** (PRD §3 W-4): one
  short, factual write-up per pilot — what they set out to build, what
  they got, the O-1–O-5/O-7/O-8 numbers, and every logged assist. No
  aggregation across pilots into a single number until each individual
  report exists and is legible on its own.

## 4. Recruit criteria

Per `phase-4-outcome-program-prd.md` §3 W-4 and the handoff's own framing
("nothing else can de-confound the data"):

- **2–3 people total.**
- **At least one non-developer** — required specifically for the
  "intuitive" bar (O-1's `t_loveable`, and the MLP-not-MVP distinction the
  whole program is built around). A pilot roster of only developers cannot
  test whether the product is intuitive to someone without the framing
  developers already bring.
- **Genuinely external to this program** — not someone who has read this
  initiative's docs, watched the author build it, or absorbed context by
  proximity. Familiarity with the CSE (even passive) contaminates the
  "stranger" premise in §1.
- **Has a real problem to bring** — the pilot must have their own actual
  solution to build, not a problem invented for the pilot. A person with
  no real need to build anything cannot generate a real O-1–O-5 signal.
- **Willing to be logged** — the pilot needs to consent to their session
  transcripts, `tc solution` ledger, and assist-defect log being read for
  this program (a straightforward ask, but stated here so it isn't
  skipped when recruiting).

### The owner's picks (empty — fill before recruiting starts)

| # | Name | Developer? | Real problem they're bringing | Recruited (date) | Notes |
|---|---|---|---|---|---|
| 1 | _(owner to fill)_ | | | | |
| 2 | _(owner to fill)_ | | | | |
| 3 | _(optional — owner to fill)_ | | | | |

## 5. What this kit does not do

- It does not recruit anyone. That's the owner's call (`phase-4-handoff.md`
  §6 row 6; `phase-4-outcome-program-prd.md` §4 "W-4 recruits").
- It does not set the O-8 tolerance number. That belongs in `claims.yaml`,
  pre-registered, before any pilot's data is looked at (V-2).
- It does not build the transfer-coefficient collector. That's
  implementation work for whoever runs TASK-126 once recruits exist —
  this kit specifies what that collector needs to do (§2), not its code.

## 6. Bookkeeping

`tc task update 126 --status blocked --metadata '{"blocked_on":"owner
recruit picks, §4"}'` — the honest status: the kit is ready, the ruling
(who the 2–3 pilots are) is not this initiative's to make.
