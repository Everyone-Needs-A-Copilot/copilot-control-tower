# ADR-005 — Visible ecosystem repositories are the user-facing source locations

Status: Accepted
Date: 2026-07-31
Task: `tc` 202

## Context

Control Tower previously counted private GitHub repositories and hidden clones
under `~/.copilot/mirrors` as installed layers. A person could therefore see a
green Personal result while no corresponding repository was visible beside the
Copilot repositories they actually use. Department membership was also omitted
from aggregate onboarding, so an Accounting user received a twelve-layer plan
instead of the entitled sixteen-layer topology.

## Decision

1. Aggregate onboarding owns one visible `paths.repositories_root`.
2. It may infer that root only from an unambiguous existing component cluster
   inside already approved project roots. Otherwise the person chooses it.
3. Foundation, Organization, entitled Department, and Personal repositories
   are created or downloaded as visible siblings in that root.
4. A Personal layer is never stored only under `~/.copilot/mirrors`.
5. The layer manifest records the visible checkout path and GitHub remote.
6. Existing visible working trees are human-owned. Control Tower may reuse
   them, or fast-forward a clean checkout; it never resets a dirty checkout.
7. A disposable hidden cache may exist for transport optimization, but it is
   non-authoritative and cannot satisfy repository presence or readiness.
8. Department layers are included only when both the organization handoff and
   active GitHub team membership prove entitlement.
9. Readiness requires the expected GitHub repository, visible checkout,
   manifest connection, synchronization/materialization, non-empty resolution,
   and post-apply verification to pass.

## Consequences

- The interface exposes repository names and visible paths; ranks stay internal.
- Legacy hidden Personal clones are excluded from readiness and moved intact
  out of the active mirror tree after the visible topology verifies.
- A wrong-origin path, unfamiliar manifest, missing shared remote, dirty
  checkout requiring history movement, or unreadable GitHub response stops the
  transaction without altering that checkout.
- Existing architecture language that describes every layer checkout as a
  disposable mirror is superseded for user-visible onboarding checkouts by this
  decision. Never-destroy applies to every visible checkout.

## Rejected alternatives

- Keep Personal repositories hidden and merely disclose the path.
- Copy content into a visible folder while retaining a hidden canonical clone.
- Infer department participation from folder names.
- Reset visible shared checkouts because they are normally consumer read-only.
- Let the app synthesize readiness independently of `cc`.
