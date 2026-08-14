# GitHub solo-owner governance audit

Date: 2026-08-14 Organization: `Everyone-Needs-A-Copilot` Task: TASK-306 Decision: [ADR-011](../decisions/adr-011-solo-owner-repository-governance.md)

## Scope resolution

The live GitHub organization contained 55 repositories. The operation included 51 repositories whose names do not contain `hermes` and excluded `Hermes-3`, `Hermes-2`, `hermes-1`, and `hermes`.

No organization-level ruleset existed. Repository rulesets and legacy default-branch protection were inspected separately because GitHub can enforce review requirements through either mechanism.

## Before

Seven repositories had legacy default-branch protection requiring one approval: `cli-copilot-internal`, `claude-copilot-internal`, `codex-copilot-internal`, `claude-copilot-accounting`, `codex-copilot-accounting`, `knowledge-copilot-accounting`, and `copilot-control-tower`.

`claude-copilot` had an active `main-protection` ruleset requiring one approval and last-push approval. That ruleset also carried technical rules that had to be preserved.

## Mutation

Only pull-request review parameters changed. Required approving-review counts became zero; stale-review dismissal, code-owner review, and last-push approval became false. No ruleset, branch, status check, signature rule, history rule, conversation-resolution rule, deletion rule, or force-push rule was deleted.

## After

| Measure                                   | Result |
| ----------------------------------------- | -----: |
| Non-Hermes repositories audited           |     51 |
| Hermes repositories excluded              |      4 |
| Non-Hermes legacy review gates remaining  |      0 |
| Non-Hermes ruleset review gates remaining |      0 |
| Hermes repositories mutated               |      0 |

Preserved checks include `CodeQL` on `claude-copilot` and `accounting-sensitive-content` on `knowledge-copilot-accounting`.

## Pull-request verification

| Pull request | Merge state after change | Review gate | Technical checks |
| --- | --- | --- | --- |
| `claude-copilot#66` | `CLEAN` | None | All configured checks successful; billed live evaluation intentionally skipped |
| `knowledge-copilot-internal#1` | `CLEAN` | None | No required checks configured |
| `knowledge-copilot-accounting#1` | `CLEAN` | None | `accounting-sensitive-content` successful |

No pull request was merged during TASK-306.

## Rollback boundary

Rollback is possible per repository by restoring its prior review parameters. ADR-011 makes that inappropriate for the ENAC solo-owner default unless Pablo explicitly changes the decision or a repository is reclassified as a multi-developer exception. Hermes settings remain the model for repository-specific exceptions.

ARTIFACT: external-state-check ARTIFACT: diff-check VERDICT: APPROVED
