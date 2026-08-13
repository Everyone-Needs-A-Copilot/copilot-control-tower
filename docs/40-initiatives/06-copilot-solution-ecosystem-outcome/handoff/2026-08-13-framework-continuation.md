# Framework ecosystem continuation handoff

Date: 2026-08-13  
Owner: Pablo Alejo  
Scope: framework ecosystem only; the Control Tower Mac app is deferred

## Start the next conversation here

Use this prompt:

> Continue the framework ecosystem work from
> `docs/40-initiatives/06-copilot-solution-ecosystem-outcome/handoff/2026-08-13-framework-continuation.md`.
> Do not work on the Mac app or reopen locally approved framework hardening.
> First verify the three protected PR review states. If the reviews are present,
> complete the protected framework and content release sequence, then run the
> real organization/accounting effectiveness evaluation and regenerate the
> eligible-fleet census. If the reviews are absent, report that external blocker
> directly rather than writing more framework code.

## Current result

The framework candidate is technically complete, installed on this machine, and
green in hosted CI. The remaining release blocker is independent human review,
not another implementation defect.

- Framework PR: [claude-copilot #66](https://github.com/Everyone-Needs-A-Copilot/claude-copilot/pull/66)
- Exact head: `3e5f12952410fd94e6d7d0f7311c830534ffc638`
- Exact tree: `986795503108a8658012c07fb106fca2565a8912`
- Hosted result: CodeQL, conformance, root, `tools/cc`, `tools/tc`, skill,
  TUI, smoke, onboarding, path, wiring, time-language, and local evaluation
  checks all pass. The billed live-evaluation job is intentionally skipped.
- GitHub Actions were enabled only for that bounded verification window and are
  disabled again.
- PR state at handoff: `BLOCKED`, `REVIEW_REQUIRED`, zero reviews.
- Final evidence: TASK-297 WP-1013.

The installed machine runtime matches the hosted head exactly:

- `cc version 2.12.8`
- runtime manifest: `~/.copilot/framework-runtime.json`
- immutable snapshot:
  `~/.copilot/framework-snapshots/claude-copilot-3e5f12952410fd94e6d7d0f7311c830534ffc638`
- all six global machine commands come from that snapshot
- exactly one enabled framework plugin exists:
  `codex-copilot@codex-copilot-project`
- installed no-cache round-trip: 19 pass, 0 fail, 0 could-not-run
- full no-cache conformance: 0 could-not-run and 0 regression failures

## The three human-review gates

Do not merge, tag, bypass protections, or manufacture approval. A qualifying
reviewer must approve each applicable protected change.

1. Framework: [claude-copilot #66](https://github.com/Everyone-Needs-A-Copilot/claude-copilot/pull/66)
   - head `3e5f12952410fd94e6d7d0f7311c830534ffc638`
   - all required hosted checks green
   - James Lukensow requested
   - zero reviews at handoff
2. Organization content: [knowledge-copilot-internal #1](https://github.com/Everyone-Needs-A-Copilot/knowledge-copilot-internal/pull/1)
   - head `c51784d4e34b0f65ec955a82aa72c2196bae2e5e`
   - approved tree `90b9aed75a2fd630d12bcf94d53d0ab8ff311f26`
   - mergeable/clean, zero reviews at handoff
3. Accounting content: [knowledge-copilot-accounting #1](https://github.com/Everyone-Needs-A-Copilot/knowledge-copilot-accounting/pull/1)
   - head `e0471f509be2844615d55698e98db4ef3f607d51`
   - tree `310156cb07c8b286ecbcad931a66d3b5df4b9d18`
   - sensitive-content check green, review required, zero reviews at handoff

The accounting signed root/tag and live E-4 lock projection already work. The six
remaining S0 conformance rows (`cco`, `do`, `ind`, `sd`, `uids`, and `uxd`) are
six views of one condition: the approved organization content is not yet
published as a signed immutable release.

## Correct continuation order

1. Read the three PR states. Do not start new engineering if approvals are still
   absent.
2. After framework approval, merge PR #66 through the protected normal path.
   Do not bypass the ruleset. Publish a signed immutable framework release/tag
   only from the reviewed merge result.
3. Reinstall the released exact commit with
   `scripts/install-framework-snapshot.py`, then verify the runtime manifest,
   six command hashes, single Codex plugin source, `cc version`, and no-cache
   round-trip.
4. After organization/accounting approvals, merge through their protected normal
   paths and publish new non-moving signed tags/pins. Do not reuse or move an old
   tag.
5. Run `cc update --json`, verify the signed organization and accounting winners,
   immutable source receipts, and canonical lock projections.
6. Run the bounded effectiveness cases from TASK-285. The practical minimum is
   EVAL-01, EVAL-02, one of EVAL-03/EVAL-04, and EVAL-05 across foundation and
   layered conditions, with Claude/Codex where supported. Preserve criterion
   evidence; do not invent an aggregate quality score.
7. Rerun `cc conformance check --full --no-cache --json`. Closure requires zero
   S0, zero unexplained could-not-run, and zero unreviewed regressions.
8. Regenerate TASK-300's exact census from the installed entitlement ledger.
   Seek owner approval of that exact mutation set before TASK-288 applies any
   fleet changes.

## One local non-S0 cleanup

The Control Tower repository has one S1 lock mismatch:
`scripts/copilot-gate.sh` is the signed and QA-approved gate from commit
`e67088a2f50011085df3b2a4889c88eddc7c36c6` / WP-904, while its project lock
still records older bytes. The legacy updater would overwrite the approved gate,
so it was correctly not run. Resolve this only through an evidence-bound lock
adoption transaction that updates the enumerated checksum without changing the
approved source file or unrelated lock members. This does not block the
framework PR or organization release.

## Explicitly deferred or external

- Do not work on Control Tower application packaging, Apple signing,
  notarization, Installer certificates, app installation, or app release. Those
  obligations remain intact under PRD-24/TASK-301.
- GitHub provider garbage collection for the legacy accounting object remains a
  support-portal matter; there is no supported REST ticket API. Do not fabricate
  a support ticket or treat local unreachable-object checks as provider purge.
- The seven-person access roster still needs business need-to-have confirmation.
- Do not reopen the accepted local-evaluator namespace-ordering residual recorded
  in WP-966 unless real production evidence demonstrates impact.

## Repositories and durable evidence

- Control Tower task database and initiative docs:
  `/Volumes/Dev/Sites/COPILOT/copilot-control-tower`
- Framework source:
  `/Volumes/Dev/Sites/COPILOT/claude-copilot`
- Final framework worktree/branch:
  `/Volumes/Dev/Sites/COPILOT/.worktrees/claude-copilot-final-snapshot-installer`,
  `fix/final-snapshot-installer`
- Hosted framework branch: `integrate/pr63-pr65-local`
- Primary task entry: `tc task get 278 --json`
- Content release task: `tc task get 297 --json`
- Evaluation tasks: TASK-284 and TASK-285
- Fleet tasks: TASK-300 then TASK-288
- Final hosted/installed QA: WP-1013
- Installer/plugin QA: WP-1012
- Integrated framework QA: WP-1010
- Live accounting evidence: WP-1001

## Fast verification commands

```bash
cd /Volumes/Dev/Sites/COPILOT/copilot-control-tower
tc task get 278 --json
tc task get 297 --json

gh pr view 66 --repo Everyone-Needs-A-Copilot/claude-copilot \
  --json headRefOid,mergeStateStatus,reviewDecision,reviews,statusCheckRollup,url
gh pr view 1 --repo Everyone-Needs-A-Copilot/knowledge-copilot-internal \
  --json headRefOid,mergeStateStatus,reviewDecision,reviews,url
gh pr view 1 --repo Everyone-Needs-A-Copilot/knowledge-copilot-accounting \
  --json headRefOid,mergeStateStatus,reviewDecision,reviews,statusCheckRollup,url

gh api repos/Everyone-Needs-A-Copilot/claude-copilot/actions/permissions
$HOME/.local/bin/cc version
$HOME/.local/bin/cc conformance check --layer roundtrip --full --no-cache --json
```

Expected safe handoff state: framework Actions disabled, exact installed commit
`3e5f129...`, round-trip 19/19, and no protected merge performed without human
approval.
