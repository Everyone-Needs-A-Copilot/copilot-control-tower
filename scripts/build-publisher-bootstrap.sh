#!/bin/bash
# Builds a publisher-bootstrap app from the current source tree. This output is
# not trusted or installable merely because this script produced it. Initial
# provisioning and all updates must independently fetch an approved immutable
# public tree, Developer-ID sign, notarize, staple, verify, and root-install it.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUTPUT="${1:-${ROOT}/build/Copilot Control Tower Publisher Bootstrap.app}"
case "${OUTPUT}" in /*) ;; *) echo "error: output path must be absolute" >&2; exit 1;; esac
[[ ! -e "${OUTPUT}" ]] || { echo "error: output already exists: ${OUTPUT}" >&2; exit 1; }
/bin/mkdir -p "${OUTPUT}/Contents/MacOS"
/bin/cp "${ROOT}/publisher-bootstrap/Info.plist" "${OUTPUT}/Contents/Info.plist"
/usr/bin/swiftc -O -debug-prefix-map "${ROOT}=__CT_AUTHENTICATED_SOURCE__" \
  "${ROOT}/publisher-bootstrap/PublisherBootstrap.swift" \
  -o "${OUTPUT}/Contents/MacOS/ct-publisher-bootstrap"
/bin/chmod 755 "${OUTPUT}/Contents/MacOS/ct-publisher-bootstrap"
/bin/chmod 644 "${OUTPUT}/Contents/Info.plist"
echo "publisher bootstrap built (UNTRUSTED until independently signed/notarized/installed): ${OUTPUT}"
