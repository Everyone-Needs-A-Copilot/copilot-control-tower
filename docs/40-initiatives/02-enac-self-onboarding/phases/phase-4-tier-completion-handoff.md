# Phase 4 — Lock the tier in fully (hand-off)

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Depends on: [`phase-3-tier-inheritance-and-secrets.md`](phase-3-tier-inheritance-and-secrets.md)
> (the live tier stack + credential ladder + secret migration — shipped).
> **Taking this over in a new conversation? Read this doc, then Phase 3, then
> the session memory `cli-tier-inheritance-live.md`. Everything below is
> additive and reversible; the tier is already live and working today.**

## Status — code backlog COMPLETE (2026-07-20)

All five code items below shipped, each independently QA-verified, committed
(**not yet pushed** — see the push decision with the owner). Full CLI suite
**979 passed / 10 skipped, zero regressions**.

| Item | What shipped | Commits |
|---|---|---|
| #4+#5 | dead-secret cleanup (live `.env`) + keychain hint fix | `cli-copilot-internal 715cde0` |
| #1 | config inheritance (`TierConfigSource` + store fold); **live mirror migrated + 3-level verified** (isolated test, real 9-secret fetch from inherited config, real-binary smoke) | `cli-copilot 69c3759`, `cli-copilot-internal 8bbe108` |
| #2a | `copilot update` core sync + never-destroy gate (dirty / non-git / status-exception / ahead>0 unpushed-commits, all fail-safe) | `cli-copilot b8706cd`, `d2a062b` |
| #2b | semver range→tag resolver (prereleases excluded), versioned `--json` + `update.schema.json`, presence-only store-readiness report | `cli-copilot c68c281` |
| #3 | per-`requires_secret` `from: store\|keychain` hint (back-compat, fail-closed, invariant #4 verified) | `cli-copilot 8842f19`, `cli-copilot-internal 10e028c` |

Remaining = **owner-only actions** (see "Owner actions" below) + the multi-repo
**push** of the eight commits above.

## Where things stand (start here)

ENAC's Mac runs `copilot` as **public foundation + private org overlay**, and
every secret resolves through the credential ladder: **Infisical** for the app
secrets, **keychain** for the two Infisical bootstrap creds + the Discord bridge
token. This is live, verified, and pushed (Phase 3 lists the commits).

What "**fully** locked in" still needs is the difference between *"works on the
one machine it was hand-wired on"* and *"a second machine / department / person
runs one command and inherits the same tier."* That gap is this phase.

## Remaining work, highest-leverage first

### 1. Config inheritance — wire the overlay `config:` merge  *(the main gap)*
Today the store config (`INFISICAL_WORKSPACE_ID` / `_ENVIRONMENT` / `_SECRET_PATH`,
plus `INFISICAL_BASE_URL`) lives in the **local, gitignored `.env`**. It is
non-secret and *should* inherit down-tier — otherwise a dept/personal tier or a
second machine has no idea where the org's Infisical store is. The overlay
`cli.overlay.yml` already parses a `config:` block (`OverlayAdopt.config`) but it
is **not merged** into the composed `Settings`, and `managed_store` reads store
config from the layer `.env`, not that block.
- **Do:** fold each tier's `config:` into the layered settings source chain (a
  `config` source ahead of the tier `.env`), and have `managed_store._find_store_layer`
  read from the composed config, not just `.env`. Then move the store config out
  of `.env` into the org tier's `cli.overlay.yml config:` so it inherits.
- **Verify:** a scratch personal/dept tier with no store config in its own `.env`
  still resolves org secrets (config inherited from the org layer).

### 2. `copilot update` — build the mirror-sync verb  *(onboarding blocker)*
The manifest (`~/.config/copilot/copilot.layers.yml`) and mirrors
(`~/.copilot/mirrors/cli/<id>/`) were placed **by hand**. A real onboarding needs
`copilot update` to clone/pull each layer's repo into its mirror and refresh the
overlay + non-secret config. This is the initiative's **V-4** (one `copilot
update` propagates a change to every enrolled project) and the owner's #1 pain
(per-project fan-out). See [`phase-2-standup-and-rollout.md`](phase-2-standup-and-rollout.md).
- **Do:** implement the sync (clone by manifest `source.repo`/`ref`/`auth`,
  materialize `cli.overlay.yml` + `.env` into the mirror, honour never-destroy).
- **Verify:** V-3 (dirty-tree hold, zero writes) and V-4 (fan-out propagates).

### 3. Per-secret routing — let keychain secrets skip the store fetch  *(perf/robustness)*
Rung 1 fires on **every** base `Settings` construction (uspto is a base
`requires_secret` that lives in the store), so every command does one
`list_secrets`. Keychain-backed secrets (the bridge, bootstrap) still pay a
store round-trip on a miss (~6 s if Infisical is down). A per-`requires_secret`
`from: store|keychain` hint in the overlay would let the ladder skip rungs it
knows won't have a given name. Optional but removes the last latency/availability
wart.

### 4. Dead-secret cleanup in `.env`  *(hygiene)*
`CONVERSATIONS_API_KEY` and `CONVERSATIONS_AGENT_API_SECRET_KEY` are plaintext in
`-internal/.env` but **not read by any CLI field** (backend secrets, already in
the `convoco` Infisical project). Confirm no hook/script reads them, then delete
the lines. (`conversations_api_token` is an optional OAuth-override and correctly
stays empty; the live conversations auth — the X-Agent-Auth secret — is already
in Infisical as `CONVERSATIONS_AGENT_AUTH_SECRET`.)

### 5. Cosmetic — stale hint
`copilot_overlay_internal/.../services/discord/client.py:89` still says "Set
DISCORD_BOT_TOKEN in your .env"; it now lives in the keychain. Update the hint.

## Owner actions (not code)

- **Do one real Discord handoff** to confirm the bridge end-to-end. The code path
  is verified (keychain-resolved, command loads) but a live handoff wasn't
  triggered.
- **Broader-arc, gated decisions** (from Phase 2 + memory): the one-way **public
  flip** of `knowledge-copilot` + `cli-copilot` (squash + tag `v0.1.0`), the
  hardcoded **`^5.13.0` foundation-pin** fix before the admin live-run, and the
  admin-dogfood standup itself.

## Key files, commands, rollback

- **Ladder / store:** `cli-copilot/copilot_cli/config/{secrets_ladder,managed_store,layers,settings}.py`.
- **Overlay:** `cli-copilot-internal/cli.overlay.yml` (+ mirror copy at
  `~/.copilot/mirrors/cli/org-internal/cli.overlay.yml` — it is a **copy, not a
  symlink**, so edits must be `/bin/cp`'d over) and
  `copilot_overlay_internal/.../config/settings.py`.
- **Secret migration tool** (this session, reusable): the pattern in
  `secret_migrate.py` — `keychain|store|delete-keychain|delete-store NAME
  [--src env|keychain|store]`. Reads values in-process, never prints them.
- **Rollback (whole tier):** `git -C cli-copilot-internal checkout -- copilot_cli`
  → `pip install -e cli-copilot-internal` → `pip uninstall copilot-overlay-internal`
  → `rm ~/.config/copilot/copilot.layers.yml ~/.copilot/mirrors/cli/*`.
- **Per-secret rollback:** re-add to `.env` from keychain/store, or move
  store↔keychain with the tool above.

## Pointers

- Session memory: `cli-tier-inheritance-live.md` (full wiring + every gotcha).
- Invariants: repo `CLAUDE.md` (#1 parse-not-compute, #4 no-weaken, #6 secrets).
- Contract: `docs/01-architecture/{cli-contract,inheritance-and-publish}.md`,
  `docs/05-security/credentials-and-boundary.md` (the ladder's normative spec).
