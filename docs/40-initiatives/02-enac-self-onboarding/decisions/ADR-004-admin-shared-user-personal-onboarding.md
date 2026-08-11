# ADR-004 — Admin provisions shared layers; the user provisions the personal layer

## Status

Accepted — 2026-07-21.

## Decision

ENAC has no department layer. For both Claude and Codex, the effective stack is:

1. personal, rank 10;
2. organization, rank 30;
3. public foundation, rank 40.

Admin Setup owns the overall readiness outcome and provisions the shared
organization layer. It creates or verifies the private organization repositories,
authors shared non-secret configuration, configures policy, and produces a
machine-readable handoff for User Setup.

User Setup owns the personal stage. After the individual signs in with their own
GitHub identity, it creates or selects that individual's private personal
repositories, seeds rank-10 manifests, and installs the resolved personal content.
The admin may verify an opaque status and provenance summary returned by `cc`, but
may not create, own, clone, inspect, or write the personal repositories.

Repository conventions are:

| Layer | Claude | Codex | Owner |
|---|---|---|---|
| Foundation | `Everyone-Needs-A-Copilot/claude-copilot` | `Everyone-Needs-A-Copilot/codex-copilot` | ENAC/public |
| Organization | `Everyone-Needs-A-Copilot/claude-copilot-internal` | `Everyone-Needs-A-Copilot/codex-copilot-internal` | ENAC org |
| Personal | `<user>/claude-copilot-private` | `<user>/codex-copilot-private` | individual user |

`cc` is the onboarding and resolution authority. Control Tower invokes `cc` and
renders its structured result; the app does not compute precedence or write layer
manifests itself. Resolution is product-aware: a winner is selected by
`(product, dimension, item)`, so a Claude skill never shadows a same-named Codex
skill. Materialization uses product-specific, allowlisted targets.

## Consequences

- “Admin Setup covers personal onboarding” means it guarantees and verifies the
  handoff, not that the administrator receives personal access.
- A setup is not complete until User Setup reports personal, organization, and
  foundation layers for both Claude and Codex.
- Duplicate same-named Codex plugins/skills are not treated as inheritance;
  `cc` must resolve one effective winner before materialization.
- Personal credentials, private keys, repository contents, and write authority
  never cross into the admin brief, organization repositories, or fleet output.

## Rejected alternatives

- **Admin creates personal repositories.** Rejected because it transfers personal
  ownership and content visibility to the organization boundary.
- **Install all layers independently and rely on host discovery order.** Rejected
  because identically named skills do not merge and discovery order is not the
  ecosystem precedence contract.
- **Control Tower writes manifests directly.** Rejected because the app must
  parse and render; deterministic CLI code owns computation and mutation.
