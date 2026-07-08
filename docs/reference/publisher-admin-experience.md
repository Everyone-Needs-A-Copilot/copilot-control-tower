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

**Role:** the IT/fleet operator who deploys a publisher-built artifact into an
organization.

**Authority held:**

- MDM console access.
- Org repo/access policy.
- `ecosystem.yml` ownership.
- `AdminContact`, update feed, telemetry collector, and rollout scope.

**Primary job:** turn a trusted artifact plus org policy into a working fleet.

**Journey:**

1. Start from the signed/notarized artifact produced by the Publisher journey.
2. Author or generate the org `ecosystem.yml` seed.
3. Configure org/dept repo access and policy signers.
4. Generate the MDM `.mobileconfig`.
5. Run preflight.
6. Upload the app artifact and profile to the MDM.
7. Roll out to a test Mac.
8. Watch fleet status and handle governance/offboarding.

**Admin mode must not dead-end:**

- Every red preflight item names the offending input and the next fix.
- Every profile/config gap explains whether IT, publisher, or end user owns it.
- Fleet views render per-machine state, not a computed score.
- Safety escalation always points to the configured `AdminContact` when present.

**Admin journey done means:** a managed test machine silently provisions from the
profile, reports honestly, and can be governed/offboarded. That is separate from
the publisher's signing/notarization success.

## Handoff Boundary

Publisher hands Admin:

- Signed/notarized/stapled app or DMG.
- Publisher Team ID.
- Version and compat notes.
- Update-signing status: production two-of-N ready, or explicitly not ready.

Admin hands Publisher only when needed:

- Release-blocking feedback from MDM/preflight/fleet validation.
- Required update-feed or rollout-channel expectations.

Admin should never need the Publisher's Developer ID private key, Apple
notarization password, App Store Connect API key, or update-manifest private
keys.
