#!/usr/bin/env bash
# smoke-cli.sh — Phase F's build+seam gate.
#
# 1. Builds the Admin binary (`scripts/build-admin.command`) to prove the old
#    tray/wizard/admin code and this phase's new CLI-seam files
#    (native/cli-client.swift / native/cli-dtos.swift / native/render-state.swift)
#    compile together into one binary.
# 2. Compiles a throwaway scratch driver
#    (scripts/tests/fixtures/smoke-cli/main.swift) together with
#    native/cli-client.swift + native/cli-dtos.swift + native/render-state.swift
#    + native/models.swift, and runs it against `src-tauri/fixtures/mock-cc`
#    for a spread of the real doctor/auth/layers/projects fixture corpus,
#    asserting the specific badge/sentence/decode outcomes the Phase F plan
#    names (at minimum: healthy-clean-fleet -> .none/"Everything is set up.",
#    offline -> .cloudSlash, signed-out-claude-personal -> .key,
#    exit-2 -> unreadable/.bang, schema-version-above-max -> unreadable/.bang,
#    12-of-14-updated -> a fan-out line containing "12").
#
# This stands in for the real `CT_SELFTEST` hook, which lands in Phase I —
# see the Phase F plan extract's own note on this substitution.
#
# Exits non-zero if the Admin build fails OR any scratch-driver assertion
# fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

MOCK_CC="${REPO_ROOT}/src-tauri/fixtures/mock-cc"
if [[ ! -x "${MOCK_CC}" ]]; then
    echo "FATAL: mock CLI not found or not executable at ${MOCK_CC}" >&2
    exit 1
fi

echo "=== smoke-cli: building Admin binary (scripts/build-admin.command) ==="
if ! bash "${REPO_ROOT}/scripts/build-admin.command" --build-only; then
    echo "FAIL: scripts/build-admin.command did not exit 0" >&2
    exit 1
fi
echo "ok - scripts/build-admin.command exits 0"
echo

echo "=== smoke-cli: compiling the CLI-seam scratch driver ==="
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/control-tower-smoke-cli.XXXXXX")"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

DRIVER_BIN="${WORKDIR}/smoke-cli-driver"
DRIVER_SOURCES=(
    "${SCRIPT_DIR}/fixtures/smoke-cli/main.swift"
    "${REPO_ROOT}/native/cli-client.swift"
    "${REPO_ROOT}/native/cli-dtos.swift"
    "${REPO_ROOT}/native/render-state.swift"
    "${REPO_ROOT}/native/models.swift"
)

# Same CC=/usr/bin/cc PATH=/usr/bin:$PATH convention as build-user.command /
# build-admin.command — see those scripts' headers.
if ! CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc "${DRIVER_SOURCES[@]}" -o "${DRIVER_BIN}"; then
    echo "FAIL: scratch driver failed to compile" >&2
    exit 1
fi
echo "ok - scratch driver compiles"
echo

echo "=== smoke-cli: running the scratch driver against mock-cc ==="
"${DRIVER_BIN}" "${MOCK_CC}"
DRIVER_EXIT=$?

echo
if [[ "${DRIVER_EXIT}" -eq 0 ]]; then
    echo "smoke-cli.sh: PASS"
else
    echo "smoke-cli.sh: FAIL (scratch driver exited ${DRIVER_EXIT})" >&2
fi
exit "${DRIVER_EXIT}"
