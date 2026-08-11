# Active Setup Preflight — Architecture

Decision: [ADR-010](../decisions/ADR-010-active-setup-preflight.md)

## Boundary

`cc reconcile prepare --json` is the only new mutation boundary. The native app
adds one typed client method and one preparation report DTO. The existing
`ReconciliationAssessReport` is nested verbatim as `assessment` and becomes the
same input Step 7 already renders after preparation.

## Response shape

- `schema_version`, `phase: prepare`, `result`, `run_id`, `generated_at`
- `completed_actions[]`: stable action kind, product/shared scope, display name,
  outcome, plain summary, and optional before/after/commit object IDs
- `project_checkpoints`: considered, committed, held
- `ecosystem_refresh`: considered, updated, current, held
- `authority`: read-only, author-capable, unknown counts; no raw permission in
  user-facing copy
- `holds[]`: code, scope, display name, responsible actor, detail, next action
- `assessment`: a complete schema-2.0 assess report generated after mutations
- `summary`: CLI-authored headline/detail and `next_actions[]`

Exit 0 is ready; exit 1 is partial/blocked business output; exit 2 is a
structured error. A partial result still requires `assessment` when a safe
fresh read completed.

## Project checkpoint transaction

The initial census provides repository scope and approved-root containment.
Each eligible product project is independently re-identified and locked through
`project_lock`. The checkpoint preflight rejects Git operation state, detached
HEAD, conflicts, unreadable status/identity, unsafe roots, and sensitive paths.
It snapshots the index, stages all non-ignored work, invokes an ordinary commit,
restores the index on a failed commit, and verifies the new HEAD plus fresh
status. Completed commits are durable preservation actions and are not rolled
back merely because a later project or ecosystem update holds.

## Shared-source refresh and authority

The existing onboarding topology classifier and `_apply_visible_topology`
remain the sole fast-forward implementation. Only its `fast-forwardable` action
may mutate, and the current `HEAD == fetched target` postcondition remains
mandatory. GitHub's repository response is extended with calculated permission
evidence. Permission failure degrades to read-only; it does not block pulls.

## Swift integration

`loadProjectWorkspaces()` replaces the parallel legacy-workspaces/assess start
with prepare plus the legacy read used by aftercare. The presentation state is
`preparing` until Python returns. Swift stores the exact prepare report, assigns
its nested assessment, and derives no receipt counts. Retry invokes prepare
again; idempotency produces a zero-work result after successful commits and
fast-forwards.

## Failure model

- Project holds do not prevent independent safe checkpoints or shared pulls.
- Shared update holds do not undo completed project commits.
- If fresh assessment fails, completed actions remain in the report and the app
  enters the existing support-report holding surface.
- Lock contention is a specific retryable hold, never a generic failure.
- Offline GitHub evidence prevents refresh/authority elevation but does not
  fabricate stale success.

