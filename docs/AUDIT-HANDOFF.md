# AUDIT HANDOFF: Copilot Control Tower

**For an independent developer auditing the build.** This is a *verification*
brief, not a sales pitch. Every claim below is something you should try to
**disprove**, not take on faith. Where a claim is enforced by a test, the test ID
is named so you can run it, read it, and try to break it.

> **Model note (read before auditing):** since the build described here was
> completed, an audit of the *docs* (separate from this build audit) found the
> product model needed correction: the Copilot Solutioning Ecosystem (CSE), see
> [`docs/10-reference/cse-alignment-decisions.md`](10-reference/cse-alignment-decisions.md).
> Two consequences for you as an auditor: (1) MDM is dropped completely as a
> mechanism going forward (no `.mobileconfig`, no forced/managed domain, no
> fleet dashboard as Admin's center of gravity); the M5/M9 code below still
> *implements* the pre-correction MDM design, so audit it as built, but do not
> treat "MDM-based" as the target state; the entitlement model is now GitHub
> repo access, and rework is deferred to the build phase, not done by this doc
> pass. (2) What this file calls "product" (Knowledge/CLI/Claude/Codex) is a
> **component** in the corrected vocabulary; "Product/Project" is reserved for a
> built output, never synced by Control Tower. The code still uses `product` as
> a field/module name; that rename is also deferred.

- **Product:** open-source macOS menu-bar app (Tauri v2, Rust core + tiny vanilla-TS UI) that is a **"parse, never compute" face + supervisor** over the `copilot`/`cc` CLI, plus an Admin/fleet mode.
- **Status at handoff:** all 9 milestones built, sec+qa gated, pushed. macOS builds green. Live infra/credentials are **intentionally mocked** (see §8, do not file these as defects).
- **What to produce:** findings ranked by severity, each tied to a file:line and an invariant, plus a verdict on whether the six invariants actually hold. Format in §10.

---

## 1. How to use this document

1. Read §2 (invariants): they are the acceptance criteria; everything else serves them.
2. Read §3 and get a **build + test run green** locally. If you can't reproduce green, stop and report that first.
3. Work §5 milestone-by-milestone, or §2 invariant-by-invariant if you prefer a threat-led audit. Each milestone names the **specific claim** and the **fitness test** that's supposed to enforce it; your job is to check the test actually enforces it (mutation-test it: break the code, confirm the test fails).
4. Cross-check §8 (known gaps) before filing anything: a mocked seam is not a bug.
5. Deliver findings in the §10 format.

---

## 2. The invariants: the actual acceptance criteria

These come from [`CLAUDE.md`](../CLAUDE.md) verbatim. The whole audit reduces to:
**do these six hold, structurally, under adversarial input?**

| # | Invariant | The claim to disprove | Primary enforcement |
|---|---|---|---|
| 1 | **Parse, never compute** | The app never computes ecosystem state (health, resolution, sync, merge, wipe); it only renders CLI `--json` verdicts. A false "Healthy" must be *structurally impossible*. | `render/derive.rs`, `model/doctor.rs`, FF-M6-4, FF-M7-NOSCORE |
| 2 | **Single process / crash-only** | One binary = tray+supervisor+scheduler. `launchd` is crash-only (`KeepAlive={SuccessfulExit:false}`), **never** resurrect-always. CLI self-serializes via `flock`; the app is not the lock. | `platform/macos/watchdog.rs`, `updater/circuit_breaker.rs`, FF-M4-* |
| 3 | **Never-destroy** | Freely re-materializes `.claude/` + read-only mirrors; **never** touches a dirty personal working tree. Publish path is additive, never governed by re-materialization. | `deprovision/render.rs`, `wizard/materialize.rs`, FF-M5-* |
| 4 | **Security inherited, never weakened** | No `--skip-verify`, no `--force`. Security config honored **only** via compiled-in trust roots and signed, inherited org/foundation config (a signed capability policy). **As-built the code still reads this from a forced/managed MDM domain (`managed/forced.rs`); that is the pre-correction design and is now a known divergence from the current invariant, see the model note above, not an approved target.** Trust roots are compiled-in code, not config. | `managed/forced.rs`, `managed/keys.rs`, `updater/trust.rs`, FF-M5-* |
| 5 | **Route by actor-competence × reversibility** | Auto-act reversible things the user can't judge; escalate to IT what they can't action; ask the user only non-deferrable decisions about their own data. | `routing/policy.rs`, `routing/event.rs`, FF-M6-A..D |
| 6 | **One-way inheritance; secrets never travel** | Secrets never enter inheritance content or any git repo (only `requires_secret: <NAME>` refs). No cross-tier write path. Sync is pull-only/downward. Fail-closed leak-scan on every writable push. Shared-secret-store endpoint is delivered via inherited org repo config, GitHub-team-gated, never an MDM-forced domain. | `settings/guard.rs`, `settings/authoring.rs`, `telemetry/schema.rs`, FF-M7-CONTENTFREE |

**If you audit nothing else, audit invariant #1 and #6.** Those are the product's
whole reason to exist; a hole in either is a critical finding.

---

## 3. Build, test, run (reproduce green first)

**Repos & branches (state at handoff):**

| Repo | Path | Branch | Notes |
|---|---|---|---|
| App | `copilot-control-tower` | `app-build` (→ `28d4e07`) | the thing you're auditing |
| CLI engine | `claude-copilot` | `ws-a-doctor-slice` | the `cc` verbs the app parses; audit its schema, not required to build the app |

**Build gotcha (you WILL hit this):** the `copilot` CLI is installed on this
machine as `cc`, which **shadows the C compiler** and breaks the `aws-lc-sys`
build script. Prefix cargo with a clean compiler + PATH:

```bash
cd copilot-control-tower/src-tauri
PATH="/usr/bin:$PATH" CC=/usr/bin/cc cargo test      # authoritative test count
PATH="/usr/bin:$PATH" CC=/usr/bin/cc cargo clippy --all-targets
cargo fmt --check
```

Web UI:

```bash
cd copilot-control-tower
npm install && npm run build      # unaffected by the cc shadow
```

**Static test surface:** 741 `#[test]`/`#[tokio::test]` functions across
`src-tauri/src` (run `cargo test` for the live, authoritative number; treat any
delta as your first thing to explain). Tests are **co-located** in each module's
`#[cfg(test)] mod tests`, not a separate `tests/` tree.

**Windows:** all `#[cfg(windows)]`-gated. It **cannot** build or run on macOS by
design. Verify it's gated *out* (the macOS build ignores it); do **not** try to
prove Windows behavior on this box: that's owner-gated (§8).

---

## 4. Architecture in one page

- **Parse-never-compute:** Rust core spawns `cc <verb> --json` by an **absolute,
  translocation-safe path** (never bare `copilot`; avoids the `gh copilot`
  collision), deserializes into a **fail-closed** model (`model/`), and the web UI
  renders it. No resolution/sync/merge/wipe logic exists in Rust. The merge-conflict
  chooser renders CLI-computed options and passes the choice back; it does not
  compute the merge.
- **4 components × 4 layers, component-first:** Knowledge / CLI / Claude / Codex
  (called "products" in the code and most milestone docs at time of writing; the
  corrected CSE vocabulary calls this axis "component"; see the model note
  above) × foundation / org / dept / personal. The UI is component-first
  (component dropdown, then layer detail).
- **Single process:** one signed binary. `launchd` (macOS) / Task Scheduler
  (Windows) is a **crash-only watchdog**. The CLI, not the app, holds the
  `flock` on `copilot.lock`.
- **Dev-seam pattern:** test seams are gated behind a `dev-seam` Cargo feature
  (not `#[cfg(test)]` alone) so they compile out of `--release`. Check this held:
  an earlier bug let a dev override survive into release builds.

Full spec: [`01-architecture/architecture.md`](01-architecture/architecture.md),
[`cli-contract.md`](01-architecture/cli-contract.md).

---

## 5. Per-milestone audit map

Each row: what shipped, where it lives, and **the specific thing to try to break**.

### M1: Tauri tray, parse-never-compute (`a137c6b`)
- **Code:** `tray.rs`, `timer.rs`, `model/doctor.rs`, `model/state.rs`, `render/derive.rs`, `render/glyph.rs`; UI `src/render/{popover,badges,copy}.ts`.
- **Verify:** the tray status is a *pure function of* the parsed `doctor --json`. Try to make it render "Healthy" without the CLI saying so. Check `render/derive.rs` has no health computation. Confirm the glyph state table is grayscale-legible (no color-only encoding).
- **Fail-closed:** feed `model/doctor.rs` malformed/partial/hostile JSON; it must refuse (fail closed), never coerce to a green default.

### M2: Settings authors the layer manifest cc reads (`a87af76`)
- **Code:** `settings/{manifest,validate,writer,guard,authoring,managed,secret_store,config_pointer}.rs`; UI `src/render/settings.ts`.
- **Verify (invariant #6):** `settings/guard.rs` is the leak-scan. Try to get a secret-shaped value (high-entropy token, map **keys**, single-char-class tokens) written into manifest content. An earlier QA pass found the scanner missed map-keys and single-char-class high-entropy tokens; **confirm those specific cases are now caught** (regression targets).
- **Verify (#4):** managed/security-sensitive config is read **only** from the forced domain (`settings/managed.rs`), never a user-editable domain.

### M3: First-run wizard (`31dd1f6`)
- **Code:** `wizard/{state,dto,signin,managed_flow,unmanaged_flow,materialize,persistence,support}.rs`; UI `src/render/wizard.ts`.
- **Verify:** the app holds **no secret**. Sign-in is a device-flow **seam** (`wizard/signin.rs`); the real `cc auth` verb doesn't exist yet (mocked, §8). Confirm the app never stores or logs a credential.
- **Verify (#3):** `wizard/materialize.rs` re-materializes disposable trees but must refuse to clobber a dirty personal tree.

### M4: Distribution, signing & crash-only self-update (`e0e597c`)
- **Code:** `updater/{trust,verify,heartbeat,watchdog,check,multisig,circuit_breaker,launch,selftest,rollback_marker,startup}.rs`; `platform/macos/watchdog.rs`.
- **Verify (#2):** watchdog is **crash-only**: `KeepAlive={SuccessfulExit:false}`, never `true`. Grep for any resurrect-always path. The circuit-breaker (ADR-M4-001) must actually gate restart storms (earlier it was doc-only; confirm it's wired, FF-M4-*).
- **Verify (#4):** signature verification against **compiled-in** trust roots; `updater/multisig.rs` enforces `k ≥ 2`. No `--skip-verify` path exists.
- **Watch for:** rollback/self-test machinery that's built but **unwired**; an earlier audit found exactly this. Confirm the anti-orphan fitness test proves each is reachable from a real code path.

### M5: MDM & security (`c89529b`)
- **Code:** `managed/{forced,keys,secret_store}.rs`, `mobileconfig/generator.rs`, `deprovision/render.rs`, `loginitem/smappservice.rs`.
- **Verify (#4):** forced-domain read via `CFPreferencesAppValueIsForced`; refuse security config from anywhere else. Trust roots not config.
- **Verify (#3):** deprovision is **render-not-compute**: the app renders the CLI's wipe plan; it computes no wipe itself. Dirty trees retained.
- **Model note:** this milestone's mechanism (MDM forced domain, `.mobileconfig`) is the pre-correction design. The current invariant #4 (see the model note at the top of this document and `CLAUDE.md`) rehomes security-sensitive config to compiled-in trust roots plus signed, inherited org config, and drops MDM entirely (D4). Audit this milestone's code as it was built and verify the render-not-compute and fail-closed properties hold; do not fault it for still being MDM-shaped, that is a known, tracked rework item, not a hidden defect. The corrected entitlement/deployment mechanism (GitHub repo access; a central shared secret store gated by GitHub-team membership) has no shipped code yet.

### M6: Bob-agency & escalation (`fa7fddb`)
- **Code:** `routing/{event,policy,emit,wire,deprovision_trigger}.rs`; `render/{bob_lane,security_banner}.rs`.
- **Verify (#5):** the router is a **pure classifier**: `route(event) → {AutoAct | EscalateIt | AskBob}`; computing no health verdict. FF-M6-4 source-scans against it computing. Confirm the user is **never** asked to approve a held-major / clear a policy-denial / self-unblock (those go to IT or auto). Security banner is un-dismissable (re-affirm-only).

### M7: Observability & Admin/fleet (folds M8) (`ff8460b`)
- **Code:** `render/fleet.rs`, `telemetry/{schema,optin,emitter}.rs`, `admin/{seed,preflight}.rs`; UI `src/render/fleet.ts`.
- **Verify:** **no computed fleet score** (FF-M7-NOSCORE): dashboard renders CLI-computed per-host worst-wins, no "94/100"/rings/sparkline. Telemetry is **content-free** (FF-M7-CONTENTFREE: machine_id + status enum + event kind only, never a personal name/path) and **opt-in, default OFF** (FF-M7-OPTIN). Two-of-N signing (FF-M7-TWO-OF-N). **No closed/paid/hosted component** (pure OSS).
- **Caveat:** Admin/fleet surfaces are stamped **UNVALIDATED HYPOTHESIS**; no real IT operator has used them. Audit the code; flag UX-validity as out of scope.

### M9: Windows re-skin (`73ae27b`)
- **Code:** `platform/windows/*` (`cli_path,forced,loginitem,schtasks,secret_store,tray,watchdog`).
- **Verify:** invariants hold identically on Windows *in code*; everything `#[cfg(windows)]`-gated so macOS is unregressed. Crash-only maps to Task Scheduler failure-restart-with-cap (**never** periodic-repeat). Forced-config reads `HKLM\Policies` **and refuses unless domain-joined/MDM-enrolled**. Runtime verification is owner-gated (§8).

---

## 6. The invariant fitness tests (verify these actually bite)

These are the load-bearing tests. For each, **mutation-test it**: make the code
violate the invariant and confirm the test goes red. A green fitness test over
code that doesn't enforce anything is the worst-case finding.

| Test ID | Proves | Where to look |
|---|---|---|
| FF-M4-1..6 | Crash-only watchdog, circuit-breaker wired, no resurrect-always, rollback/self-test reachable | `updater/`, `platform/macos/watchdog.rs` |
| FF-M5-1..7 | Forced-domain-only security config, deprovision render-not-compute, never-destroy | `managed/`, `deprovision/`, `mobileconfig/` |
| FF-M6-4 | Router computes no verdict (source-scan) | `routing/policy.rs` |
| FF-M6-A..D | Actor-competence routing correctness; user never asked forbidden approvals | `routing/` |
| FF-M7-NOSCORE | No computed fleet health score | `render/fleet.rs` |
| FF-M7-CONTENTFREE | Telemetry carries no personal name/path | `telemetry/schema.rs` |
| FF-M7-OPTIN | Telemetry default OFF, opt-in only | `telemetry/optin.rs` |
| FF-M7-TWO-OF-N | `k ≥ 2` signatures required | `updater/multisig.rs` |

**Note:** M1–M3 invariants are enforced by fail-closed deserialization + co-located
unit tests rather than named `FF-` markers; check `model/failclosed.rs`,
`model/doctor.rs`, and `settings/guard.rs` directly.

---

## 7. Schemas: the frozen contract (fail-closed is the point)

`docs/01-architecture/schemas/`: `_envelope.schema.json`, `doctor`, `resolve`,
`freshness`, `update`, `deprovision`, `repair`, `publish`. The app deserializes
**fail-closed**: unknown/missing/malformed ⇒ refuse, never a permissive default.
**Audit target:** find a schema field whose Rust deserialization coerces a missing
or bad value into a *safe-looking* value (e.g. missing `signed` → treated as
signed). The correct behavior everywhere is missing `signed` ⇒ **unsigned**;
`blocked[]` retained ⇒ EscalateIt. See `model/envelope.rs`, `model/failclosed.rs`.

---

## 8. Known gaps: DO NOT file these as defects

These are **intentionally mocked** because they need owner-only infra/credentials.
The seams exist and are tested against fixtures; only the far ends are stubbed.

- **Signing/notarization**: placeholder identity until an Apple Developer ID cert exists (enrollment pending).
- **`cc auth` device-flow, `cc layers add`, per-layer status field, `telemetry.enabled/endpoint`**: CLI verbs/fields not yet in `claude-copilot`; app renders mocks. This is the **WS-A de-mock** track.
- **Four infra endpoints**: telemetry ingest, fleet collector API, IT/AdminContact channel, update feed. All mocked.
- **minisign 2-of-N keys**: placeholder root; real keys + second holder owner-gated.
- **MDM forced-domain**: generator unit-tested; not verified against a live enrolled Mac. Also note: per the model note above, MDM is now dropped as the target mechanism entirely (D4), so this gap is superseded rather than pending completion; do not recommend "finish MDM verification" as the fix.
- **Windows**: code gated but never built/signed/run (no Windows box + Authenticode cert).
- **Admin/fleet UX**: UNVALIDATED HYPOTHESIS; no real IT operator has used it.
- **Three CSE surfaces not yet built or audited** (new since this build; not a defect in the audited code, listed here so you don't go looking for them): department discovery + join by GitHub repo access; a distinct register for entitled shared integrations (org/dept-provisioned) versus personal sign-in (device-flow); personal-key multi-machine sync. See `docs/10-reference/cse-alignment-decisions.md` D7.

Full owner-gated detail: [`RESUME-HERE.md`](RESUME-HERE.md) and the per-milestone
memory notes referenced there.

---

## 9. Red-team & security docs to read

- [`04-validation/redteam-platform.md`](04-validation/redteam-platform.md): platform-level attack surface.
- [`04-validation/redteam-use-cases.md`](04-validation/redteam-use-cases.md): per-use-case abuse cases each workstream had to close.
- [`04-validation/test-plan.md`](04-validation/test-plan.md).
- [`05-security/threat-model.md`](05-security/threat-model.md), [`credentials-and-boundary.md`](05-security/credentials-and-boundary.md), [`signing-custody.md`](05-security/signing-custody.md), [`security-and-trust.md`](05-security/security-and-trust.md), [`incident-response.md`](05-security/incident-response.md).

**Audit ask:** pick 3 red-team cases at random and confirm the code actually closes
them (not just that a doc says so).

---

## 10. What to deliver

Findings ranked most-severe first. For each:

- **file:line** and the **invariant** it touches (or "none, quality").
- **Severity**: Critical (breaks an invariant) / High / Medium / Low / Nit.
- **Failure scenario**: concrete input/state → wrong output. Not "this looks risky."
- **Whether a fitness test should have caught it** (and why it didn't).

Plus a one-paragraph **verdict per invariant**: holds / holds-with-caveats / broken,
with the evidence. If you couldn't reproduce a green build+test, that's finding #1.

**Ground rule:** prefer proving a failing case over asserting a smell. A finding
with a reproduction beats ten "consider refactoring" notes.
