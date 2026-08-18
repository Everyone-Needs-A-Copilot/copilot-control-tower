# Ecosystem links

Control Tower is a client of the Copilot ecosystem, not its own second ecosystem. These are the pointers back to where the broader initiative and its tooling actually live.

| What | Where |
|---|---|
| **Ecosystem-extensions initiative** | `claude-copilot` repo, [`docs/40-initiatives/01-ecosystem-extensions/`](https://github.com/Everyone-Needs-A-Copilot/claude-copilot/tree/ecosystem-extensions/docs/40-initiatives/01-ecosystem-extensions) — branch `ecosystem-extensions` &mdash; ⚠️ link path assumes the `docs/40-initiatives-migration` rename has landed upstream; as of this writing that rename is only on an unpushed local branch in `claude-copilot`, so this URL 404s until it merges |
| **Shared ecosystem registry** | `<CSE root>/knowledge-copilot-internal/ECOSYSTEM.md` — the index of every product in the ecosystem with local path, repo, status, and description |
| **Product Creation Copilot** | `<CSE root>/product-creation-copilot` — the conversational product-design tool used for Control Tower's UI/UX track (see [`../03-design/ui-ux/README.md`](../03-design/ui-ux/README.md)) |

> `<CSE root>` is `/Volumes/Dev/Sites/CSE` on the owner's primary machine and
> `/Users/pabs/Sites/CSE` on machines where `/Volumes/Dev` is not mounted — the same
> two-spelling contract `tools/cse-bench/collectors/paths.py` resolves in code.
> The registry moved twice: `shared-docs` → `knowledge-copilot` (2026-06-29) →
> `knowledge-copilot-internal` (2026-07-17), and from the COPILOT root to CSE.

## Self-contained copies already in this repo

To keep this repo buildable without a live cross-repo dependency, self-contained snapshots of the relevant ecosystem docs are vendored here:

- [`ecosystem-architecture.md`](ecosystem-architecture.md) — the ecosystem's own architecture
- [`ecosystem-use-cases.md`](ecosystem-use-cases.md) — the use cases Control Tower delivers against
- [`four-tier-topology.md`](four-tier-topology.md) — the four-tier product topology
- [`../assets/ecosystem-diagram.html`](../assets/ecosystem-diagram.html) and [`../assets/ecosystem-walkthrough.html`](../assets/ecosystem-walkthrough.html) — the two diagrams

These are **snapshots**, not the live source — if the ecosystem-extensions initiative changes upstream, re-pull the relevant sections rather than editing the ecosystem's own docs from here.
