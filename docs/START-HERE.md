# START HERE — Copilot Control Tower

This repo holds Control Tower's spec + design, and (in a sibling repo) the CLI engine it renders. Read this for orientation; **for the current build state and the immediate next step, read [`HANDOFF.md`](HANDOFF.md) first** — it's the app-build kickoff.

**Start from the corrected model:** [`reference/copilot-solutioning-ecosystem.md`](reference/copilot-solutioning-ecosystem.md) (the canonical CSE model) and [`reference/cse-alignment-decisions.md`](reference/cse-alignment-decisions.md) (the decisions that align this repo to it).

## Where we are

- **Spec + design are complete.** The hardened [`architecture`](01-architecture/architecture.md) (§10 = 25 red-team fixes), the parallel [`PRD`](02-prd/prd.md), the full **Product Creation Copilot design package** ([`product-design/`](product-design/), Phases 1–5) and a **RATIFIED [`SOUL.md`](../SOUL.md) v1.3** at repo root, plus versioned `--json` schemas, threat model, test plan, and launch docs.
- **The CLI engine (WS-A) is underway.** Five core `cc` verbs (`doctor`/`resolve`/`freshness`/`update`/`deprovision`) are built and tested on the **unpushed `ws-a-doctor-slice` branch** in the `claude-copilot` repo (see `HANDOFF.md` → "The engine").
- **The app is not started — that's the current job.** The Tauri v2 menu-bar app has no code yet; milestone 1 is the tray icon wired to `cc doctor --json` + the component-first dropdown. See `HANDOFF.md`.
- **The model is settled:** 4 components (Knowledge / CLI / Claude / Codex Copilot) × 4 layers (foundation / org / dept / personal), component-first.

## Key decisions already locked

- **What Control Tower manages:** the CSE tooling components (Knowledge / CLI / Claude / Codex Copilot) across foundation, org, dept, and personal layers, entitled by GitHub repo access. It does not manage the products/projects you build with that tooling.
- **Copilot Control Tower** — own repo (this one), **open source** (public at launch), Tauri v2, **single process**, macOS-first.
- **Face + supervisor over the CLI, never a second brain** — the load-bearing invariant.
- **Host-aware** (Claude Copilot + Codex Copilot) via detection + `copilot derive` column selection.
- **Two faces:** Operator (end-user client) + Admin (open-source IT setup/deploy tool + docs).
- **`/cli` write-gate:** confirm on writes to systems of record, reads unprompted.

## How to proceed (build order)

1. **Build the app — milestone 1** (the current job): scaffold the Tauri v2 app and get a real tray icon wired to `cc doctor --json`, rendering the honest status + the component-first dropdown. Full brief + the paste-to-begin prompt in [`HANDOFF.md`](HANDOFF.md). The design is already done — build to `docs/product-design/04-experience-design/`, don't re-invent it.
2. **Then Settings, wizard, Admin mode** — Settings writes org/dept/personal repo URLs into the layer manifest the engine reads; the wizard confirms entitled layers via GitHub repo access, keeping questions to a minimum.
3. **Finish/freeze WS-A in `claude-copilot`** as needed — the 5 core verbs exist on `ws-a-doctor-slice` (unpushed); `repair`/`publish` and the freeze decisions are the open follow-ups (see `HANDOFF.md` → "Open decisions").
4. **Run the app workstreams in parallel** — `/orchestrate` on [`02-prd/prd.md`](02-prd/prd.md) (WS-B…WS-I), respecting the dependency spine and phase gates.

## Docs map

| Dir | Contents |
|---|---|
| `00-overview/` | Product brief (reframed to democratization); `soul.md` → pointer to ratified [`SOUL.md`](../SOUL.md) at repo root |
| `01-architecture/` | The architecture; `cli-contract.md`; `inheritance-and-publish.md`; `error-taxonomy.md`; `windows-parity.md`; versioned [`schemas/`](01-architecture/schemas/) |
| `02-prd/` | The parallel PRD (app workstreams WS-B…WS-I) |
| `03-design/` | Three engineering design streams — **process model superseded by `architecture.md`** (banners in place) |
| `product-design/` | The PCC design package (Discovery → Design Challenge), Phases 1–5 done; **the app's UX/UI/copy lives in `04-experience-design/`** |
| `04-validation/` | Two red-team reports + `test-plan.md` |
| `05-security/` | `credentials-and-boundary.md` + `threat-model.md` + `incident-response.md` (done) |
| `06-deployment/` | Deployment/onboarding guides: self-install of the signed app, GitHub repo-access entitlement and onboarding. **Stub** (build-time) |
| `07-contributing/` | Developer guide + `release-and-versioning.md` (done; root `CONTRIBUTING.md`/`CODE_OF_CONDUCT.md`/`SECURITY.md`) |
| `08-observability/` | Telemetry spec (two-channel, `machine_id`, fleet dashboard) |
| `reference/` | Canonical model: [`copilot-solutioning-ecosystem.md`](reference/copilot-solutioning-ecosystem.md) + [`cse-alignment-decisions.md`](reference/cse-alignment-decisions.md); four-tier arch, use cases, `glossary.md`, diagrams |

## What still needs creating (and by what)

- **The app itself** → milestone 1 onward (see [`HANDOFF.md`](HANDOFF.md)); build to the design in `product-design/04-experience-design/`.
- **`06-deployment/` guides** → Admin-mode work (WS-H) + `@agent-doc`, at build time.
- **WS-A finish/freeze** (in `claude-copilot`) → `repair`/`publish` + the freeze decisions (see `HANDOFF.md` → "Open decisions").
- **Real-user validation** → the Admin/IT + multi-writer-author experiences are hypotheses awaiting real operators/writers.
