# Phase 6 — Truthful setup and project integration aftercare handoff

> Initiative: [`02-enac-self-onboarding`](../README.md)
>
> Previous handoff:
> [`phase-6-v0.1.3-user-install-handoff.md`](phase-6-v0.1.3-user-install-handoff.md)
>
> **This is the release-candidate record as of 2026-07-30.** The previous
> handoff remains implementation and release history. The checked-in package
> now embeds the separately signed and Apple-notarized cc 1.7.12 universal
> helper and passes the walkthrough acceptance gate.

Date: 2026-07-30
Primary repository: `copilot-control-tower`
Branch: `app-build`
CLI repository: `claude-copilot`
CLI branch: `feat/adopt-and-project-setup`
Task lineage: `tc` 182 → 183 → 184 → 185 → 187 → 188–193
Status: source implementation and packaged-helper QA complete; signed Control
Tower 0.1.9 packaging and installed-artifact verification remain

## Start Here

Read the numbered walkthrough index:

`docs/40-initiatives/02-enac-self-onboarding/walkthroughs/README.md`

The walkthroughs are intentionally ordered `01` through `12`. For the current
setup and project-integration problem, concentrate on:

1. `05-truthful-setup-recovery-uxd-walkthrough.html`
2. `06-truthful-setup-recovery-uids-walkthrough.html`
3. `07-project-integration-aftercare-uxd-walkthrough.html`
4. `08-project-integration-aftercare-uids-walkthrough.html`

The UIDS walkthroughs are the high-fidelity experience. The UXD walkthroughs
explain the interaction decisions behind them.

## What Has Been Established

The installed Control Tower 0.1.7 CLI reported 53 projects:

- 31 had both Claude and Codex recognized.
- 5 were called Ready while only one recommended Copilot was recognized.
- 17 materially different projects were collapsed into one generic
  “existing setup needs review” blocker.

The `31 Ready / 11 likely safe finish / 11 guided integration` split is a
research-backed candidate grouping. It is not an executable verdict. A richer
CLI contract must compute the authoritative classification.

Representative project shapes were verified against the local projects:

- `pipeline-copilot`: customized and already integrated.
- `admin-server`: compatible Claude setup with critical project safety rules.
- `codex-copilot`: recognizable Codex setup without current proof.
- `h3` and `convoco-policy-build`: only one recommended Copilot is integrated.
- `crm-automation-copilot`: valuable project guidance without shared framework
  integration.
- `preflight-copilot`: deeply specialized older ecosystem with 24 agents, eight
  skills, and eight commands.
- `research-copilot` and `transformation`: mixed Claude and Codex customization.

## Product Decisions

1. A project is self-contained. Control Tower does not sync or own project
   contents.
2. Control Tower renders CLI facts; it does not classify project contents itself.
3. Project customization is a positive capability, not a failure state.
4. Exact compatible layouts may receive a bounded safe-finish action.
5. Semantic reconciliation receives a CLI-generated plan and guarded prompt.
6. An authorized author may open that prompt in Codex or Claude Code.
7. A non-owner receives a prepared, shareable handoff. “Owner will review” by
   itself is not an outcome.
8. The CLI independently verifies the project after external work. An assistant’s
   self-report never marks the project Ready.
9. Existing project agents, skills, commands, rules, and integrations must be
   preserved unless a competent owner explicitly decides otherwise.

These decisions follow `SOUL.md`: parse-never-compute, route by actor competence,
keep Bob out of technical decisions, and preserve projects as self-contained
products.

## Implemented CLI Contract

Workspace inspection now returns, per project and per Copilot component:

- expected contract and version;
- recognized setup and evidence;
- missing requirements;
- classification: Ready, can finish safely, guided integration, owner decision,
  or could not verify;
- exact safe action, when one exists;
- responsible actor;
- project capabilities and files that must be preserved;
- prohibited actions;
- generated integration-plan and prompt payload;
- verification command and stop conditions.

The complete service contract is in:

- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/project-integration-aftercare-service-spec.md`
- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/project-integration-aftercare-analysis.md`
- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/truthful-setup-recovery-service-spec.md`

The frozen consumer contract is:

- [`docs/01-architecture/schemas/workspaces.schema.json`](../../../01-architecture/schemas/workspaces.schema.json)

Its SHA-256 is
`470a663277f77b0d60359103e1f206852f05c1b7392f3b5c31b1810b90c75c33`,
identical to the CLI repository's frozen fixture.

## Completed Implementation

1. The CLI owns a closed, fail-closed five-state classification for each
   project and each Claude/Codex component.
2. Exact safe-finish actions are opaque, bounded, and independently verified.
3. Guided plans carry preservation facts, prohibited actions, guarded prompts,
   owner handoffs, persistent holds, and authoritative verification commands.
4. Control Tower decodes the frozen contract and renders its facts directly. It
   does not reproduce classification or semantic inspection logic.
5. Safe-finish, guided-integration, owner-decision, and could-not-verify routes
   have explicit controls. External assistant actions open the selected project
   folder and copy the CLI-generated prompt.
6. Only CLI verification can transition a project to Ready.
7. Representative live projects were inspected read-only; classification did
   not mutate their working trees.

## Completed Design and QA

- Tasks 183 and 184 are complete with service, UX, UI, and QA work products.
- Task 185 orders the walkthroughs, records the future naming convention, and
  produces this handoff.
- Tasks 187 through 193 cover the architecture, frozen schema, classification,
  safe finish, guided integration, representative-project QA, and Control Tower
  consumer.
- CLI QA passed 61 focused tests and the environment-excluded full suite with
  1,186 passing tests. Read-only representative-project checks preserved every
  pre-inspection fingerprint.
- Control Tower QA passed the frozen-contract decoder, user-app bundle,
  compatibility release gate, CLI seam smoke suite, and the 126-scenario matrix.
- Live safe-finish and guided-integration popovers passed production-width visual
  checks, including the full guided-plan drill-in.
- The focused walkthroughs passed Chromium navigation, theme, responsive,
  no-external-request, no-console-error, Aviator-branding, and visual checks.
- The shared UxD and UIDS skills now require
  `NN-<feature>-<stage>-walkthrough.html`, contiguous narrative ordering, adjacent
  UXD/UIDS pairs, a directory index, and reference updates when renumbering.

## Walkthrough 05–08 Acceptance Gate

The executable matrix is:

- [`09-walkthrough-05-08-acceptance-matrix.md`](../walkthroughs/09-walkthrough-05-08-acceptance-matrix.md)
- `scripts/tests/test_walkthrough_05_08_acceptance.sh`

Measured results:

- checked-in release package with the signed and notarized universal cc 1.7.12:
  **33/33, 100%, zero critical failures**;
- clean-home lifecycle: `safe-finish → finish → Ready → verify`, plus
  independent guided-integration and owner-decision routes;
- the release helper is cc 1.7.12 from signed foundation snapshot `v5.13.14`,
  accepted by Apple notarization, universal for arm64 and x86_64, and pinned by
  SHA-256 in `packaging/cc/PINNED_SHA256`.

## Remaining Boundary

The helper release boundary is closed. The remaining release-owner steps are:

1. commit and push this exact Control Tower source;
2. tag the source as 0.1.9;
3. build, Developer-ID sign, Apple-notarize, and staple the app and DMG from
   that pushed ref;
4. reinstall from the produced DMG and rerun the clean-home lifecycle against
   the embedded helper.

Only after those installed-artifact checks pass may this phase be called
release-ready.
