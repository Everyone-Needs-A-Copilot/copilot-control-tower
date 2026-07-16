# Phase 1 — Public-base extraction (the content map)

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Goal: split `knowledge-copilot` and `cli-copilot` into a **public generic base**
> and a **private ENAC org layer** (`-internal`), with a concrete per-file
> decision map — not just the mechanics.

## The principle: structure transfers, content stays private

The public base answers one question: *"what does a brand-new company clone to get
the same system ENAC started from?"* The answer is **structure, method, and
tooling** — never ENAC's accumulated content.

- **Base (public `<C>-copilot`)** = the generic skeleton, conventions, templates,
  method, and open tooling. It is what lets another company *build up to* ENAC's
  level over time. It is **not** a copy of ENAC's five years of content.
- **Org layer (private `<C>-copilot-internal`)** = ENAC's mature, business-specific
  content — the filled-in version of the base. This is where the value ENAC has
  accumulated lives, and it never goes public.

"Get a user to the level I am" means giving them the **same tooling and structure**
plus the generic improvements ENAC promotes down over time — not handing them
ENAC's business knowledge pre-populated.

## The one decision test (apply to every file)

For each file/dir in the current mature repo, ask **in order**:

1. **Does it contain a secret** (token, key, `.env` value, `mcp.json` credential)?
   → It belongs in **neither** repo. Secrets live only in a gitignored `.env` /
   the OS keychain / the managed store (invariant #6). Strip it.
2. **Does it name a customer, a deal, a person outside ENAC, or an ENAC-specific
   business fact** (real product roster, internal ops, proprietary method detail,
   private endpoints)? → **`-internal`** (private org layer).
3. **Is it generic structure, convention, template, method, or open tooling** that
   any company would want unchanged? → **base** (public).
4. **Unsure?** → **`-internal`.** Never-public is the safe default; promotion to
   base is a deliberate, leak-scanned act, never an accident.

## `knowledge-copilot` — the hard split (content *is* the asset)

`knowledge-copilot` is the shared knowledge layer pulled read-only into every
repo's `.claude/`. Its content is the sensitive part, so most of it is `-internal`;
the base is the scaffolding.

| Goes to **public base** (`knowledge-copilot`) | Goes to **private org layer** (`knowledge-copilot-internal`) |
|---|---|
| The **directory taxonomy** itself (the `00-…`/`02-products/<layer>/…`/`04-shared-systems/…` structure) as empty/illustrative scaffolding | Every real `02-products/**` dossier (Convoco, Insights, Method, Forces, etc.) — real product & business data |
| `ECOSYSTEM.md` as a **template** with example/placeholder rows and the column contract explained | The real `ECOSYSTEM.md` with the ~20-product roster, local paths, repo names, statuses |
| The **initiatives standard** (`40-initiatives/` rules, the checker, the pre-commit hook, README template) | Real initiatives with ENAC specifics, client references, or internal strategy |
| Doc **conventions & templates** — overview-card format, claim-check convention, migration guide, "how to use this knowledge layer" | Real company/org profile, positioning, engagement-derived best practices that name clients or deals |
| **Generic** best-practice docs that are true for any company and name no one | Anything referencing a named customer, a real deal, revenue, or internal ops |
| The `@machine`-style sentinels / registry-path conventions (mechanism, not values) | Real registry values, real machine paths, real endpoints |

**Acceptance for `knowledge-copilot` base:** a clean clone builds a coherent, empty
knowledge scaffold a new company can start filling in; a grep across it for any
ENAC customer name, product name, or private endpoint returns nothing.

## `cli-copilot` — the easier split (code publishes; config stays)

`cli-copilot` is the `copilot` binary fronting ~20 services. The **code** is
largely publishable because secrets already live in a gitignored `.env`
(invariant #6). The split is mostly about business-specific *configuration*, not
source.

| Goes to **public base** (`cli-copilot`) | Goes to **private org layer** (`cli-copilot-internal`) |
|---|---|
| The binary **source** and command structure | ENAC-specific service **wiring/config** choices (which services, which internal endpoints) |
| Service **adapter interfaces** + the plugin/extension architecture (how to add a service) | Any **proprietary/ENAC-only** service adapters not meant to be open |
| **Open** integrations whose code carries no secret (e.g. the Discord bridge logic, skill runtime) | The **integrations registry** (`integrations.registry.json`) with real ENAC integrations |
| `.env.example` **templates** + docs on configuring services | The real `.env` → **neither repo** (gitignored; keychain/managed store only) |
| Generic "how to run / configure `copilot`" docs | Hardcoded internal hostnames, private service URLs, ops runbooks naming ENAC infra |

**Acceptance for `cli-copilot` base:** the binary builds and runs from the base
clone with `.env.example` copied to `.env`; no real endpoint, token, or ENAC-only
adapter is present; the leak-scan deny-list passes.

## `claude-copilot` / `codex-copilot` — already public base

These are already public framework repos. No split needed. Create
`claude-copilot-internal` / `codex-copilot-internal` (private) **only if** ENAC has
org-level customizations (extra agents, org-default protocol tweaks) to layer on
top; otherwise skip — the org layer for these can be empty or absent.

## The leak-scan deny-list (the gate before any base goes public)

Before a base repo is made public (Phase 2, gated), it must pass a hard-fail scan
for:

- credential shapes — `BEGIN … PRIVATE KEY`, known token prefixes, high-entropy
  strings, `.env` value shapes, `mcp.json` secrets;
- **ENAC customer / person names** (deny-list of known client and partner names);
- real deal / revenue / engagement data;
- private endpoints / internal hostnames;
- internal-knowledge path globs (e.g. anything under the real `02-products/**`
  business dossiers).

A hit is a **refuse-to-publish**, not a warning. This is the defense-in-depth
backstop; the primary guarantee is the never-public default (decision test step 4).

## Mechanics — the rename-redirect sequence (do not reorder)

Per repo (`knowledge-copilot` first, then `cli-copilot`):

1. **Rename** the current private repo → `<C>-copilot-internal` (stays private,
   becomes the org layer). GitHub preserves history/issues and sets a redirect from
   the old name.
2. **Create** a fresh `<C>-copilot` — **create it PRIVATE**. Creating a repo with
   the old name drops the old→new redirect and the new repo takes the name.
   > ⚠️ **Hazard:** from this point, every consumer still pointing at
   > `Everyone-Needs-A-Copilot/knowledge-copilot` resolves to the **base skeleton**,
   > not the mature content. Phase 2 re-points every consumer via the manifest
   > **before** anything relies on it. Sequence: rename → create-new → re-point.
3. **Curate** the base into the fresh repo using the maps above; run the leak-scan.
4. Leave it **private** until Phase 2's gated publicize step.

**Registry note:** `knowledge-copilot` is also the ecosystem registry home. Renaming
it touches registry paths and this repo's `CLAUDE.md`/`ECOSYSTEM.md` references —
update those in the same change.

## Open decision carried into this phase

**`copilot promote` is not built** (not among the WS-A verbs). The first
base-extraction is therefore a **manual, one-time curation**. Decide whether to
build `promote` (topology §8.2 — the private→public cherry-pick + leak-scan + PR
valve) **before** the ongoing "author privately → promote generic bits to public"
loop needs to be smooth. For the first pass, manual curation is sufficient.

## Exit criterion

Both `knowledge-copilot` and `cli-copilot` exist as (a) a private `-internal` org
layer holding ENAC's full mature content and (b) a private, curated, leak-scan-clean
base repo ready for Phase 2. No base repo is public yet.
