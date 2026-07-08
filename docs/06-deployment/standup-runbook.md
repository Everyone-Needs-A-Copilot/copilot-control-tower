# Standup runbook — deploying Control Tower for an org

> **UNVALIDATED HYPOTHESIS (Founding Decision #9).** This runbook describes
> **Admin mode**, the IT/fleet-operator surface — no real IT operator has
> touched it. It is written to the design (`architecture.md` §8.1, `SOUL.md`
> §1's Raj row: *"To stand up and deploy the whole ecosystem from a guided
> tool + docs alone... — HYPOTHESIS, no real IT operator has touched it"*).
> Follow it as the intended path, not as a confirmed-working procedure.

> **Read [`README.md`](README.md)'s "What's real today vs. what's designed"
> table first.** Several steps below are code-complete and tested (M5); others
> describe the M7 design and are **not yet implemented in this repo** — each
> step says which, explicitly, so this runbook doesn't quietly imply more is
> built than is.

**Who this is for:** an IT/security admin (Raj) standing up Control Tower for
their org, end to end, from Admin mode + this doc alone — the SOUL success
signal this runbook exists to satisfy is *"I stood up the whole fleet from
Admin mode and the docs alone — I never hand-edited YAML."* Today, step 1
can't yet meet that bar (see below) — flagged there, not glossed over.

**Prerequisites:**
- An org enrolled in an MDM (Jamf, Kandji, or Intune) with admin console
  access.
- A GitHub org for `<org>/copilot-ecosystem` (or your org's equivalent
  ecosystem repo), with permission to open PRs against it.
- Someone designated to receive IT safety escalations (this becomes
  `AdminContact`, step 5).
- A Control Tower release build (signed, notarized) to distribute once
  rollout starts.

---

## Step 1 — Author the org `ecosystem.yml` seed

**Design status: not yet built (M7-S6, `tc task get 65`).** The seed
generator — a pure-Rust builder mirroring the `.mobileconfig` generator
below, emitting `products`/`departments`/`foundation` pins/`auth`/`host`/
`mirror`/`policy_signers`/the `telemetry` block, with the same fail-closed
secret scan the `.mobileconfig` generator uses (`looks_like_a_secret`) —
does not exist in this repo yet (no `src-tauri/src/seed/`). **Interim:**
until it lands, hand-author `ecosystem.yml` directly against the ecosystem's
own schema (see the ecosystem repo's own docs) — this is the one step where
"no hand-YAML" genuinely isn't true yet. Once M7-S6 ships, this step becomes:
run the seed generator in Admin mode, review the diff, and let it open the
PR to `<org>/copilot-ecosystem` (dry-run against a mock target during
development; the real PR target is owner-gated per `README.md` item 6).

## Step 2 — Preflight validation

**Design status: not yet built (M7-S7, `tc task get 66`).** The designed
preflight is an **on-demand, one-time** red/green check before rollout — not
a continuous telemetry signal (`observability.md` §7.1 says this explicitly:
"preflight is a one-time, on-demand validation call... not a continuous
signal from the fleet"). It validates: the seed parses; declared department
repos exist; the capability policy is signed by an authorized signer; the
managed profile is *complete for the silent path* (the same completeness
check the wizard itself needs, A-C1/B-H4); the foundation pin resolves; the
mirror is reachable. **Interim:** until it lands, walk this checklist by
hand before pushing the `.mobileconfig` in step 3 — every check above is
something you can verify manually (does the repo exist, is the profile
missing a required key, does the mirror URL respond) even without the
automated report.

## Step 3 — Generate and push the `.mobileconfig`

**Design status: shipped (M5).** This is the one step you can run for real
today. `src-tauri/src/mobileconfig/generator.rs`'s `generate()` takes a
`MobileConfigInputs` (org display name, a `PayloadIdentifier` prefix, and a
map of `managed::keys::MANAGED_KEYS` values — see `README.md`'s key
reference table) and emits one `.mobileconfig` containing up to three
payloads:

1. `com.apple.ManagedClient.preferences` — every forced-domain key you
   supply, keyed under `com.everyoneneedsacopilot.controltower` (built by
   iterating `MANAGED_KEYS`, so a key you don't supply is simply omitted, not
   silently defaulted — check `missing_keys()`'s output before shipping).
2. `com.apple.servicemanagement` — the managed login-item payload (step 4).
3. `com.apple.notificationsettings` — pre-authorizes the bundle's
   notifications so the safety-escalation channel isn't silently defeated by
   a denied OS permission.

`generate()` is fail-closed on secrets: every string value is scanned by
`looks_like_a_secret()` (token prefixes, URL userinfo, JWT/PEM shapes)
**before** any XML is written, and generation is refused rather than emitting
a credential by accident — this is a defense-in-depth backstop; a
`.mobileconfig` should only ever carry references/endpoints/flags per
invariant #6, never a secret value. A worked example is checked in at
`packaging/mobileconfig/sample-acme-corp.mobileconfig` (byte-identical to the
golden fixture `src-tauri/fixtures/mobileconfig/sample-acme-corp.mobileconfig`
the generator's own tests produce) — `plutil -lint` clean, a real artifact
you can open and read.

**Push it:** upload the generated `.mobileconfig` to your MDM console (Jamf
Custom Profile, Kandji Custom Profile, or Intune Configuration Profile — a
step-by-step per-MDM click-path is still to be written, per `README.md`'s
"what's real vs. designed" table; the artifact itself is real today, the
per-console walkthrough isn't yet). Scope it to the device group standing up
Control Tower.

**Real-world caveat:** pushing this and confirming `CFPreferencesAppValueIsForced`
actually flips to `true` on an enrolled Mac has not been exercised outside
`cargo test`'s dev-seam overrides — see `README.md`'s owner-gated table item
1.

## Step 4 — Managed login-item

**Design status: shipped (M5).** Included automatically in step 3's
`.mobileconfig` if `include_login_item_payload` is set. On a managed Mac,
this force-approves Control Tower as a non-toggleable login item via
`SMAppService` (`src-tauri/src/loginitem/{mod,smappservice}.rs`) — distinct
from, and never a substitute for, the crash-only `launchd` watchdog
(`packaging/launchd/com.everyoneneedsacopilot.controltower.plist`,
`KeepAlive={SuccessfulExit:false}`, never `true`). Two mechanisms, one
binary: `SMAppService` owns "start at next login," `launchd` owns "restart
after a crash." Nothing here needs a separate push — it rides the same
profile as step 3.

**Real-world caveat:** whether a managed payload genuinely makes the item
non-toggleable to Bob has not been confirmed on a real enrolled Mac
(`README.md` owner-gated item 2).

## Step 5 — Enable IT safety-escalation (`AdminContact`)

**Design status: shipped, mandatory for managed machines.** Safety
escalation (sig-fail, auth-revoked, policy-conflict, stalled-onboarding,
persistence-disabled, notifications-off) is **on by default** for every
managed machine — not a toggle you opt into, a mandatory forced key. Set
`AdminContact` in the values you pass to the step-3 generator to the
address/endpoint your team actually monitors. If you omit it, the underlying
signal still surfaces **in-app** on Bob's own machine (a solo/unmanaged
install has no IT to notify anyway) — but no safety signal reaches your team
at all, silently. Don't ship without it.

## Step 6 — Enable opt-in analytics telemetry

**Design status: partially built (M7-S1, `tc task get 60` — the wire schema
type only); the gate and transport are not yet built (M7-S2/S3, `tc task get
61/62`).** `src-tauri/src/telemetry/schema.rs`'s `FleetEvent` type exists and
is content-free by construction (pinned by
`tests/fitness_m7_telemetry_schema_content_free.rs`) — but nothing in this
build yet decides *whether* to emit one (the opt-in gate) or *sends* one
anywhere (the transport). Re-check `git status`/`src-tauri/src/telemetry/`
before trusting this list — it was landing, piece by piece, while this
runbook was written.

Analytics (sync/drift/auth-expiry/version-skew/usage counts — never a named
person, never file/prompt/memory content) is a **separate, off-by-default**
channel from the mandatory safety channel in step 5 — conflating the two was
the exact shape of a named finding (A-C5: safety escalations silently gated
behind an analytics opt-in) `observability.md` §1 exists to prevent. Per the
design: analytics only ever emits if your org has explicitly signed
`telemetry.enabled: true` + `telemetry.endpoint: <your collector URL>` into
your `ecosystem.yml` — never a local preference, never guessed. **Carrier
caveat (G-M7-1, open):** because the app can't itself verify an
`ecosystem.yml` signature, the opt-in has to be surfaced to the app as a CLI
`--json` field rather than read directly from the yml — the exact shape of
that field is not yet ratified. **Interim:** there is nothing to turn on
today; no telemetry code path exists in this build. Do not configure
`ecosystem.yml`'s `telemetry` block expecting it to do anything yet.

## Step 7 — Two-of-N signing custody

**Design status: verifier code has landed (M7-S5), but it is not yet the
live path and no real custody exists.** See
[`two-of-n-custody-runbook.md`](two-of-n-custody-runbook.md) for the full
picture — in short, `updater::multisig` now compiles in a 3-key array and a
k=2 threshold, tested against dev keys, but the self-update flow still
verifies against the single, separate `updater::trust::
TRUST_ROOT_PUBLIC_KEY_B64` key. There is no custody setup to perform yet
(no real keys, no assigned second custodian); the runbook documents what's
built, what isn't, and the owner-gated real-key decision.

## Step 8 — Roll out

Distribute the signed, notarized build to the scoped device group via your
MDM's normal app-deployment mechanism (outside this app's scope — your
MDM's own app push, not something Control Tower generates). First run on
each machine reads the pushed `.mobileconfig` (forced `OrgSlug`/`Department`/
`EcosystemSeedURL` etc.) and runs the wizard silently if `DisableWizard` is
forced (`architecture.md` §4).

## Step 9 — Verify with the fleet dashboard

**Design status: frontend has landed (M7-S4), renders fixtures only — no
live backend yet.** See
[`../08-observability/operator-guide.md`](../08-observability/operator-guide.md).
Until the backend lands, verification is manual: spot-check a few machines'
own status (the same tray a Bob sees) and confirm the safety-escalation
address from step 5 is receiving anything real IT would expect to see.

## Step 10 — Deprovisioning a leaver

**Design status: shipped (M5).** Deprovision is **MDM-native, not
app-contingent** — the real backstop is server-side token revocation (the
next online `copilot update` fails closed) plus an explicit forced
`Deprovisioned=true` (never mere profile removal) triggering a wipe,
debounced over a settling window, soft-then-hard (quarantine clones for a
grace window; a flip-back restores without a re-clone). On the app side:
`routing::deprovision_trigger::route_deprovision_trigger_for` reads the
forced `Deprovisioned` key via `managed::forced::forced_string` (not
`forced_bool` — an ambiguous forced value must never silently resolve to
either "triggered" or "not triggered"; it escalates to IT instead of wiping)
and, on a genuine `true`, calls `deprovision::run_deprovision` — the app
contains **zero** wipe/retain logic of its own; it parses `cc deprovision
--json`'s own result (`wiped`/`partial`/`noop`) and renders it.
`auth[].state == "revoked"` (permanent, distinct from transient `expired`)
also routes straight to IT, never a Bob prompt, via the same forced-domain
`AdminContact`.

**Open question, flagged not resolved (G-M5-3):** does the app *invoke* `cc
deprovision` (today's implementation) or only *render* a deprovision an
MDM-run agent already performed out of band? The current build invokes it
because no render-only seam exists yet — this is a CLI-owner decision, not
an app-side guess, and is documented in `routing::deprovision_trigger`'s own
module doc.

**To deprovision a leaver:** set `Deprovisioned=true` for that machine in
your MDM console (forced domain, same mechanism as every key in step 3).
Nothing in Control Tower requires you to also uninstall the app — the wipe
is triggered by the forced key, not by app presence, precisely so trashing
Control Tower or staying offline can't defeat it (`architecture.md` §8.3,
fixes A-C4).

---

## What's still missing from this runbook

Per-MDM (Jamf/Kandji/Intune) click-by-click upload instructions for step 3
are not yet written (`README.md`'s "what's real vs. designed" table) — this
runbook documents the artifact and the forced-key mechanism, not each
console's own UI. An offline/air-gapped path (staple-for-offline-Gatekeeper,
`Waiting-for-network`, foundation-mirror pinning) is architecture-documented
(`architecture.md` §4/§7) but not yet distilled into a runbook section here.
