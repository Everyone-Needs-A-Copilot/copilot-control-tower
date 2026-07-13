# Phase 3 — SOUL Remediation Plan

> Initiative: `01-cse-auditability` · Prepared: 2026-07-13 · PRD-9 extension
> Input: the S-series measurements (2026-07-12) and the 30-claim register.
> Rule: every failing SOUL-anchored claim gets exactly one remediation task,
> a mechanical check that proves the fix, and an owner-gate flag where the fix
> is a product decision rather than work.

Every task below must, on completion, flip a specific claim in
[`claims.yaml`](../claims.yaml) from `failing` to `passing` (or record an
owner-ratified decision that the claim is retired). That is the definition of
done — not "the work happened," but "the check now passes."

## Development framework (claude-copilot & codex-copilot)

| Task | Gap (claim) | Fix | Gate |
|---|---|---|---|
| **R-1** | Agents return 658-token median vs the SOUL's ~100 bar (`framework-agent-frugality`) | Two-part: (a) tighten agent return-format instructions + add a SubagentStop size check (warn, then deny over threshold); (b) if the ~100 bar is judged unrealistic, propose an evidence-based SOUL §6 amendment instead — with the measured distribution attached. Fix or amend; never ignore. | Owner picks (a) enforce vs (b) amend |
| **R-2** | QA-gate has never fired; 8 sessions shipped `me` work with no `qa` (`framework-qa-gate-adherence`) | Roll out the C-6-fixed hooks beyond claude-copilot per the documented readiness checks (= existing **C-3 / TASK-103**), starting with the 3 most-active repos. | Readiness checks per repo |
| **R-3** | Protocol adoption 0.9% (`protocol-declaration-rate-baseline`) | Diagnose before fixing: is /protocol too heavy for real turns, or unenforced? Deliverable = a decision memo with the enforcement/simplification options and their measured costs. | Owner decision on direction |
| **R-4** | Eval coverage 1/16 agents (`agent-eval-coverage`) | Golden sets for the next 5 highest-traffic agents (me, ta, doc, sd, uxd), baselined before merge (= existing **C-5 / TASK-105**). | — |
| **R-5** | SOUL §3 still quotes the falsified "~94%" figure (`framework-externalization-94pct`) | Owner-ratified SOUL §10 amendment replacing the number with the measured reality (README already corrected, 7274e6b). | **Owner ratification** |

## Knowledge framework (knowledge-copilot)

| Task | Gap (claim) | Fix | Gate |
|---|---|---|---|
| **R-6** | 52.5% cross-link resolution, 124 broken (`knowledge-crosslink-integrity`) | Fix the systematic wrong-depth batch first (28 links in one file), then the remaining real breaks; add a link-check pre-commit so the claim can't silently regress (repo currently has no hooks). | — |
| **R-7** | Zero `last_updated` keys; 1.3% freshness coverage (`knowledge-staleness-honesty`) | Adopt one freshness key (`last_updated` + `status`), backfill active (non-archive) docs from git history, enforce on new/edited files via the same pre-commit. | — |
| **R-8** | The tone-of-voice doc fails its own linter at 2.74/100w (`knowledge-voice-self-conformance`) | Rewrite `02-tone-of-voice.md` to pass `voice_lint` (rules stay, prose conforms), and restructure the `cw` extension to carry the **distilled rules** (the voice bench proved rules-format beats prose-format). | — |
| **R-9** | Registry omits control-tower and knowledge-copilot itself; 12 dirs untracked (`knowledge-registry-completeness`) | Add the missing Local-path rows; reconcile the 12 unmentioned dirs (add, or mark archived); stale clones (`conversations-copilot`, `shared-docs` dirs) are deletions → owner decides. | Deletions owner-gated |
| **R-10** | Contradictory version facts, e.g. insights-copilot 2.7.0 vs 2.6.0 (`contradictory facts` in knowledge_soul) | Correct the dossier(s) to a single source of truth; keep the collector's version-conflict probe as the regression check. | — |

## Integration framework (cli-copilot)

| Task | Gap (claim) | Fix | Gate |
|---|---|---|---|
| **R-11** | 13 tracked conformance gaps (`cli-soul-conformance`) | Flip each strict-xfail to pass: infisical test file; migrate coolify/infisical error classes onto `CopilotError`; 3 missing `docs/services/` entries; document the 12 missing env vars in `.env.example`. Suite goes 138/138. | — |
| **R-12** | Residual doc untruths: `CLAUDE.md` "17 services", overview line 31 | Two-line truth fixes. | — |
| **R-13** | Structurally dead surface: fireflies/reddit (no creds), metabase (empty dir), method (creds, no service) | Configure-or-cut decision per service; cuts are product deletions → feeds **B-17 / TASK-100**. | **Owner decides** |

## Sequencing

1. **Wave R-mechanical (no decisions needed):** R-6, R-7, R-8, R-10, R-11, R-12 — each ends with a claim flip and a regression check.
2. **Wave R-staged:** R-2 (per-repo readiness), R-4 (eval-by-eval).
3. **Owner queue:** R-1 direction, R-3 direction, R-5 ratification, R-9 deletions, R-13 cuts.
4. Ecosystem endgame unchanged: **B-13 ladder test → B-14 external pilot** — the "substantial value" question stays unanswerable until these run.

## Done means

`python3 tools/cse-bench/check_claims.py` shows the nine currently-failing
SOUL-anchored claims either `passing` or retired-by-ratification, and the
dashboard's three component sections show green where the SOULs promise it.
