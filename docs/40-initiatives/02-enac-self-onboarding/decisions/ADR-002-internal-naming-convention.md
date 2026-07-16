# ADR-002 — `-internal` naming convention (universal)

**Status:** Accepted (owner, 2026-07-16) · Implemented + test-backed
**Initiative:** [`02-enac-self-onboarding`](../README.md)

## Decision

The org layer is always `<C>-copilot-internal` — a **fixed literal `internal`**, not
the org name. Departments are `<C>-copilot-<department>`. The foundation stays the
bare `<C>-copilot` (public). `internal` is a **reserved department slug**. This is
**universal** — every customer uses these exact names.

| Layer | Repo | Visibility |
|---|---|---|
| Foundation | `Everyone-Needs-A-Copilot/<C>-copilot` | public (bare, never suffixed) |
| Org | `<org>/<C>-copilot-internal` | private |
| Department | `<org>/<C>-copilot-<dept>` | private |

## Why

The engine previously named org-layer repos identically to the foundation
(`<C>-copilot`), relying on a *separate org* to avoid collision. In ENAC's one-org
model ([ADR-001](ADR-001-one-org-no-second-company.md)) those names already exist as
the public foundation, so the engine would conflate the two. A fixed `-internal`
literal is always distinct from the bare foundation name, so foundation and org
coexist in one org — and because it is universal, ENAC dogfoods the shipped path
rather than a bespoke variant. The owner chose the literal `internal` over the org
name (`knowledge-copilot-internal`, not `knowledge-copilot-enac-internal`).

## Consequence

- **Engine** (`scripts/admin_bootstrap.sh`): the org triplet and every reference to
  the org's own repos (ecosystem.yml target, team grants, branch protection,
  `_check_org_triplet`) carry `-internal`; `_check_foundation_pin` stays bare.
- **Reserved word:** the engine refuses a department named `internal`, and the
  undeclared-department scanner skips `<C>-copilot-internal` so it is not misread as
  a department.
- **Tests:** `scripts/tests/test_admin_bootstrap.sh` asserts all of the above →
  **142 passed, 0 failed**.
- **Contract:** `docs/01-architecture/admin-standup-contract.md` carries the
  normative naming table and the reserved-word note.

## Alternative rejected

An optional `org_repo_token` brief field (default empty, preserving the bare
`<C>-copilot` for separate-org customers). Rejected as more complex than needed: a
universal `-internal` literal is simpler, collision-free by construction, and keeps
one convention for everyone.
