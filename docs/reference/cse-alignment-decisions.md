# CSE Alignment Decisions

The authoritative decision record for correcting Copilot Control Tower to the
Copilot Solutioning Ecosystem (CSE) model. Everything else in the repo conforms
to this. Read the model first: [`copilot-solutioning-ecosystem.md`](./copilot-solutioning-ecosystem.md).

Context: an audit found the repo was ~80% aligned to the CSE but carried a
pervasive vocabulary collision, an over-rotation into enterprise MDM, and two
missing CSE responsibilities. These decisions resolve that.

## D1. What Control Tower manages

Control Tower orchestrates the **CSE tooling components** (Development Harness,
Claude/Codex Copilot instruction layer, Knowledge Copilot, CLI Copilot) across
four inheritance layers. It does **not** manage the **products/projects** you
build with that tooling. This is the load-bearing distinction.

## D2. Vocabulary (pinned)

- **Component** = a CSE tool: `knowledge`, `cli`, `claude`, `codex` (+ the
  Development Harness). What Control Tower syncs.
- **Layer / tier** = `foundation` -> `org` -> `department` -> `personal`.
- **Product / Project** = the built output (Insights Copilot, Pipeline, Method).
  **Never synced by Control Tower.** Reserve this word for outputs only.
- **Entitlement** = GitHub repo access. You have a layer iff you can access its repo.

Action: rename `product` -> `component` across code and docs wherever it means a
CSE tool. Do not rename genuine uses that mean a built output.

## D3. Entitlement is GitHub repo access (the spine)

Repo access is the single entitlement and deployment model. Team membership grants
read/write; selecting an entitled department syncs that layer onto the machine.

## D4. MDM is dropped completely (including the seam)

No MDM. No `.mobileconfig` generation, no Jamf/Kandji/Intune flows, no forced/
managed configuration domain, no fleet dashboard as an Admin center of gravity,
no forced-key deprovision. Consequences and rehoming:

- **Install:** users self-install the signed, notarized `.dmg`. No zero-touch.
- **Security-sensitive config** was previously honored only from the forced MDM
  domain. Rehomed to: **compiled-in trust roots** (unchanged) + **signed,
  inherited org/foundation config** (a signed capability policy). Nothing
  security-critical comes from user-editable local config.
- **Shared secret-store endpoint** was previously delivered via the MDM forced
  domain. Rehomed to **inherited org repo config**. The endpoint URL is not a
  secret; access to the store remains gated by the user's own GitHub-team
  membership / token, so pointing elsewhere grants nothing.
- **Offboarding:** revoke the person's GitHub access + rotate shared-secret store
  tokens. Accepted residual: content already synced to a departed person's disk
  is not remotely wiped (no MDM to reach the device). Acceptable for the target
  (small, trusted orgs).
- **Deprovision flag integrity** (a user cannot un-deprovision themselves) was an
  MDM property; it is replaced by server-side revocation (repo access + store
  tokens), which the user cannot reverse.

MDM may return later as an **optional enterprise adapter**, but it is a future
re-architecture, not a dormant seam we keep now.

## D5. Inheritance mechanism (resolves CSE open question 1)

Not fork/upstream. Each component x tier is a **separate, co-resolved repo**;
orgs keep their own additions via **resolver precedence** over the separate
Foundation repo (referenced by version, e.g. `^5.13.0`, anon HTTPS), and promote
personal/dept work upward only via a one-way, human-invoked `copilot promote`.
See `docs/reference/four-tier-topology.md` §6/§8.

## D6. Central shared secrets (resolves CSE open question 3)

A tier-scoped shared secret store (e.g. Infisical / OpenBao) holds org/department
integration keys (Workday, Salesforce, Microsoft, etc.). Access is by GitHub-team
membership. Endpoint delivered via inherited org config (D4). Users never set up
their own keys for shared integrations. This is distinct from personal sign-in.

## D7. Three surfaces to design (the CSE gaps)

These are new; none exists today.

1. **Department discovery + join-by-repo-access** (CSE open question 2). Surface
   the departments a user is entitled to, validate by their repo access, sync the
   selected layer onto the machine. The prior design *descoped* this
   (`control-tower-interaction-spec.md` open-Q6); that descope is reversed.
2. **Entitled shared-integrations.** Show the shared integrations a user has via
   org/dept entitlement (provisioned centrally, D6), as a distinct register from
   **personal sign-in** (device-flow, per-person). The current design conflates
   the two.
3. **Personal-key multi-machine sync** (CSE open question 4). Sync a user's own
   personal keys across their own machines, ending the `.env` hand-copying. The
   current credential model assumes per-machine re-auth; this reverses that for
   personal keys.

## D8. Delete the products-picture vestige (confirmed)

Remove `DeptProjectView` / `LayerView.projects` (a project nested inside a
component layer), its renderers (`popover.ts` `buildProjectRow`, `copy.ts`
`deptProjectLabel`), and its placeholder test. It seeds the products picture the
model forbids, is inert today (always empty; the M1 CLI schema has no project
field), and its removal loses no working feature. Owner-confirmed.

## D10. Projects are self-contained, not a Control Tower layer

A **product/project** carries its own knowledge, skills, agents, and integrations
*inside its own repo* (a project always has its own repo). That project-level CSE
content is standardized and materialized by the Copilot instruction layer
(Codex/Claude Copilot) when you work in that project. It is **not** a Control Tower
sync layer, and there is no "department project" entry in Control Tower's model.
This is the reason D8's `DeptProjectView` is removed.

Open (framework concern, revisit later — NOT Control Tower): how a project
standardizes its knowledge/skills/agents/integrations — all within `docs/` or a
dedicated structure — likely built into Codex/Claude Copilot, so projects don't
each need extra repos.

## D9. What is kept (do not rework)

- The four-layer inheritance model, pull-only downward, never-destroy.
- Secrets-never-in-git; per-user on-device keys + tier-scoped shared store.
- CLAUDE.md invariants (parse-never-compute, never-destroy, route-by-competence,
  one-way inheritance) — with invariants #4 and #6 reworded for D4.
- The design **craft**: the "Quiet Instrument" visual system, honest-degrade /
  silent-when-fine, the badge grammar, the interaction mechanics, the Publisher
  Setup family look, and the entire **Publisher signing journey**.
- The Admin **seed generator** and the repo + team-grant spine.

## Impact map (docs to conform)

| Doc | Change |
|---|---|
| `docs/reference/glossary.md` | Redefine `product` axis as `component`; add Product/Project = output. |
| `docs/reference/four-tier-topology.md` | Rename `product` axis -> `component`; note it answers CSE open-Q1. |
| `SOUL.md` | Name the CSE components as the synced units; import the tooling-not-products line; remove MDM as the managed lane. |
| `CLAUDE.md` | Rewrite invariant #4 (drop forced MDM domain; trust roots compiled-in + signed inherited config) and invariant #6 (secret-store endpoint via inherited org config, not MDM). |
| `docs/05-security/credentials-and-boundary.md` | Rehome secret-store endpoint delivery (D4); add personal-key multi-machine sync (D7.3); recast offboarding (D4). |
| `docs/01-architecture/cli-contract.md` | Add an entitlement/discovery verb for department join (D7.1); remove MDM/forced-domain contract surface. |
| `docs/00-overview/product-brief.md` | Name all four components as synced; drop MDM framing. |
| `docs/02-prd/prd.md` | Reframe "what is synced" per component x layer; elevate entitlement discovery; drop MDM workstreams. |
| `docs/03-design/three-role-journeys.md` | Keep Publisher; reframe User (component currency + join + shared-vs-personal integrations); rebuild Admin around repos/teams/secret-store/seed, drop MDM half. |

## Open (still to decide during design)

- The exact UX and CLI verb for department discovery/join (D7.1).
- The carrier/mechanism for personal-key multi-machine sync (D7.3) and how it
  reconciles with the per-user on-device key model.
