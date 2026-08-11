# Default Project Batch — UX Specification

Status: implementation-approved from owner direction

Task: `tc` 241

Companion: `19-default-project-batch-uxd-walkthrough.html`

## Primary experience

The selection screen leads with the outcome, not the census:

> **Set up and fix your projects**
>
> 47 projects can be handled safely. They are all selected.

Two visible counts explain that batch:

- **New setup** — projects receiving Claude Copilot and Codex Copilot from the
  ground up.
- **Needs correction** — projects whose existing Copilot setup can be brought
  to the current verified shape.

Ready projects receive one quiet acknowledgement. Projects needing human review
receive one protective note stating that they are not selected and will not be
changed.

## Selection behavior

- The checkbox **Set up and fix all N projects** is on by default.
- The primary action is **Review changes for N projects**.
- **Choose projects individually** changes the surface to a project-only list.
- Individual mode lists only projects from Python's default selection.
- Every row is selected on entry. **Select all** and **Select none** are present.
- A project row has one checkbox, project name, and its Python-authored category
  label. It has no Claude/Codex controls.
- Returning to all-project mode restores the complete Python-authored default
  selection.
- The review action is disabled when no projects are selected.

## Information hierarchy

1. Number of safe projects selected.
2. New-setup and correction counts.
3. One all-project checkbox.
4. Primary review action.
5. Quiet ready acknowledgement.
6. Quiet needs-review exception count.
7. Individual selection, only after an explicit request.
8. Technical census and project dossiers, only in later review or receipts.

## Machine status language

“Machine readiness” is removed from the customer-facing heading.

- Ready: **This Mac has what it needs.**
- Action required: **Before projects can be updated** followed by one exact
  Python-authored next action.
- Could not verify: **Control Tower could not safely confirm this Mac yet.**

Helper paths, framework versions, and repeated blocker messages stay out of the
primary surface. They remain available in diagnostics and receipts.

## Empty and exception states

- All ready: “All N projects are already set up. Nothing needs to change.”
- No projects: identify the checked folder and offer another folder or continue.
- Review only: “N projects need someone to review them. Nothing is selected.”
- Machine blocked: retain the project counts, disable plan review, and show the
  one prerequisite action.
- Fresh evidence mismatch: clear the stale review and return to a fresh batch.

## Accessibility

- The all-project checkbox announces the selected and total count.
- Summary cards have count, category, and meaning in their accessible label.
- Entering individual mode moves focus to its heading; leaving it returns focus
  to **Choose projects individually**.
- Selection changes are announced politely as “N projects selected.”
- Category and selection are never conveyed by color alone.
- Checkbox rows meet a 44-point target and the entire label is clickable.
- The primary action names the exact selected count.

## Contract dependency

Python must return the exact default project selections, both component names,
any deterministic recipe bindings, four reconciled batch counts, and one machine
status message. Swift may present and subtract from this set only.
