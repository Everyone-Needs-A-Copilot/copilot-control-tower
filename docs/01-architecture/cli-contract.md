# The app↔CLI contract (WS-A — the prerequisite)

Control Tower is a face + supervisor: it **parses machine-readable CLI output; it never computes**. This document is the authoritative spec for the **`--json` + `flock` additions to the `copilot`/`cc` CLI** (which live in the `claude-copilot` repo). **This contract must be defined and frozen before app development begins** — the app cannot supervise a CLI it can't read machine-readably. It is workstream **WS-A** in the [PRD](../02-prd/prd.md) and gates every other workstream.

Full detail: [`../03-design/design-integration.md`](../03-design/design-integration.md) §1. Rationale: [`architecture.md`](architecture.md) §6.

## Requirements

Every consumed verb grows a **versioned `--json`** mode. All schemas carry a top-level `schema_version`. Control Tower declares a `min_schema`/`max_schema` range and **gates both directions** — a CLI schema older than its floor is as fatal as one newer. **Missing security-relevant fields fail closed** (absent `destructive`/`signed`/`severity` ⇒ treated as destructive/unsigned/fail, never safe).

| Verb | Emits | Notes |
|---|---|---|
| `copilot doctor --json` | `{schema_version, host, score(0–100), status, offline, checkers:[{id,severity(pass\|warn\|fail),repair,destructive,…}], auth:[…]}` | Mirrors `cc memory check`; exit `0` clean / `1` any fail / `2` env error. `status` computed CLI-side. |
| `copilot update --json` | `{result, lock_before, lock_after, changed:[{dimension,layer,item,op(added\|updated\|pruned\|unchanged),from,to,signed,severity_trailer,shadowed_by}], held_for_approval:[…], blocked:[…]}` | `pruned` surfaces the reconciling-sync deletion; `severity_trailer` + `shadowed_by` drives the un-dismissable security banner. |
| `copilot resolve --explain --json` | per-item `{item,dimension,winning_layer,winning_sha,shadowed[],signer_of_introducing_commit,live_hash_matches}` | `live_hash_matches:false` ⇒ "MODIFIED", never stale "signed ✓". |
| `copilot deprovision <org> --json` | `{result, removed:{materialized,clones[]}, retained_dirty[], secrets_touched}` | `secrets_touched` MUST be `0` (no secret ever lived in a layer). |
| `copilot freshness --json` | `{latest_lock_sha, current_lock_sha, stale, checked_at}` | The **cheap poll target** (single SHA) — not full `update`. |

## Concurrency (the double-write fix)

- **`flock` on `copilot.lock`** across `update` / `repair` / `deprovision`; fail-fast if held. A **global per-host mutex across all verbs** so `deprovision` drains pending syncs before wiping. *The CLI self-serializes — Control Tower is not the lock.* (Fixes red-team B-C1.)

## CLI-updater ownership

- **`COPILOT_MANAGED_BY=controltower`** disables `copilot self-update`, so Control Tower is the single owner of the vendored CLI (no two-updater fight). (Fixes B-C4.)

## Contract test (required)

A **CI contract test in the `copilot` repo** asserts every `--json` command matches the published schema on every release. This schema is the safety boundary: schema drift = silent security bypass (a misread `fail`→`pass` shows green over a red pipeline). See red-team B-H6 and integration §8.

## Acceptance

The schema is published, versioned, and the CI contract test is green. Concurrent `copilot` invocations serialize with no torn `.claude/` tree. Only then does app development (WS-B onward) begin.
