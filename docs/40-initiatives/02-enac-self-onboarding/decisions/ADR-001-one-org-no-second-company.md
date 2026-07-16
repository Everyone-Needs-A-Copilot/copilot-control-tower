# ADR-001 — One GitHub org, no second company

**Status:** Accepted (owner, 2026-07-16)
**Initiative:** [`02-enac-self-onboarding`](../README.md)

## Decision

ENAC keeps everything in its existing GitHub org, `Everyone-Needs-A-Copilot`. It
does **not** create a separate org for its private "internal" layer. The
foundation-vs-org-layer distinction is carried by **repo name + visibility**
(`<C>-copilot` public vs `<C>-copilot-internal` private), not by a separate GitHub
organization.

## Why

GitHub's read-confidentiality boundary is the **repository** (public vs private),
not the **organization**. A private repo in `Everyone-Needs-A-Copilot` is exactly
as confidential as one in a dedicated org. The four-tier model
(`docs/10-reference/four-tier-topology.md` §8) only requires a **separate private
layer** — a distinct private repo — on top of the public foundation. It never
actually requires a separate GitHub org; the separate-org language there was
written for a *generic customer* (Acme), whose private content naturally lives in
*their own* org. ENAC is the publisher, so its private layer and the public
foundation share one org, disambiguated by name.

## Consequence

- No new org to create, administer, or pay for.
- The org-layer repo naming must be distinct from the foundation names → resolved
  by [ADR-002](ADR-002-internal-naming-convention.md) (`-internal`).
- ENAC's setup is structurally the same as any customer's, so it dogfoods the real
  path.

## Alternative rejected

Creating a dedicated private org (e.g. `enac-internal`). Rejected by the owner:
"I don't want to create another company. That's the whole point of doing it with my
company." It also added an org boundary the confidentiality model does not need.
