# Publisher and Admin Experience

This document defines the two operational journeys that happen before a real
fleet can run Control Tower. They may be performed by the same human while
dogfooding, but they are different roles with different authority.

## Publisher Journey

**Role:** the release owner who produces a macOS artifact that Gatekeeper can
trust.

**Authority held:**

- Apple Developer ID Application certificate.
- Apple notarization credential.
- Release workflow secrets.
- Update-manifest signing custody, once production two-of-N keys exist.

**Primary job:** turn source code into a signed, notarized, stapled artifact.

**Journey:**

1. Join/confirm Apple Developer Program membership.
2. Create a Developer ID Application certificate using the G2 Sub-CA.
3. Install Apple's Developer ID - G2 intermediate if the certificate appears
   untrusted.
4. Confirm the certificate is visible to macOS and has its private key.
5. Generate an Apple app-specific password at `account.apple.com`.
6. Run **Publisher Setup.app**.
7. On success, run the publisher build/sign/notarize commands.
8. Hand the signed/notarized artifact to the Admin journey.

**Publisher Setup.app must not dead-end:**

- Before submission, it shows prerequisites so the publisher knows what they
  need before clicking.
- On success, it replaces the form with a completion view and copyable next
  commands.
- On failure, it replaces the form with a recovery view, copyable failure
  details, and the most relevant next action.

**Publisher journey done means:** a signed, notarized, stapled `.app`/`.dmg`
exists. It does not mean the app is deployed to an organization.

## Admin Journey

**Role:** the org admin who stands up the Copilot Solutioning Ecosystem (CSE)
for their org and hands members a working, entitled machine. There is no MDM in
this model: entitlement and deployment run entirely on **GitHub repo access**
(CSE `cse-alignment-decisions.md` D3/D4). See
[`docs/03-design/three-role-journeys.md`](../03-design/three-role-journeys.md)
§2 for the full journey this section summarizes.

**Authority held:**

- GitHub org-owner (or delegated team-admin) access.
- `ecosystem.yml` ownership.
- Central shared secret store admin access (e.g. Infisical/OpenBao).
- `AdminContact` (safety-escalation endpoint), update feed, and telemetry
  collector configuration.

**Primary job:** turn a trusted artifact plus org policy into a working,
entitled org.

**Journey:**

1. Start from the signed/notarized artifact produced by the Publisher journey.
2. Stand up the four-tier component repo topology: `<org>/copilot-org` plus a
   separate `<org>/copilot-dept-<unit>` repo per department (confidentiality
   boundary is the repo).
3. Create department GitHub teams and grant read/write — **this is the
   entitlement** (a user has a layer iff they have access to its repo; D3).
4. Configure the central shared secret store (org/department integration
   keys — Workday, Salesforce, Microsoft, etc.), scoped by GitHub-team
   membership, with the endpoint delivered via inherited org repo config
   (never a secret itself; D4/D6).
5. Author or generate the org `ecosystem.yml` seed (components, departments,
   foundation pins, `auth`/`host`/`mirror`, `policy_signers`, telemetry) and
   open the PR.
6. Sign the capability policy with the security-team key, distinct from push
   authority; set CODEOWNERS/rulesets on the executable paths.
7. Run preflight: repos exist, seed parses, policy is signed, the secret store
   is reachable, the foundation pin resolves.
8. Point org members at the signed `.dmg` link; each person self-installs and
   joins their own department by GitHub repo access (no push, no zero-touch).
9. Watch the observability dashboard and handle governance/offboarding
   (revoke GitHub repo access + rotate shared-secret-store tokens for a
   leaver — never a remote wipe; content already synced to a departed
   person's disk is an accepted residual).

**Admin mode must not dead-end:**

- Every red preflight item names the offending input and the next fix.
- Every config gap explains whether the admin, publisher, or end user owns it.
- The observability dashboard renders per-machine state, not a computed score.
- Safety escalation always points to the configured `AdminContact` when present.

**Admin journey done means:** the four spine artifacts exist and verify clean —
the component repos + teams (entitlement), the central secret store, and a
signed `ecosystem.yml` — and a test machine self-installs, joins a department
by repo access, reports honestly, and can be offboarded. That is separate from
the publisher's signing/notarization success.

## Handoff Boundary

Publisher hands Admin:

- Signed/notarized/stapled app or DMG.
- Publisher Team ID.
- Version and compat notes.
- Update-signing status: production two-of-N ready, or explicitly not ready.

Admin hands Publisher only when needed:

- Release-blocking feedback from preflight/observability validation.
- Required update-feed or rollout-channel expectations.

Admin should never need the Publisher's Developer ID private key, Apple
notarization password, App Store Connect API key, or update-manifest private
keys.
