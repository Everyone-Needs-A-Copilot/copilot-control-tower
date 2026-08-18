# Agent Instructions

> **Status line — rebuilt from evidence, 2026-08-02.** Describes Copilot Control Tower v0.4.0. Superseding the prior version of this file, which described a Tauri v2/Rust stack that is no longer what ships.

## Project Overview

- Project: `copilot-control-tower`
- Description: Open-source native macOS menu-bar app that supervises the `copilot`/`cc` CLI and provides an Admin mode for IT setup and deployment.
- Stack: **Native SwiftUI/AppKit**, compiled by `swiftc` (no Xcode project, no package manager for the app itself). Source lives in [`native/`](native/) — `models.swift`, `cli-client.swift`, `cli-dtos.swift`, `render-state.swift`, `wizard.swift`, `user-settings.swift`, `control-tower-tray.swift` (the User app) plus `admin.swift`/`admin-support.swift` (Admin-only, compiled with `-D CT_ADMIN_BUILD`). Build entry points are `scripts/build-user.command` and `scripts/build-admin.command`; packaging/signing/notarization is `scripts/package-user-release.sh`.
- **The retired Tauri v2/Rust/TypeScript/Vite tree (`src-tauri/`) was removed from this repository in commit `chore: remove retired src-tauri tree`; it survives only in git history.** It was never the shipping stack and was not built by any release script. Do not propose changes there; the shipping app is `native/*.swift`. If you need historical context on a pre-native design decision, read it out of git history and verify against `native/*.swift` before trusting it.
- macOS-only. Windows was designed against the retired Rust core and is formally out of scope; see the superseded banner on `docs/01-architecture/windows-parity.md`.

## Codex Copilot

This project uses the shared `codex-copilot` framework through the project-local plugin link:

- `./plugins/codex-copilot`

Use these native specialist skills when appropriate:

- `$protocol`
- `$launcher`
- `$sd`
- `$uxd`
- `$uids`
- `$uid`
- `$ta`
- `$me`
- `$qa`
- `$ind`
- `$sec`
- `$doc`
- `$do`

## Memory And Skills Copilot

Use the new `cc` CLI for persistent memory, skill discovery, and Copilot config. It replaces the old Skills Copilot and Memory Copilot MCP servers.

- Preferred command: `$HOME/.local/bin/cc`
- Fallback if needed: `cc`, after confirming it resolves to the Claude Copilot CLI and not the system C compiler
- Source: Claude Copilot `tools/cc/`
- Project config: `.claude/cc/config.json`
- Project memory: `.claude/memory/entries/`
- Project skills bridge: `.claude/skills/codex-copilot` -> `plugins/codex-copilot/skills`

When a task needs Copilot config values, run:

```bash
eval "$($HOME/.local/bin/cc env)"
```

Use `cc memory ...` for durable project/global memory and `cc skill ...` to list, search, inspect, and retrieve reusable skills.

### Apple Notarization Credential Doctrine

- This publisher Mac is already provisioned with the `ct-notary` `notarytool`
  profile for team `3SYGVX2HB8`. `.env.release.local` stores only that profile
  name; the Apple credential itself remains in macOS Keychain.
- Unless `notarytool store-credentials` is given an explicit `--keychain`, Apple
  stores and reads the profile from the **Data Protection Keychain**. A
  `security find-generic-password` query against `login.keychain-db` does not
  inspect that store and must never be used to conclude the profile is absent.
- The authoritative probe is
  `xcrun notarytool history --keychain-profile ct-notary --output-format json`.
  Retry a local lookup failure, then re-run it from the logged-in user's fresh
  Terminal session. If any probe succeeds, the profile exists and release work
  must continue without asking Pablo to recreate credentials.
- A single local `No Keychain password item found` result means **temporarily
  unavailable in that process context**, not deleted. Never ask for a new
  app-specific password or open Publisher Setup on that evidence alone.
- Only repeated failure from the logged-in user context, with no later
  successful `notarytool` probe, can justify treating the profile as
  unavailable. A server-side authentication rejection such as HTTP 401 is a
  different condition: report the remote rejection without calling the profile
  missing.
- Local release automation must preflight the profile before an expensive build
  and retry only transient Keychain lookup failures at notarization boundaries.
  It must never bypass verification. See
  `docs/07-contributing/publisher-release-runbook.md#credential-troubleshooting`.

## Live Docs

Before planning or implementing against an installed third-party package API, use Live Docs through `cc`:

```bash
$HOME/.local/bin/cc docs get <package> --topic <area> --json
```

If `cc docs` is unavailable, say so and verify against local package files or official docs before coding.

## Task Management

Use `tc` for task tracking and work-product storage in this repository.

- Preferred command: `tc`
- Fallback if unavailable: `./.venv-tc/bin/tc`
- Use `--json` on commands that support it.

### Core Pattern

1. `tc task get <taskId> --json`
2. do the work
3. `tc wp store --task <taskId> --type <type> --title "..." --content "..." --json`
4. `tc task update <id> --status completed --json`

For three or more related `tc` operations, prefer one `python3` block using `tc.api`. For three or more related `cc` memory/skill operations, use a separate `cc.api` block. Keep `tc` and `cc` API blocks separate.

### QA Gate Convention

Codex Copilot cannot rely on Claude runtime lifecycle hooks such as SessionStart, PreToolUse, or SubagentStop, so implementation work uses explicit `tc` state. This does not change the design-led product creation protocol.

- implementation tasks that need verification should carry `metadata.requiresQa=true`
- `$me` stores an implementation work product and routes to `$qa`
- `$qa` stores a `test` work product with an `ARTIFACT:` marker and a `VERDICT: APPROVED`, `VERDICT: APPROVED-WITH-MINOR-FIXES`, or `VERDICT: REJECTED` token
- `scripts/copilot-gate.sh` can inspect QA-required tasks before closure

Passing QA verdicts must be evidence-bound. Valid artifact markers include `test-run`, `file-check`, `diff-check`, `screenshot-check`, `a11y-check`, and `design-fidelity-check`.

## Framework Rules

- Start new work with `$protocol` unless the correct specialist path is already obvious.
- Use `$launcher` when the correct specialist flow is unclear.
- Read `SOUL.md` before substantial product-facing work and use it to decide whether the direction should be built, reshaped, deferred, or rejected.
- Read `docs/01-architecture/12-architecture-guiding-principles.md` before durable architecture, migration, data, security, performance, AI pipeline, or productized implementation work.
- Use `$ta` before implementation for architecture, refactors, or non-trivial features.
- Use `$me` for implementation once the work is framed.
- Use `$qa` to verify implementation work.
- Use `$do -> $me -> $qa` for infrastructure, CI, deployment, and environment changes that require implementation.
- Use `spawn_agent` only when the user explicitly asks for delegation or parallel subagents.
- Keep plans free of time estimates.

## Decision Instruments

- `SOUL.md` is the product taste and purpose lens. It answers whether a product-facing direction belongs here.
- `docs/01-architecture/12-architecture-guiding-principles.md` is the technical lens. It answers how accepted direction should be built.
- When either file changes the route, state that explicitly before continuing.

## Project-Specific Rules

- Every change to the application must end with a new release. Do not stop at source implementation or local QA: increment the appropriate app version, build from immutable pushed source, sign/notarize/staple the macOS artifact, verify the install artifact, and publish the release and its provenance.
