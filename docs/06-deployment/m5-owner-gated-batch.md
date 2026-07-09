# M5 owner-gated batch (Security & credentials)

> **Status: build input, not a report.** Everything below is code-complete and
> verified against mocks/fixtures/dev-seams by `cargo test` (see
> `scratchpad/qa-m5-acceptance.md` for the verification session that produced
> this list). None of it can be exercised further by an automated session;
> each item needs a human with real credentials, a real Mac, or a real GitHub
> org. Nothing here blocks M5 code-complete; everything here blocks
> *real-world* activation.

> **Product model correction (2026-07-08).** M5 was originally scoped
> "MDM & Security." Per
> [`../reference/cse-alignment-decisions.md`](../reference/cse-alignment-decisions.md)
> D4, MDM is dropped completely, including the seam. Item 1 below (the old
> "real MDM enrollment" gate) is **superseded**, not carried forward as an
> active gate - it's kept in this doc, marked superseded, so nobody
> re-discovers "enroll a Mac in Jamf" as a live task. Items 2–6 were not
> exclusively MDM concerns; each is reconciled below to note what survives
> D4 and what doesn't.

## 1. Real forced-domain / MDM enrollment - SUPERSEDED BY D4

- This item used to read: enroll a Mac in a real MDM and push a
  `.mobileconfig` that sets `CFPreferencesAppValueIsForced` for
  `com.everyoneneedsacopilot.controltower`, as the only way to exercise
  `managed/forced.rs`'s real `CFPreferencesAppValueIsForced`/
  `CFPreferencesCopyAppValue` FFI calls end to end. **This is no longer
  part of the target deployment model.** `managed/forced.rs`,
  `mobileconfig/generator.rs`, and the managed-login-item force-approve half
  of `loginitem/smappservice.rs` are all MDM-era code that D4 supersedes.
  They are not yet removed from the repo (a follow-up code task), but no
  real-world activation work should be planned against them. The
  entitlement/deployment gate they used to serve is now **README.md**'s
  owner-gated item 1 (stand up the GitHub org + team repo access).
- **G-M5-1 domain-name reconciliation** (found and confirmed live, still
  relevant for a different reason): `tauri.conf.json`'s `identifier` and
  `managed::keys::APPLICATION_ID` are both, correctly,
  `com.everyoneneedsacopilot.controltower` - the code-authoritative
  application identifier, pinned by
  `managed::keys::tests::application_id_matches_the_tauri_bundle_identifier`.
  This identifier is still load-bearing outside MDM (it's the app bundle ID
  the updater, keychain, and self-update trust checks all key off of), so
  the reconciliation itself still stands even though the MDM-specific reason
  it was originally raised for (matching a `.mobileconfig`'s payload domain)
  no longer applies. `docs/01-architecture/architecture.md` (3 call sites)
  still says `dev.enac.controltower` in places; reconcile the docs to the
  code identifier when touched next.

## 2. Real login-item registration on a signed bundle

- `loginitem::smappservice`'s `LoginItemService` real implementation (backed
  by `objc2-service-management`) is exercised in `cargo test` only through
  the `LoginItemService` trait's fake (`FakeService` in `loginitem/mod.rs`'s
  own tests). The real approval flow - does an unmanaged `register()`
  genuinely prompt the user - needs a signed, notarized `.app` running on a
  real Mac. **The managed, force-approved, non-toggleable half of this item
  (via a `com.apple.servicemanagement` MDM payload) is superseded by D4** - under the repo-access model there is no fleet-forced login item; it is
  always a normal, user-toggleable preference. Only the unmanaged
  `register()`/prompt path remains an owner-gated verification item.

## 3. Real `cc deprovision` - CLI-repo sandbox only, NEVER this app / `~/.claude`

- Every deprovision-path test in this crate (`deprovision::run_deprovision`,
  `routing::deprovision_trigger`) drives the mock `fixtures/mock-cc` via the
  `CT_CLI_PATH`/`CT_FIXTURE` dev seam. The real `cc deprovision <org> --json`
  contract - including the soft-then-hard debounce/settling window, entirely
  CLI-side per ADR-M5-002 - must be exercised in the **CLI repo's own tmp
  sandbox**, never against a real `~/.claude`, and never from this app's
  test suite.
- **Trigger mechanism reworked per D4, not yet reflected in code/docs
  (flag, not silently resolved):** this item and `routing::deprovision_trigger`'s
  own module doc still describe the trigger as a forced `Deprovisioned=true`
  key an MDM console sets. Per D4 and `standup-runbook.md` step 10, the real
  trigger is now **GitHub access revocation detected on the next
  `copilot update`/`freshness` call**, routed the same way any other
  permanent `auth[].state == "revoked"` is routed today - no forced key
  involved. The module doc has not yet been updated to say this; treat this
  paragraph as the current authoritative statement until it is.
- **G-M5-3, still open (Proposed, not Accepted) - flag to the CLI owner at
  freeze**: does the app *invoke* `cc deprovision` (current implementation,
  `routing::deprovision_trigger::route_deprovision_trigger_for` calling
  `deprovision::run_deprovision`), or only *render* a deprovision the CLI
  already performed out of band on revocation? The current build *invokes*
  the CLI process - because no second "read an already-computed result
  without invoking" schema/seam exists today. Needs a CLI-owner ruling, not
  an app-side guess. This question is unaffected by D4 in substance, only in
  what triggers it.

## 4. Real notifications-profile authorization - SUPERSEDED BY D4

- The old item: `mobileconfig::generator`'s `com.apple.notificationsettings`
  payload pre-authorized the safety-escalation channel via an MDM push, and
  was never confirmed on a real Mac. **Not applicable under the repo-access
  model** - there is no managed pre-authorization payload to push. What
  remains owner-gated is the plain, unmanaged case: confirming the OS
  notification permission prompt behaves as expected when a real user is
  asked for it, with no fleet-forced grant available as a fallback if they
  deny it.

## 5. The secret-store endpoint value itself

- `managed::secret_store::secret_store_endpoint()` reads
  `SharedSecretStoreURL`/`SharedSecretStoreTier` as an **endpoint reference
  only** (never a secret value - `credentials-and-boundary.md` §1.6.4) and is
  fully tested via the dev seam for forced/absent/user-domain-only/
  half-populated cases. **Reconciled to D4:** this reader currently reads
  from the old forced/managed preferences domain, which D4 drops. Per D4 the
  endpoint should instead be delivered via **signed, inherited org config**
  (a field the seed generator emits into `ecosystem.yml`) - that rehoming is
  a pending code change, not yet done (`standup-runbook.md` step 2 flags the
  same gap). Once rehomed, the actual production URL and which tier scheme a
  real org uses remains an infra decision outside this app's scope; nothing
  in this milestone hard-codes or guesses one.

## 6. G-M5-3 render-vs-invoke freeze decision (cross-referenced from §3)

Restated because it's the one open architectural question (ADR-M5-002 status:
"Accepted (with G-M5-3 open)") rather than a pure infra/credential gate: a
CLI-owner ruling on invoke-vs-render changes `routing::deprovision_trigger`'s
implementation, not just its documentation, if the answer is "render only."
Its trigger condition changed under D4 (see §3 above); the invoke-vs-render
question itself did not.

## What is NOT on this list (already closed, verified this session)

- The no-wipe-logic (FF-M5-2), IT-only routing (FF-M5-3), and no-secret-in-
  config (FF-M5-7) findings are all code-complete, genuinely mutation-tested
  (not tautological), and green under `cargo test`/`cargo test --release` - see `scratchpad/qa-m5-acceptance.md`. The forced-domain-specific findings
  (FF-M5-1 consolidated boundary, FF-M5-5 forced-domain-only registry,
  FF-M5-6 generator/reader domain match) are still technically green but
  test code that D4 supersedes; they are not evidence of anything the
  target model still needs.
- `settings::guard::DENIED_KEYS` denies `sharedsecretstoreurl`/
  `sharedsecretstoretier`/`loginitemmanaged` (the gap `managed::keys`'s own
  module doc flagged at freeze) - confirmed closed, not just flagged. This
  guard remains correct under D4 regardless of where the endpoint value
  eventually gets rehomed to.
