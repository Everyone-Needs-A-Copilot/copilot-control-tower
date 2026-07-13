# The MLP Expectation Rubric — Ladder Bench (TASK-125 / W-3)

> Status: **DRAFT — prepared, not ratified.** Per
> `phases/phase-4-outcome-program-prd.md` par.3 W-3 and
> `phases/phase-4-handoff.md` §6 row 6: *"the MLP expectation rubric needs
> owner sign-off before first scoring — it operationalizes his bar."* See
> `docs/40-initiatives/01-cse-auditability/decisions/DEC-6-mlp-rubric-signoff.md`
> for the decision memo this rubric is attached to. **No `t_loveable`
> scoring may run against this rubric until DEC-6 says `Status:
> **ratified**`** — `run.py` mechanically refuses a non-dry-run invocation
> until then (see `run.py`'s `check_signoff()`).

## 0. What this rubric is for

O-1 (Time-to-First-Loveable-Solution) needs two timestamps per job-config
cell: `t_working` (mechanical — the job's acceptance check passes, see
`job_pack.py`) and `t_loveable` (does the deliverable meet a person's
actual expectations — "MLP not MVP," per the ratified outcome bars,
`phases/phase-4-outcome-program-prd.md` par.2 O-1). `t_working` is
objective; `t_loveable` is not, by nature — this rubric is the
pre-registered, exemplar-anchored operational definition that makes it
scoreable without smuggling in an after-the-fact judgment call (V-2).

Per the PRD's own framing (par.3 W-3): *"guided experience, sensible
defaults, error help, polish — judged blind, exemplar-anchored,
deterministic checks where possible."* Four dimensions, each below.

## 1. The four dimensions

Each dimension is scored **0–3**. A dimension's score is the HIGHEST level
whose full description is satisfied (not a partial-credit average across
levels) — if level 2's bar is not fully met, the score is 1, even if some
level-2 elements are present.

### 1.1 Guided experience

*Does the deliverable make it obvious what it does and how to use it,
without requiring the reader to read the implementation?*

| Level | Anchor |
|---|---|
| 0 — Absent | No usage guidance anywhere (no `--help`, no docstring, no comment, no README) — a user must read source to know how to invoke it. |
| 1 — Minimal | A bare docstring or comment states what the thing does, but not how to run it (no example invocation, no argument description). |
| 2 — Adequate | A clear "how to run this" exists (a `--help` output, a usage comment, or a short README section) naming the exact invocation and what arguments mean. |
| 3 — Excellent | Level 2, PLUS the deliverable proactively tells the user what happened after it ran (a summary line, a "next step" hint, or — for job-3 — a report that explains its own structure) rather than leaving the user to infer success from silence or a bare exit code. |

**Deterministic sub-check (where possible):** does invoking the
deliverable with no arguments or `--help` (if applicable) print SOMETHING
to stdout/stderr, vs. exiting silently or with a bare traceback? This is a
mechanical floor for level ≥1, not a substitute for the judge's read of
levels 2–3.

### 1.2 Sensible defaults

*Does the deliverable do the right thing with minimal required input, or
does it force the user to specify things a reasonable default should
handle?*

| Level | Anchor |
|---|---|
| 0 — Absent | Requires configuration/arguments beyond what the brief implies are the essential inputs, with no fallback. |
| 1 — Minimal | Works for the exact case in the brief/fixture, but a small, foreseeable variation (e.g. a slightly different but equally valid input) breaks it. |
| 2 — Adequate | Handles the brief's case and at least one foreseeable variation (e.g. job-2: a file with fewer than 5 distinct words; job-3: `copilot` present but a service degraded rather than fully healthy) without crashing or silently producing wrong output. |
| 3 — Excellent | Level 2, PLUS an explicit, reasonable choice is made (and stated) for every genuinely ambiguous point in the brief, rather than the ambiguity being silently resolved one way with no trace of the decision. |

**Deterministic sub-check:** for job-2, does `wordfreq.py` handle a
fixture variant with fewer than 5 distinct words without crashing (this is
checkable mechanically and SHOULD be folded into `job_pack.py`'s
acceptance check once this rubric is ratified — see §3 Known gaps)?

### 1.3 Error help

*When something goes wrong (bad input, a missing dependency, an
unavailable integration), does the deliverable say something a person can
act on, or does it fail opaquely?*

| Level | Anchor |
|---|---|
| 0 — Absent | A raw stack trace, a silent wrong answer, or a hang, with no human-readable explanation. |
| 1 — Minimal | An error is reported, but it restates the failure mechanically (e.g. "FileNotFoundError") without saying what the user should do about it. |
| 2 — Adequate | The error names the actual problem in plain language AND suggests a concrete next step (e.g. job-3's honest "integrations unavailable, run X to enable them" path, per its brief). |
| 3 — Excellent | Level 2, AND the deliverable distinguishes between error classes it can't help with (e.g. a missing external tool) and ones it can partially recover from (e.g. proceeding with a degraded-but-useful result instead of stopping entirely). |

**Deterministic sub-check:** for job-3, does `report.md` contain the
literal phrase `integrations unavailable` (mechanically checked today by
`fixtures/job-3-integration-report/check.py` as part of `t_working`
itself) when `copilot` is not reachable, rather than fabricated service
data? A report that fabricates data when integrations are absent scores
**0** on this dimension regardless of anything else, full stop — this is
the one hard floor this rubric sets mechanically rather than leaving to
judgment, because fabrication is a different failure class than
"unpolished," and the PRD's honesty style (`phases/phase-4-outcome-program-prd.md`
par.5.4: "never quote a struck number... null and negative results are
findings") extends to what a *product* is allowed to fabricate, not only
what a report writer is allowed to claim.

### 1.4 Polish

*Would a person be comfortable handing this to someone else, as-is?*

| Level | Anchor |
|---|---|
| 0 — Absent | Debug prints, placeholder text ("TODO", "FIXME" left in user-facing output), inconsistent formatting, or output that only makes sense with the brief open next to it. |
| 1 — Minimal | Functionally complete but visibly rough (inconsistent spacing/casing in output, no thought given to formatting beyond "technically correct"). |
| 2 — Adequate | Output is clean, consistent, and reads naturally without needing the brief for context. |
| 3 — Excellent | Level 2, PLUS the deliverable anticipates how its output will actually be used (e.g. job-2's word list is trivially pipeable/greppable; job-3's report.md renders sensibly as markdown, not just as plain text with `.md` in the filename). |

## 2. Blind, exemplar-anchored judging protocol

**Blind.** The judge (human or model) is shown ONLY:
- The job's brief (`job_pack.py`'s `brief` field for that job).
- The deliverable's file contents and its stdout/stderr from the
  acceptance-check run.
- This rubric.

The judge is **never** shown: which of the 4 ladder configs produced the
deliverable, the config's position in the ladder ("rung 1" vs "rung 4"),
elapsed time, or token count. `run.py`'s `build_blind_judge_prompt()`
enforces this by construction — it takes a `DeliverableBundle` (brief +
files + stdout/stderr) that never carries a config name or job-cell
identifier into the prompt text itself; the mapping from
`(config, job, rep)` to a blinded bundle id is kept only in `run.py`'s own
bookkeeping, written to the audit trail AFTER scoring, never before.

**Exemplar-anchored.** Each level's anchor above is written as a concrete,
checkable description (not "good" vs "bad") specifically so two different
judges (or the same judge on two different days) converge on the same
score for the same deliverable. Anchors were written BEFORE any live job
was scored (V-2) — extending an anchor's wording after seeing a run is a
new, dated commit to this file, never a silent edit (same rule
`claims.yaml`'s own header states for itself).

**Deterministic checks where possible.** Each dimension above names a
mechanical sub-check that can run without a judge at all. These are
floors/hard-fails, not full substitutes for levels 2–3, which require
reading the deliverable — the PRD's own phrasing ("judged blind...
deterministic checks where possible") reads as "use mechanical checks
where they suffice, not everywhere."

**Judge mode.** Two are supported by `run.py`'s scoring hook
(`score_t_loveable()`), selected by `--judge-mode {model,human}`:
- `human` — writes a scoring worksheet (one per job-config-rep cell) to
  the run's audit-trail directory and returns a `pending-human-score`
  placeholder; a person fills in 4 scores + rationale, and a follow-up
  `run.py --ingest-scores <dir>` pass (not yet built — see §3 Known gaps)
  would fold them back in.
- `model` — builds a blind judge prompt (rubric + brief + deliverable,
  no config/rung identifiers) for a headless `claude -p` call. **This mode
  is what the hard sign-off gate blocks**: `run.py` refuses to actually
  invoke the judge model outside `--dry-run` until DEC-6 is ratified (see
  §0). In `--dry-run`, the prompt is built and validated (structure,
  no leaked identifiers) but never sent.

## 3. `t_loveable` threshold

A job-config-rep cell reaches `t_loveable` when **every one of the 4
dimensions scores ≥ 2 ("Adequate")** — not an averaged total. This mirrors
"MLP not MVP" literally: a solution that is excellent on 3 dimensions but
opaque on errors (dimension 1.3 score 0–1) has NOT met a person's actual
expectations, no matter how good the other three are. `t_loveable` is the
timestamp of the run/judging pass that first produces a
qualifying score; if no rep qualifies, `t_loveable` is `null` for that
cell (an honest miss, not a forced score).

## 4. Known gaps (stated honestly, not hidden)

- The "sensible defaults" and "polish" deterministic sub-checks above are
  named but not yet wired into `job_pack.py`'s mechanical
  `acceptance_check` — today they inform the judge's read only. Folding
  the checkable ones (e.g. job-2's short-input variant) into the
  mechanical check is a candidate follow-up once this rubric is ratified,
  not before (changing the mechanical bar after sign-off would itself
  need a new dated revision here).
- `--ingest-scores` (the human-judge path's second half) is specified in
  §2 but not implemented — `human` mode today produces the worksheet and
  stops; no run has needed it yet since no scoring has happened.
- This rubric has not been exercised against a single real deliverable.
  Every anchor is a considered prediction of what "adequate" looks like,
  not a description calibrated against evidence — exactly what owner
  sign-off (§0) exists to check before that changes.
