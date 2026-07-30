# Project Integration Aftercare — UX Specification

Status: interaction walkthrough
Task: `tc` 184
Companion: `07-project-integration-aftercare-uxd-walkthrough.html`

## Primary task

Understand why a customized project is or is not integrated, choose the
appropriate safe or guided completion path, and return to a verified Ready state.

## Inventory model

The project register uses three primary groups:

1. **Ready**, including “Project-specific setup” as a positive detail.
2. **Can finish safely**, containing only CLI-declared reversible actions.
3. **Guided integration**, requiring project understanding in Claude Code or
   Codex.

“Owner review” is not a primary state. Ownership changes the available route
inside Guided integration.

## Walkthrough sequence

### 01 — Evidence from this Mac

Show the observed 53-project inventory:

- 31 currently recognized with both components;
- five currently mislabeled Ready with only one component;
- 17 collapsed into the existing generic blocker.

Then show the candidate target grouping of 31 Ready, 11 safe finish, and 11
guided integration. Label the last two counts as dependent on the richer CLI
preflight.

### 02 — Use-case map

Show the six combined project patterns:

- customized and integrated;
- compatible setup missing proof;
- one copilot ready, other customized;
- project guidance only;
- deeply specialized legacy;
- mixed Claude and Codex customization.

### 03 — Customized and integrated

Use `pipeline-copilot`.

Show both ecosystem entry points and project-local pipeline, writing, and legal
agents. Primary result: Ready. No remediation control.

### 04 — Compatible setup can finish safely

Use `admin-server` and `codex-copilot` as variants:

- current Claude core plus critical local safety rules;
- recognizable Codex framework missing only current proof.

Show bounded “Will add / Will preserve / Will not change” review.

### 05 — Safe finish result

The project becomes Ready only after both components pass verification.

### 06 — One component ready, other customized

Combine:

- `h3`: Claude ready; project-specific `AGENTS.md` blocks a mechanical Codex
  template;
- `convoco-policy-build`: Codex ready; project-specific Claude guidance requires
  integration.

Primary action: Begin guided integration for the missing component.

### 07 — Project guidance only

Use `crm-automation-copilot`.

Explain that its current `CLAUDE.md` is valuable project knowledge, not Copilot
integration proof. The plan preserves it while adding shared entry points.

### 08 — Deep specialization

Use `preflight-copilot`.

Show 24 agents, eight skills, and eight commands as preserved project assets.
This requires semantic reconciliation; no one-click overwrite exists.

### 09 — Mixed customization

Use `research-copilot` and `transformation` as variants.

Show current Claude/Codex documents, incomplete links, and project-specific rules.
The plan covers both components and can stop for an owner decision.

### 10 — Guided plan

Show:

- detected setup;
- required additions;
- preservation set;
- prohibited changes;
- verification target.

### 11 — Choose the route

Authorized author:

- Open in Codex;
- Open in Claude Code;
- Copy integration prompt.

Non-owner:

- Prepare project-owner handoff.

### 12 — Generated prompt preview

Show a readable prompt summary with technical payload behind “Show full prompt.”
The prompt explicitly preserves project-local behavior and names the verification
command.

### 13 — Owner handoff variation

Show what Bob sees:

> This project needs someone who can change its project setup. Nothing has been
> changed.

The handoff package contains the reason, generated prompt, and return-to-verify
instruction.

### 14 — Return and verify

The user returns from Claude/Codex. Control Tower re-inspects; it does not trust
the external agent’s success statement.

### 15 — Verification outcomes

Cover:

- verified Ready;
- one remaining item;
- owner decision required;
- project changed since inspection;
- could not verify.

### 16 — Updated project register

Ready rows retain “Project-specific setup” details. Guided items remain visibly
incomplete and link back to their plan.

## Interaction rules

- “Ready” requires every recommended component.
- Customization never causes warning styling by itself.
- Safe actions are component-scoped and independently selectable.
- Opening Claude or Codex uses the CLI-generated payload.
- Copy is always available if external launch fails.
- Handoff does not mark a project ready.
- A stale plan cannot be resumed; it must be regenerated.
- The user can defer guided integration without losing the plan.

## Accessibility

- Every use-case status has text and a distinct glyph.
- Counts are announced with their group definitions.
- Route choices use buttons with explicit destinations.
- Prompt preview is selectable and keyboard reachable.
- Returning from an external app moves focus to “Verify project.”
- Verification changes use a polite live region.

## Unresolved technical dependencies

- Per-component project contract and complete-recommended-component rule.
- CLI-declared customization summary and safe-action classification.
- CLI-generated structured prompt and owner-handoff payload.
- Reliable external app launch/deep-link contract for Claude Code and Codex.
- Project-author/owner routing source.
