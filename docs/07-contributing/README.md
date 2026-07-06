# Contributing — developer docs (stub / index)

> **Status: stub / index.** These docs do not exist yet. This file lists what needs writing so a future session picks up exactly where this one left off.

**Candidate owner:** WS-D in [`../02-prd/prd.md`](../02-prd/prd.md) (build/signing/release workstream).

## Docs to be written

- **Tauri v2 dev setup** — Rust toolchain, Node/frontend tooling, running the app locally, the single-process model's implications for local dev (no separate daemon to mock).
- **Build** — `tauri build`, universal binary targeting (`aarch64` + `x86_64`), local vs CI build parity.
- **The cross-repo binary contract** — vendoring already-signed, notarized `copilot`/`cc` artifacts from `claude-copilot` CI at a pinned SHA+version; Control Tower CI *verifies* (`codesign`, `spctl`) but never re-signs; the compat-floor check that blocks release if the vendored CLI is stale.
- **Developer ID signing, notarization & stapling** — the inside-out signing order, `notarytool submit --wait`, stapling both `.app` and `.dmg` for offline Gatekeeper validation on air-gapped fleets.
- **Self-update & the compat matrix** — the minisign-signed manifest updater, two-of-N signing custody, the staged-bundle `--self-test` + liveness-heartbeat rollback watchdog, and how the compat matrix evaluates the one canonical invoked CLI version.
- **Release process** — versioning, staged rollout with anomaly-halt, and the `AllowSelfUpdate=false` version-locked-pair packaging path for managed fleets.

## Cross-links

[`../03-design/design-distribution.md`](../03-design/design-distribution.md) is the detailed design source for signing, packaging, and lifecycle these docs should translate into a runnable contributor workflow.
