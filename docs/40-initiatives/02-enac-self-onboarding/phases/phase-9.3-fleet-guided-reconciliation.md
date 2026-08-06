# Phase 9.3 — Fleet-guided project reconciliation

Task Copilot: PRD-19 · TASK-252

## Outcome

One Control Tower action creates one run-specific instruction package beneath
the approved Sites root and opens one visible Codex or Claude Code conversation
there. That one conversation works through every selected product project. The
person never opens projects individually, composes commands, or carries state
between assistant sessions.

Python remains the source of truth for scope and verification. The assistant
may inspect the selected projects and make the project-specific changes that a
fixed recipe cannot express, but its own success message never completes setup.
Each project becomes complete only after the helper freshly verifies the exact
Claude and Codex components selected for it.

## Product boundary

- Control Tower creates and launches the handoff; it does not become a chat UI.
- The instruction package contains paths, detected facts, missing requirements,
  preservation rules, and verification commands, never project file contents or
  secrets.
- Ecosystem repositories remain managed separately and never enter this run.
- Dirty, unsafe, owner-dependent, or unreadable projects remain outside write
  authority with a Python-authored reason.
- The primary route is one fleet session. Per-project Terminal sessions are not
  part of first-run setup.
- An interrupted run can be opened again from the same instruction package.

## Run package

The helper writes a private run directory below the first approved root:

```text
.copilot-control-tower/reconciliation/<run-id>/
  INSTRUCTIONS.md
  PROJECTS.json
```

`INSTRUCTIONS.md` is the assistant-facing runbook. `PROJECTS.json` is the exact
machine-readable selection and evidence. Authoritative progress remains in the
helper's private state area and is read through versioned JSON commands; the
assistant cannot declare itself verified by editing a file.

## Required experience

1. Review one selected project batch.
2. Choose **Finish with Codex** or **Finish with Claude Code**.
3. Control Tower writes the package and opens Terminal at the approved root.
4. The assistant reads the runbook and works through the complete list.
5. Control Tower shows Python-authored verified and remaining counts, with one
   **Bring Terminal forward** action.
6. The assistant asks owner questions in that same conversation.
7. When the session ends, Python freshly verifies the whole selection.
8. Ready continues setup. Remaining work can reopen the same package in one new
   fleet session without recreating per-project handoffs.

## Failure and recovery

- Missing assistant: keep the package and offer the other installed assistant
  plus **Copy instructions**.
- Terminal automation denied: name the System Settings route; claim no launch.
- Assistant exits early: finalize with fresh verification and show what remains.
- Stale or changed project evidence: verification returns the new reason; never
  silently reuse the earlier assessment as proof.
- Interrupted Control Tower: a later status call can reopen the run package.
- Final machine update available: the wizard performs the already-supported
  update action before running Doctor again; it does not promise a quiet update
  and then pause.

## Verification

- Python contract/schema tests for prepare, status, per-project check, finalize,
  containment, excluded repositories, dirty projects, and malformed run IDs.
- Native DTO and launcher tests for both assistants, quoting, launch failures,
  progress transitions, resumption, and final verification.
- Accessibility and design-fidelity checks against walkthroughs 23 and 24.
- Build and release gates run against the signed, notarized, stapled artifact.

