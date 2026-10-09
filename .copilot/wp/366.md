# Phase 7 — Live ecosystem run, Stage A: read-only forensics and plan verification

Status: **Stage A complete. Zero mutations performed. Stage B (the reviewed apply) is a separate, not-yet-run task.**

Date: 2026-07-31, evidence gathered 21:44–21:52 UTC (17:44–17:52 local, America/New_York)

Owner: Pablo Alejo

Task: `tc` 215 (G-8), stage A only — the read-only forensics and plan-verification leg

Prior handoff: [`phase-6-v0.2.4-live-setup-blocker-handoff.md`](phase-6-v0.2.4-live-setup-blocker-handoff.md)

Helper source under test: `claude-copilot` branch `feat/adopt-and-project-setup` @ `8aaa424c602f40882e488fe562291ab96c26dc54`

Executing agent: @agent-qa, in a read-only forensics role — no `--apply`, no ref-moving git command, no repository creation, no push, was run at any point in this session.

## 1. Evidence baseline — the "pre" fingerprint bundle

### 1.1 Local repository fingerprints (the 7 of 16 layers currently visible under `/Volumes/Dev/Sites/COPILOT`)

All timestamps 2026-07-31 21:44 UTC. `status_porcelain` is the untracked/dirty line count from `git status --porcelain`; every line in every one of these repos begins with `??` (untracked-only) — there is not one modified-tracked-file (`M`, `A`, `D`) line in any of the seven. That distinction matters for section 3.

| Repo | HEAD | Branch | status_porcelain lines | Origin URL | Origin ls-remote HEAD |
|---|---|---|---:|---|---|
| knowledge-copilot | `ce3e1ad37afe81d9f09260b749e8855161883088` | main | 19 (all `??`, framework materialization litter — `.claude/`, `AGENTS.md`, `SOUL.md`, `docs/40-initiatives/`, etc.) | `https://github.com/Everyone-Needs-A-Copilot/knowledge-copilot.git` | `ce3e1ad3...` (matches local HEAD exactly) |
| knowledge-copilot-internal | `8a956014f8290d0c3bd676c8b70eb844a1fa2b82` | main | 0 | `https://github.com/Everyone-Needs-A-Copilot/knowledge-copilot-internal.git` | `8a956014...` on `main` (matches); `dev` branch also present at `c9ba0eee...`, unrelated to this checkout |
| cli-copilot | `949f37846cf5993766d3726a1f7fbbd4dbec6b45` | hotfix/schema-mismatch-v0.3.1 | 0 | `https://github.com/Everyone-Needs-A-Copilot/cli-copilot.git` | `main`/HEAD at `48cbcf5055e4b6200e5864ddecc666f96c27bf31` — does not match local branch tip; see section 3.1 |
| cli-copilot-internal | `380c840f9a15f8c0942cc3984f7973f1f543254c` | hotfix/schema-mismatch-v0.1.1 | 0 | `https://github.com/Everyone-Needs-A-Copilot/cli-copilot-internal.git` | `main`/HEAD at `b27d45cbe478d551d1d53fc270c1c5d472b4a343` — does not match local branch tip; see section 3.2 |
| claude-copilot | `8aaa424c602f40882e488fe562291ab96c26dc54` | feat/adopt-and-project-setup | 10 (all `??` — `.agents/`, `dist/`, `docs/40-initiatives/`, `scripts/copilot-gate.sh`, etc.) | `https://github.com/Everyone-Needs-A-Copilot/claude-copilot.git` | `main`/HEAD at `ff89280a406ebf061107bf620179f0fae8ba5abf`; the same-named remote branch `feat/adopt-and-project-setup` is at `761c0dc83b57a8e064473eb70072f61242c5cde9`, i.e. local is ahead of its own remote tracking branch by unpushed commits — this is the helper's own dev repo, not a topology row problem, and is out of scope for section 3 |
| claude-copilot-private | `5c0f810375da824ebf23cd9973befa167a1e442c` | main | 21 (all `??` — `.claude/`, `memory/entries/*.md` x10, `plugins/`, etc.) | `https://github.com/pablitoalejo/claude-copilot-private.git` | `5febc1e0...` — does not match local HEAD (local is behind by an unrecorded amount; this repo's row classifies as `local-changes`/review before any ahead/behind comparison ever runs, per the classifier's dirty-tree short-circuit — see section 2.4) |
| codex-copilot | `85acbbe949fe5c7235498d6ceab8c78c4ca1589c` | main | 0 | `https://github.com/Everyone-Needs-A-Copilot/codex-copilot.git` | `main`/HEAD at `c0639a8304789dedce4e5aee94edb26476e56f91` — local is 1 unpushed commit ahead of its own `origin/main`; see section 3.3 |

### 1.2 Manifest fingerprint

Path: `/Users/pabs/.config/copilot/copilot.layers.yml`. SHA-256: `f9d471649fb9262bfc91fb8ae4d2f851a83c91a8675a6124f003becd8da9762d`. mtime: `2026-07-30T14:51:12-0400` (epoch `1785437472`). 90 lines, `version: 1`, 8 layers (CLI, Claude, Codex; no Knowledge entries beyond org, no Department entries), all reachable `source.path` fields null.

### 1.3 GitHub inventory across both accounts

Authenticated as `pablitoalejo` (keyring, scopes `admin:org gist repo workflow write:ssh_signing_key`). Both accounts that matter for this topology are reachable from this one token: the `Everyone-Needs-A-Copilot` organization (which hosts every shared-tier ecosystem repo, and, per this machine's registry, every one of Pablo's product repos too — `copilot-control-tower`, `convoco`, `pipeline-copilot`, etc. all live in the same org) and the `pablitoalejo` personal account (which hosts the four `*-copilot-private` personal-tier repos).

**Everyone-Needs-A-Copilot org — the 12 shared-tier ecosystem repos (foundation/organization/department, all 4 components):**

| Repo | Visibility | Created (UTC) | Last pushed (UTC) | Contents when not locally cloned |
|---|---|---|---|---|
| knowledge-copilot | private | — (present locally, foundation) | — | n/a, cloned |
| knowledge-copilot-internal | private | — (present locally, organization) | — | n/a, cloned |
| knowledge-copilot-accounting | private | 2026-07-24T14:10:12Z | 2026-07-24T14:10:13Z | **empty** — `gh api .../contents` returns 404 |
| cli-copilot | private | — (present locally, foundation) | — | n/a, cloned |
| cli-copilot-internal | private | — (present locally, organization) | — | n/a, cloned |
| cli-copilot-accounting | private | 2026-07-24T14:10:14Z | 2026-07-24T14:10:15Z | **empty** — 404 |
| claude-copilot | public | — (present locally, foundation) | — | n/a, cloned |
| claude-copilot-internal | private | 2026-07-24T13:55:36Z | 2026-07-24T14:52:21Z | seeded — `copilot.layer.yml`, `ecosystem.yml` (the org handoff file, size 2 KB) |
| claude-copilot-accounting | private | 2026-07-24T14:10:07Z | 2026-07-24T14:10:21Z | seeded — `copilot.layer.yml` |
| codex-copilot | public | — (present locally, foundation) | — | n/a, cloned |
| codex-copilot-internal | private | 2026-07-24T13:55:38Z | 2026-07-24T13:55:51Z | seeded — `copilot.layer.yml` |
| codex-copilot-accounting | private | 2026-07-24T14:10:09Z | 2026-07-24T14:10:22Z | seeded — `copilot.layer.yml` |

**pablitoalejo personal account — the 4 personal-tier repos:**

| Repo | Visibility | Created (UTC) | Last pushed (UTC) | Local checkout | Contents |
|---|---|---|---|---|---|
| claude-copilot-private | private | 2026-07-04T13:09:08Z | 2026-07-27T20:34:54Z | present | full working tree |
| cli-copilot-private | private | **2026-07-31T18:27:57Z** | 2026-07-31T18:28:00Z | **missing** | seeded — `copilot.layer.yml` only |
| knowledge-copilot-private | private | **2026-07-31T18:27:55Z** | 2026-07-31T18:27:59Z | **missing** | seeded — `copilot.layer.yml` only |
| codex-copilot-private | private | **2026-07-27T20:34:52Z** | 2026-07-27T20:34:55Z | **missing** | seeded — `copilot.layer.yml` only |

**GitHub inventory surprise, flagged for the reviewer:** the task briefing for this run named exactly two orphaned Personal remotes (`knowledge-copilot-private`, `cli-copilot-private`, both created 2026-07-31T18:27Z by the earlier blocked apply documented in phase 6). Live inventory shows a **third** orphaned Personal remote, `pablitoalejo/codex-copilot-private`, created four days earlier (2026-07-27T20:34:52Z) — evidently seeded by a still-earlier attempt that the phase-6 handoff never recorded. It is seeded identically to the other two (`copilot.layer.yml` only) and must be treated exactly the same way: adopted/downloaded on a future apply, never recreated.

**Second GitHub inventory surprise:** all nine of the locally-missing layers already exist as GitHub repositories — none are truly greenfield. Two (`knowledge-copilot-accounting`, `cli-copilot-accounting`) are genuinely empty (0 files, 404 on contents) and correctly need an `initialize` action rather than a straight download. The other seven are pre-seeded with at least `copilot.layer.yml` from earlier interrupted onboarding attempts. This is exactly the read-only plan run's own classification (section 2) — it independently corroborates that the plan's `download`/`initialize` split is correct and that a future apply must never call GitHub repo-create for any of these nine.

## 2. Read-only plan run with the real (fixed) helper

### 2.1 Invocation

Followed the exact documented read-only invocation from the phase-6 handoff, against the source checkout at the commit named in this task's brief:

```bash
cd /Volumes/Dev/Sites/COPILOT/claude-copilot/tools/cc
TMPDIR=/tmp uv run cc onboard \
  --org auto \
  --products claude,codex \
  --repository-root /Volumes/Dev/Sites/COPILOT \
  --json
```

Exit code 0, non-empty stdout, empty stderr. As a bonus parity check, the same invocation was also run against the unsigned dev binary at `/Volumes/Dev/Sites/COPILOT/copilot-control-tower/.copilot/build-cache/cc-fresh/8aaa424c602f40882e488fe562291ab96c26dc54/cc` (per its `BUILD_METADATA.json`, built from this exact source commit by `scripts/build-fresh-vendored-cc.sh` for task 209, never a release artifact). Both invocations are read-only: neither one passes `--apply`.

### 2.2 Schema validation

Both reports validate cleanly against `docs/01-architecture/schemas/onboard.schema.json`'s `ecosystemReport` branch (schema_version `2.0`) using `jsonschema` 4.26.0 — `schema_version: "2.0"`, `scope: "ecosystem"`, `mode: "plan"`, `layers_state: "reported"` with exactly 16 fully-populated `layers` rows (satisfying the schema's `allOf` constraint that `reported` implies `minItems: 1`, and separately hand-verified as exactly 16, not just ≥1), and `completed_actions: []`.

### 2.3 Source-vs-binary parity

The two JSON reports are byte-for-byte structurally identical after parsing: same 16 sorted `layers`, same `result` (`changes-required`), same `stages`, same `inventory`, same `completed_actions` (`[]`). This directly answers the phase-6 handoff's open concern #5 (source and packaged helper disagreeing on topology shape) for this exact source commit and this exact unsigned dev build — they agree. It does not clear the signed, notarized release artifact, which was not rebuilt or re-tested here; that remains a packaging-gate obligation for whoever cuts the next release.

### 2.4 The 16-row classification table

`org: Everyone-Needs-A-Copilot` (the `--org auto` single-match resolution), `products: [claude, codex]`, `components: [knowledge, cli, claude, codex]`, `result: changes-required`, `layers_state: reported`, `completed_actions: []`.

| Product | Role | Rank | Repository | Local state | Sync state | Remote state | Action |
|---|---|---:|---|---|---|---|---|
| knowledge | personal | 10 | knowledge-copilot-private | missing | not-checked | ready | download |
| knowledge | department | 20 | knowledge-copilot-accounting | missing | not-checked | **empty** | **initialize** |
| knowledge | organization | 30 | knowledge-copilot-internal | visible | current | ready | **reuse** |
| knowledge | foundation | 40 | knowledge-copilot | visible | **local-changes** | ready | **review** |
| cli | personal | 10 | cli-copilot-private | missing | not-checked | ready | download |
| cli | department | 20 | cli-copilot-accounting | missing | not-checked | **empty** | **initialize** |
| cli | organization | 30 | cli-copilot-internal | visible | **diverged-identical** | ready | **review** |
| cli | foundation | 40 | cli-copilot | visible | **diverged-identical** | ready | **review** |
| claude | personal | 10 | claude-copilot-private | visible | **local-changes** | ready | **review** |
| claude | department | 20 | claude-copilot-accounting | missing | not-checked | ready | download |
| claude | organization | 30 | claude-copilot-internal | missing | not-checked | ready | download |
| claude | foundation | 40 | claude-copilot | visible | **local-changes** | ready | **review** |
| codex | personal | 10 | codex-copilot-private | missing | not-checked | ready | download |
| codex | department | 20 | codex-copilot-accounting | missing | not-checked | ready | download |
| codex | organization | 30 | codex-copilot-internal | missing | not-checked | ready | download |
| codex | foundation | 40 | codex-copilot | visible | **diverged** | ready | **review** |

Summary: 4 `download` + 2 `initialize` (the genuinely empty department repos, correctly distinguished from the seeded-but-uncloned ones) + 1 `reuse` + 9 `review` (of which 3 are the previously-known divergent-history cases and — this is the finding worth flagging — 3 more are dirty-tree cases the task brief's framing did not anticipate: `knowledge-copilot`, `claude-copilot`, and `claude-copilot-private` are all held for review purely because `git status --porcelain` is non-empty, and in every one of the three that non-emptiness is 100% untracked framework-materialization litter (`.claude/`, `AGENTS.md`, `SOUL.md`, `memory/entries/*.md`, etc.), not a modified tracked file). The classifier (`_classify_repository_history` in `claude-copilot/tools/cc/src/cc/commands/onboard.py:778`) checks `git status --porcelain` before it ever compares SHAs, and any non-empty output — untracked or modified — routes to `local-changes`/`review` without ever fetching or ancestry-checking. That is the correct, conservative reading of invariant #3 (never touch a dirty tree): the classifier has no way to distinguish "someone's uncommitted edit" from "someone's untracked scratch file" without risking exactly the kind of judgment call this project has decided belongs to a human, so it treats both the same. It does mean 6 of the 7 present repos land on `review`, not the 3 the brief expected — only `knowledge-copilot-internal` is clean enough to `reuse` outright.

Other rows worth narrating: `layer-manifest` stage is `changes-required`/`repair` (grows the current 8-layer manifest to 16, preserving what exists — never a destructive rewrite); `secret-store` is `deferred` (Infisical unreachable on this Mac, existing credentials kept, no blocking); `personal-packages` stage confirms `existing: 4, missing: 0, created: 0` — i.e. the plan run independently agrees with section 1.3 that all four personal GitHub repos already exist and none needs creating; `device-ssh` and `organization-handoff`/`codex-plugin` are all clean `ready`.

### 2.5 Zero-mutation confirmation

Every one of the 7 local repos' `HEAD`, branch, and dirty-line-count, plus the manifest's SHA-256 and mtime, were re-captured after both the source run and the fresh-binary run and diffed against the section 1.1/1.2 baseline: all fields are byte-identical, with no exceptions. The GitHub personal-repo count for the `*-copilot-private` naming pattern was independently re-queried afterward and is still exactly 4, matching the `personal-packages` stage's own `created: 0` self-report. Two consecutive read-only plan invocations against two different binaries produced zero local git mutation and zero GitHub mutation.

## 3. Resolution dossier for the three divergent-history review repos — investigation only, nothing executed

All ancestry facts below come from `git log`, `git rev-list --left-right --count`, `git diff --stat`, `git rev-parse ^{tree}`, and `git branch -r --contains`, run read-only against local object stores (fetches were into the object store only, never into a working tree, index, or ref).

### 3.1 cli-copilot

Local HEAD `949f37846cf5993766d3726a1f7fbbd4dbec6b45` on branch `hotfix/schema-mismatch-v0.3.1`, authored 2026-07-28T11:01:11-04:00 by Pablo Alejo `<pablitoalejo@gmail.com>`, subject `fix(layers): read canonical product manifests safely`. The pin lives in `_layer_manifest`'s hardcoded `LEGACY_FOUNDATION_REFS["cli"] = "^0.3.0"` (`claude-copilot/tools/cc/src/cc/commands/onboard.py:49`), resolved by `_resolve_foundation_ref` against `gh api repos/Everyone-Needs-A-Copilot/cli-copilot/tags` to the highest matching tag, `v0.3.1` → commit `48cbcf5055e4b6200e5864ddecc666f96c27bf31`, authored 2026-07-28T11:46:30-04:00 by the same person but under GitHub's PR-merge identity `<85700047+pablitoalejo@users.noreply.github.com>`, subject `fix(layers): read canonical product manifests safely (#1)` — i.e. this is a squash/rebase-merged PR of the exact local commit. `git rev-list --left-right --count HEAD...v0.3.1` = `1  1` (1 ahead, 1 behind). `git rev-parse HEAD^{tree}` and `v0.3.1^{}^{tree}` are both `e4922c5f562eed5f948959d330c06f1840264703` — identical trees, confirmed by an empty `git diff v0.3.1 HEAD --stat`. Critically, `git branch -r --contains HEAD` returns `origin/hotfix/schema-mismatch-v0.3.1` — the exact local commit already exists on `origin`, under its own branch name; nothing about this local ref is unique to this machine.

Resolution options (none executed):

Option 1, recommended — point the working tree at the published lineage while leaving the hotfix branch untouched: `git -C /Volumes/Dev/Sites/COPILOT/cli-copilot fetch origin main` then `git -C /Volumes/Dev/Sites/COPILOT/cli-copilot checkout -B main origin/main`. Content loss: none (trees are identical). Reversibility: full — the `hotfix/schema-mismatch-v0.3.1` ref is never touched by this sequence and remains checked out on origin too, so even a total local loss recovers it. This is the option that gets the classifier to a durable `current`/`reuse` state on the next plan run without discarding anything.

Option 2 — do nothing; accept `diverged-identical` as a permanent, non-actionable terminal state and let a future classifier revision (or manifest annotation) record the two as content-equivalent. Content loss: none. Reversibility: trivial, since nothing changes. Downside: this row will keep surfacing as `review` on every future plan run until someone acts.

Option 3 — delete the local `hotfix/schema-mismatch-v0.3.1` branch after switching to `main`: adds `git branch -D hotfix/schema-mismatch-v0.3.1` to option 1's sequence. Content loss: none in the tree (the commit is safe on `origin/hotfix/schema-mismatch-v0.3.1`), but it does destroy the *local* ref, which conflicts with this project's never-destroy posture more than option 1 does for no added benefit — not recommended without Pablo explicitly saying he's done with the branch name.

### 3.2 cli-copilot-internal

Structurally identical shape to 3.1. Local HEAD `380c840f9a15f8c0942cc3984f7973f1f543254c` on branch `hotfix/schema-mismatch-v0.1.1`, authored 2026-07-28T11:01:17-04:00, subject `fix(discord): isolate optional hooks from harness turns`. Pin: role `organization` layers always compare against `ref: "main"` in `_layer_manifest`'s `layer_specs` (`onboard.py:1288-1295`) rather than a resolved tag, but `origin/main` happens to sit exactly at the release tag `v0.1.1` here (`git cat-file -t v0.1.1` = `tag`, peeling to commit `b27d45cbe478d551d1d53fc270c1c5d472b4a343`, which equals `origin/main`'s tip) — the GitHub PR merge commit for the same change, subject `fix(discord): isolate optional hooks from harness turns (#6)`, authored under the PR-merge identity. `git rev-list --left-right --count HEAD...v0.1.1` = `1  1`. Trees identical: both `c5e481abba0da2cacd32320fe5d4f813a7c517f8`. `git branch -r --contains HEAD` = `origin/hotfix/schema-mismatch-v0.1.1` — again, the local commit already lives on origin under its own name.

Resolution options mirror 3.1 exactly, substituting the repo path and branch name: Option 1 (recommended) — `git -C /Volumes/Dev/Sites/COPILOT/cli-copilot-internal fetch origin main` then `checkout -B main origin/main`, zero content loss, fully reversible, hotfix branch preserved both locally and on origin. Option 2 — leave as-is, accept the permanent review state. Option 3 — additionally delete the local hotfix branch ref; not recommended for the same reason as 3.1.

### 3.3 codex-copilot

This one is a different shape from the other two, and the task brief's framing ("4 ahead/0 behind v0.6.0, trees differ") does not match today's live resolution — flagged as a finding below. Local HEAD `85acbbe949fe5c7235498d6ceab8c78c4ca1589c` on `main`, and `git status -sb` shows `main...origin/main [ahead 1]` — one ordinary unpushed commit (`feat(skills): require ordered walkthrough filenames`, 2026-07-30) sitting on top of `origin/main`'s tip (`c0639a83`, `chore(release): prepare codex foundation v0.6.1`, 2026-07-27). That part is mundane and has nothing to do with the review-state classification.

The pin, however, is resolved from a different, live source: the org handoff file `Everyone-Needs-A-Copilot/claude-copilot-internal/ecosystem.yml` (fetched by `_load_handoff`, `onboard.py:620`), whose `foundation.refs.codex` value is `"^0.6.0"`. `_resolve_foundation_ref` queries `gh api repos/Everyone-Needs-A-Copilot/codex-copilot/tags`, finds `v0.6.0` and `v0.6.1`, and picks the max — `v0.6.1`, commit `325db12c1cc22e8e8139311e7ebcb2e3b6f442ba`. That commit has **zero parents** — `git log -1 --format='%P' v0.6.1^{}` is empty. This is not accidental drift: `claude-copilot/scripts/verify-foundation-release.sh` hard-requires every foundation release to be "a signed, parentless snapshot commit" (`rev-list --parents -n 1` must return exactly one token), which is this project's deliberate mechanism for shipping a clean, disconnected public release history for foundation tiers, decoupled from internal dev branch history — consistent with this repo's CLAUDE.md invariant #3's description of the `copilot publish` push path as additive and separate from the working tree it's cut from. Given that, `git rev-list --left-right --count HEAD...v0.6.1` = `32  1` is expected shape for a foundation-role repo, not a red flag by itself. What does matter is content: `git diff v0.6.1 HEAD --stat` shows exactly 2 files differ — `plugins/codex-copilot/skills/uids/SKILL.md` and `plugins/codex-copilot/skills/uxd/SKILL.md`, 5 lines changed each — meaning local `main` has made two small, real edits since `v0.6.1` was cut that have not yet been folded into a new foundation snapshot. (Checked separately against the lower tag `v0.6.0` for completeness: `HEAD` is a clean, fast-forward-shaped 4-ahead/0-behind descendant of `v0.6.0` with the expected larger diff of everything landed between the two releases — but `v0.6.0` is not the resolved pin today, `v0.6.1` is, per the `^0.6.0` range's max-match rule, so this comparison is informational only and is why the task brief's "v0.6.0" framing is stale relative to this session's live resolution.)

Resolution options (none executed):

Option 1, recommended for the mundane piece — push the one unpushed local commit so `origin/main` stops silently lagging local dev history: `git -C /Volumes/Dev/Sites/COPILOT/codex-copilot push origin main`. Content loss: none. Reversibility: full (ordinary git history, the owner's own push credentials, trivially revertable). This does not change the `diverged` classification against the `v0.6.1` foundation tag at all, because that comparison is structurally always going to look "diverged" for a parentless-snapshot release process — that's correct, not a defect.

Option 2 — cut a new foundation release (e.g. `v0.6.2`) once the two-file skill diff (and anything else landed on `main` since `v0.6.1`) is judged release-ready, via the existing publish pipeline that produces a signed parentless snapshot and passes `verify-foundation-release.sh`, then let `ecosystem.yml`'s `foundation.refs.codex` range continue to resolve forward to it. Content loss: none — this only adds a new tag; nothing existing is touched. Reversibility: forward-only by design (release tags are meant to be immutable and signed), which is exactly why this is a release-readiness judgment call for the owner, not something a plan/apply transaction should ever decide on its own.

Option 3 — do nothing; accept the `review` gate on this row indefinitely until the owner is ready to either push (option 1) or publish (option 2). Zero risk, fully reversible because nothing happens.

Recommended combination: option 1 now (pure bookkeeping, no judgment required, no divergence-resolution effect) plus option 3 for the actual tag question — defer whether/when to cut `v0.6.2` to Pablo, since that's a real product decision about release readiness, not a mechanical git fix, and it is exactly the kind of decision this dossier exists to surface rather than resolve.

## 4. Task and work-product bookkeeping

`tc task get 215 --json` confirms the task exists, status `pending`, agent `qa`, gated on dependencies `[204, 205, 206, 207, 208, 209, 210, 211, 213, 214]`, `liveMachineAcceptance: true` in its metadata. This document is Stage A evidence only; task 215 as a whole (which also requires the reviewed apply itself) is not being closed here.
