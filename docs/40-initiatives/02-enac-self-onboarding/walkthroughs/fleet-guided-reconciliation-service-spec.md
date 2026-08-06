# Fleet-guided reconciliation — service specification

## Job to be done

When many projects have different existing Claude and Codex setups, the person
wants one capable assistant conversation to finish the whole approved Sites
folder, so they do not have to understand repositories, recipes, or verification
commands.

## Service concept

Control Tower prepares one trustworthy work order; Codex or Claude Code performs
the project-specific reasoning in one root-level conversation; Python witnesses
scope, progress, and completion. The user has one handoff and one place to ask
questions.

## Journey and responsibilities

| Stage | Person sees or does | Control Tower | Python helper | Coding assistant |
|---|---|---|---|---|
| Select | Reviews one included batch | Renders authored selection | Excludes unsafe and ecosystem repositories | Not running |
| Start | Chooses Codex or Claude Code | Requests package and opens Terminal | Writes exact runbook and project inventory | Reads the package |
| Work | Watches Terminal or continues the conversation | Shows verified/remaining counts | Freshly checks reported project milestones | Inspects and fixes projects sequentially |
| Decide | Answers only genuine project-owner questions | Keeps one session visible | Preserves the unresolved reason | Asks in the same conversation |
| Finish | Returns to one result | Rechecks and advances or offers continuation | Verifies the complete selection | Cannot self-approve |

## Failure paths

- If the chosen assistant is unavailable, the package remains useful and the
  other assistant or copied instructions can use it.
- If Terminal permission is denied, no session is claimed to have started.
- If the assistant stops, Python verifies actual filesystem evidence and keeps
  remaining work explicit.
- If evidence changes after preparation, current verification wins.
- Dirty or unsafe projects are never added to the assistant's write scope.

## Alternatives rejected

- One session per project: unacceptable cognitive and operational load.
- Content-free recipe selection: safe but unable to resolve real customization.
- An in-app chat surface: makes Control Tower a second pilot and expands audit
  surface without improving the actual coding environment.
- Trusting the assistant's completion statement: violates evidence honesty.

## Service constraints

- The handoff file may contain project paths and non-secret inspection facts.
- It must not contain project-authored file contents, credentials, or tokens.
- The person explicitly launches the external assistant, which is the competent
  actor for project-specific edits.
- Python alone authors ready, remaining, blocked, and excluded states.

