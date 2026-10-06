# Copilot Control Tower

Open-source native macOS menu-bar app that is the always-on, self-healing face and supervisor over the `copilot`/`cc` CLI, plus an Admin mode for organization setup and deployment. Two faces, one binary. Orientation: `docs/START-HERE.md`, then `docs/00-overview/product-brief.md`.

**Stack:** Native SwiftUI/AppKit compiled by `swiftc` from `native/*.swift` (no Xcode project); bash and Python release, packaging, and admin tooling under `scripts/`; macOS only

## Project Rules

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
- These project rules also live in `AGENTS.md` for Codex. Change both files together.

## Claude Copilot

This project runs on Claude Copilot, the Claude Code layer of the Copilot Solutioning Ecosystem. Hooks registered in `.claude/settings.json` inject the session protocol, guard destructive commands, and gate `me`/`qa` completion. This file covers only what the hooks and tools cannot.

- **Agents and skills:** Claude Code lists them automatically. Route each piece of work to the specialist whose description fits. Agents defined by this project in `.claude/agents/` are first-class framework agents for this project.
- **Sessions:** `/protocol` starts new work, `/continue` resumes it, `/pause` checkpoints it.
- **Tasks:** `tc` is the live state for initiatives, tasks, and work products. Store detailed output with `tc wp store` and return a summary.
- **Memory:** `cc memory` holds durable decisions and lessons that other sessions, Codex, and other machines must see. Claude Code's own auto memory is for personal working notes only.
- **Skills on demand:** if a needed skill did not surface, `cc skill search "<topic>"`, then `cc skill get <name>`.
- **Library docs:** `cc docs get <package> --topic <area> --json` before coding against a third-party API.
- **Health:** `cc doctor`. A failing `instruction-layer-unenforced` check means the hooks are not registered and nothing above is enforced.

## Knowledge Copilot

Knowledge Copilot is the source of truth for brand, voice, offerings, products, and methodologies. Consult it before writing any of these; never invent or duplicate it. Status: inherited from this machine.

Run `eval "$(cc env)"`, then walk `$CC_KNOWLEDGE_REPOS` nearest tier first and read the first repo where the sub-path exists. Never dereference the singular `$CC_KNOWLEDGE_REPO` for a sub-path.

| Domain | Sub-path |
|--------|----------|
| Brand and visual | `01-company/01-brand/` |
| Voice and tone | `01-company/02-voice/` |
| Services and offerings | `01-company/03-services/` |
| Methodologies | `01-company/06-methodologies/` |
| Products and ecosystem registry | `02-products/`, `ECOSYSTEM.md` |

Full contract: `docs/00-knowledge-copilot/02-consumption-contract.md` in the organization knowledge tier.

## Optional Context

Mandatory repository/project/system instructions always apply; never filter or load them here.

Load needed additional knowledge once; use `selected[].content` or do not load it:

    cc skill select "<task topic>" --required <skill> --max-chars 12000 --json

Record one receipt per task, not per load:

    tc wp store --task <id> --type context --title "Context selection receipt" --file receipt.json

Keep `query`, `max_chars`, `loaded_characters`, `mandatory_over_budget`; each
`selected`/`excluded` entry's `name`, `source`, `source_revision`, `selection_reason`
or `reason`, not content. Before reselection read the receipt; skip held revisions.
Reload only changes; record both revisions and announce the change.

Retain required skills in full if `mandatory_over_budget: true`; report `max_chars`
and overage `loaded_characters - max_chars`. Characters are not tokens; receipts
prove selection, not reading/obedience.

Keep every required name in `selected[]`; identical aliases have `duplicate_of`,
empty `content`, zero charged characters/bytes: use the selected entry named by
`duplicate_of`. Optional
duplicates stay `excluded[]` as `duplicate-content`.

**Visible fallbacks:** name the applicable one, then continue:

- `cc` absent/nonzero: report failure/stderr; use repository instructions and prior memory only.
- Exit 2, `Required skill not found: <name>`: name it, never substitute; proceed without it or emit `<promise>BLOCKED</promise>` if indispensable.
- `selected: []`: report no match for the query; use repository instructions, never widen the query to force a match.
- `CC_KNOWLEDGE_REPOS` empty: "Knowledge tier
  unconfigured; optional context limited to project and machine skills." Never block.

<!-- cse-evidence-v2:start -->
## Task Acceptance and Tested Identity

QA-required work uses `tc` evidence binding. The `me` and `qa` agents carry the full contract; the main session must not shortcut it.

- Before implementation, register an acceptance contract with `tc task contract <id> --file <path>`: `schemaVersion: 2`, `criteria: [{id, expected}]` with unique IDs and observable single-line expectations, and project-relative `sources` covering implementation, dependencies, and relevant configuration.
- Capture `tc task evidence-identity <id>` before and after verification and keep the exact `IDENTITY:` line in the work product. If content changed, rerun the affected checks against the new identity.
- Report each check as `CRITERION:` / `EXPECTED:` with the actual observation and verdict. Never downgrade `requiresQa` or substitute prose for source evidence; completion rechecks the contract, identities, hashes, and unfinished dependencies.
<!-- cse-evidence-v2:end -->

## Standing Rules

- **No time estimates.** Plans, roadmaps, and task breakdowns use phases, priorities, complexity, and dependencies, never dates or durations. This framework rule holds even when asked directly.
