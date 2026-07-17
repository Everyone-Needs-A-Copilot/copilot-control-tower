# Deployment - Admin guides

> **UNVALIDATED HYPOTHESIS (Founding Decision #9, `SOUL.md` §9 item 9).** Every
> document in this directory (and [`../08-observability/operator-guide.md`](../08-observability/operator-guide.md))
> describes **Admin mode** - the IT/org-operator surface. As of this writing,
> **no real IT operator has touched Admin mode.** These docs are designed-to,
> not validated-by-use. Earl (the IT/Admin persona) is a hypothesis the product
> is built for, not a proven shape (`SOUL.md` §1 psychographic table, §9 item
> 9). Treat every workflow below as "this is how it should work," not "this is
> confirmed to work for a real org" - and do not let a confident tone in the
> prose below be mistaken for field validation.

> **Product model correction (2026-07-08).** This directory previously
> described deployment in terms of enterprise MDM (Jamf/Kandji/Intune,
> `.mobileconfig` profiles, a forced/managed configuration domain, a
> fleet-dashboard center of gravity). That framing has been dropped in full;
> see [`../10-reference/cse-alignment-decisions.md`](../10-reference/cse-alignment-decisions.md)
> D4. **GitHub repo access is now the entitlement and deployment spine**: a
> person has a layer (org, or a given department) if and only if they have
> access to that layer's repo. Admin mode stands up the repos and teams,
> configures a tier-scoped shared secret store, authors the ecosystem seed,
> and users self-install the signed app and join their entitled departments.
> Offboarding is a server-side revoke (repo access + secret-store tokens), not
> a device wipe. This whole directory has been rewritten to that model; read
> [`../10-reference/copilot-solutioning-ecosystem.md`](../10-reference/copilot-solutioning-ecosystem.md)
> first if the "component / tier / entitlement" vocabulary below is new to
> you.

**Home for these docs:** `docs/06-deployment/` is the canonical home for
Admin/IT operational runbooks; the one exception is the fleet-dashboard
operator guide, which lives at `docs/08-observability/operator-guide.md`
because it reads the telemetry wire format `08-observability/observability.md`
already owns - keeping the *dashboard's* doc next to the *schema* it renders,
rather than splitting the observability doc set across two directories.
`docs/09-admin/` does not exist and isn't needed; nothing here outgrew this
one directory.

Admin deployment starts after the publisher has produced a signed, notarized
artifact. For the role split and handoff boundary, see
[`../10-reference/publisher-admin-experience.md`](../10-reference/publisher-admin-experience.md) - note that document still describes the MDM-era Admin journey and has not
yet been reconciled to D4; read this README as the current model where the
two disagree.

## What's real today vs. what's designed

This matters more than usual here, because Admin mode's real surfaces (the
seed generator, preflight, telemetry, the fleet dashboard, two-of-N signing)
landed piece by piece and the vocabulary/model shifted underneath some of them
partway through (D4). The table below reflects a snapshot taken while writing
this doc set - re-check `git status`/`tc task list --prd 7` yourself before
trusting it days later.

| Piece | State | Real code / artifact |
|---|---|---|
| Seed generator (`ecosystem.yml` authoring: `org`/`foundation`/`departments`/`policy_signers`/`telemetry`, fail-closed no-secret scan) | **Shipped (M7-S6)** | `src-tauri/src/admin/seed.rs` (`EcosystemSeed`, `generate`, `validate_shape`, `validate_no_secrets`) |
| Preflight red/green validation (seed parses; department repos exist; capability policy signed by an allowed signer; foundation pin/mirror reachable) | **Shipped (M7-S7)** | `src-tauri/src/admin/preflight.rs` |
| Entitlement discovery + join (`copilot layers` / `copilot layers join`) | **Proposed CLI contract addition (D7.1), not yet in upstream WS-A scope** | `docs/01-architecture/cli-contract.md` §"`copilot layers [join] --json`" - the app has no render code against this verb yet |
| Two-of-N signing verifier (k≥2 compiled-in keys) | **Code landed (M7-S5)** - a sibling entrypoint, dev keys, not yet the active path | `src-tauri/src/updater/multisig.rs` (`TRUST_ROOTS_B64`, `THRESHOLD_K=2`), `verify::verify_update_multisig` - `verify::verify_update` (single-key) is still what's actually invoked; see `two-of-n-custody-runbook.md` |
| Self-update trust root, single compiled-in minisign key | **Shipped, still the live path** | `src-tauri/src/updater/trust.rs` (`TRUST_ROOT_PUBLIC_KEY_B64` - one key) |
| Telemetry wire schema (`FleetEvent`, `machine_id` derivation) | **Shipped (M7-S1)** | `src-tauri/src/telemetry/schema.rs` - the type only |
| Telemetry opt-in gate + transport | **Landed (M7-S2/S3)** | `src-tauri/src/telemetry/{optin,emitter}.rs` - re-verify wiring before trusting this row; it was landing piece by piece |
| Fleet dashboard | **Frontend landed (M7-S4)** - renders fixtures only, no live backend | `src/render/fleet.ts`, `src/fleet.html`, `src/dev-fixtures/fleet/*.json` - no `get_fleet` Rust command exists yet |
| `.mobileconfig` generator, managed login-item force-approve, forced-domain reader, forced-key deprovision trigger | **Superseded by D4 - MDM is dropped, including the seam.** Code still on disk (`src-tauri/src/mobileconfig/`, `src-tauri/src/loginitem/`, `src-tauri/src/managed/forced.rs`, `src-tauri/src/routing/deprovision_trigger.rs`) but is **not** part of the target deployment model this directory now documents. It is not removed as of this writing - that is a follow-up code task, not a docs fix - but do not build a new standup around it. | see the individual `m5-owner-gated-batch.md` entries below for what of M5 survives D4 and what doesn't |
| Shared secret-store endpoint reader (`SharedSecretStoreURL`/`Tier`) | **Shipped, but reads the now-dropped forced/managed domain.** Per D4 the endpoint should be delivered via **signed, inherited org config** instead - that rehoming is a pending code change, not yet done | `src-tauri/src/managed/secret_store.rs` |

The runbooks below say, at each step, which side of this table that step is
on. Nothing in this directory claims a not-yet-built piece works.

## Docs in this directory

- **[`standup-runbook.md`](standup-runbook.md)** - the deployment runbook: seed
  → preflight → stand up the tier repos + team grants → rollout → opt-in
  telemetry → offboarding a leaver. The single "to actually stand up the
  ecosystem" walkthrough.
- **[`two-of-n-custody-runbook.md`](two-of-n-custody-runbook.md)** - the
  signing-custody runbook: the k-of-N verifier that now exists in code
  (dev keys, not yet the live path) alongside the still-live single-key
  path, and who has to hold what before it's real. This is an
  update-signing concern, not a deployment-model one - unaffected by D4.
- **[`m5-owner-gated-batch.md`](m5-owner-gated-batch.md)** - the M5-specific
  list of "code-complete, blocked on a human with real credentials/a real
  Mac/a real GitHub org" items, reconciled to D4 (MDM-specific items are
  flagged superseded, not carried forward as active gates).
- **[`m9-owner-gated-split.md`](m9-owner-gated-split.md)** - the M9
  (Windows re-skin) counterpart: buildable-now-behind-`cfg` vs. owner-gated
  (needs a real Windows box or EV cert), carrying its own
  **BUILT-BUT-UNVERIFIED-ON-WINDOWS** stamp since no Windows runtime
  behavior can be verified from this machine at all. Its one MDM-shaped row
  (forced-config parity, ADR-M9-003) is flagged for reconciliation with D4,
  not yet rewritten - see [`windows-parity.md`](../01-architecture/windows-parity.md)
  §5 for the independently-QA'd verification matrix and
  [`windows-bringup.md`](windows-bringup.md) for the owner's actual
  bringup checklist.
- **[`../08-observability/operator-guide.md`](../08-observability/operator-guide.md)** - the fleet-dashboard operator guide (reading per-host worst-wins + the
  safety-escalation feed - there is no fleet-health score to read).

## The deployment model, in one page

Per [`../10-reference/copilot-solutioning-ecosystem.md`](../10-reference/copilot-solutioning-ecosystem.md)
and [`cse-alignment-decisions.md`](../10-reference/cse-alignment-decisions.md) D3/D4/D6:

1. **Stand up the repos.** Each CSE component (Knowledge, CLI, Claude/Codex
   Copilot) exists at four tiers - foundation (public, open-source), org,
   department, personal. An Admin stands up the org and department repos
   (foundation is already public; personal repos belong to each person).
2. **Grant access with GitHub teams.** Entitlement to a layer *is* GitHub
   repo access to it - nothing else grants or gates it. A department team
   grant is what "gives someone that department."
3. **Configure the shared secret store.** A tier-scoped shared secret store
   (Infisical/OpenBao) holds org/department integration keys, accessed by
   GitHub-team membership. Its endpoint is delivered via inherited org
   config (D4) - never MDM, never a value in git.
4. **Author the ecosystem seed.** Run the seed generator (Admin mode) to
   produce `ecosystem.yml`: org identity, the foundation pin, the department
   list, the policy-signer allow-list, and the (off-by-default) telemetry
   endpoint. Review the diff; open the PR.
5. **Users self-install and join.** A person downloads the signed, notarized
   release and opens it - no zero-touch, no profile push. The wizard shows
   which departments they're entitled to (by repo access) and syncs the ones
   they select.
6. **Offboard by revoking access.** Remove the person from the relevant
   GitHub team(s) and rotate any shared-secret-store tokens they could read.
   The next `copilot update`/`freshness` check on their machine fails closed.
   Content already synced to a departed person's disk is not remotely wiped - there is no MDM to reach the device; this is an accepted residual for the
   target (small, trusted orgs), not an oversight.

## Owner-gated: what a human must decide or do before real rollout

Consolidated from `m5-owner-gated-batch.md` (code-complete today, reconciled
to D4) and the M7 task definitions (`tc task get 60`–`69`) +
`observability.md` §11 / `architecture.md` §11.

| # | Item | Blocks | Status |
|---|---|---|---|
| 1 | A real GitHub org with the four-tier repos created (org repo, one repo per department) and teams granting the right access | Any entitlement resolving at all - this is the repo-access model's equivalent of "MDM enrollment" | Org decision, no code gap |
| 2 | Real signed/notarized `.app` on a real Mac | Confirming self-install actually opens cleanly, no security warning | Code-complete, needs Apple Developer ID + notarization creds (M4) |
| 3 | `AdminContact` endpoint value (a real IT-owned URL/address) | Safety-escalation delivery - without it, signals fall back to in-app-only (A-H10) | Org decision, no code gap |
| 4 | Real update-feed endpoint (replaces `updates.controltower.example` in `trust.rs`) | Self-update actually resolving a real `latest.json` | Owner-gated, undecided (D-4-M4) |
| 5 | Minisign two-of-N real keys + second-key holder assignment | The `verify_update_multisig` verifier being real (and live) rather than dev-keyed and unwired | **Verifier code landed** (dev keys, sibling entrypoint), custody unassigned (M7-S5) - see `two-of-n-custody-runbook.md` |
| 6 | `EcosystemSeedURL` real seed-repo target + the seed generator's PR target (`<org>/<C>-copilot-internal`, one per component) | The seed generator opening a real PR instead of a dry-run mock | **Generator code landed**, real PR target not yet wired |
| 7 | The opt-in analytics carrier field ratification (G-M7-1) | Analytics ever emitting for a real org | Simplified by D4: since there is no forced domain to choose between, the carrier is the signed `ecosystem.yml` `telemetry` field - confirm the app can't itself forge that signature before trusting it |
| 8 | Collected-fleet-event source / org collector query API (G-M7-3) | The fleet dashboard rendering anything beyond fixtures | **Frontend landed against fixtures**, backend/collector source not built |
| 9 | Shared secret-store endpoint (`SharedSecretStoreURL`/`Tier`) | The credential-resolution ladder's shared-store rung | Org infra decision; **also blocked on a code rehoming from the forced/managed domain to signed inherited org config per D4** - not yet done |
| 10 | Stalled-onboarding threshold + safety-channel retry/backoff numbers | `stalled-onboarding` firing deterministically; safety-channel queue/backoff bounds | Unratified numbers |
| 11 | Entitlement discovery/join verb (`copilot layers` / `copilot layers join`, D7.1) landing in the real CLI and the app rendering it | The wizard's department-join step actually working end to end, replacing the old MDM-pushed `Department` key | **Proposed CLI contract only** - not yet upstream, not yet rendered app-side |

Items 2–4 restate what `m5-owner-gated-batch.md` already covers in more
depth (read that file for the exact verification detail per item). Items
5–10 don't have their own "owner-gated batch" doc yet; they're listed here
from the M7 task definitions and `observability.md` §11 so nobody has to
reconstruct them from the task tracker later. Item 1 and item 11 replace what
used to be "real MDM enrollment" - repo/team standup is now the equivalent
gate, and the entitlement verb is the equivalent of the old forced
`OrgSlug`/`Department` keys.
