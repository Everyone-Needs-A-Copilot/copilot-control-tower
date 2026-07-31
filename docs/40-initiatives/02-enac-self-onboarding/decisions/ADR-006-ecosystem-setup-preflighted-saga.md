# ADR-006 — Ecosystem setup is a preflighted saga

Status: Accepted (owner-ratified 2026-07-31)
Date: 2026-07-31
Task: `tc` 204–208 (documented under `tc` 213, gap G-9)

## Context

The Control Tower 0.2.4 live setup blocker (`phases/phase-6-v0.2.4-live-setup-blocker-handoff.md`, `tc` 203) showed that `cc onboard`'s prior planner classified any clean checkout whose HEAD differed from the target remote SHA as `behind`/`repair` and promised "a clean fast-forward is available" without ever proving ancestry — misclassifying both an ahead-only checkout and a divergent-but-identical-tree checkout as safely repairable. The same transaction created two Personal GitHub repositories before the Git-ancestry precondition it already knew about could fail, then reported "nothing changed" once it did. Tasks 204–208 (commits `d0f2869`, `5208681`, `24f3c06`, `4e45cd7`, `8aaa424` on `claude-copilot` branch `feat/adopt-and-project-setup`) close that gap end to end.

## Decision

1. Repository history is classified by one pure function, `_classify_repository_history`, over observed git facts (fetch, `git merge-base --is-ancestor`, tree-hash comparison) into exactly eight closed states: `exact`, `fast-forwardable`, `dirty`, `ahead-only`, `divergent-identical-tree`, `divergent-different-content`, `wrong-origin`, `unreadable`. Only `fast-forwardable`, proven by `git merge-base --is-ancestor`, may claim a clean fast-forward is available; every other state routes to the owner (`action=review`) and is never auto-repaired (task 204).
2. Every deterministic preflight check — including that classifier's result — runs before any irreversible GitHub write (Personal repository creation, SSH key registration). A blocked preflight now performs zero mutations; `_apply_visible_topology` keeps its own guard as defense-in-depth (task 206).
3. Apply asserts the postcondition (`git rev-parse HEAD` equals the fetched target SHA) before ever reporting a fast-forward as successful, rather than trusting `git merge --ff-only`'s exit code, which also exits `0` as a no-op when the checkout is already an ancestor of the target. Each row records whether a fast-forward actually happened versus the checkout already being at the target, so "already at target" is never relabeled as "repaired" (task 205).
4. A run-scoped `completed_actions` ledger records every GitHub repository creation, SSH keypair generation/registration, layer-manifest write (with its rollback outcome), visible-topology clone/fast-forward, and local mirror materialization as it happens, threaded through every exit path — success, blocked, or failed (task 207).
5. Resume and adoption: a `resume` hint is present whenever `result` is `blocked` and always instructs the caller to adopt already-created remotes on retry, never recreate them. "Nothing changed" is only ever a legal claim when the ledger is empty.
6. Never-destroy compensation stays scoped to the existing manifest-file rollback only (original bytes saved to a content-addressed local rollback directory before `migrate`/`repair`). A created GitHub repository or a registered device SSH key is never rolled back — it is recorded as completed and adopted, not recreated, on the next run. No compensation action ever deletes a repository or a key.

## Consequences

- The onboarding transaction is documented and treated as a **saga**, not an atomic transaction: cross-system atomicity across GitHub and local Git is not literally available, so a truthful partial-progress record replaces a false all-or-nothing claim.
- `cc onboard --json` must always carry a `completed_actions` array (possibly empty) and a `resume` hint whenever blocked — formalized as required schema fields in [ADR-007](ADR-007-onboard-schema-v2-breaking-bump.md).
- Control Tower renders the ledger and resume hint; it never infers "safe to retry" on its own — parse-never-compute holds for recovery UX exactly as it does for setup and resolution.
- A "Try again" affordance may only be offered when the reported blocker can actually change; otherwise the UI must route to a specific owner or repair action rather than re-running a transaction that will block identically.
- Any future onboarding-adjacent verb must reuse `_classify_repository_history` as the single source of truth for history classification rather than re-deriving ancestry logic.

## Rejected alternatives

- **Trusting `git merge --ff-only`'s exit code as proof of a completed fast-forward.** Rejected: it also exits `0` as a no-op when the checkout is already an ancestor of the target, which would hide "already at target" behind a false "repaired" label.
- **Reordering mutations without adding a ledger.** Rejected: moving Personal-repo creation later reduces exposure but still leaves no honest record if a later step blocks after a partial write.
- **Rolling back created GitHub repositories or SSH keys on failure.** Rejected: an automated delete on a resource the CLI cannot prove is safe to reverse is a bigger blast-radius mistake than adopting it on retry; never-destroy applies to what the transaction itself created, not only to pre-existing checkouts.
- **A single combined "repaired" label for both "fast-forward performed" and "already at target".** Rejected: it collapses two different facts a resuming operator needs to distinguish.
