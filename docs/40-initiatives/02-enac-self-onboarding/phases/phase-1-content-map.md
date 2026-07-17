# Phase 1 — Finalized content map (`base` / `-internal` / `neither` / `split`)

> Initiative: [`02-enac-self-onboarding`](../README.md) · Companion to
> [`phase-1-public-base-extraction.md`](phase-1-public-base-extraction.md) (the *why*;
> this doc is the *per-path what*).
> Produced 2026-07-17 by a **read-only** classification sweep of the real trees
> (`/Volumes/Dev/Sites/COPILOT/{knowledge-copilot,cli-copilot}`). Nothing was modified.
> This doc contains `-internal`-class detail (private endpoints, infra, secret
> *locations*) — it lives only in this **private** repo and must never be promoted to a
> base. It quotes **no secret values**.

**Buckets** (from the one-decision-test):

- **`base`** — generic; goes to the public `<C>-copilot`.
- **`-internal`** — ENAC business content; goes to the private `<C>-copilot-internal`.
- **`neither`** — a secret or a local/build artifact; belongs in **no** repo.
- **`split`** — structurally generic but ENAC-filled: the real file → `-internal`, a
  templatized/placeholder copy → `base`. Strip-lists are in [§4](#4-split-files--the-strip-lists).

---

## 1. ⚠️ STOP-SHIP — live secrets are committed to git (do these before anything else)

The sweep found **live credentials in tracked files / git history**. The base/internal
split does **not** undo git-history exposure, so this is the first work of Phase 1, ahead
of any rename.

| Location | What's exposed | Action |
|---|---|---|
| `knowledge-copilot/03-ai-enabling/03-operations/02-keys.md` (**tracked**) | A **live** set: Discord bot token + app id/public key, an **OpenAI** key, an **Anthropic** key, a **Coolify** API key, a **Notion** token, a localhost overview token | **Rotate/revoke all of them now.** Then remove the file; move values to keychain / managed store (invariant #6). |
| `knowledge-copilot/config/mcp-credentials.md` (**git history**) | A Skills-Copilot Postgres password + `SKILLSMP_API_KEY` (self-documented as revoked, but still in history) | Confirm revoked; scrub history or fresh-init the base (below). |
| `knowledge-copilot/config/ssl/postgres-ca.crt` | ENAC Postgres CA cert | `neither` — never copy to base. |
| `cli-copilot/.env` (**gitignored + untracked** ✓) | `ecosystem-admin` Infisical identity + all service keys | Safe today. Keep untracked; never add to either repo. |

**Structural consequence — the base repos must be a fresh `git init`, not a
history-filter.** Because live/revoked secrets sit in `knowledge-copilot` history, curating
the base by filtering existing history would republish them. Both repos' sweeps reached
this independently; `cli-copilot` already encodes it as **GATE A** in its own
`docs/initiatives/001-framework-oss-split.md` (full-history scrub / fresh history + `@agent-sec`
sign-off). **Decision to lock: base = fresh-history repo seeded by copy, no inherited git log.**

---

## 2. `knowledge-copilot` — the hard split

### 2.1 Root files

| path | bucket | note |
|---|---|---|
| `CLAUDE.md`, `CLAUDE_REFERENCE.md`, `.gitignore` | base | Pure generic framework guidance. |
| `.mcp.json`, `.codex-copilot.json` | base *(templatize)* | Strip the `/Users/pabs/...` path / `WORKSPACE_ID` / `projectName`. |
| `README.md`, `PURPOSE.md`, `STRUCTURE.md`, `SETUP.md` | **split** | Generic shape, filled with ENAC brand/products/methods/org/domains. |
| `SOUL.md`, `AGENTS.md` | **split** *(light)* | One ENAC line each — strip the company/project reference. |
| `ECOSYSTEM.md` | **split** | Schema is generic; body = the real product roster, private endpoints, org, owner, client names, local paths. |
| `knowledge-manifest.json` | **split** | Manifest schema is generic; entries declare proprietary skills/voice/infra extensions. |

### 2.2 Directories

| path | bucket | note |
|---|---|---|
| `00-best-practices/` | base | Cross-project templates/standards. *Two files leak a method name / "Convoco" anecdote — genericize on promote.* |
| `01-company/` | **-internal** | The entire real company KB (brand, voice, Forces, pricing, GTM, case studies w/ real clients, org/team, pursuits). |
| `config/mcp-credentials.md` | **-internal** | References private Infisical endpoint + infra history (see §1). |
| `config/ssl/postgres-ca.crt` | **neither** | Cert (§1). |
| `.claude/agents,commands,hooks,skills,cc,fitness-check.sh,settings*` | base | Generic framework wiring; no secrets. |
| `.claude/extensions/` | **-internal** | The proprietary payload: `sd.override`=Moments, `do.extension`=real `*.ineedacopilot.com` infra inventory, `cw`=Authentic Provocateur voice, `uxd`=force-based, `ind`. |
| `.claude/memory/entries/*.md` | **-internal** | Tracked memory (ADRs, real paths, product names). |
| `.claude/memory/memory.db*`, `.copilot/tasks.db*` | **neither** | Gitignored local stores. |
| `.agents/`, `plugins/` (symlinks), `scripts/` (checkers/installers) | base | Generic tooling. |
| `scripts/crosslinks-baseline.json` | **-internal** | Generated snapshot of this repo's real content paths; base regenerates its own. |
| `_archive/` | *(excluded)* | Never ingested; not part of either repo. |

### 2.3 `02-products/`, `03-ai-enabling/`, `04-shared-systems/`, `openclaw/`, `docs/`

| path | bucket | note |
|---|---|---|
| `02-products/` layer taxonomy (`01-ecosystem … 99-innovation-roadmap` empty scheme + the 8-section dossier skeleton) | base | Reusable folder convention/template when empty. |
| `02-products/README.md` | **split** | Structure prose = base; strip the real roster + visibility statuses. |
| `02-products/{01-ecosystem,02-foundational,03-work,04-applications,99-innovation-roadmap}/**` | **-internal** | Every real dossier (repos, local paths, infra, API, security) + the 99-roadmap interview guides that name real people. |
| `03-ai-enabling/01-skills/` taxonomy + `00-reference/How To Create A Skill.md` + ~17 generic skill families (code, testing, design, security, infra, architecture, docs, service-design, copywriting, strategy, analysis, etc.) | base | Skill **framework** + methodologies that name no client (spot-checked). **Large reusable library.** |
| `01-skills/01-analysis/{forces-analysis,moments-mapping}`, `02-facilitation/{colab,cocreate}`, `06-strategy/forces-quick`, `07-copywriting/authentic-provocateur-voice`, `07-service-design/forces-of-progress-mapping`, `17-software-factory/**` | **-internal** | ENAC proprietary methods / brand voice / factory model (names real repos + paths). |
| `03-ai-enabling/02-profiles/*/00-template.md` (and agentic templates) | base | Blank role-profile templates. |
| `03-ai-enabling/02-profiles/**` (filled), `03-operations/**`, `03-openclaw/**` | **-internal** | ENAC persona roster, ops docs, personal life-ops agents. |
| `03-ai-enabling/03-operations/{01-human-centered-development,03-documentation-guide,06-…statusline}` | **split** | Generic conventions filled with ENAC examples. |
| `03-ai-enabling/04-prompt-library/{00-04}` | base | Reusable client-free LLM prompts. |
| `03-ai-enabling/04-prompt-library/05-n8n-prompts.md` | **split** | Verify no ENAC workflow IDs before promoting. |
| `04-shared-systems/00-systems-map.md`, `platform/**` | **-internal** | 41 KB ENAC systems map; real infra (Hetzner CCX23 Ashburn, Coolify, Mac Mini M4, `*.ineedacopilot.com`, SSH keyfile name). |
| `04-shared-systems/design-system/src` (components + token *architecture*), config (`.storybook`, vite/tailwind/tsconfig) | base | Generic React/Tailwind/Storybook engine. |
| `04-shared-systems/design-system/{README, LANDING-PAGE-*, stories/07-templates/LandingPage*, patterns/Hero, layout/Header+Footer}` + brand color/type token **values** | **-internal** | ENAC marketing brand + landing templates. |
| `04-shared-systems/design-system/{node_modules,storybook-static,*-lock}` | **neither** | Build artifacts. |
| `openclaw/**` | **-internal** | Self-hosted config: real key paths, MCP connections, Mac-mini deployment. |
| `docs/00-knowledge-copilot/{01-build-a-kms,02-consumption-contract}` | base | Generic KMS methodology + path contract. |
| `docs/00-knowledge-copilot/{03-migration-guide,04-machine-settings-migration}` | **-internal** | ENAC-specific migration (real paths/history). |
| `docs/01-architecture/12-…principles.md`, `docs/40-initiatives/README.md` | **split** | Principles/framework text = base; strip the ENAC system-context header / current-initiatives table. |
| `docs/40-initiatives/_template/**` | base | Generic initiative/ADR/retro templates. |

### 2.4 knowledge-copilot ⚠️ red-flags (beyond §1)

- **`03-ai-enabling/03-operations/02-keys.md`** — the live-key file (§1). Highest risk.
- **Placeholders (safe):** `sk-…` patterns in `insights-copilot/06-security.md` and a
  technical-writing skill are illustrative, not live.
- **Infra topology** in `04-shared-systems/platform/**` and `.claude/extensions/do.extension.md`
  (host sizing, subdomains, SSH keyfile name) — not key material, but `-internal`.

---

## 3. `cli-copilot` — the easier split (code publishes; config stays)

### 3.1 Core + per-service verdict

| path | bucket | note |
|---|---|---|
| `copilot_cli/__main__.py`, `main.py`, `shared/` | base | Generic dispatch / HTTP / plugin plumbing. |
| `copilot_cli/config/settings.py` | **split** | Generic `_find_env_file()` + `BaseSettings` pattern = base; **hardcodes 3 ENAC default endpoints + git identity** (strip-list §4). *Single most important cut.* |
| services → **base**: `bi, brevo, coolify, discord, docker, document, filesystem, git, monitoring, n8n, nocodb, postgresql, shell, skill, system_services, uspto` | base | Generic adapters; all endpoints/keys come from env/config. |
| services → **base (1 templatize)**: `infisical` | base | Adapter is instance-agnostic; only `core/config.py` hardcodes the ENAC default (§4). |
| services → **-internal**: `conversations` (Convoco: `*.convocoai.com`, private repo shell-out), `insights` (Insights Copilot API `insightsapi.ineedacopilot.com`), `project_copilot` (ports an internal worker workflow; `method-demo.ineedacopilot.com`) | -internal | ENAC-product-coupled adapters. |
| services → **exclude**: `fireflies`, `metabase`, `reddit` | *(none)* | Empty stubs — **no committed source** (`git ls-files` empty). |
| `docs/services/*` for base services (git, docker, shell, filesystem, system-services, postgresql, nocodb, brevo, n8n, document, bi, monitoring, skill, uspto, discord) | base | Generic usage docs (0 infra hits). |
| `docs/services/{09-insights,15-coolify,16-project-copilot,17-conversations}.md` | **-internal** | Proprietary products / real VPS IP + SSH runbook (`15-coolify`). |
| `docs/services/18-infisical.md` | **split** | Strip `secrets.ineedacopilot.com` from the env table. |
| `docs/{00-overview,01-setup,02-usage}.md` | base | Generic orientation. |
| `docs/initiatives/**` (`000-open-core`, `001-oss-split`, `banking-integrations`, `discord-*`, `infisical-rollout`, `reddit-research`, …) | **-internal** | Internal business/build planning; `infisical-rollout` names a live Coolify service UUID, Hetzner, admin identity. |
| `tests/**` for base adapters | base | Come along with their adapters. |
| `tests/test_services/{test_insights,test_conversations*,test_evidence,test_project_copilot*,…}` | **-internal** | Assert ENAC-product URLs. |
| `tests/test_services/test_infisical.py` | base *(1-line)* | L115 asserts the ENAC default — update to templatized value. |
| `.env` | **neither** | Untracked (§1). |
| `.env.example`, `.claude/skills/workflow-automation/SKILL.md` | **split** | ENAC URLs baked in (§4). |
| `.mcp.json.example`, `.claude/cc/config.json`, `pyproject.toml`, `Makefile`, `uv.lock`, `.github/`, `scripts/e2e_health.py`, `README/SOUL/CLAUDE` | base | Standard meta (skim README/SOUL for narrative before push). |

### 3.2 cli-copilot ⚠️ red-flags (beyond §1)

- **`docs/services/15-coolify.md`** — real VPS IP, `root@` SSH + Mac-mini ProxyJump runbook. `-internal`.
- **`docs/initiatives/infisical-rollout/**`** — points at `cli-copilot/.env`, a Coolify service UUID, Hetzner, `secrets.ineedacopilot.com`. `-internal`.
- **Hardcoded ENAC endpoints in code** (strings, no tokens) — the CI "zero-company-strings" gate targets: `settings.py`, `infisical/core/{config,api_client}.py`, `project_copilot/evidence.py`, `conversations/launch/env.py`.

---

## 4. Split files — the strip-lists

**knowledge-copilot**

- `ECOSYSTEM.md` → keep column headers + one placeholder row + the 3-layer taxonomy prose; strip all product rows, local paths, endpoints, the GitHub org, owner handle, and the client-delivery line.
- `README.md` / `PURPOSE.md` / `STRUCTURE.md` / `SETUP.md` → keep the scaffold with `<COMPANY>`/`<method>`/`<org>/<repo>`/`<skill>` placeholders; strip brand, domains, method names (Forces/Moments/CoLab/CoCreate), "Authentic Provocateur", product tables, infra (Coolify/Hetzner/Mac Mini), skill names.
- `SOUL.md` / `AGENTS.md` → strip the single company/project line each.
- `knowledge-manifest.json` → `version`/`framework` + empty (or one placeholder) `extensions[]`; drop proprietary skill/voice/infra declarations.
- Base-bucket files needing a token swap on promote: `00-best-practices/03-templates/06-…/00-vision.md` (method names), `…/07-initiative-package/README.md` ("Convoco" anecdote), plus the generic skills whose worked examples name ENAC products (`06-architecture/03-technical-writing`, `10-documentation/readme-excellence`, `02-testing/03-testing-patterns`, `03-design/05-user-flows`).

**cli-copilot**

- `copilot_cli/config/settings.py` → base gets `_find_env_file()` + a `BaseServiceSettings`; move ENAC defaults to the `-internal` subclass. Strip: `n8n_base_url`, `nocodb_url`, `insights_base_url` (→ `*.example.com`/empty), `git_user_name`/`git_user_email` (→ generic).
- `copilot_cli/services/infisical/core/config.py` → `_DEFAULT_BASE_URL` → empty (require env) or `https://app.infisical.com`; scrub the docstring + `api_client.py` probe comment.
- `.env.example` → replace the two `*.ineedacopilot.com` values with `*.example.com`.
- `.claude/skills/workflow-automation/SKILL.md` → replace the n8n default (twice).
- `docs/services/18-infisical.md` → placeholder the env-table value.
- `tests/test_services/test_infisical.py` L115 → match the templatized default.

---

## 5. Promotable — generic content to pull into base

- **knowledge:** the whole skill **framework + taxonomy** and the ~17 client-free skill
  families; all templates (profile, initiative/ADR/phase/retro, the empty product-dossier
  skeleton — derive a template file from the structure); the KMS methodology + consumption
  contract docs; the client-free prompt library; the design-system **engine** (component +
  token architecture, minus brand values/marketing templates).
- **cli:** the entire binary + plugin/adapter architecture and all generic service adapters
  (incl. `infisical` post-templatize) with their `docs/services/*` + `tests/*`; meta
  (`.env.example` post-strip, `.mcp.json.example`, `pyproject.toml`, `Makefile`,
  `scripts/e2e_health.py`).

---

## 6. What this changes about the mechanics

1. **Secrets first (§1).** Rotate the live keys, remove the key file, confirm the
   history-borne secrets are revoked — *before* any rename.
2. **Fresh-history base repos.** Seed each base by **copy**, then `git init` — never by
   filtering the mature repo's history. Aligns with `cli-copilot`'s own GATE A.
3. **Reconcile with cli-copilot's existing OSS-split plan.** `cli-copilot/docs/initiatives/`
   already has `000-open-core` + `001-framework-oss-split` (with a `BaseServiceSettings`
   boundary + a "zero-company-strings" CI gate). Phase 1 should **adopt/extend** that plan
   for cli, not reinvent it — and mirror the same CI gate for knowledge.
4. **`neither` is a real third bucket.** Certs, local DBs, build artifacts, and `.env` must
   be actively excluded from the seeding copy, not just left to `.gitignore`.

## 7. Open items / next actions

- [ ] **Owner:** rotate the six live credentials in `02-keys.md` and confirm the two
      history-borne secrets are revoked. *(Blocks everything.)*
- [ ] Decide base-seeding method (copy-then-init) and the CI "zero-company-strings" gate,
      reusing cli-copilot's `001-oss-split` design.
- [ ] Author the four scaffolding wizards (per the companion doc) as base capability.
- [ ] Then the rename-redirect sequence (knowledge first, cli second) + leak-scan.
