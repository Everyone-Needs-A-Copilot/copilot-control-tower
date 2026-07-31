#!/usr/bin/env bash
# Keeps the native release honest by requiring full verification for the
# signed Mach-O helper and fail-closed behavior for any development placeholder.
#
# G-6 (task 209): verify-vendored-cc.sh now also runs the vendored binary's
# `onboard --json` against a minimal local Git fixture and validates the
# report against the canonical schema (docs/01-architecture/schemas/
# onboard.schema.json, v2.0). packaging/cc/cc is currently the STALE
# pre-G-5/G-6 artifact (schema 1.0, no layers_state/completed_actions/
# resume) -- this gate is expected to FAIL until release engineering pins a
# fresh onboard.py-carrying artifact (see scripts/build-fresh-vendored-cc.sh
# and scripts/tests/test_packaged_cc_topology_contract.sh for the tooling
# that builds and proves such an artifact). This mirrors the same
# intentional-failure-until-re-pin state already documented for PKG-01b in
# scripts/tests/test_walkthrough_05_08_acceptance.sh.

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
