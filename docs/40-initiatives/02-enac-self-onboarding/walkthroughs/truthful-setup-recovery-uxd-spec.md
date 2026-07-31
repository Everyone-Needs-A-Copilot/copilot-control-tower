# Truthful Setup and Recovery — UX Specification

Status: interaction walkthrough
Task: `tc` 183
Companion: `05-truthful-setup-recovery-uxd-walkthrough.html`

## Experience goal

The flow turns an opaque setup audit into a sequence of plain-language answers.
At every point, the person knows:

- what Control Tower checked;
- what is ready;
- what is missing;
- what Control Tower will change;
- what remains unchanged;
- whether the next action belongs to them.

## Primary user

Bob works in accounting. He can choose whether to connect an account or include
a project, but he should not need to understand Git, repositories, dotfiles,
manifests, symlinks, or legacy layouts.

Project owners and administrators are secondary actors. Their technical detail
belongs behind “Review details,” not in Bob’s default path.

## Information architecture

The setup journey has four stable stages:

1. Your Copilot setup
2. Your projects
3. Set up
4. Final check

Connections remain a separate register and show only organization-provided
options. They do not affect the truthfulness model in this walkthrough.

## Screen sequence

### 01 — Checking all four copilots

- Name Knowledge, CLI, Claude, and Codex while checking.
- Use determinate row completion when results return.
- Do not show a success headline before the roster is complete.

### 02 — One component-by-layer inventory

- Show Knowledge, CLI, Claude, and Codex as expandable component rows.
- Inside each component, show Foundation, Organization, entitled Department,
  and Personal.
- Show repository existence, visible checkout, connection, sync, and
  verification as separate states.
- Never expose rank 10, 20, 30, or 40.
- Primary action: “Review setup.”

### 03 — Visible repository folder

- Show the inferred or chosen repository folder above the inventory.
- Explain that new components will be created or downloaded beside existing
  components.
- Offer “Choose another folder…” without hiding the current path.
- If no unambiguous location exists, require a folder choice before review.

### 04 — Setup review and progress

- Summarize the exact transaction: reuse, create private, download,
  initialize empty Department layers, connect, synchronize, and verify.
- Show a real denominator made from named operations.
- Completed and active rows use text, shape, and restrained color.
- The window may close while work continues from the aviators icon.

### 05 — This Mac is verified

- Re-check all four components.
- State that all four are ready only after verification.
- Give one next action: review projects.

### 05 — Project inventory

- Use the diagnosed total of 53.
- Live inspection found that the current 36 Ready count includes five projects
  with only one recommended copilot recognized.
- Candidate classification after richer per-component preflight:
  - 31 currently have both components recognized;
  - 11 can likely finish safely;
  - 11 need guided integration.
- These are design-research counts. The final grouping remains contract-driven.
- The focused variations live in
  `07-project-integration-aftercare-uxd-walkthrough.html`.

### 06 — Safe addition detail

- Show one representative project with existing Claude setup and missing Codex.
- Tell the person exactly what will be added and preserved.
- Primary action names the safe change.

### 07 — Recognized setup and guided integration

- An exact-match legacy project receives a reviewed adoption option.
- A custom project receives a CLI-generated guided plan.
- An authorized author can open Claude Code or Codex with that plan.
- A non-owner receives a prepared project-owner handoff.
- Never combine these states into “Needs review.”

### 08 — Setup result

- Separate safe finishes, adoptions, guided plans, and verified projects.
- State that nothing changed when a handoff is prepared.
- Never imply that every discovered project must be modified.

### 09 — Final check

- Verify all four copilots and summarize project outcomes.
- Explain what happens next.
- Connect onboarding to the aviators menu-bar icon.

### 10 — Steady-state popover

- Show a readable label for each copilot: Ready, Missing, or Couldn’t verify.
- Layer indicators have headings or accessible labels.
- No unexplained empty circles.

### 11 — Honest recovery states

- Verification unavailable is distinct from missing.
- Older `cc` versions produce “Layer details unavailable.”
- A retry is shown only when it can change the outcome.

## Interaction rules

- One primary action per screen.
- Selection is required only for optional projects.
- Expanding a group never changes state.
- Adoption requires an explicit review and exact-match proof.
- “Continue” is not blocked by owner-only project issues.
- Keyboard focus follows visual order.
- Status never relies on color alone.
- Reduced-motion users receive no animated progress treatment.

## Content rules

- Use “Personal” consistently for the layer and “private repository” for its
  storage/privacy promise.
- Show repository names and visible paths wherever placement or ownership is
  part of the decision.
- Prefer “existing setup” to “collision.”
- Prefer “project owner” to “developer” when describing responsibility.
- Every failure includes cause, preservation statement, and next actor.
- Do not hide the selected repository root or layer checkout paths.

## Responsive behavior

The native setup window targets 920 × 700. At narrower widths:

- the stage rail collapses;
- summaries remain above controls;
- rows stack status and action below the name;
- no horizontal scrolling is required.

## Accessibility

- Minimum target size: 32 × 32 points for secondary controls, 36 points for the
  primary action.
- Use semantic headings and ordered screen navigation.
- Provide text equivalents for all shapes and badges.
- Preserve 4.5:1 contrast for body copy.
- Honor `prefers-color-scheme` and `prefers-reduced-motion`.
