# Copilot Control Tower

Copilot Control Tower is a native macOS menu-bar app that presents the state
reported by the `cc` command-line tool in plain language. It also has an Admin
build for setting up an organization’s Copilot components.

The app is intentionally thin: `cc` remains the source of truth for setup,
resolution, verification, and repair. The Swift app parses versioned JSON and
renders it; it does not independently calculate ecosystem health.

## Status

This is the clean public source repository. It begins with the current reviewed
source tree and intentionally does not contain the former private repository’s
history, releases, issues, pull requests, workflow records, or operational audit
material.

The project is dogfooding on macOS. It is not yet presented as generally
available, and no release artifact should be trusted unless it is signed,
notarized, stapled, and accompanied by matching source provenance.

## What ships

- `Copilot Control Tower.app`: the user-facing menu-bar app and setup flow.
- `Copilot Control Tower Admin.app`: the same native app with Admin-only setup
  surfaces compiled under `CT_ADMIN_BUILD`.
- `Publisher Setup.app`: local publisher tooling for the gated macOS release
  process.

All shipping UI is native SwiftUI/AppKit under [`native/`](native/). The app is
compiled directly with `swiftc`; there is no Xcode project and no web runtime.

## Build

Requirements:

- macOS with Xcode command-line tools
- a separately obtained, signed `cc` helper whose version, checksum, and
  notarization evidence match [`packaging/cc/`](packaging/cc/)

Place the verified helper at `packaging/cc/cc` for local development, then run:

```sh
./scripts/build-user.command --build-only
./scripts/build-admin.command --build-only
```

The helper binary is deliberately not committed to this source repository. The
release process verifies it as a pinned external input before embedding it.

## Release integrity

[`scripts/package-user-release`](scripts/package-user-release) is the only
supported release entry. It resolves an immutable ref from this exact public
HTTPS repository, fetches it into a config-isolated bare Git store, materializes
a source tree with no `.git` directory, and repeatedly verifies the materialized
bytes before signing or producing metadata.

Building, signing, notarizing, and stapling a candidate does not publish it.
Publishing a release is a separate owner-gated action.

## Documentation

- [Architecture](docs/01-architecture/architecture.md)
- [CLI contract](docs/01-architecture/cli-contract.md)
- [Architecture principles](docs/01-architecture/12-architecture-guiding-principles.md)
- [Threat model](docs/05-security/threat-model.md)
- [Publisher release runbook](docs/07-contributing/publisher-release-runbook.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

Licensed under the [Apache License 2.0](LICENSE).
