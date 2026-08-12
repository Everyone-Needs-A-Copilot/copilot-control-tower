# CLAUDE.md — Copilot Control Tower

This file records the non-negotiable product and engineering invariants for
contributors. The shipping app is native SwiftUI/AppKit in `native/`; the
retired Tauri implementation is intentionally absent from this clean public
repository.

## What this is

Copilot Control Tower is an open-source macOS menu-bar app that supervises the
`copilot`/`cc` CLI. Its User app renders machine-readable status and setup
facts. Its Admin app helps an authorized administrator prepare and verify an
organization setup. The CLI remains the source of truth for ecosystem state.

## Invariants

1. **Parse, never compute.** The app renders versioned CLI facts. Resolution,
   sync, signature, merge, and repair decisions belong in the CLI, not Swift.
2. **One signed app process.** Tray, supervisor, and scheduler behavior stay in
   the native app. `launchd` is a crash-only watchdog with
   `KeepAlive={SuccessfulExit:false}`; a clean Quit stays quit.
3. **Never destroy human work.** Disposable materialized state may be rebuilt,
   but a personal or authoring working tree is never treated as disposable.
4. **Never weaken security to make a path pass.** No skip-verification or force
   bypass belongs in setup, update, or release flows. Unknown state remains
   unknown and fails closed where trust cannot be established.
5. **Route by actor competence and reversibility.** Automate safe reversible
   work, escalate administrator-owned work to administrators, and ask users
   only for decisions about their own data.
6. **Inheritance is one-way and carries no secrets.** Shared content flows
   downward to consumers. Secrets stay in an appropriate OS or managed secret
   store; promotion upward is a separate, human-invoked action.

## Build and release boundary

Use `scripts/build-user.command` and `scripts/build-admin.command` for local
builds. Release artifacts must be produced only from an immutable, anonymously
readable commit through the compiled credential-free bootstrap. Signing and
notarization authority may be loaded only after the bootstrap has independently
verified and materialized that Git tree. Publishing a release is a distinct
owner-controlled action.

See `SOUL.md`, `docs/01-architecture/12-architecture-guiding-principles.md`,
and `docs/07-contributing/publisher-release-runbook.md` for the product,
architecture, and release doctrine.
