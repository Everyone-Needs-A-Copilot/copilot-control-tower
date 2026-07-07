# Test & QA Strategy — Copilot Control Tower

| | |
|---|---|
| **Status** | Proposed — first version, written pre-P0 (no app code exists yet; this is the target test architecture the workstreams build against) |
| **Scope** | Operator mode + Admin mode, macOS-first (Windows/P4 noted, not detailed) |
| **Test basis** | [`30-acceptance-criteria.md`](../product-design/03-requirements/30-acceptance-criteria.md) (29 FC + 9 DQ criteria), [`20-use-cases-and-scenarios.md`](../product-design/03-requirements/20-use-cases-and-scenarios.md) (7 E2E scenarios, E1–E22, 5 Critical Views), [`cli-contract.md`](../01-architecture/cli-contract.md), [`architecture.md`](../01-architecture/architecture.md), [`prd.md`](../02-prd/prd.md), [`CLAUDE.md`](../../CLAUDE.md) invariants |
| **No time estimates** | Everything below is phased (P0–P4) and prioritized (Critical/High/Med), never hours/days/sprints, per project convention |

> **Why this doc exists.** The whole safety model rests on one claim — "Control Tower parses, it never computes" — and one artifact — the versioned `--json` contract between the CLI and the app. Until now that claim was prose (`architecture.md` §6, `cli-contract.md`) with no test named. This doc turns it, and the three hardest acceptance criteria (DQ-1/2/3), into concrete, runnable checks, and maps all 29 acceptance criteria + 29 scenarios to the test type that covers them.

---

## 1. Test strategy & the pyramid

Control Tower is a Tauri v2 app: a Rust core (state machine, CLI spawner/parser, timers, MDM-preference reader) plus a deliberately tiny web UI (tray menu, wizard, dashboard). It supervises an external process (`copilot`/`cc`) it must never fully trust to be well-behaved and must never re-implement. That shape drives four test layers, weighted like a pyramid — most tests at the bottom, fewest at the top:

```
                    ▲  E2E (tray / wizard / dashboard)          — fewest, slowest, highest confidence per test
                   ╱ ╲
                  ╱   ╲   Contract test (CLI --json ↔ schemas/) — small in count, but LOAD-BEARING (blocks release)
                 ╱     ╲
                ╱       ╲  Integration (Rust core ↔ mock CLI)  — many, fast, no real `copilot` binary needed
               ╱         ╲
              ╱───────────╲ Unit (parsing, state machine, routing) — most, milliseconds, pure functions
```

### 1.1 Unit tests (Rust, most numerous)

Target: pure functions with no process spawn, no filesystem, no network.

- **JSON→state parsing** (`cli::parse_doctor`, `parse_update`, `parse_resolve`, `parse_freshness`, `parse_publish`): given a `serde_json::Value` fixture, assert the typed struct or the fail-closed error it produces. One test per field per fail-closed rule (missing `destructive`/`signed`/`severity_trailer`/`leak_scan`/`tier` ⇒ treated as unsafe, never defaulted to safe).
- **Status state machine** (`state::reduce`): given a set of per-host `doctor` results + auth + network flags, assert the rendered state and precedence (`IT-config-incomplete > Signed-out > Needs-attention > Offline > Syncing > Update-available > Healthy`), and that it **only** transitions from a fresh CLI payload (no default-to-last-good, no client-side inference).
- **Escalation router** (`escalate::route`): given an event class + reversibility + actor-competence inputs, assert it lands in exactly one of `auto-act` / `escalate-it` / `ask-bob` (FC-9, FC-12, FC-14, FC-16, §9 of `architecture.md`).
- **Schema gate** (`schema::gate`): given `schema_version` vs. the app's compiled `min_schema`/`max_schema`, assert fail-closed on both older-than-floor and newer-than-ceiling (FC-26, E6, B-H6).
- **Managed-preference reader** (`prefs::read_security_key`): given a stub `CFPreferences`-shaped double that reports a value present-only-in-user-domain vs. forced/managed, assert the security-sensitive keys (`UpdateFeedURL`, `FoundationMirror`, `EcosystemSeedURL`, `HTTPSProxy`, `GitHubHost`, `AuthMode`, `AllowSelfUpdate`, `Deprovisioned`) are **ignored** unless `CFPreferencesAppValueIsForced` is true, and a tamper event is logged (FC-27, E7, B-C5).
- **Property-based tests** (proptest/quickcheck-style, on the parser and the state reducer):
  - *Idempotence:* `reduce(reduce(s, evt), evt) == reduce(s, evt)` — replaying the same fresh JSON twice never flips state.
  - *Monotonic fail-closed:* for any fixture, deleting a security-relevant field never makes the parsed result **more** permissive (mutate-and-assert: strictly-equal-or-more-restrictive severity).
  - *No fabricated Healthy:* for any generated `doctor` JSON where `status != "healthy"`, `reduce` never outputs the Healthy state (this is the executable form of DQ-1/FC-6, run continuously, not just against curated fixtures).
- **Test doubles used:** Stubs for `CFPreferences`/keychain/network reachability (canned responses, isolate from macOS APIs in unit scope). No Mocks here — nothing in this layer needs interaction verification, only correct transformation of inputs to outputs.

### 1.2 Integration tests (Rust core ↔ a mock CLI, majority of confidence-per-test)

A **mock `copilot` binary** (a small Rust or shell shim, `tests/fixtures/mock-copilot/`) that: accepts the real verb/flag surface (`doctor --json`, `update --json`, `resolve --explain --json`, `deprovision <org> --json`, `freshness --json`, `publish --json --resolve <choice>`), returns a **fixture JSON** selected by an env var or a scripted sequence, and can simulate the real CLI's `flock` behavior (hold `copilot.lock`, exit non-zero if asked to simulate "held"), non-zero exit codes (1/2), and slow/hanging responses.

These tests exercise the **real Rust spawn code path** (`cli.rs`: absolute-path spawn, timeout, `--json` parse, retry/backoff) against the mock, not against unit-level stubs — this is a Fake (a working, in-process re-implementation of the CLI's I/O contract), not a Mock: it isolates the app from the real binary while still exercising the app's actual process-management and parsing logic end to end.

Representative suites:
- **Timer/poll loop**: mock advances a fake clock; assert sync ~6h / doctor ~1h / freshness ~15m cadence, coalescing (no overlapping in-flight calls), and battery/metered backoff (feed a stub power-state Fake) — B5.
- **Auto-heal (FC-9)**: mock returns `freshness --json {stale:true}` then a healable `fail`; assert `repair` is invoked with no prompt, and an unknown/non-parseable class instead escalates and is excluded from the auto-heal denominator.
- **Session-active backoff (FC-10, E18)**: mock reports a live host session; assert a non-security `update` is deferred, not blocked, and applied once the session-live signal clears; assert a `security` trailer is **not** deferred.
- **flock contention (E15, B-C1)**: mock simulates `copilot.lock` already held; assert the app surfaces the CLI's fail-fast exit rather than retrying with a lock of its own — see §4's DQ-3-adjacent check for the assertion that the app **never opens/holds a lock file itself**.
- **Deprovision (FC-24, Scenario 6)**: mock returns `secrets_touched: 0` and a soft-then-hard sequence; assert the app renders quarantine → wipe without initiating either phase itself (it only reports).
- **Publish conflict rendering (cli-contract.md `publish --json`)**: mock returns each of `auto-merged` / `needs-choice` / `parked-escalated`; for `needs-choice`, assert the app renders **rendered content**, never raw Git markers, and that the human's pick is passed back verbatim as `--resolve <choice>` with **no merge computed app-side**.
- **Test doubles used:** the mock CLI is a **Fake**. Where a test needs to verify the app called a specific verb with specific flags (e.g., "menu 'Repair' spawns `copilot repair --json`, nothing else" — FC-11), a **Spy** wrapping the mock records invocations for assertion — this is the one place interaction-verification (not just state-based assertion) is the right tool, per the taxonomy (Meszaros): the requirement *is* "only these verbs get spawned."

### 1.3 The contract test (load-bearing — described concretely)

This is the test the whole safety model rests on, per `cli-contract.md`: *"A CI contract test in the `copilot` repo asserts every `--json` command matches the published schema on every release... schema drift = silent security bypass."* Today that's a sentence. Concretely, it is **two tests in two repos that must both exist and both stay green**, plus a shared fixture corpus:

1. **Producer-side contract test (lives in the `copilot`/`claude-copilot` repo, WS-A, task A6).** Runs the *real* CLI binary for every consumed verb (`doctor`, `update`, `resolve --explain`, `deprovision`, `freshness`, `publish`) against a set of scripted repo/lock states, captures the real `--json` output, and validates it against the versioned JSON Schema in `docs/01-architecture/schemas/` (schema per verb, `schema_version`-keyed). Any field drift, added/removed required field, or type change fails the build. **This is the test named in `cli-contract.md`'s Acceptance section — it must exist before WS-B onward begins (P0 gate).**
2. **Consumer-side contract test (lives in this repo, Control Tower).** Takes the **same schema files** (vendored/synced from `copilot`, pinned by version — the schemas are the shared artifact, not duplicated by hand) and validates that the Rust `serde` structs the app deserializes into are a **structural match**: every field the schema marks required is non-`Option` in the Rust type (or explicitly handled as fail-closed-if-absent); every field the schema marks security-relevant (`destructive`, `signed`, `severity`, `severity_trailer`, `shadowed_by`, `leak_scan`, `tier`) has an explicit fail-closed test (§1.1) proving its absence is treated as unsafe. This test also runs against the **fixture corpus** (§4) offline, so it doesn't require a live CLI, and is the one that catches "the app's assumption about the schema silently diverged from what the schema now says."
3. **Bidirectional schema-version gate test.** Feeds `schema_version` values below `min_schema`, above `max_schema`, and in-range, and asserts fail-closed on both out-of-range ends (FC-26, E6, B-H6) — this closes the "gate is one-directional" red-team finding explicitly.

**Status of this artifact today:** `docs/01-architecture/schemas/` now **exists** as versioned draft schemas (one per verb + a shared `_envelope`), derived from `cli-contract.md` prose with encoded assumptions flagged via `$comment`. The consumer-side contract test can therefore be built against them now — but they are **not yet frozen**: they must be reconciled with WS-A's CLI-published authoritative contract (notably `repair`, which `cli-contract.md` gives no `--json` shape and whose schema is a full reconstruction). Treat the current schemas as the working source of truth pending that WS-A reconciliation.

### 1.4 E2E tests (tray / wizard / dashboard, fewest, highest confidence per test)

Tauri's webview surfaces (wizard, dropdown "What changed" panel, Admin fleet dashboard) are testable via `tauri-driver` (WebDriver over the embedded webview) driving the actual UI, with the mock CLI (§1.2) backing it so the whole stack runs without a real `copilot` binary or network. **The native tray icon / NSStatusItem menu itself is not WebDriver-reachable** — it needs either a thin Rust-side test hook (an IPC command the E2E harness calls to assert "menu action X was armed to spawn verb Y" using the same Spy from §1.2) or macOS accessibility-API-driven UI automation for a smaller, Critical-View-only smoke set. This plan uses the former (cheaper, deterministic) for coverage and reserves the latter for a manual/exploratory Critical-View pass per release, not CI.

Required for every UI change per this repo's testing floor: **zero console errors** in the webview, user interactions produce the expected state transition end-to-end (mock CLI → parse → render), and a visual check against the 5 Critical Views (CV-1..CV-5, `20-use-cases-and-scenarios.md`) for the honest-state renderings (no path to a fabricated Healthy, distinct badge+text per non-Healthy state, never color-alone — FC-8, Quality Criteria "Accessibility").

E2E suites, one per Critical View + one per E2E scenario (§6 has the full mapping):
- CV-1 icon/status sentence: render each state from a mock `doctor --json`, assert the exact plain-language sentence naming the failing host where applicable (FC-7, E21).
- CV-2 wizard: silent-managed zero-question path (mock a complete forced-domain profile); ≤3-question unmanaged path; fail-closed IT-config-incomplete; Waiting-for-network hold; resume-after-quit from a persisted checkpoint.
- CV-3 dropdown/what-changed: Sync now/Repair/Sign-in spawn the right verb only (Spy-verified); security-shadow past-tense message; prune-of-used-item notice vs. silent zero-usage prune.
- CV-4 Admin fleet dashboard: healthy/stuck/behind/needs-auth categorization from mock fleet data; version-skew panel; held-major-awaiting-IT card; persistence-disabled card.
- CV-5 Admin setup + preflight: seed generator → scaffolding → MDM profile generator → preflight, including a red preflight on a declared-repo 404 (FC-19).

**Test doubles used:** the mock CLI (Fake) throughout; a Spy for verb-invocation assertions (FC-11). No Mocks — nothing here requires asserting a call happened in a particular order for its own sake; state-based assertion (rendered text/badge/state) is preferred and is what the requirement actually says.

---

## 2. CI matrix

| Job | Runs on | Trigger | Layer |
|---|---|---|---|
| **Rust unit tests** | macOS runner (Rust toolchain only, no Xcode signing needed) | every PR | §1.1 |
| **Rust integration tests (mock CLI)** | macOS runner | every PR | §1.2 |
| **Consumer-side contract test** | macOS runner, pinned schema version from `copilot` | every PR + nightly against `copilot`'s latest tagged schema | §1.3.2 |
| **Producer-side contract test** | *lives in the `claude-copilot`/`copilot` repo*, not here — this repo only consumes its published schema artifact | on every `copilot` release (their CI) | §1.3.1 |
| **Schema-version gate test** | macOS runner | every PR | §1.3.3 |
| **Static-analysis / parse-never-compute gate** | macOS runner, `cargo clippy` + a custom lint/grep pass (see §3, DQ-3) | every PR, blocking | code-review gate |
| **E2E (tauri-driver)** | macOS runner (webview requires macOS; no Linux headless substitute for this app) | every PR touching UI (`src/`, wizard, dashboard) | §1.4 |
| **Signing/notarization smoke** | macOS runner with Developer ID cert in CI secrets | on tag/release build only (not every PR — cert-gated) | D1/D2 (distribution, adjacent to this doc, owned by WS-D) |
| **Manual Critical-View accessibility pass** | a real Mac, a human | before each release | CV-1..CV-5 tray-menu portion not reachable by `tauri-driver` |

**Notes:**
- **macOS-first, by necessity, not just by priority** — the tray, `SMAppService`, `launchd`, Keychain, and the webview itself are all macOS APIs; there is no meaningful Linux/Windows substitute for most of this matrix today.
- **Windows (P4 re-skin) is out of this matrix for now.** When P4 starts, the CI matrix gets a second column (Windows runner) for the six boundary shims (tray, Task Scheduler, EV/SmartScreen, MSI/winget, Credential Manager, Intune/GPO) — §1.1/§1.2/§1.3 (parsing, state machine, contract test) are **platform-independent by design** (pure Rust) and should need zero changes; only §1.4 (E2E) and the shims need Windows-specific suites. This is deferred, not designed in detail here, per P4 phasing.
- **No test in this matrix ever spawns a real `flock` against a real `copilot.lock` on a developer's actual `~/.copilot` tree.** All lock-contention behavior is exercised against the mock CLI (§1.2) or a scratch directory, never a real ecosystem tree — this matters because CLAUDE.md's never-destroy invariant extends to CI hygiene: tests must not have a blast radius onto anything resembling a real personal working tree.

---

## 3. Instrumenting the three hardest acceptance criteria

These three are flagged in `30-acceptance-criteria.md` as **not thresholds — any violation is a Critical regression**, and explicitly called "hardest to verify." Each needs an instrument beyond ordinary test-writing.

### DQ-1 — False-Healthy rate = 0 (no sampling tolerance)

**Claim under test:** Healthy is never rendered over a foundation-only / mis-provisioned / drifted machine.

**Instrumentation, two layers:**
1. **Pre-field (CI), exhaustive by construction, not sampled.** The property test in §1.1 (*"No fabricated Healthy"*) runs the state reducer against every fixture in the corpus (§4) plus property-generated mutations, and asserts: **for every input where the fixture's `status != "healthy"` (or a required security field is absent/malformed, or the profile fails schema validation, or network is down on a foundation-only first run), the reducer's output is never the Healthy variant.** Because this is a property over the *entire* input space the fixture generator can reach — not a fixed list of scenarios — it is the closest CI can get to "no sampling tolerance": a single counterexample the generator finds is a failing build, not a flaky test to quarantine.
2. **Field (post-release), an out-of-band ground-truth oracle.** Per the QA instrumentation note in `30-acceptance-criteria.md`: an independent process (not Control Tower, not sharing its code path) runs `copilot doctor --json` directly against each fleet machine on the same cadence as telemetry, and cross-checks its verdict against every `status: healthy` the fleet dashboard (G3) recorded for that machine at that timestamp. Any mismatch (oracle says not-healthy, dashboard recorded Healthy) is filed as a **Critical regression**, not a metric that tolerates a rate. This oracle is a separate, small CLI-invocation script — deliberately **not** built on Control Tower's own parser, so a bug shared between "the thing being tested" and "the thing testing it" can't hide a false-Healthy from both.

### DQ-2 / FC-16 — Security-shadow auto-suspend coverage = 100%

**Claim under test:** a `security:`-trailered fix always wins over a stale personal override, before any Bob-facing signal, in every environment Bob might be in.

**Instrumentation — an adversarial injection harness**, a dedicated integration suite (`tests/adversarial/security_shadow.rs`) that:
1. **Seeds** a stale override for an item, then feeds the mock CLI (§1.2) an `update --json` with `changed[{severity_trailer: "security", shadowed_by: <the override>}]`.
2. **Crosses it with every relevant environment permutation** — the full matrix, not a happy-path sample:
   - Focus/DND: on / off
   - Notification permission: granted / denied
   - Host state: Claude only / Codex only / both / neither
   - Session-live: yes / no (interacts with FC-10's session backoff — assert security is **exempt** from the backoff even under this permutation)
3. **Asserts, for every cell of the matrix**, in this order: (a) the auto-suspend action fires and the fixed version is live in the app's resolved state **before** (b) any user-facing signal is even attempted, and (c) the IT escalation fires in parallel regardless of Focus/DND/notification-denied (it does not depend on the same channel Bob's notification depends on).
4. **Field cross-check:** the escalation-router audit log (append-only, hash-chained per `architecture.md` §9/§10 B-L2) is diffed against every published `security:` trailer in the upstream feed; any published security trailer with no corresponding audit-log auto-suspend entry is a Critical finding.

This directly operationalizes the acceptance note ("adversarial test harness... across host/Focus/notification-denied permutations... assert the fixed version is live before any user-facing signal") and closes red-team C3/A-C3.

### DQ-3 / FC-25 — Parse-never-compute = 0 lines

**Claim under test:** the app contains zero resolution/health/signature/merge/wipe logic — every decision is the CLI's.

This is explicitly **not behaviorally testable** (`30-acceptance-criteria.md`: *"Not testable by behavior alone"*) — a behavioral test can prove the app produces the *right* answer without proving it didn't *compute* that answer itself by accident replicating CLI logic. Instrumentation is two-part:

1. **Static-analysis + code-review gate, every release (blocking CI job, not a nightly advisory).**
   - A denylist lint (a small custom `clippy`-style check, or a grep-based CI script as a first-pass floor) over `src-tauri/src/`: no function bodies performing git merge/rebase operations, no signature-verification primitives (no `ed25519`/`minisign`/hashing-for-trust-decisions outside the vendored-binary-verification path, which is a distinct, allowed concern — verifying the *app's own* signed bundle is not "computing ecosystem state"), no `winning_layer`/conflict-resolution logic, no destructive-file-deletion logic outside calling the CLI's `deprovision`/`repair` verbs.
   - A **required PR checklist item** (code-review gate) for any change touching `cli.rs`, `state.rs`, or the publish-chooser UI: reviewer explicitly confirms no new decision logic was added — this is the human backstop for what the static lint can't catch (e.g., a subtly-reimplemented severity ranking).
2. **Runtime cross-check (the provenance diff, DQ-6).** Materialized content on disk is diffed against `resolve --explain --json`'s reported winning layer/SHA on every run where both are available; a mismatch means *something* wrote content the CLI didn't compute — which is the field-visible symptom of a DQ-3 violation (`30-acceptance-criteria.md`: *"A false-Healthy in the field is the symptom that this broke"* — likewise here, a provenance mismatch is the symptom a parse-never-compute violation produces).
3. **The flock non-ownership test** (ties to invariant #2 and E15/B-C1): an integration test asserts the Rust core **never calls a file-lock syscall** (`flock`/`fs2::FileExt::lock_exclusive` or equivalent) against `copilot.lock` or any ecosystem-tree path — the app only ever *reads* the CLI's reported lock state (`lock_before`/`lock_after` in `update --json`) and never contends for the lock itself. Implemented as a linked-syscall-audit in the integration harness (the mock CLI's lock file is instrumented; assert only the mock process, never the app process, ever holds it) plus the same static-lint pass as above.

---

## 4. Fixture strategy

A versioned corpus, `tests/fixtures/cli-json/`, one directory per verb, each fixture a `{schema_version, ...}` JSON file plus a one-line comment header naming the scenario/finding it represents. This corpus is the **shared input** to unit parsing tests (§1.1), integration tests (§1.2), the consumer-side contract test (§1.3.2), and the DQ-1 property test (§3) — one corpus, many consumers, so a new fixture instantly gets exercised by every layer.

```
tests/fixtures/cli-json/
  doctor/
    healthy.json                       # exit 0, all checkers pass — the ONLY legit path to Healthy
    healthy-both-hosts.json
    warn-healable.json                 # auto-repair path (FC-9)
    fail-one-host.json                 # names the failing host (FC-7/E21)
    fail-unhealable.json               # escalates, excluded from auto-heal denominator
    missing-security-field.json        # absent `destructive` — must fail-closed (FC-6, E6)
    offline-foundation-only.json       # Waiting-for-network (E2/FC-4)
    schema-too-old.json                # below min_schema (FC-26/E6/B-H6)
    schema-too-new.json                # above max_schema
    malformed-hostile.json             # truncated/garbage JSON, wrong types, injection-shaped strings
  update/
    reversible-warn.json               # AUTO-ACT lane (FC-9)
    security-trailer-shadowed.json     # DQ-2/FC-16 seed fixture
    session-active-deferred.json       # FC-10/E18
    prune-recently-used.json           # FC-13/E11 (notify)
    prune-zero-usage.json              # FC-13/E11 (silent)
    held-major.json                    # FC-14/E10
    two-host-partial.json              # FC-7/M14
  publish/
    auto-merged.json
    needs-choice.json                  # rendered content, never Git markers (inheritance-and-publish.md)
    parked-escalated.json
    missing-leak-scan.json             # fail-closed publish refusal
  resolve-explain/
    matches-materialized.json          # DQ-6 happy path
    live-hash-mismatch.json            # "MODIFIED", never stale "signed ✓"
  deprovision/
    clean-wipe.json                    # secrets_touched == 0
    soft-phase-quarantine.json
    hard-phase-wipe.json
  freshness/
    stale-true.json
    stale-false.json
  malformed-and-hostile/               # cross-verb: fuzz-shaped inputs for the parser layer
    truncated.json
    wrong-types.json
    unicode-and-control-chars.json
    oversized-array.json
```

**Provenance rule:** every fixture in this corpus must trace to a criterion or scenario ID in a header comment (e.g. `// FC-16, DQ-2, E8 — security-shadow with stale override`) — this is what makes §6's mapping table auditable rather than aspirational, and what lets a reviewer tell a "just in case" fixture from one that closes a specific gap.

**Growth rule:** every red-team finding closed (§7) and every new criterion added to `30-acceptance-criteria.md` gets a fixture before its corresponding code lands — fixtures are written from the spec, not reverse-engineered from an implementation, so they can catch the implementation being wrong.

---

## 5. Mapping table — acceptance criteria & scenarios → test type

Legend: **U**nit · **I**ntegration · **C**ontract · **E**2E · — not yet coverable (flagged, reason given)

| ID | Criterion / Scenario | Test type(s) | Note |
|---|---|---|---|
| FC-1 | Silent managed first-run | I, E | mock forced-domain profile; assert zero prompts (event-log assertion) |
| FC-2 | Unmanaged ≤3 questions | E | wizard E2E, prompt-count assertion |
| FC-3 | Fail-closed on missing MDM key | U, I, E | schema-validate unit test + wizard E2E for IT-config-incomplete render |
| FC-4 | Waiting-for-network / seed-vs-solo | U, I, E | state-machine unit test + wizard E2E |
| FC-5 | Resume interrupted setup | I, E | checkpoint-persistence integration test + quit/relaunch E2E |
| FC-6 | Honest icon, never false-Healthy | U (property, §3 DQ-1), I | see §3 DQ-1 for the exhaustive instrument |
| FC-7 | Names the failing host | U, E | state reducer unit test + CV-1 E2E |
| FC-8 | Distinct honest states, not color-alone | E (+ manual a11y pass) | CV-1 visual/contrast check; automated contrast tooling + human review |
| FC-9 | Auto self-heal | I | mock-CLI integration (§1.2) |
| FC-10 | Session-active backoff | I | mock-CLI integration, incl. security-exemption case |
| FC-11 | Menu spawns CLI verbs only | I (Spy), E | Spy-verified invocation; no state-mutation code path (static check too) |
| FC-12 | Asked only about own data | I, E | escalation-router unit + wizard/dropdown E2E for the two legitimate prompts |
| FC-13 | Prune-of-used-item notifies | I, E | fixture-driven (prune-recently-used vs prune-zero-usage) |
| FC-14 | Held-major routes to IT | I, E | CV-4 dashboard E2E + router unit test |
| FC-15 | Notification-denied fallback | I, E | stub notification-permission state; assert popover fallback + IT re-route |
| FC-16 | Security-shadow auto-suspend | **adversarial harness (§3 DQ-2)** | see §3 |
| FC-17 | Bad self-update rollback | I (watchdog harness) | needs a distinct watchdog-process integration harness — owned by WS-D; **not yet coverable in this repo's CI as designed** (watchdog is a separate stable binary; needs its own test target once WS-D lands, see §8) |
| FC-18 | Clean uninstall | manual + scripted smoke | `launchctl`/`SMAppService` state assertions post-uninstall; owned by WS-D, needs a real macOS runner with install rights |
| FC-19 | Admin seed + scaffolding + preflight | I, E | CV-5 preflight E2E, incl. red-preflight-on-404 fixture |
| FC-20 | MDM profile generator | I, E | generated `.mobileconfig` validated against the managed-profile schema |
| FC-21 | Fleet dashboard | E | CV-4, mock fleet-data fixtures |
| FC-22 | Safety channel never a no-op | I | escalation-router + audit-log integration test (F3) |
| FC-23 | Persistence/notifications-off detection | I | stub `SMAppService.status`/notification-permission Fakes |
| FC-24 | MDM-native deprovision | I, E | Scenario 6 fixtures; `secrets_touched==0` assertion |
| FC-25 | Parse-never-compute + provenance | **static + code-review gate + provenance diff (§3 DQ-3)** | not behaviorally testable alone |
| FC-26 | Bidirectional schema gate | U, C | §1.3.3 |
| FC-27 | Security keys only from forced domain | U | stub `CFPreferencesAppValueIsForced` |
| FC-28 | Telemetry PII un-emittable | U | schema-level type test: usage payload type admits only {org,dept,foundation} |
| FC-29 | Do-no-harm coexistence | I | flock-contention integration test (§1.2, E15) |
| DQ-1 | False-Healthy = 0 | U property test + field oracle | §3 |
| DQ-2 | Auto-suspend = 100% | adversarial harness | §3 |
| DQ-3 | Parse-never-compute = 0 lines | static gate + provenance diff | §3 |
| DQ-4 | Managed machines reach true terminal state ≥99% | field dashboard metric | not a pre-release CI test — a fleet-observability metric fed by G3; **flagged: depends on WS-G dashboard existing** |
| DQ-5 | Telemetry PII leakage = 0 | U | same as FC-28 |
| DQ-6 | Materialized content matches CLI-computed winning layer | I | provenance-diff integration test, also backstops DQ-3 |
| DQ-7 | Safety escalations reach IT = 100% | I | audit-log-vs-emitted-signal cross-check, same mechanism as FC-22 |
| DQ-8 | Deprovision secrets_touched == 0 | I | fixture assertion, `deprovision/clean-wipe.json` |
| DQ-9 | No user-domain security key ever honored | U | same as FC-27, plus a CI preference-lint pass |
| Scenario 1 — Silent First Light | I, E | FC-1/FC-3 suites combined |
| Scenario 2 — Unmanaged ≤3 questions | E | FC-2 |
| Scenario 3 — Invisible steady-state self-heal | I | FC-9/FC-10 |
| Scenario 4 — Security shadow | adversarial harness | FC-16/DQ-2 |
| Scenario 5 — Org standup + fleet deploy | E | FC-19/20/21 (Admin mode, CV-5) |
| Scenario 6 — Offboarding a leaver | I, E | FC-24 |
| Scenario 7 — Watchdog catches a bad update | — **not yet coverable** | needs the stable-watchdog binary + `--self-test` heartbeat mechanism (WS-D, P1); design a dedicated watchdog-integration harness once that binary exists |
| E1 | Missing MDM key + silent wizard | U, I, E | = FC-3 |
| E2 | Offline first-run | I, E | = FC-4 |
| E3 | Seed not yet published | I, E | = FC-4 |
| E4 | Quit mid-wizard | I, E | = FC-5 |
| E5 | Gatekeeper kills vendored CLI | manual/CI signing smoke | owned by WS-D; needs a real signed build, not unit-testable |
| E6 | Schema drift shows green over red | U, C | = FC-26 |
| E7 | User-domain preference-write attack | U | = FC-27 |
| E8 | Security shadow Bob never sees | adversarial harness | = FC-16/DQ-2 |
| E9 | Un-wipeable leaver | I | = FC-24 |
| E10 | Held-major dumped on Bob | I, E | = FC-14 |
| E11 | Used-skill silently pruned | I, E | = FC-13 |
| E12 | Notification permission denied | I, E | = FC-15 |
| E13 | Login item toggled off | I | = FC-23 |
| E14 | Bad self-update crash-loops | — **not yet coverable** | = Scenario 7, needs WS-D watchdog |
| E15 | Dual-writer race | I | flock-contention (§1.2) |
| E16 | Bob-actionable alert nudged then silent | I | time-box-escalation integration test (F4) |
| E17 | Safety escalation reaches no one | I | = FC-22/DQ-7 |
| E18 | Breaking change mid-session | I | = FC-10 |
| E19 | Blocked update, no self-unblock | E | dashboard/dropdown E2E, absence-of-control assertion |
| E20 | Telemetry name-leak attempt | U | = FC-28/DQ-5 |
| E21 | Both hosts, one broken | U, E | = FC-7 |
| E22 | Stale auth token | I, E | Signed-out state rendering + routing (own-data vs machine-credential) |

**Summary of flagged gaps:** FC-17, FC-18, Scenario 7, E5, E14 depend on **surfaces not yet built** — the stable self-update watchdog binary (WS-D) and the signed/notarized distribution pipeline. They cannot be meaningfully automated in CI today; they get dedicated harnesses once WS-D lands (P1), and a manual/scripted smoke pass in the interim. DQ-4 is a fleet-observability metric (needs WS-G's dashboard shipped and real or staged fleet data), not a pre-release CI gate.

---

## 6. Red-team regression — every closed finding gets a regression test

Each finding below is marked **closed** in `architecture.md` §10; each gets a fixture (§4) and a test (§1–3) so it cannot silently reopen. This table is the enforcement mechanism for "closed" actually meaning closed.

| Finding | Regression test |
|---|---|
| A-C1 / B-H4 | `doctor/missing-security-field.json`-style fixtures for the managed profile; wizard E2E asserting IT-config-incomplete, never Healthy, on any required-key-absent case; settling-window retry timing test |
| A-C2 | Signing/notarization CI smoke (`cli-spawnable` doctor check present and asserted as a named finding, not a generic red) — owned by WS-D |
| A-C3 / FC-16 | Adversarial harness (§3 DQ-2) |
| A-C4 | Deprovision integration suite (§1.2); assert wipe trigger is `Deprovisioned=true` only, never profile-removal alone (regression for M1 too) |
| A-C5 / FC-22 | Safety-channel-always-on integration test; assert the channel fires independent of the analytics opt-in flag |
| A-H6 / FC-5 | Checkpoint-resume integration + E2E (quit-after-clone-before-materialize fixture) |
| A-H7 / FC-4 | Offline-first-run fixture; assert Waiting-for-network, never Healthy, never a scary error |
| A-H8 / FC-10 | Session-active backoff integration test, incl. security-exemption |
| A-H9 / FC-13 | Prune-notify vs prune-silent fixture pair |
| A-H10 / FC-15 | Notification-denied fallback integration test |
| A-H11 / FC-14 | Held-major-routes-to-IT E2E; assert **no** approve/unblock control renders for Bob |
| A-H12 / FC-4 | Seed-not-yet-published vs solo distinction fixture pair |
| A-H13 | Time-boxed escalation integration test (deadline-passed fixture) |
| M14 / FC-7 | Two-host-partial fixture; per-host transactional-lock assertion |
| M15 | Capability-policy-denial routes to IT log only, never a Bob notification — integration test on the router |
| M16 | Urgent-marker override of battery/metered backoff — timer-loop integration test (flag as PROVISIONAL per the perf table; test the override path exists, not the propagation-time SLA) |
| M17 | Global per-host mutex across verbs — integration test: `deprovision` mid-scheduled-sync fixture, assert sync drains before wipe |
| B-C1 | Single-process + flock-non-ownership test (§3 DQ-3 item 3) |
| B-C2 | `KeepAlive={SuccessfulExit:false}` plist assertion (static config check) + circuit-breaker integration test (N non-zero exits → stop relaunching) |
| B-C3 | Watchdog liveness-heartbeat integration harness — **owned by WS-D, needs the watchdog binary; see §8 gap** |
| B-C4 | Compat-matrix integration test: newer-CLI-pulls-newer-app fixture; `COPILOT_MANAGED_BY=controltower` self-update no-op assertion |
| B-C5 / FC-27 | Forced-domain-only security-key test (§1.1) |
| B-H1 | Cross-repo signing contract — CI smoke asserting vendored CLI is verified (`codesign`/`spctl`), never re-signed; blocks release if older than compat floor. Owned by WS-D. |
| B-H2 | Signed-uninstaller + self-`bootout`-guard smoke — owned by WS-D |
| B-H3 / FC-23 | Managed-login-item + `.requiresApproval` detection unit/integration test |
| B-H4 | = A-C1 above |
| B-H5 / FC-28 | Per-user salted `machine_id` unit test; layer-restricted usage-emission schema test |
| B-H6 / FC-26 | Bidirectional schema gate test (§1.3.3) |
| B-H7 | Per-user tree/keychain/login/watchdog isolation test; kiosk machine-credential path integration test |

---

## 7. Test-double taxonomy applied (summary)

Per this repo's testing floor: never Mock where a Stub suffices.

| Layer | Double used | Why |
|---|---|---|
| Unit parsing/state | **Stub** (canned `CFPreferences`, canned JSON) | isolating pure functions from macOS APIs — no interaction to verify |
| Integration (mock CLI) | **Fake** (a working, scriptable re-implementation of the CLI's I/O contract) | needs realistic process-spawn + `--json` + exit-code behavior, not just canned data |
| Menu → verb spawn assertions (FC-11) | **Spy** | the requirement genuinely is "only this verb gets called" — an interaction, not a state |
| Adversarial harness (DQ-2) | **Fake** (mock CLI) + **Spy** (escalation-router call recorder) | needs both realistic CLI behavior and proof the auto-suspend action was invoked before any signal |
| Static-analysis gate (DQ-3) | n/a — not a test double, a lint/grep pass | behavior-based tests cannot prove absence of logic |
| E2E | Fake (mock CLI) backing a real webview | full-stack confidence without a real `copilot` binary or network |

---

## 8. Coverage gaps & open dependencies (honest status)

1. **`docs/01-architecture/schemas/` now exists but is not yet frozen.** The consumer-side contract test (§1.3.2) and the fixture corpus (§4) can now be built against the versioned draft schemas, but those schemas encode assumptions (flagged via `$comment`) and reconstruct `repair` (which has no `--json` spec in `cli-contract.md`). They must be reconciled with WS-A's CLI-published authoritative contract before the contract test is considered binding — flag to WS-A/PRD owner.
2. **FC-17, FC-18, Scenario 7, E5, E14** depend on the stable self-update watchdog binary and the signed/notarized distribution pipeline (WS-D, P1) — not yet buildable, so not yet automatable. Interim: manual/scripted smoke only.
3. **DQ-1's field-oracle** and **DQ-4's fleet metric** require a deployed fleet (even a small pilot) to produce real data — pre-field, only the CI-side property test (§3) exists; the field cross-check is a P2/P3 operational process, not a CI job, and should be written up as an ops runbook item under WS-G/WS-H once a pilot fleet exists.
4. **Native tray/menu automation** (§1.4) is not WebDriver-reachable; covered via an IPC test-hook Spy in CI plus a manual accessibility-driven pass per release. If this proves insufficient, consider `axe`-style macOS UI automation as a P2/P3 investment — flagged, not designed here.
5. **Windows/P4** — this plan's §1.1–§1.3 are platform-independent by construction (pure Rust); §1.4 and the six boundary shims need their own E2E design when WS-I starts. Not detailed here, per phasing.

---

**Related:** [Acceptance Criteria](../product-design/03-requirements/30-acceptance-criteria.md) · [Use Cases & Scenarios](../product-design/03-requirements/20-use-cases-and-scenarios.md) · [CLI Contract](../01-architecture/cli-contract.md) · [Architecture](../01-architecture/architecture.md) · [PRD](../02-prd/prd.md) · [Red-Team: Use Cases](redteam-use-cases.md) · [Red-Team: Platform](redteam-platform.md)
