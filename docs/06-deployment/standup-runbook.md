# Standup runbook - deploying Control Tower for an org

> **UNVALIDATED HYPOTHESIS (Founding Decision #9).** This runbook describes
> **Admin mode**, the IT/org-operator surface - no real IT operator has
> touched it. It is written to the design (`architecture.md` §8.1, `SOUL.md`
> §1's Earl row: *"To stand up and deploy the whole ecosystem from a guided
> tool + docs alone... - HYPOTHESIS, no real IT operator has touched it"*).
> Follow it as the intended path, not as a confirmed-working procedure.

> **Product model correction (2026-07-08).** This runbook previously walked
> an MDM standup (enroll a Mac, push a `.mobileconfig`, force-domain keys).
> Per [`../10-reference/cse-alignment-decisions.md`](../10-reference/cse-alignment-decisions.md)
> D4, MDM is dropped completely. **GitHub repo access is the entitlement and
> deployment spine.** The steps below now walk: author the seed, stand up
> the tier repos and grant team access, users self-install and join their
> entitled departments, and offboard by revoking access. Read
> [`README.md`](README.md)'s "What's real today vs. what's designed" table
> first - several steps below are shipped and tested; the entitlement-join
> verb is still a proposed CLI contract addition, not yet real.

**Who this is for:** an IT/org admin (Earl) standing up Control Tower for
their org, end to end, from Admin mode + this doc alone - the SOUL success
signal this runbook exists to satisfy is *"I stood up the whole ecosystem
from Admin mode and the docs alone - I never hand-edited YAML."* Today, step
1 can't yet fully meet that bar (the seed generator exists but its output
shape isn't yet CLI-ratified) - flagged there, not glossed over.

**Prerequisites:**
- A GitHub org (or equivalent) to hold the org repo and one repo per
  department, with permission to create repos and manage team access.
- A GitHub org for `<org>/<C>-copilot-internal` (the org-layer repo, one per
  component, that carries `ecosystem.yml`), with permission to open PRs
  against it.
- If you use shared integrations (Workday, Salesforce, Microsoft, etc.): a
  tier-scoped shared secret store instance (Infisical or OpenBao), reachable
  by GitHub-team membership.
- Someone designated to receive IT safety escalations (this becomes
  `AdminContact`, step 5).
- A Control Tower release build (signed, notarized) for people to download
  once rollout starts.

---

## Step 1 - Stand up the four-tier repos and grant access

**Design status: infra step, no code gap.** Per component (Knowledge Copilot,
CLI Copilot, Claude/Codex Copilot) and per tier:

- **Foundation** is already public and open-source - nothing to stand up.
- **Org** gets one repo per component under your GitHub org (or org
  namespace), with org-wide base read for every employee (or an `everyone`
  team) per `four-tier-topology.md` §6.3.
- **Department** gets one *separate* repo per component per department
  (confidential-by-default: GitHub has no path-level read ACL, so a
  subfolder does not isolate confidential departmental content - a separate
  repo is the only real read boundary; see `four-tier-topology.md` §6.2).
  Grant access via a GitHub team scoped to that department.
- **Personal** repos belong to each person; nothing for Admin to create.

**This is the entitlement step.** There is no separate "enrollment" action - a person is entitled to a layer the moment their GitHub account has read
access to that layer's repo, via team membership.

## Step 2 - Configure the tier-scoped shared secret store

**Design status: infra decision + a pending code rehoming.** Stand up
Infisical or OpenBao (self-hosted, no paid tier), scoped per org/department
tier, and grant access by the same GitHub teams from step 1. The store holds
shared integration credentials (Workday, Salesforce, Microsoft, etc.) so
individual users never set up their own API keys for shared integrations - distinct from personal sign-in, which stays per-person.

The endpoint (`SharedSecretStoreURL`/`SharedSecretStoreTier`) is a
**reference, never a secret** - pointing an app at the wrong endpoint grants
nothing, because access to the store itself is still gated by the reader's
own GitHub-team membership/token. Per D4, this endpoint should be delivered
via **signed, inherited org config** (i.e. a field in `ecosystem.yml`, step
3), not a device-management push. **As of this writing the app still reads
this endpoint from the old forced/managed preferences domain**
(`src-tauri/src/managed/secret_store.rs`) - that rehoming to the seed/config
path is a pending code change, not yet done. Skip populating a real endpoint
until it lands.

## Step 3 - Author the org `ecosystem.yml` seed

**Design status: shipped (M7-S6).** The seed generator
(`src-tauri/src/admin/seed.rs`) is a pure-Rust builder: typed Admin input
(org identity, the foundation pin, the department list, the security team's
`policy_signers` public-key allow-list, the off-by-default `telemetry`
block) → the same fail-closed no-secret scan the `.mobileconfig`-era
generator used → emitted `ecosystem.yml` text. Run it in Admin mode, review
the diff, and let it open the PR to `<org>/<C>-copilot-internal`.

**Flagged, not silently resolved (G-M7-7):** the shape this generator emits
is a careful, evidence-cited transcription of
`docs/10-reference/ecosystem-architecture.md` §4.2's worked example - it is not
yet a shape the real CLI (`claude-copilot/tools/cc`) parses or validates
against a ratified schema. Generate to this documented shape; don't treat it
as a settled contract yet. The seed's per-component department map is
currently keyed as `products` in code (a vocabulary holdover from before the
component/product split, `cse-alignment-decisions.md` D2) - read it as
"components," not built outputs; renaming the field is a follow-up code
task, not yet done.

## Step 4 - Preflight validation

**Design status: shipped (M7-S7).** The preflight
(`src-tauri/src/admin/preflight.rs`) is an **on-demand, one-time** red/green
check before rollout - not a continuous telemetry signal
(`observability.md` §7.1: "preflight is a one-time, on-demand validation
call... not a continuous signal from the fleet"). It validates: the seed
parses and is well-formed; it carries no secret-shaped value; declared
department repos exist; the capability policy is signed by an authorized
signer (checked against the seed's own `policy_signers` allow-list); the
foundation pin/mirror is reachable. Run it before rollout and fix every red
item - each one names the offending input and the next fix.

## Step 5 - Enable IT safety-escalation (`AdminContact`)

**Design status: shipped, mandatory.** Safety escalation (sig-fail,
auth-revoked, policy-conflict, stalled-onboarding, persistence-disabled,
notifications-off) is **on by default**, not a toggle you opt into. Set
`AdminContact` in `ecosystem.yml` to the address/endpoint your team actually
monitors. If you omit it, the underlying signal still surfaces **in-app** on
the affected person's own machine (a solo/unmanaged install has no IT to
notify anyway) - but no safety signal reaches your team at all, silently.
Don't ship without it.

## Step 6 - Enable opt-in analytics telemetry

**Design status: landed (M7-S1/S2/S3) - re-verify wiring before trusting
this section; it was landing piece by piece.** `FleetEvent`
(`src-tauri/src/telemetry/schema.rs`) is content-free by construction
(pinned by `tests/fitness_m7_telemetry_schema_content_free.rs`). Analytics
(sync/drift/auth-expiry/version-skew/usage counts - never a named person,
never file/prompt/memory content) is a **separate, off-by-default** channel
from the mandatory safety channel in step 5 - conflating the two was the
exact shape of a named finding (A-C5) `observability.md` §1 exists to
prevent.

Analytics only ever emits if your org has explicitly signed
`telemetry.enabled: true` + `telemetry.endpoint: <your collector URL>` into
`ecosystem.yml` (step 3) - never a local preference, never guessed. D4
simplifies what was an open carrier question (G-M7-1: "forced-domain vs.
signed `ecosystem.yml` field"): with no forced domain to choose between, the
signed `ecosystem.yml` field is the only carrier. What remains open is
narrower: the app can't itself verify `ecosystem.yml`'s own signature, so the
opt-in still has to reach the app as a CLI `--json` field rather than a
direct yml read - the exact shape of that field is not yet ratified.

## Step 7 - Two-of-N signing custody

**Design status: verifier code has landed (M7-S5), but it is not yet the
live path and no real custody exists.** Unaffected by D4 - this is an
update-signing concern, not a deployment-model one. See
[`two-of-n-custody-runbook.md`](two-of-n-custody-runbook.md) for the full
picture.

## Step 8 - Roll out: users self-install and join

**Design status: mixed - self-install is shipped; entitlement discovery/join
is a proposed CLI contract addition (D7.1), not yet real.** There is no push
step. Share the download link for the signed, notarized build (an internal
wiki page, a pinned message, a GitHub Releases page - whatever your org
already uses) with anyone entitled to any layer. Each person downloads it and
opens it themselves.

On first run, the wizard is meant to call `copilot layers --json` to show
which org/department layers the signed-in person is entitled to (by GitHub
repo access) and let them join one with `copilot layers join <id> --json`
(`docs/01-architecture/cli-contract.md` §"`copilot layers [join] --json`").
**This verb does not exist in the real CLI yet** - it is a control-tower-
originated proposal not yet folded into upstream WS-A scope, and the app has
no render code against it yet. Until it lands, department selection has no
guided path; this is the one step where "no hand-configuration" genuinely
isn't true yet, mirroring what step 1 of the old MDM-era runbook used to
flag about the seed generator.

## Step 9 - Verify with the fleet dashboard

**Design status: frontend has landed (M7-S4), renders fixtures only - no
live backend yet.** See
[`../08-observability/operator-guide.md`](../08-observability/operator-guide.md).
Until the backend lands, verification is manual: spot-check a few machines'
own status (the same tray a user sees) and confirm the safety-escalation
address from step 5 is receiving anything real IT would expect to see.

## Step 10 - Offboarding a leaver

**Design status: reworked per D4 - server-side revocation replaces the
MDM wipe flag.** Offboarding is now:

1. **Remove the person from every relevant GitHub team** (department and,
   if applicable, org) - this is what actually revokes entitlement.
2. **Rotate any shared-secret-store token(s)** they could read via that
   team membership.

There is no forced `Deprovisioned=true` flag to set and no device to reach - the mechanism is credential revocation, not a wipe command. The next online
`copilot update`/`freshness` check on their machine fails closed once their
GitHub access no longer resolves, routing through the existing
`auth[].state == "revoked"` path straight to IT (never a user-facing prompt),
the same routing this app already uses for any other permanent auth
revocation. **Accepted residual, not a gap:** content already synced to the
departed person's disk is not remotely wiped - there is no MDM to reach the
device. This is acceptable for the target (small, trusted orgs); it is a
structural trade-off of dropping MDM, not an oversight to work around.

**What this replaces:** the old model routed `Deprovisioned=true` through
`routing::deprovision_trigger` to `cc deprovision`, with the open question
(G-M5-3) of whether the app should invoke or only render that call. That
open question still exists in principle, but its trigger is now "GitHub
access revoked, detected on next sync attempt," not an MDM-forced flag - `routing::deprovision_trigger`'s own module doc and `m5-owner-gated-batch.md`
item 3/6 have not yet been updated to reflect this and remain the
authoritative flag of the open question until they are.

---

## What's still missing from this runbook

The entitlement-discovery/join verb (step 8) doesn't exist in the real CLI
yet - there is no guided "which departments am I entitled to" flow until
`copilot layers`/`copilot layers join` lands (D7.1). The shared secret-store
endpoint (step 2) still reads from the old forced/managed domain in code,
not yet from `ecosystem.yml`. Both are pending code changes, not missing
documentation - tracked in `README.md`'s owner-gated table, items 9 and 11.
