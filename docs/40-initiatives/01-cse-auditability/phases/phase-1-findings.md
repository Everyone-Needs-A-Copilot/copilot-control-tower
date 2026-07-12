# Phase 1 — Falsification Probe: Findings

> Run: 2026-07-11 / 2026-07-12 · Scope: **all four CSE products**
> Corpus: `~/.claude/projects/**/*.jsonl` (113 sessions, 51 projects) +
> `~/.claude/stats-cache.json` + git history + live source of all four repos
> Harness: [`tools/cse-audit/`](../../../../tools/cse-audit/)

## Read this first: this probe violated the initiative's own V-2 rule

**These findings were not pre-registered.** `claims.yaml` does not exist yet, so
the probe chose its own operational definitions *after* seeing the data — exactly
the freedom V-2 exists to remove.

That does not make them wrong. It means **they carry the weakest evidentiary
status this initiative will ever accept**, and must be re-run against a
pre-registered register before being quoted outside this document.

An audit whose first act is to exempt itself from its own rules has already
failed. So this is recorded at the top, not in a footnote.

## Verdicts and confidence

| Verdict | Meaning |
| --- | --- |
| `VERIFIED` | Checked; the claim held. |
| `FALSIFIED` | Checked; the claim did not hold. |
| `UNTESTABLE` | Cannot be scored **as stated** — usually because it was never operationalized. |
| `CEILING` | **Structurally unlearnable as currently built.** Not "not yet measured" — no amount of effort fixes it without changing the product. |
| `INCONCLUSIVE` / `HYPOTHESIS` | Suggestive; not evidence. |

| Confidence | Meaning |
| --- | --- |
| **DIRECT** | Re-run by the session author against live files/git. Reproducible in one command. |
| **PROBE** | Computed by the harness using an operational definition it *inferred*. Plausible, unaudited. |

**Tally: 8 FALSIFIED · 1 VERIFIED · 3 UNTESTABLE · 1 CEILING · 1 INCONCLUSIVE ·
1 HYPOTHESIS.**

---

# Part I — Claude / Codex Copilot (the framework)

## F-1 — The delegation enforcement was disabled the day it shipped · FALSIFIED · DIRECT

**Claim.** `04-framework-restructure-2026-04.md:334` — the hooks close the
delegation gap and "cannot be silently bypassed."

- `20097d9` (2026-04-22) — *"restructure framework for mechanical delegation
  enforcement and model-tier inversion (v4.0.0)"*. Ships `PreToolUse` with
  matcher `Bash|Read|Edit|Agent`.
- `23c02c0` (2026-04-22, **same day**) — *"resolve hook deadlock"*:

  ```diff
  -        "matcher": "Bash|Read|Edit|Agent",
  +        "matcher": "Bash",
  ```

- Live `settings.json` today: still `Bash`.

**The deadlock was resolved by removing the enforcement, not by fixing it.** The
hook built to stop the main session doing `Read`/`Edit` work instead of
delegating **has never once fired on `Read`, `Edit`, or `Agent`.**

Re-run: `git show 23c02c0 -- .claude/settings.json`

## F-2 — The framework is installed as documentation, not as a mechanism · FALSIFIED · DIRECT

Of **27** repos carrying `.claude/agents/`, **1** has `PreToolUse` registered —
`claude-copilot` itself. In the other 26, including this one, the framework is a
set of markdown files with nothing behind them.

## F-3 — The model-tier claim is false under every denominator · FALSIFIED · PROBE

**Claim.** `04-framework-restructure-2026-04.md:172` — *"Sonnet for ~94% of work;
Opus reserved for design/architecture."*

| Denominator | Sonnet | Opus | n |
| --- | --- | --- | --- |
| Main-session assistant messages | ~0% | **92.5%** | 16,816 |
| All messages (main + subagent) | **57.7%** | 33.9% | 64,228 |
| Token share (`stats-cache`, post-hook) | **20.5%** median | — | 60 days |
| **Claim** | **94%** | *"reserved"* | — |

All three readings are defensible from the sentence as written. **The claim is
falsified under all three**, and "Opus reserved for design" is refuted by Opus
running 92.5% of orchestrator turns, which are overwhelmingly not design work.
The model-pinning launcher is not in use.

Most robust finding in the report: it reads a literal `model` field.

## F-4 — The protocol-declaration rate never recovered · FALSIFIED (weakly) · PROBE

The problem that motivated the restructure was **3.5%**. Measured post-hook:
**0.8%** median across all main-session turns (n=101); **0.0%** under the strict
definition (n=78). By ISO week: 1.7 · 0.5 · 1.4 · 0.0 · 1.2 %. Flat, no trend.

*Weakly* falsified only because April's own definition is unrecoverable (F-6).

## F-5 — Delegation rate is definition-dependent, therefore unscoreable · UNTESTABLE · PROBE

| Definition | Median | IQR | vs April baseline (6%) |
| --- | --- | --- | --- |
| Tool-share | 40.5% | 0.0–85.2 | far above |
| Event-share | 3.1% | 0.0–14.4 | **below** |

Under one defensible definition the framework looks like a large improvement.
Under the other it looks *worse than the baseline it was built to fix*.

**This is not a measurement problem. It is a claim that was never operationalized
— and it is the clearest single argument for why the register must precede every
tool.**

## F-6 — The before/after comparison is permanently closed · UNTESTABLE · DIRECT

Earliest transcript: **2026-06-09**. Hooks shipped: **2026-04-22**. **Zero**
pre-intervention transcripts. The only artifact spanning the cutover is a daily
aggregate with no message-level content.

"Did the hooks improve delegation?" is not hard. It is **unanswerable**. The
evidence was pruned before anyone thought to ask.

Also unrecoverable: April's "671 turns/session." The probe measures a median of
**6.0**. A ~100× gap means the two count different things; without April's script
the definition is gone. **A definitional incompatibility, not a finding.**

**Consequence: transcript retention is the only action in this initiative where
delay is irreversible.**

## F-7 — The natural control group points the wrong way · INCONCLUSIVE · PROBE

Cross-sectional, post-hook window only. **Not causal.**

| Cohort | n | Delegation | Protocol | Named specialists |
| --- | --- | --- | --- | --- |
| Hooks active (`claude-copilot`) | 8 | 84.4% | 1.4% | 82.4% |
| Agents only, no hooks | ~80 | **27.8%** | 0.5% | 85.6% |
| No framework at all | ~13 | **53.1%** | 2.0% | **4.3%** |

Projects with **no framework** delegate *more* (53.1%) than projects with the
framework but no hooks (27.8%). What the framework demonstrably changes is **who**
you delegate to — named specialists vs. built-in generic agents — not **whether**
you delegate.

Heavily confounded (hooks-active cohort is n=8, all `claude-copilot` meta-work).
The direction is unflattering and is not being dropped. Whether named specialists
beat generic agents is a Tier-B efficacy question, and it is **unmeasured**.

## F-8 — The "~94% less context" figure may be a misattributed caching artifact · HYPOTHESIS

The claim (`claude-copilot/README.md:114`) has **no script, no dataset, no run**
anywhere in the codebase.

The probe independently measured **cache-read share of context tokens: 93.6%
median** (IQR 86.4–96.7, n=99).

**93.6% and "~94%" is a coincidence worth chasing.** If the figure originated as
cache-read share, it measures Claude Code's *prompt caching* — a property of the
harness, present with or without the framework — and attributing it to the agent
framework would be not merely unprovenanced but **wrong**.

---

# Part II — Knowledge Copilot

**The mechanism, first, because every finding depends on it.** Knowledge is
**never injected**. `session-start.sh:117` emits the repo's **path**, not its
content — zero bytes of knowledge cross into context automatically. What actually
happens is that a *sentence inside each agent file* (`ta.md:41`, `cw.md:25`)
tells the agent to go read it, and the agent decides whether to. Consumption is
discretionary, model-mediated, and unenforced.

This is good news for measurement: usage is **fully observable**, and the
counterfactual is **clean** (point `CC_KNOWLEDGE_REPO` at an empty tree — there
is no hidden channel to control for). Knowledge Copilot is the most ablatable
product in the CSE.

Note: `copilot-control-tower` has **no `.claude/settings.json` at all**, so in
this repo not even the pointer is injected.

## F-9 — The extension system is inert · FALSIFIED · DIRECT

**Claim.** `PURPOSE.md:171` — *"Reduced context building — Extensions load
automatically."*

Five extensions are declared (`knowledge-copilot/.claude/extensions/{cw,do,ind,sd,uxd}.*.md`).
**Nothing loads them.** `~/.claude/agents/` is empty. `sync-knowledge.sh:126-127`
only checks that the manifest *exists*. The "Authentic Provocateur" voice text is
not in `cw.md` — `cw.md` carries only a pointer.

The extension system does not exist as a mechanism.

## F-10 — The glossary claim depends on a file that does not exist · FALSIFIED · DIRECT

**Claim.** `PURPOSE.md:166` — *"Proper terminology — Glossary ensures correct
language."*

The manifest resolves **227 of 228** references. The one broken reference is
`.glossary` → `03-ai-enabling/03-operations/12-shared-glossary.md`, **which does
not exist.** Of 228 refs, the single dead one is the one a claim rests on.

Related conformance state: 27 of 28 contract paths resolve; only **25 of 209**
`.md` files carry `last_updated`/`status` frontmatter (12%), so metadata-based
freshness covers ~12% of content. `copilot freshness` — the verb Control Tower's
architecture depends on — **does not exist**. The knowledge repo has **no CI, no
tests, no git hooks**.

## F-11 — Usage: one fifth of sessions; 95.6% of the corpus never read · MEASURED · PROBE

- **23 of 113 sessions (20.4%)** read knowledge. 20 of those genuinely consulted
  it from *another* product (8 from `pipeline-copilot`); 3 were authoring
  sessions.
- Of **1,722** files in the repo, **190 were ever read. 1,646 (95.6%) were never
  touched.**
- The **`/knowledge-copilot` skill has been invoked 0 times.** Ever.
- Consumption is overwhelmingly by subagents (~425 of ~460 calls) — consistent
  with the prose-instruction mechanism.

**Caveat that materially weakens this** (see Limitations): the corpus starts
2026-06-09. "Never read" means *never read in a five-week window*.

## F-12 — Knowledge efficacy has a structural ceiling · CEILING

Three independent reasons a benchmark cannot answer "does knowledge make the
output better," and **none is an effort problem**:

1. **Retrieval is not influence.** A `Read` proves bytes entered context. There
   is no citation requirement, no attribution, and no link from an output token
   back to a source file. Telemetry is off (`CC_TELEMETRY_ENABLED="False"`).
2. **The ground truth is prose, not a rubric.** The brand voice exists as
   human-readable guidance (`01-company/01-brand/02-tone-of-voice.md`), with no
   scorable rubric and no gold-standard corpus of correct outputs.
3. **The base model is contaminated.** Claude produces plausibly on-brand copy
   *without* the repo. So a null result in a voice ablation is **ambiguous between
   "knowledge adds nothing" and "the measurement cannot see it."**

Fixable only by **changing the product** (require citations; write a real rubric)
— not by measuring harder.

The *factual* half is in better shape: `ECOSYSTEM.md` and the product dossiers
are checkable factual claims, so "do agents get product facts right" **is**
answerable.

## What Knowledge Copilot claims

The consumption contract (`02-consumption-contract.md`) contains **zero benefit
statements** — confirmed. Its only "source of truth" line is about *path
stability*, not value (`:60`).

The benefit claims live in `PURPOSE.md:157-174`: *"Voice preservation"* (`:158`),
*"Consistent voice"* (`:165`), *"Proper terminology — Glossary ensures correct
language"* (`:166`), *"Extensions load automatically"* (`:171`).

**Two of the four are refuted by the mechanism itself** (F-9, F-10).

---

# Part III — CLI Copilot

`copilot-cli` v1.4.5, Python/Typer, ~35k LOC. **22** service groups
(`main.py:73-94`), **208** leaf commands.

## F-13 — "Testable" is true · **VERIFIED** · DIRECT

**Claim.** `docs/00-overview.md:11` — *"replaces separate MCP servers with one
portable, **testable** CLI."*

Run, not read: **1,588 tests pass**, 16 deselected, **53% coverage** (16,081
statements / 7,582 missed), 34.85s, 41 test files. CI at
`.github/workflows/ci.yml` — ruff check + format-check + pytest with coverage,
matrix py3.11/3.12, on push-to-main and PRs. Coverage is uneven
(`shared/approval.py` 0%, `uspto/commands.py` 39%) and E2E tests are
marker-deselected behind `COPILOT_E2E_LIVE=1`.

**This is the only claim in the entire CSE that has been checked and held.**

## F-14 — Control Tower's CLI contract names a binary that has none of its verbs · FALSIFIED · DIRECT

**Four programs share two names on this machine:**

| Name | Resolves to | What it is |
| --- | --- | --- |
| `copilot` (interactive) | alias → `cd /Volumes/Dev/Sites/COPILOT` | **a directory change** — it shadows the binary |
| `/opt/homebrew/bin/copilot` | **CLI Copilot** | 22 groups, 208 commands. Only top-level verb: `health`. |
| `cc` → `~/.local/bin/cc` (2nd copy at `/opt/homebrew/bin/cc`) | **claude-copilot's `tools/cc/`** | Has `doctor`, `resolve`, `freshness`, `repair`, `update`, `deprovision` |
| `/usr/bin/cc` | the C compiler | — |

- Control Tower's **code is correct**: it invokes `cc doctor --json`,
  `cc deprovision`, `cc update` (`src-tauri/src/cli/spawn.rs`,
  `src-tauri/src/model/deprovision.rs`) and vendors/signs the `cc` binary
  (`scripts/verify-vendored-cc.sh`).
- Control Tower's **docs are wrong**: `docs/01-architecture/cli-contract.md:17-37`
  and the project `CLAUDE.md` both say `copilot doctor/resolve/freshness/publish
  --json`. **`copilot doctor` is "no such command."**

**Consequence, and it is not a documentation nit: Control Tower does not
orchestrate CLI Copilot. It never has.** The "CLI" in its CLI contract is
claude-copilot's `cc`. CLI Copilot sits entirely outside the inheritance, sync,
and supervision model the CSE is supposedly about — a standalone 208-command CLI
wired into nothing.

## F-15 — The "versioned `--json` contract" has no version · FALSIFIED · DIRECT

`--json` is real and works (global positional flag, `main.py:37-43` →
`shared/output.py:20-28`; verified live: `copilot --json git status` emits bare
JSON). But there are **zero** occurrences of `schema_version`, `$schema`, or
`contract_version` in the package. It is an output-formatting toggle, not a
contract.

Minor, same family: the service count is stated as **17**
(`docs/00-overview.md:11`), **20** (`README.md:3`), and **20** (service index).
The code registers **22**.

## F-16 — Usage is unknown, not low — because the product records nothing about itself · MEASURED · PROBE

- **22 of 113 sessions (19.5%)** invoked it unambiguously; 30 (26.5%) including
  ambiguous bare-`copilot` calls.
- **8 of 22 service groups were ever invoked.** Usage is `discord` (253 calls) and
  `coolify` (216); `infisical`, `conv`, `db` a distant tier. **14 groups
  (`crm`, `brevo`, `n8n`, `bi`, `monitoring`, `reddit`, `uspto`, …) never
  invoked.**
- Bare `copilot` calls error **5× more often** than path-qualified ones (14.5% vs
  2.9%) — the alias collision is visible in the data, not just in the docs.

**The self-refutation, and it is load-bearing.** CLI Copilot is a *terminal* tool.
This corpus only sees invocations *from inside Claude sessions*. **Shell usage
leaves no transcript.** And the CLI itself has **zero `logging` calls** — no
invocation log, no exit-code history, no telemetry (by charter: `SOUL.md:124-127`
forbids local state).

So **19.5% is a floor, not a measurement, and "14 dead services" may be simply
wrong** — those services could be used daily from a terminal and this corpus
could not tell. The honest verdict on CLI Copilot utilization is **unknown**.

A deliberate design choice — statelessness — made the product's own value
unprovable.

## F-17 — The CLI's core advantage is bounded by the platform and offset by an uncounted cost · UNTESTABLE

The counterfactual is unusually clean: **only two real MCP servers exist**, and
**both have direct CLI twins**.

| MCP server | Tools | ≈Schema tokens | CLI twin |
| --- | --- | --- | --- |
| `nocodb-mcp` | 19 | ~3,322 | `copilot crm` |
| `postgresql-mcp` | 13 | ~2,726 | `copilot db` |

Both surfaces are runnable today. But:

- **Claude Code auto-defers MCP schemas above 10% of the context window.** So
  "one CLI beats twenty MCP servers" **can never save more than ~10% of a
  window** — the platform clamps it before the CLI can. It is a *bounded
  constant*, not a scaling argument. (At ~6k tokens, these schemas *do* load
  upfront, so the advantage is real for this machine's config — just capped.)
- **An offsetting cost is uncounted.** The CLI is only free if the model already
  knows its verb grammar, which arrives via CLAUDE.md prose or trial-and-error
  `--help` probing. Nobody has measured those tokens.

The true quantity is `min(MCP_schema_tokens, 10% × window) − CLI_grammar_cost`,
and **both terms live outside CLI Copilot's repo. You cannot measure this
product's core advantage by looking at this product.**

## What CLI Copilot claims

`SOUL.md` is dense with claims — *"one consistent command instead of wiring up a
bespoke client or MCP server per service per project"* (`:22`), *"No `--serve`
mode, no MCP server, no daemon"* (`:109`). Read carefully, these are all
**posture** claims: stateless, portable, client-not-server, uniform grammar.

**Not one is an outcome claim.** No assertion anywhere about token cost, latency,
success rate, or money saved. **"Testable" is the only falsifiable claim in the
corpus — and it is the only one that passed.**

---

# Part IV — The finding beneath the findings

## F-18 — Seven artifacts, zero mechanisms

| # | The artifact | The mechanism |
| --- | --- | --- |
| 1 | `PreToolUse` matcher | never fires on Read/Edit/Agent (F-1) |
| 2 | Restructure doc's "After" column | results never measured (F-4) |
| 3 | Knowledge extensions | *"load automatically"* — nothing loads them (F-9) |
| 4 | Glossary | *"ensures correct language"* — the file doesn't exist (F-10) |
| 5 | `task-copilot` MCP config (2 repos) | `dist/index.js` doesn't exist |
| 6 | `--json` "versioned contract" | no `schema_version` anywhere (F-15) |
| 7 | Codex parity scorecard | a template of zeros, never run |

Seven independent instances, across all four products. **This is not a pattern.
It is the operating mode.**

The CSE is a system for producing convincing specification artifacts with AI. Its
characteristic failure is producing convincing artifacts unbacked by the thing
they represent — which is **the failure mode of the AI it orchestrates**.

**The framework has the exact defect it was built to prevent.**

That is why the fix must be mechanical rather than cultural. A cultural fix — "be
more rigorous" — is the same category of thing that already failed. As the
ecosystem's own initiatives standard puts it: *a rule that isn't checked
mechanically, and checked on every commit, is not a rule. It's a wish.*

## The inversion

> **The products make claims in inverse proportion to their measurability.** The
> framework promises the most and can prove the least. The CLI promises almost
> nothing — one clause — and is the only one that delivers.

If that holds, part of the answer to *"how do I prove it's useful?"* is not a
benchmark at all. It is: **start claiming the things you can actually
demonstrate.**

---

# What is possible to learn — and what is not

| | Exists as claimed? | Actually used? | Changes behavior? | Change is good? |
| --- | --- | --- | --- | --- |
| **Claude / Codex** | ❌ F-1, F-2 | Partial — 56/113 delegate; protocol 0.8% | Learnable; control arm must be **built** | Expensive: task suite + judge |
| **Knowledge** | ❌ F-9, F-10 | 20.4%; 95.6% of files never read | **Learnable, cleanly** — empty-repo ablation | 🧱 **CEILING** (F-12) |
| **CLI Copilot** | ✅ **F-13** | **Unknown** — shell use invisible (F-16) | **Learnable today** — 2 MCP twins | Bounded by platform (F-17) |
| **Codex parity** | Manifest real; scorecard never run | — | — | Rung 1 nearly free |

**Usage is the binding constraint, not efficacy.** Measuring the quality of
knowledge that is never read, or of a CLI whose invocations aren't recorded, is a
category error. Before any efficacy question is meaningful, the ecosystem has to
be able to *see itself* — and today it cannot.

## Limitations — stated, not buried

1. **Not pre-registered.** Definitions chosen after seeing the data. **Every
   verdict in this document is therefore provisional.**
2. **No pre-intervention data.** Nothing here is causal.
3. **The corpus is five weeks old** (from 2026-06-09). Every "never" means "never
   in a five-week window."
4. **CLI shell usage is invisible.** The strongest-sounding finding in Part III
   (14 dead services) may simply be wrong. See F-16 — I am refuting my own
   headline.
5. **Inferred definitions.** "Turn," "delegation," "protocol declaration" were
   reverse-engineered, not recovered. F-3 depends least on this; F-4/F-5 most.
6. **Cohort confounding.** F-7's cohorts are not exchangeable (n=8, one repo).
7. **Ambiguity excluded, not folded favorably.** 79 `cc`-token matches (~8%) were
   unresolvable by regex and are excluded from all headline counts.
8. **The probe audited the ecosystem; nobody has audited the probe.** Its
   operational definitions deserve the same skepticism it applied to the CSE.
   → Being addressed: [`phase-1-review-handoff.md`](phase-1-review-handoff.md).

### Two known holes, found while preparing the review handoff (2026-07-12)

These are **unclosed defects in this document**, recorded rather than quietly
fixed, because they bear directly on two headline numbers.

- **H-1 — `~/.zsh_history` was never mined.** F-16 concludes CLI Copilot's usage
  is *unknown* because shell invocations leave no transcript. But shell history
  exists, very likely spans months **before the transcript corpus begins**, and
  was simply not looked at. **It could settle F-16 outright and could overturn
  the "14 dead services" claim.** This is the single largest unexploited data
  source in the probe.
- **H-2 — Bash-mediated reads may be uncounted, inflating F-11.** The 95.6%
  never-read figure counts **`Read` tool calls** against knowledge paths. But the
  archaeology also established that **no native `Grep`/`Glob` calls exist anywhere
  in the corpus — file search happens via `Bash`.** If an agent ran `cat`, `grep`,
  `rg`, or `head` against a knowledge file, that read may never have been counted.
  **F-11's headline number is therefore an upper bound on "dead knowledge," not a
  measurement.**

Also corrected: F-2's denominator of **27** is 26 real `.claude/agents/`
directories plus 1 symlink (`research-copilot` → `knowledge-copilot`). A
`find -type d` returns 25 and is wrong. The ratio — **exactly 1 wired** — is
unaffected.

Confirmed clean while checking the above: there is **no global `PreToolUse` hook**
(`~/.claude/settings.json` carries only `Stop` and `UserPromptSubmit`), and
`/Users/pabs/Sites/COPILOT` and `/Volumes/Dev/Sites/COPILOT` are **the same tree**
via a symlink — an earlier pass nearly double-counted every repo.

## The open fork — not a recommendation

Two genuinely different benchmarks are available, answering different questions:

- **A utilization audit** — what is alive, what is dead. Nearly free. But it
  requires **adding instrumentation that does not exist** (CLI invocation
  logging, transcript retention), because the honest answer today is *"we cannot
  see."*
- **An efficacy benchmark** — is any of it *good*. Constructible for CLI Copilot
  this week. Constructible-but-expensive for the framework. **Impossible for
  Knowledge Copilot's voice claims** without changing the product (F-12).

Underneath both:

> **Do you want to know whether the CSE is useful — or which parts of it should
> exist at all?**

The data leans toward the second being the more urgent question. That is an
observation. The decision is the owner's.
