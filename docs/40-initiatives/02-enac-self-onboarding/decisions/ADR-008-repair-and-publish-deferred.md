# ADR-008 — `repair` and `publish` verb scoping

Status: Accepted (owner-ratified 2026-07-31)
Date: 2026-07-31
Task: `tc` 213 (gap G-9)

## Context

`CLAUDE.md` invariant 1 and `docs/01-architecture/cli-contract.md` name `doctor`/`update`/`repair`/`resolve`/`deprovision`/`freshness`/`publish` as the versioned CLI contract, but `claude-copilot/tools/cc/src/cc/commands/` contains no `repair.py` and no `publish.py` (verified by directory listing). At the same time, tasks 204–208 (G-1 through G-5) gave `cc onboard` a real, tested history classifier, preflight ordering, postcondition assertion, and mutation ledger — the practical work a `repair` verb was meant to name — for the one case in scope: Git history remediation during ecosystem setup (see [ADR-006](ADR-006-ecosystem-setup-preflighted-saga.md)). The owner ruled on both verbs' scope on 2026-07-31.

## Decision

1. History remediation ("repair" semantics) lives **inside `cc onboard`'s routing**, not a standalone verb. `_classify_repository_history`'s eight states route fast-forwardable rows to an in-onboard fast-forward repair, and every review-state — `dirty`, `ahead-only`, `divergent-identical`, `divergent-different`, `wrong-origin`, `unreadable` — to the owner.
2. A first-class `cc repair` verb is **deferred**: not scheduled, not scoped into this initiative. If a future need arises for repair semantics outside onboard's routing (for example, repairing a materialized `.claude/` tree independent of ecosystem setup), it must be proposed and ratified as a new ADR, not silently assumed from the existing contract prose.
3. `cc publish` — the author-side push of a writable org/department tier — is **formally deferred**. It is not implemented; no code action is scheduled under this initiative. The prior design intent captured in `docs/01-architecture/inheritance-and-publish.md` and the `publish` subsection of `cli-contract.md` remains a valid design record, not a claim that the verb currently exists.
4. No documentation in this repo may list `repair` or `publish` as existing/implemented contract verbs. `cli-contract.md`'s verb inventory lists only implemented verbs (or verbs explicitly proposed and scoped for upstream freeze, as already marked for `layers`); `repair` and `publish` move to an explicit "Deferred verbs" section that cites this ADR. `CLAUDE.md` invariant 1 is reworded to name the verbs that actually exist and to state that `repair` and `publish` are deferred per this ADR.

## Consequences

- Gap G-9 is closed: the contract doc and the invariant no longer imply two verbs that were never implemented.
- A future audit of `claude-copilot/tools/cc/src/cc/commands/` against the contract docs should find no mismatch for `repair`/`publish` going forward — this ADR is a documentation correction, not a code-action item.
- If `cc repair` or `cc publish` is ever built, the implementing task must supersede this ADR explicitly (a new ADR that marks this one superseded) and move the verb back into the main inventory and invariant, rather than quietly re-adding it to the prose.
- The `publish` design intent (author-side push, CLI-computed merge/conflict resolution, app renders the chooser only) is preserved as forward-looking design in `inheritance-and-publish.md` and `schemas/publish.schema.json`; this ADR does not delete that work, it only corrects present-tense claims about it.

## Rejected alternatives

- **Building a first-class `cc repair` verb now.** Rejected: tasks 204–208 already gave `cc onboard` a working, tested classifier, preflight, and ledger for the one repair case in scope. A parallel verb would duplicate ancestry-proof logic and create two sources of truth for the same Git facts.
- **Scoping `cc publish` into this initiative now.** Rejected: the writable-inheritance publish path is a distinct, larger workstream — conflict rendering, leak-scan, tier-scoped credentials — not gated by or required for G-9's history-remediation gap.
- **Leaving the contract docs mismatched until publish/repair are eventually built.** Rejected: this is the reported gap itself; an unresolved doc/code mismatch is a standing trust defect for anyone reading the contract as authoritative.
- **Deleting the `publish` design subsection and schema entirely.** Rejected: it is valid forward-looking design, not inaccurate; the fix is to stop asserting it exists now, not to erase the plan.
