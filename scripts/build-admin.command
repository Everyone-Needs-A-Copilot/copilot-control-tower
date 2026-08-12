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
APP="build/Copilot Control Tower Admin.app"
APP_CONTENTS="${APP}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_RESOURCES="${APP_CONTENTS}/Resources"
APP_BIN="${APP_MACOS}/Copilot Control Tower Admin"

SOURCES=(
    native/models.swift
    native/cli-client.swift
    native/cli-dtos.swift
    native/render-state.swift
    native/design-system.swift
    native/wizard.swift
    native/user-settings.swift
    native/control-tower-tray.swift
    native/admin.swift
    native/admin-support.swift
)

mkdir -p "${BUILD_DIR}"

GH_SOURCE="${CT_ADMIN_GH_PATH:-$(bash scripts/vendor-admin-tool.sh gh)}"
JQ_SOURCE="${CT_ADMIN_JQ_PATH:-$(bash scripts/vendor-admin-tool.sh jq)}"
if [[ -z "${GH_SOURCE}" || ! -x "${GH_SOURCE}" ]]; then
    echo "error: gh is required on the build machine so it can be bundled into Admin." >&2
    exit 2
fi
if [[ -z "${JQ_SOURCE}" || ! -x "${JQ_SOURCE}" ]]; then
    echo "error: jq is required on the build machine so it can be bundled into Admin." >&2
    exit 2
fi

# CC=/usr/bin/cc PATH=/usr/bin:$PATH avoids the `copilot` CLI's own `cc`
# alias shadowing the real C compiler on this machine (see repo memory:
# "cc name collision breaks cargo" — the same collision can shadow the Swift
# toolchain's C compiler lookup for any linked C dependency).
case "${CT_FORCE_REBUILD:-0}" in
    0|1) NEEDS_BUILD="${CT_FORCE_REBUILD:-0}" ;;
    *)
        echo "error: CT_FORCE_REBUILD must be 0 or 1." >&2
        exit 2
        ;;
esac
if [[ ! -x "${BIN}" ]]; then
    NEEDS_BUILD=1
else
    for SOURCE in "${SOURCES[@]}"; do
        if [[ "${SOURCE}" -nt "${BIN}" ]]; then
            NEEDS_BUILD=1
            break
        fi
    done
    if [[ "scripts/build-admin.command" -nt "${BIN}" ]]; then
        NEEDS_BUILD=1
    fi
fi

if [[ "${NEEDS_BUILD}" -eq 1 ]]; then
    CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc -D CT_ADMIN_BUILD "${SOURCES[@]}" -o "${BIN}"
fi

# The unbundled development binary carries the deterministic Admin engine
# beside it. Packaged builds resolve the same script from app Resources.
cp scripts/admin_bootstrap.sh "${BUILD_DIR}/admin_bootstrap.sh"
chmod 755 "${BUILD_DIR}/admin_bootstrap.sh"
mkdir -p "${BUILD_DIR}/bin"
cp "${GH_SOURCE}" "${BUILD_DIR}/bin/gh"
cp "${JQ_SOURCE}" "${BUILD_DIR}/bin/jq"
chmod 755 "${BUILD_DIR}/bin/gh" "${BUILD_DIR}/bin/jq"

# Conventional double-clickable macOS bundle. The bare binary above stays in
# place because the existing smoke harness launches it directly.
if [[ -d "${APP}" ]]; then
    rm -rf "${APP}"
fi
mkdir -p "${APP_MACOS}" "${APP_RESOURCES}/scripts" "${APP_RESOURCES}/bin"
cp packaging/macos/Admin-Info.plist "${APP_CONTENTS}/Info.plist"
cp "${BIN}" "${APP_BIN}"
cp scripts/admin_bootstrap.sh "${APP_RESOURCES}/scripts/admin_bootstrap.sh"
cp "${GH_SOURCE}" "${APP_RESOURCES}/bin/gh"
cp "${JQ_SOURCE}" "${APP_RESOURCES}/bin/jq"
cp packaging/macos/ControlTower.icns "${APP_RESOURCES}/ControlTower.icns"
cp assets/brand/aviator-glyph.svg "${APP_RESOURCES}/aviator-glyph.svg"
chmod 755 "${APP_BIN}" "${APP_RESOURCES}/scripts/admin_bootstrap.sh" "${APP_RESOURCES}/bin/gh" "${APP_RESOURCES}/bin/jq"

# Local development builds are ad-hoc signed so macOS can validate bundle
# integrity. Release distribution still uses the Developer ID/notary pipeline.
codesign --force --deep --sign - "${APP}" >/dev/null

if [[ "${1:-}" == "--build-only" ]]; then
    echo "${APP}"
    exit 0
fi

open "${APP}"
