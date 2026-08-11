> **Evidence appendix — captured 2026-08-02.** A survey of what the product actually *was* on this date, read from shipping code and release artifacts rather than from documentation. It is one of three inputs to [`audit-2026-08-02-findings.md`](audit-2026-08-02-findings.md), which is the readable summary; this file is the raw working record, preserved because it would otherwise have been lost with the session that produced it. The snapshot was taken at **v0.3.2**; **v0.4.0** shipped hours later the same day, so the note here about the connections bridge being uncommitted is superseded — that work is committed and released. Nothing else in this file is affected.

---

# GROUND TRUTH — Copilot Control Tower, from code and shipped artifacts (2026-08-02)

Scope: what the product IS today, read from `native/`, `scripts/`, `packaging/`, `src-tauri/`, `docs/01-architecture/`, `docs/40-initiatives/`, `CHANGELOG.md`, `release/`, `dist/`, and git history. Excluded by instruction: `docs/product-design/**`. No changes proposed.

---

## 1. Real feature surface and entry points

### 1.1 What actually gets built

There are **three separate Swift executables** in this repo, plus a fourth artifact (the vendored `cc` helper) that is packaged, not compiled here.

| Artifact | Built by | Sources | Output |
|---|---|---|---|
| **Copilot Control Tower.app** (User face) | `scripts/build-user.command:26-34` | `models.swift`, `cli-client.swift`, `cli-dtos.swift`, `render-state.swift`, `wizard.swift`, `user-settings.swift`, `control-tower-tray.swift` (explicit list, never a glob — see the file header comment at `scripts/build-user.command:1-8`) | `build/Copilot Control Tower.app`, `Info.plist` from `packaging/macos/User-Info.plist` |
| **Copilot Control Tower Admin.app** (Admin face) | `scripts/build-admin.command:24-34` | the seven User files **plus** `admin.swift` + `admin-support.swift`, compiled with `-D CT_ADMIN_BUILD` (`scripts/build-admin.command:99`) | `build/Copilot Control Tower Admin.app`; also bundles `scripts/admin_bootstrap.sh`, a vendored `gh` and a vendored `jq` into `Contents/Resources/` (`scripts/build-admin.command:37-47,113-124`) |
| **Publisher Setup.app** | `scripts/setup-publisher.sh` / `scripts/publisher-setup.command` | `scripts/publisher_setup.swift` (2,314 lines) | owner-only release tooling: Developer ID identity pick, trust verify, notary profile creation, build, handoff (`scripts/publisher_setup.swift:29-45` — seven roadmap stages: welcome, prerequisites, identity, trustVerify, notaryConfig, build, handoff) |

Line counts (`wc -l`): `wizard.swift` 7,626 · `control-tower-tray.swift` 4,118 · `admin.swift` 2,675 · `admin-support.swift` 2,120 · `cli-dtos.swift` 1,226 · `cli-client.swift` 813 · `user-settings.swift` 852 · `models.swift` 458 · `render-state.swift` 448 — **22,650 lines of Swift** (native + publisher_setup). That is the product.

The vendored helper is `packaging/cc/cc` (21.4 MB PyInstaller binary), version `2.1.2` (`packaging/cc/VERSION`), SHA-256 pinned in `packaging/cc/PINNED_SHA256` and independently notarized (`packaging/cc/NOTARIZATION.json`). It is copied to `Contents/Resources/cc` at release build time (`scripts/build-user.command:141-144`) and is preferred over every machine-installed `cc` by `CliLocator` (`native/cli-client.swift:246-253`).

### 1.2 The User app — tray

`StatusBarController` (`native/control-tower-tray.swift:2533`) owns an `NSStatusItem` whose glyph is the aviator SVG (`native/models.swift:356` `AviatorGlyph`, template-tinted, no SF-Symbol fallback allowed) badged with one of **12 shape-first badge tokens** (`native/models.swift:40-71` `BadgeState`: pass, ring, key, update, triangle, wrench, clock, cloud-slash, bang, spinner, hollow, none — each mapped to an SF Symbol + system color).

- **Poll cadence:** a single `Timer` at **300 s** (`native/control-tower-tray.swift:2536,2585`). Refresh also happens on launch and on popover open (`:2575`).
- **Right-click menu** (`native/control-tower-tray.swift:2660-2688`): `Sync now`, `What changed`, `Settings...` (⌘,), `Open Administration...` (only inside `#if CT_ADMIN_BUILD`, `:2673-2684`), `Quit`.
- **Popover** (`PopoverContentView`, `native/control-tower-tray.swift:1445`) sections, by their literal on-screen strings: `YOUR COPILOTS` (:1549), `AVAILABLE TO JOIN` with per-row `Join` buttons and a `JoinRowState` machine (:1570, `:61`), `SHARED WITH YOUR TEAM` (:1601), `YOUR ACCOUNTS` → GitHub row (:1608). Action buttons: `Sync now` (:1635), `What changed` (:1642), `Set up` (:1656), `Settings…` (:1662), `Review your changes` for a dirty-tree hold (:1701), `Grant this on GitHub` for the missing `write:public_key` scope (:1725), `Add the connection` (:1818), `Choose folder…` / `Not on this Mac` / `Add another folder…` / `Stop watching this folder` for project-root approval (:1784-1954).
- **Projects drill-in inside the popover** (`ProjectRowRender`, `:357`; `ProjectTriageCategory` in `native/wizard.swift:170`): five CLI-authored categories, per-project detail with `Finish safely` (:2127), `Diagnose in Codex` / `Diagnose in Claude Code` (:2142-2147), `Copy diagnostic report` (:2155), `Check again` (:2159), `Run in Codex` / `Run in Claude Code` (:2270-2275), `Copy prompt` (:2280), `Copy project-owner handoff` (:2291), `Bring Terminal forward` (:2324), `Check project now` (:2330).
- **"What changed" view** (`:2415-2510`): a `Recently` list with `Projects set up for you` / `Projects brought up to date` groups and an explicit "Nothing has changed since you last looked." empty state.
- **Assistant launching is real**: `ProjectIntegrationLauncher` (`:439`) resolves the assistant to an absolute executable and drives Terminal via Apple Events (entitlement + purpose string are release-gated, CHANGELOG 0.2.2 "Security").

### 1.3 The User app — first-run wizard

`WizardStage` (`native/wizard.swift:62-79`) is a **9-stage** enum, rendered as "Step N of 10" in copy (the file header at `:55-60` records the projects step being added and every eyebrow shifting):

`welcome` → `connectGitHub` → `detect` → `whatYoureGetting` → `departments` → `integrations` (titled **"Your connections"**) → `projects` (**"Your projects"**) → `materialize` (**"Set up"**) → `verify`.

Supporting state machines in the same file: `DeviceFlowStatus` (`:83`, GitHub device flow — render-only, no token field by construction), `GrantFlowStatus` (`:117`, the least-privilege `write:public_key` upgrade with `identityMismatch`/`insufficientScope` terminal states), `OrgFieldValidation` (`:106`), `DepartmentJoinState` (`:134`), `ProjectTriageCategory` (`:170`), `SetupRowState`/`SetupProgressState` (`:370-412`), `HoldingVariant`/`HoldingInfo` (`:465-549` — the "holding" copy family H1..H7), plus modal sheets `InstallHelperSheet`, `GrantPermissionSheet`, `GrantFallbackSheet`, `OrgSignInIDSheet`, `OrgHelpSheet` (`:6709-7033`).

### 1.4 The User app — Settings

`UserSettingsView` (`native/user-settings.swift:442`), window controller at `:814`. It renders **4 components × 4 tiers**: `UserSettingsComponent` = knowledge / cli / claude / codex (`:22-38`, labelled "Knowledge Copilot", "CLI Copilot", "Claude Copilot", "Codex Copilot"); `UserSettingsTierStatus` keyed on `Layer` (foundation/org/dept/personal, `native/models.swift:100-112`); `UserSettingsTierKind` = ready / needsSetup / needsAttention / notJoined / couldNotCheck (`:40-65`). Derivation is pure and shared (`UserSettingsRender`, `:82`) from `DoctorReport` + `OnboardReport` + `LayersReport`. Settings also hosts the project categories (`:70-72`) and, in uncommitted work, a "Your connections" card (see §5.4).

### 1.5 The Admin app

`AdminModel` (`native/admin.swift:721`), `AdminRootView` (`:1598`), `AdminSidebar` (`:1523`), `AdminWindowController` (`native/admin-support.swift:2097`). Navigation is `AdminSelection` (`native/admin.swift:602`) over two stage families — **16 surfaces total**, per the file header (`native/admin.swift:9-12,51-53`):

- `AdminOnboardingStage` (`:539-545`), 11 entries: Orientation, Prerequisites, Contacts, Connect GitHub, Describe your organization, Integrations, Secret store, Review setup, Organization setup, Setup check, Done.
- `AdminGovernanceStage` (`:577-582`), 5 entries: Add a department, Someone left, Connect the shared store, Org setup, Analytics.

Admin does **not** compute its own org state. The deterministic engine is `scripts/admin_bootstrap.sh` (98 KB bash, header at `:1-12`: "The script, never the model, makes every existence/idempotency decision. Every mutation is check-then-act (GET before POST/PATCH/PUT)"). Dependencies are `gh` + `jq` (vendored into the bundle) + stock `python3` + `/usr/bin/curl`. Foundation pins live in that script (`:31-34`: claude `^5.8.0`, codex `^0.6.0`, knowledge `^0.1.0`, cli `^0.3.0`). Supporting UI in `admin-support.swift`: `RunChecklistView` (`:846`), `BriefCardBody` (`:1126`), `RepositoryInventoryCardBody` (`:1216`), `SetupCheckBody` (`:1558`), `SlowCallWatcher`/`RunWorkingIndicator` (`:769-811`).

The User build never links Admin: the `Open Administration...` menu item is inside `#if CT_ADMIN_BUILD` (`native/control-tower-tray.swift:2673-2684`), and the source list in `build-user.command` deliberately excludes the two admin files.

### 1.6 Headless / selftest entry points (the real test surface)

`AppDelegate.applicationDidFinishLaunching` branches before creating any UI (`native/control-tower-tray.swift:2735-2790`):

- `--headless-detect` (`:2744`) — runs the exact three Detect verbs (`auth status`, `doctor`, ecosystem onboard plan) through the production `CliClient` and prints typed JSON. Plan-only by design, "has no apply counterpart" (`:2742-2743`). Driven by `scripts/headless-detect.sh`.
- Env-gated in-binary selftests: `CT_ONBOARD_QUESTION_SELFTEST`, `CT_PROJECTS_STEP_SELFTEST`, `CT_TRAY_PROJECTS_SELFTEST`, `CT_SETUP_PROGRESS_SELFTEST`, `CT_SETUP_TRANSACTION_SELFTEST`, `CT_TRAY_WAIT_SELFTEST` (`:2758-2787`), plus `CT_ADMIN_HARNESS_SELFTEST` / `CT_ADMIN_COMPLETION_DEPARTMENT_SELFTEST` in the Admin build. The setup-transaction selftest is hard-guarded: it refuses to run unless `CT_ALLOW_INERT_SETUP_PROOF=1` **and** `CT_CLI_PATH` basename is literally `mock-cc` (`:2774-2781`) — "An arbitrary CT_CLI_PATH must never turn a selftest into a live mutation."
- Shell harnesses in `scripts/tests/`: `smoke-scenarios.sh` (51 KB, 138 scenarios per the phase-7 doc), `test_packaged_cc_topology_contract.sh` (16-row, 8-history-state gate against the **packaged** binary), `test_admin_bootstrap.sh` (77 KB), `test_user_app_bundle.sh`, `test_admin_app_bundle.sh`, `test_headless_detect.sh`, `test_schema_compatibility_release_gate.sh`, `test_notarization_order.sh`, `test_walkthrough_05_08_acceptance.sh`, `test_completed_setup_acceptance.sh`, `test_vendored_cc_release_gate.sh`, `test_project_integration_contract.sh`, `test_foundation_snapshot_release.sh`, `test_notary_profile_preflight.sh`, `smoke-cli.sh`, `smoke-launch.sh`.

---

## 2. Tauri vs native: which one ships

**The native Swift app ships. Tauri is reference-only.**

Evidence:

1. `scripts/package-user-release.sh` — the one release pipeline — builds via `bash scripts/build-user.command --build-only` (`:161-163`), i.e. `swiftc`. It never invokes `cargo`, `tauri build`, or `npm`. Everything downstream (sign, `verify-user-automation.sh`, `verify-vendored-cc.sh`, `headless-detect.sh`, `headless-setup-transaction.sh`, notarize, DMG, staple, Gatekeeper, metadata) operates on `build/Copilot Control Tower.app`.
2. `package.json:5` describes the product as "Thin skin: no UI framework" and its scripts are only `vite`/`tsc`/`tauri` passthroughs. `dist/index.html`, `dist/wizard.html`, `dist/settings.html`, `dist/fleet.html` + `dist/assets/*` are vite build output that nothing packages.
3. Version drift proves the Rust side is unmaintained: `package.json:3` = `0.3.2`, `src-tauri/tauri.conf.json:4` = `0.3.2`, `packaging/macos/User-Info.plist:24` = `0.3.2`, but **`src-tauri/Cargo.toml:3` is still `0.2.4`**.
4. `CLAUDE.md` "Tech": "This supersedes the prior Tauri v2 / web-UI plan." `docs/START-HERE.md` (bullet 2): "The earlier **Tauri v2 plan is retired**; the Tauri code that exists is read-only historical reference, not the shipping app."
5. Timestamps: last modification under `src-tauri/src/` is 2026-07-09 (`render/`), most of it 2026-07-08. `native/*.swift` was last touched 2026-08-02.

The one place Tauri still has teeth: `.github/workflows/release.yml:44-48` still runs `cargo test --all-targets` + `clippy -D warnings` + `fmt --check` before packaging. But that job is gated `if: ${{ vars.RELEASE_CI_ENABLED == 'true' }}` (`:24`) with the in-file comment "The repository currently has no release environment or Apple credential secrets" — so in practice **releases are cut locally** by `scripts/package-user-release.sh`, and the Rust tests do not gate them. The Tauri build also still supplies two real assets to the native build: `src-tauri/icons/icon.icns` and the bundle identifier `com.everyoneneedsacopilot.controltower` (`build-user.command:139`, `native/models.swift:222`).

---

## 3. The CLI contract as implemented

### 3.1 Verbs the app actually calls

From `native/cli-client.swift` (argv arrays, all `--json`):

| Call site | argv | Line |
|---|---|---|
| `doctor()` | `doctor --json` | 475 |
| `authStatus()` | `auth status --json` | 479 |
| `authLoginInitiate/Poll()` | `auth login --json` / poll (built at 491-520) | 491,503 |
| `configSetGithubAppOrg()` | `config set github_app.org <org>` (raw, not JSON) | 522 |
| `authGrantInitiate/Poll()` | `auth grant --json`, `auth grant --poll --device-code <c> --json` | 532,536 |
| `layers()` | `layers --json` | 540 |
| `layersJoin(id:)` | `layers join <id> --json` | 544 |
| `freshness()` | `freshness --json` | 548 |
| `connections()` | `connections --json` | 561 **(uncommitted, see §5.4)** |
| `freshnessAllProjects()` | `freshness --all-projects --json` | 565 |
| `update()` | `update --json` | 569 |
| `updateFanout()` | `update --fanout --json` | 573 |
| `updateProject(path:)` | `update --project <path> --json` | 577 |
| `onboardPlan/Apply(components:)` | `onboard --scope personal --components <csv> [--apply] --json` | 581,585 |
| `ecosystemOnboardPlan/Apply()` | `onboard --org … --products … [--repository-root …] [--apply] --json` | 595-616 |
| `workspaces()` / `workspace(path:)` | `workspace --all --json` / `workspace --project <p> --json` | 619,625 |
| `verifyWorkspace()` | `workspace verify --project <p> --json` | 650 |
| `workspaceIntegrationPlan()` | `workspace plan --project <p> --json` | 655 |
| `finishWorkspace/holdWorkspaceIntegration/configureWorkspace/configureAllWorkspaces` | `workspace …` variants | 631-701 |
| `approveWorkspaceRoot/forgetWorkspaceRoot` | `workspace approve-root/forget-root --path <p> --apply --json` | 703,707 |
| `workspaceRoots()` | `workspace roots --json` | 713 |
| `declineWorkspaces()` | `workspace decline --apply --json` | 719 |
| `revertWorkspace()` | `workspace revert …` | 728 |

**Not called anywhere in `native/`:** `resolve`, `deprovision`, `publish`, `repair`. `resolve` and `deprovision` have schemas in `docs/01-architecture/schemas/` and Rust code in `src-tauri/src/deprovision/`, but no Swift caller.

### 3.2 Schema gate

`SchemaGate` (`native/cli-client.swift:313-361`) decodes **only** `schema_version` before trusting any other field, then requires an exact major match, **per verb**:

```
static func requiredMajor(forVerb verb: String) -> Int {
    switch verb {
    case "onboard": return 2
    default: return requiredMajor   // 1
    }
}
```
(`native/cli-client.swift:324-330`; `requiredMajor = 1`, `minSchema = "1.0"` at `:319-320`.)

`CliError` (`:273-311`) is the fail-closed vocabulary: `notFound`, `launchFailed`, `exit2(code,message)`, `parse`, `schemaOutOfRange`, `missingSecurityField`. `CliUnreadableReason` (`native/models.swift:152-163`) is the render-side mirror.

`CliLocator` (`native/cli-client.swift:216-264`) resolution order: `CT_CLI_PATH` override (only if executable) → **bundle `Contents/Resources/cc`** → `~/.local/bin/cc` → `/opt/homebrew/bin/cc` → `/usr/local/bin/cc`. Never a bare name; `Process.executableURL` does not consult `$PATH` by design (`:210-215`).

`CliRuntimeEnvironment.childProcessEnvironment` (`native/cli-client.swift:362-397`) injects a private `TMPDIR` under `~/Library/Caches/com.everyoneneedsacopilot.controltower/cc-runtime` (0700) and sets `COPILOT_MANAGED_BY=controltower`.

### 3.3 Schemas on disk

`docs/01-architecture/schemas/` — 15 `*.schema.json` + `README.md`. Only `onboard.schema.json` pins a literal version (`"schema_version": { "const": "2.0" }`, `:15` and `:68`); `workspaces.schema.json` documents itself as schema 1.1; the rest are major-1 by convention and gated as such.

Files: `_envelope`, `auth`, `connections` (added 2026-08-02), `deprovision`, `doctor`, `freshness`, `layers`, `onboard`, `projects`, `publish`, `repair`, `resolve`, `update`, `workspace-root`, `workspaces`. Note `repair.schema.json` and `publish.schema.json` still exist as files even though ADR-008 formally defers both verbs.

### 3.4 Compat pin

`controltower.compat.json` (repo root, mirrored into every release dir):

```
app_version 0.3.2
cc: minimum 2.0.0, maximum_exclusive 3.0.0, schema_version 1.0–2.0
cli_reader: compatible_commit 48cbcf50…, release_tag v0.3.1, minimum_package_version 1.4.6
optional_hooks: verified_commit b27d45cb…, release_tag v0.1.1, policy "fail-open", max_internal_timeout 25s
```

The `optional_hooks.policy: fail-open` entry is the codified outcome of the 03-schema-mismatch incident (Discord hook must never break the harness).

---

## 4. What shipped

Git tags: `v0.1.1, v0.1.2, v0.1.3, v0.1.4, v0.1.5, v0.1.8, v0.1.9, v0.2.0, v0.2.1, v0.2.2, v0.2.3, v0.2.4, v0.3.0, v0.3.1, v0.3.2` (note the gaps at 0.1.6/0.1.7). Signed artifacts retained in `release/`: `0.2.1-e358455`, `0.2.2-a769502`, `0.2.3-1ee07ec`, `0.2.4-b84aa2b`, `0.3.0-193c4ba`, `0.3.1-f5ba1dd`, `0.3.2-e0bf0c3` — each a notarized `.dmg` (~24–25 MB) + `.sha256` + `controltower.compat.json` + `cc-notarization.json` + `release-metadata.json` (0.2.4 onward also keep the `.app`).

**Current version: 0.3.2**, built 2026-08-01 from source commit `e0bf0c380534ffbe25a3d4b69899f9bc1e31b5dd`, build number 18, arm64 only, vendored `cc 2.1.2` (sha `bd99124f…`), notarized + stapled + Gatekeeper-verified (`release/control-tower-0.3.2-e0bf0c3/release-metadata.json`). Signing identity throughout: `Developer ID Application: Pablo Alejo Jr (3SYGVX2HB8)`.

CHANGELOG arc (`CHANGELOG.md`), newest first:

- **0.3.2** (2026-08-01) — helper `cc 2.1.2`; `onboard.schema.json` gains optional `materialize` (additive to 2.0, not a bump); held/blocked materialize items surfaced honestly; warn-severity doctor no longer rolls back a verified manifest write; cold-start mirror seeding fixed.
- **0.3.1** (2026-08-01) — helper `cc 2.0.2`; ninth git-history state: a parentless foundation-snapshot pin with a byte-identical tree now classifies `current`/`reuse` instead of a permanently unclearable `diverged-identical`/`review`.
- **0.3.0** (2026-08-01) — helper `cc 2.0.1`; **onboard schema 1.0 → 2.0 breaking**; compat range moves to cc 2.0.0–<3.0.0; the 8-state history classifier, merge-base-proven fast-forward, `HEAD == target` postcondition, preflight-before-any-irreversible-write, annotated-tag peeling, `completed_actions` ledger, retryability-gated "Try again"; new packaged-binary topology gate.
- **0.2.4** (2026-07-31) — helper `cc 1.7.16`; department membership + full 16-layer Foundation/Org/Dept/Personal topology across all four components; GitHub repo or hidden mirror no longer counts as an installed layer; visible repository root; four expandable component rows replacing roster/inventory/rank lists; dedicated helper extraction cache.
- **0.2.3** (2026-07-31) — 8-layer → 12-layer additive repair with exact rollback copy; Knowledge/CLI get product-owned read-only mirrors; canonical tier role from the helper.
- **0.2.2** (2026-07-31) — "Run in Codex"/"Run in Claude Code" open a real Terminal session; Apple Events entitlement + purpose string added and release-gated.
- **0.2.1** (2026-07-30) — returning-person ecosystem view; "Finish Personal Setup"; project aftercare cards; "Personal" replaces "Private" as the tier name; helper `cc 1.7.14`.
- **0.2.0** (2026-07-30) — focused Step 7 project triage (expandable/searchable/paginated); Ready / guided setup / owner decision / couldn't-confirm detail views; helper `cc 1.7.13` from foundation tag `v5.13.15`.

Every entry from 0.2.1 onward carries an explicit **Rollback** paragraph naming the prior signed DMG, and the standing rule "Release tags are immutable; supersede a defective build with a new version."

`dist/user-release/` holds the current 0.3.2 artifacts; `dist/*.html` + `dist/assets/` are stale Tauri frontend output.

---

## 5. Initiatives and decisions in flight

### 5.1 `01-cse-auditability` — ACTIVE

Per `docs/40-initiatives/README.md`: Phase 1 + adversarial re-audit done (13/18 claims upheld, F-12 overturned); claims register live (`claims.yaml`, 38 claims, pre-commit enforced); cse-bench harness + dashboard shipped; outcome bars O-1..O-9 ratified 2026-07-13. Next step is the Outcome Program (`phases/phase-4-handoff.md`). This initiative is largely about the wider ecosystem, not the app binary.

### 5.2 `02-enac-self-onboarding` — ACTIVE, the live one

Goal: make ENAC the first real consumer of its own ecosystem, one GitHub org, no throwaway company. Naming model is `<C>-copilot` (public foundation) / `<C>-copilot-internal` (org) / `<C>-copilot-<dept>` / `<C>-copilot-private` (personal), for `<C>` ∈ {knowledge, cli, claude, codex} → 16 layers.

**ADRs (all in `decisions/`):**

| ADR | Status | One-line verdict |
|---|---|---|
| ADR-001 | Accepted 2026-07-16 | One GitHub org; the confidentiality boundary is the **repository**, not the org — no second company. |
| ADR-002 | Accepted 2026-07-16, implemented + test-backed | Org layer is always `<C>-copilot-internal` (fixed literal `internal`, a reserved department slug); departments `<C>-copilot-<dept>`; foundation stays bare. |
| ADR-003 | Accepted 2026-07-16 | Dogfood ENAC directly — no `Acme-Copilot` practice run; ENAC is the hardest case (publisher + first consumer). |
| ADR-004 | Accepted 2026-07-21 | Admin provisions shared (org) layers; the **user** provisions the personal layer; admin may never create/own/clone/inspect personal repos. ENAC's stack is personal(10) → org(30) → foundation(40). |
| ADR-005 | Accepted 2026-07-31 | Visible ecosystem repositories are the user-facing source of truth: one visible `paths.repositories_root`, Personal never lives only under `~/.copilot/mirrors`, hidden mirrors are non-authoritative, dirty trees are human-owned, departments count only with proven active membership. |
| ADR-006 | Accepted 2026-07-31 | Ecosystem setup is a **preflighted saga**, not an atomic transaction: one pure `_classify_repository_history` over 8 closed states, only merge-base-proven `fast-forwardable` may auto-repair, all deterministic preflight before any irreversible GitHub write, `HEAD == target` postcondition, a run-scoped `completed_actions` ledger, never-destroy compensation (report, never delete). |
| ADR-007 | Accepted 2026-07-31 | Onboard schema **1.0 → 2.0 breaking**: full `ecosystemLayer` required fields, a `layers_state` discriminator (`reported` \| `not-computed`) so an empty `layers` array can never masquerade as evidence, `completed_actions` required, `resume` blocked-only. |
| ADR-008 | Accepted 2026-07-31 | `repair` and `publish` are **formally deferred**: repair semantics live inside `cc onboard`'s routing; `publish` is design-record only. No doc in this repo may list either as an existing verb. |
| ADR-006 addendum | commit `3be29f4` | Parentless snapshot pins with identical trees classify as current (shipped as cc 2.0.2 / app 0.3.1). |

**Phase status.** `phases/phase-7-transaction-fix-and-owner-runbook.md:3` was written as "All 13 gaps shipped; live apply (task 215 stage B) and the release (task 216 stage B) not yet run." Both have since been closed: commit `731a3f7` "phase-7 stage C — 16/16 live apply", `59469f9` "phase-7 stage C — full acceptance achieved via cc 2.1.2", `e0bf0c3`/`589ba94` the 0.3.2 release. Session memory (`MEMORY.md`, "PRD-15 transaction fix shipped", 2026-08-01) records: **TERMINAL — ecosystem LIVE 16/16, manifest complete, v0.3.2 published (cc 2.1.2), P0 org-content destruction restored + guarded; remaining = owner content (voice/protocol/dept), V-5 cold-laptop proof, publicize.**

**Still open (owner-gated, from the runbook §5 and the ADRs):** task 218 (V-5 two-machine cold-laptop onboarding proof with an empty keychain), task 217 (scrub → rotate → publicize `knowledge-copilot` and `cli-copilot` private→public — deliberately last, irreversible, gated on credential rotation the recorded history exposure requires), cross-repo CI decision to wire the packaged-binary topology gate into `release.yml` (needs a deploy key/PAT to check out `claude-copilot`), and an unsettled MAJOR-vs-MINOR versioning tension flagged in the runbook §4 (the onboard `SchemaGate` moving to major 2 arguably meets `release-and-versioning.md` §1.1's MAJOR definition, but shipped as MINOR).

**Design corpus:** 14 HTML walkthroughs + 13 markdown specs under `walkthroughs/` (adopt-and-project-setup, truthful-setup-recovery, project-integration-aftercare, completed-setup-topology, holding copy, org-question copy, progress-and-waiting, admin-completion-departments). These are the direct source of the wizard/tray copy in `native/`.

### 5.3 `03-schema-mismatch` — COMPLETE

`docs/40-initiatives/03-schema-mismatch/README.md` (frontmatter `status: complete`). Incident: the aggregate layer manifest migrated to `product:` while CLI Copilot's resolver still filtered `component:`, so it loaded foundation-only, the org-overlay `discord` command vanished, and the `UserPromptSubmit` hook exited 2 — **Claude Code rejected every prompt**. Remediation released in Control Tower 0.1.1; the follow-on Finder-`PATH` defect (the bundled `cc` resolved `copilot` with `shutil.which`, and Finder gives `/usr/bin:/bin:/usr/sbin:/sbin`) in 0.1.2; complete headless first-run release gate in 0.1.3. Durable outputs: `product` is canonical with bounded legacy `component` compatibility and hard failure on conflicting duals; Discord hook shims are **transport fail-open**; `cc` owns machine inventory and resolves every dependency to a canonical absolute executable, the app stays parse-only; and the stated testing shape — "test the state engine directly, test the app's typed seam headlessly, then run the same headless command against the final packaged artifact. Opening the UI is a visual-product check, not the primary integration test."

### 5.4 Uncommitted work in the tree right now (2026-08-02)

`git status` shows five modified, uncommitted native files: `cli-client.swift`, `cli-dtos.swift`, `render-state.swift`, `user-settings.swift`, `wizard.swift` — **+541 / −44** lines. This is the `cc connections --json` bridge (task 221, "stage B"/"stage C"): `ConnectionsReport`/`ConnectionRow`/`ConnectionSecretState` DTOs (`native/cli-dtos.swift:286-377`), `CliClient.connections()` (`native/cli-client.swift:560-562`), `ConnectionsRender` grouping into "Ready to use" / "Available to connect" / no-store, fail-closed on an unrecognized `secret_state` (`native/render-state.swift:355-448`), rendered by wizard step 6 and the Settings "Your connections" card. The **docs** side already landed (`fc90a5e`, `docs/01-architecture/schemas/connections.schema.json`, `cli-contract.md` row); the **app** side is not committed and is not in any released binary.

---

## 6. Invariants in force — what tests actually enforce

`CLAUDE.md` states six invariants: (1) parse-never-compute, (2) single process / crash-only launchd watchdog / CLI self-serializes via `flock`, (3) never-destroy, (4) security posture inherited and never weakened (no `--skip-verify`/`--force`, compiled-in trust roots, signed inherited config), (5) route by actor-competence × reversibility, (6) one-way inheritance and secrets never travel in it.

### 6.1 The 40 `src-tauri/tests/fitness_*.rs` files

They map to invariants as follows (headers read from each file):

| Invariant | Fitness tests |
|---|---|
| #1 parse-never-compute | `fitness_no_fabricated_healthy.rs` (`CliStatus::Healthy` constructed at exactly one guarded call site), `fitness_badge_vocabulary.rs` (one badge vocabulary across Rust + TS), `fitness_m6_router_no_verdict_computation.rs`, `fitness_m9_windows_tray_reuses_badge_table.rs`, `fitness_no_bare_cli_name.rs` (no literal `"cc"`/`"copilot"` in a `Command`) |
| #2 single process | `fitness_single_process_ff_m4_7.rs`, `fitness_watchdog_plist.rs` (FF-M4-1: `KeepAlive` is a dict with `SuccessfulExit=false`, never bare `true`), `fitness_m5_loginitem_not_watchdog.rs`, `fitness_m9_windows_watchdog_no_periodic_trigger.rs`, `fitness_launch_circuit_breaker_adr_m4_001.rs`, `fitness_self_update_machinery_is_wired.rs` |
| #3 never-destroy | `fitness_m5_no_wipe_logic.rs` (no file-deletion/tree-wiping/history-destroying primitive in the app) |
| #4 security posture | `fitness_m5_single_forced_boundary.rs`, `fitness_m9_windows_forced_never_reads_hkcu.rs`, `fitness_m7_two_of_n_signing.rs`, `fitness_m9_windows_verify_pre_promote.rs` |
| #5 actor-competence routing | `fitness_m6_router_exhaustive.rs`, `fitness_m6_askbob_closed_set.rs` (exactly two Bob-facing prompts: `sign-in`, `dirty-wip`), `fitness_m5_deprovision_is_it_routed.rs`, `fitness_m6_security_banner_reaffirm_only.rs` |
| #6 secrets never travel | `fitness_no_secret_on_wizard_dto.rs`, `fitness_signin_seam_holds_no_secret.rs`, `fitness_m5_secretstore_reference_only.rs`, `fitness_m5_generator_domain_and_no_secrets.rs`, `fitness_m6_itsignal_content_free.rs`, `fitness_m6_itsignal_sink_content_free.rs`, `fitness_m7_telemetry_schema_content_free.rs`, `fitness_m7_telemetry_transport_content_free.rs`, `fitness_m9_windows_secret_store_no_secret_leak.rs` |

### 6.2 Things the fitness tests enforce that `CLAUDE.md` does not state

- **Pure OSS, no closed/paid/hosted component, ever** — `fitness_m7_no_closed_component.rs` calls this SOUL Founding Decision #1 ("openness IS the security guarantee"; named anti-pattern: the "Ledger" precedent). `CLAUDE.md` never mentions it.
- **No ETA/countdown/percentage in the wizard** — `fitness_no_eta_in_wizard.rs` (ADR-M3-003): progress by phase NAME only. This is a strong product rule that only lives in a test.
- **Telemetry is opt-in and structurally content-free** — three M7 tests plus `telemetry_fixture_corpus_shape.rs`. `CLAUDE.md` is silent on telemetry entirely.
- **Two-of-N signing custody** — `fitness_m7_two_of_n_signing.rs` extends the compiled-in-trust-root rule to k-of-N; `CLAUDE.md` mentions only "compiled-in trust roots."
- **Golden-fixture drift guards** — `fitness_m5_generator_domain_and_no_secrets.rs`, `fitness_m7_seed_fixture_drift.rs`, `dev_fixtures_in_sync.rs`, `fitness_m9_windows_uninstall_task_names_match.rs`.
- **Per-user MSI, never `ALLUSERS="1"`** — `fitness_m9_windows_wix_no_alluser_1.rs`, framed as invariant #3's admin-free constraint.
- **The security banner is structurally un-dismissable** — `fitness_m6_security_banner_reaffirm_only.rs`.

### 6.3 The load-bearing caveat

**Every one of those 40 fitness tests scans `src-tauri/src/**` — the Rust crate that no longer ships.** They cannot see a single line of the 22,650 Swift lines that are the product. `scripts/package-user-release.sh` never runs `cargo`; `.github/workflows/release.yml` does, but is disabled behind `vars.RELEASE_CI_ENABLED`. So as of today the fitness functions are a *historical* guarantee about a retired implementation, not a live gate on the shipping binary.

What actually gates the shipping binary (from `scripts/package-user-release.sh` and `.github/workflows/release.yml:61-64`): `test_headless_detect.sh`, `test_user_app_bundle.sh`, `smoke-scenarios.sh` (138 scenarios), `verify-vendored-cc.sh --release` (checksum + verify-not-resign), `verify-user-automation.sh` (rejects a signed app lacking the Apple Events entitlement or purpose string), `test_schema_compatibility_release_gate.sh`, `test_notarization_order.sh`, `plutil -lint` on the watchdog plist, `headless-setup-transaction.sh` (drives the real `WizardModel` Set up → Verify against an inert fixture helper), then notarize/staple/`spctl`. Several native-side invariants *are* enforced here — never a bare CLI name (`CliLocator`), fail-closed schema gate, selftests that refuse to run against a non-`mock-cc` helper — but they are enforced by Swift code review and shell harnesses, not by the named fitness functions.

### 6.4 Things `CLAUDE.md` states that nothing in `native/` implements

- **launchd crash-only watchdog.** `packaging/launchd/com.everyoneneedsacopilot.controltower.plist` + `install-watchdog.sh`/`uninstall-watchdog.sh` exist, and `fitness_watchdog_plist.rs` guards the plist, but grepping `native/*.swift` for `launchd|LaunchAgent|KeepAlive` returns **zero** production hits (the only `watchdog` matches are unrelated in-app async timeouts, e.g. `native/control-tower-tray.swift:912,957,1235`). The shipping app does not install or manage the LaunchAgent.
- **Self-update.** No `minisign`, no update-feed, no staged-bundle rollback anywhere in `native/`. That machinery is entirely `src-tauri/src/updater/`. Users update by reinstalling a DMG (which is exactly what every CHANGELOG **Rollback** paragraph instructs).
- **`flock` on `copilot.lock`.** Asserted as the CLI's job; nothing in the app observes or references it.

---

## 7. Conspicuous absences — what was deliberately NOT built

| Absent thing | Status | Where it says so |
|---|---|---|
| **`cc repair` verb** | Deferred, not scheduled. Repair semantics live inside `cc onboard`'s 8-state routing. | `ADR-008` §Decision 1–2; `docs/01-architecture/cli-contract.md` "Deferred verbs" |
| **`cc publish` verb** (author-side push of a writable tier) | Formally deferred; the full design (auto-merged / needs-choice / parked-escalated, CLI-computed conflict chooser, fail-closed `leak_scan`) is preserved as *design record only*. `publish.schema.json` still exists. | `ADR-008` §Decision 3; `cli-contract.md` "`copilot publish --json` — deferred design"; `CLAUDE.md` invariant 1 |
| **`copilot promote`** (private→public curation valve) | Not built; the first base extraction is a manual one-time curation; whether to build it is an open decision. | `docs/40-initiatives/02-enac-self-onboarding/README.md` §Non-Goals |
| **A second GitHub org** | Explicitly rejected. | `ADR-001`; `README.md` §Non-Goals |
| **An `Acme-Copilot` throwaway practice run** | Explicitly rejected. | `ADR-003` |
| **Windows** | Deferred to P4; the parity doc carries a "BUILT-BUT-UNVERIFIED-ON-WINDOWS" honesty stamp — every line was authored and `cargo test`-proven on a Mac with no Windows toolchain, and "Do not read a row's status below… as evidence Control Tower has ever actually run on Windows — it has not." The whole Windows surface (10 `fitness_m9_*` tests, `packaging/windows/wix`, `packaging/taskscheduler`, `scripts/sign-windows.ps1`) is in the retired Rust tree. | `docs/01-architecture/windows-parity.md:1-20`; `docs/00-overview/product-brief.md:42`; `CLAUDE.md` "Tech" |
| **MDM / `.mobileconfig` forced config** | Designed and Rust-implemented (M5: `src-tauri/src/mobileconfig/`, `packaging/mobileconfig/sample-acme-corp.mobileconfig`, `fitness_m5_single_forced_boundary.rs`, `fitness_m5_generator_domain_and_no_secrets.rs`); **zero references in `native/*.swift`**. Not in the shipping app. | grep of `native/` |
| **Deprovision UI** | Same: `src-tauri/src/deprovision/`, `deprovision.schema.json`, two M5 fitness tests — no Swift caller. | grep of `native/` |
| **Telemetry / fleet dashboard** | Rust-only (`src-tauri/src/telemetry/`, `src/fleet.html`, four M7 fitness tests). No Swift equivalent; the native Admin app has an "Analytics" governance surface with an `analyticsEnabled` toggle (`native/admin.swift:823,1661`) but no emitter. | grep of `native/` |
| **In-app self-update** | Not in the native app (§6.4). Rollback = reinstall the prior signed DMG. | every CHANGELOG "Rollback" section |
| **Zero-touch install** | Rejected; the Bob self-install path is the critical path. | `docs/02-prd/prd.md:41` (D4) |
| **App-side resolution/sync/merge logic** | Prohibited by construction. | `CLAUDE.md` invariant 1; `docs/START-HERE.md` "How to proceed" item 3 |

---

## 8. Where reality has drifted from the written record

1. **`docs/START-HERE.md` is stale.** It says "Version **0.2.4** is the latest tagged release" and "the shipped 0.2.4 release carries helper version **cc 1.7.16**", and directs the reader to `phase-6-v0.2.4-live-setup-blocker-handoff.md` as "the current pickup." Reality: 0.3.2 / cc 2.1.2, the blocker is closed, and the live 16/16 apply succeeded. It also states "~19,600 lines of Swift"; today it is ~20,336 in `native/` alone.
2. **`docs/40-initiatives/README.md`** (a generated index) still shows `02-enac-self-onboarding` as blocked on the 0.2.4 defect.
3. **`src-tauri/Cargo.toml:3` = `0.2.4`** while everything else is `0.3.2`.
4. **`CLAUDE.md` invariant 2's watchdog claim** describes packaging assets and Rust code, not the shipping Swift app (§6.4).
5. **`docs/01-architecture/windows-parity.md` and `docs/06-deployment/m9-owner-gated-split.md`** describe a Windows port of an implementation that has been retired.
6. **`repair.schema.json` and `publish.schema.json` still sit in `schemas/`** even though ADR-008 defers both verbs — the schemas README still lists `publish` and `resolve` rows without a deferred marker (the prose in `cli-contract.md` does carry the marker).
7. **`docs/02-prd/prd.md`'s WS-B…WS-I workstream spine** describes a Tauri-era plan (WS-D self-update, WS-G telemetry/IT dashboard, WS-I Windows re-skin) that the native rebuild did not carry over.
