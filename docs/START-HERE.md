# START HERE — Copilot Control Tower

This repo holds Control Tower's spec, design, and the native macOS app itself; the CLI engine it renders (`cc`) lives in the sibling `claude-copilot` repo. Read this for orientation, then read [`docs/40-initiatives/02-enac-self-onboarding/phases/phase-8-live-ecosystem-and-connect-experience-handoff.md`](40-initiatives/02-enac-self-onboarding/phases/phase-8-live-ecosystem-and-connect-experience-handoff.md) for the current pickup — the ecosystem is live at 16/16 on the owner's Mac, five releases have shipped, and the open work is a short list of owner-gated actions (an Infisical credential re-mint, a cold-laptop proof, the self-service-provisioning broker) plus a small set of flagged next-build items.

**Start from the corrected model:** [`10-reference/copilot-solutioning-ecosystem.md`](10-reference/copilot-solutioning-ecosystem.md) (the canonical CSE model) and [`10-reference/cse-alignment-decisions.md`](10-reference/cse-alignment-decisions.md) (the decisions that align this repo to it).

**Standing up an organization?** Read [`06-deployment/admin-prerequisites.md`](06-deployment/admin-prerequisites.md) first: what has to be true before setup can run, and the exact GitHub access it needs (and why).

## Where we are

- **Spec + design are complete.** The hardened [`architecture`](01-architecture/architecture.md) (§10 = 25 red-team fixes), the parallel [`PRD`](02-prd/prd.md), the full **Product Creation Copilot design package** ([`product-design/`](product-design/), Phases 1–5), a **RATIFIED [`SOUL.md`](../SOUL.md)**, plus versioned `--json` schemas, threat model, test plan, and launch docs.
- **The app is built and shipped.** Copilot Control Tower is a native macOS **SwiftUI/AppKit** menu-bar app — roughly 19,600 lines of Swift across nine files in [`native/`](../native/) (`control-tower-tray.swift`, `wizard.swift`, `admin.swift`, `admin-support.swift`, `cli-client.swift`, `cli-dtos.swift`, `models.swift`, `render-state.swift`, `user-settings.swift`). It builds as two targets from that shared source tree — the Operator app (tray + wizard, [`scripts/build-user.command`](../scripts/build-user.command)) and the Admin app (adds `admin.swift`/`admin-support.swift` for org setup, [`scripts/build-admin.command`](../scripts/build-admin.command)) — and it is de-mocked against the real CLI, not fixtures. Version **0.2.4** is the latest tagged release (`release/control-tower-0.2.4-b84aa2b`). The earlier **Tauri v2 plan is retired**; the Tauri code that exists is read-only historical reference, not the shipping app (see [`10-reference/cse-alignment-decisions.md`](10-reference/cse-alignment-decisions.md) and `CLAUDE.md` — "This supersedes the prior Tauri v2 / web-UI plan").
- **The CLI engine (`cc`) is a separate repo, actively developed.** It lives at `/Volumes/Dev/Sites/COPILOT/claude-copilot`, under `tools/cc`, currently on branch `feat/adopt-and-project-setup`. The app bundles a signed copy of it at `Contents/Resources/cc` inside the app bundle — the shipped 0.2.4 release carries helper version **cc 1.7.16**.
- **The current job is not new-feature build — it's closing verified gaps in the live ecosystem-setup transaction.** The first owner-run apply of 0.2.4 stopped partway through on `cli-copilot`, after already making an irreversible remote write (creating two Personal GitHub repos) while the UI reported "nothing changed." That is being tracked as Phase 7 of the ENAC self-onboarding initiative — Task Copilot PRD 15, "Honest ecosystem setup transaction (ENAC gap closure)" — with the confirmed diagnosis, the required architecture decisions, and the reproduction steps in [`phase-6-v0.2.4-live-setup-blocker-handoff.md`](40-initiatives/02-enac-self-onboarding/phases/phase-6-v0.2.4-live-setup-blocker-handoff.md), and the resulting ADRs plus fitness functions recorded as `tc wp get 354` (task 203, PRD 15). Do not run a live `cc onboard --apply` on the owner's Mac until that transaction work is done and reviewed.
- **The model is settled:** 4 components (Knowledge / CLI / Claude / Codex Copilot) × 4 layers (foundation / org / dept / personal), component-first.

## Key decisions already locked

- **What Control Tower manages:** the CSE tooling components (Knowledge / CLI / Claude / Codex Copilot) across foundation, org, dept, and personal layers, entitled by GitHub repo access. It does not manage the products/projects you build with that tooling.
- **Copilot Control Tower** — own repo (this one), **open source** (public at launch), **native SwiftUI/AppKit**, **single process**, macOS-first.
- **Face + supervisor over the CLI, never a second brain** — the load-bearing invariant; the app parses `cc --json` and renders it, it computes nothing itself.
- **Host-aware** (Claude Copilot + Codex Copilot) via detection + `copilot derive` column selection.
- **Two faces:** Operator (end-user client) + Admin (open-source IT setup/deploy tool + docs).
- **`/cli` write-gate:** confirm on writes to systems of record, reads unprompted.

## How to proceed

1. **Read the current pickup first:** [`phase-6-v0.2.4-live-setup-blocker-handoff.md`](40-initiatives/02-enac-self-onboarding/phases/phase-6-v0.2.4-live-setup-blocker-handoff.md) has the confirmed diagnosis, the safety instructions (do not click "Try again," do not re-run `cc onboard --apply`), the required product/architecture decisions, and the learning path through the actual code (`onboard.py` in `claude-copilot`, then `native/cli-dtos.swift`, `native/cli-client.swift`, `native/wizard.swift`, `native/user-settings.swift` in this repo).
2. **Pull the gap-analysis and ADRs** with `tc wp get 354 --json` and `tc prd get 15 --json` — they cover the preflighted-saga transaction model (ADR-006), the `layers` contract field (ADR-007), the fitness functions, and which streams can run concurrently versus must serialize on shared files.
3. **Do not add resolution/sync/compute logic to the native app.** Every gap in the current work is a `cc`-side fix (history classification, transaction ordering, schema tightening); the app changes only how it renders the result. This is the same invariant #1 that governed the original build.
4. **Once Phase 7 lands:** remaining app-side work runs against [`02-prd/prd.md`](02-prd/prd.md) (WS-B…WS-I) as before, respecting the dependency spine and phase gates; `06-deployment/` guides are the other open documentation surface (Admin-mode work).
5. **Historical build brief, for context only:** [`HANDOFF.md`](HANDOFF.md) was the original build-from-zero brief (superseded — the build finished); [`RESUME-HERE.md`](RESUME-HERE.md) was the post-build signing/de-mock pickup (also superseded — signing and de-mocking are done). Neither reflects the current state; they're kept for lineage, not as instructions to follow today.

## Docs map

| Dir | Contents |
|---|---|
| `00-overview/` | Product brief (democratization framing); `soul.md` → pointer to ratified [`SOUL.md`](../SOUL.md) at repo root |
| `01-architecture/` | The architecture; `cli-contract.md`; `inheritance-and-publish.md`; `error-taxonomy.md`; `windows-parity.md`; versioned [`schemas/`](01-architecture/schemas/) |
| `02-prd/` | The parallel PRD (app workstreams WS-B…WS-I) |
| `03-design/` | Engineering + experience design streams for the native app (interaction spec, visual system, copy deck, agentic-setup, `ui-ux/`) |
| `product-design/` | The PCC design package (Discovery → Design Challenge), Phases 1–5 done; **the app's UX/UI/copy lives in `04-experience-design/`** |
| `04-validation/` | Red-team reports + `test-plan.md` |
| `05-security/` | `credentials-and-boundary.md` + `self-service-store-provisioning.md` + `threat-model.md` + `incident-response.md` |
| `06-deployment/` | Deployment/onboarding guides: signed-app install, GitHub repo-access entitlement, standup/runbook docs for Admin mode |
| `07-contributing/` | Developer guide, `release-and-versioning.md`, `publisher-release-runbook.md` (root also has `CONTRIBUTING.md`/`CODE_OF_CONDUCT.md`/`SECURITY.md`) |
| `08-observability/` | Telemetry spec (two-channel, `machine_id`, fleet dashboard) |
| `09-prototypes/` | Standalone HTML walkthroughs (admin/user experience, ecosystem diagram) used during design review |
| `10-reference/` | Canonical model: [`copilot-solutioning-ecosystem.md`](10-reference/copilot-solutioning-ecosystem.md) + [`cse-alignment-decisions.md`](10-reference/cse-alignment-decisions.md); four-tier topology, ecosystem use cases, `glossary.md` |
| `40-initiatives/` | Live initiative tracking — `02-enac-self-onboarding/` is the active one; its `phases/` has the dated handoffs, `decisions/` has the ADRs (ADR-001…ADR-005 so far), `walkthroughs/` has the truthful-setup service/UX/UI specs |

## What still needs creating (and by what)

- **The live-setup transaction fix** (Phase 7, PRD 15) → the current job; see "How to proceed" above. This is primarily `claude-copilot`/`cc` work (`onboard.py`), with a matching, file-disjoint docs/recovery-view slice in this repo.
- **`06-deployment/` guides** → Admin-mode work (WS-H) + `@agent-doc`, ongoing as Admin mode matures.
- **Real-user validation** → the Admin/IT + multi-writer-author experiences are hypotheses awaiting real operators/writers beyond the owner's own ENAC dogfooding.
