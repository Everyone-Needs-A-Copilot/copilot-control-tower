# Copilot Control Tower

**The always-on menu-bar client + open-source IT setup/deploy tool for the Copilot ecosystem.**

Control Tower is two faces over one open-source binary:

- **Operator mode** — a macOS menu-bar app that gives a non-technical person a working, focus-scoped Copilot partner from one double-click, then keeps every machine **synced and self-healed** as a *face + supervisor over the `copilot`/`cc` CLI* (never a second brain).
- **Admin mode** — a guided, open-source tool that lets an IT team **stand up and deploy the whole ecosystem** for their org (seed generator, MDM-profile generator, preflight validation, fleet dashboard, deployment runbooks), with full documentation.

The name is the model: a control tower doesn't fly the plane — it watches every flight, keeps them coordinated and on schedule, clears them to proceed, and raises the alarm when something's off.

> **Status:** Private / pre-build. This repo will be made **public for the official launch of the Copilot ecosystem** once the app is built and tested. The architecture is complete and validated against two adversarial red-teams; the build has not started.

---

## Stack

- **Tauri v2** (Rust core + minimal web UI), **single process**, macOS-first (Windows = later re-skin).
- **Developer ID** signed + notarized; MDM-deployable (Jamf / Kandji / Intune).
- A thin supervisor over the ecosystem's `copilot`/`cc` CLI — all resolution, sync, signature-verify, and wipe logic lives in the CLI, not here.

## The one invariant

**Control Tower parses; it never computes.** Every health verdict, resolution, signature check, prune, and wipe is done by the CLI — the same hardened pipeline a headless developer runs. If Control Tower vanished, the CLI would still be correct. That contract is what makes an always-on, auto-pulling agent *safer* than a human running `copilot update` by hand.

## Build from here

Read **[`docs/START-HERE.md`](docs/START-HERE.md)** first — it orients a fresh session and points at the spec and the next actions. The authoritative build spec:

| Doc | What |
|---|---|
| [`docs/01-architecture/architecture.md`](docs/01-architecture/architecture.md) | The validated architecture (§10 maps 25 Critical/High red-team fixes) |
| [`docs/01-architecture/cli-contract.md`](docs/01-architecture/cli-contract.md) | **The prerequisite** — the `copilot --json` + `flock` contract that gates everything |
| [`docs/02-prd/prd.md`](docs/02-prd/prd.md) | The parallel, multi-phase PRD (workstreams, acceptance, phase gates) |
| [`docs/03-design/`](docs/03-design/) | The three design streams + the UI/UX track (Product Creation Copilot) |
| [`docs/04-validation/`](docs/04-validation/) | The two red-team reports |

## Ecosystem context

Control Tower is a client of the Copilot ecosystem defined in the `claude-copilot` initiative `ecosystem-extensions`. Self-contained copies of the relevant ecosystem docs live in [`docs/10-reference/`](docs/10-reference/) (the four-tier architecture, the use cases the app delivers, and the two diagrams).

## License

To be selected at public launch. Private until then.
