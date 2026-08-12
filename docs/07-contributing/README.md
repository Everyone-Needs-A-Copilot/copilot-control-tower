# Contributing — developer guide

Copilot Control Tower is a native macOS SwiftUI/AppKit application compiled
directly with `swiftc`. The shipping source is in `native/`; there is no Xcode
project or package-manager dependency for the app itself.

Start with the repository-level [`CONTRIBUTING.md`](../../CONTRIBUTING.md),
[`SOUL.md`](../../SOUL.md), and [`CLAUDE.md`](../../CLAUDE.md). Changes must
preserve the parse-never-compute, fail-closed, never-destroy, and one-way
inheritance invariants.

## Build

Prerequisites are macOS, the Xcode command-line tools, and an independently
signed `cc` helper matching `packaging/cc/PINNED_SHA256`. The helper is not
stored in this public source repository.

```bash
CT_VENDORED_CC_PATH=/absolute/path/to/cc ./scripts/build-user.command --build-only
CT_VENDORED_CC_PATH=/absolute/path/to/cc ./scripts/build-admin.command --build-only
```

The build verifies the helper's checksum, Team ID, signature, topology schema,
and reconciliation contract. It never re-signs the helper.

## Focused checks

```bash
./scripts/tests/test_native_invariants.sh
./scripts/tests/test_native_watchdog.sh
./scripts/tests/test_release_source_integrity.sh
./scripts/tests/test_notarization_order.sh
```

The unconditional native-invariants workflow runs the source-level invariant
gate for pushes and pull requests. Tests must keep unknown state honest and
must not weaken a negative fixture merely to make a report green.

## Release boundary

Local builds are not release candidates. A candidate must be built through the
compiled credential-free launcher from an exact anonymously readable Git ref:

```bash
./scripts/package-user-release --source-ref <immutable-ref>
```

The outer bootstrap receives no signing, notarization, or publication
authority. It resolves and fetches the canonical public repository with
config-null Git, materializes regular blobs from a bare object store without a
working checkout or `.git`, verifies the complete tree, and only then allows
the verified inner release program to load local release authority. See the
[`publisher release runbook`](publisher-release-runbook.md).

Building, signing, notarizing, stapling, candidate verification, and publishing
are distinct gates. Publication is always an explicit owner action.
