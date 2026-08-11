# Default Project Batch — Service Specification

Status: implementation-approved from owner direction

Task: `tc` 241

## Service promise

Control Tower offers one safe batch: every project the Python helper can set up
or correct without an unresolved decision is included by default. The person
reviews one exact plan and approves it once. Projects that are already ready stay
quiet. Projects that are unsafe or unclear stay unchanged and are named only as
exceptions.

## Actor and job

The primary actor is a person with a Mac containing a mix of ready, new, old,
customized, dirty, and uncertain Git projects. Their job is not to understand
the reconciliation taxonomy. Their job is to decide whether Control Tower should
handle all currently safe work or a smaller project subset.

## Service sequence

1. Python inspects the Mac and every project under approved roots without writing.
2. Python tests the universal Claude-plus-Codex selection against each project.
3. Python returns one exact default selection and four non-overlapping counts:
   new setup, correction, ready, and needs review.
4. Control Tower opens with every default project selected.
5. The person either reviews the whole batch or chooses projects individually.
6. Python creates an exact, expiring plan for the submitted subset.
7. The person approves that exact plan.
8. Python re-inspects, applies bounded operations, rolls back failures, and emits
   a durable receipt.
9. A separate helper call verifies the same selection.

## Service boundaries

- “All” means all Python-authored safe actionable projects, never every folder
  regardless of safety.
- Every selected project always requests both `claude` and `codex`.
- Ready projects are acknowledged by count and omitted from selection.
- Held, excluded, ambiguous, unverifiable, owner-decision, source-unavailable,
  and non-deterministic-recipe projects are not selected.
- The app may remove Python-authored selections in response to checkbox input.
  It may not add an ineligible project, choose a component, choose among recipes,
  or derive a category.
- Exact-plan review, stale-plan rejection, project boundaries, rollback, and
  independent verification remain mandatory.

## Failure and recovery

- If no safe work exists, the screen says so and offers a fresh check; it does
  not show an empty checklist.
- If the Mac needs attention, one Python-authored prerequisite summary appears.
  Repeated low-level blocker actions are not rendered.
- If project evidence changes before planning or apply, the old selection or
  plan is refused and a fresh assessment is offered.
- If only some selected projects succeed, the receipt separates verified,
  unchanged, restored, and still-needs-review outcomes.

## Success measures

- The first meaningful control answers “handle all safe projects?” and starts on.
- No component-level choice appears anywhere in the selection step.
- A person can reach exact-plan review without opening a project row.
- The visible counts reconcile to the total exactly once.
- No ready project occupies a primary row.
- No unsafe project can enter the default request.
