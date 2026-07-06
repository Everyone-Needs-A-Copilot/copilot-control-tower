# START HERE — Copilot Control Tower

This repo continues the design conversation that produced Control Tower. Read this to know **where we are** and **how to proceed**.

## Where we are

- **The architecture is complete and validated.** [`01-architecture/architecture.md`](01-architecture/architecture.md) is the hardened design; its §10 maps **25 Critical/High** adversarial red-team findings to their fixes. Two red-team reports are in [`04-validation/`](04-validation/).
- **The plan is written.** [`02-prd/prd.md`](02-prd/prd.md) is a parallel, multi-phase PRD: one prerequisite workstream gates eight concurrent app-side workstreams, with per-task acceptance and P0–P4 gates.
- **The build has not started.** No app code exists yet. This repo currently holds the spec + docs.

## Key decisions already locked

- **Copilot Control Tower** — own repo (this one), **open source** (public at launch), Tauri v2, **single process**, macOS-first.
- **Face + supervisor over the CLI, never a second brain** — the load-bearing invariant.
- **Host-aware** (Claude Copilot + Codex Copilot) via detection + `copilot derive` column selection.
- **Two faces:** Operator (end-user client) + Admin (open-source IT setup/deploy tool + docs).
- **`/cli` write-gate:** confirm on writes to systems of record, reads unprompted.

## How to proceed (build order)

1. **WS-A first — the CLI contract.** [`01-architecture/cli-contract.md`](01-architecture/cli-contract.md) defines the `copilot --json` schemas + `flock` + `COPILOT_MANAGED_BY` that must land in the `copilot`/`cc` CLI (in the `claude-copilot` repo) **before** the app can supervise it. Freeze this schema first. Everything else parallelizes off it.
2. **Adopt the framework** — run `/setup-project` here for agents/memory/protocol.
3. **Design the UI/UX via Product Creation Copilot** — [`03-design/ui-ux/README.md`](03-design/ui-ux/README.md). We already did the systems architecture and requirements, so **do not re-run discovery**; use PCC for the visual/interaction design of the menu-bar dropdown, the wizard, the Admin-mode setup UI, and the fleet dashboard (its Figma/Storybook output feeds the engineering workstreams).
4. **Run the workstreams in parallel** — `/orchestrate` on [`02-prd/prd.md`](02-prd/prd.md), respecting the dependency spine (A → B → D → E) and phase gates.

## Docs map

| Dir | Contents |
|---|---|
| `00-overview/` | Product brief; `soul.md` (product essence — to be produced via PCC) |
| `01-architecture/` | The architecture; the CLI-contract prerequisite |
| `02-prd/` | The parallel PRD |
| `03-design/` | Three design streams (core/dist/integration) + the UI/UX track (PCC) |
| `04-validation/` | Two red-team reports (use-case + platform layers) |
| `05-security/` | Security & trust doc (to be written — the enterprise-review enablement) |
| `06-deployment/` | MDM/IT deployment guides + admin runbooks (to be written) |
| `07-contributing/` | Dev setup, build, signing, release (to be written) |
| `reference/` | Self-contained ecosystem context (four-tier arch, use cases, diagrams) |

## What still needs creating (and by what)

- **`00-overview/soul.md` + UI/UX design** → **Product Creation Copilot** (design track).
- **`05-security/security-and-trust.md`** → `@agent-sec` (threat model, signing/verification, what the agent does/never does).
- **`06-deployment/`** guides → Admin-mode work (WS-H) + `@agent-doc`.
- **`07-contributing/`** → WS-D (build/signing/release).
- **The app itself** → the PRD workstreams, once WS-A's contract is frozen.
