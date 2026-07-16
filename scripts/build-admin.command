#!/bin/bash
# Builds the ADMIN face of Copilot Control Tower: everything
# `scripts/build-user.command` builds, PLUS `native/admin.swift` +
# `native/admin-support.swift` (surfaces 1-16, Admin mode's org setup tool),
# compiled with `-D CT_ADMIN_BUILD` so admin-only code can be conditionally
# compiled in without breaking a shared file.
#
# This is the FOUNDATION PHASE'S build gate (see the Phase F plan extract):
# the old tray/wizard code plus this phase's new CLI-seam files
# (`native/cli-client.swift`/`native/cli-dtos.swift`/`native/render-state.swift`)
# must compile together into one binary, exactly as they will once
# integration wires them up for real. Unlike `build-user.command`, this build
# is expected to succeed THIS phase — the old tray already references
# `AdminWindowController`/`AdminModel` unconditionally, and this build
# compiles those definitions in, so nothing is left dangling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR=".copilot/control-tower-admin"
BIN="${BUILD_DIR}/Copilot Control Tower (Admin)"

SOURCES=(
    native/models.swift
    native/cli-client.swift
    native/cli-dtos.swift
    native/render-state.swift
    native/wizard.swift
    native/control-tower-tray.swift
    native/admin.swift
    native/admin-support.swift
)

mkdir -p "${BUILD_DIR}"

# CC=/usr/bin/cc PATH=/usr/bin:$PATH avoids the `copilot` CLI's own `cc`
# alias shadowing the real C compiler on this machine (see repo memory:
# "cc name collision breaks cargo" — the same collision can shadow the Swift
# toolchain's C compiler lookup for any linked C dependency).
NEEDS_BUILD=0
if [[ ! -x "${BIN}" ]]; then
    NEEDS_BUILD=1
else
    for SOURCE in "${SOURCES[@]}"; do
        if [[ "${SOURCE}" -nt "${BIN}" ]]; then
            NEEDS_BUILD=1
            break
        fi
    done
fi

if [[ "${NEEDS_BUILD}" -eq 1 ]]; then
    CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc -D CT_ADMIN_BUILD "${SOURCES[@]}" -o "${BIN}"
fi

if [[ "${1:-}" == "--build-only" ]]; then
    exit 0
fi

exec "${BIN}"
