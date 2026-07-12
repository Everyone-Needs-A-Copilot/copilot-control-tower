# Phase 1 — Falsification Probe: Findings

> Run: 2026-07-11 · Corpus: `~/.claude/projects/**/*.jsonl` (113 sessions with
> metrics, 51 projects) + `~/.claude/stats-cache.json` + git history of
> `claude-copilot`
> Harness: `probe/` (`run_probe.py`, `session_metrics.py`, `jsonl_utils.py`,
> `framework_registry.py`, `stats_cache_analysis.py`, `corpus_scan.py`)

## Read this first: this probe violated the initiative's own V-2 rule

**These findings were not pre-registered.** `claims.yaml` does not exist yet.
The probe chose its own operational definitions *after* seeing the corpus, which
is exactly the freedom V-2 exists to remove.

That does not make the findings wrong. It means **they carry the weakest
evidentiary status this initiative will ever accept**, and they must be re-run
against a pre-registered register before any of them are quoted anywhere
outside this document. The `FALSIFIED` verdicts below are stated with that
caveat attached, not in spite of it.

Recording this is not throat-clearing. An audit whose first act is to exempt
itself from its own rules has already failed.

## Confidence tiers used below

| Tier | Meaning |
| --- | --- |
| **DIRECT** | Re-run by the session author against live files and git history. Reproducible in one command. |
| **PROBE** | Computed by the probe harness from the transcript corpus, using an operational definition the probe *inferred*. Plausible, unaudited. |
| **HYPOTHESIS** | A pattern worth chasing. Not evidence. |

---

## F-1 — The delegation enforcement was disabled the day it shipped · FALSIFIED · DIRECT

**Claim under test.** `docs/10-architecture/04-framework-restructure-2026-04.md:334`
— the hooks close the delegation gap and "cannot be silently bypassed."

**Evidence.**

- `20097d9` (2026-04-22) — *"restructure framework for mechanical delegation
  enforcement and model-tier inversion (v4.0.0)"*. Ships `PreToolUse` with
  matcher `Bash|Read|Edit|Agent`.
- `23c02c0` (2026-04-22, **same day**) — *"resolve hook deadlock — Bash-only
  PreToolUse matcher"*:

  ```diff
  -        "matcher": "Bash|Read|Edit|Agent",
  +        "matcher": "Bash",
  ```

- Live `claude-copilot/.claude/settings.json` today: `PreToolUse` matcher is
  still `Bash`.

**Verdict.** The hook built to stop the main session from doing `Read`/`Edit`
work instead of delegating **has never once fired on `Read`, `Edit`, or
`Agent`.** The deadlock was resolved by removing the enforcement, not by fixing
it. The claim that it "cannot be silently bypassed" is false: it is bypassed by
default, for every tool it was built to police.

**Re-run.** `git show 23c02c0 -- .claude/settings.json`

---

## F-2 — The framework is installed as documentation, not as a mechanism · FALSIFIED · DIRECT

**Claim under test.** That the framework's mechanical enforcement applies across
the ecosystem.

**Evidence.** Of **27** repos under `/Volumes/Dev/Sites/COPILOT/` with a
`.claude/agents/` directory present, **1** has `PreToolUse` registered in
`.claude/settings.json` — `claude-copilot` itself. Every other framework-bearing
repo (`copilot-control-tower`, `convoco`, `insights-copilot`, `cli-copilot`, …)
carries the agent definitions and **no enforcement at all**.

**Verdict.** In 26 of 27 repos, the framework is a set of markdown files. The
mechanism it claims does not exist there.

---

## F-3 — The model-tier claim is false under every available measure · FALSIFIED · PROBE

**Claim under test.** `04-framework-restructure-2026-04.md:172` — *"Sonnet for
~94% of work; Opus reserved for design/architecture."*

**Evidence.** Three independent denominators, all pointing the same way:

| Denominator | Sonnet share | Opus share | n |
| --- | --- | --- | --- |
| Main-session assistant messages | ~0% | **92.5%** | 16,816 |
| All assistant messages (main + subagent) | **57.7%** | 33.9% | 64,228 |
| Token share (`stats-cache.json`, post-hook) | **20.5%** (median) | — | 60 days |

**Verdict.** The claim is 94%. The three defensible readings give ~0%, 57.7%,
and 20.5%. **It is falsified under all of them**, and the second half of the
claim — that Opus is *reserved for design* — is refuted by Opus running 33.9% of
all turns and 92.5% of orchestrator turns, which are overwhelmingly not design
work. The model-pinning launcher is not in use.

This finding is the most robust in the report: it reads a literal `model` field
and requires almost no inference.

---

## F-4 — The protocol-declaration rate did not recover · FALSIFIED (weakly) · PROBE

**Claim under test.** That the hooks fixed the 3.5% protocol-declaration rate
diagnosed in April.

**Evidence.**

| Definition | Median | Mean | n |
| --- | --- | --- | --- |
| All main-session turns | 0.8% | 3.6% | 101 |
| First assistant message per user turn (strict) | **0.0%** | 0.2% | 78 |

By ISO week, post-hook: 1.7% · 0.5% · 1.4% · 0.0% · 1.2%. Flat, near zero, no
trend.

**Verdict.** The rate is **at or below** the 3.5% that motivated the entire
restructure. Marked *weakly* falsified only because the April figure's own
definition is unrecoverable — see F-6.

---

## F-5 — Delegation rate is definition-dependent, and therefore currently untestable · UNTESTABLE · PROBE

**Evidence.** The same corpus yields:

- **Tool-share** definition: median **40.5%** (IQR 0.0–85.2, n=95)
- **Event-share** definition: median **3.1%** (IQR 0.0–14.4, n=95)

April's baseline was 6%. Under one definition the framework looks like a large
improvement; under the other it looks *worse than baseline*. **Both definitions
are defensible from the sentence as written.**

**Verdict.** This is not a measurement problem. It is a claim that was never
operationalized. It cannot be scored until `claims.yaml` fixes the definition —
and it must be fixed *before* the next run, not after. **This finding is the
single clearest argument for why Phase 0 precedes everything.**

---

## F-6 — The before/after comparison is permanently closed · UNTESTABLE · DIRECT

**Evidence.** Earliest raw transcript on disk: **2026-06-09**. Hooks shipped:
**2026-04-22**. There are **zero** pre-intervention transcripts.

The only artifact spanning the cutover is `stats-cache.json`, a daily aggregate
with no message-level content — it cannot compute delegation rate or protocol
rate at any point in time, before or after.

**Verdict.** "Did the hooks improve delegation?" is **permanently unanswerable**
from this machine's evidence. Not hard — closed. The data was pruned before
anyone thought to ask.

Also unrecoverable for the same reason: April's "671 turns/session" figure. The
probe measures a median of **6.0** turns/session — a ~100× gap that indicates
the two are counting different things entirely. Without the April script, the
definition cannot be recovered. **This is a definitional incompatibility, not a
finding.**

**Consequence, and the most urgent action in this initiative:** every day
without transcript retention forecloses another question permanently.

---

## F-7 — The natural control group points the wrong way · INCONCLUSIVE · PROBE

Cross-sectional, within the post-hook window (not causal — see limitations):

| Cohort | n | Delegation (tool-share) | Protocol rate | Named-specialist share |
| --- | --- | --- | --- | --- |
| Hooks active (`claude-copilot` only) | 8 | 84.4% | 1.4% | 82.4% |
| Agents only, no hooks | ~80 | **27.8%** | 0.5% | 85.6% |
| No framework | ~13 | **53.1%** | 2.0% | **4.3%** |

**Read carefully.** Projects with *no framework at all* delegate **more**
(53.1%) than projects with the framework installed but no hooks (27.8%). What
the framework demonstrably changes is **who you delegate to** — named
specialists (85.6%) versus Claude Code's built-in generic agents (4.3%) — not
**whether** you delegate.

**Verdict.** Inconclusive, and heavily confounded: the hooks-active cohort is
n=8 and is 100% `claude-copilot` meta-work. But the direction is unflattering
and it must not be quietly dropped. Whether delegating to *named specialists*
beats delegating to *generic agents* is precisely a Tier-B efficacy question,
and it is **unmeasured**.

---

## F-8 — The "~94% less context" figure may be a misattributed caching artifact · HYPOTHESIS

**Not a finding. A lead.**

The claim (`claude-copilot/README.md:114`) is *"~94% less context."* It has no
script, no dataset, and no run behind it anywhere in the codebase.

The probe measured **cache-read share of context tokens (main session): median
93.6%** (IQR 86.4–96.7, n=99).

93.6% and "~94%" is a coincidence worth chasing. **If** the figure originated as
cache-read share, then it measures Claude Code's prompt caching — a property of
the harness, present with or without the framework — and attributing it to the
agent framework is not merely unprovenanced but **wrong**.

**Action.** The provenance hunt in Phase 0 must resolve this. Per the initiative's
Target Outcomes, the figure gets provenance or it gets deleted. There is no third
option, and this hypothesis makes deletion substantially more likely.

---

## Limitations — stated, not buried

1. **Not pre-registered.** See the top of this document. Definitions were chosen
   after seeing the data.
2. **No pre-intervention data.** Every comparison here is cross-sectional or
   post-only. Nothing in this report is causal.
3. **Inferred definitions.** "Turn," "delegation," and "protocol declaration"
   were reverse-engineered from the April doc, not recovered from its code. The
   probe flags each guess in its docstrings. F-3 depends least on this; F-4 and
   F-5 depend most.
4. **Cohort confounding.** The hooks-active cohort (n=8) is entirely
   `claude-copilot` meta-work — a different task mix from every other repo.
   F-7's cohorts are not exchangeable.
5. **Composition drift.** Project mix and task mix changed across the window.
   The `stats-cache` pre/post comparison (messages and tool calls per
   session-day both *rose* post-hook) uses daily-active-session-count as its
   unit, which is a poor proxy for sessions started. Directional color only.
6. **The probe audited the framework; nobody has audited the probe.** Its
   operational definitions deserve the same skepticism this report applies to
   the CSE. That audit has not happened.

## What this changes

1. **Retention first.** A transcript archive job, before anything else. It is the
   only item where delay is irreversible (F-6).
2. **A hook self-test** — `test_pretool_hook_fires_on_read`. One check that would
   have caught F-1 on 2026-04-22 and every day since. The matcher rotted for
   exactly one reason: nothing tested that it fired.
3. **Then Phase 0.** F-5 and F-8 are unanswerable without the register, and F-3
   and F-4 cannot be quoted until they are re-run pre-registered.

**The pattern beneath F-1, F-4, and F-8 is one pattern, not three:** in each
case the artifact that *represents* the work was produced and the work was not —
a `settings.json` that looks like enforcement, an "After" column that looks like
a result, a number that looks like a measurement.

The CSE is a system for producing convincing specification artifacts with AI.
Its characteristic failure is producing convincing artifacts unbacked by the
thing they represent — which is the failure mode of the AI it orchestrates.
**The framework has the defect it was built to prevent.** That is the finding
that matters, and it is why the fix must be mechanical rather than cultural.
