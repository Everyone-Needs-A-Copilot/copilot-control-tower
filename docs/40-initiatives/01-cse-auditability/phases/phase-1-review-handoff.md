# Phase 1 — Adversarial Review Handoff

> For: an independent developer reviewing the Phase 1 falsification probe
> Findings under review: [`phase-1-findings.md`](phase-1-findings.md)
> Harness: [`tools/cse-audit/`](../../../../tools/cse-audit/)
> Prepared: 2026-07-12

## Your job

**Try to prove the findings wrong.** Not to confirm them, not to "sanity check"
them, not to sign off. The probe made 18 claims about a system its own author
built. Nobody has audited the probe. That is limitation #8 of the findings
document, and closing it is your entire remit.

Concretely, you are looking for three things:

1. **A finding that is simply false** — the evidence doesn't say what it's
   claimed to say.
2. **A finding that is true but load-bearing on a bad definition** — where a
   different, equally defensible operational definition flips the verdict.
   (F-5 already demonstrates this failure mode inside the report; assume there
   are more.)
3. **A finding that is true, but flattering** — where the honest version is worse
   or more uncertain than stated.

**A review that overturns nothing is a suspicious review.** The report contains
8 `FALSIFIED` verdicts produced in about a day. The base rate for a first pass
being entirely correct is not high.

## The 60-second context

The **Copilot Solutioning Ecosystem (CSE)** is four products the owner built:

| Product | What it is | Where |
| --- | --- | --- |
| **Claude Copilot / Codex Copilot** | The agent framework — 15 specialists, a protocol, hooks | `/Volumes/Dev/Sites/COPILOT/claude-copilot`, `.../codex-copilot` |
| **Knowledge Copilot** | The shared knowledge repo (also aliased `shared-docs`) | `.../knowledge-copilot` |
| **CLI Copilot** | A 208-command Python CLI (`copilot`) | `.../cli-copilot` |
| **Copilot Control Tower** | A macOS menu-bar supervisor (this repo) | `.../copilot-control-tower` |

The initiative ([`../README.md`](../README.md)) exists because the owner asked a
fair question — *"how do I prove any of this is useful?"* — and the honest answer
turned out to be that almost none of it had ever been checked.

**Note the conflict of interest you are correcting for: the auditor and the
audited have the same author.** Every incentive in this report ran toward finding
something dramatic. Weigh accordingly.

## Reproduce before you review

Everything below is read-only. None of it mutates the ecosystem.

```bash
cd /Volumes/Dev/Sites/COPILOT/copilot-control-tower

# The transcript-mining harness (F-3..F-8). Streams ~/.claude/projects/**/*.jsonl.
python3 tools/cse-audit/run_probe.py            # writes tools/cse-audit/output/report.txt
python3 tools/cse-audit/product_usage.py -v     # F-11, F-16

# F-1 — the hook that was disabled the day it shipped
cd /Volumes/Dev/Sites/COPILOT/claude-copilot
git show 23c02c0 -- .claude/settings.json
python3 -c "import json;print(json.load(open('.claude/settings.json'))['hooks']['PreToolUse'])"

# F-2 — enforcement is wired in exactly one repo
R=/Volumes/Dev/Sites/COPILOT
for p in "$R"/*/; do [ -e "$p.claude/agents" ] && echo "$(basename "$p")"; done | wc -l   # -> 27
find "$R" -maxdepth 3 -name settings.json -path '*/.claude/*' -exec grep -l PreToolUse {} \;  # -> 1

# F-13 — the only claim that passed. RE-RUN THIS; I did not.
cd /Volumes/Dev/Sites/COPILOT/cli-copilot && python3 -m pytest --cov

# F-14 — the verb that does not exist
/opt/homebrew/bin/copilot doctor    # -> no such command
/Users/pabs/.local/bin/cc --help    # -> doctor/resolve/freshness/... all present
```

**Two traps in the environment that will waste your time if you don't know them:**

- **`copilot` is a shell alias for `cd /Volumes/Dev/Sites/COPILOT`.** Typing
  `copilot doctor` interactively changes directory and swallows the argument. Use
  absolute paths.
- **`cc` is four different things** — claude-copilot's tool (twice on PATH), and
  `/usr/bin/cc`, the C compiler. See F-14. Any grep for `cc` in shell commands
  will over-count by ~3x if it matches substrings rather than command position.

## The operational definitions — challenge these first

Every `PROBE`-confidence finding rests on a definition that was **inferred, not
recovered**. The original April 2026 diagnostic's script does not exist; its
numbers (delegation 6%, protocol 3.5%, 671 turns/session) were reverse-engineered
from prose. **If a definition is wrong, the finding built on it is worthless.**

| Term | Definition used | Where it's fragile |
| --- | --- | --- |
| **turn** | a `type:"user"` record, `isSidechain≠true`, `isMeta≠true`, non-`tool_result` content | The probe measures **6.0 turns/session** median; April claimed **671**. A ~100× gap means one of these is not measuring what the other measured. **We assumed ours is right. Check that assumption.** |
| **delegation rate** | subagent-executed tool calls ÷ (main + subagent tool calls) | An *event-share* definition gives 3.1%; a *tool-share* definition gives 40.5%. **Both are defensible. This is F-5.** Is there a third definition that is more obviously correct than either? |
| **protocol declaration** | first non-thinking text block starts with `[PROTOCOL` | Does the April doc's 3.5% mean the same thing? Unrecoverable. |
| **"Sonnet for ~94% of work"** | tried 3 denominators: main-session messages, all messages, token share | **Is there a fourth reading under which 94% is true?** If you find one, F-3 weakens substantially. It is currently the report's most confident finding. |
| **CLI invocation** | binary name in *command position* of a Bash call, not substring | Excludes 79 ambiguous `cc` matches (~8%). They were dropped, not folded in favorably — but verify that. |

## What to attack, ranked

Ordered by **(how load-bearing) × (how likely I'm wrong)**. Start at the top.

### 1. F-12 (`CEILING`) — the most attackable finding in the report

This is the only verdict that is an **argument**, not a measurement. It claims
Knowledge Copilot's efficacy is *structurally unlearnable* — that no benchmark
can determine whether knowledge improves output, because retrieval isn't
influence, the voice ground truth is prose rather than a rubric, and base Claude
writes plausibly on-brand copy anyway.

**If you can design a measurement that gets around all three, the finding
collapses.** The report itself concedes one crack: the *factual* half (do agents
get product facts right?) **is** answerable against the product dossiers. Is the
voice half really as closed as claimed, or did the auditor reach for
"structurally impossible" when it meant "hard"?

**This one matters most, because a CEILING verdict tells the owner to stop
trying.** If it's wrong, it will have talked him out of something achievable.

### 2. F-16 — and the hole I know about and did not close

The report says CLI Copilot was used in 19.5% of sessions, then **refutes its own
number**: the CLI is a *terminal* tool, shell usage leaves no transcript, and the
CLI has zero logging by charter. So 19.5% is a floor and "14 dead services" may
be wrong.

**But there is a data source I never mined: `~/.zsh_history`.**

That is very likely to contain months of real `copilot ...` invocations, from
before the transcript corpus even begins. **It could settle F-16 outright, and it
could overturn the report's most quotable claim — that most of the CLI is dead
surface.** I did not look. That's the single highest-value thing you can do.

### 3. F-11 — a likely counting error, and it's mine

"95.6% of the knowledge repo has never been read" counts **`Read` tool calls**
against knowledge paths.

But the usage archaeology also found: ***no native `Grep`/`Glob` tool calls exist
anywhere in the corpus — file search happens via `Bash`.*** So if an agent ran
`cat`, `grep`, `rg`, or `head` against a knowledge file through `Bash`, **that
read may never have been counted.**

**If Bash-mediated reads are uncounted, the 95.6% figure is inflated, possibly
badly.** Check `product_usage.py` and find out. This is a concrete, probable bug
in a headline number.

### 4. F-13 — the only good news, and I never verified it

A subagent ran CLI Copilot's test suite and reported 1,588 passing, 53% coverage.
**I did not re-run it.** It is the only `VERIFIED` verdict in the report and the
only claim in the whole CSE that passed. **Re-run it.** If it doesn't reproduce,
the report has no good news at all, and that is a materially different document.

### 5. F-17 — a claim sourced from a changelog, not a test

The assertion that Claude Code auto-defers MCP tool schemas above **10% of the
context window** comes from a changelog line, not from an experiment. The whole
"the CLI's advantage is capped" conclusion rests on it. **Verify the threshold
empirically, or downgrade the finding.**

### 6. F-3 — most confident, so most worth trying to break

Main-session turns are 92.5% Opus, 0% Sonnet; all-message share is 57.7% Sonnet;
token share ~20.5%. The claim is 94%. **Find a fourth denominator under which the
claim is true.** If one exists, the report's most robust finding becomes another
F-5 (definition-dependent, unscoreable) — which would be a significant result in
its own right.

### 7. F-9, F-10 — verified by an agent, not by me

"Nothing loads the knowledge extensions" and "the glossary file doesn't exist"
were established by a subagent reading source. **Re-verify independently.** Is
there a loader somewhere nobody looked — a plugin, a skill, a `SessionStart` hook
in a repo that wasn't scanned?

### Already checked; don't re-spend time here

- **Is there a *global* `PreToolUse` hook that would make F-1/F-2 wrong?** No.
  `~/.claude/settings.json` has only `Stop` and `UserPromptSubmit`.
  `settings.local.json` does not exist. Checked 2026-07-12.
- **Is there a second COPILOT tree?** No. `/Users/pabs/Sites/COPILOT` and
  `/Volumes/Dev/Sites/COPILOT` are **the same tree** (`/Users/pabs/Sites` is a
  symlink). An earlier version of this analysis nearly double-counted.
- **The 27 figure in F-2** = 26 real `.claude/agents/` directories + 1 symlink
  (`research-copilot` → `knowledge-copilot`). A `find -type d` gives 25 and is
  wrong; `[ -e ]` gives 27 and is right.

## What would change my mind

Stated per finding, so the review has a target rather than a vibe.

| Finding | Overturned by |
| --- | --- |
| **F-1** hook disabled day one | Any live enforcement path that fires on `Read`/`Edit`/`Agent` — a plugin, a global hook, an `UserPromptSubmit` script that inspects tool history |
| **F-2** wired in 1 of 27 | A second enforcement mechanism outside `.claude/settings.json` |
| **F-3** model tier false | A fourth defensible denominator giving ~94% Sonnet |
| **F-4** protocol rate never recovered | Evidence that April's 3.5% counted something different enough that the comparison is void |
| **F-5** delegation unscoreable | A definition so obviously correct that the ambiguity dissolves |
| **F-6** permanently closed | **Any** pre-2026-06-09 transcripts anywhere — a backup, an archive, a Time Machine snapshot. This would be the best possible outcome of your review |
| **F-8** 94% = cache-read share | Finding the figure's actual provenance — a script, a commit, a note |
| **F-9/F-10** knowledge mechanisms inert | An extension loader anywhere; the glossary file existing under another name |
| **F-11** 95.6% never read | **Bash-mediated reads being uncounted** (likely — see above) |
| **F-12** CEILING | A measurement design that beats all three obstacles |
| **F-13** testable ✅ | The suite not reproducing |
| **F-14** CT doesn't orchestrate CLI Copilot | Any Control Tower code path invoking `/opt/homebrew/bin/copilot` |
| **F-16** usage unknown | **`~/.zsh_history`** giving a real number |
| **F-17** advantage capped | The 10% deferral threshold being wrong or inapplicable |

## Traps — please don't do these

- **Don't fix anything.** This is a review, not a remediation. If the hook is
  broken, say so; do not repair it. The owner has not yet decided which claims
  should survive, and fixing a mechanism that supports a claim he may delete is
  wasted work.
- **Don't soften a null result.** "The delegation rate did not improve" is the
  most useful sentence available. It does not need a silver lining.
- **Don't treat the report's confidence tiers as trustworthy.** `DIRECT` means
  the author re-ran it; it does not mean it's right.
- **Don't audit the *products'* code quality.** Out of scope. The question is
  whether the *claims* are true, not whether the code is good.
- **Beware the pre-registration hole.** These findings were produced **without a
  claims register** — definitions were chosen after seeing the data. That is a
  known, admitted violation of the initiative's own V-2 rule. **It means every
  verdict here is provisional.** Do not let the report's confident tone override
  that.

## Deliverable

A markdown document in this directory, named `phase-1-review-<yourname>.md`, with:

1. **A verdict per finding** — `UPHELD` / `OVERTURNED` / `WEAKENED` /
   `NOT REVIEWED`, with the evidence.
2. **Anything you found that the probe missed.** New findings are welcome and
   expected.
3. **Your own limitations section.** Same standard the report holds itself to.
4. **A blunt answer to one question:** *is this report trustworthy enough to base
   product decisions on?* The owner is deciding whether to delete claims — and
   possibly whole products — on the strength of it. If it isn't solid enough to
   carry that weight, **say so plainly.** That is the most valuable outcome this
   review can produce.

Do not soften it. The whole initiative exists because nobody said the hard thing
early enough.
