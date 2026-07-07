# The app↔CLI contract (WS-A — the prerequisite)

Control Tower is a face + supervisor: it **parses machine-readable CLI output; it never computes**. This document is the authoritative spec for the **`--json` + `flock` additions to the `copilot`/`cc` CLI** (which live in the `claude-copilot` repo). **This contract must be defined and frozen before app development begins** — the app cannot supervise a CLI it can't read machine-readably. It is workstream **WS-A** in the [PRD](../02-prd/prd.md) and gates every other workstream.

Full detail: [`../03-design/design-integration.md`](../03-design/design-integration.md) §1. Rationale: [`architecture.md`](architecture.md) §6.

> **Machine-readable source of truth:** the versioned JSON Schemas in [`schemas/`](schemas/) (one `*.schema.json` per verb, Draft 2020-12) are authoritative for the CI contract test; this prose and those schemas must stay in sync (**schemas win for machines**).

## Requirements

Every consumed verb grows a **versioned `--json`** mode. All schemas carry a top-level `schema_version`. Control Tower declares a `min_schema`/`max_schema` range and **gates both directions** — a CLI schema older than its floor is as fatal as one newer. **Missing security-relevant fields fail closed** (absent `destructive`/`signed`/`severity` ⇒ treated as destructive/unsigned/fail, never safe).

| Verb | Emits | Notes |
|---|---|---|
| `copilot doctor --json` | `{schema_version, host, score(0–100), status, offline, checkers:[{id,severity(pass\|warn\|fail),repair,destructive,…}], auth:[…]}` | Mirrors `cc memory check`; exit `0` clean / `1` any fail / `2` env error. `status` computed CLI-side. |
| `copilot update --json` | `{result, lock_before, lock_after, changed:[{dimension,layer,item,op(added\|updated\|pruned\|unchanged),from,to,signed,severity_trailer,shadowed_by}], held_for_approval:[…], blocked:[…]}` | `pruned` surfaces the reconciling-sync deletion; `severity_trailer` + `shadowed_by` drives the un-dismissable security banner. |
| `copilot resolve --explain --json` | per-item `{item,dimension,winning_layer,winning_sha,shadowed[],signer_of_introducing_commit,live_hash_matches}` | `live_hash_matches:false` ⇒ "MODIFIED", never stale "signed ✓". |
| `copilot deprovision <org> --json` | `{result, removed:{materialized,clones[]}, retained_dirty[], secrets_touched}` | `secrets_touched` MUST be `0` (no secret ever lived in a layer). |
| `copilot freshness --json` | `{latest_lock_sha, current_lock_sha, stale, checked_at}` | The **cheap poll target** (single SHA) — not full `update`. |
| `copilot publish --json` **(WS-A addition, 2026-07-07)** | `{schema_version, tier, result, conflict?, resolutions[], parked_ref?, escalated_to?, leak_scan}` | Author-side push of a writable org/dept tier. **CLI computes the merge**; the app only renders the chooser and passes back the choice. Conflict states: `auto-merged` / `needs-choice` / `parked-escalated`. See the subsection below. |

## `copilot publish --json` (WS-A addition — 2026-07-07)

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

## Concurrency (the double-write fix)

- **`flock` on `copilot.lock`** across `update` / `repair` / `deprovision`; fail-fast if held. A **global per-host mutex across all verbs** so `deprovision` drains pending syncs before wiping. *The CLI self-serializes — Control Tower is not the lock.* (Fixes red-team B-C1.)

## CLI-updater ownership

- **`COPILOT_MANAGED_BY=controltower`** disables `copilot self-update`, so Control Tower is the single owner of the vendored CLI (no two-updater fight). (Fixes B-C4.)

## Contract test (required)

A **CI contract test in the `copilot` repo** asserts every `--json` command matches the published schema on every release. This schema is the safety boundary: schema drift = silent security bypass (a misread `fail`→`pass` shows green over a red pipeline). See red-team B-H6 and integration §8.

## Acceptance

The schema is published, versioned, and the CI contract test is green. Concurrent `copilot` invocations serialize with no torn `.claude/` tree. Only then does app development (WS-B onward) begin.
