---
initiative: 04-github-authorized-store-access
title: GitHub-Authorized Store Access and Complete Setup Journey
status: active
status_note: Python broker, CLI integration, live verification gate, and support-report access implemented locally on 2026-08-07. Immutable releases, ENAC control-plane deployment, live proof, Swift connection, and app release remain tracked in tc PRD 21.
owner: Pablo Alejo
created: 2026-08-07
execution_context:
  prd: "tc PRD 21"
  tasks: "tc tasks 258-263"
superseded_by: null
---

# GitHub-authorized store access and complete setup journey

This initiative completes the machine-to-project setup journey without placing
a long-lived Infisical identity on an interactive Mac.

The accepted architecture is ADR-009's B-prime design:

1. a user signs in to GitHub once;
2. an open-source, organization-operated broker verifies that account's live
   organization and team membership;
3. the broker issues a short-lived, scope-bound OIDC assertion;
4. Python exchanges the assertion for a 15-minute Infisical access token;
5. Python completes ecosystem and Product-project reconciliation and reports
   one evidence-backed operational verdict; and
6. Swift renders the Python contracts without computing state.

The broker is organization infrastructure deployed beside that organization's
Infisical instance. It is not a Control Tower-hosted service, does not hold an
Infisical credential, and cannot create or widen an Infisical identity. Its two
secrets are its OIDC signing key and a least-privilege GitHub App private key
with organization-membership read access.

## Current evidence

- `cc 2.11.1` has already proved 47/47 Product projects ready and 6/6 shared
  repositories current on the publisher Mac.
- Setup checkpoint-commits eligible dirty Product work locally.
- Foundation, organization, and department repositories are refreshed only by
  download or merge-base-proven fast-forward. Setup never pushes.
- The current Infisical Universal Auth pair exists in Keychain but is rejected
  by the server. Eight unavailable connection groups are downstream symptoms.
- ENAC's live `store.team_scopes` is empty.
- The existing device-flow sign-in client is not the separate broker-side
  GitHub App installation with `Members: read` and an organization-controlled
  private key. Production deployment must create or explicitly designate that
  least-privilege App; no code may infer it from the public client ID.
- No authenticated Infisical admin browser session was available from the
  implementation environment on 2026-08-07, so live identity/trust creation
  remains an owner-hands deployment gate rather than a hidden assumption.

## Acceptance boundary

Python is complete only when all of the following are proven against fixtures,
the packaged helper, and the live publisher Mac:

- every expected ecosystem repository is current;
- every eligible Product project is integrated and freshly verified;
- every declared connection is ready;
- interactive Macs hold no long-lived Infisical client credential;
- setup performs zero pushes, including for GitHub author-capable accounts;
- all mutation exits carry a completed-actions ledger;
- secret-shaped values never appear in JSON, diagnostics, broker logs, argv, or
  inherited Git content;
- positive and negative store-scope checks both pass;
- failure injection proves nonce replay rejection, fail-closed entitlement,
  stale-token recovery, rollback, rate limiting, and honest partial progress;
- the final operational confidence is at least `0.95`.

Swift work begins only after that boundary passes. The app then consumes frozen
JSON/progress contracts, adds direct report access, fixes misleading language,
prevents repeated permission prompts/window activation, and ships through the
repository's signed/notarized release process.

## Durable records

- [Phase 1: contract and threat model](phases/phase-1-contract-and-threat-model.md)
- [Phase 2: Python implementation](phases/phase-2-python-implementation.md)
- [Phase 3: ENAC deployment and live proof](phases/phase-3-enac-deployment.md)
- [ADR-001: assertion broker boundary](decisions/ADR-001-assertion-broker-boundary.md)
- [ADR-009: ratified B-prime policy parameters](../02-enac-self-onboarding/decisions/ADR-009-self-service-store-provisioning-rulings.md)
- [Security design and threat model](../../05-security/self-service-store-provisioning.md)
