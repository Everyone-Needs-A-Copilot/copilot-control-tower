# knowledge_qa — B-9 private-fact Q&A bench (TASK-92)

Measures whether Knowledge Copilot's product dossiers change what Claude
answers, using closed-book questions whose answers are private facts a
base model cannot plausibly produce on its own. This is the bench that
overturned Phase 1's F-12 "unmeasurable" verdict
([`phase-1-findings.md`](../../../../docs/40-initiatives/01-cse-auditability/phases/phase-1-findings.md)
§F-12) and closes T4 in
[`phase-2-prd.md`](../../../../docs/40-initiatives/01-cse-auditability/phases/phase-2-prd.md).

## Why F-12 doesn't apply here

F-12 gave three reasons a knowledge-efficacy benchmark couldn't work, all
about **voice conformance**:

1. Retrieval isn't influence — a `Read` proves bytes entered context, not
   that they changed the output.
2. The brand-voice ground truth is prose with no scorable rubric.
3. The base model already produces plausibly on-brand copy without the
   repo, so a null result is ambiguous between "knowledge adds nothing"
   and "the measurement can't see it."

None of these hold for **private-fact recall**. The ground truth is an
objectively checkable string (a version number, a Coolify UUID, an
internal domain), not prose needing a rubric. And a base model asked
`cwd`-isolated, tool-less, closed-book questions about an internal
product's Coolify application UUID or its exact `SECRET_KEY` generation
command has no plausible way to produce the right string by chance —
there is nothing "on-brand" to fake. A high UNKNOWN rate in the
without-knowledge arm is not a measurement failure; it is the
contamination-immunity mechanism working exactly as designed, and this
run measured a 100% without-arm UNKNOWN rate (see Results below).

## Design

1. **Question bank** (`bank.yaml`) — hand-authored against the real
   product dossiers under
   `/Volumes/Dev/Sites/COPILOT/knowledge-copilot/02-products/04-applications/{convoco,insights-copilot}/`.
   This is the LLM-judgment step the task calls out: each question was
   chosen because its answer is a **private fact** — a version number,
   framework/stack specific, internal module name, former product name,
   internal/legacy domain, tool count, or canonical config value — not
   something a language model could produce from public knowledge or
   plausible improvisation. Every entry has:
   - `id`, `dossier`, `question`
   - `answer` — the canonical, objectively checkable string
   - `accept` — normalized-equivalent phrasing/punctuation/unit variants
   - `source` — `<dossier>/<file>:<line>`, the exact line the answer was
     read from, for auditability

   **What makes a question "private."** The bar applied while drafting:
   would base Claude, asked with no tools and no context, have any
   non-trivial chance of guessing this string correctly? Public facts
   about the products (that Convoco is a relationship-intelligence tool,
   that Insights Copilot does synthesis) were excluded even though
   they're *in* the dossiers, because a model could plausibly infer or
   hallucinate something close from the product name alone. What
   survived: Coolify UUIDs, exact `openssl` key-generation commands,
   internal module names (`force_tracking`, `TenantMiddleware`),
   deduplication thresholds (`0.85`/`0.70`), a legacy deploy platform
   (`DigitalOcean App Platform`), a former product name
   (`conversations-copilot`), and internal/legacy domains. Two candidate
   questions were dropped during drafting because they weren't actually
   private: "what does Convoco do" (guessable from the name) and "is
   Insights Copilot's backend written in Python" (guessable from the
   `.py` file paths visible in any partial context).

2. **Harness** (`run.py`, stdlib) — for each question, two arms via
   headless `claude -p <prompt> --model sonnet`:
   - **`without`** — `cwd` is a **fresh, empty `tempfile.TemporaryDirectory`**
     created per call. Prompt: *"Answer this question about the product
     `<dossier>` in <=10 words. If you do not know, say UNKNOWN. No
     tools. Question: `<question>`"*. No `CLAUDE.md`, no repo file, no
     tool is reachable even if the model wanted one.
   - **`with`** — identical empty `cwd`; the prompt is prefixed with the
     full text of the **one dossier file** `source` cites for that
     question: *"Using this reference document: `<file content>` ...
     `<same question tail>`"*. The knowledge is delivered as prompt
     content, not as ambient repo context — this isolates "does the fact
     change the answer when supplied" from "does having a bigger cwd
     change the answer," which is a different (and messier) question.

   Both arms run through the same `subprocess.run(..., timeout=120)`
   call; a timeout or non-zero exit is recorded as an `error` verdict and
   the run continues — one bad call never aborts the bench. Every raw
   call (full prompt char count, stdout, stderr tail, duration, verdict)
   is written to `output/bench_knowledge_qa-runs/<UTC stamp>/<id>__<arm>.json`
   for audit. Up to 4 calls run concurrently
   (`concurrent.futures.ThreadPoolExecutor`); `--concurrency` overrides.

3. **Scoring** — normalized containment match: lowercase, strip every
   non-alphanumeric character, collapse whitespace, then check whether
   the question's `answer` (or any `accept[]` variant, similarly
   normalized) is a substring of the normalized response. If no variant
   matches, the response is checked against a small UNKNOWN-marker list
   (`unknown`, `do not know`, `not sure`, ...) before falling back to
   `incorrect`. Per arm: `correct` / `incorrect` / `unknown` / `error`
   counts, `accuracy` (correct/total), `accuracy_excl_errors`
   (correct/(total-error)), `unknown_rate`. The headline is
   `accuracy_with`, `accuracy_without`, `delta = with - without`, split
   overall and per dossier.

   **Known scoring limitation, stated honestly:** containment matching on
   a short bare number (e.g. a two-digit version) has a real, if small,
   false-positive risk — a response could contain that digit sequence
   incidentally. The bank mitigates this by preferring qualified answer
   strings (`"PostgreSQL 16"` rather than `"16"`) as the primary `answer`,
   with bare-number forms only in `accept[]`. This was not empirically an
   issue in the run below (0 `incorrect` verdicts recorded — every
   response was either a clean match or UNKNOWN), but it remains a
   structural risk worth flagging for anyone extending the bank with more
   numeric-only facts.

4. **Output** — the same schema-versioned envelope the other `cse-bench`
   collectors use (`schema_version`, `collector`, `generated_at`,
   `host_scope`, `metrics`, `errors`), written to
   `tools/cse-bench/output/bench_knowledge_qa-<UTC stamp>.json` and
   `bench_knowledge_qa-latest.json`. `metrics` carries the full bank size
   and dossier list, run parameters (model, limit, arm filter,
   concurrency, timeout), the headline/by-arm/by-dossier breakdown, and a
   `definitions` block restating what each field means (same convention
   `collectors/velocity.py` uses) so no consumer has to read this file to
   know what a number means.

## Re-run it

```bash
cd tools/cse-bench/benches/knowledge_qa

# Full bank (49 questions x 2 arms = 98 claude -p calls, ~2 minutes at
# the default concurrency of 4 on this machine)
python3 run.py

# Smaller / faster run, balanced across dossiers
python3 run.py --limit 30

# One arm only (e.g. to sanity-check the without-arm's UNKNOWN rate alone)
python3 run.py --arm without --limit 10

# Preview the exact prompts without spending any calls
python3 run.py --dry-run

# Different model / concurrency / timeout
python3 run.py --model sonnet --concurrency 4 --timeout 120
```

Requires the `claude` CLI on `PATH` (verified working via `claude -p
"..." --model sonnet` on this machine) and read access to
`/Volumes/Dev/Sites/COPILOT/knowledge-copilot` (override with
`--dossier-root` if that repo moves; defaults to `$CC_KNOWLEDGE_REPO` when
set, else the hardcoded path above).

## Results — 2026-07-12 live run

Bank: **49 questions across 2 dossiers** (convoco: 24, insights-copilot:
25). Model: `sonnet`. Concurrency: 4. Full envelope:
[`output/bench_knowledge_qa-latest.json`](../../output/bench_knowledge_qa-latest.json).

| Arm | Accuracy | Correct | Unknown | Incorrect | Error |
|-----|----------|---------|---------|-----------|-------|
| **without** (empty cwd, no reference) | **0.0%** | 0/49 | 49/49 (100%) | 0 | 0 |
| **with** (reference document in prompt) | **97.96%** | 48/49 | 1/49 | 0 | 0 |

**Delta: +0.9796 (97.96 percentage points).**

Per dossier (`with` arm): convoco 23/24 (95.83%), insights-copilot 25/25
(100%). Both dossiers' `without` arm scored 0% (100% UNKNOWN) —
contamination immunity held identically across both.

The single `with`-arm miss (`convoco-12`, "what major version of
SQLAlchemy does Convoco's backend use") is not a harness bug: the model
was given the reference text ("SQLAlchemy 2 async, asyncpg, Alembic
migrations...") and answered `UNKNOWN` rather than guess — a real,
conservative instance of the "if you do not know, say UNKNOWN" prompt
instruction, visible in the raw record at
`output/bench_knowledge_qa-runs/20260712T175029Z/convoco-12__with.json`.

## Extending the bank

**Coverage today: 2 dossiers (convoco, insights-copilot).** The task's P2
acceptance bar is **≥3 dossiers** — this run does not yet clear it; stated
honestly rather than rounded up. To extend:

1. Pick a new dossier under
   `knowledge-copilot/02-products/04-applications/<product>/` (or any
   other Knowledge Copilot dossier tree).
2. Read its `00-overview.md` through `07-decisions.md` (or equivalent)
   and mine 20-25 private facts using the "would base Claude have any
   real chance of guessing this?" bar in Design §1 above — prefer version
   numbers, internal module/class names, canonical config/threshold
   values, UUIDs, former names, and internal/legacy domains over
   anything inferable from the product's public name or purpose.
3. Append entries to `bank.yaml` under a new `# --- <dossier> ---`
   comment block, following the existing schema exactly (`id` must stay
   globally unique; `source` must resolve to a real
   `<dossier>/<file>:<line>` under the dossier root).
4. Re-run `python3 run.py --dry-run` first — it builds every prompt
   (resolving every `source` citation against the real dossier files) and
   reports failures without spending a single `claude` call.
5. Run live: `python3 run.py`.

No changes to `run.py` are needed to add a dossier or grow the bank — it
reads whatever `bank.yaml` contains.
