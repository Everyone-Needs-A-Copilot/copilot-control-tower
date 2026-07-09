# CLAUDE.md — Copilot Control Tower

Guidance for a Claude Code session building this product. Read [`docs/START-HERE.md`](docs/START-HERE.md) for orientation, then the spec in `docs/`.

## What this is

An open-source macOS menu-bar app (Tauri v2) that is the always-on, self-healing **face + supervisor over the `copilot`/`cc` CLI**, plus an **Admin mode** IT setup/deploy tool. Two faces, one binary. See [`docs/00-overview/product-brief.md`](docs/00-overview/product-brief.md).

## The invariants (do not violate)

1. **Parse, never compute.** Control Tower calls CLI verbs (`copilot doctor/update/repair/resolve/deprovision/freshness/publish`) via a **versioned `--json` contract** and renders the result. It contains **no** resolution, sync, signature, merge, or wipe logic of its own. If a decision requires computing ecosystem state, it belongs in the CLI, not here. (Even the merge-conflict chooser is CLI-computed — the app renders the options and passes the choice back.) See [`docs/01-architecture/cli-contract.md`](docs/01-architecture/cli-contract.md).
2. **Single process.** One signed binary = tray + supervisor + scheduler. **No** separate daemon, **no** in-app fallback loop. `launchd` is a **crash-only watchdog** (`KeepAlive={SuccessfulExit:false}`, never `true`). The **CLI self-serializes** via `flock` on `copilot.lock` — the app is not the lock.
3. **Never-destroy.** May freely re-materialize `.claude/` and re-clone read-only mirrors; **never** touches a dirty personal working tree. This holds under writable inheritance: **consumers only ever *pull*** (mirrors stay disposable), an **author's writable authoring checkout is a personal working tree and is protected as one**, and the `copilot publish` push path is **additive** and never governed by re-materialization. See [`docs/01-architecture/inheritance-and-publish.md`](docs/01-architecture/inheritance-and-publish.md).
4. **Security posture is inherited and enforced, never weakened.** No `--skip-verify`, no `--force`. Security-sensitive config is honored only via **compiled-in trust roots** (unchanged) and **signed, inherited org/foundation config** (a signed capability policy); nothing security-critical comes from user-editable local config. Trust roots are compiled-in code, not config.
5. **Route by actor-competence × reversibility, not event-class.** Auto-act on reversible things the user can't judge; escalate to IT what they can't action; ask the user only for non-deferrable decisions about their own data. See architecture §9.
6. **One-way inheritance; secrets never travel in it.** The inheritance model (foundation → org → dept → personal) is enforced **structurally, not by care**:
   - **Secrets never enter inheritance content or any git repo.** Credentials live in a **per-user OS keychain** and/or a **tier-scoped managed secret store** whose endpoint is delivered via **inherited org repo config** (the endpoint is not a secret; access to the store stays gated by the user's own GitHub-team membership); inheritance content carries only `requires_secret: <NAME>` **references**. GitHub is **never** a secret carrier. **Git *push* credentials are always per-user (on-device key), never shared-store material.**
   - **No cross-tier write capability.** No working tree, credential, or sync path that holds **personal** content may have write access to a **shared** (dept/org/foundation) remote.
   - **Sync is pull-only and downward.** Personal content **never** flows up automatically; publishing to a broader tier is always a **separate, human-invoked, distinctly-credentialed** action.
   - **Fail-closed leak-scan on every writable push** — a defense-in-depth **backstop only**; the real guarantee is the structural separation above.
   See [`docs/05-security/credentials-and-boundary.md`](docs/05-security/credentials-and-boundary.md) and [`docs/01-architecture/inheritance-and-publish.md`](docs/01-architecture/inheritance-and-publish.md).

## Tech

- **Tauri v2**, Rust core + minimal web UI (keep the UI tiny — no heavy framework).
- macOS-first; design every OS-integration edge so Windows is a re-skin (see design-distribution §6).
- Invoke the CLI by **absolute, translocation-safe** path; never bare `copilot` (avoids the `gh copilot` collision).

## How to build

The [PRD](docs/02-prd/prd.md) is the plan: **WS-A (the CLI `--json`/`flock` contract, in the `copilot` repo) is the prerequisite** that freezes the schema; then eight app-side workstreams run in parallel. Respect the phase gates (P0–P4) and per-task acceptance criteria. Every workstream must close its assigned red-team findings ([`docs/04-validation/`](docs/04-validation/)).

## Framework

The Claude Copilot framework is **installed** in this repo — agents (`.claude/agents/`, 15 specialists), the protocol and continue commands (`.claude/commands/`), memory (`.claude/memory/`), and `cc/config.json` are all present and wired to the shared registry (`shared_docs`/`knowledge_repo` → `@machine`). Codex Copilot is installed alongside it (`AGENTS.md`, `plugins/codex-copilot`). Use the protocol, agents, and memory for build work; keep this file as the project's source of truth for the invariants above. Re-run `/setup-project` only to refresh or repair the install.

## Guardrails for this session

- Do not start coding the app before the WS-A CLI contract is defined — the app can't supervise a CLI it can't read machine-readably.
- Keep the app a thin skin. If you find yourself re-implementing resolution/sync logic in Rust, stop — it goes in the CLI.
- The UI/UX is designed via **Product Creation Copilot**, not hand-invented. See [`docs/03-design/ui-ux/README.md`](docs/03-design/ui-ux/README.md).
