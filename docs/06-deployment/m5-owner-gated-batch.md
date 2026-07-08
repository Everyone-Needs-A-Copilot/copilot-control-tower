# M5 owner-gated batch (MDM & Security)

> **Status: build input, not a report.** Everything below is code-complete and
> verified against mocks/fixtures/dev-seams by `cargo test` (see
> `scratchpad/qa-m5-acceptance.md` for the verification session that produced
> this list). None of it can be exercised further by an automated session —
> each item needs a human with real credentials, a real managed Mac, or a
> real MDM console. Nothing here blocks M5 code-complete; everything here
> blocks *real-world* activation.

## 1. Real forced-domain / MDM enrollment

- Enroll a Mac in a real MDM (Jamf/Kandji/Intune) and push a `.mobileconfig`
  that actually sets `CFPreferencesAppValueIsForced` for
  `com.everyoneneedsacopilot.controltower` — the ONLY way to exercise
  `managed/forced.rs`'s real `CFPreferencesAppValueIsForced`/
  `CFPreferencesCopyAppValue` FFI calls end to end. Today `cargo test` proves
  the FFI binding compiles/runs (returns `false`/`Absent` on an unmanaged dev
  box, per `managed::forced`'s own `on_this_unmanaged_dev_machine_no_registry_key_is_forced`
  test) and that the pure `resolve_string`/`resolve_bool` decision logic is
  correct for all three `ForcedLookup` variants (via the `CT_FORCED_OVERRIDE_*`
  dev seam) — never that a real MDM push is actually honored as `Forced`.
- **G-M5-1 domain-name reconciliation** (found and confirmed live, not just
  theorized): `tauri.conf.json`'s `identifier` and
  `managed::keys::APPLICATION_ID` are both, correctly,
  `com.everyoneneedsacopilot.controltower` — the code-authoritative domain,
  pinned by `managed::keys::tests::application_id_matches_the_tauri_bundle_identifier`.
  `docs/01-architecture/architecture.md` (3 call sites) and
  `docs/06-deployment/README.md` still say `dev.enac.controltower`. Reconcile
  the docs to the code domain — do not change the code to match the docs.

## 2. Real `SMAppService` approval on a signed bundle

- `loginitem::smappservice`'s `LoginItemService` real implementation (backed
  by `objc2-service-management`) is exercised in `cargo test` only through
  the `LoginItemService` trait's fake (`FakeService` in `loginitem/mod.rs`'s
  own tests). The real approval-state transitions —
  does an unmanaged `register()` genuinely prompt Bob; does a
  `com.apple.servicemanagement` managed payload genuinely force-approve and
  make the item non-toggleable (closing B-H3) — need a signed, notarized
  `.app` running on a real Mac (managed, for the force-approve half).

## 3. Real `cc deprovision` — CLI-repo sandbox only, NEVER this app / `~/.claude`

- Every deprovision-path test in this crate (`deprovision::run_deprovision`,
  `routing::deprovision_trigger`) drives the mock `fixtures/mock-cc` via the
  `CT_CLI_PATH`/`CT_FIXTURE` dev seam. The real `cc deprovision <org> --json`
  contract — including the soft-then-hard debounce/settling window, which is
  entirely CLI-side per ADR-M5-002 — must be exercised in the **CLI repo's
  own tmp sandbox**, never against a real `~/.claude`, and never from this
  app's test suite (this app must never gain a test that can wipe a real
  personal working tree).
- **G-M5-3, still open (Proposed, not Accepted) — flag to the CLI owner at
  freeze**: does the app *invoke* `cc deprovision` (current implementation,
  `routing::deprovision_trigger::route_deprovision_trigger_for` calling
  `deprovision::run_deprovision`), or only *render* a deprovision an
  MDM-run agent/CLI already performed out of band? The current build follows
  render-not-invoke's spirit (zero wipe/retain logic anywhere in this crate,
  FF-M5-2) but does *invoke* the CLI process — because no second
  "read an already-computed result without invoking" schema/seam exists
  today. `deprovision::run_deprovision`'s own module doc names this exact
  open question. Needs a CLI-owner ruling, not an app-side guess.

## 4. Real notifications-profile authorization

- `mobileconfig::generator`'s `com.apple.notificationsettings` payload
  (pre-authorizing the safety-escalation channel per architecture.md §9) is
  proven well-formed XML (`plutil -lint` clean) and byte-stable against the
  checked-in golden fixture, but was never pushed to a real Mac to confirm
  macOS actually honors it as a silent notifications grant.

## 5. The secret-store endpoint value itself

- `managed::secret_store::secret_store_endpoint()` reads
  `SharedSecretStoreURL`/`SharedSecretStoreTier` as an **endpoint reference
  only** (never a secret value — `credentials-and-boundary.md` §1.6.4) and is
  fully tested via the dev seam for forced/absent/user-domain-only/
  half-populated cases. The actual production URL + which tier scheme a real
  org uses is an infra decision outside this app's scope; nothing in this
  milestone hard-codes or guesses one.

## 6. G-M5-3 render-vs-invoke CLI freeze decision (cross-referenced from §3)

Restated because it's the one open architectural question (ADR-M5-002 status:
"Accepted (with G-M5-3 open)") rather than a pure infra/credential gate: a
CLI-owner ruling on invoke-vs-render changes `routing::deprovision_trigger`'s
implementation, not just its documentation, if the answer is "render only."

## What is NOT on this list (already closed, verified this session)

- The consolidated forced-domain boundary (FF-M5-1), no-wipe-logic (FF-M5-2),
  IT-only routing (FF-M5-3), login-item/watchdog delineation (FF-M5-4),
  forced-domain-only registry (FF-M5-5), generator/reader domain match
  (FF-M5-6), and no-secret-in-config (FF-M5-7) are all code-complete,
  genuinely mutation-tested (not tautological), and green under
  `cargo test`/`cargo test --release` — see `scratchpad/qa-m5-acceptance.md`.
- `settings::guard::DENIED_KEYS` denies `sharedsecretstoreurl`/
  `sharedsecretstoretier`/`loginitemmanaged` (the gap `managed::keys`'s own
  module doc flagged at freeze) — confirmed closed, not just flagged.
