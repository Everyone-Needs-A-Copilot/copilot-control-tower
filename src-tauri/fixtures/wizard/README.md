# M3 wizard fixture corpus + the `mock-cc auth` device-flow seam

Drives the first-run wizard's sign-in step and end-to-end scenarios without a real
`cc`, real OAuth, or a real fleet. Referenced by the M3 architecture WP
(`.copilot/wp/15.md` §0, §2 S3/S4/S5/S8, §3 ADR-M3-001, §4 fitness fn 2) and consumed
by Stream-A (`src-tauri/src/wizard/`, Rust orchestration + DTO), Stream-B (the wizard
web UI), and Stream-Z's own integration/Playwright tests.

**This corpus is deliberately NOT validated against a frozen upstream JSON Schema.**
Per the WP §0, `cc auth --json` has no schema yet — the real verb doesn't exist
(D-3-M3, batched to WS-A). What's frozen instead is the **SHAPE** documented below
(ADR-M3-001: build against a dev-mockable seam now, batch the real verb + its formal
schema later). `validate.py`/`validate.sh` in this directory pin down that SHAPE
mechanically so a regression here is caught the same way the sibling doctor corpus
catches schema drift.

## Layout

```
src-tauri/fixtures/wizard/
  README.md              this file
  validate.sh            runs validate.py — green on the auth seam + scenario corpus
  validate.py            the actual validator (Python, no external packages needed)
  products.sample.json   sample ecosystem.yml-derived product list (ADR-M3-005, S5)
  scenarios/             *.json — one manifest per end-to-end wizard scenario
```

The `mock-cc` executable itself lives one directory up
(`src-tauri/fixtures/mock-cc`) — it now serves **both** the M1/M2 doctor corpus
(`corpus/`, `invalid/`) **and** the M3 `auth` seam below, from one binary, exactly
like the real CLI would.

## The `mock-cc auth` seam (the frozen SHAPE, ADR-M3-001)

Two phases, mirroring the standard OAuth device flow (RFC 8628):

### 1. Initiate — `mock-cc auth --json` (or the alias `mock-cc auth login --json`)

Always emits the same canned ceremony, regardless of scenario (the outcome hasn't
happened yet when this call is made):

```json
{"user_code":"WDJB-MJHT","verification_uri":"https://example.com/device","expires_in":900,"interval":5}
```

`auth login` is accepted as a byte-identical alias for `auth` — this reconciles the
WP §0 design inconsistency: the wizard's host/GitHub sign-in step is described
elsewhere as "poll `gh auth status`" (a screen-scrape of human CLI output — Case Law
OUT). D-3-M3 recommendation #2 replaces that with treating GitHub identity as one
more `cc auth <integration> --json` integration; `auth login` is the mock's stand-in
for that reconciled verb name.

### 2. Poll — `mock-cc auth --json --poll`

Emits a single-key JSON object carrying only the terminal (or interim) status:

```json
{"status":"authorized"}
```

`status` is one of `authorized | denied | expired | timeout | pending`. `pending`
means still waiting — the Rust seam should keep polling at the ceremony's `interval`
seconds; the other four are terminal.

**No token is ever emitted.** The app must hold nothing (invariant #6): on
`authorized` the CLI has already written the credential to the keychain itself; the
app only learns the outcome. This is why the poll body has exactly one key,
enforced by `validate.py`.

### Scenario selection

Checked in this order (mirrors the existing `$CT_FIXTURE` convention exactly):

1. `--scenario=<name>` / `--scenario <name>` on the command line
2. `$CT_AUTH_SCENARIO`
3. `$CC_AUTH_SCENARIO` (alias)
4. `authorized` (default — an unconfigured run is still deterministic)

```bash
# initiate (scenario doesn't matter yet)
src-tauri/fixtures/mock-cc auth --json

# poll, happy path
CT_AUTH_SCENARIO=authorized src-tauri/fixtures/mock-cc auth --json --poll

# poll, each honest-failure variant
CT_AUTH_SCENARIO=denied  src-tauri/fixtures/mock-cc auth --json --poll
CT_AUTH_SCENARIO=expired src-tauri/fixtures/mock-cc auth --json --poll
CT_AUTH_SCENARIO=timeout src-tauri/fixtures/mock-cc auth --json --poll

# poll, still waiting (spinner state, not a failure)
CT_AUTH_SCENARIO=pending src-tauri/fixtures/mock-cc auth --json --poll

# simulate the env-error / exit-2 path
CT_AUTH_SCENARIO=exit-2 src-tauri/fixtures/mock-cc auth --json --poll

# the ONE adversarial negative-test scenario — see below
CT_AUTH_SCENARIO=authorized-leaked-field-adversarial src-tauri/fixtures/mock-cc auth --json --poll
```

**Exit codes** (only two apply to `auth` — there's no per-checker `severity` concept
here, unlike `doctor`):
- `0` — normal. This **includes** `denied`/`expired`/`timeout`/`pending` — those are
  expected, honest terminal/interim outcomes, not environment errors.
- `2` — env error: `CT_AUTH_SCENARIO=exit-2`, or an unrecognized scenario name (fails
  closed rather than guessing).

### The adversarial scenario: `authorized-leaked-field-adversarial`

The **real** `cc auth` verb will never emit a token to the app. This one scenario
exists purely as a **negative-test fixture** for fitness function 2
(no-secret-on-wizard-DTO, WP §4): it emits an otherwise-normal `authorized` poll
response plus one extra, obviously-synthetic field —

```json
{"status":"authorized","access_token":"FAKE-SYNTHETIC-NOT-A-REAL-TOKEN-0000000000"}
```

Feed this through the Rust seam's parser and assert the resulting
`WizardState`/`SigninState` DTO has no `access_token` field and the literal string
never appears anywhere the app could render or log it. The field name and value are
both deliberately unrealistic and are never reused by any other scenario —
`validate.py` asserts this constant hasn't drifted into something more
realistic-looking, which would defeat the point of the test.

## Wizard scenario corpus (`scenarios/`) — one manifest per end-to-end path

Each file is a small, human-and-machine-readable manifest: which env vars to export
to point the app at `mock-cc` (reusing the existing `CT_CLI_PATH` mechanism), which
scenario/fixture combination to drive it with, and what the wizard is expected to do.
These are **not** part of the frozen CLI contract — they're QA-authored test
manifests for Stream-A/Stream-Z's own unit/integration/Playwright tests to consume or
mirror; `fixture_version` marks them as such.

| File | Path | What it exercises |
|---|---|---|
| `managed-silent-healthy.json` | managed | The Silent First Light happy path: valid MDM profile (reuses `../settings/valid-multi-layer.yml`), 0 questions, `Done` gated on a fresh `doctor status:healthy` (reuses `corpus/healthy-clean-fleet.json`). |
| `managed-silent-holding-malformed-profile.json` | managed | Present-but-invalid MDM profile (reuses `../settings/invalid-missing-required-field.yml`) → **immediate** `Holding(ItConfigIncomplete)`, never a retry, never Healthy. |
| `managed-silent-holding-profile-absent.json` | managed | MDM profile not yet delivered → settling-window retry, then honest holding — never a silent fallback to unmanaged, never a fabricated Healthy. |
| `managed-silent-holding-waiting-for-network.json` | managed | Valid profile, offline/no network yet (reuses `corpus/waiting-for-network-startup.json`) → `Holding(WaitingForNetwork)`, distinct from a confirmed `offline` verdict. |
| `unmanaged-guided-healthy.json` | unmanaged | The ≤3-question guided path: product-first Q1 (see `products.sample.json`, ADR-M3-005), sign-in Q2 (`CT_AUTH_SCENARIO=authorized`), company+department-picklist Q3, `Done` on fresh `doctor status:healthy`. |
| `signin-denied-holding.json` | unmanaged | User denies the device-flow request → reuses the **existing** doctor `signed-out` render (`corpus/signed-out-claude-personal.json`), never a fabricated success, never a raw OAuth error string. |
| `signin-expired-holding.json` | unmanaged | `user_code` ceremony expires before completion → same honest `signed-out` render. |
| `signin-timeout-holding.json` | unmanaged | Poll loop times out (not a user decision, e.g. a transient network issue) → same honest `signed-out` render. |
| `signin-pending-in-progress.json` | unmanaged | Still polling, not yet terminal — the spinner state. **Not** a failure; distinct from the three variants above. |
| `signin-adversarial-leaked-field.json` | unmanaged | NEGATIVE TEST ONLY — see "the adversarial scenario" above. |

All three failure variants (`denied`/`expired`/`timeout`) deliberately converge on the
**same** render target — the app never differentiates auth-failure causes with
different UI severity beyond the existing doctor `signed-out` state, which already
anticipates the `cc auth login` repair token
(`corpus/signed-out-claude-personal.json`'s checker: `"repair": "cc auth login"`).

## Running the validator

```bash
src-tauri/fixtures/wizard/validate.sh
```

No external Python packages required (unlike the sibling `../validate.sh`, which
needs `jsonschema`/`referencing` — there's no upstream schema to validate `auth`
against yet). Checks, in order:

1. `mock-cc auth --json` and `mock-cc auth login --json` emit byte-identical ceremony
   bodies with exactly the four documented keys and no secret-shaped field.
2. `mock-cc auth --json --poll` for every scenario (`authorized`/`denied`/`expired`/
   `timeout`/`pending`) emits exactly `{"status": "<scenario>"}` at exit 0; `exit-2`
   and an unknown scenario name both fail closed at exit 2 with no stdout body; the
   adversarial scenario carries exactly the documented synthetic poison and nothing
   more realistic.
3. Every `scenarios/*.json` manifest has its required keys, its `env.CT_FIXTURE`
   resolves to a real `../corpus/` or `../invalid/` doctor fixture, its
   `managed_profile_fixture` (if any) resolves to a real `../settings/*.yml` file, and
   it carries no secret-shaped key outside the one documented adversarial exception.
4. `products.sample.json` is well-formed with unique product ids.

## How S3/S4/S5/S8 wire the app to it

Same dev-override mechanism as the doctor corpus — `cli::path.rs`'s `CT_CLI_PATH`
special case, extended to the `auth` verb:

```bash
CT_CLI_PATH=/absolute/path/to/src-tauri/fixtures/mock-cc \
CT_AUTH_SCENARIO=<scenario-name> \
  <run the Tauri app / test harness in dev>
```

- **S3** (sign-in device-flow seam, sec-owned): spawns `mock-cc auth --json` for
  initiate and `mock-cc auth --json --poll` on a loop for poll, via
  `cli::path::resolve()` — never a bare `cc`/`mock-cc` name (fitness fn 3, reused from
  M1/M2). Parses the ceremony into `SigninState{status, user_code, verification_uri}`
  — the exact three fields `fitness_no_secret_on_wizard_dto.rs`'s
  `signin_state_has_exactly_the_frozen_render_fields` test already asserts as the
  closed field set. Run the adversarial scenario through this same parse path to
  prove the extra field never survives into the DTO.
- **S4** (managed silent orchestration): points `CT_MANAGED_OVERRIDE=1` (M2's
  dev/test-only override, `cfg(any(debug_assertions,test))`-gated, never in a release
  build) at one of the three `managed-silent-*` scenario manifests above, reusing the
  referenced `../settings/*.yml` fixture for profile validation and the referenced
  `../corpus/*.json` fixture for the post-materialize doctor re-poll.
- **S5** (unmanaged guided first-run): points `CT_MANAGED_OVERRIDE=0` at
  `unmanaged-guided-healthy.json`, using `products.sample.json` to drive the
  product-first Q1 (ADR-M3-005) and `CT_AUTH_SCENARIO=authorized` to drive Q2 to
  completion before `Done`.
- **S8** (wire wizard UI ↔ live orchestration end-to-end): drives the full set of
  `scenarios/*.json` — managed and unmanaged, happy path and every documented holding
  state — through the live IPC/orchestration path in Playwright-headless, asserting
  each scenario's `expected.*` block against the rendered DTO. A partial failure must
  hold honestly (per-scenario `expected.reaches_done: false`), never fabricate
  `Done`/Healthy.

## Verification run (this session)

```bash
src-tauri/fixtures/validate.sh          # sibling doctor corpus — unchanged, still green
src-tauri/fixtures/wizard/validate.sh   # this corpus — auth seam shape + scenario corpus
```

Both must exit 0. `cargo test` in `src-tauri/` also exercises the wizard DTO fitness
functions (`fitness_no_secret_on_wizard_dto.rs`, `fitness_no_eta_in_wizard.rs`) against
Stream-A's `src/wizard/dto.rs` — those assert against the Rust struct definitions
directly and are outside this fixture corpus's ownership (Stream-A owns `src/wizard/`;
this directory is Stream-Z/qa-owned per the WP's file-ownership map).
