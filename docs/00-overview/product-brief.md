# Product brief — Copilot Control Tower

Control Tower is the always-on menu-bar client + open-source IT setup/deploy tool for the Copilot ecosystem. It is **two faces over one open-source binary**:

- **Operator mode** — a macOS menu-bar app that gives a non-technical person (the "Bob" persona) a working, focus-scoped Copilot partner from one double-click, then keeps the machine synced and self-healed for as long as it runs.
- **Admin mode** — a guided, open-source tool that lets an IT team stand up and deploy the whole ecosystem for their org: seed generator, MDM-profile generator, preflight validation, fleet dashboard, deployment runbooks.

## Control tower, not the pilot

The name is the model. A control tower doesn't fly the plane — it watches every flight, keeps them coordinated and on schedule, clears them to proceed, and raises the alarm when something's off. Control Tower is that supervisor role over the ecosystem's `copilot`/`cc` CLI, never a second brain that reimplements what the CLI already does.

## The one invariant

**Control Tower parses; it never computes.** Every health verdict, resolution decision, signature check, prune, and wipe is performed by the CLI — the same hardened pipeline a headless developer runs by hand. If Control Tower vanished, the CLI would still be correct. That contract is what makes an always-on, auto-pulling agent *safer* than a human running `copilot update` manually: nothing about the GUI's presence changes what's true or what's safe.

## Host-awareness

Control Tower detects and manages **Claude Copilot** and/or **Codex Copilot** independently on a given machine — zero, one, or both may be present. It has no hard-coded product knowledge beyond detection and column selection; the CLI's `derive` step resolves the rest.

## Non-goals

- **Not a second brain.** No resolution logic, no health scoring, no signature verification lives in the app — that would duplicate a hardened pipeline and create two sources of truth.
- **No independent decision-making about systems of record.** Reads happen unprompted; writes confirm.
- **Windows is deferred**, not designed against — macOS-first, Windows is a later re-skin.
- **Does not replace systems of record** (GitHub, MDM, Teams/HR directories) — it supervises and surfaces state that already lives there.

For the full validated architecture — the status model, process model, the app↔CLI contract, distribution/signing, Admin mode, and the escalation model — see [`../01-architecture/architecture.md`](../01-architecture/architecture.md).
