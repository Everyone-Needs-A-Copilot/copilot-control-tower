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
