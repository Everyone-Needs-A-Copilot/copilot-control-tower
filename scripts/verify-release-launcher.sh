#!/bin/bash
# Proves the committed Mach-O was built from the reviewed Swift source. The
# Swift derives the UUID from the output basename, so compiling to the same
# basename makes the unsigned payload reproducible; ad-hoc signature bytes are
# removed from disposable copies before comparison.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-launcher-verify.XXXXXX")"
cleanup() { rm -rf "${scratch}"; }
trap cleanup EXIT

/usr/bin/swiftc scripts/package-user-release.swift -o "${scratch}/package-user-release"
cp scripts/package-user-release "${scratch}/committed"
/usr/bin/codesign --remove-signature "${scratch}/package-user-release"
/usr/bin/codesign --remove-signature "${scratch}/committed"
cmp "${scratch}/package-user-release" "${scratch}/committed"

for relative in package-user-release package-user-release.swift package-user-release.program; do
    expected="$(/usr/bin/awk -v path="${relative}" '$2 == path { print $1 }' \
        scripts/package-user-release.sha256)"
    actual="$(/usr/bin/shasum -a 256 "scripts/${relative}" | /usr/bin/awk '{print $1}')"
    [[ -n "${expected}" && "${expected}" == "${actual}" ]]
done
/usr/bin/codesign --verify --strict scripts/package-user-release
echo "release launcher source/binary identity: PASS"
