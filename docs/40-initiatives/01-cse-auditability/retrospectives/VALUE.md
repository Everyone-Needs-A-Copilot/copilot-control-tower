# What the CSE Is Worth — An Honest Value Statement

> **What this document is.** The single artifact its owner uses to correctly describe the
> Copilot Solutioning Ecosystem (CSE) to a client, a partner, or another organization — no
> more, no less. Every quantified sentence below traces to a live, re-runnable check in
> [`claims.yaml`](claims.yaml) via a `<!-- claim-check: <id> -->` annotation. Re-verify any
> number yourself: `python3 tools/cse-bench/check_claims.py` validates the register's own
> structure; each claim's own `check:` field is the command that reproduces its number.
>
> **This document names its own forbidden claims (§3) and its own blind spots (§5) before
> anyone else can.** That is not humility for its own sake — it is the only thing that makes
> the rest of it worth reading.

---

## Read this before anything else: the single-author caveat

**Every number in this document comes from one person's machine, over one measurement
window.** No external user has yet run this ecosystem. Two of the nine outcome bars that
would establish product-level (not personal-toolkit-level) value — voluntary return (O-7)
and transfer to a non-author (O-8) — are pre-registered but **gated**, waiting on pilots that
have not yet run <!-- claim-check: outcome-return-rate --><!-- claim-check: outcome-transfer -->.
The register's own truth condition for "this is a product, not a personal toolkit" is
currently unmet, stated in its own words: *"Every number in existence is single-author"*
<!-- claim-check: t8-value-transfers-beyond-author -->.

**The correct qualifier on every claim below, without exception, is: true for the person who
built it.** Do not drop that qualifier when repeating any number in this document to a third
party. §6 says more about what would remove it.

---

## 1. What the CSE is

The Copilot Solutioning Ecosystem is three components, orchestrated by a fourth:

- **A development framework** (Claude Copilot and Codex Copilot — one framework, two
  harnesses) that supervises a coding agent through specialist sub-agents, a task/memory
  layer, and a working protocol.
- **A knowledge framework** (Knowledge Copilot) — a versioned repository of an
  organization's private facts, voice rules, and case history, inherited into a project's
  context.
- **An integration framework** (CLI Copilot) — a single CLI fronting a fixed set of live
  external services (CRM, docs, project tools, and so on) behind one grammar.
- **Copilot Control Tower** (this repo) — a menu-bar supervisor that renders the other three
  components' state; it computes nothing itself.

The stated goal of the whole ecosystem is narrow and singular: *support a person in creating
a solution they love — quickly, efficiently, and intuitively.* Every measurement in this
document is judged against that goal and nothing else.

**What it is not, yet:** a proven product. It is a working system its owner uses daily, whose
components have been individually, adversarially measured against their own stated promises.
Some of those promises held. Several did not. §2 and §3 are the difference.

---

## 2. What is proven — and exactly how strong the proof is

Four findings in this ecosystem have survived adversarial re-verification: an independent
pass that re-ran the same measurement, read the raw deliverables by hand, or re-fetched the
ground truth a second time on a different day. Each is stated here with its number, the exact
method, and the caveat that must travel with it.

### 2.1 The knowledge layer changes output on a knowledge-discriminating task

On a task engineered so the correct answer is genuinely unreachable without the
organization's private material (write a house-voice document using an org's real
vocabulary), four configurations were run three times each: bare model, model +
development-framework scaffold only, + the knowledge repo, + live integrations.

| Config | Result |
|---|---|
| bare | 0/3 <!-- claim-check: ladder-v2-o6-discriminating-verdict --> |
| +framework | 0/3 <!-- claim-check: ladder-v2-o6-discriminating-verdict --> |
| +knowledge | 3/3 <!-- claim-check: ladder-v2-o6-discriminating-verdict --> |
| +integrations | 3/3 <!-- claim-check: ladder-v2-o6-discriminating-verdict --> |

**Method and the check against string-injection.** `check.py` requires zero hits on a
banned-jargon denylist *and* at least one hit on the organization's real private-vocabulary
set — a rung cannot pass by writing bland text alone. A second reviewer independently read
all 12 raw deliverables off disk (not just the pass/fail flags): bare and +framework
consistently produce fluent, generic consulting prose; +knowledge and +integrations
consistently and coherently use the organization's real private terms. This was not a
keyword-stuffing artifact <!-- claim-check: ladder-v2-o6-discriminating-verdict -->.

**Caveat.** This is one job, in one job pack, at one model (Sonnet), run three times per
config. It is the first job in this program's history capable of discriminating the
knowledge layer at all — an earlier job pack could not, by construction, and produced an
uninformative 12/12 tie across every rung <!-- claim-check: ladder-v2-o6-discriminating-verdict -->.

**Statistical honesty, added 2026-07-14, resolved same day.** Three reps per config is a small
sample, and this document was originally silent on what that does and does not license.
Fisher's exact test, two-sided, on the bare-vs-knowledge split above (0/3 vs 3/3): p = 0.10 <!-- claim-check: ladder-v2-o6-discriminating-verdict -->
— not significant at the conventional α = 0.05 threshold <!-- claim-check: ladder-v2-o6-discriminating-verdict -->,
and structurally the smallest p-value any n=3-vs-n=3 comparison can ever produce, however clean
the split looks <!-- claim-check: ladder-v2-o6-discriminating-verdict -->. A same-model,
same-jobs confirmation at n=10 reps per rung (80 cells) has since run <!-- claim-check: ladder-v2-confirmation-n10 -->.

| Config (n=10) | Result |
|---|---|
| bare | 0/10 <!-- claim-check: ladder-v2-confirmation-n10 --> |
| +framework | 0/10 <!-- claim-check: ladder-v2-confirmation-n10 --> |
| +knowledge | 8/10 <!-- claim-check: ladder-v2-confirmation-n10 --> |
| +integrations | 8/10 <!-- claim-check: ladder-v2-confirmation-n10 --> |

**The finding is now genuinely statistically established, and also genuinely smaller than it
first looked.** Bare-vs-knowledge at n=10: p = 0.000714 <!-- claim-check: ladder-v2-confirmation-n10 -->
(significant at α = 0.05); pooled bare+framework (0/20) vs knowledge+integrations (16/20): <!-- claim-check: ladder-v2-confirmation-n10 -->
p = 1.54 × 10⁻⁷ <!-- claim-check: ladder-v2-confirmation-n10 -->. But the clean, complete
separation at n=3 was not fully replicated: at n=10, knowledge and integrations each land at
80% (8 of 10), not the full 100% the smaller sample showed <!-- claim-check: ladder-v2-confirmation-n10 -->
— two knowledge-rung and two integrations-rung reps wrote generic prose with no banned jargon
but also no positive house-vocabulary evidence, real model variance the smaller sample could
not show <!-- claim-check: ladder-v2-confirmation-n10 -->.
Read this section as: real, mechanism-verified, AND now statistically significant (p < 0.001 <!-- claim-check: ladder-v2-confirmation-n10 -->)
— but "large and significant," not "perfect," is the accurate description of the effect size.

### 2.2 Private-fact accuracy: +98 percentage points

With an organization's private-fact dossier in context, the model answered 98.0% of private <!-- claim-check: knowledge-factual-accuracy-delta -->
product-fact questions correctly (48/49); without it, 0.0% (49/49 — the model correctly <!-- claim-check: knowledge-factual-accuracy-delta -->
reported "unknown" rather than guessing), a delta of +98.0 points <!-- claim-check: knowledge-factual-accuracy-delta -->.
The 0% "without" figure is itself a <!-- claim-check: knowledge-factual-accuracy-delta -->
finding worth naming: it means the model did not hallucinate plausible-sounding private facts
in the dossier's absence; it declined. **Caveat.** One 49-question bank, one model, one run.

### 2.3 The integrations layer earns its keep, and the whole program shows zero fabrication

On the job whose correct answer requires live external-service data, only the
`+integrations` rung ever produced real, byte-exactly-matching service data — 20 of 20 <!-- claim-check: ladder-v2-o6-discriminating-verdict -->
services correct, independently re-fetched and compared a day later. The other 9 cells (bare,
+framework, +knowledge) all used the honest "integrations unavailable" fallback rather than
inventing numbers <!-- claim-check: ladder-v2-o6-discriminating-verdict -->.

**The headline is not the 20/20 — it is what happened in the other 9.** <!-- claim-check: ladder-v2-o6-discriminating-verdict --> Across the entire
72-cell program (48 main cells + 24 ablation cells, all six configurations), zero cells
fabricated data at any point. Every cell either produced real, verified-correct output or
honestly declined <!-- claim-check: ladder-v2-o6-discriminating-verdict -->. That property —
not one invented number across 72 independently scored attempts — is worth stating on its own
merits, separate from whether any given rung "won."

**Statistical honesty, added 2026-07-14, resolved same day.** The zero-fabrication property
above is exhaustive (every one of 72 cells was checked, not sampled) and stands on its own.
The +integrations rung's 3/3 real-data-match record that opens this section <!-- claim-check: ladder-v2-o6-discriminating-verdict --> was, like §2.1's
split, only an n=3 reliability sample. A same-model n=10 confirmation has since run: <!-- claim-check: ladder-v2-confirmation-n10 -->
**+integrations reached 10/10** exact ground-truth matches, zero fabrication across all 40 <!-- claim-check: ladder-v2-confirmation-n10 -->
job-3 confirmation cells — a stronger result than the original 3/3 <!-- claim-check: ladder-v2-confirmation-n10 -->,
extending this program's zero-fabrication record to 152 cells cumulative (72 + 80) <!-- claim-check: ladder-v2-confirmation-n10 -->.
One honest caveat on the confirmation run itself, not on the framework: 5 of the 40 job-3
confirmation cells (bare/framework/knowledge rungs) failed their mechanical check only because
the check's own independent live ground-truth call timed out under this run's higher
concurrency — a measurement artifact in this specific run, verified by reading each failure's
own error message directly, not a model or fabrication failure <!-- claim-check: ladder-v2-confirmation-n10 -->.

### 2.4 The knowledge layer's value comes from distillation, not from dumping the repo into context

A separate bench measured voice-rule conformance (violations per 100 words) under three <!-- claim-check: voice-conformance-deltas -->
prompting arms:

| Arm | Violations / 100 words <!-- claim-check: voice-conformance-deltas --> |
|---|---|
| bare | 2.77 <!-- claim-check: voice-conformance-deltas --> |
| knowledge repo as raw context | 0.48 <!-- claim-check: voice-conformance-deltas --> |
| compiled rules pasted directly into the prompt | 0.10 <!-- claim-check: voice-conformance-deltas --> |

Knowledge beats bare — real value. But **compiled rules-in-prompt beat the raw
knowledge-as-context by roughly 5x.** <!-- claim-check: voice-conformance-deltas --> The mechanism by which the knowledge layer helps is
distillation into a small, structured rule set, not bulk repo content in the model's context
window. This is a genuine, transferable finding about *how* to deliver the value found in
§2.1–2.3, not a discovery that the value is absent — and it directly falsified a narrower,
adjacent claim (§3.3).

### 2.5 Resume-with-state: 100% vs 0%, at a real but small token cost <!-- claim-check: framework-resume-value -->

When the framework's persisted task/memory state is available at the start of a session, a
model resumes a cold task (task, completed step, next action) correctly 100% of the time; <!-- claim-check: framework-resume-value -->
without it, 0% of the time — at a measured overhead of +3.9% tokens for the roughly <!-- claim-check: framework-resume-value -->
654-token state block <!-- claim-check: framework-resume-value -->. This is the framework's
own stated job (persist state so work survives a session boundary), measured directly.
**Caveat.** Contamination-controlled, three repetitions per arm — a real but small
experiment.

### 2.6 Two harnesses, one behavior — with three named limits

Claude Copilot and Codex Copilot are meant to be the same framework behind two different
coding-agent harnesses. Run through the same 4-job pack at the `+framework` rung, both
harnesses reached the identical pass/fail outcome on all 4 jobs
<!-- claim-check: t6-two-harnesses-one-behavior -->.

This is real, but it is exactly as narrow as stated, no further:

- One of the four "matches" is **agreement on failure** — both harnesses correctly fail the
  knowledge-discriminating job because neither materializes real knowledge content at this
  rung. That is a weaker form of agreement than agreeing on success.
- **Delegation and orchestration equivalence is not tested.** Neither harness's headless mode
  invokes the Task tool at all — see §5.
- **Only the `+framework` rung was cross-tested.** Bare, +knowledge, and +integrations remain
  untested across harnesses.

<!-- claim-check: t6-two-harnesses-one-behavior -->

---

## 3. What is false — the forbidden list

These claims have been made about this ecosystem, in its own documentation, at some point.
Every one of them is now disproven by this program's own measurement. **Repeating any of
these — including by the person who built this ecosystem — is a false statement, not an
optimistic rounding.**

### 3.1 "~94% less context" (externalizing work through work products vs inlining) <!-- claim-check: framework-externalization-94pct -->

**FALSE, and inverted.** Measured directly: a delegated agent's own final return is a median
893 tokens; the work-product content it externalizes is a median 353 tokens. Agent returns
are **~2.5x larger** than the artifacts they claim to externalize (a −153% savings ratio, the <!-- claim-check: framework-externalization-94pct -->
opposite sign of the claim) <!-- claim-check: framework-externalization-94pct -->. This figure
has since been struck from the framework's own README and SOUL documents by an owner-ratified
correction — but the correction retired the *claim*, not the underlying finding, which stays
on record and remains the operative number whenever this topic comes up
<!-- claim-check: framework-externalization-94pct -->.

### 3.2 "Sonnet for ~94% of work" (the cheaper model does the bulk of orchestration) <!-- claim-check: model-tier-opus-dominant-main-session -->

**FALSE.** Measured main-session share is Opus-dominant, not Sonnet-dominant: 92.5% of <!-- claim-check: model-tier-opus-dominant-main-session -->
main-session assistant messages and 94.5% of main-session tool calls run on Opus — the <!-- claim-check: model-tier-opus-dominant-main-session -->
opposite of the design intent, under every denominator tested
<!-- claim-check: model-tier-opus-dominant-main-session -->.

### 3.3 "The mandatory protocol declaration / process enforcement ensures quality" <!-- claim-check: protocol-declaration-rate-baseline --><!-- claim-check: framework-qa-gate-adherence -->

**FALSE on the evidence available.** The mandatory `[PROTOCOL: ...]`-prefix declaration
requirement measured 0.0% adoption under both its strict and loose definitions in the most <!-- claim-check: protocol-declaration-rate-baseline -->
recent re-run — because the hook meant to enforce it contains zero references to "protocol"
at all; nothing ever checked it
<!-- claim-check: protocol-declaration-rate-baseline -->. The requirement has since been
retired rather than enforced, on the honest grounds that a directly-measured proxy for the
same underlying discipline (delegation rate) already exists and is separately tracked (§2 does
not include it — it is discussed as an open question in §5). Separately, the mechanism most
directly named as "ensuring quality" — a QA-gate hook requiring an `ARTIFACT:` marker before
work ships — is **installed but has never fired**: its state file exists and is empty, zero
sessions tracked <!-- claim-check: framework-qa-gate-adherence -->. An unfired hook enforces
nothing.

### 3.4 "CLI Copilot beats its MCP twins on token cost"

**FALSE as stated.** Net token advantage is negative for both measured MCP twins under
realistic (probe-everything) usage — one twin scored 780 tokens worse, the other 1,894 tokens
worse. It is positive for only one twin (+1,238 tokens), and only when that service's shipped
prose documentation is provided to the agent up front rather than discovered live
<!-- claim-check: cli-mcp-net-token-advantage -->.

### 3.5 "CLI Copilot has 208 commands" <!-- claim-check: cli-command-liveness-breakdown -->

**FALSE — a roughly 2x undercount.** <!-- claim-check: cli-command-liveness-breakdown --> The real, re-audited surface is 439 leaf commands across
22 service groups <!-- claim-check: cli-command-liveness-breakdown -->. Correcting the count
also surfaces an uncomfortable adjacent fact worth stating in the same breath: of those 439,
only 103 (23%) show every liveness signal (config, recent activity, transcript use, and shell <!-- claim-check: cli-command-liveness-breakdown -->
history); 133 (30%) show none <!-- claim-check: cli-command-liveness-breakdown -->.

---

## 4. What it costs — stated plainly

**The framework has a fixed entry fee, and it is paid before any work happens.** An in-situ,
same-model, same-task-type ablation (not a synthetic probe) isolated the token premium of
running with the full development-framework scaffold versus bare, per job, at the point in
the session where it is actually incurred:

- **Mean premium: 3,003 tokens per job**, and **100% of it lands in the first turn**, before <!-- claim-check: ladder-o4-scaffold-attribution-wp79-closed -->
  any tool result exists. This is a one-time entry fee, not a tax that accumulates with more
  tool calls <!-- claim-check: ladder-o4-scaffold-attribution-wp79-closed -->.
- Of that premium, all five scaffold files this framework installs have now been individually <!-- claim-check: ladder-o4-full-attribution-closed -->
  isolated in situ — but at the n=4 jobs this was measured on, only a COARSE ordering is
  statistically supported, so this document quotes ranges, not a false ranking.
  **CLAUDE.md's mean is 1,227.8 tokens (40.9% of the premium), 95% CI [956, 1499]** <!-- claim-check: ladder-o4-full-attribution-closed -->
  **and the 13-agent roster's mean is 1,070.8 tokens (35.7%), 95% CI [799, 1342]** <!-- claim-check: ladder-o4-full-attribution-closed -->
  **— the two intervals overlap by 343 tokens, so they are roughly TIED as the two dominant <!-- claim-check: ladder-o4-full-attribution-closed -->
  costs**; this program cannot yet say CLAUDE.md costs more than the agent roster, only that
  together (point estimates summing to ~76.6% of the premium) both are far larger than <!-- claim-check: ladder-o4-full-attribution-closed -->
  everything else. **skills adds a smaller, genuinely distinguishable cost: 567.8 tokens <!-- claim-check: ladder-o4-full-attribution-closed -->
  (18.9%), CI [342, 794]** <!-- claim-check: ladder-o4-full-attribution-closed -->; **commands (127.8 tokens, 4.3%, CI [-99, 355]) and <!-- claim-check: ladder-o4-full-attribution-closed -->
  .mcp.json (-59.2 tokens, -2.0%, CI [-386, 267]) both have confidence intervals that include <!-- claim-check: ladder-o4-full-attribution-closed -->
  zero** — .mcp.json is confirmed a no-op (an empty placeholder file); commands may cost
  nothing at all. All five together sum to ~97.8% of the premium; the remaining ~2.2% is <!-- claim-check: ladder-o4-full-attribution-closed -->
  smaller than any single component's own measurement noise, not a sixth undiscovered cost.
  **Scope, stated plainly: "97.8% attributed" means attributed among the five FILES this <!-- claim-check: ladder-o4-full-attribution-closed -->
  framework copies** — two other bare-vs-framework differences (PATH access to `tc`/`cc`;
  whether the knowledge repo is even wired up) are not files, are never ablated by this design, <!-- claim-check: ladder-o4-full-attribution-closed -->
  and sit outside what this number claims. This is also a marginal-only design — each rung
  removes exactly one component against the full baseline, with no leave-two-out rung — so it
  found no evidence of a large interaction between components, but cannot rule small ones out <!-- claim-check: ladder-o4-full-attribution-closed -->.
- A separate, earlier measurement on a different job pack found every non-bare configuration
  (framework, knowledge, and integrations alike) used **more** tokens than bare, not fewer —
  a mean of 24.2% more, ranging from 18% to 35% more, across 9 of 9 measured non-bare cells <!-- claim-check: outcome-token-efficiency -->
  <!-- claim-check: outcome-token-efficiency -->.

**Against the outcome program's own bar:** the CSE's stated aspiration is a 90% token <!-- claim-check: outcome-token-efficiency -->
reduction versus a bare-harness counterfactual, with 60% treated as the "still work to do" <!-- claim-check: outcome-token-efficiency -->
floor. The measured result is the **opposite sign** of that bar in every measurement this
program has taken — every rung costs more tokens than bare, not fewer
<!-- claim-check: outcome-token-efficiency -->. A real mitigation has since shipped (a trim to
the CLAUDE.md template) and it is a genuine win against its own before/after baseline
(−37.1% on CLAUDE.md's own contribution) — but measured against the ladder's real per-cell <!-- claim-check: framework-claude-md-payload-trim -->
premium, it recovers only roughly 8–12% of the overage, and does not change the sign <!-- claim-check: framework-claude-md-payload-trim -->
<!-- claim-check: outcome-token-efficiency --><!-- claim-check: framework-claude-md-payload-trim -->.

**Cost language rule, applied throughout this document and non-negotiable going forward:**
every run in this program executes under the owner's personal Claude Code subscription, not a
metered API key. Any dollar figure this program ever produces is Claude Code's own computed
*list-price-at-metered-rates equivalent* — the amount a metered account would have been
billed for the same token volume — never an amount actually charged. This document therefore
reports cost in tokens first and does not quote a dollar figure without spelling out that
distinction. Anyone quoting this ecosystem's cost in dollars without that qualifier is
misrepresenting a subscription workload as a metered one.

---

## 5. What is unknown, and why that is the honest answer

**The framework's core value proposition — that specialist delegation produces a better
result than one model working alone — has never been exercised by this program's own
instrument.** Across all 72 controlled cells run to date, including the three configurations
where a full 13-agent roster was materialized and available on disk, the model invoked the
delegation (Task) tool **zero times** <!-- claim-check: ladder-cannot-measure-framework-agent-layer -->.
The correct reading of that zero is not "the agent layer adds nothing." It is: *this specific
instrument (a headless, single-shot, single-file, single-skill task run non-interactively)
never gave the agent layer a chance to fire at all* <!-- claim-check: ladder-cannot-measure-framework-agent-layer -->.

**This sits in real, unresolved tension with production data.** Real session transcripts — <!-- claim-check: delegation-rate-baseline -->
ordinary day-to-day work, not the controlled ladder — show a tool-share delegation rate with a
median around 40.5–40.9% (an order of magnitude apart from an event-share reading of the same <!-- claim-check: delegation-rate-baseline -->
sessions, ~3.0–3.2%; the two definitions disagree by roughly 10x and neither is authoritative <!-- claim-check: delegation-rate-baseline -->
alone) <!-- claim-check: delegation-rate-baseline -->. Zero percent in a controlled instrument
against roughly 40% in real use is not a contradiction this document resolves — it is an open <!-- claim-check: delegation-rate-baseline -->
question this document names.

**One thing would settle it, and it has not been built yet; a second, related item is now
done:**

1. A harness mode where delegation can actually fire — an interactive, multi-turn session
   rather than a single headless call, or a job whose scope forces decomposition even within
   a single invocation (for example, a brief spanning several distinct specialist domains at
   once, rather than this program's current single-file, single-skill jobs). Still open.
2. DONE, updated 2026-07-14: the §4 token residual has since been closed among scaffold FILES <!-- claim-check: ladder-o4-full-attribution-closed -->
   — commands, skills, and `.mcp.json` were each isolated as their own rung, taking file-level
   attribution to ~97.8% of the premium (see §4 for the CIs and the "files-only" scope this <!-- claim-check: ladder-o4-full-attribution-closed -->
   number carries — PATH and the knowledge-repo wiring are still outside what any file-based
   ablation can measure).

<!-- claim-check: ladder-cannot-measure-framework-agent-layer -->

Until one of those exists, any claim that specialist delegation does or does not add value —
in either direction — outruns what this ecosystem has actually measured.

---

## 6. The single-author caveat, in full

Restated from the top of this document because it cannot be said only once: **every measured
number in this document — the wins in §2, the falsifications in §3, the costs in §4, the
open questions in §5 — was produced on one machine, by the one person who also built the
system being measured.** There is no external replication of any of it.

Two of the outcome program's nine success bars exist specifically to close this gap, and both
remain gated, not merely unmeasured:

- **O-7, Voluntary Return Rate** — does a person choose this ecosystem again, unprompted,
  after their first solution — is gated on pilots that have not yet run
  <!-- claim-check: outcome-return-rate -->.
- **O-8, Transfer Coefficient** — do at least two people who are not the author reach the same
  outcomes, unassisted, within a stated tolerance of the author's own numbers — is likewise
  gated on pilots that do not yet exist. Its tolerance has been pre-registered (before any
  pilot data exists, so the yardstick cannot be bent to fit a result) but pre-registering the
  yardstick does not manufacture the pilots it is waiting to score
  <!-- claim-check: outcome-transfer -->.

The program's own truth condition for "this transfers beyond its author" — a non-author
completing representative tasks measurably better with the CSE than without — is stated in
its own register in five words: *"Every number in existence is single-author"*
<!-- claim-check: t8-value-transfers-beyond-author -->.

**Do not describe this ecosystem as validated for anyone other than its builder.** It is
validated, rigorously, for exactly one person. That is not nothing — §2 is real — but it is
also not yet evidence of a product.

---

## 7. Why you should believe this document

The strongest argument for trusting the numbers above is not a claim about their accuracy. It
is a claim about what this measurement program has already done to its own owner's favorite
numbers, and it is verifiable by reading the register yourself.

**It falsified its own flagship claims.** The "~94% less context" figure, the "Sonnet for <!-- claim-check: framework-externalization-94pct -->
~94% of work" figure, the "CLI beats MCP on tokens" figure, and the 208-command count were all <!-- claim-check: model-tier-opus-dominant-main-session -->
produced by this ecosystem's own prior documentation, and all four were disproven by this same
program (§3). A knowledge-layer claim thought likely to pass was checked precisely because the
answer was not obvious, and one of its two clauses came back falsified
<!-- claim-check: t4-knowledge-layer-changes-output -->.

**It caught its own checks being weaker than their claims — and fixed them rather than quoting
the flattering result.** A claim about maintenance cost was briefly marked "passing" on a
check that tested only half of what its own statement required; the gap was caught in review
and the claim was corrected back to an honest, unflattering "unchecked" state
<!-- claim-check: outcome-upkeep-tax -->. A session-length-threshold claim's check was found
to test only that a configuration variable existed, not that it held the claimed value; the
check was strengthened before the claim was allowed to stand
<!-- claim-check: framework-session-cap-thresholds -->. The register's own top-level rule
exists precisely to make this failure mode impossible to hide
<!-- claim-check: t2-no-claim-outlives-its-check -->.

**It rejected its own greens-by-construction.** An agent-return quality bar was originally
written so that a class's own median was, by definition, always within its own limit — a pass
that could not fail. That structure was found, named explicitly as a "pass-by-construction
trap," and replaced with a bar that can actually be breached — and five of its tracked classes
promptly breached it <!-- claim-check: framework-agent-frugality -->.

**It refused a rewrite that would have manufactured a pass.** A claim requiring *every*
framework agent to carry a passing evaluation, with most agents still uncovered, was left
failing rather than quietly narrowed to "every agent that happens to have an evaluation
passes it" — a rewrite that was available, would have gone green immediately, and was
explicitly declined <!-- claim-check: agent-eval-coverage -->.

**It registers a claim about its own blindness.** Rather than let a 72-cell run with zero
delegation events be reported as "agents don't help," this program wrote a first-class claim
whose entire content is *this instrument cannot see the thing it would need to see to answer
that question* — and named exactly what would fix that
<!-- claim-check: ladder-cannot-measure-framework-agent-layer -->.

A scorecard produced by the party being scored, with no red rows, is not evidence of a good
system — it is evidence of a bad auditor. As of this writing, this register carries more
failing and unchecked rows than a marketing document would ever choose to publish on its own,
and every one of them is reproducible with a command anyone can run:
`python3 tools/cse-bench/check_claims.py`. **A register that fails its owner's favorite
numbers is the one you can trust when it passes them.**
