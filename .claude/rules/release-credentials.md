# Release credentials doctrine

This publisher Mac is fully provisioned. Standing credentials that exist and must be assumed present:

- The `ct-notary` `notarytool` keychain profile (team `3SYGVX2HB8`). `.env.release.local` stores only that profile name; the Apple credential itself stays in the macOS Keychain.
- The Developer ID Application signing identity.
- `~/.ssh/enac_foundation_release` (foundation signing).
- Keychain service `copilot-cli` entries (Infisical machine identity and service tokens).
- `gh auth` with `admin:org`.

## Probing the notary profile

- Unless `notarytool store-credentials` was given an explicit `--keychain`, `notarytool` stores and reads the profile from the macOS Data Protection Keychain. `security find-generic-password` against `login.keychain-db` does not inspect that store and is never a valid existence test.
- The authoritative probe is `xcrun notarytool history --keychain-profile ct-notary --output-format json`. Retry a local lookup failure, then re-run it from the logged-in user's fresh Terminal session before treating the profile as unavailable.
- A local "No Keychain password item found" means the item was temporarily unavailable to that process, not that it was deleted. Never ask Pablo for a new app-specific password, to recreate credentials, or to rerun Publisher Setup on that evidence alone. If any later probe succeeds, continue the release.
- Only repeated failure from the logged-in user context, with no later successful probe, justifies treating the profile as unavailable.
- A remote rejection of a credential that reads fine locally, evidenced by server-side logs (for example HTTP 401), is a different condition: report the remote rejection without calling the profile missing. It may require owner action.

## Automation

- Local release automation must preflight the profile before an expensive build and retry only transient Keychain lookup failures at notarization boundaries.
- Never work around a credential check to get past any of these cases: no `--skip-verify`, no `--force` (invariant 4).

See `docs/07-contributing/publisher-release-runbook.md#credential-troubleshooting`.
