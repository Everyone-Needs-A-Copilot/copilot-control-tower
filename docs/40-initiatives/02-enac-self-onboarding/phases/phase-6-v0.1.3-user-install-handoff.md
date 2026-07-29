# Phase 6 — Control Tower 0.1.3 user-install handoff

> Initiative: [`02-enac-self-onboarding`](../README.md)
>
> Incident companion:
> [`03-schema-mismatch`](../../03-schema-mismatch/README.md)
>
> Previous implementation record:
> [`phase-6-honest-setup-work-record.md`](phase-6-honest-setup-work-record.md)
>
> Previous handoff:
> [`phase-6-honest-setup-handoff.md`](phase-6-honest-setup-handoff.md)
>
> **This is the continuation source of truth as of 2026-07-29.** The previous
> handoff accurately records how the work evolved, but its branch, release, and
> owner-action status is historical. Start here before acting.

## 1. Pickup in one minute

Control Tower **0.1.3 build 4 is published, signed, notarized, stapled, and
approved by the repository QA gate**. It embeds `cc 1.7.10`. The exact
downloadable app has passed the complete production Detect seam against this
Mac and the production Set up → Verify orchestration against an inert helper.

The user has not yet confirmed the real live Set up transaction with 0.1.3.
That is the next product proof. The user explicitly does not want a throwaway
account, repeated GUI launches during development, or an agent mutating the
live Claude/Codex setup to manufacture a test. They will install and run it
themselves once it is ready. It is ready now.

The next developer should therefore:

1. Ask the user to replace 0.1.1 with the published 0.1.3 app, if they have not
   already done so.
2. Do **not** ask them to reinstall or rerun the Admin app. The organization
   handoff exists and the released app's real read-only Detect found
   `Everyone-Needs-A-Copilot`.
3. If the user reports a failure, collect the support details and app version,
   then reproduce the background path with `scripts/headless-detect.sh` before
   considering another GUI run.
4. Never run the real `--apply` transaction on the user's behalf unless they
   explicitly change the current instruction.

## 2. Exact repository and release state

| Item | State |
|---|---|
| Repository | `Everyone-Needs-A-Copilot/copilot-control-tower` |
| Working branch | `app-build` |
| Branch HEAD | `7ab408ba648f87c907422a072b1f88cd1afd43b7` |
| Remote state at handoff | `app-build` equals `origin/app-build` |
| Release source commit | `078adc18c76d4eace2ddab22f5cfabc0bf05dbd7` |
| Tag | annotated `v0.1.3`, pointing to the release source commit |
| Release | <https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/releases/tag/v0.1.3> |
| Release state | published; not draft; not prerelease |
| App version/build | `0.1.3 (4)` |
| DMG | `Copilot-Control-Tower_0.1.3_arm64.dmg` |
| DMG SHA-256 | `41f8c79472a43b21660efc143fa00b62b41a6caaa2d0c955391b5a3153423173` |
| App/DMG notarization | `e8b59eb8-f105-4b86-bc0c-8e14e16787f3` — Accepted |
| Embedded helper | `cc 1.7.10` |
| Embedded helper SHA-256 | `6f9a1f329b68cf1a433ff54fc1839c11288ec342b718eeb54e2d5eece39f4d7c` |

Release assets also include `release-metadata.json`,
`controltower.compat.json`, `cc-notarization.json`, and the DMG checksum.
GitHub reports the uploaded DMG digest as the same SHA-256 above.

The release tag is on the `app-build` history; do not assume the repository's
default `main` branch contains this release. Start a repair from `app-build`,
`v0.1.3`, or the exact release commit after checking the intended integration
target.

At handoff, the only unrelated local workspace state was:

```text
 M .obsidian/appearance.json
?? release/
```

Those paths belong to the user. Do not stage, overwrite, clean, or delete them.

## 3. What the user is trying to achieve

The user wants the signed User app to inspect the current Mac, explain the
personal + organization + foundation setup it will establish for Claude and
Codex, apply it once with explicit consent, verify it, and then supervise the
installed ecosystem.

The intended ownership boundary is:

- **Admin app:** organization-level shared setup and public bootstrap handoff.
- **User app:** the person's GitHub connection, device identity, personal
  packages, aggregate layer manifest, materialization, Codex plugin, and final
  health check.
- **`cc`:** the only authority that reads or mutates machine ecosystem state.
- **Control Tower:** a typed client and orchestration/UI layer; it must not
  recreate inventory or mutation rules.

The user does not need a test company or test account. ENAC is deliberately
dogfooding the exact customer path.

## 4. Why repeated attempts failed

Several independent defects appeared at the same visible wizard step. Treating
them as one generic “Detect is broken” problem caused repeated GUI-driven
iterations.

### 4.1 Schema migration broke Claude Code

The aggregate manifest writer emitted canonical `product: cli`, while the
installed CLI layer resolver still filtered legacy `component: cli`. The
resolver silently dropped the organization CLI layer, including the Discord
command. A user-level Claude hook then ran the missing command and returned
nonzero, so Claude Code rejected every prompt.

The remediation made `product` canonical, retained bounded legacy read
compatibility, rejects contradictory dual declarations, and made the optional
Discord transport fail open. Full details and prevention rules are in
[`03-schema-mismatch`](../../03-schema-mismatch/README.md).

### 4.2 An early packaged Python helper was not self-contained

The user supplied a macOS crash report for Python 3.13.13. `dyld` could not
load:

```text
/Library/Frameworks/Python.framework/Versions/3.13/Python
```

That report proves the launched helper depended on a framework absent from the
machine. Do not infer more than the crash proves. The current release no longer
uses that artifact: it embeds a checksum-pinned, signed, notarized universal
`cc` executable and verifies the embedded bytes during packaging.

### 4.3 GitHub organization discovery was unavailable

Earlier builds reached `onboard-unavailable` while listing organizations. The
subsequent device-flow and organization-handoff work established the dedicated
OAuth identity, required GitHub scopes, and public bootstrap contract. The
current released artifact's real Detect decoded:

```text
auth=authorized
login=pablitoalejo
scopes=read:org,repo,write:public_key
org=Everyone-Needs-A-Copilot
```

Do not restart Admin setup merely because this historical error existed.

### 4.4 Control Tower 0.1.1 could not find `copilot` from Finder

The app found its bundle-relative `cc` helper, but that helper used only
`shutil.which` to find its own `copilot` dependency. Finder supplies a minimal
`PATH`, so `/opt/homebrew/bin/copilot` disappeared even though it worked in a
terminal. The visible result was:

```text
Step: layer-manifest
Result: blocked
Message: The installed `copilot` command is unavailable.
```

`cc 1.7.10` fixes this at the state-owner boundary by resolving `gh`,
`copilot`, `claude`, and `codex` from the current `PATH` and bounded canonical
macOS locations. Upstream changes:

- <https://github.com/Everyone-Needs-A-Copilot/claude-copilot/pull/46>
- <https://github.com/Everyone-Needs-A-Copilot/claude-copilot/pull/47>

### 4.5 The first headless proof was too narrow

Control Tower 0.1.2 could reproduce the onboarding plan without opening the
app, but the real Detect step makes three concurrent production calls:

1. `cc auth status --json`
2. `cc doctor --json`
3. `cc onboard --org auto --products claude,codex --json`

Testing only call 3 left two unproven failure boundaries. It also exposed a
logic error: a successfully decoded `signed-out` auth envelope advanced as if
it meant signed in. Version 0.1.3 runs all three calls through the same typed
client used by `WizardModel.performDetect` and returns to device flow for
signed-out accounts.

## 5. The corrected testing architecture

Confidence now comes from three concentric production seams:

1. **Engine seam.** `cc` owns inventory, plan/apply, manifest adoption,
   materialization, rollback, and final doctor verification. Its transaction
   and rollback behavior is tested directly in disposable state.
2. **App boundary seam.** `--headless-detect` invokes the exact three
   `CliClient` calls used by the real wizard, with the normal bundle-relative
   helper lookup, `Process` boundary, schema checks, and typed decoders. It
   exits before creating UI and never passes `--apply`.
3. **Orchestration seam.** A guarded self-test drives the production
   `WizardModel` Set up → Verify path against the inert `mock-cc`. The helper
   records argv, independently proving the exact apply and verify commands.

The release pipeline executes seams 2 and 3 against the exact signed app before
notarization. The final mounted DMG was then tested again.

Opening the UI remains necessary for visual and interaction review. It is not
the primary way to diagnose background logic.

## 6. Control Tower 0.1.3 implementation

Release commit `078adc1` contains the complete change.

### Production changes

- `native/control-tower-tray.swift`
  - expands `--headless-detect` to auth, doctor, and onboarding;
  - reports typed results and the exact call list;
  - fails its contract for helper absence, unreadable boundaries, signed-out
    auth, missing layer-manifest inspection, and the known installed-copilot
    blocker;
  - adds a guarded production `WizardModel` setup-transaction self-test.
- `native/wizard.swift`
  - routes a decoded signed-out account back to Connect GitHub/device flow
    instead of claiming “GitHub: signed in.”
- `src-tauri/fixtures/mock-cc`
  - optionally logs received argv through `CT_MOCK_INVOCATION_LOG`.

### Test and release controls

- `scripts/headless-detect.sh`
  - read-only;
  - uses Finder's minimal `PATH` by default;
  - requires all three production calls and both products.
- `scripts/headless-setup-transaction.sh`
  - requires `CT_ALLOW_INERT_SETUP_PROOF=1`;
  - requires the override helper's basename to be `mock-cc`;
  - proves the real `WizardModel` emits:

    ```text
    onboard --org auto --products claude,codex --apply --json
    doctor --json
    ```

- `scripts/package-user-release.sh`
  - runs both headless seams against the signed app before DMG creation and
    notarization.
- `scripts/tests/test_user_app_bundle.sh`
  - covers the positive bundle path and negative unreadable/signed-out
    boundaries.
- `scripts/tests/test_headless_detect.sh`
  - covers the shell harness contract.

Version references were advanced to 0.1.3/build 4 across package, Cargo, Tauri,
macOS plist, compatibility, and Winget metadata.

## 7. Evidence supporting the release decision

The repository's QA task is `TASK-176`:

```text
P0 prove complete first-run journey headlessly to 95% release confidence
status=completed
metadata.requiresQa=true
```

Work products:

| ID | Type | Purpose |
|---|---|---|
| WP-252 | architecture | state-owner and three-seam testing decision |
| WP-253 | implementation | complete Detect and setup-proof changes |
| WP-254 | test | detailed release evidence and residual risk |
| WP-255 | test | gate-conformant approved verdict |

The final repository gate passes:

```bash
scripts/copilot-gate.sh --task 176
```

Result:

```text
QA gate passed (1 QA-required task(s) checked)
```

### Engine evidence

- focused onboarding transaction and rollback suite: **41 passed**;
- non-optional `cc` suite: **1,134 passed**;
- a broader optional run produced 1,154 passes, 3 failures caused by a missing
  optional Task Copilot import, and 14 collection errors caused by an
  incompatible optional MCP test dependency. Those tests are outside the
  onboarding release claim and are recorded rather than hidden.

### Control Tower evidence

- `cargo fmt --check`: passed;
- `cargo clippy --all-targets -- -D warnings`: passed;
- `cargo test --all-targets`: passed, including **700 Rust unit tests** and all
  fitness targets;
- native app scenario matrix: **110 passed, 0 failed**;
- CLI seam scratch driver: passed plan/apply decoding, rollback evidence,
  workspace, auth, doctor, and fail-closed schema cases;
- User bundle, schema compatibility, signed vendored helper, foundation
  snapshot, smoke launch, headless Detect, and headless setup gates: passed.

### Exact downloadable artifact evidence

The final mounted DMG app:

- passed strict code-sign verification;
- was accepted by Gatekeeper as `Notarized Developer ID`;
- had a valid staple, as did the DMG;
- ran real read-only Detect through embedded `cc 1.7.10`:

  ```text
  contract=pass
  read_only=true
  auth=authorized
  org=Everyone-Needs-A-Copilot
  products=claude,codex
  layer-manifest=changes-required/repair
  ```

- ran production Set up → Verify against the inert fixture:

  ```text
  apply=ready
  layer-manifest=applied
  onboardDoctor=healthy
  verify=healthy
  ```

This supported a **96% confidence** statement for the current Mac's background
first-run path. The remaining uncertainty is described in §11.

## 8. What the user should do next

The published installer is:

<https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/releases/download/v0.1.3/Copilot-Control-Tower_0.1.3_arm64.dmg>

The user path is:

1. Quit Control Tower 0.1.1.
2. Open the 0.1.3 DMG.
3. Replace `/Applications/Copilot Control Tower.app`.
4. Launch the app and complete User Setup.

They do **not** need to:

- reinstall the Admin app;
- rerun organization setup;
- create a test GitHub account;
- manually repair the layer manifest before launching;
- manually run `cc onboard`.

The real read-only plan says the current layer manifest needs a reversible
repair. That is expected work for User Setup, not a new blocker. A doctor status
of `update-available` with a readable report is also not itself a Detect
failure.

## 9. Safe diagnosis if the user reports another blocker

First establish that they are running 0.1.3. The support block must show:

```text
Copilot Control Tower 0.1.3 (4)
```

Then ask for the complete support details and one screenshot. Do not ask them
to repeat Admin setup by default.

Run the installed app's exact Detect path without opening a window:

```bash
scripts/headless-detect.sh \
  --app "/Applications/Copilot Control Tower.app"
```

This command is read-only. Preserve its JSON as evidence. It must report:

```json
{
  "mode": "headless-detect",
  "read_only": true,
  "calls": ["auth-status", "doctor", "onboard-plan"],
  "products": ["claude", "codex"],
  "contract": "pass"
}
```

Also verify the installed artifact before blaming machine state:

```bash
codesign --verify --deep --strict --verbose=2 \
  "/Applications/Copilot Control Tower.app"

spctl --assess --type execute --verbose=2 \
  "/Applications/Copilot Control Tower.app"

"/Applications/Copilot Control Tower.app/Contents/Resources/cc" --version
```

If the background Detect passes but the UI does not, the problem is now in
wizard state/rendering rather than machine inventory. Reproduce it with a
scenario or add a deterministic self-test before opening the app again.

If Detect fails:

1. Identify which typed boundary failed: `auth_error`, `doctor_error`, or
   `onboard_error`.
2. Run only the corresponding read-only embedded-helper command.
3. Check Finder-path resolution rather than relying on terminal `PATH`.
4. Fix the state owner (`cc`) if inventory is wrong; do not add duplicate
   executable discovery to Swift.
5. Add the failure to the headless release gate before publishing another
   build.

Do not run `cc onboard ... --apply`, rewrite Claude/Codex hooks, edit the live
manifest, refresh GitHub scopes, or alter Keychain state merely to diagnose a
read failure. Those actions require evidence and explicit authority.

## 10. Re-running the non-UI proof

Against a locally built or mounted app:

```bash
scripts/headless-detect.sh --app "/absolute/path/Copilot Control Tower.app"

scripts/headless-setup-transaction.sh \
  --app "/absolute/path/Copilot Control Tower.app"
```

The first command uses the real embedded helper and current signed-in session,
but is plan-only. The second command substitutes the inert fixture and cannot
touch the user's setup.

The setup harness must print:

```text
SELFTEST setupTransaction apply=ready layerManifest=applied onboardDoctor=healthy verify=healthy
```

Do not weaken the self-test's three guards:

- explicit `CT_SETUP_TRANSACTION_SELFTEST=1`;
- explicit `CT_ALLOW_INERT_SETUP_PROOF=1`;
- a `CT_CLI_PATH` whose basename is exactly `mock-cc`.

## 11. Residual risk and incomplete acceptance

The release work is complete. The larger Phase 6 user-install proof is not yet
complete because the user has not reported the outcome of the real 0.1.3 apply.

Known residual risk:

- GitHub or network state can change between a read-only plan and the user's
  later apply.
- The real mutating transaction was deliberately not run against the user's
  live machine during development.
- Mutation and rollback are hermetically tested, and the exact app
  orchestration is tested against an inert helper, but only the user's
  authorized run can close the final live-apply acceptance.
- A full manual latest-artifact visual walkthrough was deliberately avoided
  during the final confidence pass because repeated app launches disrupted the
  user's workflow. Existing scenario and smoke coverage remains green.
- The initiative's separate cold second-machine proof and foundation trust
  anchor work remain broader Phase 6 items; they are not required for this
  Mac's 0.1.3 install attempt.

Do not conflate “0.1.3 is release-ready” with “Phase 6 is fully complete.”

## 12. Trust and machine-safety rules carried forward

These are release requirements, not optional cleanup:

1. Test the engine directly, the app boundary headlessly, and the final signed
   artifact.
2. Never treat terminal success as proof of Finder success.
3. Never let a mock replace the final embedded-helper integration gate.
4. Keep `cc` as the single machine-state and mutation owner.
5. Make optional transports such as Discord fail open so they cannot disable
   Claude Code or Codex.
6. A schema writer must prove compatibility with the installed reader before
   moving the live pointer.
7. Preserve exact prior bytes and require rollback evidence for machine
   mutations.
8. Run live diagnosis read-only until the failing boundary is known.
9. Do not change user hooks, manifests, Keychain entries, SSH configuration, or
   GitHub grants as incidental test setup.
10. Preserve unrelated dirty-worktree state.
11. Package from the exact pushed source ref and verify the mounted download,
    not merely the staging build.
12. One user screenshot may reveal a visual or state-routing defect that
    headless tests cannot; use it intentionally, not as the primary test loop.

## 13. Related commits and records

Control Tower:

- `d43deb5` — contain the schema mismatch and replace `cc 1.7.8`;
- `1288aa6` — Control Tower 0.1.1 release source;
- `bde5290` — make Detect reproducible without UI;
- `c0fc74a` — merge Finder Detect fix, Control Tower 0.1.2 line;
- `078adc1` — complete first-run path headlessly, Control Tower 0.1.3 source;
- `7ab408b` — record complete first-run release evidence.

Upstream `cc`:

- PR 46 merge `703c5cdd01ba835674849127eb7a41a279c06e16` — bounded
  executable discovery for Finder;
- PR 47 merge `c03ffa440ef252e31f67ec93dc8f7ad672261df8` — release
  Finder-path gate.

Incident detail, quarantine history, schema decisions, and the complete
prevention checklist remain in
[`03-schema-mismatch`](../../03-schema-mismatch/README.md).

## 14. Exact continuation checklist

- [x] Publish Control Tower 0.1.3.
- [x] Verify release source provenance and uploaded checksum.
- [x] Verify Apple notarization, staple, code signature, and Gatekeeper.
- [x] Run exact mounted-artifact Detect against the real current machine.
- [x] Run exact mounted-artifact Set up → Verify orchestration inertly.
- [x] Record an evidence-bound QA verdict and pass the project QA gate.
- [ ] User replaces 0.1.1 with 0.1.3.
- [ ] User completes the real User Setup transaction.
- [ ] Record the resulting support details and doctor state.
- [ ] If healthy, mark this-Mac User Setup acceptance complete.
- [ ] Continue the separate cold second-machine Phase 6 proof.
