# Handoff — Truthful Setup and Project Integration Aftercare

Date: 2026-07-30
Primary repository: `copilot-control-tower`
Branch: `app-build`
Shared skill repository: `codex-copilot`
Shared skill commit: `85acbbe949fe5c7235498d6ceab8c78c4ca1589c`
Task lineage: `tc` 182 → 183 → 184 → 185

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

## Required CLI Contract

Implementation should begin with the CLI contract, not with app-side heuristics.
Workspace inspection needs to return, per project and per Copilot component:

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

## Recommended Next Work

1. Inspect the current CLI workspace/onboarding schemas and tests in the
   `cli-copilot` repository.
2. Design the richer, versioned JSON contract and fixtures before modifying
   Control Tower.
3. Implement fail-closed per-component classification in the CLI.
4. Add safe-finish, generated-plan, owner-handoff, and verification verbs or
   declared actions.
5. Update Control Tower to render those facts and launch/copy the external prompt.
6. Exercise the real representative projects above as acceptance fixtures without
   mutating their working trees during classification.
7. Rebuild the release only after CLI and app QA pass.

Do not implement the candidate `31/11/11` grouping as hard-coded app logic.

## Completed Design and QA

- Tasks 183 and 184 are complete with service, UX, UI, and QA work products.
- Task 185 orders the walkthroughs, records the future naming convention, and
  produces this handoff.
- The focused walkthroughs passed Chromium navigation, theme, responsive,
  no-external-request, no-console-error, Aviator-branding, and visual checks.
- The shared UxD and UIDS skills now require
  `NN-<feature>-<stage>-walkthrough.html`, contiguous narrative ordering, adjacent
  UXD/UIDS pairs, a directory index, and reference updates when renumbering.

## Copy Into the New Conversation

```text
$codex-copilot:protocol

Continue the truthful setup and project integration work from:
docs/HANDOFF-PROJECT-INTEGRATION-AFTERCARE.md

Read the handoff, SOUL.md, the architecture guiding principles, and numbered
walkthroughs 05 through 08 before changing code. Begin by inspecting and designing
the CLI workspace contract that will authoritatively classify complete, safely
finishable, and guided-integration projects. Do not put project classification or
semantic inspection logic in Control Tower.
```
