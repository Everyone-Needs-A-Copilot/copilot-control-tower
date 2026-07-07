# Docs index

Read [`START-HERE.md`](START-HERE.md) first — it orients a fresh session, states where the project stands, and points at the build order. This index is a map of what lives where.

| Dir | Contents | Status |
|---|---|---|
| [`00-overview/`](00-overview/) | Product brief (reframed to democratization); `soul.md` now a pointer to the ratified [`SOUL.md`](../SOUL.md) at repo root | Seeded |
| [`01-architecture/`](01-architecture/) | The hardened `architecture.md` + the `cli-contract.md` prerequisite; `inheritance-and-publish.md` (writable tiers + `copilot publish`); `error-taxonomy.md`; `windows-parity.md` (P4 re-skin tracker); versioned [`schemas/`](01-architecture/schemas/) (the `--json` contract source of truth) | Seeded |
| [`02-prd/`](02-prd/) | The parallel, multi-phase PRD (workstreams, acceptance, phase gates) | Seeded |
| [`03-design/`](03-design/) | Three engineering design streams (core / distribution / integration) — **process model superseded by `01-architecture/architecture.md`** (banners in place) | Seeded (superseded process model) |
| [`03-design/ui-ux/`](03-design/ui-ux/) | The UI/UX design track — visual/interaction design via Product Creation Copilot | To-be-written (README seeded) |
| [`product-design/`](product-design/) | The Product Creation Copilot design package (Discovery → Design Challenge) + the ratified `SOUL.md` at repo root; the product-creation front-end that complements the engineering spec | Seeded (Phases 1–5 done; Phase 6 Prototype deferred) |
| [`04-validation/`](04-validation/) | Two adversarial red-team reports (use-case + platform layer) + `test-plan.md` (test strategy, contract test, red-team regression) | Seeded |
| [`05-security/`](05-security/) | `credentials-and-boundary.md` (secret carrier, leakage wall, push creds) + `threat-model.md` (app-level STRIDE+DREAD) + `incident-response.md` (maintainer runbook); `security-and-trust.md` indexes them. Root `SECURITY.md` points here | Seeded |
| [`06-deployment/`](06-deployment/) | Per-MDM deployment guides, managed-config reference, offline path, deprovision runbook | Stub |
| [`07-contributing/`](07-contributing/) | Developer guide (setup/build/signing/self-update) + `release-and-versioning.md` (semver, contract compat, rollback). Root `CONTRIBUTING.md` + `CODE_OF_CONDUCT.md` + `.github/` templates | Seeded |
| [`08-observability/`](08-observability/) | Telemetry spec — two-channel (safety/IT escalation + opt-in analytics), `machine_id` scheme, fleet dashboard, PII guarantees | Seeded |
| [`reference/`](reference/) | Self-contained ecosystem context (four-tier architecture, use cases), `glossary.md`, + ecosystem link pointers | Seeded |
| [`assets/`](assets/) | Diagrams referenced by `reference/` docs | Seeded |

**Seeded** = written and current. **Stub** = a placeholder that states what needs writing and who writes it, so a future session (or agent) knows exactly where to pick up.
