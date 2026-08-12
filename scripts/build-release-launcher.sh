#!/bin/bash
# Developer-only builder for the dedicated release launcher. The resulting
# Mach-O and three-file identity manifest must be committed together. This
# script is not a release entry point and receives no publisher credentials.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
/usr/bin/swiftc scripts/package-user-release.swift -o scripts/package-user-release
/usr/bin/codesign --verify --strict scripts/package-user-release
{
    /usr/bin/shasum -a 256 scripts/package-user-release
    /usr/bin/shasum -a 256 scripts/package-user-release.swift
    /usr/bin/shasum -a 256 scripts/package-user-release.program
} | /usr/bin/sed 's#  scripts/#  #' > scripts/package-user-release.sha256
chmod 755 scripts/package-user-release
chmod 644 scripts/package-user-release.swift scripts/package-user-release.program \
    scripts/package-user-release.sha256
