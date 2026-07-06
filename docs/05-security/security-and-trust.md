# Security & trust — Copilot Control Tower

> **Status: stub / index.** This is the enterprise security-review enablement document an IT security team will ask for before approving fleet-wide deployment. It does not exist yet in full; this file lists what it must cover and where the source material already lives.

**Candidate author:** `@agent-sec` (STRIDE+DREAD methodology), drawing on the architecture's validated sections rather than starting from a blank threat model.

## Sections to be written

- **What the always-on agent does** — sync/heal on a schedule, project a health score, run the wizard, supervise the CLI. No more than that.
- **What it never does** — no resolution logic, no signature verification, no wipe logic implemented in the app itself; every one of those is delegated to the `copilot`/`cc` CLI (the parse-never-compute invariant).
- **The trust basis** — open source + reproducible builds + two-of-N signing (or a transparency-log witness), so no single popped key is fleet-wide RCE, and an enterprise can audit the binary it's deploying rather than trust it blind.
- **Managed-only security keys** — which config keys (`UpdateFeedURL`, `FoundationMirror`, `EcosystemSeedURL`, `HTTPSProxy`, `GitHubHost`, `AuthMode`, `AllowSelfUpdate`, `Deprovisioned`) are honored **only** from the MDM-forced domain, and why a user-domain-only value is ignored and logged as tamper rather than honored.
- **Signature-verify + capability policy** — how the app↔CLI contract fails closed on missing/malformed security-relevant fields, and how capability-policy signing is distinct from push authority.
- **The never-destroy invariant** — the hard line: Control Tower may re-materialize `.claude/` and re-clone read-only mirrors freely, but never touches a dirty personal tree.
- **Deprovision & DLP** — the MDM-native, app-independent deprovision path; the soft-then-hard two-phase wipe; the honest boundary ("no secret ever materialized," not "exfiltration undone").
- **The `--json` contract as the safety boundary** — why every consumed CLI verb requires a versioned, schema-gated `--json` mode, and why screen-scraping human output is treated as the single highest integration risk.

## Source material already validated

- [`../01-architecture/architecture.md`](../01-architecture/architecture.md) §7 (distribution, signing & self-update) and §8 (Admin mode, MDM & IT enablement, deprovision, the always-on security surface).
- [`../04-validation/redteam-platform.md`](../04-validation/redteam-platform.md) and [`../04-validation/redteam-use-cases.md`](../04-validation/redteam-use-cases.md) — the two adversarial red-team reports whose Critical/High findings this document should cite directly rather than re-derive.
