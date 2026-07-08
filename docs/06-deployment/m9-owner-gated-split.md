# M9 owner-gated split (Windows re-skin)

> **BUILT-BUT-UNVERIFIED-ON-WINDOWS.** Every item under "Buildable now" below
> can be written, reviewed, and `cargo test`-proven on this Mac — but **no
> Windows runtime behavior is verified anywhere in this milestone.** There is
> no Windows toolchain on this machine. Treat every "buildable now" item as
> "this compiles, is `#[cfg(windows)]`-gated correctly, and passes on macOS
> unchanged," never as "this runs correctly on Windows" — those are different
> claims, and this milestone only ever makes the first one. This is the M9
> analog of the Admin-mode HYPOTHESIS stamp
> (`README.md`'s "UNVALIDATED HYPOTHESIS" banner,
> `../08-observability/operator-guide.md`'s `FLEET_HYPOTHESIS_STAMP`): a
> reader must not mistake `#[cfg(windows)]`-gated code that compiles here for
> tested Windows support.

**Home for the design reasoning:** `../01-architecture/windows-parity.md` §3/§4
(ADR-M9-001..006, `tc wp get 53`). This doc is the M9-specific counterpart to
`m5-owner-gated-batch.md` — same purpose (a single "code-complete, blocked on
a human with real hardware/credentials" list), same convention, scoped to the
Windows re-skin instead of MDM/security. Superseded in scope (not content) by
`README.md`'s consolidated owner-gated table once M9 code actually lands —
that table doesn't yet carry M9 rows because, as of this doc, `platform/`
(Stream-B) has not landed.

## What "buildable now" means here

Everything in this column has zero Windows-runtime dependency to write,
review, or test: it's Rust behind `#[cfg(windows)]` (or
`#[cfg(not(target_os = "macos"))]`, the pattern `managed::forced.rs` already
established), WiX/MSI config, PowerShell/`signtool` scripts, or docs. All of
it is reviewable by reading the code; none of it can be *exercised* without
what the "owner-gated" column names.

| Area | Buildable now (macOS-green, `cfg`-gated) | Owner-gated (needs Windows box / EV cert / real MDM console) |
|---|---|---|
| Platform abstraction (ADR-M9-001) | `src-tauri/src/platform/` traits (`PlatformForcedConfig`/`PlatformLoginItem`/`PlatformWatchdogSignal`/`PlatformSecretStore`) + `cfg` `pub use` aliasing seams; macOS thin-wrapper refactor, proven behavior-preserving by the existing macOS test suite staying green | — (this row is pure refactor; nothing here is owner-gated by construction) |
| Crash-only watchdog (ADR-M9-002, parity Q1) | Task Scheduler failure-trigger XML/config wired to the reused `updater::circuit_breaker` + `updater::heartbeat`; unit tests for the decision logic (exit-code interpretation, retry-cap accounting) via the same dev-seam pattern `managed/forced.rs` uses | Real Task Scheduler behavior under repeated failures and a genuine hang; retry-interval/heartbeat-timeout tuning validated against real OS behavior, not just reused macOS constants |
| Forced config (ADR-M9-003, parity Q2) | `HKLM\Software\Policies\ENAC\ControlTower` reader, gated on an enrollment-detection function (`dsregcmd`-output parser or MDM API call), same `managed::keys::MANAGED_KEYS` registry, same fail-closed default when not enrolled; **@agent-sec review of this ADR is a prerequisite to Accepted status, itself not owner-gated** (it's a code review, not a hardware need) | Real `dsregcmd`/MDM-enrollment detection across every state Intune/GPO can produce, on a real domain-joined or MDM-enrolled Windows box; confirming a local admin on an *unmanaged* box truly cannot spoof "enrolled" |
| Secrets (ADR-M9-001, invariant #6) | `PlatformSecretStore` over the `keyring` crate (Credential Manager/DPAPI backend); SSH `ssh-agent` + Credential Manager wiring, same call shape as Keychain | DPAPI re-verification pass per `credentials-and-boundary.md` §6.5's own flag (DPAPI has no separate unlock/ACL prompt the way Keychain can) — needs a real Windows user session |
| Code signing (ADR-M9-004, parity Q3) | `signtool verify` at the same pinned-SHA call site `codesign`/`spctl` occupies today; updater pre-promote check rewritten as Authenticode-valid + version-monotonicity; signing scripts authored (not run) | EV cert acquisition + real `signtool sign` execution; observing actual SmartScreen behavior for a freshly-signed binary; validating the MDM-pushed SmartScreen allow-list genuinely suppresses the interstitial offline on a real air-gapped fleet |
| Tray light/dark (ADR-M9-001, invariant #1) | Two pre-rasterized asset variants (light-taskbar, dark-taskbar) + the `cfg`-aliased theme-read seam, still driven only by `StatusState`/`BadgeState` | Live theme-switch observed on a real Windows taskbar (does the icon actually redraw correctly on a live light↔dark toggle, does the "hidden icons" overflow chevron behave as expected) |
| Packaging / uninstall (ADR-M9-005, invariant #3) | WiX/MSI **per-user** config (`ALLUSERS` unset); the WiX custom action authored to unregister the Task Scheduler task + clear Credential Manager entries; the scheduled-task self-check (target binary vanished → self-unregister) written against the same pattern the watchdog's `Program`-path poll uses | Real MSI per-user install (confirm truly admin-free); real uninstall-orphan test (does "delete via Control Panel" actually leave no orphaned scheduled task or Credential Manager entry) |
| Notifications (§3 Q4) | Toast notification wiring via Tauri's plugin; the conservative default (fallback-to-IT-channel treated as primary on Windows) implemented as the actual code path, not just documented | Real Intune/GPO test of whether per-app notification permission can be centrally forced on Windows 11 |
| Path/DLL-hijack hardening (§3 Q6) | Fully-qualified install-path resolution (registry uninstall key or relative-to-exe); a code-level confirmation that this crate performs no dynamic DLL loading (so the hijack class doesn't apply) — or, if one is ever added, `SetDefaultDllDirectories` restricting search order | Process Monitor / a deliberately-planted decoy binary earlier in `%PATH%` — live hijack-resistance testing on a real Windows box |
| Windows build itself | — | `cargo build --target x86_64-pc-windows-msvc` and `cargo test` on a **real Windows box** (this machine has no Windows toolchain at all — not even a cross-target check has been run as of this doc) |

## What is explicitly NOT claimed by this milestone's docs

- No Windows behavior described above has been observed. Every "Resolved
  (design)" status in `windows-parity.md` means a decision was reasoned
  through against the invariants, not that it was tested.
- No task in M9 marks Windows verification complete. Stream-Z
  (`tc task get 80`) owns the parity verification matrix and the Windows
  bring-up runbook that will eventually close these rows for real — this doc
  is the honest starting list that runbook consumes, not a replacement for it.
- `ADR-M9-003` (forced-config refuse-unless-enrolled) is **Proposed pending
  @agent-sec review**, not yet Accepted — the single hardest invariant-#4
  mapping in the whole tracker gets a human security reviewer before it ships,
  same discipline `windows-parity.md` itself asks for.

## What is NOT on this list (out of scope for this doc)

- The parity verification matrix and Windows bring-up runbook — Stream-Z's
  (`tc task get 80`) deliverable, not duplicated here.
- Any code in `src-tauri/src/platform/` — Stream-B's deliverable, landing in
  parallel; this doc describes the seams it must expose (per
  `windows-parity.md` §4), not code this stream wrote.
