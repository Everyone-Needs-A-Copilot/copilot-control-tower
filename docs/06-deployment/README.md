# Deployment — IT guides

> **UNVALIDATED HYPOTHESIS (Founding Decision #9, `SOUL.md` §9 item 9).** Every
> document in this directory (and [`../08-observability/operator-guide.md`](../08-observability/operator-guide.md))
> describes **Admin mode** — the IT/fleet-operator surface. As of this writing,
> **no real IT operator has touched Admin mode.** These docs are designed-to,
> not validated-by-use. Earl (the IT/Admin persona) is a hypothesis the product
> is built for, not a proven shape (`SOUL.md` §1 psychographic table, §9 item
> 9). Treat every workflow below as "this is how it should work," not "this is
> confirmed to work for a real IT team" — and do not let a confident tone in
> the prose below be mistaken for field validation.

**Home for these docs:** `docs/06-deployment/` is the canonical home for
Admin/IT operational runbooks; the one exception is the fleet-dashboard
operator guide, which lives at `docs/08-observability/operator-guide.md`
because it reads the telemetry wire format `08-observability/observability.md`
already owns — keeping the *dashboard's* doc next to the *schema* it renders,
rather than splitting the observability doc set across two directories.
`docs/09-admin/` does not exist and isn't needed; nothing here outgrew this
one directory.

Admin deployment starts after the publisher has produced a signed, notarized
artifact. For the role split and handoff boundary, see
[`../reference/publisher-admin-experience.md`](../reference/publisher-admin-experience.md).

## What's real today vs. what's designed

This matters more than usual here, because the milestone that builds most of
Admin mode (M7 — telemetry, the seed generator, preflight, the fleet
dashboard, two-of-N signing) is **actively landing in code as this doc set was
written**, in parallel, piece by piece — `tc task list --prd 7` still shows
every M7 stream as `pending` in the tracker even though several streams'
files are already on disk (untracked, uncommitted). Only M4 (distribution/
signing, single-key) and M5 (MDM/security, mobileconfig + login-item +
deprovision) are fully committed and QA-accepted. The table below reflects a
snapshot taken while writing this doc set — re-check `git status`/`tc task
list --prd 7` yourself before trusting it days later. It is the one place
this whole directory's honesty rests on — every runbook links back to it
rather than re-asserting shipped-vs-designed per page.

| Piece | State | Real code / artifact |
|---|---|---|
| `.mobileconfig` generator (preferences + login-item + notifications payloads) | **Shipped (M5)** | `src-tauri/src/mobileconfig/{mod,generator}.rs`; golden fixture `packaging/mobileconfig/sample-acme-corp.mobileconfig` |
| Managed login-item (launch-at-login, force-non-toggleable) | **Shipped (M5)** | `src-tauri/src/loginitem/{mod,smappservice}.rs` |
| Deprovision trigger + auth-revoked → IT routing | **Shipped (M5)** | `src-tauri/src/routing/{mod,deprovision_trigger}.rs`, `src-tauri/src/deprovision/` |
| Frozen managed-key registry (single source of truth for every `.mobileconfig` key) | **Shipped (M5)** | `src-tauri/src/managed/keys.rs` (`MANAGED_KEYS`) |
| Self-update trust root, single compiled-in minisign key | **Shipped (M4), still the live path** | `src-tauri/src/updater/trust.rs` (`TRUST_ROOT_PUBLIC_KEY_B64` — one key) |
| Two-of-N signing verifier (k≥2 compiled-in keys) | **Code landing now (M7-S5, `tc task get 64`)** — built as a **sibling** entrypoint, dev keys, not yet the active path | `src-tauri/src/updater/multisig.rs` (`TRUST_ROOTS_B64`, `THRESHOLD_K=2`), `verify::verify_update_multisig` — `verify::verify_update` (single-key) is still what's actually invoked; see `two-of-n-custody-runbook.md` |
| Seed generator (`ecosystem.yml` authoring + PR) | **Designed, not yet built** (M7-S6, `tc task get 65`) | none — no `src-tauri/src/seed/` |
| Preflight red/green validation | **Designed, not yet built** (M7-S7, `tc task get 66`) | none — no `src-tauri/src/preflight/` |
| Telemetry wire schema (`FleetEvent`, `machine_id` derivation) | **Code landing now (M7-S1, `tc task get 60`)** | `src-tauri/src/telemetry/{mod,schema}.rs` — the TYPE only |
| Telemetry opt-in gate + real transport | **Designed, not yet built** (M7-S2/S3, `tc task get 61/62`) | none yet — no `telemetry/gate.rs`, `telemetry/emit_sink.rs`/`transport.rs` |
| Fleet dashboard | **Frontend landing now (M7-S4, `tc task get 63`)** — renders fixtures only, no live backend | `src/render/fleet.ts`, `src/fleet.html`, `src/dev-fixtures/fleet/*.json`, `FleetHostView`/`FleetActionItem`/`FleetView` in `src/types.ts`; **no** Rust `get_fleet` command exists yet (`types.ts` reserves the name: `GET_FLEET_CMD`) |

The runbooks below say, at each step, which side of this table that step is
on. Nothing in this directory claims a not-yet-built piece works.

## Docs in this directory

- **[`standup-runbook.md`](standup-runbook.md)** — the deployment runbook: seed
  → preflight → MDM profile → rollout → opt-in telemetry → deprovisioning a
  leaver. The single "to actually stand up the fleet" walkthrough.
- **[`two-of-n-custody-runbook.md`](two-of-n-custody-runbook.md)** — the
  signing-custody runbook: the k-of-N verifier that now exists in code
  (dev keys, not yet the live path) alongside the still-live single-key
  path, and who has to hold what before it's real.
- **[`m5-owner-gated-batch.md`](m5-owner-gated-batch.md)** — the M5-specific
  list of "code-complete, blocked on a human with real credentials/a real Mac/
  a real MDM console" items. Superseded in scope (not content) by the
  consolidated table below, which folds this list in alongside M7's
  not-yet-built equivalents.
- **[`m9-owner-gated-split.md`](m9-owner-gated-split.md)** — the M9
  (Windows re-skin) counterpart: buildable-now-behind-`cfg` vs. owner-gated
  (needs a real Windows box, EV cert, or MDM console), carrying its own
  **BUILT-BUT-UNVERIFIED-ON-WINDOWS** stamp since no Windows runtime
  behavior can be verified from this machine at all. As of Stream-Z's
  close-out (`tc task get 80`), `platform/` (Stream-B) and all eight Windows
  seams (Streams C–H) plus packaging (I) and Authenticode (J) HAVE landed,
  code-complete and `#[cfg(windows)]`-gated — see
  [`../01-architecture/windows-parity.md`](../01-architecture/windows-parity.md)
  §5 for the independently-QA'd verification matrix and
  [`windows-bringup.md`](windows-bringup.md) for the owner's actual
  bringup checklist. Not yet folded into the consolidated table below.
- **[`../08-observability/operator-guide.md`](../08-observability/operator-guide.md)**
  — the fleet-dashboard operator guide (reading per-host worst-wins + the
  safety-escalation feed — there is no fleet-health score to read).

## Managed-config key reference

Every key below is defined once, in code, in `src-tauri/src/managed/keys.rs`'s
`MANAGED_KEYS` registry — this table is a direct transcription of that
registry (14 keys, verified against the file, not the older prose list this
README used to carry). All 14 are `forced_only: true` — a value written to the
ordinary user-writable preferences domain is **ignored**, not honored, for
every one of them (`FF-M5-5`). The domain is
`com.everyoneneedsacopilot.controltower` (**not** `dev.enac.controltower` —
see the note below the table).

| Key | Type | Security-sensitive | Purpose |
|---|---|---|---|
| `OrgSlug` | string | no | Org identifier `cc derive` uses to materialize org/dept layers |
| `Department` | string | no | Department identifier for the dept layer |
| `EcosystemSeedURL` | string | **yes** | Where `cc derive` fetches the org's `ecosystem.yml` seed |
| `GitHubHost` | string | **yes** | GitHub Enterprise host override |
| `AuthMode` | string | **yes** | Git auth identity class (`ssh-personal`/`ssh-work`/`anon`/`gh-app:<slug>`) |
| `Host` | string | no | Machine-class identifier (kiosk vs. personal) |
| `FoundationMirror` | string | **yes** | Alternate foundation-tier mirror URL |
| `HTTPSProxy` | string | **yes** | Forced HTTPS proxy for ecosystem/update traffic |
| `UpdateFeedURL` | string | **yes** | Where the self-updater fetches the signed `latest.json` |
| `UpdateChannel` | string | **yes** | Release channel pin (`stable`/`beta`/`pinned:<version>`) |
| `AllowSelfUpdate` | bool | **yes** | Whether this machine self-updates at all |
| `DisableWizard` | bool | **yes** | Runs onboarding silently; gates the wizard's own fail-closed validation |
| `Deprovisioned` | bool | **yes** | Explicit MDM wipe signal — only an explicit `true` triggers a deprovision |
| `AdminContact` | string | **yes** | Mandatory IT safety-escalation endpoint |
| `SharedSecretStoreURL` | string | **yes** | Endpoint reference only (never a secret) for the shared secret store |
| `SharedSecretStoreTier` | string | **yes** | Which tier/namespace this machine's members are scoped to |
| `LoginItemManaged` | bool | no | Provisional: announces MDM separately pushed the login-item payload |

**Domain note (G-M5-1, not silently resolved):** `architecture.md` §8.3 and
this README used to say `dev.enac.controltower`. The **code-authoritative**
domain — what `tauri.conf.json`'s `identifier` and `managed::keys::
APPLICATION_ID` both actually read/write, pinned by a passing test
(`application_id_matches_the_tauri_bundle_identifier`) — is
`com.everyoneneedsacopilot.controltower`. Use the code domain in every
`.mobileconfig` you build by hand or via the (not-yet-built) seed generator.
The architecture doc's prose is flagged for reconciliation, not yet fixed.

## Owner-gated: what a human must decide or do before real fleet rollout

Consolidated from `m5-owner-gated-batch.md` (M4/M5, code-complete today) and
the M7 task definitions (`tc task get 60`–`69`) + `observability.md` §11 /
`architecture.md` §11 (M7, not-yet-built — these gate *building* it, not just
*activating* it). One trail, in the order a standup actually hits them:

| # | Item | Blocks | Status |
|---|---|---|---|
| 1 | Real MDM enrollment (Jamf/Kandji/Intune) + pushing a `.mobileconfig` that actually sets `CFPreferencesAppValueIsForced` | Any forced-domain key taking effect at all | Code-complete, needs a real MDM console (M5) |
| 2 | Real signed/notarized `.app` on a real Mac | `SMAppService` real approval-state transitions (force-approve, non-toggleable) | Code-complete, needs Apple Developer ID + notarization creds (M5) |
| 3 | `AdminContact` endpoint value (a real IT-owned URL/address) | Safety-escalation delivery — without it, signals fall back to in-app-only (A-H10) | Org decision, no code gap |
| 4 | Real update-feed endpoint (replaces `updates.controltower.example` in `trust.rs`) | Self-update actually resolving a real `latest.json` | Owner-gated, undecided (D-4-M4) |
| 5 | Minisign two-of-N real keys + second-key holder assignment | The `verify_update_multisig` verifier being real (and live) rather than dev-keyed and unwired | **Verifier code landed** (dev keys, sibling entrypoint), custody unassigned (M7-S5) — see `two-of-n-custody-runbook.md` |
| 6 | `EcosystemSeedURL` real seed-repo target + the seed generator's PR target (`<org>/copilot-ecosystem`) | The seed generator opening a real PR instead of a dry-run mock | **Not built yet** (M7-S6) |
| 7 | The opt-in analytics carrier field ratification (G-M7-1: forced-domain vs. signed `ecosystem.yml` field — the app can't verify the yml's own signature itself) | Analytics ever emitting for a real org | **Not built yet** (M7-S1 schema landed; S2 gate not built) |
| 8 | Collected-fleet-event source / org collector query API (G-M7-3) | The fleet dashboard rendering anything beyond fixtures | **Frontend landed against fixtures**, backend/collector source not built (M7-S4) |
| 9 | Shared secret-store endpoint (`SharedSecretStoreURL`/`Tier`) | The credential-resolution ladder's shared-store rung | Org infra decision, no code gap |
| 10 | Stalled-onboarding threshold + safety-channel retry/backoff numbers (`observability.md` §11 items 1/3, G-M7-5/6) | `stalled-onboarding` firing deterministically; safety-channel queue/backoff bounds | **Not built yet**, unratified numbers |

Items 1–4 and 9 are the same list `m5-owner-gated-batch.md` already
maintains in more depth (read that file for the exact verification detail per
item) — restated here only so a single table walks an owner start to finish.
Items 5–8 and 10 don't have their own "owner-gated batch" doc yet because the
code they gate doesn't exist; they're listed here from the M7 task
definitions and `observability.md` §11 so nobody has to reconstruct them from
the task tracker later.
