# DEC-6 — Sign off the MLP expectation rubric before first ladder scoring

> tc task: **TASK-125** (W-3, `phases/phase-4-outcome-program-prd.md`) ·
> Claim: `outcome-counterfactual-delta`, `ladder_mlp_rubric` (`claims.yaml`) ·
> Rubric: [`../../../../tools/cse-bench/benches/ladder/rubric.md`](../../../../tools/cse-bench/benches/ladder/rubric.md)
> · Status: prepared, **not ratified** — owner signs off before first
> scoring. **No `t_loveable` score has ever been computed against this
> rubric.** `run.py`'s `check_signoff()` reads THIS header block for a
> literal ratified-status marker (the word "Status" immediately followed
> by "ratified" in bold — see §6 for the exact text to swap in) and
> mechanically refuses a live ladder run until it appears here — see
> rubric.md §0 and run.py's module docstring.

## 1. The decision, in one sentence

The ladder bench (`tools/cse-bench/benches/ladder/`) needs a written,
exemplar-anchored rubric to score `t_loveable` (O-1's "meets the person's
expectations" half) — review `rubric.md`'s 4 dimensions and their scoring
anchors, and either ratify it, ratify it with edits, or send it back for a
different design; nothing scores against it until you do.

## 2. Context, in plain language

O-1 (Time-to-First-Loveable-Solution) needs two timestamps: `t_working`
(does the job — mechanical, an acceptance test either passes or doesn't)
and `t_loveable` (is it actually *loveable*, MLP not MVP — inherently a
judgment call). The PRD is explicit that this judgment call cannot be made
by whoever builds the harness: *"t_loveable scored against a written MLP
expectation rubric ... that goes to the owner for sign-off BEFORE first
scoring"* (`phases/phase-4-outcome-program-prd.md` par.3 W-3), and the
handoff repeats it as an open decision-queue item verbatim: *"W-3 MLP
rubric sign-off ... needs owner sign-off before first scoring — it
operationalizes his bar"* (`phases/phase-4-handoff.md` §6 row 6). This memo
exists because that sentence is a hard gate, not a suggestion — TASK-125's
own instructions say to build and dry-run-validate the entire harness+
rubric but explicitly NOT execute a single live scored run, even though
that leaves `outcome-counterfactual-delta` without its first number today.

## 3. The evidence (what was built, not what was measured — no scoring has happened)

**`rubric.md`'s 4 dimensions** (verbatim from the PRD's own list, par.3
W-3: *"guided experience, sensible defaults, error help, polish"*), each
scored 0–3 against a written exemplar anchor per level (not a bare
"good/bad" scale) so two different judges converge on the same number for
the same deliverable:

| Dimension | 0 (absent) | 3 (excellent) |
|---|---|---|
| Guided experience | no usage guidance anywhere | proactively explains what happened after running, not just how to invoke |
| Sensible defaults | breaks on the brief's exact case alone | makes and states an explicit choice for every genuine ambiguity |
| Error help | raw stack trace / silent wrong answer | distinguishes unrecoverable errors from ones it can partially work around |
| Polish | debug prints / TODOs in output | anticipates how the output will actually be used downstream |

**One hard floor set mechanically, not left to judgment:** job-3's error-help
dimension scores **0** outright if the deliverable fabricates service data
when integrations are genuinely unavailable, rather than honestly saying so
— fabrication is a different failure class than "unpolished," mirrored from
this program's own honesty style (`phases/phase-4-outcome-program-prd.md`
par.5.4: "never quote a struck number... null and negative results are
findings").

**`t_loveable` threshold** (rubric.md §3): a cell reaches `t_loveable` only
when **all 4 dimensions score ≥2** — not an averaged total, so a solution
that's excellent everywhere except opaque error handling does not count as
loveable, matching "MLP not MVP" literally.

**Blind judging protocol** (rubric.md §2): the judge (human or, once
ratified, a model via `run.py --judge-mode model`) sees the brief, the
deliverable, and the rubric — never the config name, ladder rung, elapsed
time, or token count. `run.py`'s `build_blind_judge_prompt()` enforces this
by construction, not by judge discipline alone.

**Mechanical enforcement of this gate itself:** `run.py`'s `check_signoff()`
refuses any invocation without `--dry-run` unless this exact file contains
the string `Status: **ratified**` — verified today to correctly report
`ratified=False` (see `tools/cse-bench/benches/ladder/README.md` "Dry-run
output").

## 4. Options and consequences

**Option A — Ratify as drafted.** The rubric ships exactly as written in
`rubric.md`. *Consequence:* the first live ladder run can proceed
immediately once someone runs it; if an anchor turns out to be
miscalibrated once real deliverables are judged against it, the fix is a
new, dated revision to `rubric.md` (never a silent edit — same V-2
discipline `claims.yaml` itself follows), potentially after the fact of a
first scoring pass whose numbers would then need re-stating.

**Option B — Ratify with edits.** The owner changes specific anchors,
the ALL-4-dimensions-≥2 threshold (e.g. to a weighted score, or a
lower/higher bar), or the judge-mode default (`human` vs `model`) before
signing off. *Consequence:* delays the first live run by however long the
edit+re-review takes, but the rubric reflects the owner's actual bar from
the start rather than this builder's best guess at it — the PRD's own
framing ("it operationalizes HIS bar") suggests this is the likelier
correct path for anything beyond the mechanics.

**Option C — Reject / hold for a different design.** E.g., the owner wants
`t_loveable` decided purely by a single blind model judge with no
human-worksheet fallback, or wants a 5th dimension added, or wants the
"all 4 ≥2" threshold replaced with something else entirely.
*Consequence:* `rubric.md` gets rewritten before anything is ratified;
`run.py`'s dimension list (`RUBRIC_DIMENSIONS`) and `validate_rubric_doc()`
would need matching edits so the code and the document don't drift.

**Do nothing.** The gate stays closed, `outcome-counterfactual-delta` and
`outcome-token-efficiency` stay `unchecked` (real instrumentation, zero
data) exactly as they are today — the honest, correct default state per
TASK-125's own instructions, not a failure mode.

## 5. Recommendation (advice, not a ruling)

This is advice: Option A or B, not C — the 4 dimensions are the PRD's own
named list (not invented here), the exemplar-anchor structure and the
blind-judging protocol are mechanical safeguards this rubric would need
under any reasonable design, and the one hard floor (job-3 fabrication)
is a direct extension of this program's own already-ratified honesty
style rather than a new principle. The most likely productive edit, if
any, is the `t_loveable` threshold (all-4-≥2 vs. a weighted score) and the
default `--judge-mode` (this build defaults to `human`, the safer of the
two absent a live-tested model-judge run) — both narrow, low-risk edits
that fit Option B without requiring a full Option C redesign.

## 6. Exact one-line actions

- **Option A / B (ratify, with or without edits first):** edit this file's
  header line to read `Status: **ratified**` (after making any Option-B
  edits to `rubric.md` first), then
  `tc task update 125 --status in_progress --metadata '{"decision":"ratified"}'`.
- **Option C (reject/hold):** revise `rubric.md` and this memo together
  (new dated section, not a silent rewrite), then re-submit for sign-off.
- **Do nothing:** `tc task update 125 --status blocked --metadata '{"blocked_on":"owner rubric sign-off, DEC-6"}'` (this is this task's actual closing status today).
- **Re-verify the gate is still closed:** `cd tools/cse-bench/benches/ladder && python3 run.py --dry-run 2>&1 | grep "signoff gate"`
- **Once ratified, run the first live ladder pass:** `python3 run.py --i-know-this-is-blocked-on-signoff --judge-mode human`
