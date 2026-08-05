#!/usr/bin/env bash
# Keeps the native release honest by requiring full verification for the
# signed Mach-O helper and fail-closed behavior for any development placeholder.
#
# The release gate runs the exact vendored binary against both the onboard
# schema-2.0 topology fixture and the reconcile response-schema-2.0/request-
# schema-1.0 deterministic and assistant lifecycles. A stale or placeholder
# helper must fail before the app can be packaged.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

CC_PATH="packaging/cc/cc"
VERIFY="scripts/verify-vendored-cc.sh"

"${VERIFY}" "${CC_PATH}" >/dev/null

if file "${CC_PATH}" | grep -q "Mach-O"; then
    "${VERIFY}" --release "${CC_PATH}" >/dev/null
    echo "vendored cc release gate: signed universal artifact verified"
    exit 0
fi

if "${VERIFY}" --release "${CC_PATH}" >/dev/null 2>&1; then
    echo "placeholder/non-Mach-O cc passed release verification" >&2
    exit 1
fi

echo "vendored cc release gate: placeholder correctly blocks release"
