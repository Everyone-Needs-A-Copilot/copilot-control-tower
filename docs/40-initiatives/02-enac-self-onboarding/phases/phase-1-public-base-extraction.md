# Phase 1 — Public-base extraction (the content map)

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Goal: split `knowledge-copilot` and `cli-copilot` into a **public generic base**
> and a **private ENAC org layer** (`-internal`), with a concrete per-file
> decision map — not just the mechanics. **Every** base copilot repo also ships a
> **scaffolding wizard** for its own domain — knowledge **content** (company *and*
> personal), CLI **integrations**, and **agents & skills** for claude/codex — so a
> brand-new adopter can build their *own* filled-in version (see the wizard sections
> below).

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

## Every base ships a scaffolding wizard (not just an empty tree)

"Structure transfers" is only real if a new adopter can actually *use* the empty
scaffold. So **every** base copilot repo ships a **scaffolding wizard for its own
domain** — it walks the adopter from empty skeleton to *their own* filled-in version:
propose a starting shape → let them reshape it → create it. One wizard per copilot:

| Base repo | Wizard | Scaffolds |
|---|---|---|
| `knowledge-copilot` | content wizard (extends `/knowledge-copilot`) | company/org knowledge **and** personal knowledge (two separate layers) |
| `cli-copilot` | integrations wizard (`/setup-integration`) | a new service integration + the key-storage model |
| `claude-copilot` | agents & skills wizard | a new agent or skill |
| `codex-copilot` | agents & skills wizard | a new agent or skill |

> **Command choice:** we **extend the existing `/knowledge-copilot` command** and add
> siblings (`/setup-integration`, and an agent/skill scaffolder) — we do **not** mint a
> new `/setup`. `/setup` already names the machine-setup skill; reusing it would collide.

### Everyone always has two separate layers: company/org **and** personal

A universal rule the wizards enforce structurally: **every adopter, at every size, runs
two always-separate knowledge layers.**

- **Company/Org layer** — the broader "how we work, our brand, our products, our methods
  and capabilities." Its *shape* scales with the adopter (Enterprise / SMB / Solo). It
  lives in the **org tier** (`<C>-copilot-internal`) — or, for a solo adopter with no
  company org, in that person's **own account**, but still as its own distinct layer.
- **Personal layer** — the deeply individual "how *I* specifically write, think, decide,
  and work." This is **universal and identical in concept** for a solo founder and for an
  engineer inside a 10,000-person enterprise; it adds the same value whichever hat you
  wear. It always lives in the **personal tier** (`<C>-copilot-private`), **never** mixed
  into the company layer.

So even a solo engineer gets **both** — a small company layer *and* a personal layer —
kept separate, both in their own account. This is the bottom of the inheritance chain
(foundation → org → dept → **personal**, invariant #6): the personal layer is always
present and never flows upward into shared tiers.

These wizards are **base deliverables** — generic, content-free *capability*, shipped in
each public repo. They are **net-new** relative to a pure "extract what already exists"
split, so each base curation must **author** them, not just move files. They never
contain business content; they only help an adopter create their own.

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
| The **scenario-aware content wizard** (`/knowledge-copilot`, extended) + the generic company baselines (Enterprise/SMB/Solo) **and** the universal personal-layer template | The content the wizard *produces* for ENAC — the real company knowledge (`-internal`) and the owner's personal layer (`-private`, per-user, out of this repo) |

**Acceptance for `knowledge-copilot` base:** a clean clone builds a coherent, empty
knowledge scaffold a new company can start filling in; a grep across it for any
ENAC customer name, product name, or private endpoint returns nothing.

### The content wizard — scaffolds two separate layers (base deliverable)

The content wizard (extending `/knowledge-copilot`) scaffolds **both** layers above,
**kept separate**: a **company/org layer** shaped by org size, and a **personal layer**
that is the same for everyone. It runs *propose → adjust → confirm → create* and never
assumes.

**Company/Org layer — pick the profile.** The wizard asks which of three shapes fits,
then proposes a matching baseline the user reshapes freely:

| Profile | The company baseline the wizard proposes (a starting point, fully editable) |
|---|---|
| **Enterprise** — multi-unit, regulated, governance-heavy | governance (ownership/RACI/taxonomy/review), org & operating model, brand + **DAM** (asset rights, sub-brands), voice & messaging, **legal & compliance** (privacy, records retention), **security/infosec** (data classification, incident response), people ops, procurement & vendor risk, product/service dossiers, GTM & market, **standards** (accessibility/WCAG, localization, design system, engineering), methods/playbooks, reference |
| **SMB / small firm** — one entity, light governance (≈ a trimmed ENAC) | how-this-repo-works, company & team, brand + voice (merged), offerings & pricing, GTM, methods/patterns, light policies (legal/security/people essentials), reference |
| **Solo** — a company of one, low ceremony | how-this-repo-works, offerings/products, methods & patterns, stack & capabilities, reference (still its own layer, in the adopter's own account) |

**Personal layer — universal, always separate.** Independent of the profile above, the
wizard scaffolds a personal layer whose value is identical whether you're solo or inside
an enterprise. These are **individual profile docs that shape how every copilot writes
and works for you** — they serve knowledge-copilot (how it writes), cli-copilot (how it
works), *and* claude/codex (how your agents behave):

- **Writing / voice style** — tone, rhythm, formatting; steers prose *and* commit
  messages, PR text, docstrings.
- **Personality & working-style profile** — async/direct, detail depth; sets verbosity,
  proactiveness, explain-vs-just-act.
- **Decision principles** — your heuristics and tradeoff priorities; lets a copilot make
  defensible calls unprompted, in drafts and in architecture.
- **Communication defaults** — brevity, when to ask vs. proceed, report format; governs
  how a copilot escalates.
- **Domain-expertise map** — deep vs. light areas; the copilot stops over-explaining your
  strengths and flags your weak spots.
- **Bio & positioning** — anchors first-person writing and self-referential READMEs.
- **Values + red-lines / no-gos** — what you optimize for, and hard prohibitions (words,
  tactics, libraries, licenses, data practices) a copilot must never cross.
- **Tools & stack defaults** — the coding copilot reaches for your defaults instead of
  guessing.

> The personal layer is the **individual-scoped mirror of the org's `02-voice`**
> (identity, principles, glossary) refocused from "the company" to "this person." It
> always lands in the **personal** tier (`<C>-copilot-private`), never in the public base
> or the company layer.

**Wizard journey (`propose → adjust → confirm → create`):** (1) read signals (repo count,
team size, org remotes) and **ask** the company profile — never assume; (2) render the
matching company baseline as an editable outline ("here's a proposed direction");
(3) invite freeform add / remove / rename / merge, offering common deltas, loop until
satisfied; (4) do the same for the personal layer; (5) echo **both** trees and require an
explicit "yes"; (6) create the directories in their **separate** targets (company →
`-internal`, personal → `-private`), each dir a `README.md` stub with its one-line purpose
+ a starter prompt — **scaffold only, never business content**; (7) hand off: point to the
first sections to fill.

**Acceptance (content wizard):** on a clean base clone the wizard runs, asks the company
profile, proposes a coherent baseline for **each** of the three profiles *and* the
universal personal layer, keeps the two layers in **separate** targets, accepts freeform
edits, and creates **only** empty section stubs — a grep for any business content returns
nothing.

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
| The **integrations wizard** (`/setup-integration`) + the Python adapter template + the documented Go subprocess contract | ENAC's real integrations registry, endpoints, and adapters (already `-internal` / neither, per the rows above) |

**Acceptance for `cli-copilot` base:** the binary builds and runs from the base
clone with `.env.example` copied to `.env`; no real endpoint, token, or ENAC-only
adapter is present; the leak-scan deny-list passes.

### The integrations wizard — `/setup-integration` (base deliverable)

The CLI base's transfer mechanism is an **integrations wizard** that has "the right
conversation" to scaffold a new service and teaches the adopter the **same key-storage
model** the mature instance uses — so they reach the same outcome without inheriting any
ENAC endpoint or secret.

**The right conversation (elicitation flow):** (1) service name & purpose (`kebab-case`);
(2) auth type — `api_key` / `oauth2` / `basic` / `mtls` / `none`; (3) base URL &
endpoints; (4) operations to expose (each becomes a subcommand); (5) expected rate limits
(sets retry/backoff defaults); (6) secret name(s), `SERVICE_SECRETPURPOSE` naming;
(7) **secret scope per credential — personal** (keychain/`.env`) **or shared** (managed
store); (8) output/format defaults (`json` / `table`); (9) error-handling defaults
(retry / timeout / soft-fail); (10) confirm, then scaffold. It refuses to scaffold with a
missing auth type or secret name.

**Language — Python or Go, the user chooses (the wizard pushes neither):**

| | **Python** (first-class template) | **Go** (documented alternative) |
|---|---|---|
| Integration path | Plugs into the existing adapter/plugin architecture | Standalone binary via subprocess (stdin/stdout JSON, exit codes) |
| Best for | Fast iteration; reuse of shared HTTP/retry/config helpers; most integrations | CPU/latency-sensitive work, or a dependency-free single binary |
| Secrets / config | Inherits the host's settings + secret resolution automatically | Reads resolved references passed in at invocation |
| Today | Fully templated, **ships in the base** | Supported pattern + documented contract — **no shipped Go template yet** |

> Wizard copy stays neutral: *"Python plugs straight in and is the fastest path; Go is
> supported if you want a standalone binary or raw performance. Which do you want?"*

**Key storage the wizard teaches** (correct against invariant #6 — nothing here weakens it):

- **Personal secrets** → local `.env` (gitignored) and/or the OS keychain. Never shared,
  never synced upward.
- **Shared / tier secrets** → a tier-scoped **managed store**; its **endpoint** arrives via
  inherited org config (the endpoint is *not* a secret), and access stays gated by the
  user's own team membership.
- **Resolution:** shared/inherited config carries only `requires_secret: <NAME>` — **never
  a value**. At startup `<NAME>` resolves in order: local `.env`/keychain → managed store at
  the inherited endpoint (using the caller's own credentials). If neither resolves it
  **fails closed** — `missing secret <NAME>`, never a silent default.
- **`.env.example` pattern** (committed; values never real):

  ```
  # Personal — obtain your own key from the service dashboard
  EXAMPLESERVICE_API_KEY=

  # Shared — resolved via the managed store; do not set locally unless overriding
  # requires_secret: EXAMPLESERVICE_SHARED_TOKEN
  ```

- **Never in git, ever:** raw secret values, real `.env` files, OAuth/refresh tokens,
  private keys/certs, managed-store credentials, and git **push** credentials (always
  per-user, on-device — never shared-store material).

**Acceptance (integrations wizard):** the wizard collects all elicitation items before
generating any file; presents Python and Go with **no** default pre-selected; every
generated secret is a `requires_secret: <NAME>` reference (no literal value in any
generated file); the generated `.env.example` holds only blank placeholders with
personal-vs-shared comments; it never emits `--skip-verify` / `--force` or writes
security-critical config as user-editable local config; and the scaffold includes a
runtime resolution check that fails closed on an unresolved secret.

## `claude-copilot` / `codex-copilot` — already public base (+ an agents & skills wizard)

These are already public framework repos, so **no content split is needed**. Create
`claude-copilot-internal` / `codex-copilot-internal` (private) **only if** ENAC has
org-level customizations (extra agents, org-default protocol tweaks) to layer on top;
otherwise skip — the org layer for these can be empty or absent.

**But they still get a scaffolding wizard.** To keep all four copilots symmetric and make
extension easy, each ships an **agents & skills wizard** that helps a user create a new
agent or a new skill — the "right conversation" for its domain (name, trigger/description,
tools, the methodology or steps, and where it installs). Same base-deliverable rules: it
scaffolds structure only, ships in the public repo, and authors no proprietary content.

**Acceptance (agents & skills wizard):** on a clean clone the wizard scaffolds a valid,
loadable agent or skill stub (correct frontmatter + directory placement) that the
framework discovers, with no ENAC-specific agent/skill content baked in.

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
3. **Curate** the base into the fresh repo using the maps above, **author this repo's
   scaffolding wizard** (content for `knowledge-copilot`, integrations for
   `cli-copilot`) as base capability, then run the leak-scan. *(The claude/codex
   agents & skills wizards are authored additively — those repos are already public and
   skip the rename dance.)*
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
base repo ready for Phase 2. **All four** copilots ship their **scaffolding wizard** —
the content wizard (company **and** personal layers, kept separate), the
`/setup-integration` integrations wizard, and the agents & skills wizard for
claude/codex — each running on a clean clone and creating only content-free scaffolding.
No base repo is public yet.
