# Security & trust — Copilot Control Tower

> **Status: index.** This is the enterprise security-review enablement document an IT security team will ask for before approving deployment across an org's machines. The full threat model is now written, split across two companion documents (both STRIDE+DREAD); this file indexes them and states what's still open. Conformed 2026-07-09 to `cse-alignment-decisions.md` D4: MDM is dropped completely; the trust model is compiled-in roots plus signed, inherited org/foundation config, with no MDM-managed domain as a second trust anchor.

**Author:** `@agent-sec` (STRIDE+DREAD methodology), drawing on the architecture's validated sections and the two existing red-team reports rather than starting from a blank threat model.

## What the always-on agent does / never does

Sync/heal on a schedule, project a health score, run the wizard, supervise the CLI — no more than that. It contains **no** resolution logic, **no** signature verification, **no** wipe logic implemented in the app itself; every one of those is delegated to the `copilot`/`cc` CLI (invariant #1, "parse, never compute"). See `CLAUDE.md`'s six invariants for the full statement, and [`threat-model.md`](threat-model.md) §4 for how each invariant maps to the threats it closes.

## App-level threat model (the app itself) — DONE

See **[`threat-model.md`](threat-model.md)** — ratified/executed 2026-07-07, conformed 2026-07-08 to `cse-alignment-decisions.md` D4 (MDM dropped). Covers, in STRIDE+DREAD:
- **The trust basis** — compiled-in trust roots (Apple's Developer ID chain + an independent minisign key) plus signed, inherited org/foundation config for every other security-sensitive value; nothing security-critical comes from user-editable local config, and there is no MDM-managed domain acting as a second trust anchor. Why config can't weaken this, and the cross-repo signing contract for the vendored CLI.
- **STRIDE across the app's real attack surface** — the CLI-invocation path (translocation-safe absolute path vs. the `gh copilot` collision), the `--json` parsing boundary, self-update (minisign key compromise ⇒ RCE across every installed machine, and its two-of-N mitigation), the launchd crash-only watchdog, the inherited org-config trust channel, and the telemetry sink.
- **DREAD scoring, ranked** — top finding is a **NEW** gap this pass surfaced (not in either red-team doc): `AdminContact`, the safety-escalation endpoint, is absent from the enumerated list of keys honored only from the signed, inherited org-config channel, meaning it may be spoofable via a local, user-editable config write, silently redirecting IT's safety channel.
- **Invariant-to-defense mapping** for all six `CLAUDE.md` invariants.
- **Residual risks** — including the still-open signing-custody decision (who holds the second of two-of-N minisign keys), and the accepted D4 residual that offboarding revokes access rather than remotely wiping a departed person's disk (no MDM to reach it).

## Credentials & data-boundary threat model (what the app carries) — DONE

See [`credentials-and-boundary.md`](credentials-and-boundary.md) — ratified 2026-07-07.
- **§1 — Credentials carrier (integration secrets).** OS-keychain + per-integration OAuth/device-code model; `requires_secret: <NAME>` references-not-secrets; GitHub rejected as a secrets carrier (DREAD ≈ 9.2/10); a no-cloud-secret-store fallback specified for the common case (this product has no MDM, D4); an optional shared secret-store enhancement (Infisical/OpenBao) for departments that want one, its endpoint delivered via inherited org repo config, gated by the reader's own GitHub-team membership.
- **§2 — Personal↔shared data-boundary (leakage wall).** STRIDE analysis of the four leakage paths; structural guarantees (separate repos/remotes per tier, pull-only sync, no cross-tier credential scope, fail-closed leak-scan as defense-in-depth backstop). The four owner-ratified rules in that doc's §4 are elevated into `CLAUDE.md` invariant #6.
- **§6 — Author git-push-credential provisioning** (resolved 2026-07-07) — per-user on-device SSH key + GitHub team-membership ACL.

## Source material this document draws on

- [`../01-architecture/architecture.md`](../01-architecture/architecture.md) §3 (process model), §6 (the `--json` contract), §7 (distribution, signing & self-update), §8 (Admin mode, repo/team-based IT enablement, deprovision, the always-on security surface), §9 (the Bob-agency escalation model), §11 (open decisions).
- [`../04-validation/redteam-platform.md`](../04-validation/redteam-platform.md) ("Red Team B") and [`../04-validation/redteam-use-cases.md`](../04-validation/redteam-use-cases.md) ("Red Team A") — the two adversarial red-team reports [`threat-model.md`](threat-model.md) cites directly by finding ID rather than re-deriving.
- `CLAUDE.md`'s six invariants — the defenses [`threat-model.md`](threat-model.md) §4 maps every closed threat back to.
