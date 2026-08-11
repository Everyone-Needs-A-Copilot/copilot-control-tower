# Copilot Control Tower — PRD (what was built, against the original plan)

> **Status line — rebuilt from evidence, 2026-08-02.** Describes Copilot Control Tower v0.4.0. This document originally described a parallel, multi-phase Tauri v2 build plan (workstreams WS-A through WS-I) to be executed via `/orchestrate`. That plan was never fully executed as written: the app that actually shipped is native SwiftUI/AppKit, built directly rather than orchestrated workstream-by-workstream, and several workstreams (self-update, observability/IT dashboard, Windows) did not ship at all. This rewrite keeps the original workstream structure — because it is still a useful map of the problem space — and marks each one **SHIPPED**, **PARTIAL**, **NOT SHIPPED**, or **DEFERRED / OUT OF SCOPE** against the real code, per the ground-truth survey underlying this documentation rebuild. It does not invent a new plan.

| | |
|---|---|
| **Status** | DOGFOODING — running in production on one org (ENAC), 16/16 live apply. Remaining: the V-5 cold-laptop proof, the publicize step. |
| **Product** | Copilot Control Tower — always-on menu-bar client + open-source IT setup/deploy tool |
| **Repo** | `Everyone-Needs-A-Copilot/copilot-control-tower` |
| **Architecture** | [`architecture.md`](../01-architecture/architecture.md) — rebuilt against the shipping native app |

---

## 1. Goal & non-goals

**Goal (unchanged from the original plan, and achieved for macOS).** Ship a Developer-ID-signed, notarized macOS menu-bar app that delivers a non-technical user ("Bob") a working, focus-scoped Copilot partner via one double-click, keeps every machine synced (per CSE component × entitled tier: Knowledge Copilot, CLI Copilot, Claude Copilot, Codex Copilot) and self-healed as a face+supervisor over the `copilot`/`cc` CLI, and gives an org an open-source tool plus docs to stand up and deploy the ecosystem via GitHub repo access.

**Non-goals (updated).**

- **Windows** — formally out of scope, not merely deferred. See the superseded banner on [`../01-architecture/windows-parity.md`](../01-architecture/windows-parity.md).
- **A second brain / any resolution logic in the app** — the CLI owns it. Still true; verified against `native/*.swift` for this rewrite.
- **Replacing systems of record** — CLI Copilot remains the runtime gateway.
- **Multi-org-per-machine** — deferred, ecosystem-level.
- **Device management (MDM)** — dropped completely, not merely descoped. Entitlement and deployment are GitHub repo access, full stop.
- **Product/project management** — a product/project is self-contained in its own repo, not a Control Tower layer (CSE decision D10).

**Definition of done — what "done" actually meant, and where it landed.** The original definition of done was: an org admin uses Admin mode to generate the seed and repo/team scaffolding, a non-technical employee self-installs the signed app and is entitled by GitHub repo access, stays healed, and fleet health is reported — with all Critical/High red-team findings closed and the CLI `--json` contract test green. **What actually landed:** the admin-provision and self-install path is real and dogfooded on one org with 16/16 live apply across every component × tier combination; the CLI `--json` contract is real, versioned, and documented in [`cli-contract.md`](../01-architecture/cli-contract.md). **What did not land as originally specified:** fleet health reporting (WS-G, no telemetry emitter exists), and the red-team findings were closed against a design that has since partially diverged from the shipping app — see `architecture.md` §10 for which findings still hold.

---

## 2. Workstream status (the real map)

| Workstream | Original scope | Verdict | Evidence |
|---|---|---|---|
| **WS-A** — CLI contract | `--json` + `flock` + `COPILOT_MANAGED_BY` in `copilot`/`cc` | **SHIPPED** | Lives in the sibling `claude-copilot` repo; documented and versioned in [`cli-contract.md`](../01-architecture/cli-contract.md) and [`schemas/`](../01-architecture/schemas/). This is the most current, most actively maintained contract in the whole documentation set. |
| **WS-B** — App shell & supervisor | Single-process scaffold, status state machine, host detection, timers | **SHIPPED**, with one named gap | Native tray (`native/control-tower-tray.swift`), 12-badge vocabulary, 300s poll, `CliLocator`'s absolute-path resolution, per-verb `SchemaGate`. Gap: the crash-only `launchd` watchdog (part of the original "supervisor" scope) is not implemented — G-2. |
| **WS-C** — Wizard & onboarding | GUI wizard over CLI phases, asked-vs-derived question flow | **SHIPPED** | Nine-stage `WizardStage` enum (`native/wizard.swift`), device-flow sign-in, department discovery/join, project triage, holding-state copy family (H1–H7). |
| **WS-D** — Distribution & self-update | Signing, notarization, launch-at-login, self-update, uninstaller | **PARTIAL** | Signing/notarization/stapling: **SHIPPED** (`scripts/package-user-release.sh`, 16 tags, 8 signed releases). Self-update, launch-at-login registration, and a signed uninstaller: **NOT SHIPPED** — that machinery exists only in the retired `src-tauri/src/updater/`. Today's update mechanism is "reinstall a newer signed DMG," documented per-release in `CHANGELOG.md`'s Rollback paragraphs. |
| **WS-E** — Entitlement & security | Department discovery/join, security config from trust roots/signed config, offboarding, per-user everything | **PARTIAL** | Department discovery/join: **SHIPPED** (`copilot layers [join] --json`, rendered in the wizard's Departments stage). Security-sensitive config honored only from compiled-in trust roots plus signed inherited config: **SHIPPED** as a CLI-side + app-rendered design; MDM is not merely absent, it is a dropped mechanism (CSE D4). Offboarding: a CLI/Admin capability (GitHub access revocation, shared-secret-store token rotation), not something the app itself executes or renders a dedicated flow for beyond Admin's "Someone left" governance stage. Kiosk/shared-machine credential depth: <!-- TODO: not verified against native/*.swift for this rewrite; treat as open until confirmed. --> |
| **WS-F** — Bob-agency & escalation | Escalation router by actor-competence × reversibility | **PARTIAL** | The routing principle is expressed in wizard/tray copy (holding states, fail-closed `IT-config-incomplete`-style states) but there is no dedicated escalation-router module and no channel that delivers a safety signal to an org's IT contact — that requires the telemetry pipeline in WS-G, which did not ship. Treat this as design intent embodied in copy, not a built subsystem. |
| **WS-G** — Observability & IT dashboard | Opt-in org telemetry, fleet dashboard, two-of-N signing | **NOT SHIPPED** | No telemetry emitter exists anywhere in `native/*.swift`. The Admin app's "Analytics" governance stage has a toggle (`analyticsEnabled`, `native/admin.swift`) with nothing behind it — an honest, named gap, not a hidden one. Two-of-N release signing is undecided; today there is a single signing identity. |
| **WS-H** — Admin mode & docs | Seed generator, repo/access scaffolding, capability-policy signing, preflight validation, docs | **SHIPPED** | The 16-surface Admin app (`native/admin.swift`/`admin-support.swift`) plus the deterministic `scripts/admin_bootstrap.sh` engine cover seed authoring, repo/team scaffolding, shared secret-store connection, department governance, and offboarding. Operator documentation exists under `docs/06-deployment/`. |
| **WS-I** — Windows re-skin | Boundary shims over the shared Tauri core | **DEFERRED, now formally OUT OF SCOPE** | Windows was designed against a Tauri/Rust core that no longer ships; there is no core left to re-skin. All Windows code (`platform::`, `packaging/windows/`, `#[cfg(windows)]`) is retired-tree-only. See [`../01-architecture/windows-parity.md`](../01-architecture/windows-parity.md)'s superseded banner. |

---

## 3. What "done" required and how it was actually reached

The original plan assumed a strict dependency spine (WS-A freezes the contract, then WS-B through WS-I run concurrently against it) executed via `/orchestrate`. What actually happened was closer to direct, iterative build-and-release: the native app was hand-built against the CLI contract as it matured, released early and often (16 tags, starting from v0.1.1), and hardened through a live incident (the schema-mismatch initiative, `docs/40-initiatives/03-schema-mismatch/`, now complete) and a full onboarding-transaction rework (the self-onboarding initiative, `docs/40-initiatives/02-enac-self-onboarding/`, now at 16/16 live apply). The dependency relationship the original plan predicted — the CLI contract gates everything else — held true in practice; the parallel-workstream execution model around it did not, and that's fine: the goal was the shipped, dogfooded app, not fidelity to the orchestration mechanism.

---

## 4. What remains

1. **V-5 — the cold-laptop proof.** A two-machine onboarding run against an empty keychain, proving the experience holds for someone who isn't the owner running it on their own already-configured machine.
2. **The publicize step.** Making the supporting `knowledge-copilot`/`cli-copilot` foundation repos public — deliberately last, gated on the credential rotation their prior private-repo history requires.
3. **G-1 — port the fitness-test suite.** 40 tests exist and would enforce the six `CLAUDE.md` invariants (plus several stronger unstated rules) if ported from scanning `src-tauri/src/**` to `native/*.swift`, and if the disabled CI job that runs them were re-enabled.
4. **G-2 — the `launchd` crash-only watchdog.** Packaging assets already exist (`packaging/launchd/`); porting the actual registration/management logic into the native app has not happened.
5. **WS-G, if it is still wanted.** Opt-in org telemetry and a fleet/IT dashboard were designed but never built for the native app. Whether this remains a goal, given the product's current DOGFOODING-on-one-org scope, is an open product question, not a scheduling one.
6. **Self-update, if it is still wanted.** The reinstall-a-DMG model has been the operating mechanism through every release to date and may be a deliberately acceptable steady state rather than a gap — this is a product decision, not documented anywhere as settled either way. <!-- TODO: confirm with the owner whether self-update remains a goal or has been superseded by the reinstall model as the intended UX. -->

---

## 5. Risks (updated)

- **The `--json` contract is still the whole safety boundary.** Schema drift would be a silent security bypass. Mitigation in place: per-verb `SchemaGate`, fail-closed missing fields, versioned schemas in `schemas/`.
- **Invariant enforcement has no automated backstop against the shipping app (G-1).** A regression in any of the six `CLAUDE.md` invariants would not be caught by CI today — only by code review. This is the single largest process risk this documentation rebuild surfaced.
- **No crash recovery (G-2).** A user who force-quits or whose machine crashes the app gets no automatic relaunch; there is no supervisor above the app process today.
- **Always-on agent trust, partially addressed.** Open source, compiled-in trust roots, and signed inherited config are real; two-of-N release signing and a fleet observability/anomaly-halt mechanism (both part of the original trust story) are not built.
