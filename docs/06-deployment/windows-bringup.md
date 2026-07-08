# Windows bringup runbook — turning M9's owner-gated items into a checklist

> **OWNER-GATED, in full.** This runbook exists because M9 (Windows re-skin,
> `tc task get 80`, Stream-Z close-out) could only ever produce
> `#[cfg(windows)]`-gated Rust, WiX/MSI config, and a PowerShell signing
> script authored and reviewed **on a Mac with no Windows toolchain, no
> `rustup` Windows target, no `pwsh`, no `signtool.exe`, and no EV
> certificate.** Nothing in this runbook has been executed. Every step below
> is the exact, batched, single-session checklist an owner with a real
> Windows box + an EV code-signing certificate follows to turn "code-complete
> and cfg-gated" into "actually verified on Windows." See
> `../01-architecture/windows-parity.md` §5 (the verification matrix this
> runbook closes out) and `m9-owner-gated-split.md` (the buildable-now vs.
> owner-gated split this runbook operationalizes).

**Who this is for:** an owner/maintainer with (a) a Windows 10/11 box (a VM is
fine for most steps; steps 9–10 want a domain-joined/MDM-enrolled machine),
(b) an EV (Extended Validation) code-signing certificate, and (c) admin
access to a test Intune or GPO console for the enrollment/notification steps.

**What "done" looks like:** every row in `windows-parity.md` §5 that currently
reads "owner must still verify" has that column crossed off, with a dated note
of what was actually observed (pass, fail, or "behaves differently than
designed — filed as a follow-up ADR").

---

## 0. Before you start

- [ ] Clone this repo on the Windows box (or a share/CI runner reachable from
      it). Do **not** hand-edit anything under `src-tauri/src/platform/windows/`
      to "make it compile" — if it doesn't compile as checked in, that is a
      real M9 defect to report back (file it against `tc task get 80`'s
      findings), not something to patch silently on the bringup box.
- [ ] Install the Rust MSVC toolchain: `rustup target add x86_64-pc-windows-msvc`
      (or install `rustup` fresh if this is a bare Windows box — the Windows
      installer at rustup.rs, not the shell-script installer).
- [ ] Install the Visual Studio Build Tools (MSVC linker + Windows SDK) —
      required for both the Rust MSVC target and `signtool.exe`.
- [ ] Install Node.js (matching the version this repo's `package.json`/CI
      pins) for `npm run build`.
- [ ] Install WiX Toolset v3 (Tauri's `bundle.windows.wix` target) if not
      already bundled with the Tauri CLI's own toolchain fetch.

## 1. First real Windows build (closes: "Windows build itself" in
   `m9-owner-gated-split.md`)

- [ ] `cd src-tauri && cargo build --target x86_64-pc-windows-msvc` — this is
      the FIRST time this exact code has ever compiled for Windows. Expect to
      find real compile errors: the `windows` crate 0.61 API surface used in
      `platform/windows/cli_path.rs`'s `SetDefaultDllDirectories` call and the
      `keyring` crate's `windows-native` feature name in `secret_store.rs`
      were both authored against documented APIs but explicitly flagged
      unverified (see those files' own doc comments) — fix any signature
      mismatches here, they are expected, not a sign the design is wrong.
- [ ] `cargo build --target x86_64-pc-windows-msvc --release`
- [ ] `cargo clippy --target x86_64-pc-windows-msvc --all-targets -- -D warnings`
- [ ] `cargo fmt --check` (should already be clean — this is cross-platform
      text formatting, not something the Windows target changes)
- [ ] `cargo test --target x86_64-pc-windows-msvc` — this is the FIRST time
      every `#[cfg(windows)]` test in `platform/windows/*.rs` and the nine
      `fitness_m9_windows_*.rs` files actually runs. Run it **twice** for
      determinism, matching the macOS-side discipline this milestone already
      applied.
- [ ] `npm run build` (the frontend is genuinely cross-platform; this step is
      a sanity check, not expected to surface Windows-specific issues)

**Report back:** paste the full `cargo test` Windows output (pass/fail counts)
into a WP against `tc task get 80` or a fresh follow-up task — this is the
first real Windows-side data point M9 has ever had.

## 2. Crash-only watchdog (closes: row 1, ADR-M9-002)

- [ ] Install the watchdog task from the checked-in template:
      `packaging/taskscheduler/controltower-watchdog.xml` (substitute
      `__APP_EXE__` — `platform::windows::watchdog::install` does this
      in-process; verify it actually ran via `schtasks /Query
      /TN "\EveryoneNeedsACopilot\ControlTowerWatchdog" /XML`).
- [ ] **Crash test:** kill the running app with a non-zero exit (e.g. a
      debug build's deliberate panic path, or `taskkill /F`). Confirm Task
      Scheduler relaunches it within the `<Interval>` window, up to the
      `<Count>` cap, and STOPS relaunching after the cap is hit (this is the
      one behavior no fitness test here could ever simulate — it needs a
      real failing process and a real scheduler tick).
- [ ] **Clean-quit test:** Quit the app normally (exit 0). Confirm Task
      Scheduler does **not** relaunch it. This is the single most
      invariant-critical check in this whole runbook (CLAUDE.md invariant #2)
      — if this fails, STOP and file a P0 defect; do not proceed to
      packaging.
- [ ] **Hang test:** simulate a hang (freeze the process without exiting).
      Confirm the `updater::heartbeat` file goes stale and the reused
      `updater::circuit_breaker` logic reacts as designed — Task Scheduler
      itself has no native hang detection (only exit-code-triggered restart),
      so this exercises the app-level heartbeat path, not Task Scheduler.
- [ ] Tune `RESTART_RETRY_COUNT`/`RESTART_RETRY_INTERVAL` (in
      `platform/windows/watchdog.rs`) against what you actually observed —
      these are currently reused, unvalidated macOS constants (ADR-M9-006
      names this explicitly as a placeholder).

## 3. Forced/managed config domain (closes: row 3, ADR-M9-003,
   sec-reviewed-ACCEPT with one residual)

- [ ] On an **unmanaged** (not domain-joined, not MDM-enrolled) Windows box:
      write a value directly to
      `HKLM\Software\Policies\ENAC\ControlTower` (as a local admin, via
      `reg add`). Confirm the app treats it as `Absent`, never `Forced` —
      this is the core ADR-M9-003 guarantee. Check the audit log line
      (`audit_unenrolled_policy_value_ignored`) actually fires.
- [ ] On a **real** domain-joined or Intune-MDM-enrolled Windows box: push
      the same policy via GPO or an Intune configuration profile. Confirm
      `dsregcmd /status` reports enrolled, and confirm the app now honors the
      `HKLM\...\Policies` value as genuinely `Forced`.
- [ ] Test every enrollment state Intune/GPO can actually produce (hybrid
      Azure AD join, workplace-join-only, GPO-only-no-Azure-AD) — the
      `dsregcmd`-output parser was authored against documented output shapes,
      never exercised against real output.
- [ ] **Known, accepted, NOT-closed residual (sec-reviewed, see
      `tc wp get 57`):** confirm for yourself that a local admin on an
      unmanaged/BYOD machine CAN self-service domain-join a lab AD domain or
      register a free Azure AD tenant, and that `dsregcmd` will legitimately
      then report "enrolled." This is inherent to what "domain-joined" means
      as a Windows API answer, not a bug in this code — do not expect this
      runbook step to "fail" a fixable defect; it is here so the residual is
      observed once for real, not just reasoned about.

## 4. Secrets (closes: row 4, ADR-M9-001, sec-reviewed-ACCEPT)

- [ ] Confirm `platform::windows::secret_store::secret_store_endpoint()`
      correctly resolves the shared secret-store URL/tier reference under
      the SAME forced-domain conditions as step 3 above (this module only
      ever reads an endpoint reference — it never touches Credential
      Manager/DPAPI directly; see that file's own scope note).
- [ ] **Separately** (not this app's code, but the CLI's, per
      `credentials-and-boundary.md` §1.6.4): re-verify DPAPI's actual
      unlock/ACL behavior for the real per-secret storage the CLI performs —
      confirm whether anything else running as the same logged-in user can
      read a DPAPI-protected secret without a separate prompt (the flagged
      `credentials-and-boundary.md` §6.5 gap).

## 5. Code signing + SmartScreen (closes: row 5, ADR-M9-004)

- [ ] Acquire an EV code-signing certificate; import it into
      `Cert:\CurrentUser\My` (or `Cert:\LocalMachine\My`) and note its SHA-1
      thumbprint.
- [ ] Set `CT_SIGN_THUMBPRINT` and `CT_SIGNTOOL_PATH` (absolute path to
      `signtool.exe` from the Windows SDK — never rely on `PATH`) and run
      `scripts/sign-windows.ps1` for real, against a real built MSI — this
      is the FIRST execution of this script ever; it has only ever been
      authored and (this session) could not even be `pwsh`-syntax-checked
      (no PowerShell host on the authoring machine).
- [ ] `signtool verify /pa /tw` against the signed MSI — confirm it matches
      what `updater::verify::verify_authenticode`'s production call shape
      expects (same `/pa /tw` flags).
- [ ] Install the freshly-signed, freshly-built MSI on a clean Windows VM
      with default SmartScreen settings. Observe whether the "Windows
      protected your PC" interstitial appears (expected for a brand-new
      cert/binary with no reputation yet — this is the SmartScreen gap
      ADR-M9-004 names, not a signing failure).
- [ ] For the air-gapped-fleet mitigation: push an Intune/GPO
      `SmartScreenForTrustedAppsEnabled` policy and confirm it actually
      suppresses the interstitial for this specific signed binary, offline
      (no network reputation lookup). This is the one empirical claim
      ADR-M9-004's "recommendation" status rests on and has never been
      checked.

## 6. Tray light/dark icon (closes: row 6, ADR-M9-001)

- [ ] Launch the app with the system in Light mode; confirm the tray icon
      renders dark-on-light and is legible.
- [ ] Switch to Dark mode via Settings > Personalization > Colors, WITHOUT
      restarting the app. Wait one poll interval (`timer::poll_once`'s
      cadence). Confirm the icon repaints light-on-dark.
- [ ] Time how long the repaint actually takes to appear after the toggle —
      this is poll-driven, not a live `WM_SETTINGCHANGE` hook (a documented,
      deliberate scope cut); confirm this reads as "live enough" in practice
      or file a follow-up if it's jarringly slow.
- [ ] Manually hide the tray icon into the "hidden icons" overflow chevron
      and confirm the app still functions (this is a UX parity gap named in
      `windows-parity.md` row 6, not an invariant risk — just confirm nothing
      actually breaks).

## 7. CLI path resolution + DLL hijack hardening (closes: row 7,
   ADR-M9-005 Q6)

- [ ] Confirm `platform::windows::cli_path::resolve()` finds the vendored
      `cc.exe` via the `current_exe()`-relative path in a normal install (no
      registry fallback needed).
- [ ] **Hijack test:** plant a decoy `cc.exe` earlier in `%PATH%` and a decoy
      DLL in a writable cwd the app might be launched from. Confirm `resolve()`
      never even looks at `%PATH%` (already fitness-tested at the source
      level; this step is the live confirmation) and that
      `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)` actually
      compiles with the `windows` crate 0.61 signature used and genuinely
      removes the cwd from the DLL search order (use Process Monitor to
      watch the actual search order at runtime).

## 8. Packaging / uninstall (closes: rows 10–11, ADR-M9-005)

- [ ] Build the MSI (`packaging/windows/wix/main.wxs`) via the Tauri
      bundler; confirm the install is genuinely **per-user, admin-free**
      (no UAC elevation prompt at install time — `InstallScope="perUser"`,
      `ALLUSERS` unset).
- [ ] Confirm the winget manifests
      (`packaging/windows/winget/EveryoneNeedsACopilot.ControlTower*.yaml`)
      validate against the real `winget validate` schema checker.
- [ ] **Uninstall-orphan test (the never-orphan guarantee, invariant #3):**
      uninstall via "Apps & Features" (or Control Panel). Confirm:
      - the logon-trigger task (`EveryoneNeedsACopilot\ControlTowerLogon`)
        is gone from `schtasks /Query`
      - the crash-watchdog task (`EveryoneNeedsACopilot\ControlTowerWatchdog`)
        is gone from `schtasks /Query`
      - no leftover Credential Manager entries remain
      - none of this required a second admin-elevated cleanup step
- [ ] Confirm the WiX custom action (`uninstall-customaction.rs`) only fires
      on a genuine uninstall (`REMOVE="ALL"` and NOT
      `UPGRADINGPRODUCTCODE`) — install an update in place and confirm the
      tasks/credentials are NOT wiped mid-upgrade (only on real removal).

## 9. Notifications (closes: row 8 — genuinely unbuilt, not just
   unverified)

- [ ] **This step starts from zero code**, unlike every step above — as of
      this runbook, `src-tauri` has no `tauri-plugin-notification` dependency
      and no toast-wiring source file at all (confirmed by Stream-Z, see
      `windows-parity.md` §5 row 8). Before running any test here, a future
      session first needs to actually implement Windows toast notification
      wiring (via Tauri's notification plugin) and the "fallback-to-IT-
      channel is primary" conservative-default code path §3 item 4 names as
      a decision but which has no corresponding code yet.
- [ ] Once that code exists: on a real Intune or GPO test console, attempt
      to centrally force-enable this app's notification permission for a
      managed user. This is the specific empirical question §3 item 4 leaves
      open — record whichever answer you get (yes/no/partial) as a WP, since
      neither this runbook nor the ADR could determine it without a real
      console.

## 10. Close the loop

- [ ] For every checklist item above, update `windows-parity.md` §5's
      "Owner must still verify" column with a dated result (pass / fail /
      behaves-differently-filed-as-<ADR or task>).
- [ ] If ANY invariant-critical check fails (step 3's clean-quit-never-
      restarts test, above all), stop and treat it as a P0 defect — route to
      `@agent-ta` if it needs an architectural change, or back to
      `@agent-me` if it's a code-level fix within the existing design.
- [ ] Once every row reads "observed, real Windows box, <date>," M9 can be
      re-graded from "ACCEPT-WITH-FOLLOWUPS (owner-gated)" to a genuine
      "Windows verified" status — that re-grade is this runbook's own exit
      criterion, and it belongs to whoever ran this checklist, not to the
      macOS-only session that wrote it.
