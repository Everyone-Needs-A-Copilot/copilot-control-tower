# Claude/Codex effectiveness and release continuation handoff

- Date: 2026-08-15
- Owner: Pablo Alejo
- Initiative: 06 — Copilot Solution Ecosystem Outcome
- Primary tasks: TASK-285 and TASK-291
- Framework repository: `/Volumes/Dev/Sites/COPILOT/claude-copilot`
- Active framework worktree: `/Volumes/Dev/Sites/COPILOT/.worktrees/claude-copilot-project-source-drift`
- Active branch: `feat/task-285-live-effectiveness-evaluation`
- Control Tower repository and Task Copilot database: `/Volumes/Dev/Sites/COPILOT/copilot-control-tower`

## Start here

Claude Copilot and Codex Copilot are usable now for ordinary ecosystem development. The unfinished work is the new effectiveness evaluator, its production Codex network boundary, and the immutable framework release—not the basic ability to use either copilot.

Current installed tools:

- `cc version 2.12.10`
- Claude Code `2.1.233`, logged in through `claude.ai`
- Codex CLI `0.147.0`, logged in through ChatGPT
- `cc doctor --json`: score `92`, online, status `update-available`
- The current installed `cc update --json` path was observed idempotent with no held or blocked rows.

Use `$protocol` and the normal specialist workflows (`$ta`, `$me`, `$qa`, `$sec`, `$doc`, `$do`, and others) to complete unrelated ecosystem components. Do not use the unfinished evaluator or broker code as evidence that production Codex evaluation calls are authorized.

## Executive verdict

The framework/evaluator candidate is advanced and evidence-rich, but it is not release-ready and no live effectiveness run has started.

- The committed branch is coherent, signed, and three commits ahead of `origin/main`.
- Framework `5.14.11` and `cc 2.12.11` release inputs are prepared.
- The exact 28-cell evaluation system, durable evidence pipeline, assessment/finalization path, no-call readiness, and most security boundaries are implemented and approved in bounded slices.
- Release metadata, the 87-file root lock, packaging contracts, personal fixtures, and the Apple notarization profile pass preflight.
- Six broker/prepared files remain uncommitted.
- The prepared Codex declaration is independently approved but deliberately nonauthorizing.
- The fake/process broker slice is rejected on four concrete defects listed below.
- A real production Codex credential/TLS broker and verifier-owned prepared-cell capability still do not exist.
- Installed signed source and physical materialization still disagree for routed Claude foundation content.
- Live evaluation calls remain `0/28`.

Required companion documents:

- [Phase 5 technical completion plan](../phases/phase-5-technical-ecosystem-completion-plan.md)
- [ADR-010 — technical ecosystem first](../decisions/adr-010-technical-ecosystem-first.md)
- [ADR-011 — solo-owner repository governance](../decisions/adr-011-solo-owner-repository-governance.md)
- [Effectiveness evaluation design](../phases/phase-4-effectiveness-evaluation-design.md)

## Exact Git state

At handoff:

```text
branch: feat/task-285-live-effectiveness-evaluation
origin/main: 9a4bea828dff45e6c16a5e2b2093df9447f62fa1
behind/ahead: 0/3
upstream: not configured
v5.14.11 tag: absent
```

The three commits ahead of `origin/main` have good ENAC ED25519 signatures using key `SHA256:FIfppOkzwXZUAamELQzYoSUQXiEAmTYiVewHe1ACMZo`:

1. `9f1bebdf78e2f268db4f1dfde5105db15835c36a` — `fix(cc): bind coherent shared tier updates`
2. `1ba9eb9d3a2b1c8cba00d9801e0b3be63191a32b` — `feat(eval): checkpoint canonical effectiveness framework`
3. `c19a564184bb56e2ecac4ae968097a0d24f5b121` — `fix(eval): seal readiness and atomic content publication`

Do not squash or rebase away the signed release ancestry. The release verifier expects an ENAC-signed release commit to remain an ancestor of `main`, and the signed tag must name the exact released commit.

## Dirty worktree

Only these six paths are dirty/untracked:

| State | Path | SHA-256 at handoff |
|---|---|---|
| modified | `tools/cc/src/cc/core/evaluation/codex_broker.py` | `2540482ad9e87054cd23b6cda1badcf302fd945b39ef8586b426810bc6d28a23` |
| modified | `tools/cc/tests/evaluation/test_codex_broker.py` | `7139369333e0a3824820d6d1e2cb41078bc87608715e5e690d23a8bc3e7dc0c8` |
| untracked | `tools/cc/src/cc/core/evaluation/codex_broker_process.py` | `de099318e62813b21cebb1f31fe84ec40b9c613cc4eb414876a51cb99f4ba5db` |
| untracked | `tools/cc/tests/evaluation/test_codex_broker_process.py` | `9a75e48c3916d7b9c89e4cbe3d2110fd1d810dd3a52f3a57b4778d139e7a9440` |
| untracked | `tools/cc/src/cc/core/evaluation/prepared_codex.py` | `64de5226abfca41944ab0780aa12e45927b17134c842d3385527f76d912a4c75` |
| untracked | `tools/cc/tests/evaluation/test_prepared_codex.py` | `1517e49071e839a8f21738f984fea84b6f39ee35beea5dc108af561d05261dd7` |

No agent was left editing these files at handoff. Recheck hashes before continuing.

## What is complete

### Release inputs

- Framework version markers align at `5.14.11`.
- `cc` version markers and `uv.lock` align at `2.12.11`.
- Claude plugin and marketplace manifests align with the framework version.
- Codex plugin/catalog/root-lock version remains `0.6.1` as intended.
- Root `copilot.lock.json` is canonical, declares `mutations: []`, and contains exact full-ownership rosters:
  - Claude: 25 paths
  - Codex: 62 paths
  - Total: 87 paths
- `verify-project-lock-coherence.py .` reports `2 components / 87 files`. Treat this standalone verifier as a diagnostic snapshot, not a durable authority after it returns.
- The integrated release packager has the stronger closed before/after source snapshot and is the release authority.
- The release packager sources its entry point from the verified clone and binds the caller/source commit relationship.
- Fixture package data is included in wheel/frozen-artifact checks.

Release preflight evidence:

- version consistency: 3 comparisons passed
- plugin/marketplace manifest: 0 errors, 0 warnings
- lock negative suite: 18 passed
- installer/packager contract: 9 passed
- release-signature contract: 6 passed
- personal fixture suite: 22 passed
- package script SHA-256: `e6b9200612826ba74011cd8319eed8a9ca3160d2dc0a35c64696e2903cceb1f4`

### Exact evaluation package

- Matrix SHA-256: `0c844795668aa2dc40596975ba5e20d3ee2fe345583149d20c9c8a07ef6688f6`
- Case bundle SHA-256: `a2f20f40690ff1ca09312b72575bda5d1600539be06663afa689501c8d418698`
- Personal-layer package SHA-256: `ab0cba88ddde05682c82705bb0b8498b6666ce2e238c143a11c5a4d1d523d357`
- Personal release identity: `834553c2a530658562689645850fbc21f8aabd4af7efbf18ef289e985a9881fa`
- Personal package identity: `708f882d9f1cf3fc54e5b0305ce9ce5f6e46efdc8eafb661dd824241b737776b`
- Personal snapshot identity: `2cd26a8d1f40fbff0e953685b86d1512691f4e47879427b7f73f642c3249d156`
- Raw personal snapshot SHA-256: `2717a259ebaf469f3da1820e3acadc995b13005ffbfb93c16e6bfe4a50f04a4e`

The matrix has exactly 28 cells: 14 Claude and 14 Codex. Routes are preregistered as follows:

- EVAL-01: `sd`
- EVAL-02: `sd`
- EVAL-03: `uids`
- EVAL-04: `cco`
- EVAL-05: `cpa`
- EVAL-06: `ta`
- EVAL-07: `doc`

### Evaluator and evidence pipeline

Implemented and approved in bounded slices:

- exact packaged matrix and route binding;
- sealed Claude and Codex adapters;
- canonical Claude and Codex signed-content projections;
- nearest-winner, shadowing, additive Knowledge, and authenticated-absence semantics;
- entitlement leases and protected Knowledge projection;
- retained runtime input and artifact capabilities;
- atomic attempts, authenticated timeout handling, and bounded technical retry lineage;
- process-group cleanup and descendant reaping;
- durable `UNSUPPORTED` evidence and fresh-process reload;
- private assessor vault;
- durable criterion judgments and comparisons;
- exact 28-cell portfolio, parity, attribution, and blocker logic;
- single-file retained assessment, report, and finalization bundles;
- S-04 continuation and S-05 update evidence;
- phase-one ordering and `awaiting-assessment / not-evaluated` semantics;
- public no-call readiness/CLI integration;
- copy, replacement, nested-substitution, and capability-lifecycle defenses.

The last full evaluation-tree run at a stable checkpoint reported `690 passed`. Numerous later focused/broad slices also passed independently; do not substitute their sum for a fresh final full-suite run.

### Protected Knowledge producer

The new `cc 2.12.11` producer is implemented and independently approved:

- derives every protected layer's signed Codex Knowledge contribution rather than only the global nearest winner;
- stages and verifies all generations before publication;
- journals the old/new state;
- publishes unindexed targets first;
- performs one atomic index switch;
- rolls back all staged/unpublished targets on failure;
- preserves the old index and targets until the switch;
- removes crash-orphan stages.

Focused evidence: 82 tests passed plus targeted transaction/recovery/idempotence checks.

### Readiness and no-call public integration

The canonical readiness report is independently approved as observational and nonauthorizing:

- exact packaged 28-cell order;
- exact `claude-fable-5` and `gpt-5.6-sol` model subjects;
- two exact runtime subjects;
- issuer-owned immutable canonical body;
- copied and nested-mutated reports reject;
- live calls and artifacts are fixed at zero;
- no dispatch surface exists.

Public execution re-verifies the report and still has a separate hard `codex-live-authorization-unavailable` gate. Even a synthetic authentic `READY` report cannot create an artifact root or reach phase one without a distinct production authority.

CLI readiness now emits the canonical report. The exact phase-one schema may return `awaiting-assessment / not-evaluated`; that is successful evidence collection, not effectiveness acceptance.

## Current uncommitted slices

### Prepared Codex declaration — scoped PASS

`prepared_codex.py` is a pure frozen descriptive value only:

- `authority: none`
- `dispatch_authorized: false`
- no issuer, verifier, identity, authorization, lifecycle, current, consume, or replay APIs;
- no registry, lock, weak reference, seal, or hidden capability;
- copied values remain equivalent because they carry no authority;
- self-rehashed documents remain structural and nonauthorizing;
- all 14 packaged Codex declarations remain structurally unique.

Independent QA: 14 tests, Ruff, Black, and diff checks passed.

Downstream code must never accept this declaration as dispatch authority. Production still needs a separate verifier-owned capability derived from authentic retained objects.

### Fake and process broker — scoped REJECTED

The current broker work is synthetic-auth, fake-upstream, loopback-only, and explicitly nonauthorizing. It did not access real credentials or make external/model/API calls. The process seam demonstrates a separate session/process group, READY/GO identity handshake, WAL ordering, TERM-to-KILL cleanup, descendant reaping, and value-suppressing evidence.

Independent QA nevertheless rejected it on four exact defects:

1. `CodexBrokerTestReceipt` can be changed in place to `live_runtime_authorized=True`, self-rehashed, and accepted by its verifier/document function.
2. `CodexBrokerProcessTestReceipt` can have evidence fields such as `outcome` and `upstream_call_count` changed, self-rehashed, and accepted.
3. A malformed non-JSON `egress-intent.json` is classified as retryable `no-call` using filenames rather than validated journal contents.
4. `_RetainedProcessJournal._retain` leaks the opened leaf descriptor when JSON parsing fails before ownership is registered. Fifty malformed loads produced a +50 descriptor delta.

Baseline tests still passed:

- 65 focused broker/process tests;
- 171 combined isolation/dispatch/broker/process tests;
- Ruff, Black, and diff checks;
- no lingering worker processes;
- no real auth, external network, model, or API call.

Required repair:

- bind both receipt verifiers to immutable issuer-retained canonical bodies;
- reassert every fixed invariant during verification;
- cross-bind process receipt fields to retained completion/journal evidence;
- return `invalid` for malformed or unverified restart state;
- close journal descriptors on every pre-registration failure;
- add the four exact adversarial regressions and rerun independent QA.

## What is not implemented

### Production Codex prepared-cell authority

There is no authentic aggregate capability that currently binds, in one verifier-owned one-shot object:

- exact packaged fixture and plan;
- route, journey, and Task Copilot ledger;
- prompt packet;
- parent canonical Codex content projection;
- retained artifact-root identity;
- official staged Codex executable and catalog;
- dispatch authorization and permit;
- requested model and adapter policy.

The descriptive declaration must not fill this role.

### Production Codex credential/network broker

The current broker proves mechanics only against synthetic auth and fake TLS. A production broker must still:

- retain the exact owner-only ChatGPT auth source and parent identities without exposing token bytes to Codex;
- handle freshness/refresh through a separately bounded authority;
- inject authorization/account headers only in the broker's upstream hop;
- connect only to the exact ChatGPT Codex responses endpoint over verified TLS;
- reject redirects, proxies, retries, alternate paths/methods, extra interactions, cookies, and child-provided auth headers;
- accept only the exact closed request schema with no model-visible tools;
- fully validate bounded SSE and reject tool events or unknown output types;
- write and fsync intent, then write and fsync `call-started` immediately before the first possible external connection;
- treat started-but-incomplete calls as consumed and nonretryable;
- run in a killable/reapable process boundary, never an unbounded thread-only boundary;
- kill/reap the worker and descendants before closing credentials, WAL, dispatch, or retained inputs;
- expose only value-suppressing evidence;
- consume exactly one dispatch/permit per cell.

No production consumer may import or treat either fake broker receipt as authorization.

## Installed-source blockers

### Foundation signed source versus physical lock/disk

The current installed manifest pins Claude foundation `v5.14.10`, but routed signed-tag bytes disagree with the current physical lock/materialization:

| Route | Signed `v5.14.10` SHA | Physical lock/disk SHA |
|---|---|---|
| `sd` | `67654f99117f9dd4b9e29568cd137886231e46d3f77971b541b45e2a86e1d4e8` | `b541be30613176bb218ffb4135443f6cc89e9f05651acbca587bd4e505cf2883` |
| `ta` | `a1edc201f99744c655f10b75ebac92229cfbd33a567021ce455226667519ea8d` | `ed58011f50d5ab45ed35f7957ac970880bdc077b36bfbe10ffa468e85025b06a` |

Canonical authority correctly reports `canonical-content-materialized-lock-mismatch`. Do not weaken this check. Publish/install a signed immutable `v5.14.11` release, then materialize from that exact release and prove tag = lock = disk for every routed specialist and Knowledge row.

### Protected organization Knowledge pin

Installed `cc 2.12.10` uses the older global-nearest producer. The physical protected Knowledge lock includes the department Codex pin but omits the organization contributor pin. The new `2.12.11` producer fixes this and is approved, but it is not installed yet.

After installing `2.12.11`, run the canonical update twice and prove:

- organization and department pins both exist where signed contributions exist;
- source receipt, release/ref/tree, binding, plugin digest, lock row, and materialized bytes agree;
- the second update is idempotent;
- receipt and lock generations do not change on the second run.

Preserve the existing accounting Knowledge repository divergence and CLI-authored foundation commits. Do not reset or overwrite those human/CLI-owned states.

## Last no-call readiness observation

A real installed-state, no-model probe before the final readiness-body hardening observed:

- exact cells inspected: 28
- ready: 7
- blocked: 21
- live calls: 0
- artifacts: 0
- blocker classes:
  - `canonical-content-materialized-lock-mismatch`
  - `codex-live-authorization-unavailable`

This is useful diagnostic evidence, not the final authoritative readiness result. Rerun the now-approved sealed readiness issuer only after the immutable release is installed and physical locks are reconciled.

## Task Copilot status

- TASK-285 — `in_progress`, QA required and pending.
- TASK-291 — `pending`, integrated framework security required and pending.
- TASK-297 — completed for the signed shared organization/accounting content slice.
- WP-1104 — signed canonical effectiveness framework checkpoint.
- WP-1103 — bounded/scoped security evidence only; it is not overall TASK-291 approval.

Do not mark TASK-285 or TASK-291 complete before the live-call, finalization, release, and integrated-security gates below are satisfied.

## Correct continuation order

1. Re-read this handoff, ADR-010, ADR-011, and the Phase 5 technical completion plan.
2. Recheck the branch, exact six dirty-path hashes, and `origin/main`. Do not assume the handoff hashes are still current.
3. Repair the four broker defects. Keep the broker synthetic/fake-only until independent QA passes.
4. Independently rerun broker/process tests and the four exact adversarial repros. Do not proceed on a scoped rejection.
5. Design and implement the verifier-owned prepared Codex capability from authentic retained inputs. Do not promote `PreparedCodexCellDeclaration`.
6. Implement the production credential/TLS/process broker as a distinct authority. Keep all real dispatch unreachable until an independent review passes.
7. Integrate the production authority with `CanonicalContentProjection.run_authorized`, one dispatch/permit per cell, crash-safe WAL, exact cleanup, and durable terminal evidence.
8. Add restart/resume and authenticated timeout-retry orchestration. Phase one is currently one-shot.
9. Run the complete `tools/cc` suite, full evaluation suite, conformance/fitness tests, Ruff, Black, and diff checks in a fresh process. Prove zero network/model callbacks during the no-call release gate.
10. Store evidence-bound implementation, QA, and security work products in Task Copilot.
11. Create a final ENAC-signed commit. Push the branch, merge without squash/rebase, and verify the signed commit remains an ancestor of `main`.
12. Create a signed annotated `v5.14.11` tag naming the exact release commit.
13. Build `cc 2.12.11` from the immutable pushed source. Verify wheel and frozen-artifact fixture inventories and exact identities.
14. Sign, notarize, and verify the immutable macOS artifact. The `ct-notary` profile is present and its authoritative `notarytool history` probe succeeded on 2026-08-15.
15. Install the immutable artifact and verify installed `cc version`, runtime manifest, command hashes, matrix, case bundle, personal package, and CLI command surface.
16. Advance the installed framework manifest to the signed `v5.14.11` release.
17. Run canonical `cc update --json` twice and prove signed source = lock = disk, organization + department protected Knowledge pins, and idempotence.
18. Run the final independent no-call release/security gate. Installed readiness must report exact 28 planned cells, zero attempts/calls/artifacts, and either honest blockers or `READY`.
19. Obtain explicit independent authorization for the separate live evaluation run.
20. Execute exactly 28 cells, preserving attempt claims, terminal evidence, and any supported technical retry lineage.
21. Load the retained assessment bundle, obtain the exact signed assessor references, issue 28 judgments and 14 comparisons, then persist the final portfolio/report/finalization bundle.
22. Complete S-04/S-05 consumption, store final evidence-bound QA/security work products, and close TASK-285/TASK-291 only if their exact acceptance contracts pass.
23. Regenerate the eligible fleet census and seek fresh owner approval before any fleet mutation. Evaluation completion does not authorize fleet fan-out.

## Fast verification commands

```bash
# Task and initiative state
cd /Volumes/Dev/Sites/COPILOT/copilot-control-tower
tc task get 285 --json
tc task get 291 --json

# Framework branch and signatures
cd /Volumes/Dev/Sites/COPILOT/.worktrees/claude-copilot-project-source-drift
git fetch --prune origin main
git status --short
git rev-list --left-right --count origin/main...HEAD
git verify-commit 9f1bebdf78e2f268db4f1dfde5105db15835c36a
git verify-commit 1ba9eb9d3a2b1c8cba00d9801e0b3be63191a32b
git verify-commit c19a564184bb56e2ecac4ae968097a0d24f5b121

# Release-input diagnostics
python3 .claude-plugin/check-manifest.py
bash scripts/test-version-consistency.sh
python3 scripts/verify-project-lock-coherence.py .

# Installed tools
$HOME/.local/bin/cc version
$HOME/.local/bin/cc doctor --json
claude auth status --json
codex login status

# Notarization credential doctrine: this is the authoritative probe
xcrun notarytool history \
  --keychain-profile ct-notary \
  --output-format json
```

Do not infer that the notarization profile is missing from one local Keychain lookup failure. Follow the project credential doctrine and retry from the logged-in user's fresh Terminal context.

## Do not do

- Do not start a real model/API evaluation call before the production broker, exact prepared capability, installed readiness, and independent live-call approval all pass.
- Do not treat a fake broker receipt, process test receipt, or prepared declaration as runtime authorization.
- Do not weaken source/lock/materialization checks to make readiness green.
- Do not build, tag, or install from the dirty worktree.
- Do not squash or rebase away the signed release ancestry.
- Do not move an existing tag; publish a new immutable `v5.14.11` tag.
- Do not reset, overwrite, or reconcile away the accounting Knowledge divergence or CLI-authored commits.
- Do not touch the fleet without a regenerated exact census and new owner approval.
- Do not conflate `awaiting-assessment` with accepted effectiveness.
- Do not claim generalized product quality from this bounded evaluation.
- Do not move evaluator resolution, security, signature, or health logic into the Control Tower app. The app must continue to parse CLI truth.

## Definition of done

This work is complete only when all of the following are true:

- the six dirty paths are either removed or committed in an independently approved state;
- full source and installed test gates pass from immutable source;
- signed `v5.14.11` and `cc 2.12.11` are built, notarized, installed, and identity-verified;
- signed source, entitlement, lock, and materialized bytes agree for every routed specialist and protected Knowledge contributor;
- canonical readiness reports exact 28-cell readiness with zero pre-run calls/artifacts;
- the production Codex credential/network/process boundary is independently approved;
- the separately authorized 28-cell run finishes with durable terminal evidence;
- signed assessor evidence produces 28 judgments, 14 comparisons, and an exact final portfolio/report/finalization bundle;
- S-04/S-05 evidence is consumed by the final initiative seam;
- final QA and integrated security work products are evidence-bound and passing;
- TASK-285 and TASK-291 are closed only after those gates pass.

## Prompt for the next developer

> Continue Initiative 06 from `docs/40-initiatives/06-copilot-solution-ecosystem-outcome/handoff/2026-08-15-effectiveness-release-continuation.md`. Claude Copilot and Codex Copilot are usable for normal development, but do not start any live effectiveness call. First verify the exact branch, commits, six dirty files, and hashes. Repair and independently re-audit the four broker defects. Then implement the separate verifier-owned prepared Codex capability and production credential/TLS/process broker without promoting the nonauthorizing declaration or fake receipts. Preserve all no-call readiness, source/lock, one-shot, WAL, cleanup, and signed-release gates. Only after a clean immutable v5.14.11/cc 2.12.11 release is installed and independent security reports READY may the exact 28-cell run begin.
