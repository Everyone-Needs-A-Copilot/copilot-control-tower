# Phase 3 — CLI tier-inheritance + the credential ladder (shipped)

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Depends on: [`phase-1-public-base-extraction.md`](phase-1-public-base-extraction.md)
> (the `cli-copilot` / `-internal` split — done and pushed).
> Status: **Shipped and verified live on ENAC's machine.** This is the record of
> what was built; the remaining work to *fully* lock the tier in is
> [`phase-4-tier-completion-handoff.md`](phase-4-tier-completion-handoff.md).

This phase turned the ratified naming model into a **working, live tier
stack** for the `cli` component, and then made secrets flow through it the way
invariant #6 requires. It goes beyond the original Phase 1/2 plan: those framed
the *split*; this delivered the *runtime* — layered config, a service overlay
loader, and a fail-closed credential ladder — and migrated ENAC's real secrets
onto it.

## What now runs on ENAC's Mac

The live `copilot` CLI is **base foundation + org overlay**, composed by the
same `copilot.layers.yml` manifest + nearest-wins resolver the content copilots
use:

- **Base** `copilot-cli` (public foundation) — the 12 generic services + the
  loader (`copilot_cli/config/{layers,settings,secrets_ladder,managed_store}.py`,
  `copilot_cli/services/_loader.py`).
- **Overlay** `copilot-overlay-internal` (private `-internal`) — the 8 org
  services (discord, crm→nocodb, brevo, n8n, coolify, insights, project, conv).
- **Manifest** at `~/.config/copilot/copilot.layers.yml`; org mirror at
  `~/.copilot/mirrors/cli/org-internal/`. `copilot --json layers` →
  `org-internal` (rank 30) → `foundation` (rank 40), 22 top-level commands.

## The three mechanisms built

1. **Layered config + service composition.** `resolve_cli_layer_chain()` reads
   the manifest; `settings.py` folds each tier's `.env` into a precedence chain
   (personal → … → foundation); `_loader.py` composes each tier's
   `cli.overlay.yml` (`adopt` / `provides` / `override`). Gated behind manifest
   presence, so an untiered machine is byte-for-byte the old behaviour (a parity
   fitness test locks this).

2. **The fail-closed credential ladder** (`secrets_ladder.py`). Resolves a
   declared `requires_secret: <NAME>` in order: **(1) managed store (Infisical)**
   → **(2) OS keychain** → (3) device flow *(stub)* → (4) one-time secure paste
   *(TTY)*. A miss at every rung raises — never a silent empty value.
   - **Rung 1** (`managed_store.py`) reuses the base `infisical` service's own
     `InfisicalClient`. **Dormant until a tier declares `INFISICAL_WORKSPACE_ID`**
     (no network otherwise). Bootstrap-paradox safe (Infisical's own creds come
     from keychain, never from itself), recursion-guarded, fail-through on any
     miss, one bulk `list_secrets` per process, **on-disk access-token cache**
     (`~/.cache/copilot/infisical`, 0600, JWT-TTL) so commands don't re-auth —
     which had caused a real rate-limit fail-closed mid-rollout.

3. **Overlay ladder wiring + `populate_by_name`.** The org services' own
   `Settings` gained the same `SecretRefSource` path, so org-tier fields resolve
   through the ladder. Fixed a real bug: `SecretRefSource` emits by field name
   but pydantic matches aliased fields by `validation_alias`, so an aliased
   secret silently resolved to empty until `populate_by_name=True`.

## Secret layout — "everything in Infisical, only the necessary in keychain"

The owner's ratified end state, live and verified:

| Location | Holds |
|---|---|
| **OS keychain** (`copilot-cli`) | `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET` (bootstrap — can't live in the store they unlock), **`DISCORD_BOT_TOKEN`** (bridge resilience — resolves even when Infisical is down) |
| **Infisical** `copilot-ecosystem` / `prod` / `/shared` | `USPTO_CLI_API_KEY` (base), `N8N_API_KEY`, `NOCODB_API_KEY`, `BREVO_API_KEY`, `INSIGHTS_API_KEY`, `PROJECT_COPILOT_API_KEY`, `CONVERSATIONS_AGENT_AUTH_SECRET` |
| **`.env`** | non-secret config only (base URLs, IDs, `INFISICAL_WORKSPACE_ID`/`_ENVIRONMENT`/`_SECRET_PATH`) |

**Why keychain at all** (the owner's question, answered): the *only* thing
forced into keychain is the pair of credentials that authenticate to Infisical —
they cannot live in the store they unlock. Everything else in keychain is a
deliberate resilience choice (the Discord bridge must survive an Infisical
outage). All other secrets live in Infisical.

## Verification

- Foundation suite **887 passed** (after fixing a local manifest-leak in the
  test discovery — clean CI was always green); overlay **15**; config+service
  **92**; parity/ladder/managed-store **33**.
- Live: all 7 store-backed secrets + the keychain bridge token resolve, base
  `uspto health` healthy, infisical service auth → `ecosystem-admin` via the
  keychain fallback, **0 plaintext migrated secrets in `.env`**, **0
  fail-closed**. Store adds ~0.1–0.15 s/command (one cached fetch/process).

## Commits

- Foundation `cli-copilot`: `0d7cda5` (loader) · `2f80cc2` (rung 1) ·
  `7994403` (token cache + infisical keychain fallback) · `4899f92` (test
  manifest isolation).
- Org `cli-copilot-internal`: cutover `…a5dc7a7` · `4d44d3a` (uspto→keychain) ·
  `0453e49` (overlay ladder + n8n canary) · `58b4c65` (everything→Infisical) ·
  `7468264` (bridge→keychain + conversations reconciled).

## Known tradeoffs (carried into Phase 4)

- The store rung fires on **every** base `Settings` construction (uspto is a
  base `requires_secret`), so every command does one `list_secrets`. Cached, but
  a per-secret routing hint would let keychain-backed secrets skip it.
- The rung reads **one** project/env/path, so secrets in another Infisical
  project (e.g. `convoco`) aren't reachable without extending it.
- Store config (`INFISICAL_WORKSPACE_ID`/env/path) lives in the **local**
  gitignored `.env` — it does **not** yet inherit down-tier. This is the main
  gap keeping tier-inheritance from being *complete* for config.
