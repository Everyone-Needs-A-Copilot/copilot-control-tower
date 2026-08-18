#!/bin/bash
# Developer-only builder for the inert repository adapter. The adapter contains
# no Git, credential, build, signing, or release logic; it execs only the fixed
# protected publisher bootstrap path with a closed argument set.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
/usr/bin/swiftc scripts/package-user-release.swift -o scripts/package-user-release
/usr/bin/codesign --verify --strict scripts/package-user-release
{
    /usr/bin/shasum -a 256 scripts/package-user-release
    /usr/bin/shasum -a 256 scripts/package-user-release.swift
} | /usr/bin/sed 's#  scripts/#  #' > scripts/package-user-release.sha256
chmod 755 scripts/package-user-release
chmod 644 scripts/package-user-release.swift scripts/package-user-release.program \
    scripts/package-user-release.sha256
