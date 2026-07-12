# voice_lint — voice-conformance bench (TASK-93 / B-10)

Deterministic proof of two things:

1. Does knowledge-copilot's voice content change model output AT ALL
   (`arm_knowledge` vs `arm_bare`)?
2. Does the REPO add value over just pasting the compiled rules into the
   prompt (`arm_knowledge` vs `arm_rules_in_prompt` — the repo's
   **marginal** value, the sharp question the Phase 1 re-audit raised)?

## Files

- `rules.yaml` — the voice rubric, compiled (not prose) from three
  knowledge-copilot files, every entry carrying a `source: file:lines`
  ref verified against the actual file content on 2026-07-12 (the task
  brief's line numbers had drifted in a couple of spots; this file
  records the real ones).
- `lint.py` — stdlib-only deterministic linter. Checks any text against
  `rules.yaml`: banned-word hits per category (corporate speak,
  consultant jargon, hedging, AI clichés), em-dash count, terminology-
  substitution violations, sentence-rhythm violations, and a
  Flesch-Kincaid grade with a 6–8 in-band check. `lint.py --help` for
  CLI usage; prefers PyYAML, falls back to a small vendored YAML-subset
  parser (same pattern as `../../check_claims.py`) so it has zero hard
  third-party dependency.
- `run.py` — the bench itself. 6 realistic copywriting tasks × 3 arms =
  18 live `claude -p ... --model sonnet` calls, lints every raw output,
  aggregates per-arm scores, writes the cse-bench envelope.
- `../../output/bench_voice_lint-<stamp>.json` /
  `-latest.json` — the scored results.
- `../../output/voice_lint-run-<stamp>/` — raw per-call model outputs
  (one `.txt` per task×arm) + `manifest.json`, kept for audit — nothing
  in the scored envelope should be taken on faith without being able to
  read what the model actually wrote.

## The three arms

Every arm gets the SAME company context + task ask + word-count
instruction (100–180 words). Only the voice-guidance layer differs:

- **`arm_bare`** — task prompt only. No voice guidance of any kind.
- **`arm_rules_in_prompt`** — task prompt + `rules.yaml` rendered as
  plain imperative writing instructions (generated programmatically
  from `rules.yaml` by `render_rules_as_instructions()`, so it can't
  drift from the compiled rubric).
- **`arm_knowledge`** — task prompt + the RAW text of
  `01-company/01-brand/02-tone-of-voice.md` and
  `.claude/extensions/cw.extension.md` embedded verbatim (the
  "repo-as-context" arm — everything the linter checks for AND
  everything it doesn't: voice DNA, narrative architecture, exemplars,
  calibration tables).

## Contamination control

Every `claude -p` call runs with:

- `cwd` = a **fresh, empty temp directory**, deleted immediately after
  the call — the model has no filesystem to discover this repo, the
  knowledge repo, or any ambient `CLAUDE.md` in.
- `--tools ""` — all tools disabled. The only content in the model's
  context is exactly what `run.py` put in the prompt string. There is
  no channel by which `arm_bare` could accidentally see voice guidance,
  or `arm_rules_in_prompt` could accidentally see the raw knowledge
  text.
- `--no-session-persistence`, `--output-format text` — no session state
  carried between calls; one-shot generation per call.

18 calls, up to 4 concurrent (`ThreadPoolExecutor(max_workers=4)`), 120s
timeout each. A timeout or non-zero exit is recorded as a per-call error
(never crashes the run — the first live run hit exactly one 120s timeout
on a `linkedin_post`-sized prompt under load; `run.py` recorded it,
excluded it from that arm's aggregate, and finished; a clean re-run got
18/18). Both stamped runs are kept in `output/` for history.

## Re-run

```bash
cd tools/cse-bench/benches/voice_lint
python3 run.py                 # full live bench (18 calls, ~3-6 min)
python3 run.py --dry-run       # print the 18 prompts, no live calls
python3 lint.py some_file.txt --json   # lint any single text directly
```

## Necessary, not sufficient — read this before trusting a "0 violations" score

`lint.py` measures **negative-space conformance**: does the text avoid
the things the rubric explicitly forbids (banned words, em dashes,
wrong terminology, punchy-run rhythm, off-band reading grade). A score
of 0 violations proves the text contains none of those things. It
proves **nothing** about whether the text is good copy — whether it
tells a specific story, earns its directness, sounds like a peer over
coffee rather than a press release, or would pass any of `cw.md` /
`cw.extension.md`'s own **positive** quality tests (Specificity,
Recognition, Earned, Conversational, "AI Sniff" — could ChatGPT have
written this?). A bland, generic, forgettable paragraph that happens to
avoid "leverage" and em dashes scores exactly as well on this linter as
a genuinely on-voice one. `rules.yaml`'s `exemplar_pairs` block records
the source material's own before/after pairs for exactly this reason —
they are NOT checked programmatically here.

**Exemplar-anchored judging is future work.** A follow-on bench would
score each output's similarity/adherence to the `exemplar_pairs` (or use
an LLM-judge rubric built from `cw.md`'s Quality Tests table) to measure
positive voice quality, not just the absence of banned patterns. Until
that exists, treat this bench's scores as a floor (conformance), not a
ceiling (quality).

## Known linter limitations (documented, not silently trusted)

- **No stemming.** Banned-word matching is literal word-boundary
  matching against `rules.yaml`'s exact terms. "leverages" or
  "leveraging" will NOT match the banned term "leverage". This is a
  real recall gap, observed directly during development (an `arm_bare`
  fixture used "leverages" and scored 0 corporate-speak hits). Adding
  stemming was deliberately not done — it trades a known, documented
  gap for a much harder-to-audit false-positive surface (e.g. a stem
  match on "solution" inside an unrelated compound). Kept literal on
  purpose; noted here so nobody mistakes "0 hits" for "definitely no
  hedging/corporate-speak anywhere in this text."
- **No conditional exceptions.** `tone_of_voice.md:222` allows
  "implementation roadmap" when "immediately followed by something that
  makes it real" — `lint.py` flags every occurrence regardless (see
  `rules.yaml`'s `consultant_jargon.note`).
- **FK syllable heuristic is an approximation**, not a dictionary
  lookup — see `lint.py`'s module docstring for the exact vowel-group
  algorithm and its two orthography adjustments.
- **Sentence splitting is regex-based** (`(?<=[.!?])\s+`), not a real
  sentence tokenizer — it will mis-split on abbreviations, decimals, or
  ellipses. Not observed to matter across the 18 live outputs scored so
  far, but not guaranteed in general.
