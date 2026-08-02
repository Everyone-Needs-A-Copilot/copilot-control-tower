# The app↔CLI contract (WS-A — the prerequisite)

Control Tower is a face + supervisor: it **parses machine-readable CLI output; it never computes**. This document is the authoritative spec for the **`--json` + `flock` additions to the `copilot`/`cc` CLI** (which live in the `claude-copilot` repo). **This contract must be defined and frozen before app development begins** — the app cannot supervise a CLI it can't read machine-readably. It is workstream **WS-A** in the [PRD](../02-prd/prd.md) and gates every other workstream.

> **Freeze status & source of truth (2026-07-22).** The authoritative WS-A contract is defined **upstream**, in the `claude-copilot` repo: [`05-control-tower.md`](/Volumes/Dev/Sites/COPILOT/claude-copilot/docs/40-initiatives/01-ecosystem-extensions/05-control-tower.md), [`06-control-tower-prd.md`](/Volumes/Dev/Sites/COPILOT/claude-copilot/docs/40-initiatives/01-ecosystem-extensions/06-control-tower-prd.md), and [`research/design-control-tower-integration.md`](/Volumes/Dev/Sites/COPILOT/claude-copilot/docs/40-initiatives/01-ecosystem-extensions/research/design-control-tower-integration.md). **The CLI now implements `auth`/`doctor`/`layers`/`freshness`/`update`/`projects`/`onboard` plus the project-centered `workspace` contract in `claude-copilot`'s `tools/cc` (wired into `cc/main.py`).** There is no standalone `repair` or `publish` verb, and none is scheduled: Git history remediation now lives inside `cc onboard`'s routing, and standalone `repair`/`publish` are **formally deferred** — see [`ADR-008`](/Volumes/Dev/Sites/COPILOT/copilot-control-tower/docs/40-initiatives/02-enac-self-onboarding/decisions/ADR-008-repair-and-publish-deferred.md) and the "Deferred verbs" section below. This prose and the [`schemas/`](schemas/) in this repo encode the contracts.

> **Fail-closed clarification (2026-07-21).** `cc doctor --json` may not emit
> `healthy` when `layers.manifest` is absent or invalid. It emits a failing
> `ecosystem-layer-manifest` checker instead. Control Tower continues to call
> one structured CLI and renders that verdict; it does not call both `cc` and
> CLI Copilot and merge their health in the app.

Full detail: [`../03-design/design-integration.md`](../03-design/design-integration.md) §1. Rationale: [`architecture.md`](architecture.md) §6.

> **Machine-readable source of truth:** the versioned JSON Schemas in [`schemas/`](schemas/) (one `*.schema.json` per verb, Draft 2020-12) are authoritative for the CI contract test; this prose and those schemas must stay in sync (**schemas win for machines**).

## Requirements

Every consumed verb grows a **versioned `--json`** mode. All schemas carry a top-level `schema_version`. Control Tower declares a `min_schema`/`max_schema` range and **gates both directions** — a CLI schema older than its floor is as fatal as one newer. **Missing security-relevant fields fail closed** (absent `destructive`/`signed`/`severity` ⇒ treated as destructive/unsigned/fail, never safe).

| Verb | Emits | Notes |
|---|---|---|
| `copilot auth [login\|grant\|status] --json` | `{schema_version, kind(device-code\|poll\|grant-device-code\|grant-poll\|status), …}` (see [`schemas/auth.schema.json`](schemas/auth.schema.json)) | GitHub device-flow sign-in and least-privilege SSH-key permission upgrade. `grant` requests only `write:public_key`, requires an existing `cc` sign-in, and commits the replacement token only after the returned identity matches and the scope is confirmed. `status` is offline-safe. OAuth tokens stay in the OS keychain and NEVER appear in this contract. |
| `copilot doctor --json` | `{schema_version, host, score(0–100), status, offline, checkers:[{id,severity(pass\|warn\|fail),repair,destructive,…}], auth:[{identity,scope,state(expired\|revoked),expires_at}]}` | Mirrors `cc memory check`; exit `0` clean / `1` any fail / `2` env error. `status` computed CLI-side — the authoritative ~10-state enum (`setup-needed \| it-config-incomplete \| healthy \| syncing \| update-available \| needs-attention \| signed-out \| offline \| waiting-for-network \| updating-app`) is defined in [`schemas/doctor.schema.json`](schemas/doctor.schema.json), reconciled from the upstream design's §2 state table. **Do not conflate `status` with per-checker `severity` (pass\|warn\|fail)** — they are different fields. |
| `copilot update --json` | `{result(applied\|up-to-date\|held\|blocked\|offline), lock_before, lock_after, changed:[{dimension,layer,item,op(added\|updated\|pruned\|unchanged),from,to,signed,severity_trailer,shadowed_by}], held_for_approval:[{dimension,from,to,reason}], blocked:[…]}` | `pruned` surfaces the reconciling-sync deletion; `severity_trailer` + `shadowed_by` drives the un-dismissable security banner. |
| `copilot resolve --explain --json` | per-item `{product,item,dimension,winning_layer,winning_sha,shadowed[],signer_of_introducing_commit,live_hash_matches}` | Resolution identity is `(product, dimension, item)`; ranks and shadows compete only inside one product. `live_hash_matches:false` ⇒ "MODIFIED", never stale "signed ✓". |
| `copilot deprovision <org> --json` | `{result(wiped\|partial\|noop), removed:{materialized(count),clones[]}, retained_dirty[], secrets_touched}` | `secrets_touched` MUST be `0` (no secret ever lived in a layer). `removed.materialized`'s exact count semantics remain open even upstream — to be defined at freeze. |
| `copilot freshness --json` | `{latest_lock_sha, current_lock_sha, stale, offline, checked_at}` | The **cheap poll target** (single SHA) — not full `update`. **CORRECTED 2026-07-07 (WS-A slice 3):** `latest_lock_sha`/`current_lock_sha`/`stale` are nullable and `offline` was added — the original non-nullable shape had no honest way to represent "could not check" (offline, or no local lock yet); see [`schemas/README.md`](schemas/README.md) and [`schemas/freshness.schema.json`](schemas/freshness.schema.json). |
| `copilot layers --json` **(proposed contract addition, D7.1, not yet in upstream WS-A scope)** | `{schema_version, layers:[{tier(org\|department), id, name, repo, entitled(bool), joined(bool), reason?}]}` | Entitlement discovery. Lists every department/org layer visible for the account context, whether the user is **entitled** (has GitHub repo access to it, per D3, the entitlement spine) and whether it is already **joined** (synced onto this machine). Entitlement is computed **CLI-side**; the app only renders the list. |
| `copilot layers join <id> --json` **(proposed contract addition, D7.1)** | `{result(joined\|already-joined\|not-entitled\|error), tier, id, synced_lock_sha}` | Join action. Takes the user's pick of an entitled, not-yet-joined layer from the app-rendered list and syncs it onto the machine (equivalent to what `update` materializes for an already-joined layer). `not-entitled` is a normal, renderable outcome, not a crash. |
| `cc onboard --scope personal [--components knowledge,cli,claude,codex] [--apply] --json` / `cc onboard --org <org\|auto> --products claude,codex [--repository-root <visible-path>] [--apply] --json` **(Phase 6 implemented, schema_version 2.0 — G-5, task 208)** | Repository report plus aggregate `{stages,layers_state,layers:[{id,product,role,rank,action,local_state,sync_state,remote_state,repository_name,local_path,…}],inventory,inventory_summary,completed_actions,resume?}` (see [`schemas/onboard.schema.json`](schemas/onboard.schema.json)) | Default plan mode is read-only. Aggregate Apply performs a complete preflight before mutation, includes handoff-declared departments with active membership, creates/downloads repositories into one visible root, creates Personal remotes only after explicit 404, preserves working trees, and writes a rollback copy before manifest migration/repair. Unfamiliar or conflicting state returns `review` and blocks Apply. Every `layers` row is now fully required (never the four-field `id`/`product`/`role`/`rank` skeleton alone); `layers_state` discriminates `reported` (topology computed, `layers` non-empty) from `not-computed` (the one exit before topology exists at all, `layers: []`) — see the versioning note below. |
| `cc workspace (--all\|--project <path>) --json` / `cc workspace configure --project <path> [--share-with-project] [--apply] --json` | `{schema_version,mode,result,workspaces:[{path,name,project_id,state,detail,declared_components,installed_components,recommended_components,personal_profile}],summary,actions?}` (see [`schemas/workspaces.schema.json`](schemas/workspaces.schema.json)) | Status is bounded and read-only. Configure repeats an all-product collision preflight, activates only missing component setup, and never treats the portable declaration as installation proof. Personal association stores only an opaque project id and product names outside the shared repo. |
| `cc workspace approve-root --path <folder> [--apply] --json` | `{schema_version,mode,result,root:{name,state,detail}}` (see [`schemas/workspace-root.schema.json`](schemas/workspace-root.schema.json)) | One-time User Setup approval for bounded discovery. Refuses symlinked/unavailable roots and returns only the display name to the app. |
| `cc connections --json` **(stage B, task 221)** | `{schema_version,result(ok\|copilot-unavailable\|org-config-unavailable),detail,org,store:{type,reachable,scope,detail},connections:[{id,name,description,tier,mode,requires_secret,store_scope,secret_state(ready\|needs-connect\|no-store),missing}]}` (see [`schemas/connections.schema.json`](schemas/connections.schema.json)) | Closes the "Your connections" empty-state gap (task 221 investigation, WP-388/389/390): shells `copilot --json layers` (cli-copilot foundation ≥v0.3.2, which now carries `requires_secret`/`store_scope` per service) and, for each service's `store`/`any`-hinted secret names, presence-checks them (never values) against the org's shared Infisical store — one `copilot infisical --json secret list` call per run, never per name. Read-only, no lock. `secret_state` is the only field the app filters connections on (READY TO USE vs. AVAILABLE TO CONNECT); `result` is a separate envelope-level diagnostic for two distinct fail-closed cases (`copilot` unresolvable vs. the inherited org config not yet materialized) — `org-config-unavailable` still returns the full roster with every store-dependent row honestly marked `no-store`, rather than an empty list. |

## Deferred verbs

No CLI verb inventory above may list `repair` or `publish` — neither exists in `claude-copilot/tools/cc/src/cc/commands/`. Their scope is ratified in [`ADR-008`](/Volumes/Dev/Sites/COPILOT/copilot-control-tower/docs/40-initiatives/02-enac-self-onboarding/decisions/ADR-008-repair-and-publish-deferred.md):

- **`repair`.** History remediation now lives inside `cc onboard`'s own routing rather than a standalone verb: its closed 8-state classifier (see the `cc onboard --json` row above, and [`ADR-006`](/Volumes/Dev/Sites/COPILOT/copilot-control-tower/docs/40-initiatives/02-enac-self-onboarding/decisions/ADR-006-ecosystem-setup-preflighted-saga.md)) routes fast-forwardable rows to an in-onboard fast-forward repair and every review-state (dirty, ahead-only, divergent-identical, divergent-different, wrong-origin, unreadable) to the owner. A first-class `cc repair` verb is deferred; none is scheduled.
- **`publish`.** The author-side push of a writable org/department tier is formally deferred. The subsection below records the design intent ratified 2026-07-07 for if/when it is built; it is **not** a claim that the verb currently exists.

### `copilot publish --json` — deferred design (WS-A addition — 2026-07-07)

Added when the [writable-inheritance & publish-path design](inheritance-and-publish.md) was ratified (2026-07-07, owner). `publish` is the **author-side push** of a writable org/department tier to its remote — the one governed path on which cross-author conflicts can arise. Consumers never call it (they only `update`/pull). **All merge/rebase/conflict computation is CLI-side; Control Tower only RENDERS the plain-language chooser and passes the human's pick back as `--resolve <choice>`** (invariant #1 — parse, never compute; no merge logic in the app).

**Purpose.** Fetch the tier remote, rebase the author's local tier commits onto the new tip, auto-merge non-overlapping hunks, and — on a true overlap — surface a content-level (never Git-marker) choice or park-and-escalate a sensitive/declined change. Tier-scoped leak-scan runs fail-closed before any push (SOUL *The Leak*).

**Result / conflict states** (`result`, and `conflict.state` when `conflict` is present):

| State | Meaning | `--json` shape |
|---|---|---|
| `auto-merged` | Rebased + non-overlapping hunks merged silently; push completed. | `{result:"auto-merged", tier, pushed_sha}` |
| `needs-choice` | True overlap on the same lines. CLI emits **rendered content versions** (never Git markers) and the non-destructive options. App renders the chooser; the pick returns via `copilot publish --resolve <choice>`, which the CLI applies and pushes. | `{result:"needs-choice", conflict:{tier, file, section, yours:{author,ts,rendered}, theirs:{author,ts,rendered}, base:{ts,rendered}}, resolutions:["keep-yours","keep-theirs","keep-both","escalate"]}` |
| `parked-escalated` | Sensitive path/class, or author declined to choose. The change is parked on a durable held ref (**never lost**) and escalated in plain language to a competent author via the §9 Bob-agency routing. | `{result:"parked-escalated", parked_ref, escalated_to, reason}` |

`keep-both` is the always-available **lossless floor** (both versions land side-by-side for content-level reconciliation, never a Git operation); `escalate` is the always-available exit so no non-technical author is cornered by a Git decision.

**Exit codes.** `0` = published (`auto-merged`, or `needs-choice`/`parked-escalated` cleanly reported for the app to render — a surfaced conflict is a normal outcome, not an error); `1` = publish refused (leak-scan tripped, non-fast-forward that could not be auto-handled, or a `--resolve` that no longer applies); `2` = env/credential error (e.g. the author write credential is absent — see the carried-forward seam in [`inheritance-and-publish.md`](inheritance-and-publish.md) §7).

**Fail-closed fields.** `leak_scan` and `tier` are **security-relevant**: a missing or malformed `leak_scan`/`tier` ⇒ **refuse to publish**, matching this contract's global fail-closed rule (a missing security field is never treated as safe). A CI contract test asserts this schema on every release, exactly like every other verb.

## `copilot layers [join] --json` (proposed contract addition, D7.1)

Added to close CSE open question 2 / decision D7.1 ([`cse-alignment-decisions.md`](../10-reference/cse-alignment-decisions.md)): the contract has status/sync verbs (`doctor`/`update`/`resolve`/…) but, until now, no way for a user to **discover** which department/org layers they are entitled to, or to **join** one. This is a **proposed** addition, the same not-yet-upstream status as `copilot publish --json` above, to be folded into upstream WS-A scope at freeze. The prior design *descoped* department discovery entirely; this reverses that descope.

**Purpose.** `copilot layers --json` enumerates every department/org layer the current account context could plausibly join, and for each reports whether the user is **entitled** (D3: entitlement is GitHub repo access to that layer's repo) and whether it is already **joined** (synced onto this machine). `copilot layers join <id> --json` performs the join: given an entitled, not-yet-joined layer id, it syncs that layer onto the machine, the same materialization `update` performs for an already-joined layer, and reports the result.

**Parse, never compute.** Entitlement is a fact the CLI computes by checking GitHub repo access per candidate layer (D3, the entitlement spine); Control Tower never evaluates repo permissions itself. The app's only job is to render the returned list (entitled vs. not, joined vs. not) and pass the user's selection back as the `join` argument, the identical pattern to the `publish --resolve` chooser above (invariant #1: parse, never compute; no entitlement logic in the app).

**Exit codes.** `0` = list/join succeeded (including a `not-entitled` result for `join`, a normal, renderable outcome, not an error); `1` = join refused (e.g. unknown layer id, or entitlement revoked between list and join); `2` = env/credential error (e.g. no GitHub identity resolvable at all).

## `cc onboard --json` (Phase 6)

`cc onboard` is the authoritative aggregate onboarding verb. It coordinates the
content ecosystem and the separately installed CLI/service component; Control
Tower invokes one verb and renders its result. The app never calls multiple CLIs
and synthesizes a health verdict.

**Versioning (2026-07-31, G-5, task 208 — breaking, `schema_version` 1.0 → 2.0).** The prior contract left every `ecosystemLayer` topology field optional and `layers` unbounded, so a raw four-field `{id,product,role,rank}` row (no topology evidence at all) validated identically to a fully-computed row, and an omitted-topology exit could emit `layers: []` indistinguishably from a `reported` empty array. Both ambiguities are now closed:

- `ecosystemLayer.required` now also includes `action`, `local_state`, `sync_state`, `remote_state`, `repository_name`, and `local_path` (on top of the prior `id`/`product`/`role`/`rank`) — the skeletal look-alike row no longer validates.
- A new required `layers_state` enum (`reported` | `not-computed`) discriminates the two legal `layers` shapes: `reported` requires `layers` to carry at least one fully-required row (`minItems: 1`); `not-computed` requires `layers` to be exactly `[]`. An empty array is never valid on its own — it must be paired with the explicit `not-computed` state, which only the one exit path that returns before the topology report is ever computed (the personal-packages gate, checked before the layer manifest itself is built) may emit.
- `completed_actions` (the task 207/G-4 mutation ledger) and `resume` (only present when `result` is `blocked`) are now formalized as part of the canonical schema rather than carried only in the CLI's own test fixture.

This is a breaking change for any consumer that read `layers` optimistically (treating a present-but-empty array, or a bare `id`/`product`/`role`/`rank` row, as meaningful topology evidence) — hence the `schema_version` bump. See [`schemas/onboard.schema.json`](schemas/onboard.schema.json) for the full `$defs.ecosystemReport`/`$defs.ecosystemLayer` shape.

**Versioning (2026-08-01, G-9, task 215 blocker fix — compatible, `schema_version` 2.0 minor addition, cc 2.1.1).** An optional `materialize` field is added to `ecosystemReport`, present only once a real apply has actually run the materialize step. Its shape (`$defs.materializeSummary`, reusing `held_items`/`blocked_items` from `$defs.materializeHeldItem`/`$defs.materializeBlockedItem`) reuses `cc update --json`'s own `held_for_approval`/`blocked` vocabulary verbatim — `held`/`blocked` items are never fatal to the transaction's manifest write or overall `result` on their own; they are surfaced here honestly instead of being conflated with failure. This is purely additive: no existing field, enum value, or `required` list changed, so it does not move the `schema_version` major/minor number and every app already reading `schema_version` 2.0 keeps working unchanged whether or not it branches on `materialize`. The canonical schema here was re-synced against `claude-copilot/tools/cc/tests/fixtures/schemas/onboard.schema.json` (the source of truth this shape shipped from) to close a drift where the fixture had gained this shape ahead of the copy in this repo.

The transaction has two explicit authority stages:

1. **Admin/shared:** verify the public foundation, create or verify organization
   repositories and policy, and write a non-secret user handoff.
2. **User/personal:** after personal GitHub authentication, create or select the
   individual's private repositories, establish on-device credentials, resolve
   the effective stack, materialize it, and run doctor evidence.

The personal repository gate deliberately separates `plan` from `--apply`,
resolves the owner from `gh api user`, and treats only an explicit HTTP 404 as
absence. The aggregate transaction now coordinates that gate with device
identity, manifest adoption, store provisioning, product-aware synchronization,
Codex registration, and doctor evidence. The `--products` option selects
assistant runtimes (`claude`, `codex`); it does not narrow the ecosystem roster.
Knowledge and CLI are always included alongside the selected runtimes.

For a person entitled to Accounting, each of Knowledge, CLI, Claude, and Codex
must report exactly `personal (10) -> department (20) -> organization (30) ->
foundation (40)`. Ranks remain internal precedence data and are never
user-facing. Every repository has a visible checkout under
`paths.repositories_root`; Personal is never present only under
`~/.copilot/mirrors`. Knowledge and CLI remain separate products and are never
flattened into the Claude or Codex materialization roots. Claude and Codex keep their allowlisted target
maps (for example Codex user skills in `~/.agents/skills`, native personal
agents in `~/.codex/agents`, and global instructions in `~/.codex/AGENTS.md`).
Resolution keys are `(product, dimension, item)`; ranks compete only inside one
product, so same-named capabilities coexist rather than shadow across products.

After all four product stacks synchronize, `doctor` reports healthy, and the
candidate produces a non-empty effective resolution, setup commits the manifest
pointer, visible repository root, and ordered Knowledge checkout paths in one
atomic machine-config write. Superseded hidden Personal checkouts are then
moved intact out of the active mirror tree. `doctor.checkers[].layer_role` is the canonical, closed
role (`foundation`, `organization`, `department`, or `personal`) that UI clients
render. `checkers[].layer` remains an opaque manifest identifier and must not be
parsed for role semantics.

Production materialization remains fail-closed until executable remote content
passes the ratified signature/policy check. Output may include repository owner,
role, rank, commit/tag, and health status, but never personal file contents,
tokens, private keys, keychain values, or secret-store credentials.

**Idempotency and recovery.** Re-running `cc onboard` verifies and repairs only
missing or stale managed artifacts. It preserves every dirty visible checkout,
permits only a clean fast-forward,
reports held work, and provides a recovery action for every blocked stage. A
partially completed Admin stage can be resumed by User Setup without repeating
already-passing mutations.

**Adoption contract.** `inventory[].action` is one of `reuse`, `create`,
`migrate`, `repair`, or `review`. A supported `component:` predecessor can be
translated to `product:` and merged. A recognized eight-layer predecessor with
managed CLI, Claude, and Codex stacks may be repaired additively to the complete
twelve- or sixteen-layer roster. Before `migrate` or `repair`, the original manifest bytes
are stored in a content-addressed local rollback directory; locally authored
Knowledge and CLI repositories are never modified. `review` always stops the
transaction before personal repository, SSH, store, or manifest mutation.
Control Tower renders these actions and never computes compatibility itself.

## Concurrency (the double-write fix)

- **`flock` on `copilot.lock`** across `update` / `onboard` / `deprovision`; fail-fast if held. A **global per-host mutex across all verbs** so `deprovision` drains pending syncs before wiping. *The CLI self-serializes — Control Tower is not the lock.* (Fixes red-team B-C1.) There is no standalone `repair` verb to serialize; `onboard`'s in-transaction history repair (row `action: repair`, [`ADR-008`](/Volumes/Dev/Sites/COPILOT/copilot-control-tower/docs/40-initiatives/02-enac-self-onboarding/decisions/ADR-008-repair-and-publish-deferred.md)) is covered by `onboard`'s own lock.

## CLI-updater ownership

- **`COPILOT_MANAGED_BY=controltower`** disables `copilot self-update`, so Control Tower is the single owner of the vendored CLI (no two-updater fight). (Fixes B-C4.)

## Contract test (required)

A **CI contract test in the `copilot` repo** asserts every `--json` command matches the published schema on every release. This schema is the safety boundary: schema drift = silent security bypass (a misread `fail`→`pass` shows green over a red pipeline). See red-team B-H6 and integration §8.

## Acceptance

The schema is published, versioned, and the CI contract test is green. Concurrent `copilot` invocations serialize with no torn `.claude/` tree. Only then does app development (WS-B onward) begin.
