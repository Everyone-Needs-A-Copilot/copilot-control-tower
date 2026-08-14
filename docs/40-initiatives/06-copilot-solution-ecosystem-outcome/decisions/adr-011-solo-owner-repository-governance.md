# ADR-011 — Repository governance belongs to the organization, not the Copilot framework

Status: Accepted and applied Date: 2026-08-14 Decision owner: Pablo Alejo Operational task: TASK-306

ARTIFACT: architecture-decision ARTIFACT: external-state-check ARTIFACT: security-boundary

## Context

GitHub does not allow a pull-request author to approve their own pull request. Requiring one approval therefore creates a deadlock for a sole developer when branch protections also bind the owner. Even when an administrator bypass exists, presenting an independent-review gate as mandatory misstates how Everyone Needs A Copilot currently operates.

Pablo is the owner, developer, and approver for the company's normal repositories. Hermes repositories are explicit exceptions because they involve other developers and carry their own repository-level process.

## Decision

- The default policy for repositories owned by `Everyone-Needs-A-Copilot` is zero required approving reviews, no required code-owner review, and no last-pusher approval requirement.
- Repository names containing `hermes`, matched case-insensitively, are excluded from this default and retain their existing repository-specific settings.
- Required CI/status checks, signed-commit rules, linear history, conversation resolution, deletion protection, and force-push protection are independent technical safeguards and are not removed by this decision.
- A review may still be requested when it adds value, but it is not a platform gate for the solo-owner workflow.
- An explicit owner instruction to merge a named, verified change is sufficient merge authority. The executing agent still verifies the exact repository, pull request, head identity, mergeability, and configured technical checks before merging.
- The Copilot framework, project templates, setup commands, tests, and conformance rules must not create or require a universal human-review policy.
- A company with a different process configures that process through its own GitHub organization or repository settings. A future Control Tower Admin experience may expose those settings as an explicit organization choice, but it must not silently impose the ENAC policy or a one-review default.

## Live application

The organization contained no organization-level ruleset. A complete live audit covered 55 repositories: 51 non-Hermes repositories and four Hermes exclusions.

Eight non-Hermes review gates were changed:

| Repository | Mechanism | Before | After | Technical controls preserved |
| --- | --- | --- | --- | --- |
| `claude-copilot` | Active repository ruleset | One approval, stale-review dismissal, last-push approval | Zero approvals; review-specific switches off | CodeQL, signatures, linear history, conversation resolution, deletion and non-fast-forward protection |
| `cli-copilot-internal` | Legacy branch protection | One approval | Zero approvals | Existing branch protection |
| `claude-copilot-internal` | Legacy branch protection | One approval | Zero approvals | Existing branch protection |
| `codex-copilot-internal` | Legacy branch protection | One approval | Zero approvals | Existing branch protection |
| `claude-copilot-accounting` | Legacy branch protection | One approval | Zero approvals | Existing branch protection |
| `codex-copilot-accounting` | Legacy branch protection | One approval | Zero approvals | Existing branch protection |
| `knowledge-copilot-accounting` | Legacy branch protection | One approval, code-owner review, last-push approval | Zero approvals; review-specific switches off | `accounting-sensitive-content`, admin enforcement, conversation resolution |
| `copilot-control-tower` | Legacy branch protection | One approval, last-push approval | Zero approvals; review-specific switches off | Admin enforcement and conversation resolution |

Post-change verification found zero legacy or ruleset approval gates among all 51 non-Hermes repositories. The four Hermes repositories were read for verification and were not mutated.

Framework PR #66, organization-content PR #1, and accounting-content PR #1 now report `mergeStateStatus: CLEAN`. Their configured checks remain successful. They were not merged by this governance operation because the owner did not name those pull requests for merge in the instruction.

## Code boundary

The current Control Tower Admin bootstrap contains a legacy path that creates a one-review branch-protection rule. Because ADR-010 removes the app from Initiative 06, that app path is quarantined in PRD-24 and must not be run as the ecosystem setup path. Before the next Control Tower release, the app track must replace that default with an explicit organization-controlled setting. Pulling app implementation and release work into Initiative 06 would contradict the owner's scope decision.

No current Claude, Codex, `cc`, `copilot`, Task Copilot, or project-install component may depend on that app behavior.

## Verification

- `non_hermes_repositories=51`
- `hermes_exclusions=4`
- `legacy_review_gates_remaining=0`
- `ruleset_review_gates_remaining=0`
- Framework PR #66: clean, all required checks successful
- Organization-content PR #1: clean, no required checks
- Accounting-content PR #1: clean, `accounting-sensitive-content` successful

VERDICT: APPLIED — SOLO-OWNER MERGES ARE NOT BLOCKED BY INDEPENDENT-APPROVAL POLICY; HERMES REMAINS EXCLUDED.
