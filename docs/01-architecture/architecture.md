# Copilot Control Tower — Architecture

> **Status line — rebuilt from evidence, 2026-08-02.** This document describes Copilot Control Tower v0.4.0 as it actually ships: a native macOS SwiftUI/AppKit app, not the Tauri v2/Rust design this file previously described. Sections below are marked **SHIPPED** (true of the code in `native/*.swift` today), **DESIGN POSITION** (a stated architectural commitment not yet mechanically enforced), or **HISTORICAL** (described the retired Rust implementation; kept only where the reasoning still informs the native app). Where the two invariant-enforcement gaps G-1 (fitness tests scan the retired Rust tree, not `native/`) and G-2 (the `launchd` watchdog is not implemented in the shipping app) bear on a section, they are called out inline — see `CLAUDE.md` for the canonical statement of both.

| | |
|---|---|
| **Status** | **SHIPPED.** v0.4.0, native SwiftUI/AppKit, DOGFOODING on one org (16/16 live apply); remaining items are the V-5 cold-laptop proof and the publicize step. |
| **Product** | **Copilot Control Tower** — the always-on, self-healing menu-bar client of the Copilot ecosystem, plus its Admin-mode org setup tool |
| **Repo** | `Everyone-Needs-A-Copilot/copilot-control-tower` |
| **Stack** | Native macOS **SwiftUI/AppKit**, compiled by `swiftc` (no Xcode project, no package manager), **single process**, macOS-only. A retired Tauri v2/Rust core at `src-tauri/` was removed from this repository in commit `chore: remove retired src-tauri tree`; it survives only in git history; it was not built, not tested in an active CI job, and not part of any release. |
| **Bundle identifier** | `com.everyoneneedsacopilot.controltower` |
| **Brand** | Aviator-sunglasses silhouette, template-icon friendly (renders correctly as a monochrome macOS menu-bar template image) |
| **Executables** | `Copilot Control Tower.app` (User), `Copilot Control Tower Admin.app` (User surface + Admin, built with `-D CT_ADMIN_BUILD`), `Publisher Setup.app` (owner-only release tooling) |
| **Design of record** | [`../03-design/control-tower-native-experience-architecture.md`](../03-design/control-tower-native-experience-architecture.md) · [`-interaction-spec.md`](../03-design/control-tower-interaction-spec.md) · [`-visual-system.md`](../03-design/control-tower-visual-system.md) |
| **Historical validation appendices** | [`redteam-use-cases.md`](../04-validation/redteam-use-cases.md) · [`redteam-platform.md`](../04-validation/redteam-platform.md) — written against the retired Tauri-era design under the working codename "Aviator." Read §10 below before treating any specific citation as a claim about the shipping app. |

> **The one invariant.** Control Tower is a **face + supervisor over the `copilot`/`cc` CLI — it parses, it never computes.** Every health verdict, resolution, signature check, and materialize decision is done by the CLI, the same hardened pipeline a headless developer runs. If Control Tower vanished, the CLI would still be correct. **SHIPPED**: the native `SchemaGate` (`native/cli-client.swift`) fails closed on missing security-relevant fields and unrecognized schema majors, and no resolution/merge/wipe logic exists in `native/*.swift`. **G-1**: this claim is not mechanically enforced by an automated test suite against the shipping app — see the enforcement note in §10.

---

## 1. What it is, and why a tower

The Copilot ecosystem ships the intelligence: a `cc doctor`/`onboard`/`workspace` state machine in the sibling `claude-copilot` repo, a reconciling-sync resolver, a signed inheritance model across foundation → org → department → personal. **Control Tower does not re-implement any of it.** It is the always-on GUI supervisor that keeps a machine synced and healed on a schedule, turns `doctor`'s verdict into a glanceable menu-bar badge, runs the first-run wizard as a GUI over the same CLI phases, and is the delivery vehicle for the non-technical persona this product calls "Bob" — someone who double-clicks a signed app and never opens a terminal.

**Two faces, one open-source binary family.** Control Tower is Bob's client and also the org admin's setup tool for standing up the whole Copilot Solutioning Ecosystem (CSE) for their org. §2–§7 describe the **User app** (Operator mode — the end-user client, shared by both executables); **§8 describes Admin mode** (the additional surface in `Copilot Control Tower Admin.app`). See [`cse-alignment-decisions.md`](../10-reference/cse-alignment-decisions.md) for what Control Tower manages (CSE tooling components) versus what it never manages (the products/projects built with that tooling).

---

## 2. The status model & the tray — SHIPPED

The tray's badge is driven by a **12-state badge vocabulary** (`BadgeState` in `native/models.swift`): `pass`, `ring`, `key`, `update`, `triangle`, `wrench`, `clock`, `cloud-slash`, `bang`, `spinner`, `hollow`, `none` — each mapped to an SF Symbol and a system color, composited onto the aviator glyph. This is a different, more granular vocabulary than an earlier ten-state design (`Setup-needed`/`Healthy`/`Syncing`/…) that predates the native build; the badge names above are what actually ships.

- **Poll cadence:** a single `Timer` at **300 seconds**, plus a refresh on launch and on popover open. There is no separate scheduler and no headless daemon.
- **The popover** renders sections named exactly as they appear on screen: `YOUR COPILOTS`, `AVAILABLE TO JOIN` (with per-row `Join` buttons), `SHARED WITH YOUR TEAM`, `YOUR ACCOUNTS`. Action buttons include `Sync now`, `What changed`, `Set up`, `Settings…`, `Review your changes` (for a dirty-tree hold), `Grant this on GitHub` (for a missing `write:public_key` scope), `Add the connection`, and folder-approval actions (`Choose folder…`, `Not on this Mac`, `Add another folder…`, `Stop watching this folder`).
- **The right-click menu:** `Sync now`, `What changed`, `Settings…` (⌘,), `Open Administration…` (Admin build only), `Quit`.
- **`status` is computed by the CLI, not the app** — `doctor --json`'s `status`/`checkers[].severity` fields drive every badge decision; the app performs no health scoring of its own.

---

## 3. Process model & persistence

- **SHIPPED — one signed binary.** Each executable is a single process owning its own poll timer while running. There is no separate headless daemon and no in-app fallback scheduler.
- **DESIGN POSITION, not shipped — `launchd` crash-only watchdog.** The stated design (invariant #2 in `CLAUDE.md`) is a `launchd` `LaunchAgent` with `KeepAlive={SuccessfulExit:false}`, never `KeepAlive=true`. Packaging assets for this (`packaging/launchd/`, `install-watchdog.sh`/`uninstall-watchdog.sh`) exist, and the retired Rust tree implements it, but **`native/*.swift` contains no reference to `launchd`, `LaunchAgent`, or `KeepAlive`** — this is gap **G-2**. The shipping app does not install or manage a crash-only watchdog today. If a user quits or force-kills the app, nothing relaunches it.
- **SHIPPED, CLI-side — the CLI self-serializes.** `copilot update`/`onboard`/`deprovision` take an exclusive `flock` on `copilot.lock` and fail fast if held; this is a property of the CLI (verified in the `claude-copilot` repo), not something the app observes or references. *Control Tower is not the lock; the CLI is.*
- **DESIGN POSITION, not shipped — launch-at-login and self-update.** `SMAppService` registration and a signed, minisign-verified self-updater with watchdog-mediated rollback were designed for the Tauri-era build and exist only in `src-tauri/`. The shipping Swift app has no launch-at-login registration and no in-app self-update; a user updates by reinstalling a newer signed DMG, exactly as every `CHANGELOG.md` entry's Rollback paragraph instructs for reverting.

---

## 4. The first-run wizard — SHIPPED

Nine stages, rendered from `native/wizard.swift`'s `WizardStage` enum, in the product's own copy: **Welcome → Connect GitHub → Detect → What you're getting → Departments → Your connections → Your projects → Set up → Verify.**

Supporting state machines in the same file: a GitHub device-flow sign-in (`DeviceFlowStatus`, render-only — no token field by construction, so a secret can never reach a DTO), a least-privilege `write:public_key` grant upgrade (`GrantFlowStatus`), department discovery/join (`DepartmentJoinState`), project triage categories (`ProjectTriageCategory`), setup progress (`SetupRowState`/`SetupProgressState`), and a family of "holding" copy states (`HoldingVariant`/`HoldingInfo`, H1–H7) for in-progress or blocked conditions. The wizard asks only what the CLI's `onboard --json` plan cannot derive; everything else — repo URLs, component sets, git identity — is derived CLI-side and rendered, not computed by the app.

**Offline and partial-entitlement states are honest, not silently green.** A first run that completes foundation-only, or a department the user isn't yet entitled to, renders as its own state rather than a false "Healthy" — this follows directly from invariant #1 (parse, never compute): the app has no basis to claim completeness the CLI hasn't reported.

---

## 5. Host distinction — Claude vs Codex

Control Tower detects and manages **Claude Copilot** and/or **Codex Copilot** independently — a machine may have zero, one, or both. Host presence and column selection are resolved CLI-side (`doctor`/`onboard`'s per-product reporting); the app's job is limited to rendering the result per host. `knowledge` and `cli` components are host-agnostic and shared across both. Updates are reported per component × tier, so if one component's tier fails while another succeeds, the app can name the failing one rather than blending a verdict.

---

## 6. The app↔CLI contract — SHIPPED

The authoritative, current contract lives in [`cli-contract.md`](cli-contract.md) and the schemas in [`schemas/`](schemas/) — this section only summarizes it; **that document wins on any disagreement.**

Verbs the app actually calls today: `doctor`, `auth status/login/grant`, `layers [join]`, `freshness [--all-projects]`, `update [--fanout|--project]`, `onboard` (personal and org scope), `workspace` (nine subverbs), and `connections`. The app **never** calls `resolve`, `deprovision`, `publish`, or `repair` — the latter two are formally deferred (`ADR-008`); their design intent is preserved as design-record only, not as claims about existing behavior.

**Schema gating is per-verb and bidirectional.** `SchemaGate` (`native/cli-client.swift`) decodes only `schema_version` before trusting any other field, then requires an exact major-version match: `onboard` requires schema major **2**; every other verb requires major **1**. A CLI schema older than its floor is as fatal as one newer, and missing security-relevant fields (`destructive`, `signed`, `severity`) fail closed rather than defaulting to safe.

**The CLI is resolved by absolute path, never bare.** `CliLocator` tries an explicit override, then the bundle's own `Contents/Resources/cc` (a vendored, independently notarized copy preferred over any machine-installed copy), then a small fixed list of well-known install paths — never a `$PATH` lookup, avoiding the `gh copilot` name collision by construction.

---

## 7. Distribution, signing & self-update

- **SHIPPED — Developer ID signing, hardened runtime, notarization, stapling.** `scripts/package-user-release.sh` is the one real release pipeline: build via `swiftc`, verify the vendored `cc` helper (checksum plus verify-not-resign — Control Tower never re-signs a binary it didn't produce), run the headless smoke/acceptance harnesses in `scripts/tests/`, sign, notarize, staple, and produce the DMG. 16 tags and 8 signed releases are retained under `release/`. Signing identity: `Developer ID Application: Pablo Alejo Jr (3SYGVX2HB8)`.
- **SHIPPED — the vendored CLI is a cross-repo contract, not a shared trust root.** The `claude-copilot` repo publishes an already-signed, notarized `cc` binary at a pinned SHA and version; Control Tower's build verifies it and never re-signs it.
- **NOT SHIPPED — self-update.** No minisign key, no update-feed check, and no staged-bundle rollback exist anywhere in `native/*.swift`. That machinery is entirely in the retired `src-tauri/src/updater/`. Today, "update" means reinstalling a newer signed DMG — every `CHANGELOG.md` entry's Rollback paragraph is written for exactly this reinstall-based recovery path, and it is the honest current mechanism, not a stopgap awaiting automation.
- **NOT SHIPPED — a login-item / launch-at-login registration.** See §3.

---

## 8. Admin mode & org enablement

Control Tower has **two faces**: the User app (§2–§7) and the **Admin app**, which adds a 16-surface Admin mode navigable from `AdminModel`/`AdminRootView` (`native/admin.swift`) — 11 onboarding stages (Orientation → Prerequisites → Contacts → Connect GitHub → Describe your organization → Integrations → Secret store → Review setup → Organization setup → Setup check → Done) and 5 governance stages (Add a department, Someone left, Connect the shared store, Org setup, Analytics). There is **no MDM in this model** (CSE `D4`): entitlement and deployment run entirely on GitHub repo access, never a device-management push.

**Admin does not compute its own org state.** The deterministic engine behind every Admin action is `scripts/admin_bootstrap.sh`, a bash script whose own header states the operating rule: "the script, never the model, makes every existence/idempotency decision. Every mutation is check-then-act." Its dependencies (`gh`, `jq`, `python3`, `curl`) are vendored into the Admin app bundle for `gh`/`jq`. The User build never links Admin — the source list in `build-user.command` deliberately excludes `admin.swift`/`admin-support.swift`, and the `Open Administration…` menu item exists only inside `#if CT_ADMIN_BUILD`.

**What Admin mode actually does, per its own stages:** authors the org's seed configuration; creates or verifies organization and department GitHub repositories, teams, and branch protection; connects a tier-scoped shared secret store (Infisical) whose endpoint is delivered via signed, inherited org config — never MDM, never a secret itself; supports department membership changes and offboarding (governance stage "Someone left"); and an "Analytics" governance surface that today exposes a toggle with **no telemetry emitter behind it** — this is a stated, honest gap, not a hidden one.

**Security-sensitive config is honored only from compiled-in trust roots plus signed, inherited org/foundation config** (invariant #4) — never from any local, user-editable file, environment variable, or CLI flag. A value present only in local config is ignored, not merged.

**Deprovision is server-side, never app-contingent, and has no remote-wipe backstop.** The real backstop is GitHub repo-access revocation plus shared-secret-store token rotation; a leaver who stays offline or deletes the app can't defeat the access revocation, but content already synced to their disk before revocation is not remotely wiped — no MDM exists to reach the device. This is an accepted trade-off for the product's target of small, trusted organizations, not a defect.

---

## 9. The Bob-agency model — DESIGN POSITION, partially expressed in wizard copy

The design principle: route by **actor-competence × reversibility**, not by event class. Auto-act on anything reversible a non-technical user can't judge; escalate to IT what they can't action; ask the user only when they are the sole competent actor about their own data (for example, "commit your dirty personal work before I sync"). This principle is expressed today in the wizard's holding-state copy family (H1–H7 in `native/wizard.swift`) and in fail-closed states like `IT-config-incomplete`, but there is no dedicated escalation-router module in the shipping app, and no telemetry/observability pipeline exists to carry a safety signal to an org's IT contact — that machinery, like self-update, exists only in the retired Rust tree. Treat this section as the design intent the wizard and tray copy were written against, not as a fully-implemented subsystem.

---

## 10. Validation — what the historical red-team findings mean today

[`redteam-use-cases.md`](../04-validation/redteam-use-cases.md) and [`redteam-platform.md`](../04-validation/redteam-platform.md) were written against the pre-native, Tauri-era design under the working codename "Aviator," and mapped 25 Critical/High findings to specific fixes in that design (a `launchd` watchdog, a minisign-based self-updater, MDM-managed config, a fleet telemetry dashboard). Several of those fixes never shipped in the native rebuild — see §3, §7, and §8's "NOT SHIPPED" notes above — so a finding citation in those two documents should be read as **historical validation of a design that has since diverged from the shipping app**, not as a live claim about `native/*.swift`. Findings whose reasoning is independent of the Rust implementation (fail-closed schema gating, never-bare-CLI-name resolution, never-destroy on personal trees) do still hold, and are cited as SHIPPED in the relevant section above.

**Enforcement, honestly (G-1).** A 40-file fitness-test suite exists (`src-tauri/tests/fitness_*.rs`) mapping to all six `CLAUDE.md` invariants, plus several stronger rules the invariants don't even state (no closed/paid component, no ETA in the wizard, structurally content-free telemetry). **Every one of those tests scans `src-tauri/src/**` — the retired Rust tree — and cannot see a single line of the shipping Swift.** The GitHub Actions job that would run them is gated behind a disabled repository variable. What actually gates a real release today is the shell-level harness in `scripts/package-user-release.sh`: headless-detect and bundle-structure tests, a 138-scenario smoke suite, vendored-CLI verification, schema-compatibility and notarization-order checks, and a headless setup-transaction drive against a fixture CLI. Several native-side invariants are enforced by this harness and by Swift code review — never a bare CLI name, fail-closed schema gating, selftests that refuse to run against anything but a `mock-cc` binary — but not by the named fitness functions. Porting that suite to scan `native/*.swift` and re-enabling the CI job is an open item, not a defect fixed by this documentation pass.

---

## 11. Open decisions

1. **Fitness-test enforcement (G-1).** Port the 40-test suite to scan `native/*.swift`, re-enable the CI job.
2. **The `launchd` crash-only watchdog (G-2).** Decide whether to implement it for the native app, and if so, port the design from the packaging assets that already exist.
3. **Self-update.** Decide whether an in-app updater is worth building, given the reinstall-a-new-DMG path has been the operating model through every release to date.
4. **Signing custody.** Two-of-N signing versus a transparency-log witness for release artifacts, and who would hold a second key, remains undecided — today there is a single signing identity.
5. **Windows.** Formally out of scope; see the superseded banner on [`windows-parity.md`](windows-parity.md).

---

## 12. What shipped, phase by phase (no time estimates — priority and dependency only)

- **P0 — CLI contract + shell.** SHIPPED. The `--json` contract is live and versioned (`cli-contract.md`); the native single-process shell, status badges, and host detection are live.
- **P1 — Wizard + signing.** SHIPPED (wizard, Developer ID signing, notarization, stapling). NOT SHIPPED (launch-at-login registration, self-update — see §3, §7).
- **P2 — Org config + security + Bob-agency.** SHIPPED (signed inherited org config honored per invariant #4; fail-closed schema gating). PARTIALLY SHIPPED (Bob-agency routing exists in wizard copy, not as a dedicated router; see §9). NOT SHIPPED (server-side deprovision exists as a CLI capability; the app never calls `deprovision` — see §6).
- **P2/P3 — Admin mode + docs.** SHIPPED — the 16-surface Admin app, `admin_bootstrap.sh`, the shared-secret-store connection stage.
- **P3 — Observability + hardening.** NOT SHIPPED. No telemetry emitter exists in `native/*.swift`; the Admin app's Analytics toggle has nothing behind it. Two-of-N signing is undecided (§11 item 4).
- **P4 — Windows.** Formally out of scope; see [`windows-parity.md`](windows-parity.md).

---

## Appendices

**Design of record:** [`../03-design/control-tower-native-experience-architecture.md`](../03-design/control-tower-native-experience-architecture.md) · [`-interaction-spec.md`](../03-design/control-tower-interaction-spec.md) · [`-visual-system.md`](../03-design/control-tower-visual-system.md) **Historical design (Tauri-era, superseded):** [`../03-design/design-core.md`](../03-design/design-core.md) · [`../03-design/design-distribution.md`](../03-design/design-distribution.md) · [`../03-design/design-integration.md`](../03-design/design-integration.md) **Historical validation:** [`../04-validation/redteam-use-cases.md`](../04-validation/redteam-use-cases.md) · [`../04-validation/redteam-platform.md`](../04-validation/redteam-platform.md) **Parent architecture:** [`../10-reference/ecosystem-architecture.md`](../10-reference/ecosystem-architecture.md)
