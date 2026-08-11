# ADR-010: Active Setup Preflight

- Status: Accepted
- Date: 2026-08-06
- Owner direction: `tc` task 255

## Context

The shipping Step 7 begins with `cc reconcile assess`. It can prove that a
project is dirty or a shared Copilot repository is behind, but it does not run
the routine reversible work that would remove those conditions. The result is
accurate but operationally passive: it asks the person to commit ordinary work
and update clean shared repositories before asking Control Tower to inspect the
same machine again.

The owner directed setup to save uncommitted project work and download current
foundation, organization/internal, and department setup before presenting the
project batch. The same direction requires shared Copilot repositories to be
read-only unless GitHub grants author authority.

## Decision

Add `cc reconcile prepare --json` as one Python-owned, ledger-backed saga. It:

1. performs a read-only scope and safety assessment;
2. creates normal local commits for eligible dirty **product projects**;
3. runs the existing clean, merge-base-proven ecosystem fast-forward/update;
4. performs a fresh reconciliation assessment; and
5. returns completed actions, exact holds, GitHub authority evidence, and that
   fresh assessment in one versioned response.

Project checkpoint commits are local and are never pushed. Because preparation
is unattended, repository hooks and filesystem-monitor hooks are disabled for
the bounded Git invocations in both checkpointing and shared refresh; setup
must not execute repository-supplied code as a side effect of saving or
downloading work. Git identity and signing configuration remain in force. The checkpoint fails closed on conflicts, detached HEAD, unreadable
identity/status, or unsafe paths. A failure restores transaction-owned index
state and leaves project content for the owner.

Ecosystem repositories are never checkpoint candidates. Setup remains
pull-only for them regardless of GitHub permission. The CLI records GitHub's
calculated base permission: `READ`/`TRIAGE` are read-only;
`WRITE`/`MAINTAIN`/`ADMIN` are author-capable; missing/unreadable evidence is
read-only. Author capability may enable only a separate explicit governed
publish workflow. It never enables a setup-time push.

The local checkout must remain filesystem-writable so Git can fast-forward it.
Filesystem mode bits are not an authorization boundary; the enforceable
boundary is that setup exposes no shared write/push operation and fail-closes
future author operations on fresh GitHub permission evidence.

## Consequences

- The first Step 7 state is active preparation, not a passive warning.
- Partial work is expected saga output. Every completed commit/fast-forward is
  retained and reported before the exact hold.
- Swift decodes and renders the preparation report; it does not run Git,
  combine ledgers, classify permissions, or recompute the fresh assessment.
- `reconcile.schema.json` gains an additive `prepare` response branch while
  retaining response major 2.0.
- `onboard.schema.json` gains additive repository-permission and
  author-capability evidence.
- The prior blanket phrase “never touches a dirty human-owned working tree” is
  refined: setup may append a local preservation commit under this bounded
  contract, but may never overwrite, discard, reset, merge, rebase, or push the
  person's work.

## Alternatives rejected

- **Swift calls `git commit`, `onboard`, then `assess`:** creates a second
  transaction coordinator and cannot return one truthful ledger.
- **Stash/reset before setup:** hides work and stores an implicit Git object
  without making the preservation action legible.
- **Commit ecosystem repositories too:** collapses product work and shared
  author authority, enabling accidental shared-tier publication.
- **Hard reset or forced pull:** violates never-destroy and can erase work.
- **Run repository hooks unattended:** gives a discovered product project or
  downloaded shared repository an arbitrary code-execution path during setup.
  Hooks remain available for normal human Git work, but not for bounded setup
  operations. Signing policy remains in force and can still reject a commit
  safely.
- **Make files read-only with `chmod`:** blocks legitimate pull updates, is
  trivially reversible by the local user, and does not prove GitHub authority.
- **Automatically push when GitHub says WRITE+:** setup is a consumer workflow;
  publishing is a separate higher-risk act and remains deferred.

## Fitness functions

- An ecosystem-scoped row can never reach checkpoint mutation.
- No prepare code path invokes `git push`, `reset --hard`, or force. Every Git
  invocation in both checkpoint and refresh disables repository and
  filesystem-monitor hooks.
- Dirty attached product fixtures produce one local commit and a clean fresh
  assessment without changing a remote.
- Conflict, detached, identity-missing, commit-rejected, and lock-race fixtures
  produce exact holds and preserve content; an executable repository hook is
  proven not to run.
- Clean behind ecosystem fixtures fast-forward, assert `HEAD == target`, and
  prove the refresh runner disables repository hooks.
- Dirty/diverged ecosystem fixtures remain unchanged.
- Missing GitHub permission decodes as read-only; only WRITE/MAINTAIN/ADMIN are
  author-capable.
- A partial report cannot say nothing changed when its ledger is non-empty.
