> **Superseded framing.** This document predates the Copilot Solutioning Ecosystem (CSE) realignment. Its MDM/fleet framing and its use of "product" to mean a CSE tool are superseded. The corrected model is in `docs/10-reference/copilot-solutioning-ecosystem.md`; the decisions are in `docs/10-reference/cse-alignment-decisions.md`.

# Acceptance Criteria

> **Provenance.** Every criterion is independently verifiable and traces to a user story
> ([`10-user-stories.md`](10-user-stories.md)), a scenario ([`20-use-cases-and-scenarios.md`](20-use-cases-and-scenarios.md)),
> the PRD's per-task acceptance prose (`02-prd/prd.md`), or a moments-that-matter success/failure
> criterion (`02-service-design/40-moments-that-matter.md`). Performance numbers tagged `(PROVISIONAL)`
> come from `00-overview/20-success-metrics.md` and have **no field baseline yet** — they are concrete
> Then-clauses to test against, to be revisited against real data. **Hard invariants** (false-Healthy
> rate = 0, security-shadow-miss = 0, parse-never-compute) are **not thresholds** — any violation is a
> Critical regression, not a tuning target. Genuine unknowns marked `<!-- TODO -->`.

---

## Functional Criteria (Given / When / Then)

### FC-1 · Silent managed first-run (US-B01, US-A04, US-A06 · MTM-1)
- **Given** a managed Mac with a complete, schema-valid `.mobileconfig` and `DisableWizard=true`,
  **when** Bob logs in, **then** the wizard runs silently, asks **zero** questions, and the icon
  reaches **Healthy** parsed from `doctor --json status: healthy`.
- **Given** the profile is complete, **when** the silent path runs, **then** the login-item + crash-watchdog
  are installed at the **first** phase (verifiable via `launchctl` + `SMAppService.status`).
- **Given** the whole managed path, **when** it completes, **then** no terminal window is ever created
  (verifiable: no TTY spawned; process tree contains no `Terminal`/shell UI).

### FC-2 · Unmanaged wizard ≤3 questions (US-B02)
- **Given** an unmanaged Mac with no `.mobileconfig`, **when** Bob runs the wizard, **then** he is
  prompted for **at most three** inputs (host-if-ambiguous, sign-in, company/team) and every other
  value is derived (assert: prompt-count ≤ 3 in the UI event log).
- **Given** sign-in, **when** it runs, **then** it uses a GUI device flow (8-char code + browser),
  never a terminal.

### FC-3 · Fail-closed on missing MDM key (US-B03 · MTM-1 · A-C1/B-H4)
- **Given** `DisableWizard=true` and a required key **absent**, **when** the app boots, **then** it
  enters **IT-config-incomplete** (wrench badge) and **retries over a settling window**, and it
  **never** shows Healthy or hangs.
- **Given** a required key **present-but-invalid** (type/URL-parse fail), **when** validated, **then**
  it fails immediately with `IT config error: <key>` and escalates to IT.
- **Given** any config-incomplete state, **when** it occurs, **then** a content-free `stalled-onboarding`
  signal reaches the IT `AdminContact` channel.

### FC-4 · Waiting-for-network + seed-vs-solo (US-B04 · A-H7/A-H12)
- **Given** an offline first-run that completes foundation-only, **when** status resolves, **then** the
  state is **Waiting-for-network** (clock badge), never Healthy and never a scary error.
- **Given** reconnection, **when** the supervisor next polls, **then** company clones complete
  automatically with no re-wizard.
- **Given** the app shipped before `ecosystem.yml` exists, **when** the seed is absent, **then** the
  machine holds in Waiting-for-network (distinguished from "solo" via managed `EcosystemSeedURL`),
  **never** false-Healthy.

### FC-5 · Resume interrupted setup (US-B05 · A-H6)
- **Given** a quit after clone but before materialize, **when** Bob next logs in, **then** setup
  resumes headlessly from the persisted checkpoint, requiring no user action.

### FC-6 · Honest icon, never false-Healthy (US-B07, US-O05 · MTM-2)
- **Given** any machine state, **when** the icon renders, **then** its value is **parsed** from a fresh
  CLI verdict and the app has **no code path** to render Healthy without `status: healthy`.
- **Given** a `--json` payload with a missing security field, **when** parsed, **then** it is treated
  as fail (never safe/green).
- **Invariant:** across the entire field fleet, **false-Healthy count = 0**. Any occurrence is a
  Critical regression. *(See QA instrumentation note DQ-1.)*

### FC-7 · Names the failing host (US-B08 · A-M14)
- **Given** two hosts where exactly one is broken, **when** the status line renders, **then** it names
  the specific failing host ("Codex needs sign-in; Claude is fine") — never a blended verdict.
- **Given** an update where one host succeeds and one fails, **when** it commits, **then** the lock is
  consistent **per host** (per-host transactional).

### FC-8 · Distinct honest states, not color-alone (US-B09)
- **Given** each non-Healthy honest state, **when** rendered, **then** it carries a distinct shape/badge
  **and** a plain-language sentence (wrench / clock / key), not color alone.
- **Given** multiple concurrent conditions, **when** precedence resolves, **then** it follows
  `IT-config-incomplete > Signed-out > Needs-attention > Offline > Syncing > Update-available > Healthy`.
- **Given** any state change, **when** it occurs, **then** it transitions **only** from fresh CLI JSON.

### FC-9 · Auto self-heal (US-B10 · job B2)
- **Given** `freshness --json` reports `stale: true`, **when** the supervisor runs, **then** reversible
  `warn`/healable `fail` is auto-repaired with no Bob prompt (AUTO-ACT lane).
- **Given** an unknown/non-parseable failure class, **when** encountered, **then** it **escalates**
  rather than auto-acts (it is excluded from the auto-heal denominator).

### FC-10 · Session-active backoff (US-B11 · A-H8)
- **Given** a non-security update and a live host session, **when** the update lands, **then** it is
  **deferred (not blocked)** until the session ends, then applied automatically.
- **Given** a **security** update, **when** it lands mid-session, **then** it is **not** deferred.

### FC-11 · Menu spawns CLI verbs only (US-B12)
- **Given** any dropdown action, **when** invoked, **then** it spawns a `copilot`/`cc` verb with `--json`
  and the menu **never mutates ecosystem state itself** (verifiable: no state-mutation code path in the
  menu handler; all writes go through the CLI).

### FC-12 · Asked only about own data (US-B13 · invariant #5)
- **Given** any Bob-facing prompt, **when** it fires, **then** it concerns a reversible-or-owned decision
  about Bob's **own** data (dirty WIP commit; the one sign-in) — nothing else.
- **Given** a dirty personal tree, **when** a sync is needed, **then** Control Tower **never** touches it;
  it prompts Bob to commit.

### FC-13 · Prune of a recently-used item notifies (US-B14 · A-H9)
- **Given** an update that prunes a **recently-used** item, **when** it completes, **then** Bob is
  notified ("a tool you used was removed").
- **Given** a prune of a **zero-usage** item, **when** it completes, **then** no notification fires.

### FC-14 · Held-major routes to IT, not Bob (US-B15, US-A09 · A-H11 · MTM-4)
- **Given** a held-major upgrade, **when** it awaits a decision, **then** it routes to IT centrally
  (approver authority from `ecosystem.yml`) and Bob sees only a **non-actionable** "waiting on IT."
- **Given** Bob's view, **when** rendered, **then** **no** approve/unblock control exists (Soul: OUT).
- **Given** an un-acted Bob-actionable item past its deadline, **when** the deadline passes, **then** it
  **time-boxes to IT** rather than degrading silently. (A-H13)

### FC-15 · Notification-denied fallback (US-B16 · A-H10)
- **Given** the macOS notification permission is denied, **when** a high-severity event fires, **then**
  the app opens the popover as fallback **and** re-routes safety events to the IT channel.

### FC-16 · Security-shadow auto-suspend (US-B17, US-O01 · MTM-3 · A-C3)
- **Given** an `update --json` `changed[]` entry with `severity_trailer: security` + a stale
  `shadowed_by` override, **when** parsed, **then** the override is **auto-suspended** (fixed version
  wins immediately) **and** IT is escalated in parallel.
- **Given** the auto-suspend, **when** it acts, **then** it is reversible (Bob can re-affirm) and the
  Bob-facing message is quiet + past-tense; a Bob notification is **never** the sole control.
- **Invariant:** **auto-suspend coverage = 100%**. Any miss is a Critical regression. *(See DQ-2.)*

### FC-17 · Bad self-update rollback (US-B18 · MTM-5 · B-C2/B-C3)
- **Given** a self-update whose bundle crashes on launch, **when** the watchdog launches it with
  `--self-test`, **then** absent an early liveness heartbeat it discards the bundle, keeps the working
  version, marks the bad version poisoned, and notifies calmly.
- **Given** repeated launch failures, **when** they exceed the circuit-breaker threshold, **then**
  relaunching stops and "reinstall" is surfaced — **no crash-loop** (`KeepAlive` never `true`).

### FC-18 · Clean uninstall (US-B19 · B-H2)
- **Given** the signed uninstaller runs, **when** it completes, **then** `launchctl bootout` +
  `SMAppService.unregister()` + Keychain cleanup leave **no** orphaned login item or watchdog.
- **Given** a drag-to-Trash (no uninstaller), **when** the watchdog next runs, **then** it self-`bootout`s
  because its `Program` path is missing.

### FC-19 · Admin seed + scaffolding + preflight (US-A01, US-A02, US-A05)
- **Given** the seed generator, **when** Earl completes the flow, **then** a **valid** `ecosystem.yml` is
  produced and a PR opened, with no hand-YAML.
- **Given** a declared dept repo that does not exist, **when** preflight runs, **then** it reports **red**
  before rollout (a typo can't ship a 404).
- **Given** all checks pass, **when** preflight runs, **then** it reports **green** across: seed parses,
  dept repos exist, policy signed, profile complete-for-silent, pin resolves, mirror reachable.

### FC-20 · MDM profile generator (US-A04)
- **Given** the generator, **when** Earl completes it, **then** it emits one `.mobileconfig` for
  `dev.enac.controltower` **complete-for-silent** plus login-item + notifications payloads, and uploading
  it makes managed wizards run with zero questions.

### FC-21 · Fleet dashboard (US-A07, US-A08)
- **Given** a deployed fleet, **when** Earl opens the dashboard, **then** he can distinguish
  healthy / stuck / behind / needs-auth **at a glance**, over honest CLI-parsed states.
- **Given** a new locked SHA is published, **when** the version-skew panel updates, **then** it shows the
  fraction of the fleet on-current.

### FC-22 · Safety channel is never a no-op (US-A11 · A-C5)
- **Given** any safety-relevant event (sig-fail, auth-revoked, policy-conflict, stalled-onboarding,
  persistence-disabled, notifications-off), **when** it fires on a managed machine, **then** a
  **content-free** signal reaches the live `AdminContact` channel (split from analytics, on-by-default).
- **Invariant:** **100%** of emitted safety signals reach the channel. Any miss is a Critical regression.

### FC-23 · Persistence/notifications-off detection (US-A12 · B-H3)
- **Given** the login item is disabled, **when** the app detects `.requiresApproval`, **then** it emits
  "persistence disabled" to IT (not indistinguishable from a powered-off Mac).
- **Given** a managed fleet, **when** the login-item payload is applied, **then** the item is
  non-toggleable by Bob.

### FC-24 · MDM-native deprovision (US-A13, US-A14 · A-C4/B-M1/B-M2)
- **Given** `Deprovisioned=true` (and only that, not profile removal), **when** it is set, **then**
  server-side token revocation fires **and** an MDM-run `copilot deprovision` executes.
- **Given** a leaver who trashes the app or stays offline, **when** the machine next comes online,
  **then** `copilot update` fails closed and wipes materialized content.
- **Given** a deprovision, **when** it runs, **then** `secrets_touched == 0` and a **soft-then-hard**
  two-phase with grace window allows a flip-back to restore without a re-clone.

### FC-25 · Parse-never-compute + provenance (US-O05, US-O03 · O3)
- **Given** the app codebase, **when** reviewed each release, **then** it contains **zero**
  resolution/health/signature/wipe logic (code-review gate).
- **Given** materialized content, **when** diffed against `resolve --explain --json`, **then** it matches
  the CLI-computed winning layer **100%**.
- **Given** the codebase, **when** scanned, **then** **no** `--skip-verify` / `--force` path exists.

### FC-26 · Bidirectional schema gate (US-O06 · B-H6)
- **Given** a CLI schema **older** than the app's `min_schema` **or** newer than `max_schema`, **when**
  parsed, **then** the app fails closed and surfaces in-app "versions don't match — click to update"
  (never "run doctor in a terminal").
- **Given** any consumed verb, **when** the CLI releases, **then** the `--json` contract CI test is
  **100% green** (a red gate blocks release).
- **Given** human CLI prose, **when** the app needs state, **then** it parses the `--json` contract and
  **never** screen-scrapes.

### FC-27 · Security keys only from forced domain (US-O04 · B-C5)
- **Given** `UpdateFeedURL`/`FoundationMirror`/`EcosystemSeedURL`/`HTTPSProxy`/`GitHubHost`/`AuthMode`/
  `AllowSelfUpdate`/`Deprovisioned` set in the **user** domain, **when** read, **then** the value is
  **ignored** in favor of the compiled-in default **and** logged as a tamper event.
- **Given** `defaults write dev.enac.controltower UpdateFeedURL <x>` (user domain), **when** the updater
  runs, **then** it has **no effect** on the feed.

### FC-28 · Telemetry PII un-emittable (US-O07 · B-H5)
- **Given** telemetry emission, **when** it builds a payload, **then** `machine_id =
  hmac(hardware_uuid + posix_uid, per-install-random-salt)` (per-user, non-reversible) and it emits
  **only** items whose CLI-computed winning layer ∈ {org, dept, foundation}.
- **Given** a personal item name, **when** emission is attempted, **then** it is **un-emittable by
  construction** (schema-level, not filtered at runtime).
- **Given** telemetry, **when** unconfigured, **then** it is **off by default** and org-scoped (never ENAC).

### FC-29 · Do-no-harm coexistence (US-D01 · B-C1)
- **Given** a developer running `copilot update` by hand concurrently with the supervisor, **when** both
  invoke, **then** CLI-side `flock` serializes them with **no torn `.claude/` tree**.
- **Given** a dirty personal tree, **when** any Control Tower action runs, **then** the tree is **never**
  touched (zero incidents).

---

## Performance Criteria

| Area | Metric | Target | Verification |
|------|--------|--------|--------------|
| Status latency | freshness poll → menu-bar status refresh | **< 2 s (PROVISIONAL)** | app instrumentation p95; render is a parse of already-fetched `--json`, not a network op |
| Silent provision | managed push → Healthy / honest holding state | **≥ 95% reach Healthy without human touch; p90 ≤ 10 min (PROVISIONAL)** | wizard checkpoint timestamps; wall-clock is network-bound (clone + materialize) and falls back to an honest holding state past the bound |
| Poll cadence | supervisor timers | sync ~6h · doctor ~1h · freshness ~15m, with battery/metered backoff, one-in-flight | timer log; assert no hammering, coalescing holds |
| Fleet convergence | fleet on current locked SHA within one sync cadence | **≥ 90% (PROVISIONAL)** | version-skew panel; ~6h after publish, slack for asleep/offline |
| Self-update rollback | bad-bundle detect → keep working version | before the webview mounts (early liveness heartbeat gate) | `--self-test` heartbeat timing; no crash-loop observed |
| Deprovision | `Deprovisioned=true` → access revoked | next online `copilot update` (offline machines bounded by reconnect, honest boundary) | token-revocation + `deprovision --json` receipt |

---

## Quality Criteria

| Indicator | Standard | Verification |
|-----------|----------|--------------|
| Auto-heal success | **≥ 90%** of known-parseable healable `warn`/`fail` resolved without human action (PROVISIONAL); unknown classes correctly escalate (excluded from denominator) | `doctor`→`repair` outcomes over the auto-act lane (F1) |
| Security-shadow auto-suspend coverage | **100%** — a vulnerable override never wins silently (invariant; any miss = Critical regression) | escalation-router audit log (F2) |
| `--json` contract test | **100%** green on every CLI release | CI contract test in the `copilot` repo (A6) |
| Route-by-competence | Every escalation traces to auto-act / escalate-IT / ask-Bob by the matrix; Bob-facing notification count trends toward zero | escalation-router audit trail |
| Accessibility | Status never conveyed by color alone (shape/badge + text); keyboard-navigable menu; WCAG 2.1 AA 4.5:1 contrast; visible focus | design-review + automated contrast/focus checks <!-- TODO: confirm the a11y bar for a menu-bar-only surface with WS-UIDS --> |
| Voice/tone | Status is one plain sentence naming the failing host; no jargon, no blended verdict, no unprovable reassurance | copy review against `SOUL.md` §7 language table |

---

## Data-Quality Criteria (the hard invariants + thresholds)

| ID | Criterion | Target | QA instrumentation note |
|----|-----------|--------|-------------------------|
| **DQ-1** | **False-Healthy rate** — Healthy shown over a foundation-only / mis-provisioned / drifted machine | **= 0 (hard invariant)** | **Hardest to verify.** Requires a **ground-truth oracle** independent of the app (an out-of-band `doctor --json` + provenance snapshot per fleet machine) compared against every rendered Healthy across the field fleet. There is no "acceptable rate" — instrumentation must catch a single occurrence. |
| **DQ-2** | **Security-shadow auto-suspend coverage** — a vulnerable override never wins silently | **= 100% (hard invariant)** | **Hard to verify.** Requires an **adversarial test harness** that injects `security:`-trailered fixes against seeded shadowing overrides across host/Focus/notification-denied permutations, then asserts the fixed version is live *before any user-facing signal*. Field verification needs the escalation-router audit log cross-checked against every published security trailer. |
| **DQ-3** | **Parse-never-compute** — zero resolution/health/signature/wipe logic in the app | **= 0 lines (hard invariant)** | **Hard to verify.** Not testable by behavior alone — needs a **static-analysis + code-review gate** every release, plus a provenance diff (materialized content vs. `resolve --explain --json`) as the runtime cross-check. A false-Healthy in the field is the *symptom* that this broke. |
| DQ-4 | Managed machines reaching a **true** terminal state (Healthy / Waiting-for-network / IT-config-incomplete) vs. stuck | **≥ 99% (PROVISIONAL)** | fleet dashboard state distribution (G3) |
| DQ-5 | Telemetry PII leakage — personal item names emitted | **0, un-emittable by construction** | schema review: usage payload type admits only {org,dept,foundation} items |
| DQ-6 | Materialized content matches CLI-computed winning layer | **100%** | provenance diff vs. `resolve --explain --json` |
| DQ-7 | Safety escalations reaching a live IT channel | **100%** | IT channel receipt vs. emitted safety signals (F3) |
| DQ-8 | Deprovision `secrets_touched` | **== 0** | `deprovision --json` result field |
| DQ-9 | No user-domain security key ever honored | **0 honored; every attempt logged as tamper** | preference-read audit; entitlement/preference lint in CI |

---

## The Three Hardest-to-Verify Criteria (QA priority)

1. **DQ-1 — False-Healthy = 0.** Needs a fleet-wide, out-of-band ground-truth oracle to compare against
   every rendered Healthy. No sampling tolerance; a single field occurrence is a Critical regression.
2. **DQ-2 / FC-16 — Security-shadow auto-suspend = 100%.** Needs an adversarial injection harness across
   Focus/DND × notification-denied × host permutations, asserting the fix is live *before* any signal —
   plus a field audit-log cross-check against every published security trailer.
3. **DQ-3 / FC-25 — Parse-never-compute = 0 lines.** Not behaviorally testable; requires a
   static-analysis + code-review gate each release, backstopped by the provenance diff (DQ-6).

---

**Related:** [User Stories](10-user-stories.md) | [Use Cases & Scenarios](20-use-cases-and-scenarios.md) | [Success Metrics](../00-overview/20-success-metrics.md) | [CLI Contract](../../01-architecture/cli-contract.md)
