# ADR-012 — Releases use direct local Developer ID signing; the Publisher Bootstrap requirement is deferred

Status: Accepted. Supersedes the Publisher Bootstrap release requirement documented in `docs/07-contributing/publisher-release-runbook.md` (sections 7 and 8 as they stood at v0.6.10) and ADR-009's treatment of the Apple publisher-bootstrap credential as a delivery gate. Date: 2026-10-23. Decision owner: Pablo Alejo. Operational task: TASK-316.

ARTIFACT: architecture-decision ARTIFACT: security-boundary

## Context

From v0.6.10 the only supported way to produce a release artifact was `scripts/package-user-release`, an inert adapter that hands off to a separately installed, root-owned, Developer-ID-signed Publisher Bootstrap. The bootstrap authenticates immutable source, then reads the publisher's credentials and runs the release program. Installing it requires an independently controlled Developer ID Application and Developer ID Installer context, an independently authenticated executor, an out-of-band owner approval manifest, and a root-staging executor that does not exist yet. None of that is provisioned, so no signed artifact could be produced: the v0.6.10 GitHub release has notes and no assets.

Before the bootstrap gate, releases (through v0.6.9) were produced by `scripts/package-user-release.sh`, which ran on the owner's Mac: it required local HEAD to equal the pushed ref, cloned that ref, built the User app, signed it with the Developer ID Application identity, notarized and stapled the app, built and signed a DMG, notarized and stapled the DMG, ran `spctl` and `stapler validate`, and wrote a SHA-256 sidecar. That path is proven and needs only credentials that already exist on the publisher Mac: the Developer ID Application identity in the login keychain and the `ct-notary` notarytool profile.

A DMG of an app needs no Developer ID Installer certificate. The Installer certificate signs `.pkg` installers, and only the Publisher Bootstrap package used one. Apple accepts a notarized, stapled DMG signed with the Developer ID Application identity.

The owner was asked whether to keep the high-assurance bootstrap path or switch to standard signing, and decided: "let's go with simpler."

## Decision

- The active release procedure is `scripts/release-local.sh --tag vX.Y.Z`, run by the publisher on the publisher's own Mac. It is a revival and tightening of the v0.6.9 `package-user-release.sh` pipeline, not a new design.
- The source being released is an exact signed annotated tag. The command refuses a lightweight or unsigned tag, a local tag that differs from origin's advertised tag object and commit, a clone whose HEAD differs from the tag commit, and any disagreement between the tag, both Info.plist versions and builds, `controltower.compat.json`, and the CHANGELOG. The tool lives in the publisher's checkout and builds the tag's source from a clean clone, so a release can be built from a tag that predates the tool.
- The command keeps every integrity check that still applies: the committed release launcher byte match (run locally under the pinned toolchain, otherwise required from the pinned-toolchain CI check for the exact commit), vendored `cc` verification including the compatibility range, notary profile preflight before any expensive work, the headless Detect and setup-transaction proofs before signing, the crash-only launchd proof, signing before notarization, app stapling before DMG assembly, `stapler validate` and `spctl` before the checksum, and the drag-installed artifact verification.
- It signs the User app and the Admin bundle (including the bundled `gh` and `jq`) with hardened runtime, signs the DMG, notarizes with the `ct-notary` profile, staples, and writes the SHA-256 sidecars. Credentials are read from the mode-0600 `.env.release.local` only after the source proof and are never printed, copied, or committed.
- The Publisher Bootstrap code stays in the repository, inactive and documented as a deferred option: `scripts/package-user-release*`, `publisher-bootstrap/`, `scripts/provision-publisher-bootstrap.sh`, `scripts/verify-publisher-bootstrap.sh`, `scripts/verify-publisher-approval-tuple.py`, their tests, and the runbook's bootstrap procedure. Nothing is deleted and no test was weakened.
- This is a reversible release-mechanism decision. It does not change the app, the CLI contract, the update manifest trust roots, or invariant 4: there is still no `--skip-verify` or `--force`, and a notarization failure stops the release.

## Consequences

- Protection is weaker than the bootstrap design if this Mac or the Apple account is compromised. The bootstrap separated source authentication from credential access in a root-owned anchor that a same-user attacker could not replace. Under the direct path, anything running as the publisher user on this Mac, or anyone who controls the Apple Developer account or the signing identity, can sign and notarize arbitrary code as Team 3SYGVX2HB8, and can do so without an independent approval record. The source proof (signed tag, origin match, clean clone) protects against building the wrong bytes by mistake, not against a compromised publisher.
- The mitigations that remain are the signed tag chain, the clean-clone build, the pinned-checksum vendored `cc`, the existing gates above, Apple notarization evidence, and the owner's control of the Mac and account. The compiled-in update-signing roots still apply separately to self-update promotion (see the runbook's stable-promotion caveat).
- Releases are no longer blocked on an attended first-trust ceremony, an independent executor, or a Developer ID Installer certificate.
- A release also depends on Apple's service state. If notarization returns HTTP 403 because a required agreement is missing or expired, only the account holder can fix it at developer.apple.com; the release stops at preflight and resumes by re-running the same command.
- `.github/workflows/release.yml` still invokes the bootstrap adapter. It is owner-gated, skipped unless `RELEASE_CI_ENABLED` is true, and not part of the active path. Enabling CI releases would need its own decision.

## Restoring the bootstrap path

1. Decide to adopt the high-assurance path and stop using `scripts/release-local.sh` for releases.
2. Complete the first-trust ceremony in the runbook's deferred section: provision independent Developer ID Application and Developer ID Installer authority for Team 3SYGVX2HB8, an independently authenticated executor, an `OWNER-APPROVED` manifest delivered out of band, and a root-staging executor; install the package; and pass `scripts/verify-publisher-bootstrap.sh` plus independent installed-state QA.
3. Release with `scripts/package-user-release --source-ref <tag>` again, make the runbook's section 7 the active procedure, and supersede this ADR with a new one.
4. Keep `scripts/release-local.sh` only if a documented break-glass use is accepted; otherwise remove it in the superseding change.
