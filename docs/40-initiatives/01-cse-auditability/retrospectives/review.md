# Review Dossier — CSE Auditability, End to End

> **What this document is.** The single document a skeptical, independent reviewer opens to re-derive and check every claim this engagement made — not a narrative summary, and not another value pitch (that is [`value.md`](value.md)'s job). Its job is to leave nothing hidden: every number below traces to a claim id in [`claims.yaml`](../claims.yaml) via a `<!-- claim-check: <id> -->` annotation (the same convention value.md uses, and this file is now bound by the same live-document enforcement — see §1). Where this document reports a mistake, a wrong hypothesis, or a process failure, that is the point, not an omission to be apologized for later (§4).
>
> Companion documents, each with one job: [`../phases/phase-4-handoff.md`](../phases/phase-4-handoff.md) (the working entry point for whoever picks this program up next — setup, open work, operating rules) and [`value.md`](value.md) (what the owner may honestly tell a client or partner). This document is the third leg: **the reviewer's entry point.**

---

## 1. How to review this — the fast path

Run the following, in order, from `/Users/pabs/Sites/COPILOT/copilot-control-tower` unless noted. Each proves a specific, narrow thing — read the "proves" column before treating a green result as more than it is.

| # | Command | What it proves | What green does NOT mean |
|---|---|---|---|
| 1 | `python3 tools/cse-bench/check_claims.py` | `claims.yaml` is structurally sound: every claim has a unique id, a non-empty statement/check/status, `last_checked` set whenever status isn't `unchecked`, and status is one of the closed enum values (§5). | It does NOT mean any claim is true — only that the register is well-formed enough to trust its own tallies. |
| 2 | `python3 tools/cse-bench/claim_sweep.py --check` | Every quantified assertion in the CSE's own self-description docs (READMEs/SOULs/CLAUDE.md/AGENTS.md, each repo's own top-level `docs/` markdown files — not the recursive tree — and two named living exceptions — value.md and this file) is either backed by a real, resolving claim id or already in the disclosed baseline; and for value.md/this file specifically, every citation of a `failing`/`retired-*` claim is acknowledged as such in its own paragraph (the CLAIM HEALTH check). | It does NOT mean the CSE's docs are free of unbacked prose — a large disclosed baseline remains outside this program's own scope (§5); it means no NEW one landed silently. |
| 3 | `cd tools/cse-bench && python3 cse_bench.py collect && python3 cse_bench.py render` | The collectors run against the real corpus on this machine and `output/dashboard.html` is rendered from their live output plus `claims.yaml` directly — never a hand-typed table. | A fully clean `collect` run would itself be suspicious. The `integrations` collector is EXPECTED to error (the real `copilot` binary lives at a dev path, not `/opt/homebrew/bin/copilot` — see the gotchas below); that error is disclosed, not a defect to chase. |
| 4 | `cd tools/cse-bench/benches/ladder && python3 run.py --dry-run` | The ladder harness's full pipeline (config materialization, job-pack wiring, acceptance-check wiring, rubric loading, the DEC-6 sign-off gate) wires up cleanly with zero live model calls and zero dollars spent. | It does NOT re-run the scored O-4/O-6 results — those cost real money and are already recorded (§3, §7). A live re-run is `python3 run.py` without `--dry-run`, real cost, real time. |
| 5 | `tc progress` (repo root) | The task-store's own tally of completed/blocked/cancelled work matches what §2/§6 below claim. | It does not itself prove any claim in the register — it proves the audit trail this dossier cites actually exists and is in the state described. |

### Environment gotchas — read before anything looks broken

- **`/Volumes/Dev` is not mounted on this machine.** The real, only tree is `/Users/pabs/Sites/COPILOT`. `tools/cse-bench/collectors/paths.py`'s `resolve_copilot_root()` tries both roots and uses whichever exists; this is why `cse_bench.py` works. A small number of `claims.yaml` `check:` fields that read a *sibling* repo informationally (not through the collector layer) still hardcode `/Volumes/Dev` paths — flagged, not fixed, since they are read-only diagnostic reads of another repo, not this program's own instrumentation.
- **The real, dev `copilot` CLI binary lives at `cli-copilot/.venv313/bin/copilot`.** `/opt/homebrew/bin/copilot` does not exist on this machine — this is exactly why the `integrations` collector errors honestly rather than fabricating live-service data.
- **Interactive `copilot` is a personal shell alias for `cd`** on this machine (this owner's own `.zshrc`, not shipped by any product). Always invoke binaries by absolute path.
- **`alias which='type -all'`** (also personal, not shipped) reproducibly breaks bare `which` under zsh (`bad option: -l`) — including for targets that ARE on PATH. Use `command -v`. Confirmed inert for every shipped setup script (they already use `command -v`); it is a trap for a human debugging by hand, not a product defect — and it was, at one point, mistaken for one (§4).
- **Every dollar figure anywhere in this program is a subscription list-price equivalent, never a metered charge.** All benches run under the owner's personal Claude Code subscription, not an API key. Treat any `$` figure in this document, `claims.yaml`, or the dashboard as "what a metered account would have been billed for the same tokens," not money that changed hands — this distinction was itself violated once, mid-program, and caught (§4).

---

## 2. What was done, in execution order

The engagement's raw material predates this arc: Phase 0 (the register), Phase 1 (the falsification probe, four claims falsified against the CSE's own prior documentation), and Phases 2 and 3 (the benchmark harness, the five efficacy benches, and the SOUL-aligned remediation plan) were already complete — see [`../phases/phase-1-findings.md`](../phases/phase-1-findings.md) and [`../phases/phase-3-soul-remediation.md`](../phases/phase-3-soul-remediation.md). What follows is the **Outcome Program (Phase 4)** arc, run across 2026-07-13 and 2026-07-14, ending at commit `070ba42`. Every row below names its tasks, its work products, its commits, and the claim(s) it moved, so a reviewer can jump from any item to its evidence without re-deriving anything.

### Wave 1 — the ledger, the token joins, and the first ladder

| Item | Tasks | Work products | Commits | Claims moved |
|---|---|---|---|---|
| **W-1, the Outcome Ledger.** Extended Task Copilot's own SQLite store with `solutions`/`solution_scope_log`/`solution_usage_log` tables (additive, lazily migrated into every sibling repo's `tasks.db` on first `tc solution` call — no `tc init` re-run needed) and the six `tc solution` lifecycle verbs. | TASK-123 | WP-1, WP-2 | `c3e55f3`, `f2b91ed` (control-tower); `4e0cd22` (claude-copilot) | `outcome-ttfls`, `outcome-completeness`, `outcome-speed-observed`, `outcome-survival` flipped `gated` to `unchecked` |
| **W-2, per-solution token accounting.** A `solution_sessions` join table plus a `collectors/economy.py`, computing a solution's tokens two independent ways (ledger vs. transcripts). First cut double-counted a whole session's tokens against a solution touched for seconds; caught and corrected same day. | TASK-124 | WP-15, WP-17 (QA), WP-21 (fix) | `d9dd7f6`, `da61d35`, `26a3dd7`, `2254999` | `token-accounting-dual-method-agreement` (windowing corrected — §4) |
| **W-3, the ladder harness v1** (4 configs × 3 jobs) plus the MLP expectation rubric. QA found a token-accounting defect, a sign-off-gate bypass, and a cost-ceiling gap before any scored run; all three fixed before the harness was trusted with real money. | TASK-125 | WP-22, WP-23 (QA), WP-25 (fixes) | `e4105e2`, `424dfd6` | `ladder-harness-dry-run-validated` |
| **The decision queue opened.** Five decision memos plus the W-4 external pilot kit, all *prepared, not ruled* — this program never rules on itself. | TASK-112, 113, 114, 118, 122, 126 | WP-6 through WP-11 | `e0d0d7b`, `357fa50` | none yet — memos, not rulings |
| **W-6, `value_density` and the first removal review.** Traces every agent, CLI-service-group, knowledge-area, and skill to a usage-evidence plus outcome-bar-trace pair and produces a mechanical delete-or-defend nomination list. First run nominated agents `cpa`/`cs`/`kc` and knowledge area `04-shared-systems`. | TASK-128 | WP-26, WP-28 (QA) | `6fa4f7b`, `719cb6e`, `103a717`, `483689c` | `removal-review-first-pass` |

### Wave 2 — hygiene remediation (the R-series) and the ruling session

Thirteen remediation tasks (one per failing claim named in Phase 3's plan) covering the agent-return bar, protocol adoption, the falsified `~94%` figure, broken knowledge cross-links, freshness frontmatter, a tone-of-voice rewrite, registry completeness, stale-clone deletion, contradictory product versions, CLI conformance gaps, residual doc-truth lines, and dead-service configuration — TASK-112 through TASK-122, all `completed`. Then, in a single 2026-07-14 sitting sequenced by unblock-value ([`../decisions/ruling-agenda.md`](../decisions/ruling-agenda.md)), the owner ruled the queue:

| Decision | Ruling | Executed in | Task |
|---|---|---|---|
| DEC-1 (agent-return bar) | Amend — a per-class ratchet at measured reality, corrected same day into a falsifiable ceiling (§4) | `claude-copilot@b50f66a`, `copilot-control-tower@34e746c` | TASK-112 |
| DEC-2 (protocol adoption) | Retire the declaration-prefix obligation; keep the underlying routing discipline, measured separately | `claude-copilot@1b67851` | TASK-113 |
| DEC-3 (SOUL `~94%`) | Ratify Option B — rewrite to state the mechanism, defer the number to the register | `claude-copilot@e1e1501` | TASK-114 |
| DEC-4 (stale clones) | Remove the `frosty-perlman` worktree | `git worktree remove` | TASK-118 |
| DEC-5 (dead CLI services) | Cut fireflies/reddit, finish the metabase cut, cut method+notion credentials | `cli-copilot@ba99edb` | TASK-122 |
| DEC-8 (first removal review) | Cut `cpa`/`cs`; hold and investigate `kc`; cut the `04-shared-systems` design-doc subset | `claude-copilot@6be4fb3` | TASK-100 |
| DEC-9 (per-product delete-or-defend) | Execute per DEC-4, DEC-5, and DEC-8, plus archive the dormant repos named below | (roll-up of the above) | TASK-100 |
| DEC-10 (unverifiable April-turn claim) | Retire as `retired-by-unverifiability` | `claims.yaml` register patch | (register hygiene, no task) |
| DEC-6 (MLP rubric sign-off) | Ratified as drafted (Option A) | (unblocks the ladder itself) | gate on TASK-125 |
| DEC-7 (hook rollout — C-3) | **Held** — its own recommendation is to run one real session first, then rule | still open | TASK-103, `blocked` |

Sources: [`../decisions/DEC-1-agent-return-bar.md`](../decisions/DEC-1-agent-return-bar.md) through [`DEC-10-retire-unverifiable-turn-claim.md`](../decisions/DEC-10-retire-unverifiable-turn-claim.md), each memo's own header; commits `65439d6`, `0ff41f5`, `fa5d58e`, `9157cda`, `34e746c`.

### Wave 3 — the register's own hygiene: the claim sweep, the upkeep tax, and a caught self-correction

- **The CSE-wide claim sweep** (`t2-no-claim-outlives-its-check`'s own mechanism) was built and installed pre-commit in all five product repos: `claim_sweep.py`, TASK-137, commit `a14796e`. QA then found and closed three real bypasses in the sweep itself before trusting it (§4): TASK-143, WP-78 (QA), commits `d8fbca8`, `18e68de`, `a3ec73b`.
- **O-9, the upkeep-tax instrumentation** (`tc upkeep` verbs plus `collectors/upkeep.py`): TASK-138, commits `b30b031`, `9149e98`, `056730f`. Its first flip to `passing` tested only half its own statement — caught in review and corrected the same session (§4), commit `88da826`, WP-42.
- **Free-moves nobody was blocked on**: `ECOSYSTEM.md` registry rows for `copilot-control-tower` and `knowledge-copilot`, and starting the CLI usage clock (`COPILOT_USAGE_LOG`) — TASK-134, TASK-135, commit `649ddaa`, WP-33.
- **A final serialized register pass**: `t4`'s clause-B falsification, the CLI test-suite green flip, the O-8 tolerance draft, and the registry/protocol corrections — TASK-136, commit `c4762ea`, WP-34.

### Wave 4 — the discriminating ladder (v2), the efficiency wave, and the O-4 residual

- **W-3b, job-pack v2 — the discriminating re-run.** QA found v1's job pack could not discriminate any rung from any other; v2 replaced it with jobs engineered so the correct answer is genuinely unreachable without knowledge/integrations. TASK-142, commits `4dbfd44`, `0f69c96`, `1753f1a`, `0faa1e1`; QA re-verification WP-83, commit `9d3b5bd`.
- **W-5, the efficiency wave.** Root-caused the O-4 token premium: real-API ablation showed agent/command/skill bodies are near-costless (not "eagerly loaded," a hypothesis this wave directly refuted — §4) and CLAUDE.md is the one component loaded in full; trimmed `CLAUDE.template.md` accordingly. TASK-127, WP-24, WP-77, WP-79 (QA reconciliation, itself a correction of an overclaimed attribution figure — §4). Commit `0c73f65` (claude-copilot).
- **t6, cross-harness behavior.** Built a real behavior-level comparator (Claude vs. Codex, same job pack, same `+framework` rung) rather than relying on content-hash parity alone — the exact "check weaker than its statement" defect class this session had already found repeatedly ([`../phases/phase-4-cross-harness-behavior.md`](../phases/phase-4-cross-harness-behavior.md), §0). TASK-146, commits `36721e3`, `4f67188`, `339359f`.
- **`value.md` authored** and immediately brought under the claim-sweep ratchet as a second "live" document (the same mechanism this file is now also bound by). TASK-147, commits `8a524f0`, `068c903`.
- **W-3c, closing the O-4 residual among scaffold files.** A pre-registered ablation isolated commands, skills, and `.mcp.json` as their own rungs, taking file-level attribution of the turn-1 token premium from the prior pass's partial figure to a near-complete one. TASK-148, commits `269b1a7`, `d655b63`, `6bd54ce`.
- **The n=10 statistical confirmation.** A same-model, same-job-pack confirmation run at 10 reps per rung, disclosing — before the confirmation ran — that the original headline numbers were an underpowered n=3 sample. TASK-149, commits `f34a4dc`, `070ba42`.
- **The delegation-capable harness.** Built a harness mode that actually gives the agent-delegation layer a chance to fire (`/protocol`-prefixed briefs), closing the gap where 72 earlier cells showed zero delegation events by construction, not by finding. TASK-150, commits `0667205`, `548191f`, `3c9904e`.

Full task-by-task detail, including every QA report and correction note, is retrievable via `tc wp get <id>` for any work product named above, or `tc task get <id> --json` for any task.

---

## 3. The findings that matter

Stated plainly, positives and negatives together — a reviewer should be able to trust the positives here precisely because the negatives are not softened.

### 3.1 Positive: the knowledge layer earns its keep

On a job engineered so the correct answer is unreachable without an organization's real private vocabulary, a house-voice writing task went 0 of 10 bare and 0 of 10 at `+framework`, versus 8 of 10 at `+knowledge` and 8 of 10 at `+integrations` <!-- claim-check: ladder-v2-confirmation-n10 -->. Fisher's exact, two-sided, bare-vs-knowledge lands at p = 0.000714 <!-- claim-check: ladder-v2-confirmation-n10 -->, and pooled bare+framework versus knowledge+integrations lands at p = 1.54e-7 <!-- claim-check: ladder-v2-confirmation-n10 -->, genuinely statistically established. This is the **confirmation run**, deliberately disclosed as such: the original n=3-per-arm sample (0/3 versus 3/3) looked like a perfect separation but its own p-value was 0.10 <!-- claim-check: ladder-v2-o6-discriminating-verdict -->, not significant, and structurally the smallest p-value any n=3-vs-n=3 comparison can ever produce, regardless of how clean the split looks <!-- claim-check: ladder-v2-o6-discriminating-verdict -->. Both numbers are on the record; the n=10 run is the one to cite going forward.

### 3.2 Positive: the integrations layer earns its keep, and the whole program shows zero fabrication

Only the `+integrations` rung ever produced real, byte-matching live-service data — 10 of 10 on the n=10 confirmation run <!-- claim-check: ladder-v2-confirmation-n10 -->, extending the program's zero-fabrication record to 152 cumulative cells (72 original plus 80 confirmation) <!-- claim-check: ladder-v2-confirmation-n10 -->. Every other rung, on every cell in the program, either produced real verified data or honestly declined — never invented a number <!-- claim-check: ladder-v2-o6-discriminating-verdict -->.

### 3.3 Negative: O-4 (token efficiency) is FAILING, and not narrowly

The aspiration is a 90 percent token reduction versus bare, with 60 percent treated as "still work to do" <!-- claim-check: outcome-token-efficiency -->. The measured result is the **opposite sign** in every measurement this program has taken: v1 found every non-bare cell (9 of 9) used MORE tokens than bare, mean minus 24.2 percent <!-- claim-check: outcome-token-efficiency -->; v2's in-situ ablation isolates a fixed entry fee of roughly 3,003 tokens per job for `+framework`, paid entirely in turn 1, before any tool result exists <!-- claim-check: ladder-o4-scaffold-attribution-wp79-closed -->. Decomposed with confidence intervals: CLAUDE.md's mean contribution is 1,227.8 tokens (40.9 percent of the premium, 95% CI 956 to 1,499) <!-- claim-check: ladder-o4-full-attribution-closed -->, and the 13-agent roster's mean contribution is 1,070.8 tokens (35.7 percent, CI 799 to 1,342) <!-- claim-check: ladder-o4-full-attribution-closed -->, intervals that overlap, so the two are roughly TIED as the two dominant costs, not one clearly larger than the other. Skills add a smaller, genuinely distinguishable 567.8 tokens (18.9 percent, CI 342 to 794) <!-- claim-check: ladder-o4-full-attribution-closed -->; commands (127.8 tokens, 4.3 percent) and `.mcp.json` (minus 59.2 tokens, minus 2.0 percent) both carry confidence intervals that include zero <!-- claim-check: ladder-o4-full-attribution-closed -->. All five scaffold files together sum to roughly 97.8 percent of the premium, scoped explicitly as attribution among the five files the framework copies — PATH access and knowledge-repo wiring are not files and are not ablated by this design <!-- claim-check: ladder-o4-full-attribution-closed -->. The one shipped mitigation (the CLAUDE.md payload trim) recovers only roughly 8 to 12 percent of the real per-cell premium and does not flip the sign <!-- claim-check: outcome-token-efficiency -->.

### 3.4 Negative: the agent layer is unmeasurable by the original instrument, and the new instrument's first result is a suggestive null

Across the original 72 ladder cells, including the 3 rungs where the full 13-agent roster was materialized and available, the model invoked the delegation tool zero times <!-- claim-check: ladder-cannot-measure-framework-agent-layer -->. Investigation (§1 of [`../phases/phase-4-delegation-capable-harness.md`](../phases/phase-4-delegation-capable-harness.md)) found the cause: the ladder's raw job briefs bypass the framework's own routing entry point, `/protocol`. Prefixing the identical brief with `/protocol` reliably induces natural delegation. Built into a new delegation-capable harness mode and run on 4 jobs at 2 rungs, 1 rep each: 4 of 4 jobs landed `no_effect` on mechanical pass/fail, zero helps, zero hurts, zero discordant pairs <!-- claim-check: agent-layer-marginal-value-underpowered -->, even on the 2 jobs where the `framework` rung genuinely delegated. On the one clean delegate-vs-not comparison available (job-3), delegating cost 66 percent more for an identical mechanical outcome — $0.4472 versus $0.2693 — list-price-equivalent under subscription auth, never a metered charge <!-- claim-check: agent-layer-marginal-value-underpowered -->. **This is n=4 paired cells with zero discordant pairs — a suggestive null, not an established one**; McNemar sample-size guidance suggests several dozen to 100+ paired cells would be needed before "agents help, hurt, or do nothing" can be asserted with confidence <!-- claim-check: agent-layer-marginal-value-underpowered -->. The correct product-level finding is that `/protocol` is the framework's real routing gate: without it, the entire agent layer is invisible to any headless, single-shot instrument, which is itself worth knowing independent of which way a larger battery eventually lands.

### 3.5 The falsified claims — the forbidden list

Four claims made about this ecosystem, in its own prior documentation, are now disproven by this program's own measurement.

**"~94% less context."** FALSE, and inverted: agent returns run a median of 893 tokens against a median work-product content size of 353 tokens, a savings ratio of minus 153 percent, the opposite sign of the claim <!-- claim-check: framework-externalization-94pct -->.

**"Sonnet for ~94% of work."** FALSE: main-session share is Opus-dominant, 92.5 percent of assistant messages and 94.5 percent of tool calls, under every denominator tested <!-- claim-check: model-tier-opus-dominant-main-session -->.

**"CLI Copilot beats its MCP twins on token cost."** FALSE as stated: net advantage is negative for both twins under realistic usage (minus 780 and minus 1,894 tokens), positive for only one (plus 1,238 tokens) and only when that service's prose docs are hand-fed up front <!-- claim-check: cli-mcp-net-token-advantage -->.

**"CLI Copilot has 208 commands."** FALSE, roughly a 2x undercount: the real surface is 439 leaf commands across 22 service groups, of which only 103 (23 percent) show every liveness signal and 133 (30 percent) show none <!-- claim-check: cli-command-liveness-breakdown -->.

Two further claims are effectively falsified and retired, correctly, because the underlying obligation was fixed or removed rather than the number ever having been true. Protocol-declaration adoption, measured flat at 0.0 percent under both definitions because the enforcing hook never referenced "protocol" at all, is now `retired-by-deletion` after the requirement itself was struck <!-- claim-check: protocol-declaration-rate-baseline -->. A QA-gate hook meant to "ensure quality" is installed but has never fired: its state file exists and is empty, zero sessions tracked <!-- claim-check: framework-qa-gate-adherence -->.

---

## 4. The corrections and process failures — recorded, not buried

An honest review dossier records where the work went wrong and how it was caught. This is evidence the audit works, not something to minimize.

### 4.1 Seven check-weaker-than-statement gaps, caught and fixed

The register's own disease — a check that tests less than its claim's statement actually requires — was found and fixed seven times in this session ([`../phases/phase-4-cross-harness-behavior.md`](../phases/phase-4-cross-harness-behavior.md), §0: "seven other instances already found and corrected this session; this memo exists so `t6` is not the eighth"). Two are documented in detail below.

`outcome-upkeep-tax` was flipped `passing` on a check that tested only its statement's first clause ("measured") and never its second ("netted against outcome value"). Caught in review, not by an external party — corrected the same session, and the honest re-run flipped the status back to `unchecked` because the outcome ledger has zero solutions with joined session tokens anywhere yet, so "netted" cannot yet be tested <!-- claim-check: outcome-upkeep-tax -->.

`framework-session-cap-thresholds`'s check originally grepped only for the variable names (`THRESHOLD_SOFT=`, `THRESHOLD_STRONG=`), which would have passed even if the assigned values did not match the claimed 500 and 750. Strengthened to assert the literal values; re-run under the stronger check, it still passes, for real this time <!-- claim-check: framework-session-cap-thresholds -->.

### 4.2 Two greens-by-construction, rejected

`framework-agent-frugality`'s original bar was written so that a class's own median was, by definition, always inside its own limit, a pass that could not fail. Found, named explicitly as a "pass-by-construction trap," and replaced with a bar that CAN be breached — five of its tracked classes (`cco`, `cw`, `ind`, `qa`, `ta`) promptly did <!-- claim-check: framework-agent-frugality -->.

`agent-eval-coverage`, requiring every framework agent to carry a passing golden-set eval with most agents still uncovered, was left `failing` rather than quietly narrowed to "every agent that happens to have an eval passes it," a rewrite that was available, would have gone green immediately, and was explicitly declined <!-- claim-check: agent-eval-coverage -->.

### 4.3 A claim split, refused

`outcome-counterfactual-delta`'s statement requires EACH ladder component to contribute positively; framework's own zero-delegation result could have been split into a separate, softer claim once it became clear the instrument, not the framework, was the limiting factor. It was not split — the original claim stays `failing` on its own conjunctive wording, and a separate, first-class claim was registered instead to carry the instrument-limitation finding on its own terms, explicitly so no future reader can round a zero-delegation result down to "agents add nothing" <!-- claim-check: ladder-cannot-measure-framework-agent-layer -->.

### 4.4 Four wrong root-cause hypotheses, asserted then disproven by the checks that followed

**"`tc` is off PATH for subagents."** The leading hypothesis for why subagents skip externalization. Disproven: `tc` was reliably available — 34 of 35 attempted `tc wp store` calls succeeded across many sessions and repos. The real defect was this machine's own `alias which='type -all'`, which makes bare `which` fail for anything, including targets genuinely on PATH — a false negative, not a real PATH failure. The actual, dominant mechanism, roughly 75.2 percent of sampled returns, was silent non-attempt, unrelated to PATH at all, plus a genuine design gap (a required `--task` option with no standalone-work-product fallback), since fixed <!-- claim-check: framework-agent-frugality -->.

**"Agents, commands, and skills are eagerly loaded in full."** A prior "14 agents fully loaded" framing was directly refuted by a real-API ablation: the 13-agent roster contributes roughly 690 tokens total, about 2.4 percent of its own raw on-disk content; CLAUDE.md is the sole component loaded in full <!-- claim-check: framework-scaffold-eager-load-mechanism -->.

**"The scaffold ablation explains ~98% of the ladder's real premium."** An adversarial reconciliation found the ablation's own cache-creation share of 98.3 percent described only the ablation's own measurement internally; when compared against the ladder's real, same-job turn-1 premium, the ablation, run at a smaller model on a trivial no-tool prompt, explained only about 62 percent of it (2,124 of roughly 3,442 tokens), leaving an unattributed residual of about 36 to 38 percent the original framing had not disclosed <!-- claim-check: ladder-o4-scaffold-attribution-wp79-closed -->. That residual is what the later, matched-model ablation closed to roughly 97.8 percent <!-- claim-check: ladder-o4-full-attribution-closed -->.

**"The knowledge layer is proven at n=3."** The original house-voice split (0/3 versus 3/3) was initially reported as a clean separation without stating what n=3 does and does not license. Disclosed and corrected the same day, before any confirmation cell ran: Fisher's exact at n=3 is p = 0.10, not significant, and cannot structurally reach significance at that sample size regardless of how clean the split looks <!-- claim-check: ladder-v2-o6-discriminating-verdict -->. The n=10 confirmation run (§3.1) is what actually established the finding.

### 4.5 A cost-language error, caught by the owner

Every run in this program executes under the owner's personal Claude Code subscription, never a metered API key — every dollar figure this program produces is a list-price-equivalent computation, not money charged. A register pass at one point quoted these figures in billed-cost language rather than list-price-equivalent language; the owner caught the distinction and it was corrected the same session (commit `46d1bc3`, "fix billed-vs-list-price cost defect"). The correction is the standing rule stated in §1's environment gotchas, applied throughout this document.

### 4.6 One mis-scoped commit

Commit `aed6c69` ("chore(cse-bench): refresh claim-sweep baseline for cli-copilot service-count cut") was authored with a bare `git commit -m`, which staged and absorbed a concurrent agent's own in-progress edits to `DEC-6-mlp-rubric-signoff.md` and the ladder's `README.md`, `configs.py`, `run.py`, and `rubric.md` — files unrelated to the commit's own stated purpose. The commit's own message discloses a related, checked side effect (deduplicating pre-existing duplicate baseline entries, verified key-for-key against the prior file) but does not disclose the scope absorption, which is recorded here instead. No content was lost — every absorbed file change was real, intended work from its own owning lane, landed correctly, just under the wrong commit's authorship record. The lesson, not softened: a bare `git commit -m` on a shared working tree with multiple concurrent agents can silently absorb someone else's staged work; scope every commit explicitly (`git add <paths>` before `git commit`) when more than one lane is active.

---

## 5. State of the register

### 5.1 The tally, run today, not copied from an older doc

```
$ python3 tools/cse-bench/check_claims.py
check_claims.py: OK — docs/40-initiatives/01-cse-auditability/claims.yaml:
66 claim(s), 25 definition(s), 0 violations.
```

Status breakdown, computed the same way (a structured parse of the `claims:` list, not a text grep — see §5.5 for why that distinction matters): 38 passing, 14 failing, 8 unchecked, 3 gated, and 3 retired, one each `retired-by-unverifiability`, `retired-by-ratification`, and `retired-by-deletion` <!-- claim-check: t2-no-claim-outlives-its-check -->. Every claim resolves to exactly one status; there is no "other" bucket.

### 5.2 The nine outcome bars

| Bar | Claim id | Status | What would move it |
|---|---|---|---|
| O-1 Time-to-First-Loveable-Solution | `outcome-ttfls` | unchecked | A real solution reaching `tc solution mark-loveable` (Act A) |
| O-2 Solution Completeness | `outcome-completeness` | unchecked | A real solution shipped against a locked brief (Act A) |
| O-3 Speed (observed half) | `outcome-speed-observed` | unchecked | A real solution's ledger timestamps (Act A) — the counterfactual half is O-6's job |
| O-4 Token Efficiency | `outcome-token-efficiency` | **failing**, opposite sign (§3.3) | Real-solution numerator (Act A); further mitigation beyond what is already recovered |
| O-5 Solution Survival | `outcome-survival` | unchecked | Real solutions started, shipped, then checked at N weeks (Act A) |
| O-6 Counterfactual Delta | `outcome-counterfactual-delta` | **failing**, mixed (§3) | A harness where framework-layer delegation can fire at scale (§6); O-4's residual, already mostly closed among files |
| O-7 Voluntary Return Rate | `outcome-return-rate` | gated | At least one external pilot's unprompted return (Act B) |
| O-8 Transfer Coefficient | `outcome-transfer` | gated | At least two non-author pilots within the pre-registered tolerance (Act B) |
| O-9 Upkeep Tax | `outcome-upkeep-tax` | unchecked | A real outcome-session's tokens to net against — currently reads as entirely upkeep because zero outcome tokens exist anywhere (Act A) |

### 5.3 The fourteen failing claims — why, and what would close each

| Claim id | Why it fails | What would close it |
|---|---|---|
| `outcome-token-efficiency` | Every measured rung costs MORE tokens than bare, not fewer (§3.3) | Owner: a real solution in the ledger; build: further mitigation beyond CLAUDE.md's trim |
| `outcome-counterfactual-delta` | Statement requires EACH component to contribute positively on O-1 through O-4; knowledge and integrations do on O-1, but O-4 is negative everywhere and framework's own contribution is unmeasured, not disproven | Build: a delegation-capable harness at scale (§6); already-shipped: the O-4 residual closure |
| `t1-ecosystem-sees-itself` | CLI invocation logging exists but was never switched on until this session's free-move (`COPILOT_USAGE_LOG`) | Real data: let the usage clock run and re-measure |
| `t2-no-claim-outlives-its-check` | A majority of scanned assertions across the product repos' self-description docs remain unbacked (baselined, not silently accepted) | Owner/build: triage the baseline to zero, the same un-shortcuttable editorial pass that already closed F-18's named instances |
| `t3-instruction-layer-changes-behavior` | Needs DEC-2, DEC-7, DEC-8, and a second eval wave, all four, measured together; several individual pieces have landed but the conjunction has not | Build: DEC-7's rollout plus the C-5 eval wave over the relevance-review survivors |
| `t4-knowledge-layer-changes-output` | Clause B falsified: compiled rules-in-prompt beat raw repo-as-context on voice conformance, so the repo's marginal value over prompting alone is not demonstrated (clause A, private-fact accuracy, passes decisively) | Owner call: restate the claim to match the real mechanism, distillation rather than dumping |
| `t5-integration-layer-pays-its-way` | Dead surface was pruned (DEC-5), but "retained commands show usage" has zero usage evidence anywhere — the usage ledger has not yet accrued real data | Real data: let `COPILOT_USAGE_LOG` accrue, then re-measure |
| `delegation-hook-matcher-scope` | **Failing in the desired direction** — its statement describes a since-fixed defect (the matcher narrowed to Bash-only); the fix re-widened it, so the statement is now correctly false | Not something to "close" — retire once the remaining rollout gap also closes |
| `cli-mcp-net-token-advantage` | Net token advantage is negative for both MCP twins under realistic usage; positive for only one, and only with hand-fed docs | Owner call: restate honestly — even the shipped mitigation left one twin negative in the cited run |
| `agent-eval-coverage` | Statement requires EVERY framework agent evaluated; a majority remain unmeasured | Build: the C-5 second eval wave over the relevance-review survivors |
| `framework-agent-frugality` | A minority of tracked classes breach their own registered ceiling | Build/real data: the next quarter-reduction ratchet step, re-measured after the return-contract fix already landed but untested |
| `framework-agent-return-aspiration` | Every tracked class exceeds the SOUL aspiration target | Honestly not expected to close soon — this is the aspiration bar, kept separate from the enforceable ceiling on purpose |
| `framework-qa-gate-adherence` | The QA-gate hook is installed but has never fired (empty state file); the artifact-marker rate where it does apply is well under full coverage | Build: DEC-7's rollout, then real sessions to fire the hook |
| `knowledge-registry-completeness` | A minority of top-level directories remain unmentioned or uncovered in `ECOSYSTEM.md`, though fewer than before this session's fix | Build: continued mechanical registry rows, non-owner-gated |

### 5.4 The three retired claims

`framework-externalization-94pct` is `retired-by-ratification` — DEC-3 corrected the SOUL text this claim was falsifying, so the claim's own subject no longer exists as written; the underlying finding stays on record (§3.5). `protocol-declaration-rate-baseline` is `retired-by-deletion` — DEC-2 struck the obligation itself. `turn-definition-incompatible-with-april` is `retired-by-unverifiability` — its own `check` field names a script that no longer exists; DEC-10 retired it under `t2`'s own "unverifiable claims are deleted" rule.

### 5.5 The malformed status token — investigated, found legitimate

A naive `grep -n "status:"` across `claims.yaml` surfaces one line that looks out of place among the closed status enum: `status: "proposed — owner ratification pending"`. This is **not** a claim's status field — it lives under `definitions.outcome_transfer_tolerance`, a definition entry describing whether the O-8 transfer tolerance itself has been ratified by the owner, not a CSE claim's pass/fail verdict. `check_claims.py`'s structured parser only validates the `claims:` list's own `status` field against the closed enum; it never touches `definitions:`, so this string cannot cause the zero-violations result above to be wrong. A prior QA pass already investigated this exact question (`tc wp get 82`, TASK-144: "Malformed 'proposed...' status: searched claims: section before and after every edit — none found. No fix needed.") and this review independently re-confirmed it by loading the file with the register's own structured parser and checking every claim's `status` field programmatically, all 66 claims <!-- claim-check: t2-no-claim-outlives-its-check -->, zero matches. **Left as-is** — it is a legitimately different field, correctly named for its own context, not a stray value in the register proper.

---

## 6. What remains

**The open decision item.** DEC-7 (hook rollout — C-3) is `blocked` on purpose: its own memo recommends running one real Claude Code session in `claude-copilot` and checking for sane hook-state values before ruling, rather than arguing the fix is "close enough," a discipline chosen precisely because this same hook system looked fixed once before, on 2026-04-22, and silently was not for two months.

**The two owner acts nothing else can substitute for.** (A) Track a real solution end-to-end with `tc solution create`, `lock-brief`, `mark-working`, `mark-loveable`, `log-usage`, `close`, spread across genuine elapsed work, not a burst at the end — the machinery is verified ready in a disposable scratch store, and every claim in §5.2 marked "Act A" is blocked on this alone. (B) Recruit 2 to 3 external pilots, at least one non-developer, genuinely external, bringing a real problem of their own, per [`../phases/phase-4-w4-external-pilot-kit.md`](../phases/phase-4-w4-external-pilot-kit.md) — the kit is built and a stranger-dry-run has already surfaced one real product gap (`cc config init --project` requires a pre-existing git repository with no upstream warning). This is the only act that removes the single-author caveat from every number in this program.

**A larger delegation-layer battery, designed but not run at scale.** The delegation-capable harness mode itself is built, real, and cheap to re-run (§3.4, roughly $0.27 to $0.45 per cell, list-price-equivalent) <!-- claim-check: agent-layer-marginal-value-underpowered -->, but its own first result (n=4 paired cells, zero discordant pairs) is explicitly underpowered. The harness's own memo names the scale needed, several dozen to 100+ paired job-cells, to move past "suggestive null" toward an established answer; nobody has yet run that larger battery, and no go/no-go gate has been ratified for when to invest the further compute — an owner call, not an engineering blocker <!-- claim-check: agent-layer-marginal-value-underpowered -->.

**Known open defects, disclosed not silently patched.** The waste-decomposition heuristic's literal completion-marker check does not recognize other agent roles' own completion vocabulary, likely over-counting failed-direction tokens in an ordinary multi-role session <!-- claim-check: token-accounting-dual-method-agreement -->. `claude-copilot`'s `.claude/agents/kc.md` and `.claude/commands/knowledge-copilot.md` still hardcode the unmounted `/Volumes/Dev/Sites/COPILOT/knowledge-copilot` path — reported to the owner, not fixed this session (a different lane had both files open).

**A disclosed backlog of unbacked assertions** across the product repos' self-description docs (§5.3, `t2-no-claim-outlives-its-check`) that the sweep can only shrink, never silently grow, but which still needs a human triage pass, one assertion at a time.

---

## 7. Provenance map

Every claim in the register, its backing evidence, and the command that re-runs it. "Backing" names the primary task, work product, commit, or doc cited in the claim's own `evidence:` field in `claims.yaml`; "Re-run entry point" is a short pointer, not a retyped copy of the full command — copying dozens of long shell one-liners into a second document would itself violate this program's own anti-duplication discipline (one canonical source per fact). To print any claim's exact, full `check:` command directly from the register itself:

```bash
python3 -c "
import sys; sys.path.insert(0, 'tools/cse-bench'); import check_claims as cc
d = cc.load_yaml(cc.DEFAULT_CLAIMS_PATH.read_text())
c = {x['id']: x for x in d['claims']}['<claim-id>']
print(c['check'])
"
```

| Claim id | Status | Backing | Re-run entry point |
|---|---|---|---|
| `outcome-ttfls` | unchecked | TASK-123, WP-1/WP-2 | `cse_bench.py collect --only solutions` |
| `outcome-completeness` | unchecked | TASK-123, WP-1/WP-2 | `cse_bench.py collect --only solutions` |
| `outcome-speed-observed` | unchecked | TASK-123, phase-4-outcome-program-prd.md | `cse_bench.py collect --only solutions` |
| `outcome-token-efficiency` | failing | TASK-124/TASK-142/TASK-148, WP-17/WP-79/WP-81 | `cse_bench.py collect --only economy` |
| `token-accounting-dual-method-agreement` | unchecked | TASK-124, WP-17/WP-21 | `cse_bench.py collect --only economy` |
| `outcome-survival` | unchecked | TASK-123, WP-1/WP-2 | `cse_bench.py collect --only solutions` |
| `outcome-counterfactual-delta` | failing | TASK-125/TASK-142/TASK-149, WP-44/WP-81/WP-83 | manual, see `claims.yaml` `check:` |
| `ladder-v2-o6-discriminating-verdict` | passing | TASK-142, WP-76/WP-81/WP-83 | manual, reads `bench_ladder-runs/20260714T144205Z/` |
| `ladder-v2-confirmation-n10` | passing | TASK-149, WP-79/WP-83/WP-94 | manual, reads the n=10 confirmation run directories |
| `ladder-o4-scaffold-attribution-wp79-closed` | passing | TASK-142, WP-79/WP-81/WP-83 | `benches/ladder/configs.py` (config-name check) plus the raw run dir |
| `ladder-cannot-measure-framework-agent-layer` | passing | TASK-142, WP-81/WP-83; `phase-4-delegation-capable-harness.md` | manual, scans the 72-cell run for `tool_use.name` |
| `ladder-o4-full-attribution-closed` | passing | TASK-148, WP-79/WP-91/WP-92 | `benches/ladder/configs.py` (config-name check) plus the raw run dir |
| `ladder-harness-dry-run-validated` | passing | TASK-125, WP-23/WP-47 | `benches/ladder/run.py --dry-run` |
| `outcome-return-rate` | gated | phase-4-outcome-program-prd.md §2 (O-7) | gated on Act B |
| `outcome-transfer` | gated | phase-4-outcome-program-prd.md §2 (O-8); `phase-4-w4-external-pilot-kit.md` §2 | gated on Act B |
| `outcome-upkeep-tax` | unchecked | TASK-138, WP-40/WP-42 | `cse_bench.py collect --only upkeep` |
| `t1-ecosystem-sees-itself` | failing | phase-2-prd.md (T1) | manual, see `claims.yaml` `check:` |
| `t2-no-claim-outlives-its-check` | failing | TASK-137/TASK-143, WP-41/WP-47/WP-78/WP-80 | `check_claims.py` plus `claim_sweep.py` |
| `t3-instruction-layer-changes-behavior` | failing | phase-1-findings.md (F-1, F-2, F-4) | manual, see `claims.yaml` `check:` |
| `t4-knowledge-layer-changes-output` | failing | `benches/voice_lint/README.md`, `benches/knowledge_qa/README.md` | manual, see `claims.yaml` `check:` |
| `t5-integration-layer-pays-its-way` | failing | phase-2-prd.md (T5) | manual, see `claims.yaml` `check:` |
| `t6-two-harnesses-one-behavior` | passing | TASK-145/TASK-146, WP-84/WP-86/WP-88 | `codex-copilot/scripts/check-upstream-parity.py --content` plus `cross_harness.py` |
| `t7-inheritance-ladder-in-practice` | gated | phase-2-prd.md (T7) | gated on Control Tower's own build program |
| `t8-value-transfers-beyond-author` | unchecked | phase-2-prd.md (T8) | gated on Act B |
| `delegation-rate-baseline` | passing | phase-1-findings.md (F-5) | `cse_bench.py collect --only transcripts` |
| `protocol-declaration-rate-baseline` | retired-by-deletion | DEC-2, `claude-copilot@1b67851` | `cse_bench.py collect --only transcripts` |
| `turn-definition-incompatible-with-april` | retired-by-unverifiability | DEC-10, phase-1-findings.md | manual, unverifiable by design (retired) |
| `model-tier-opus-dominant-main-session` | passing | phase-1-findings.md (F-3) | `tools/cse-audit/run_probe.py` |
| `knowledge-never-read-rate` | passing | phase-1-findings.md (F-11), TASK-139 | `cse_bench.py collect --only transcripts` |
| `cli-command-liveness-breakdown` | passing | phase-1-findings.md (F-16) | manual, see `phase-1-reaudit-report.html` |
| `cli-copilot-test-suite-verified` | passing | TASK-130, `cli-copilot@be895d6` | cli-copilot `pytest tests/` |
| `enforcement-hook-wiring-ratio` | passing | phase-1-findings.md (F-2) | manual, external repo scan |
| `delegation-hook-matcher-scope` | failing | TASK-106, `claude-copilot@77f5cdb0` | manual, external repo read |
| `knowledge-factual-accuracy-delta` | passing | `bench_knowledge_qa-latest.json` | `benches/knowledge_qa/run.py` |
| `voice-conformance-deltas` | passing | `bench_voice_lint-latest.json` | `benches/voice_lint/run.py` |
| `cli-mcp-net-token-advantage` | failing | `bench_mcp_twin-latest.json` | `benches/mcp_twin/run.py` |
| `agent-eval-coverage` | failing | TASK-105 | `cse_bench.py collect --only evals` |
| `framework-resume-value` | passing | `bench_resume_cost-latest.json` | `benches/resume_cost/run.py` |
| `framework-externalization-94pct` | retired-by-ratification | DEC-3, WP-28, `claude-copilot@e1e1501` | `cse_bench.py collect --only framework_soul` |
| `framework-agent-frugality` | failing | TASK-128/TASK-141, WP-28/WP-45/WP-46, `claude-copilot@b50f66a` | `cse_bench.py collect --only framework_soul` |
| `framework-agent-return-aspiration` | failing | DEC-1, `claude-copilot@b50f66a` | `cse_bench.py collect --only framework_soul` |
| `framework-scaffold-eager-load-mechanism` | passing | TASK-127, WP-77/WP-79 | manual, real-API ablation, see `claims.yaml` `check:` |
| `framework-claude-md-payload-trim` | passing | TASK-127, WP-77/WP-79, `claude-copilot@0c73f65` | manual, real-API ablation, see `claims.yaml` `check:` |
| `framework-qa-gate-adherence` | failing | WP-28 | `cse_bench.py collect --only framework_soul` |
| `knowledge-crosslink-integrity` | passing | R-6, knowledge-copilot's own gate script | `cse_bench.py collect --only knowledge_soul` |
| `knowledge-staleness-honesty` | passing | R-7, WP-47 | `cse_bench.py collect --only knowledge_soul` |
| `knowledge-voice-self-conformance` | passing | R-8 | `cse_bench.py collect --only knowledge_soul` |
| `knowledge-registry-completeness` | failing | TASK-118/TASK-134, `knowledge-copilot@5f729946` | `cse_bench.py collect --only knowledge_soul` |
| `cli-soul-conformance` | passing | TASK-122, `cli-copilot@ba99edb` | cli-copilot `pytest tests/test_soul_conformance.py` |
| `removal-review-first-pass` | passing | TASK-128, `value_density-latest.json` | `cse_bench.py collect --only value_density` |
| `hook-deadlock-fix-verified` | passing | TASK-106, `claude-copilot@77f5cdb0` | claude-copilot `tests/hooks/test-pretool-check.sh` |
| `knowledge-extension-install-mechanism` | passing | phase-1-findings.md | claude-copilot `install-extensions.py --help` |
| `knowledge-glossary-manifest-resolves` | passing | phase-1-findings.md | knowledge-copilot manifest read |
| `task-copilot-mcp-dist-exists` | passing | phase-1-findings.md | `test -f` on the built entrypoint |
| `cli-json-contract-not-versioned` | passing | WP-47 | cli-copilot grep for `schema_version` |
| `codex-specialist-chain-scorecard-not-run` | unchecked | WP-47, phase-1-findings.md (F-18 #7) | codex-copilot scorecard-template read |
| `cli-copilot-service-count` | passing | TASK-122 | `cse_bench.py collect --only cli_soul` |
| `cli-copilot-python-version` | passing | `docs/00-overview.md` | cli-copilot `pyproject.toml` grep |
| `cli-copilot-env-file-autodiscovery` | passing | `README.md` | manual, see `claims.yaml` `check:` |
| `claude-copilot-python-version` | passing | `README.md` | claude-copilot `pyproject.toml` grep |
| `claude-copilot-skill-description-coverage` | passing | WP-80 | manual, see `claims.yaml` `check:` |
| `framework-session-cap-thresholds` | passing | TASK-106, WP-80 | claude-copilot hook-file grep |
| `framework-april-2026-diagnostic-unrecoverable` | passing | phase-1-findings.md (F-6) | `check_pre_restructure_transcripts.py` |
| `control-tower-agent-count` | passing | `CLAUDE.md` | `find .claude/agents -maxdepth 1 -name '*.md'` |
| `delegation-capable-harness-mode-built` | passing | TASK-150, `phase-4-delegation-capable-harness.md` | `benches/ladder/delegation_harness.py` |
| `agent-layer-marginal-value-underpowered` | passing | TASK-150, `phase-4-delegation-capable-harness.md`/`phase-4-cross-harness-behavior.md` | `benches/ladder/delegation_harness.py` |

Every claim currently in `claims.yaml` is mapped above — none omitted.

---

**Total accounting (V-4).** Every claim in `claims.yaml` appears exactly once in §5 and §7 above. If a future `check_claims.py` run reports a different total, that is this document's own signal to be re-verified against §5.1 before being trusted again — the same discipline this whole program applies to everything else it measures.
