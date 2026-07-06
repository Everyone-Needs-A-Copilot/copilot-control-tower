# Deployment — IT guides (stub / index)

> **Status: stub / index.** These docs do not exist yet. This file lists what needs writing so a future session picks up exactly where this one left off.

**Produced by:** Admin mode's build work (WS-H in [`../02-prd/prd.md`](../02-prd/prd.md)) + `@agent-doc`, once the Admin-mode flows described in [`../01-architecture/architecture.md`](../01-architecture/architecture.md) §8 exist to document.

## Docs to be written

- **Per-MDM deployment guides** — Jamf, Kandji, Intune: step-by-step, using the real artifacts Admin mode's MDM-profile generator emits (not generic MDM advice).
- **Managed-config key reference** — every `dev.enac.controltower` key (`OrgSlug`, `Department`, `EcosystemSeedURL`, `GitHubHost`, `AuthMode`, `Host`, `FoundationMirror`, `HTTPSProxy`, `UpdateFeedURL`, `AllowSelfUpdate`, `DisableWizard`, `Deprovisioned`, `AdminContact`), which are honored only from the forced/managed domain, and their types/defaults.
- **Offline / air-gapped path** — how first-run, updates, and Gatekeeper validation behave without network reachability (staple-for-offline-Gatekeeper, `Waiting-for-network` state, foundation-mirror pinning).
- **Offboarding / deprovision runbook** — the MDM-native, app-independent deprovision path: server-side token revocation, `Deprovisioned=true`, the soft-then-hard wipe window, and what IT should expect to see in the fleet dashboard during and after.

## Cross-links

[`../01-architecture/architecture.md`](../01-architecture/architecture.md) §8 (Admin mode, MDM & IT enablement, deprovision) is the authoritative source these guides translate into operator-facing runbooks.
