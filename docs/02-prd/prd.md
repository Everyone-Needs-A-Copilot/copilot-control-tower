# Copilot Control Tower — PRD (parallel, multi-phase)

| | |
|---|---|
| **Status** | Proposed — ready for `/orchestrate` |
| **Product** | Copilot Control Tower — always-on menu-bar client + open-source IT setup/deploy tool |
| **Repo** | `Everyone-Needs-A-Copilot/copilot-control-tower` (new, public) |
| **Architecture** | [`architecture.md`](../01-architecture/architecture.md) (validated against 25 Critical/High red-team findings) |
| **Branch** | `ecosystem-extensions` |

> **How this runs in parallel.** One prerequisite workstream (**WS-A, the CLI `--json`/`flock` contract in `copilot`**) gates the rest; once its contract is *published* (schemas frozen), the eight app-side workstreams proceed **concurrently** against the frozen contract, each in its own worktree. Phases (P0–P4) are *maturity gates*, not sequential teams — a workstream advances through phases at its own pace. Acceptance criteria are per task; a workstream is "done for a phase" when its phase tasks pass and its red-team findings are closed.

---

## 1. Goal & non-goals

**Goal.** Ship an open-source, Developer-ID-signed, notarized macOS menu-bar app that (a) delivers a non-technical user ("Bob") a working, focus-scoped Copilot partner via one double-click, (b) keeps every machine synced (per CSE component × entitled layer: Knowledge Copilot, CLI Copilot, Claude Copilot, Codex Copilot) and self-healed as a **face+supervisor over the `copilot`/`cc` CLI** (never a second brain), and (c) gives IT an open-source tool + docs to stand up and deploy the ecosystem org-wide via GitHub repo access.

**Non-goals (v1).** Windows (P4 re-skin only); a second brain / any resolution logic in the app (the CLI owns it); replacing systems of record (CLI Copilot remains the runtime gateway); multi-org-per-machine (ecosystem-level, deferred); device management (entitlement + deployment is GitHub repo access, not MDM); product/project management (a product/project is self-contained in its own repo, not a Control Tower layer, D10).

**Definition of done (v1 / macOS).** An IT admin uses Admin mode to generate the seed and repo/team scaffolding, and a non-technical employee self-installs the signed, notarized app, is entitled by GitHub org/department repo access (discovering and joining a department if needed), stays healed, and reports fleet health — with all 25 Critical/High red-team findings closed and the CLI `--json` contract test green.

---

## 2. Workstreams (parallel) & dependency spine

```
WS-A  CLI contract (--json + flock + COPILOT_MANAGED_BY)   [PREREQ — in claude-copilot/copilot]
        └── freezes the schema ──┐
                                 ▼   (all below run concurrently against the frozen contract)
WS-B  App shell & supervisor (single process, state machine, host detect, timers)
WS-C  Wizard & onboarding            depends: B (shell), A (bootstrap json)
WS-D  Distribution & self-update     depends: B ; cross-repo signing contract with A's repo
WS-E  Entitlement & security         depends: A (entitlement/discovery verb), B for runtime
WS-F  Bob-agency & escalation        depends: B (state), A (findings schema)
WS-G  Observability & IT dashboard   depends: F (escalation split), A (json)
WS-H  Admin mode & docs (open source) depends: A (seed schema), partial E
WS-I  Windows re-skin  [P4]          depends: B, D
```

**Critical path:** WS-A contract → WS-B shell → WS-D signing → the Bob self-install path (no zero-touch, D4). WS-E's department discovery/join flow (D7.1) gates a first meaningful sync, not the initial install. Everything else parallelizes off WS-B once the contract is frozen.

---

## 3. WS-A — CLI contract *(prerequisite; lives in `copilot`/`cc`)*

*The one hard dependency. Freeze the schema first; the app cannot supervise a CLI it can't read.*

| Task | Detail | Acceptance |
|---|---|---|
| A1 | `copilot doctor --json` — 0–100 score, `checkers[]` with `pass|warn|fail`, `repair` token, `destructive` flag, `auth[]`; exit 0/1/2; `schema_version` | schema published; CI contract test asserts it |
| A2 | `copilot update --json` — `changed[]` with `op:{added,updated,pruned,unchanged}`, `signed`, `severity_trailer`, `shadowed_by`; `held_for_approval[]`; `blocked[]` | prune + security-trailer events present in output |
| A3 | `copilot resolve --explain --json` + `copilot deprovision <org> --json` (`secrets_touched==0`) + `copilot freshness --json` (single lock-SHA) | all emit versioned schema |
| A4 | **`flock` on `copilot.lock`** across `update`/`repair`/`deprovision`; fail-fast if held | concurrent invocations serialize; no torn tree (fixes B-C1) |
| A5 | `COPILOT_MANAGED_BY=controltower` disables `copilot self-update` (one CLI-updater owner) | self-update no-ops under the flag (fixes B-C4) |
| A6 | **CI contract test** in `copilot` repo asserting every `--json` matches published schema each release; `min/max_schema` compat doc | green gate on release |

---

## 4. WS-B — App shell & supervisor

| Task | Detail | Acceptance |
|---|---|---|
| B1 | Tauri v2 **single-process** scaffold; tray icon (`LSUIElement`/Accessory); no headless daemon, no fallback loop (fixes B-C1) | app runs, tray present, no second process |
| B2 | Status **state machine** (Setup-needed / IT-config-incomplete / Healthy / Syncing / Update-available / Needs-attention / Signed-out / Offline / Waiting-for-network / Updating-app); worst-wins per host; plain-language status line **naming the failing host** (fixes A-M14) | states transition only from fresh CLI JSON |
| B3 | **Host detection** probe sweep (Claude/Codex/both/neither); re-run on freshness poll; column selection via `copilot derive` | correct host(s) reported; both-hosts = one app |
| B4 | The `cli.rs` boundary — spawn `copilot`/`cc` by **absolute, translocation-safe** path (`Bundle.main.bundleURL`, fixes B-L3); parse `--json`; **bidirectional `schema_version` gate**, missing security fields **fail closed** (fixes B-H6) | unknown/old schema → safe degrade, not misparse |
| B5 | Timer loops (sync ~6h, doctor ~1h, freshness ~15m) with **battery/metered backoff**, coalescing, one-in-flight | no hammering; respects Low Power Mode |
| B6 | Dropdown menu + "What changed" panel + Preferences | actions spawn CLI verbs only |

---

## 5. WS-C — Wizard & onboarding

| Task | Detail | Acceptance |
|---|---|---|
| C1 | GUI wizard over Ring-1 phases; **install login-item + crash-watchdog at the FIRST phase**, persist a checkpoint (fixes A-H6) | interrupted setup resumes headlessly |
| C2 | Asked-vs-derived question flow (host if ambiguous, sign-in, company/team pick-list) | ≤3 questions unmanaged |
| C3 | **Silent entitled path** — read signed, inherited org/foundation config (D4); **schema-validate before silent mode**; missing/malformed required key → fail-closed **IT-config-incomplete** (reworked from A-C1, B-H4 for D4); typed values; a user already GitHub-entitled to org/department needs no manual join | zero questions when entitlement resolves cleanly; never false-Healthy |
| C4 | **Waiting-for-network** first-run (foundation-only) + **seed-not-yet-published vs solo** distinction (fixes A-H7, A-H12) | offline day-one never shows Healthy |
| C5 | Wizard window focus fix (Accessory→Regular during setup, fixes B-L1); teach panel (cheat-sheet + add-a-skill + backup offer) | window foregrounds; teach shown |

---

## 6. WS-D — Distribution & self-update

| Task | Detail | Acceptance |
|---|---|---|
| D1 | Developer ID sign + hardened runtime + **notarize + staple** `.app` and `.dmg`; minimal userland entitlements; CI entitlement lint (no `get-task-allow`) | `spctl -a` passes offline |
| D2 | **Cross-repo binary contract** — consume `copilot`/`cc` as already-signed/notarized/universal artifacts at a **pinned SHA+version** from `claude-copilot` CI; verify (`codesign`/`spctl`), never re-sign; **block release if vendored CLI < compat floor** (fixes A-C2, B-H1, B-M5); `.pkg` postinstall de-quarantine; `cli-spawnable` doctor check | notarization green; no Gatekeeper kill on cold machine |
| D3 | `SMAppService` login item + **launchd crash-only watchdog** (`KeepAlive={SuccessfulExit:false}`, `RunAtLoad=false`) + ThrottleInterval + circuit breaker (fixes B-C2); never both `RunAtLoad` | clean Quit stays quit; bad build doesn't crash-loop |
| D4 | Self-update: Tauri signed-manifest updater; **rollback owned by the stable watchdog via early liveness heartbeat** (fixes B-C3); staple-verify staged bundle offline (fixes B-M3) | a bundle that crashes on launch auto-reverts |
| D5 | **Compat matrix, one canonical version**; newer CLI *pulls* newer app (no deadlock); `AllowSelfUpdate=false` → CLI+app as a version-locked pair (fixes B-C4) | no red-badge dead-end |
| D6 | **Signed uninstaller** (`launchctl bootout` + `SMAppService.unregister` + Keychain clear); watchdog self-`bootout` if `Program` missing (fixes B-H2) | Trash-drag doesn't orphan a login item |

---

## 7. WS-E — Entitlement & security

*Entitlement + deployment is GitHub repo access (D3); there is no MDM (dropped completely, D4).*

| Task | Detail | Acceptance |
|---|---|---|
| E1 | **Department discovery + join** (D7.1, elevated from a descoped side effect) — surface the departments a user is entitled to, validate by their GitHub repo access, sync the selected layer onto the machine | user discovers and joins an entitled department without hand-editing config |
| E2 | **Security-sensitive config** honored only from compiled-in trust roots + signed, inherited org/foundation config (a signed capability policy); values present only in user-editable local config are ignored + logged as tamper (reworked from B-C5 for D4) | a locally-edited `UpdateFeedURL` has no effect |
| E3 | **Entitled shared integrations** (D7.2) — show shared org/dept integrations provisioned by entitlement (secret-store endpoint via inherited org config, D6) as a register distinct from **personal sign-in** (device-flow, per-person) | shared vs personal integrations never conflated |
| E4 | **Offboarding** — revoke the person's GitHub access + rotate shared-secret store tokens; accepted residual: content already synced to a departed person's disk is not remotely wiped, no MDM to reach the device (reworked from B-M1, A-C4, B-M2 for D4) | revoked leaver loses further sync and shared-secret access on reconnect |
| E5 | **Personal-key multi-machine sync** (D7.3) — sync a user's own personal keys across their own machines, ending `.env` hand-copying | a personal key added on one machine is available on the user's other machines |
| E6 | **Per-user** everything ($UID tree/keychain/login/watchdog); no writable `/Users/Shared`; kiosk **machine-credential** (`gh-app` in system keychain); stable keychain designated requirement (fixes B-H5, B-H7, B-M6) | two users = two ids; kiosk auth works |

---

## 8. WS-F — Bob-agency & escalation

| Task | Detail | Acceptance |
|---|---|---|
| F1 | Escalation router by **actor-competence × reversibility** (auto-act / escalate-IT / ask-Bob), replacing event-class routing (fixes the Bob-agency problem) | each event class routed by the matrix |
| F2 | **Auto-suspend** a personal override that shadows a `security:`-trailer fix (reversible; Bob re-affirms) + escalate (fixes A-C3) | vulnerable override can't win silently |
| F3 | **Split safety-escalation from analytics**; mandatory `AdminContact`; safety channel **on by default** for managed machines; content-free signals (fixes A-C5) | "IT notified" is never a no-op |
| F4 | **Time-boxed escalation** for un-acted Bob-actionable items (backup-missing, re-auth); **session-active backoff** for non-security materialize (fixes A-H13, A-H8); **notify on prune of a recently-used item** (fixes A-H9); held-major → IT approves centrally (fixes A-H11); policy denials → IT log only (fixes A-M15) | no Bob-only silent-forever degradation |

---

## 9. WS-G — Observability & IT dashboard

| Task | Detail | Acceptance |
|---|---|---|
| G1 | **Opt-in, org-scoped** telemetry (endpoint in `ecosystem.yml`, never ENAC); content-free schema | off by default; org endpoint only |
| G2 | `machine_id = hmac(hardware_uuid + posix_uid, per-install-random-salt)` — per-user, non-reversible; usage emits only CLI-verified {org,dept,foundation} items, never personal names (fixes B-H5) | personal name un-emittable by construction |
| G3 | IT **fleet dashboard** (sync health, drift, auth-expiry, version skew, usage/adoption) — closes the ecosystem observability gap | admin sees healthy-vs-stuck at a glance |
| G4 | Release integrity: **two-of-N signing** (or transparency-log witness), separate key custody, staged rollout + **anomaly-halt** (fixes B-M4); hash-chained action log anchored to org endpoint (fixes B-L2) | one popped key ≠ fleet RCE |

---

## 10. WS-H — Admin mode & docs (open source enablement)

| Task | Detail | Acceptance |
|---|---|---|
| H1 | **Seed generator** — guided `ecosystem.yml` authoring; opens PR to `<org>/copilot-ecosystem` | valid seed produced, no hand-YAML |
| H2 | **Repo & access scaffolding** — create/verify org + separate dept repos; emit team/CODEOWNERS/branch-protection; declared-repo existence check | typo can't ship a 404 |
| H3 | **Capability-policy** authoring + signing (security key distinct from push) | policy signed by authorized signer |
| H4 | **Self-install + entitlement guide** — walks a user through installing the signed `.dmg` and discovering/joining an entitled department (replaces MDM profile/zero-touch, D4) | user can self-install and join without an IT push |
| H5 | **Preflight validation** — seed parses, dept repos exist, policy signed, pin resolves, mirror reachable; red/green report | IT validates before rollout |
| H6 | **Documentation set** — quickstart, self-install + department-entitlement guide, config reference, security-&-trust doc, ops/offboarding runbook; versioned in the public repo | an IT team can deploy from docs alone |

---

## 11. WS-I — Windows re-skin *(P4)*

Five boundary shims over the shared Tauri core: system tray, Task Scheduler (vs launchd), EV code-sign + SmartScreen, MSI/winget, Credential Manager (vs Keychain). Core, wizard, updater, compat guard, device-flow auth, escalation model, and GitHub-repo-access entitlement all unchanged.

---

## 12. Phase gates (maturity, cross-cutting)

| Phase | Gate |
|---|---|
| **P0** | WS-A contract frozen + `flock`; WS-B shell runs, reads `doctor --json`, correct host state |
| **P1** | WS-C wizard (silent + fail-closed + waiting-for-network); WS-D signed/notarized + cross-repo binary contract + watchdog rollback |
| **P2** | WS-E entitlement & security (department discovery/join, signed inherited config, GitHub-based offboarding); WS-F actor-competence escalation + safety-channel-on |
| **P3** | WS-G opt-in telemetry + IT dashboard + two-of-N signing; WS-H Admin mode + docs |
| **P4** | WS-I Windows re-skin |

**Exit (v1):** all Critical/High red-team findings (§10 of `05-control-tower.md`) closed; a test Mac self-installs, is entitled by GitHub org/department repo access, and reports fleet health; IT can stand up + deploy the ecosystem from Admin mode + docs alone.

---

## 13. Risks

- **The `--json` contract is the whole safety boundary** (B-H6) — schema drift = silent security bypass. Mitigation: contract test in `copilot` CI, bidirectional gate, fail-closed missing fields. *Owner: WS-A.*
- **Cross-repo signing lockstep** (B-H1) — two repos, one signature requirement. Mitigation: signed-artifact contract + pinned SHA. *Owner: WS-D + WS-A repo.*
- **Always-on agent trust** — an auto-pulling token-holder is a supply-chain surface. Mitigation: open source + two-of-N signing + compiled-in trust roots and signed inherited config + full audit trail. *Owner: WS-E/WS-G/WS-H.*
- **Bob is not a reliable actor** — the entire escalation model must assume this. *Owner: WS-F.*
