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
- **Credentials carrier (integration secrets) — DONE.** See [`credentials-and-boundary.md`](credentials-and-boundary.md) §1 — ratified 2026-07-07. OS-keychain + per-integration OAuth/device-code model; `requires_secret: <NAME>` references-not-secrets; GitHub rejected as a secrets carrier (DREAD ≈ 9.2/10); no-MDM/no-cloud-secret-store fallback specified. **Open seam carried forward, not yet designed:** author git-push-credential provisioning (`ssh-personal`/`ssh-work` key generation/distribution/rotation) — see that doc's §6.
- **Personal↔shared data-boundary (leakage wall) — DONE.** See [`credentials-and-boundary.md`](credentials-and-boundary.md) §2 — ratified 2026-07-07. STRIDE analysis of the four leakage paths; structural guarantees (separate repos/remotes per tier, pull-only sync, no cross-tier credential scope, fail-closed leak-scan as defense-in-depth backstop). The four owner-ratified rules in that doc's §4 are being elevated to `CLAUDE.md` invariants.

## Source material already validated

- [`../01-architecture/architecture.md`](../01-architecture/architecture.md) §7 (distribution, signing & self-update) and §8 (Admin mode, MDM & IT enablement, deprovision, the always-on security surface).
- [`../04-validation/redteam-platform.md`](../04-validation/redteam-platform.md) and [`../04-validation/redteam-use-cases.md`](../04-validation/redteam-use-cases.md) — the two adversarial red-team reports whose Critical/High findings this document should cite directly rather than re-derive.
