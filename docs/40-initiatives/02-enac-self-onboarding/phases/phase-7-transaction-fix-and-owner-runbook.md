# Phase 7 — Transaction fixed; owner runbook for the remaining live steps

Status: **All 13 gaps' code/decision work shipped and pushed. Live apply (task 215 stage B) and the release (task 216 stage B) are not yet run — both need the owner steps in this document.**

Date: 2026-07-31

Owner: Pablo Alejo

Pickup tasks: `tc` 215 (stage B, the reviewed live apply) and `tc` 216 (stage B, sign/notarize/publish)

Parent PRD: `tc prd 15`, "Phase 7 — Honest ecosystem setup transaction (ENAC gap closure)" (tracker-only, no markdown file); its full-text gap analysis is `tc wp get 354`

Helper repository: `claude-copilot`, branch `feat/adopt-and-project-setup`, pushed to origin at `8a5cfcc`

App repository: `copilot-control-tower`, branch `app-build`

## Purpose

This supersedes [`phase-6-v0.2.4-live-setup-blocker-handoff.md`](phase-6-v0.2.4-live-setup-blocker-handoff.md) as the current pickup document. Phase 6 diagnosed a cross-repository transaction defect and stopped before fixing it. This session closed all 13 gaps PRD 15 named — the false-fast-forward classifier, the mutation-ordering defect, the missing ledger, the under-constrained schema, the mock-only release gate, the non-retryable Try again, the stale docs, and the unratified Accounting entitlement — and ran a read-only forensics pass against the live machine. What remains is not code: it is six git decisions, one credential provisioning step, one reviewed apply, and one signed release, all owner-gated. This document is the runbook for those steps.

## What shipped this session

All commits below are pushed. `claude-copilot feat/adopt-and-project-setup` is at `8a5cfcc` on origin; `copilot-control-tower app-build` carries the matching compat and doc commits.

| Task | Gap | Commit(s) | What it closed |
|---|---|---|---|
| 204 | G-1 | `claude-copilot d0f2869` | Closed 8-state history classifier in `onboard.py` — only a merge-base-proven fast-forward may claim "a clean fast-forward is available"; the other seven states (dirty, ahead-only, diverged, diverged-identical, wrong-origin, unreadable, plus exact) route to the owner instead of being auto-repaired. |
| 205 | G-2 | `claude-copilot 5208681` | Apply now asserts `HEAD == target` as a postcondition; "already at target" and "fast-forwarded" are reported as distinct outcomes instead of collapsing into one. |
| 206 | G-3 | `claude-copilot 24f3c06` | All deterministic preflight — including the closed classifier — now runs before any irreversible GitHub write; a blocked review row now produces zero mutations instead of creating Personal repositories first and blocking after. Note: this commit and its 189 lines of new tests are on `origin/feat/adopt-and-project-setup`, but `tc task get 206` still shows `status: pending` and has no linked work product — a tracker bookkeeping gap to close, not a sign the code is unshipped. |
| 207 | G-4 | `claude-copilot 4e45cd7` | A `completed_actions` ledger is threaded through all 15 result exit paths plus resume hints; "nothing changed" is now only a legal claim on an empty ledger; compensation follows never-destroy (report, never delete). |
| 208 | G-5 | `claude-copilot 8aaa424`, `copilot-control-tower 5e9847e` | Onboard schema bumped to `2.0`: `layers_state` discriminates `reported` from `not-computed`, every `ecosystemLayer` row requires its topology fields, `completed_actions` is required, resume is blocked-only. Fixture synced; `cli-contract.md` carries the versioning note. |
| — | — | `claude-copilot 8a5cfcc` | `cc` version bumped `1.7.16` → `2.0.0` for the schema-2.0 break. |
| — | — | `copilot-control-tower 29a1923` | App compat pins updated to accept `cc` `2.0.0` / schema `2.0`. |
| 212 | G-12 | `copilot-control-tower 68332d8` | `START-HERE.md` corrected to native-app reality. |
| 213 | G-9 | `copilot-control-tower 151d6e9` | ADR-006, ADR-007, ADR-008 written; `cli-contract.md` and `CLAUDE.md` stop naming `repair`/`publish` as verbs that exist. |
| 210, 211 | G-7, G-4b | `copilot-control-tower 2057020` | App-side per-verb `SchemaGate` (onboard now requires schema major 2, every other verb stays major 1), v2.0 DTOs, Try-again gated on CLI-reported retryability, the ledger rendered at every site that used to render a false "nothing changed." `scripts/tests/smoke-scenarios.sh` is green at 138/138 (re-run and confirmed for this document). |
| 209 | G-6 | `copilot-control-tower 1c196e9` | Packaged-binary topology gate: a 16-row, 8-history-state git fixture drives the exact packaged binary (never a mock), asserting zero mutation, schema validity, and source/packaged parity. The old pinned helper fails the gate and a fresh build from the reviewed source passes it, proven both directions. `PKG-01` (the walkthrough acceptance gate) is split into `PKG-01a` (version-shape regex) and `PKG-01b` (runs the packaged binary against a fixture and asserts a schema-2.0-valid populated report); `verify-vendored-cc.sh` is likewise strengthened. |
| 214 | G-13 | owner ratification, 2026-07-31 19:11 | Accounting ratified as a genuine dogfood department; the topology target stays 16 layers and the `initialize` writes for the two empty accounting repos are authorized. |
| 215 (stage A) | — | `claude-copilot 46dcc14` | Read-only live forensics — see [`phase-7-live-run-evidence-stage-a.md`](phase-7-live-run-evidence-stage-a.md) (WP-366). Zero mutations. Stage B (the actual apply) is what this runbook's step 3 covers. |
| 216 (stage A) | — | WP-365 | Blocked at notarization, not at code: the Developer ID signing identity is present and valid, but the `ct-notary` notarytool keychain profile is absent from this machine's keychain and is, by design, owner-provisioned rather than agent-provisioned. Source-side, the branch-push blocker that also existed at the start of this stage is now cleared — `feat/adopt-and-project-setup` reached origin at `8a5cfcc` during this session, so `claude-copilot/scripts/package-cc-macos-release.sh` can build from it once notarization credentials exist. |

Stage A of task 215 found three findings the phase-6 handoff and the task briefs did not anticipate, all recorded in the stage-A evidence doc: a third orphaned Personal remote (`pablitoalejo/codex-copilot-private`, created 2026-07-27, four days before the two phase-6 already knew about); six review rows rather than the three phase-6 expected (three are dirty trees — `knowledge-copilot`, `claude-copilot`, `claude-copilot-private` — all untracked-only litter, not modified tracked files); and all nine locally-missing layers already exist as GitHub repositories, so only `knowledge-copilot-accounting` and `cli-copilot-accounting` are genuinely empty and need `initialize` rather than `download`.

## Owner ratifications, 2026-07-31

Recorded verbatim in `cc memory` (entry `9b30dd30`), all six checkpoints ratified together, "proceed all phases, no further checkpoints":

1. Accounting is a real entitled department; target stays 16 layers; `initialize` writes for the two empty accounting repos are authorized.
2. Phase-6 handoff finding 5 (signed helper returning an empty `layers` array) is corrected — it was a schema/emitter defect (ADR-007), not a PyInstaller packaging defect; no PyInstaller rebuild work is scheduled.
3. ADR-006 (preflighted saga) and ADR-007 (breaking schema bump) are approved.
4. `cli-copilot`, `cli-copilot-internal`, and `codex-copilot` are accepted as manual-resolution cases — the owner resolves them by hand rather than the classifier ever auto-repairing them.
5. `cc publish` is formally deferred (ADR-008); repair semantics live inside `cc onboard`'s own routing for now, not a standalone `cc repair` verb.
6. G-10 (scrub, rotate, publicize `knowledge-copilot` and `cli-copilot`) is sequenced last, after the scrub and credential rotation it depends on.

## Owner runbook

These are the only steps left. They are ordered — do not skip ahead, since step 3 depends on step 1 being resolved and step 4 depends on step 2.

### 1. Resolve the six review rows

The stage-A read-only plan puts six of the sixteen rows in `review`, meaning the apply will not touch them until you decide. Full ancestry evidence, options, and reversibility for the three divergent-history cases is in [`phase-7-live-run-evidence-stage-a.md`](phase-7-live-run-evidence-stage-a.md) §3; this is the short version.

**(a) `cli-copilot` and `cli-copilot-internal`** — recommended: `git fetch origin && git checkout -B main origin/main` in each repo. Both local hotfix-branch commits already exist on `origin` under their own branch names (`origin/hotfix/schema-mismatch-v0.3.1`, `origin/hotfix/schema-mismatch-v0.1.1`) and have git trees byte-identical to the resolved foundation tag, so this loses no content and is fully reversible via reflog even if something goes wrong. Do not delete the hotfix branches unless you're separately done with those branch names — deleting a local ref is not covered by the "zero content loss" claim the way switching branches is.

**(b) `codex-copilot`** — push the one unpushed local commit (`git push origin main`), then decide separately whether to cut a new foundation release tag (`v0.6.2`). These are two independent decisions: the push is pure bookkeeping with no judgment required, while the tag is a release-readiness call — two `SKILL.md` files have real edits on `main` since `v0.6.1` that are not yet in any signed foundation snapshot. Note the design wrinkle this surfaces: foundation releases are deliberately parentless snapshot commits (`verify-foundation-release.sh` enforces this), so the classifier will keep reporting this repo as `diverged` against whatever tag is currently resolved even after a clean push — that is expected shape for a foundation-role repo, not a defect, but it means this row will never reach `reuse` on its own. Resolving it permanently means either cutting the tag (which only ever adds a new immutable snapshot, never rewrites one) or accepting a future classifier refinement that recognizes snapshot-tag foundations as a distinct non-actionable state — neither is scoped into this initiative today.

**(c) The three dirty trees** — `knowledge-copilot`, `claude-copilot` (the untracked project-integration files that predate this initiative), and `claude-copilot-private` each have untracked-only `git status --porcelain` output. Commit what you want kept, or intentionally `.gitignore`/stash what you don't, in each of the three. The classifier will not act on any of them itself — that's the invariant working as designed, not a bug to route around.

### 2. Provision notarization

Task 216 stage A stopped here: the Developer ID Application signing identity (`Developer ID Application: Pablo Alejo Jr (3SYGVX2HB8)`) is present and valid, but the `ct-notary` notarytool keychain profile that `.env.release.local` names is absent, and no `APPLE_NOTARY_KEY_*` environment variables or `.p8` API-key files exist anywhere on this machine. This is deliberate — notarization credentials are owner-provisioned, never agent-accessible, per invariant 4. Run Publisher Setup.app, or `scripts/setup-publisher.sh` from a terminal, to (re)create the `ct-notary` profile with a fresh Apple app-specific password.

### 3. Re-run the live apply (task 215 stage B)

Once step 1's review rows are clear, review the sixteen-row plan one more time (the exact read-only invocation is documented in the stage-A evidence doc §2.1), then perform exactly one apply, through the app or the equivalent headless flow. Acceptance criteria, all must hold:

- All 16 layers are visible under `/Volumes/Dev/Sites/COPILOT` (or an approved replacement root).
- The written manifest carries a populated `source.path` for every layer.
- The three previously-orphaned Personal remotes (`knowledge-copilot-private`, `cli-copilot-private`, and the newly-found `codex-copilot-private`) are adopted as downloads, never recreated.
- The ledger is honest — every "nothing changed" claim corresponds to an empty `completed_actions`, and any partial state is reported exactly, not summarized away.
- Doctor independently verifies the result before the app shows Ready.
- Pre/post repository fingerprints and the GitHub inventory are recorded as evidence, the same shape as the stage-A baseline.

### 4. Cut the release (task 216 stage B)

Follow [`docs/07-contributing/publisher-release-runbook.md`](../../../07-contributing/publisher-release-runbook.md). Recommended app version is `0.3.0` — never reuse `v5.13.18` or `v0.2.4`. Flag for your own attention when you cut it: [`release-and-versioning.md`](../../../07-contributing/release-and-versioning.md) §1.1 defines a MAJOR bump as dropping support for a `schema_version` floor a supported CLI still emits, and the app's onboard `SchemaGate` now requiring major 2 (previously 1.0) arguably fits that definition literally, even though the task brief preferred MINOR on the grounds that no fleet yet depends on the old floor — a real tension, not a settled call, worth five minutes before you tag. Separately, wiring the new packaged-binary topology gate into `.github/workflows/release.yml` needs a cross-repo CI decision that was not made this session: the gate's source-oracle comparison requires CI to also check out and build `claude-copilot`, which `release.yml` cannot do today without a new deploy key or PAT.

### 5. V-5 cold-laptop proof, then publicize (last)

Once the release is cut, run task 218 (the V-5 cold-laptop two-machine onboarding proof — a second machine starting with an empty keychain onboards, clones both mirrors, and resolves every service with no hand-copied secret and no `.env`). Only after that, run task 217 — scrub, rotate, then publicize `knowledge-copilot` and `cli-copilot` from private to public. This is deliberately last: it is irreversible, high blast radius, and gated on the credential rotation the recorded `knowledge-copilot` history exposure requires (see memory entry `knowledge-copilot-live-secrets-in-git` — a prior scrub attempt was cleanly rolled back with nothing pushed, and rotation is still owed before this step).

## Learning path for the next developer

Read in this order before touching code or running the apply:

1. [`SOUL.md`](../../../../SOUL.md), especially parse-never-compute, never-destroy, and actor competence.
2. [`ADR-006-ecosystem-setup-preflighted-saga.md`](../decisions/ADR-006-ecosystem-setup-preflighted-saga.md), [`ADR-007-onboard-schema-v2-breaking-bump.md`](../decisions/ADR-007-onboard-schema-v2-breaking-bump.md), and [`ADR-008-repair-and-publish-deferred.md`](../decisions/ADR-008-repair-and-publish-deferred.md) — the three decisions this phase's code implements.
3. [`phase-7-live-run-evidence-stage-a.md`](phase-7-live-run-evidence-stage-a.md) for the exact live-machine state the runbook above is resolving.
4. [`phase-6-v0.2.4-live-setup-blocker-handoff.md`](phase-6-v0.2.4-live-setup-blocker-handoff.md) for the original diagnosis and the prior release lineage.
5. In `claude-copilot`, `tools/cc/src/cc/commands/onboard.py`, focusing on `_classify_repository_history`, `_apply_visible_topology`, `build_ecosystem_onboard_report`, and `_ecosystem_result`.
6. [`docs/01-architecture/cli-contract.md`](../../../01-architecture/cli-contract.md)'s onboard row and the schema-2.0 versioning note, plus [`onboard.schema.json`](../../../01-architecture/schemas/onboard.schema.json).
7. In Control Tower, `native/cli-dtos.swift`, `native/cli-client.swift`, and `native/wizard.swift` for the per-verb `SchemaGate` and ledger rendering.

## Definition of done

Task 215 closes only when stage B's live apply is complete with the acceptance criteria in step 3 above proven on this Mac, with an evidence-bound QA work product. Task 216 closes only when a signed, notarized, Gatekeeper-accepted, published, downloaded, checksum-verified app and helper release exist — not when the code that makes such a release possible merely exists on `origin`. Neither task may be marked done from source-only or fixture-only evidence.

## Stage B — review-row resolution (2026-08-01)

Status: three of the six stage-A review rows are resolved or advanced by this session (`@agent-me`, owner-approved per the qa dossier's recommendations, executed against real repositories with a backup branch per repo and full pre/post verification). `tc` 215 stage B as a whole is **not** complete — the live 16-row apply (owner runbook step 3 above) has not run, and `codex-copilot`'s foundation release remains a separate owner-gated decision. The three dirty-tree review rows (`knowledge-copilot`, `claude-copilot`, `claude-copilot-private`) were correctly left untouched per the HARD RULE governing this session and per the owner runbook's own step 1(c).

### cli-copilot — resolved (review → reuse)

Pre-action facts reconfirmed live and matched stage A exactly: `git status --porcelain` empty, local HEAD `949f37846cf5993766d3726a1f7fbbd4dbec6b45` on branch `hotfix/schema-mismatch-v0.3.1` contained in `origin/hotfix/schema-mismatch-v0.3.1`, `git diff HEAD origin/main --stat` empty (identical trees), `origin/main` at `48cbcf5055e4b6200e5864ddecc666f96c27bf31`, the peeled commit of tag `v0.3.1`.

Backup branch `backup/pre-phase7-reconcile` created at `949f37846cf5993766d3726a1f7fbbd4dbec6b45` (local only, not pushed) before any ref move. Executed `git checkout -B main origin/main`. Post-verification: `git status --porcelain` empty, `git rev-parse HEAD` == `origin/main` == `48cbcf5055e4b6200e5864ddecc666f96c27bf31`, `git diff backup/pre-phase7-reconcile HEAD --stat` empty (content unchanged). The `hotfix/schema-mismatch-v0.3.1` branch and its `origin` counterpart were never touched and remain fully recoverable.

### cli-copilot-internal — resolved (review → reuse)

Pre-action facts reconfirmed live and matched stage A exactly: `git status --porcelain` empty, local HEAD `380c840f9a15f8c0942cc3984f7973f1f543254c` on branch `hotfix/schema-mismatch-v0.1.1` contained in `origin/hotfix/schema-mismatch-v0.1.1`, `git diff HEAD origin/main --stat` empty, `origin/main` at `b27d45cbe478d551d1d53fc270c1c5d472b4a343`, the peeled commit of tag `v0.1.1`.

Backup branch `backup/pre-phase7-reconcile` created at `380c840f9a15f8c0942cc3984f7973f1f543254c` (local only, not pushed). Executed `git checkout -B main origin/main`. Post-verification: `git status --porcelain` empty, `git rev-parse HEAD` == `origin/main` == `b27d45cbe478d551d1d53fc270c1c5d472b4a343`, `git diff backup/pre-phase7-reconcile HEAD --stat` empty. This repo is the live editable-install source of the `copilot` CLI; `/opt/homebrew/bin/copilot --version` was confirmed still running after the checkout (`copilot-cli 1.4.6`). The `hotfix/schema-mismatch-v0.1.1` branch and its `origin` counterpart were never touched.

### codex-copilot — push done; foundation release deliberately not cut

Pre-action facts reconfirmed live and matched stage A exactly: `git status --porcelain` empty, `main...origin/main [ahead 1]`, exactly one unpushed commit `85acbbe949fe5c7235498d6ceab8c78c4ca1589c` (`feat(skills): require ordered walkthrough filenames`, 2 files changed — `plugins/codex-copilot/skills/uids/SKILL.md` and `plugins/codex-copilot/skills/uxd/SKILL.md`, 5 lines each) — confirmed to be the same mundane bookkeeping commit the stage-A dossier already characterized, not unfinished work.

Executed `git push origin main`; GitHub accepted the fast-forward (`c0639a8..85acbbe`). Post-verification: `origin/main` == local `HEAD` == `85acbbe949fe5c7235498d6ceab8c78c4ca1589c`; no divergence remains for the push leg.

**Stopped on cutting `v0.6.2` — the recipe's own gate refuses it, so nothing was hand-rolled.** Located the canonical recipe: `copilot-control-tower/scripts/foundation-snapshot-release.py`, documented at `copilot-control-tower/docs/06-deployment/foundation-release-signing.md` (there is no release-cutting script inside `codex-copilot/scripts/`; `claude-copilot/scripts/verify-foundation-release.sh` is a verify-only companion — read for context only, never executed, and `claude-copilot`'s own dirty tree was never touched). The recipe requires a dedicated ENAC foundation release SSH signing key plus an explicitly approved `SHA256:` fingerprint (`--signing-key` / `--approved-fingerprint`), and the doc's own "Current status" section states plainly: "Public release tags and compiled signer fingerprints remain blocked until a dedicated ENAC release key is selected, registered, and approved." This machine's filesystem and keychain were searched for any such key or fingerprint — none exists. That is a hard trust gate, not a missing convenience, so `v0.6.2` was not cut; `codex-copilot`'s foundation row remains `diverged`/`review`, exactly as this runbook's own step 1(b) already anticipated ("this row will never reach `reuse` on its own"). The manifest pin (`ecosystem.yml`'s `foundation.refs.codex: "^0.6.0"`, resolved live via `gh api` from the org handoff repo `claude-copilot-internal`, not a local file in any repo touched this session) was left untouched since there is no new tag for it to accept.

### Final verification — read-only plan re-run

Ran the documented invocation from `/Volumes/Dev/Sites/COPILOT/claude-copilot/tools/cc` (local HEAD `8a5cfccd3069889023310b6da3491e4e76517b97`, matching this runbook's own header pin `8a5cfcc`): `TMPDIR=/tmp uv run cc onboard --org auto --products claude,codex --repository-root /Volumes/Dev/Sites/COPILOT --json`. Exit 0, `schema_version: "2.0"`, `result: "changes-required"`, `completed_actions: []`.

Zero-mutation re-fingerprint: the manifest's SHA-256 and mtime are byte-identical to the stage-A baseline (`f9d471649fb9262bfc91fb8ae4d2f851a83c91a8675a6124f003becd8da9762d`, `2026-07-30T14:51:12-0400`); all three repos touched this session (`cli-copilot`, `cli-copilot-internal`, `codex-copilot`) show identical HEAD/branch/porcelain immediately before and after the plan run; the three untouchable repos (`knowledge-copilot`, `claude-copilot`, `claude-copilot-private`) were reconfirmed unchanged from their stage-A HEAD and dirty-line-count baselines — `claude-copilot`'s own HEAD having advanced to `8a5cfcc` between stage A and now is pre-existing upstream dev-branch history that this runbook's own header already records, not a mutation performed by this session; no git command was run against `claude-copilot` at any point, only file reads.

### New 16-row classification (before → after)

| Product | Role | Repository | Stage A (before) | Stage B (after) |
|---|---|---|---|---|
| knowledge | personal | knowledge-copilot-private | download | download (unchanged) |
| knowledge | department | knowledge-copilot-accounting | initialize | initialize (unchanged) |
| knowledge | organization | knowledge-copilot-internal | reuse (current) | reuse (current), unchanged |
| knowledge | foundation | knowledge-copilot | review (local-changes) | review (local-changes) — untouched, HARD RULE |
| cli | personal | cli-copilot-private | download | download (unchanged) |
| cli | department | cli-copilot-accounting | initialize | initialize (unchanged) |
| cli | organization | cli-copilot-internal | review (diverged-identical) | **reuse (current) — resolved** |
| cli | foundation | cli-copilot | review (diverged-identical) | **repair (behind) — advanced, see finding below** |
| claude | personal | claude-copilot-private | review (local-changes) | review (local-changes) — untouched, HARD RULE |
| claude | department | claude-copilot-accounting | download | download (unchanged) |
| claude | organization | claude-copilot-internal | download | download (unchanged) |
| claude | foundation | claude-copilot | review (local-changes) | review (local-changes) — untouched, HARD RULE |
| codex | personal | codex-copilot-private | download | download (unchanged) |
| codex | department | codex-copilot-accounting | download | download (unchanged) |
| codex | organization | codex-copilot-internal | download | download (unchanged) |
| codex | foundation | codex-copilot | review (diverged) | review (diverged) — unchanged by design, release gated (see above) |

### Finding: `cli-copilot`'s foundation row lands on `repair`, not `reuse` — a classifier quirk, not a git-state defect

The stage-A dossier's recommended option for `cli-copilot` predicted this row would reach a durable `current`/`reuse` state after the checkout. Live re-verification instead shows `behind`/`repair`. Root cause, traced and reproduced directly against `claude-copilot/tools/cc/src/cc/commands/onboard.py:778` (`_classify_repository_history`, read-only — not edited, since `claude-copilot` is untouchable this session): for the foundation role, the classifier fetches the resolved ref by name (`git fetch <repo> v0.3.1`) and compares local `HEAD` to `FETCH_HEAD`. For an **annotated** tag, `FETCH_HEAD` resolves to the tag object's own SHA (`c4be6cc7e9934906926201051534ff76a672f5db`), not the peeled commit it points at (`48cbcf5055e4b6200e5864ddecc666f96c27bf31`) — reproduced directly: `git fetch git@github-work:Everyone-Needs-A-Copilot/cli-copilot.git v0.3.1` sets `FETCH_HEAD` to the tag object, while `git rev-parse v0.3.1^{}` gives the different, peeled commit SHA. Since local `HEAD` is a commit and can never literally equal a tag object's own SHA, the classifier's exact-match branch (`head_sha == target_sha`) can never succeed for a foundation role pinned to an annotated version tag, no matter how current the checkout is; it falls through to the forward-ancestor check instead, which does succeed (a commit is its own ancestor), yielding `fast-forwardable`/`behind`/`repair` rather than `exact`/`current`/`reuse`. `cli-copilot-internal`'s organization role does not hit this, because its pin is the branch name `main` rather than a tag, so `FETCH_HEAD` there is an ordinary commit SHA and the exact-match branch works as designed (confirmed: it now reports `reuse`). This is a latent classifier defect scoped to `claude-copilot` — out of scope to fix in this session both because that repo's dirty tree is one of the three untouchable repos and because no further git action against `cli-copilot` itself can change the outcome (it is already checked out at the exact commit the tag resolves to). Recommend a follow-up task against `claude-copilot`, owner-scheduled, to peel annotated tags before comparing (e.g. `git rev-parse "${ref}^{commit}"`, or fetching `refs/tags/${ref}:refs/tags/${ref}` and peeling locally) so foundation-role repos pinned to annotated tags can reach `reuse` the way branch-pinned roles already do. Net effect on stage B's eventual apply: `repair` is lower-friction than `review` — the runbook's own step 3 apply will fast-forward it automatically rather than needing a further human decision — so this finding does not block stage B; it is a fidelity gap worth fixing, not a blocker.

### Task bookkeeping

`tc task get 215 --json` confirms the task is still `status: in_progress`, `agent: qa`. This session did not close it — stage B's full live apply (owner runbook step 3) is still outstanding, and `codex-copilot`'s release cut remains owner-gated on step 2 (notarization) and the ENAC foundation release signing key. No `tc` mutation was made this session beyond the confirming read.
