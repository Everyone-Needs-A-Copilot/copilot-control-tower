# Agent Instructions

## Project Overview

- Project: `Copilot Control Tower`
- Description: Open-source native macOS menu-bar app that is the always-on, self-healing face and supervisor over the `copilot`/`cc` CLI, plus an Admin mode for organization setup and deployment. Two faces, one binary. Orientation: `docs/START-HERE.md`, then `docs/00-overview/product-brief.md`.
- Stack: Native SwiftUI/AppKit compiled by `swiftc` from `native/*.swift` (no Xcode project); bash and Python release, packaging, and admin tooling under `scripts/`; macOS only

## Project-Specific Rules

- **Invariant 1, parse, never compute.** The app calls CLI verbs (`copilot auth/doctor/update/resolve/deprovision/freshness/layers`, `cc onboard/workspace`) through a versioned `--json` contract and renders the result. It holds no resolution, sync, signature, merge, or wipe logic. If a decision requires computing ecosystem state, it belongs in the CLI (the sibling `claude-copilot` repo), not here. There is no standalone `repair` or `publish` verb: Git history remediation lives inside `cc onboard`'s routing, and both verbs are deferred (`docs/40-initiatives/02-enac-self-onboarding/decisions/ADR-008-repair-and-publish-deferred.md`). If `publish` is ever built, the merge-conflict chooser is CLI-computed and the app only renders options and passes the choice back. Contract: `docs/01-architecture/cli-contract.md`.
- **Invariant 2, single process.** One signed binary is tray, supervisor, and scheduler. No separate daemon and no in-app fallback loop. `launchd` is a crash-only watchdog (`KeepAlive={SuccessfulExit:false}`, never `true`). The CLI self-serializes via `flock` on `copilot.lock`; the app is not the lock.
- **Invariant 3, never-destroy.** The app may freely re-materialize `.claude/` and re-clone read-only mirrors, but never touches a dirty personal working tree. Consumers only ever pull (mirrors stay disposable), an author's writable authoring checkout is a personal working tree and is protected as one, and the `copilot publish` push path is additive and never governed by re-materialization. See `docs/01-architecture/inheritance-and-publish.md`.
- **Invariant 4, security posture is inherited and enforced, never weakened.** No `--skip-verify`, no `--force`. Security-sensitive config is honored only via compiled-in trust roots and signed, inherited org/foundation config (a signed capability policy). Nothing security-critical comes from user-editable local config. Trust roots are compiled-in code, not config.
- **Invariant 5, route by actor-competence × reversibility, not event class.** Auto-act on reversible things the user cannot judge, escalate to IT what they cannot action, and ask the user only for non-deferrable decisions about their own data. See architecture §9.
- **Invariant 6, one-way inheritance; secrets never travel in it.** The foundation → org → dept → personal model is enforced structurally, not by care. See `docs/05-security/credentials-and-boundary.md` and `docs/01-architecture/inheritance-and-publish.md`.
  - Secrets never enter inheritance content or any git repo. Credentials live in a per-user OS keychain and/or a tier-scoped managed secret store whose endpoint arrives via inherited org repo config (the endpoint is not a secret; access stays gated by the user's own GitHub team membership). Inheritance content carries only `requires_secret: <NAME>` references. GitHub is never a secret carrier. Git push credentials are always per-user (on-device key), never shared-store material.
  - No cross-tier write capability: no working tree, credential, or sync path that holds personal content may have write access to a shared (dept/org/foundation) remote.
  - Sync is pull-only and downward. Personal content never flows up automatically; publishing to a broader tier is always a separate, human-invoked, distinctly-credentialed action.
  - A fail-closed leak scan runs on every writable push, as a defense-in-depth backstop only; the real guarantee is the structural separation above.
- Keep the app a thin skin. If you find yourself re-implementing resolution or sync logic in Swift, stop: it goes in the CLI.
- The shipping app is `native/*.swift` only. The retired Tauri v2/Rust tree (`src-tauri/`) was removed and survives only in git history; never propose changes there, and verify any historical design decision against `native/*.swift` before trusting it. Windows is out of scope.
- Invoke the CLI by an absolute, translocation-safe path, never bare `copilot` (avoids the `gh copilot` collision).
- Build the User app with `scripts/build-user.command` and the Admin app (adds `admin.swift`/`admin-support.swift`, compiled with `-D CT_ADMIN_BUILD`) with `scripts/build-admin.command`. Packaging, signing, and notarization run through `scripts/package-user-release.sh`.
- Every change to the application ends with a new release: increment the app version, build from immutable pushed source, sign, notarize, and staple the macOS artifact, verify the install artifact, and publish the release and its provenance. Do not stop at source implementation or local QA.
- Release credentials are already provisioned; before treating any signing or notarization credential as missing, follow `.claude/rules/release-credentials.md`.
- Remaining app-side work runs against the PRD (`docs/02-prd/prd.md`, WS-B through WS-I): respect its dependency spine, phase gates, and per-task acceptance criteria, and close each workstream's assigned red-team findings in `docs/04-validation/`.
- The UI/UX is designed through Product Creation Copilot, not hand-invented. See `docs/03-design/ui-ux/README.md`.
- `SOUL.md` is the product taste and purpose lens: read it before substantial product-facing work to decide whether a direction should be built, reshaped, deferred, or rejected. `docs/01-architecture/12-architecture-guiding-principles.md` is the technical lens: read it before durable architecture, migration, data, security, or performance work. When either changes the route, say so before continuing.
- This file is the project's source of truth for the invariants above.
- Keep shared project requirements consistent between CLAUDE.md and AGENTS.md; preserve their scope and keep tool-specific instructions in the appropriate entrypoint.

- Read `.claude/rules/release-credentials.md` before release/notarization work; it preserves the full credential-probing and transient-failure doctrine formerly embedded here.
- Before work in a domain named above, read its referenced `.claude/rules/` document. Where it declares `paths:`, apply it only to those paths; where it names a workflow, apply it only during that workflow. Those conditions require explicit reading in Codex, not Claude-style automatic loading.

## Project Commands

- On macOS, root-relative `scripts/build-user.command` and `scripts/build-admin.command` build the native app; use `README.md`, `Building from a tag`, and `docs/07-contributing/publisher-release-runbook.md` for prerequisites, verification, signing, and release effects. No web dev server applies.

## Instruction Scope

- Check applicable nested `AGENTS.md` / `AGENTS.override.md` before working in a subtree. Preserve scoped rules; references and Claude `paths:` frontmatter are not automatic Codex imports.
- Keep shared project requirements consistent with `CLAUDE.md` when present; preserve scope and keep tool-specific routing separate. Do not import either whole entrypoint into the other.

## Codex Copilot

- Use relevant skills exposed in this session. `$protocol` and specialist names are shorthand, not shell commands or requests to spawn agents. Read only task-relevant skills/references.
- Start with `$protocol` unless the specialist is obvious; use `$launcher` when routing is unclear. Apply playbooks locally; if unavailable in the session, inspect `plugins/codex-copilot/skills/<name>/SKILL.md`. Report missing capabilities.

## Output Contract

- Lead with the answer, decision, result, or blocker. Default to 6 sentences or 5 bullets; expand when completeness requires it. Preserve findings, uncertainty, citations, QA evidence, safety warnings, Task/WP identifiers, and blockers.
- For real decisions, give 2–3 concrete outcome options and a short question. Do not manufacture decisions or ask again for authorized work.
- Keep progress brief and material. Report outcome, changed scope, verification, and limitations at completion; store detail in `tc` work products.

## `cc` CLI

- Use `cc` for memory, skills, Live Docs, and configuration; `tc` for tasks/work products. The retired Copilot MCP servers and their `initiative_*`, `memory_*`, and `skill_*` tools do not exist.
- Prefer `$HOME/.local/bin/cc`; verify bare `cc` is not the C compiler. Source: Claude Copilot `tools/cc/`. Config: `.claude/cc/config.json`; memory: `.claude/memory/entries/`.
- When configuration is needed, run `eval "$($HOME/.local/bin/cc env)"`; use returned values instead of machine-specific paths.

## Live Docs

- Before planning or implementing against an installed third-party package API, run `$HOME/.local/bin/cc docs get <package> --topic <area> --json`.
- If `cc docs` is unavailable, state the limitation and verify against local package files or official documentation before coding.

## Knowledge and Optional Context

- For brand, voice, product, or methodology knowledge, hydrate `cc env`; follow project consumption-contract pointers through comma-separated `CC_KNOWLEDGE_REPOS`, nearest tier first, reading the first matching sub-path. Never use singular `CC_KNOWLEDGE_REPO` for sub-path lookup. Report missing sources; never invent company facts.
- Before `cc skill select`, read the current session’s installed specialist-agents shared-behaviors reference, section `Optional Context`; this repository’s older vendored reference lacks that section. Follow its load-once, receipt, and fallback rules; mandatory instructions are never relevance-filtered.

## Task Management

- Track substantial work in `tc` PRDs/tasks and store detailed work products there; create missing records. Use `cc memory` for durable decisions and lessons.
- Prefer `tc`, then `./.venv-tc/bin/tc`; use `--json` where supported. Read `plugins/codex-copilot/skills/task-copilot/SKILL.md` when managing tasks.
- Batch three or more related operations using `tc.api`, or separately `cc.api`, with a verified interpreter. Never mix these APIs in one process.
- Formal initiatives belong in `docs/40-initiatives/NN-slug/`, indexed in `docs/40-initiatives/README.md`, with `README.md`, `phases/`, `decisions/`, and `retrospectives/`. Markdown holds durable rationale/evidence; `tc` owns live state. Never create `docs/initiatives/`.

### QA Gate Convention

- For verification-required implementation, set `metadata.requiresQa=true` and register observable criteria and source scope with `tc task contract <id> --file <path>` (`schemaVersion: 2`) before implementing.
- `$me` stores implementation evidence; `$qa` verifies it. Read their installed evidence contracts for those tasks.
- Capture `tc task evidence-identity <id>` before and after checks, preserve the exact `IDENTITY:` line, and rerun affected checks if the tested content changes.
- Store a task-bound `test` work product with matching `CRITERION:` / `EXPECTED:`, actual observations, inspectable `ARTIFACT:` evidence, untested scope, and one `VERDICT:`. Missing required behavior, bare markers, or stale evidence cannot support approval.
- Before completion, run `tc task check-qa <id> --json` and the setup-installed `scripts/copilot-gate.sh --task <id>`. Never remove `requiresQa` to bypass QA; installed hooks alone prove neither enforcement nor approval.

## Framework Rules

- Experience work starts with `$sd` / `$uxd`; visual direction uses `$uids` before `$uid`. Architecture and non-trivial technical work use `$ta`; `$me` implements and `$qa` verifies.
- Bugs follow `$qa -> $me -> $qa`; security-sensitive work includes `$sec`; infrastructure changes needing implementation follow `$do -> $me -> $qa`.
- Keep changes focused, preserve user work, omit time estimates, and respect the user's authorization and review boundaries.
- Use `spawn_agent` only when the user explicitly requests delegation, subagents, or parallel agent work.

### Delegating to Subagents

- Do not end a subagent prompt with an enumerated reporting checklist.
- The standing return contract is at most three sentences: outcome, root cause if known, and anything anomalous or requiring a decision. Put full evidence in a file and return its path.
- Surface every safety-relevant anomaly in those three sentences; never bury it only in the evidence file.
- Request more depth only when the decision genuinely depends on it.

## Debugging Discipline

When an explanation conflicts with a measurement, follow the measurement and narrow the investigation.

1. Confirm a mechanism exists in the relevant environment, plan, or account before naming it as the cause.
2. State what every diagnostic exercised, including the selected key, config, binary, branch, interpreter, and working directory when relevant.
3. Count failures through one shared dependency as one observation unless that dependency is varied.
4. After two hypotheses are falsified, stop hypothesizing. Read the code that enforces the behavior and cite `file:line`.

## Decision Instruments

- Read `SOUL.md` before substantial product-facing work to decide whether the direction belongs here; report missing or unfilled purpose rather than inventing it.
- Read `docs/01-architecture/12-architecture-guiding-principles.md` for durable architecture, migration, data, security, performance, or AI pipeline decisions. Report a missing reference and use verified project authority.
- When either instrument changes the route, state that before continuing.
