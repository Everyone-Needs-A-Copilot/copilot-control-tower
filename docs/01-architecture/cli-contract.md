# The app↔CLI contract (WS-A — the prerequisite)

Control Tower is a face + supervisor: it **parses machine-readable CLI output; it never computes**. This document is the authoritative spec for the **`--json` + `flock` additions to the `copilot`/`cc` CLI** (which live in the `claude-copilot` repo). **This contract must be defined and frozen before app development begins** — the app cannot supervise a CLI it can't read machine-readably. It is workstream **WS-A** in the [PRD](../02-prd/prd.md) and gates every other workstream.

> **Freeze status & source of truth (2026-07-07).** The authoritative WS-A contract is defined **upstream**, in the `claude-copilot` repo: [`05-control-tower.md`](/Volumes/Dev/Sites/COPILOT/claude-copilot/docs/40-initiatives/01-ecosystem-extensions/05-control-tower.md), [`06-control-tower-prd.md`](/Volumes/Dev/Sites/COPILOT/claude-copilot/docs/40-initiatives/01-ecosystem-extensions/06-control-tower-prd.md), and [`research/design-control-tower-integration.md`](/Volumes/Dev/Sites/COPILOT/claude-copilot/docs/40-initiatives/01-ecosystem-extensions/research/design-control-tower-integration.md). **The CLI does not yet implement any of these verbs — WS-A is unstarted.** This prose and the [`schemas/`](schemas/) in this repo *encode the design* so app development can proceed against a frozen shape; they are not evidence the CLI exists yet, and they **must be reconciled with the real CLI** once WS-A is actually built. Three known gaps at freeze time: `publish` (§ below) is a control-tower-originated addition that must still be folded into the upstream PRD; `layers`/`layers join` (§ below, D7.1) is a second control-tower-originated proposal, also not yet in upstream scope; `flock`/`copilot.lock` serialization is a design claim, not yet implemented anywhere.

Full detail: [`../03-design/design-integration.md`](../03-design/design-integration.md) §1. Rationale: [`architecture.md`](architecture.md) §6.

> **Machine-readable source of truth:** the versioned JSON Schemas in [`schemas/`](schemas/) (one `*.schema.json` per verb, Draft 2020-12) are authoritative for the CI contract test; this prose and those schemas must stay in sync (**schemas win for machines**).

## Requirements

Every consumed verb grows a **versioned `--json`** mode. All schemas carry a top-level `schema_version`. Control Tower declares a `min_schema`/`max_schema` range and **gates both directions** — a CLI schema older than its floor is as fatal as one newer. **Missing security-relevant fields fail closed** (absent `destructive`/`signed`/`severity` ⇒ treated as destructive/unsigned/fail, never safe).

| Verb | Emits | Notes |
|---|---|---|
| `copilot doctor --json` | `{schema_version, host, score(0–100), status, offline, checkers:[{id,severity(pass\|warn\|fail),repair,destructive,…}], auth:[{identity,scope,state(expired\|revoked),expires_at}]}` | Mirrors `cc memory check`; exit `0` clean / `1` any fail / `2` env error. `status` computed CLI-side — the authoritative ~10-state enum (`setup-needed \| it-config-incomplete \| healthy \| syncing \| update-available \| needs-attention \| signed-out \| offline \| waiting-for-network \| updating-app`) is defined in [`schemas/doctor.schema.json`](schemas/doctor.schema.json), reconciled from the upstream design's §2 state table. **Do not conflate `status` with per-checker `severity` (pass\|warn\|fail)** — they are different fields. |
| `copilot update --json` | `{result(applied\|up-to-date\|held\|blocked\|offline), lock_before, lock_after, changed:[{dimension,layer,item,op(added\|updated\|pruned\|unchanged),from,to,signed,severity_trailer,shadowed_by}], held_for_approval:[{dimension,from,to,reason}], blocked:[…]}` | `pruned` surfaces the reconciling-sync deletion; `severity_trailer` + `shadowed_by` drives the un-dismissable security banner. |
| `copilot resolve --explain --json` | per-item `{item,dimension,winning_layer,winning_sha,shadowed[],signer_of_introducing_commit,live_hash_matches}` | `live_hash_matches:false` ⇒ "MODIFIED", never stale "signed ✓". |
| `copilot deprovision <org> --json` | `{result(wiped\|partial\|noop), removed:{materialized(count),clones[]}, retained_dirty[], secrets_touched}` | `secrets_touched` MUST be `0` (no secret ever lived in a layer). `removed.materialized`'s exact count semantics remain open even upstream — to be defined at freeze. |
| `copilot freshness --json` | `{latest_lock_sha, current_lock_sha, stale, offline, checked_at}` | The **cheap poll target** (single SHA) — not full `update`. **CORRECTED 2026-07-07 (WS-A slice 3):** `latest_lock_sha`/`current_lock_sha`/`stale` are nullable and `offline` was added — the original non-nullable shape had no honest way to represent "could not check" (offline, or no local lock yet); see [`schemas/README.md`](schemas/README.md) and [`schemas/freshness.schema.json`](schemas/freshness.schema.json). |
| `copilot publish --json` **(control-tower-originated proposal, not yet in upstream WS-A scope — must be added upstream at freeze)** | `{schema_version, tier, result, conflict?, resolutions[], parked_ref?, escalated_to?, leak_scan}` | Author-side push of a writable org/dept tier. **CLI computes the merge**; the app only renders the chooser and passes back the choice. Conflict states: `auto-merged` / `needs-choice` / `parked-escalated`. See the subsection below. |
| `copilot layers --json` **(proposed contract addition, D7.1, not yet in upstream WS-A scope)** | `{schema_version, layers:[{tier(org\|department), id, name, repo, entitled(bool), joined(bool), reason?}]}` | Entitlement discovery. Lists every department/org layer visible for the account context, whether the user is **entitled** (has GitHub repo access to it, per D3, the entitlement spine) and whether it is already **joined** (synced onto this machine). Entitlement is computed **CLI-side**; the app only renders the list. |
| `copilot layers join <id> --json` **(proposed contract addition, D7.1)** | `{result(joined\|already-joined\|not-entitled\|error), tier, id, synced_lock_sha}` | Join action. Takes the user's pick of an entitled, not-yet-joined layer from the app-rendered list and syncs it onto the machine (equivalent to what `update` materializes for an already-joined layer). `not-entitled` is a normal, renderable outcome, not a crash. |

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

## `copilot layers [join] --json` (proposed contract addition, D7.1)

Added to close CSE open question 2 / decision D7.1 ([`cse-alignment-decisions.md`](../reference/cse-alignment-decisions.md)): the contract has status/sync verbs (`doctor`/`update`/`resolve`/…) but, until now, no way for a user to **discover** which department/org layers they are entitled to, or to **join** one. This is a **proposed** addition, the same not-yet-upstream status as `copilot publish --json` above, to be folded into upstream WS-A scope at freeze. The prior design *descoped* department discovery entirely; this reverses that descope.

**Purpose.** `copilot layers --json` enumerates every department/org layer the current account context could plausibly join, and for each reports whether the user is **entitled** (D3: entitlement is GitHub repo access to that layer's repo) and whether it is already **joined** (synced onto this machine). `copilot layers join <id> --json` performs the join: given an entitled, not-yet-joined layer id, it syncs that layer onto the machine, the same materialization `update` performs for an already-joined layer, and reports the result.

**Parse, never compute.** Entitlement is a fact the CLI computes by checking GitHub repo access per candidate layer (D3, the entitlement spine); Control Tower never evaluates repo permissions itself. The app's only job is to render the returned list (entitled vs. not, joined vs. not) and pass the user's selection back as the `join` argument, the identical pattern to the `publish --resolve` chooser above (invariant #1: parse, never compute; no entitlement logic in the app).

**Exit codes.** `0` = list/join succeeded (including a `not-entitled` result for `join`, a normal, renderable outcome, not an error); `1` = join refused (e.g. unknown layer id, or entitlement revoked between list and join); `2` = env/credential error (e.g. no GitHub identity resolvable at all).

## Concurrency (the double-write fix)

- **`flock` on `copilot.lock`** across `update` / `repair` / `deprovision`; fail-fast if held. A **global per-host mutex across all verbs** so `deprovision` drains pending syncs before wiping. *The CLI self-serializes — Control Tower is not the lock.* (Fixes red-team B-C1.)

## CLI-updater ownership

- **`COPILOT_MANAGED_BY=controltower`** disables `copilot self-update`, so Control Tower is the single owner of the vendored CLI (no two-updater fight). (Fixes B-C4.)

## Contract test (required)

A **CI contract test in the `copilot` repo** asserts every `--json` command matches the published schema on every release. This schema is the safety boundary: schema drift = silent security bypass (a misread `fail`→`pass` shows green over a red pipeline). See red-team B-H6 and integration §8.

## Acceptance

The schema is published, versioned, and the CI contract test is green. Concurrent `copilot` invocations serialize with no torn `.claude/` tree. Only then does app development (WS-B onward) begin.
