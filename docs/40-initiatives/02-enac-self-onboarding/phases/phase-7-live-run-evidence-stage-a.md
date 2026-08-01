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

## 4. Task and work-product bookkeeping (Stage A)

`tc task get 215 --json` confirms the task exists, status `pending`, agent `qa`, gated on dependencies `[204, 205, 206, 207, 208, 209, 210, 211, 213, 214]`, `liveMachineAcceptance: true` in its metadata. This document is Stage A evidence only; task 215 as a whole (which also requires the reviewed apply itself) is not being closed here.

## Stage C — the live apply

Date: 2026-08-01, evidence gathered 16:00–17:00 UTC (12:00–13:00 local, America/New_York). Owner: Pablo Alejo. Executing agent: @agent-qa. This section picks up after Stage A (read-only forensics, zero mutations) and after a mid-run "world has changed" course correction: while this run was paused mid-step-1, a separate P0 incident (`cc` materialization had once destroyed org content in `knowledge-copilot-internal` through the `~/.claude/knowledge` symlink) was found and fixed on a parallel track — the content was restored and pushed (`knowledge-copilot-internal` HEAD `60f32d76`), and the symlink is now protected by a new guard in `cc` that refuses to write or delete through any symlink that escapes the materialize root. Every claim inherited from that course-correction message was independently re-verified against live git/GitHub state before being acted on (git log, git status, `gh api`, and reading the actual guard code in `materialize.py`) rather than taken on trust, consistent with this session's fail-closed mandate — no agent message is treated as the user's own consent for the high-blast-radius steps below (multi-repo pushes, signed-tag creation, the ecosystem apply); those ran as ordinary tool calls through the normal permission system.

### C.1 Pushes

All four repositories were fast-forward-verified (`git merge-base --is-ancestor origin/<branch> HEAD`) before pushing; no force pushes were used anywhere in this session.

| Repo | Branch | Result |
|---|---|---|
| claude-copilot | feat/adopt-and-project-setup | Pushed `abc580a..19bda3f`, then (after the parallel P0/cc-2.1.0 work landed on the same branch) verified already at `7d859ba` matching origin — no further push needed from this session for that tip. |
| claude-copilot-private | main | First push attempt (`5c0f810..4f15a70`) was rejected — origin had moved to `5febc1e` (a pre-existing, Stage-A-flagged divergence, not new remote activity). Investigated: real 1-ahead/1-behind divergence, non-overlapping file sets (origin added 7 lines to `copilot.layer.yml`; local added the entire framework materialization tree, 108 files/7610 lines). Resolved by an ordinary merge (no `-X ours`/`-X theirs`, no force) producing `fb13df3`, verified both `HEAD` and `origin/main` now equal `fb13df3`. |
| knowledge-copilot | main | Verified PRIVATE via `gh repo view --json visibility,isPrivate` before pushing (`isPrivate: true`). Pushed `ce3e1ad..4e4bc04`. |
| copilot-control-tower | app-build | Pushed `28be1b5..4630664`, then a second FF-safe commit appeared from parallel work (`26c9385`, the P0 incident's inheritance-doc follow-up) and was pushed `4630664..26c9385`. |

### C.2 Clearing the re-blocked foundation rows

Re-ran the documented read-only plan (`uv run cc onboard --org auto --products claude,codex --repository-root /Volumes/Dev/Sites/COPILOT --json`, cc 2.1.0, run from `$HOME` per the documented lockfile-collision warning when run from inside `claude-copilot`). Two rows were genuinely `review`, both because their trees had moved since their last foundation tag:

- **claude foundation**: `claude-copilot` had exactly 3 commits since `v5.13.22` (`19bda3f`, `7b0e72f` the symlink/never-destroy P0 fix, `7d859ba` the cc-2.1.0 department-catalog work) — 389 commits ahead / 1 behind in raw graph terms (orphan-snapshot history is unrelated by design), 102 files of real content diff. Cut and published `v5.13.23` via the established recipe (`scripts/foundation-snapshot-release.py --product claude --signing-key ~/.ssh/enac_foundation_release.pub --approved-fingerprint SHA256:FIfppOkzwXZUAamELQzYoSUQXiEAmTYiVewHe1ACMZo`), dry run first then `--publish`. Source commit `7d859ba`, snapshot commit `caa0e54b`, 46 executable items provenance-verified, commit and tag signatures both independently re-verified afterward with `git verify-tag`/`git verify-commit` against a throwaway `allowedSignersFile` (exit 0, "Good \"git\" signature"). Confirmed the fingerprint is genuinely compiled into `FOUNDATION_ALLOWED_SIGNERS` for both `claude` and `codex` in the live `onboard.py` (the `docs/06-deployment/foundation-release-signing.md` "Current status: blocked" line is stale, as a prior session's memory entry had already flagged).
- **knowledge foundation**: `knowledge-copilot` has no signed-orphan-snapshot convention (`FOUNDATION_ALLOWED_SIGNERS["knowledge"] = ()`, `PRODUCT_LAYOUTS` in the snapshot script has no `knowledge` entry) — its one existing tag, `v0.1.0`, is a plain annotated tag on ordinary ancestry. 1 commit since `v0.1.0` (the materialization-footprint commit). Cut `v0.1.1` as a plain annotated tag (`git tag -a`) directly at the current `HEAD` — an exact-SHA tag rather than a new commit, so the classifier's `head_sha == target_sha` exact-match path applies — and pushed it (private remote, tag push is safe).

Re-ran the read-only plan after both tags: **zero `review` rows** — all 7 previously-visible layers read `current`/`reuse` (including `codex-foundation`, which reaches `reuse` via the classifier's `parentless-snapshot-match` path — content-identical to its already-current `v0.6.2` snapshot, zero parents confirmed — not a new tag). Target met exactly as specified: no row was forced past a genuine review state; both rows that needed a tag got one via the existing, previously-proven recipe, and the third `review` category anticipated by the runbook (architecturally-permanent `diverged-identical` on foundation rows) did not occur here because cutting the new tag at the exact current tree produces `parentless-snapshot-match`/`reuse`, not `diverged-identical`/`review` — confirmed by reading `_classify_repository_history` in `onboard.py:794-939` directly rather than assuming.

### C.3 Pre-apply fingerprint bundle

Captured before the apply: all 8 then-visible-or-about-to-be-visible repos' `HEAD`/branch/`status --porcelain` line count (all 0 dirty except `copilot-control-tower`'s 3 untracked memory-entry files); the manifest's SHA-256 (`f9d471649fb9262bfc91fb8ae4d2f851a83c91a8675a6124f003becd8da9762d`) and mtime (`2026-07-30T14:51:12-0400`) — both byte-identical to the Stage A baseline, confirming nothing had touched the manifest between Stage A and this apply; GitHub inventory for the 4 personal-tier `*-copilot-private` repos (created-at timestamps, for post-apply adoption proof) and confirmation the two department "empty" repos (`knowledge-copilot-accounting`, `cli-copilot-accounting`) were still genuinely empty (404 on contents).

Before running `--apply`, read the actual apply-time code paths (`_apply_visible_topology`, `_seed_department` in `onboard.py`) to confirm by inspection, not assumption, that `download`/`create` actions are pure `git clone` (no `gh repo create` call anywhere in the path) and that `initialize` is a single-file `PUT` of `copilot.layer.yml` into an already-existing empty repo — i.e. the "adopt, never recreate" guarantee for the 3 orphaned personal repos is structural (the `action` field can only become `create` when `remote_state == "missing"`, and all 3 already show `remote_state: "ready"`), not merely a convention this run had to honor by hand.

### C.4 THE APPLY

Invocation: `uv run cc onboard --org auto --products claude,codex --repository-root /Volumes/Dev/Sites/COPILOT --apply --json`, run from `$HOME`. Exit code **1**, `"result": "blocked"`.

**What completed cleanly (12 ledger entries, all independently re-verified against live reality, not just trusted from the JSON):**

- 7 `download` + 2 `initialize` actions all report `outcome: "completed"`. Verified each of the 9 resulting repos' actual on-disk `git rev-parse HEAD` against the ledger's `to_sha` — **9/9 match exactly**.
- All 3 orphaned personal-private repos (`knowledge-copilot-private`, `cli-copilot-private`, `codex-copilot-private`) were adopted, never recreated: re-queried `gh api user/repos` after the apply and confirmed all 4 `*-copilot-private` repos' `created_at` timestamps are byte-identical to the pre-apply baseline (e.g. `codex-copilot-private` still `2026-07-27T20:34:52Z`, `cli-copilot-private` and `knowledge-copilot-private` still `2026-07-31T18:2x:5xZ`).
- All 16 expected repository directories are now visible under `/Volumes/Dev/Sites/COPILOT` (`"stage": "visible-repositories", "result": "ready", "layers": 16"` — independently confirmed by `ls`).
- The 7 previously-visible repos are byte-identical pre/post apply on `HEAD`, branch, and dirty-line-count — no forced checkout, no reset, no unexpected mutation of anything this run didn't itself author.

**What did not complete — the layer-manifest write:**

`_apply_manifest_adoption` wrote the candidate 16-layer manifest over the real path, then called the materialize/update step for real (`dry_run=False`) against that candidate. That step reported `"result": "blocked"` (`blocked: 48, held: 4`), which `onboard.py`'s orchestration (`update_exit != 0` at line 3056) treats as fatal for the whole ecosystem transaction, triggering `blocked_after_write`, which restores the manifest backup and then re-runs the materialize step a second time against the *old* manifest purely to confirm the restore is safe. That confirmation step hit the same two gates again, so `restore_exit != 0`, and the stage self-reported `"result": "rollback-failed"` — the conservative label the code uses whenever it cannot *prove* the rollback, even though the underlying file write did succeed: independently verified the actual manifest file on disk is SHA-256 `f9d471649fb9262bfc91fb8ae4d2f851a83c91a8675a6124f003becd8da9762d`, byte-identical to the pre-apply baseline (mtime bumped to the write/rollback timestamp, content unchanged). This is a real, reproducible finding, not a flake — re-ran `cc update --dry-run --json` against the (still-old, 8-layer) live manifest afterward and got the structurally identical shape (1 `blocked`, 4 `held`) on a smaller scope.

Root-caused both gates by reading the source, not by guessing:

1. **4 `held` items** (`reason: "protected: symlink /Users/pabs/.claude/knowledge resolves to /Volumes/Dev/Sites/COPILOT/knowledge-copilot-internal, which escapes the materialize root ... -- refusing to write or delete through it"`) — this is exactly the P0-fix guard the course-correction predicted, firing on the `claude/knowledge` dimension. It is a `held`, not a `blocked`, outcome in `materialize.py`'s own vocabulary — correct, expected, and by design: knowledge is pull-only/externally-consumed through that symlink and the guard is refusing to write through it, never overwriting anything.
2. **48 `blocked` items** (`reason: "unverified"`) — a separate, pre-existing mechanism: `materialize.py`'s `gate()` call defers to `policy.py`'s `evaluate()`, whose current default fail-closed behavior blocks *any* executable-content item that has no real signature verifier wired in yet, independent of the symlink issue. `update.py`'s own inline comment names this precisely: *"with today's fail-closed policy default (policy.py evaluate() blocks everything unverified), any non-empty resolved+materializable set will report blocked until a real signature verifier lands — this is intentional honesty, not a bug."* That comment is flagged in the code itself as an "OWNER-DEFENSIBLE CHOICE... flag for confirmation at freeze" — i.e. a known, pre-existing, not-yet-resolved product decision, not something introduced by this run. It fires broadly here because the candidate manifest adds 8 brand-new layers (org/department/personal tiers for claude, codex, cli, knowledge) whose executable content has never passed through a real signer.

**This is exactly the scenario flagged in advance and exactly the fail-closed instruction that applies to it: stop and report rather than force.** Forcing past either gate (weakening the policy default, deleting/bypassing the symlink guard, hand-editing the manifest to claim 16 layers without materialization backing it) would violate this project's own invariant #4 (no `--skip-verify`, no `--force`, security posture never weakened). No such workaround was attempted. The manifest remains the pre-apply 8-layer file; the repository topology (16/16 checkouts) is fully complete and independently verified; the gap is specifically the manifest-adoption step of the transaction, which is architecturally coupled (by `onboard.py`'s current design) to a materialize policy gate that, as currently built, will block on *any* apply that introduces new unverified layers — this is not specific to today's content and would recur on a clean re-run for the same structural reason.

### C.5 Post-verification

- **16/16 repos visible**: confirmed (`claude-copilot`, `claude-copilot-accounting`, `claude-copilot-internal`, `claude-copilot-private`, `cli-copilot`, `cli-copilot-accounting`, `cli-copilot-internal`, `cli-copilot-private`, `codex-copilot`, `codex-copilot-accounting`, `codex-copilot-internal`, `codex-copilot-private`, `knowledge-copilot`, `knowledge-copilot-accounting`, `knowledge-copilot-internal`, `knowledge-copilot-private`).
- **Manifest with populated `source.path` for all 16 layers**: **not achieved** — the ADR-005 clause-5 gap is not resolved by this run. Manifest is unchanged from Stage A: SHA-256 `f9d47164...`, 8 layers, `version: 1`, every `source.path` still `null`. Backup of the (byte-identical) pre-apply content exists per the ledger at `/Users/pabs/.config/copilot/.copilot-control-tower-backups/f9d471649fb9262bfc91fb8ae4d2f851a83c91a8675a6124f003becd8da9762d/copilot.layers.yml`.
- **Resolution**: `cc resolve --explain --json` returns a non-empty capability set (53 resolved items against the current 8-layer manifest, `claude-foundation` winning the `agents`/`skills`/`commands` dimensions) — the resolver itself is healthy.
- **Doctor**: `cc doctor --json` reports `score: 96`, `status: "update-available"` (not fully green, honestly reported, not glossed over) — 1 `warn` (`claude-claude-personal-sync`: the materialized `claude-personal` mirror is behind the just-merged `claude-copilot-private` push, repair hint `cc update`, itself gated on the same materialize policy default above) against otherwise-`pass` checkers for every cli/claude/codex sync row this manifest currently tracks.
- **Live `copilot` CLI**: `/opt/homebrew/bin/copilot --version` → `copilot-cli 1.4.6`, exit 0; `copilot layers` (a trivial read-only command) runs cleanly and reads the same manifest, confirming the live daily-use CLI Copilot tool was not broken by this run. (Note for future runs: `/opt/homebrew/bin/copilot` is CLI Copilot's own general-purpose tool — `docker`/`discord`/`docs`/`layers`/`health`/etc. subcommands — not the ecosystem `cc onboard`/`doctor` tool used throughout this runbook; the two share the "copilot" name per the ecosystem's known four-programs-two-names ambiguity, and this section is intentionally checking the former.)
- **Final read-only plan re-run**: **zero `review` rows, and now zero `download`/`initialize` rows too** — all 16 layer rows read `visible`/`current`/`ready`/`reuse`. The only remaining `changes-required` in the whole report is the `layer-manifest` stage itself (`action: "repair"`, `layers: 16`), which is the honestly-stated remaining action from C.4, not a new or different gap.

### C.6 Verdict for Stage C

Task 215's repository-topology objective (16/16 visible, orphaned personals adopted not recreated, no destructive git operations, foundation rows honestly cleared) is **fully met and evidence-bound**. Task 215's manifest objective (a 16-layer manifest with populated `source.path`) is **not met**: the apply is structurally blocked by `cc`'s current fail-closed materialize-policy default combined with `onboard.py`'s all-or-nothing treatment of any non-zero materialize exit code (whether `blocked` or merely `held`) as grounds for a full manifest rollback. This is a `cc` code-level architecture gap, not a live-machine data problem, and is out of scope for this qa run to patch — it belongs with @agent-me / the coordinator to decide whether the manifest-write step should be decoupled from the materialize-content step (so a manifest can legitimately record 16 known layers even while some of their executable content stays `held`/`blocked` pending a real signer), and whether `held` (a passive, protective non-write) should ever have shared fatal-rollback treatment with `blocked` (an active refusal) in the first place. Re-running the exact same apply again is expected to reproduce the identical `blocked` outcome for the identical structural reason, so it was not retried blindly.

## Stage C completion — second course correction, second independent blocker

Date: 2026-08-01, evidence gathered 17:15–18:40 UTC (13:15–14:40 local, America/New_York). A second coordinator message reported the C.6 blocker fixed in `cc` 2.1.1 (origin `1bbf091` on `feat/adopt-and-project-setup`) and asked this run to finish. As with the first course correction, every claim was independently re-verified before being acted on rather than trusted — the fix commit was read in full (`git show 1bbf091`), the branch was fetched and fast-forward-confirmed rather than blind-pulled, and the predicted "48→1 blocked" shape was checked with a read-only `cc update --dry-run` before any live apply was attempted again.

### D.1 Re-established bearings

`claude-copilot` fetched and fast-forwarded cleanly to `1bbf091` (already there — a parallel track had landed it), clean tree, `cc --version` confirmed `2.1.1` from `$HOME`. Re-fingerprinted all 16 now-visible repos (all clean, all `HEAD`s matching the C.4 post-apply state) and the manifest (still SHA-256 `f9d47164...`, unchanged).

### D.2 Independently verified the fix, not just the commit message

Read the actual diff (`git show 1bbf091 -- tools/cc/src/cc/commands/onboard.py tools/cc/src/cc/core/ecosystem/materialize.py tools/cc/src/cc/core/ecosystem/policy.py`) rather than trusting the commit message. Confirmed: (1) the manifest write now only rolls back on a genuine environment failure (`update_exit not in (0, 1)`, or an exception) — a `held`/`blocked` (exit 1) materialize outcome is surfaced honestly in a new, additive `report["materialize"]` field and no longer invalidates the transaction; (2) rollback confirmation is now a direct byte comparison of the manifest file, never a second run of the materialize/policy gates against the restored manifest — the exact conflation this session's C.4 incident hit; (3) `verify_git_item` now accepts an optional `ref` and is scoped to the layer's actually-pinned commit when it resolves locally, falling back to the prior blind-HEAD check otherwise — strictly a tighter check, never a bypass (confirmed by reading the fallback path, not assumed). This is a legitimate fix, not a `--skip-verify`-shaped workaround.

Also found (read-only, not part of the fix but relevant): `claude-foundation` had reverted to `review`/`diverged` in a fresh plan run, because the local branch had moved one more commit past `v5.13.23` (to `1bbf091` itself). A `v5.13.24` tag already existed both locally and pushed to origin (cut by the parallel track landing the fix) — independently verified its signature (`git verify-tag`/`verify-commit`, exit 0, same approved fingerprint) and its tree (`git rev-parse v5.13.24^{}^{tree}` equals current `HEAD^{tree}` exactly) before trusting it. Re-ran the plan: zero review rows, all 16 `reuse`/`current`.

### D.3 Second apply attempt — materialize fix confirmed, a second gate surfaces

`cc onboard --apply` (same invocation) → exit 1, `"result": "blocked"` again, but the shape changed exactly as predicted: `"materialize": {"blocked": 1, "held": 4}` (down from 48 blocked). The `layer-manifest` stage now reports `"result": "rolled-back"` (not `"rollback-failed"`) — the byte-comparison rollback fix is independently confirmed working: `copilot.layers.yml` SHA-256 checked immediately after and is exactly `f9d471649fb9262bfc91fb8ae4d2f851a83c91a8675a6124f003becd8da9762d`, unchanged. **The routed C.6 blocker is confirmed fixed.**

But the transaction still did not complete: `"doctor": {"result": "offline", "score": 48}` — a **new, previously-latent gate**, not mentioned in the second course-correction's prediction. `onboard.py`'s post-materialize health check (`if doctor.get("status") != "healthy": return blocked_after_write(...)`) is untouched by the 2.1.1 fix and still rolls back on anything short of `"healthy"`. Retried the identical apply once more to rule out a transient blip (`gh api rate_limit` showed 4988/5000 remaining, ruling out rate-limiting) — reproduced byte-for-byte identically (`blocked: 1, held: 4`, `doctor: offline, score: 48`) both times, confirming this is deterministic, not flaky.

### D.4 Root-caused the doctor gate without ever touching the real manifest

Rather than guess or force another live write, reconstructed the exact candidate 16-layer manifest read-only by calling `cc`'s own internal `_layer_manifest(...)` (the identical function `onboard.py` itself calls) via a driver script inside the `uv`-managed project environment, serialized it to a throwaway file under `/tmp`, and called `build_doctor_report(_manifest_path=<temp file>)` against that copy only — the real manifest at `/Users/pabs/.config/copilot/copilot.layers.yml` was never touched by this diagnostic. Result: `status: "offline", score: 71`, with 9 non-passing checkers, all `severity: "warn"`, none `"fail"`. Two distinct sub-causes:

- **4 `knowledge-*` layers all read "could not reach remote to verify sync"** (`knowledge-personal`, `knowledge-department-accounting`, `knowledge-organization`, `knowledge-foundation` — including the two that are NOT new, long-established repos). Traced to `component_status.py`'s `_remote_sha_for_layer`: it first tries `git ls-remote <repo> refs/copilot/lock` (a component-sync freshness-pointer convention, `mirror.latest_lock_sha`), independently confirmed empty/absent for `knowledge-copilot-internal` right now (`git ls-remote git@github-work:.../knowledge-copilot-internal.git refs/copilot/lock` returns nothing — a real absence, not a network failure); then falls back to a local mirror-clone HEAD check at `~/.copilot/mirrors/knowledge/<layer-id>` — confirmed by `ls` that `~/.copilot/mirrors/knowledge/` does not exist at all. Both signals are honestly absent because the `knowledge` product's layers have never appeared in any manifest this doctor ladder has checked before this run (Stage A's 8-layer manifest had zero Knowledge entries) — not a defect in this run's data.
- **`claude-department-accounting` and `codex-department-accounting`** show the same "could not reach remote" for the same first-cause (no `refs/copilot/lock` published yet), and their mirror-clone fallback also comes up empty (`~/.copilot/mirrors/` has no `claude-department-accounting`/`codex-department-accounting` directory, unlike `~/.copilot/mirrors/cli/cli-department-accounting`, which *does* exist — apparently created as a side effect of this same run's materialize pass for the `cli`-namespaced mirror convention, while `claude`/`codex` mirrors use a different, non-product-namespaced directory convention that this brand-new layer id was never populated into).

Net: this is a **"cold start" gap independent of the C.6 fix** — a freshness-pointer/mirror-clone health signal designed around already-established foundation/organization-tier layers legitimately cannot be positive for department/personal/knowledge-tier layers on their very first-ever appearance in a manifest, and `onboard.py`'s post-materialize `doctor.status != "healthy"` gate (unchanged by 2.1.1) still treats that honest, non-fatal "offline"/`warn`-only state as grounds to roll back an otherwise-successful, already-verified manifest write. No `fail`-severity checker fired; every one of the 9 non-passing checkers was `warn`. Per this session's own fail-closed mandate, no workaround was attempted (no fabricating a `refs/copilot/lock` ref, no hand-creating mirror-clone directories to satisfy the fallback, no patching the doctor status ladder or the onboard gate) — this belongs with @agent-me/the coordinator, the same way C.6 did, to decide whether the same "manifest write survives an honest imperfection" philosophy that was just applied to `materialize` should also apply to this post-apply `doctor` gate.

### D.5 Final state

The manifest is confirmed unchanged (`f9d471649fb9262bfc91fb8ae4d2f851a83c91a8675a6124f003becd8da9762d`, 8 layers, all `source.path` still `null`) after both retries. `cc layers join` was not exercised this session — the manifest-write step it depends on (a 16-layer base to extend) never completed, so joining the four `accounting-*` department layers individually was not attempted; it would face the identical doctor-gate rollback once it reaches the same health check. `cc resolve --explain --json` continues to return a non-empty capability set (unchanged, 53 items against the still-8-layer manifest). `cc doctor --json` against the live (unchanged) manifest continues to report `score: 96`, `status: "update-available"`, the same single pre-existing `warn`. The live `/opt/homebrew/bin/copilot` CLI (CLI Copilot) is unaffected and still healthy. A final read-only plan re-run shows the same state as C.5: all 16 layer rows `reuse`/`current`, zero `review`, with `layer-manifest` as the sole remaining `changes-required` stage.

### D.6 Verdict for Stage C completion

The specific blocker routed at the end of C.6 (`onboard.py` treating any non-zero materialize exit as fatal, and rollback confirmation re-running the same fail-closed gates against the restored manifest) is **independently confirmed fixed** in `cc` 2.1.1 — verified by reading the diff, verified by the materialize shape changing exactly as predicted (48→1 blocked, 4 held), and verified by the rollback now self-reporting `"rolled-back"` with a byte-identical file instead of the previous false-negative `"rollback-failed"`. Task 215's manifest objective is **still not met**, now blocked by a second, independent, previously-latent gate (the post-materialize `doctor.status != "healthy"` check, tripped by an honest "offline" freshness-pointer/mirror-clone cold-start gap for department/personal/knowledge-tier layers that have never been through this health ladder before). This is not the same bug being routed twice — it is a distinct code path (`doctor.py`/`component_status.py`, not `onboard.py`'s materialize/rollback logic) that the 2.1.1 fix did not touch and was not asked to touch. Routed to @agent-me/the coordinator with full root-cause detail above; not force-workaroundable without fabricating remote refs or local mirror state, which this session's fail-closed mandate rules out.
