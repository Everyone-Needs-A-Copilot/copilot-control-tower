#!/bin/bash
# Builds the USER face of Copilot Control Tower: the tray/popover + the
# first-run wizard, WITHOUT Admin mode. Explicit file list (never a
# `native/*.swift` glob) so this build can never accidentally pull in
# `native/admin.swift`/`native/admin-support.swift` — those two are Admin-only
# and are compiled by `scripts/build-admin.command` instead.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR=".copilot/control-tower-tray"
BIN="${BUILD_DIR}/Copilot Control Tower"
BUILD_MODE_FILE="${BUILD_DIR}/build-mode"
APP="build/Copilot Control Tower.app"
APP_CONTENTS="${APP}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_RESOURCES="${APP_CONTENTS}/Resources"
APP_BIN="${APP_MACOS}/Copilot Control Tower"

SOURCES=(
    native/models.swift
    native/cli-client.swift
    native/cli-dtos.swift
    native/render-state.swift
    native/wizard.swift
    native/control-tower-tray.swift
)

mkdir -p "${BUILD_DIR}"

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
case "${CT_SKIP_ADHOC_SIGN:-0}" in
    0|1) ;;
    *)
        echo "error: CT_SKIP_ADHOC_SIGN must be 0 or 1." >&2
        exit 2
        ;;
esac
case "${CT_VISUAL_TEST_BUILD:-0}" in
    0|1) ;;
    *)
        echo "error: CT_VISUAL_TEST_BUILD must be 0 or 1." >&2
        exit 2
        ;;
esac
if [[ "${CT_VISUAL_TEST_BUILD:-0}" -eq 1 && "${CT_SKIP_ADHOC_SIGN:-0}" -eq 1 ]]; then
    echo "error: visual-test builds cannot enter the release-signing path." >&2
    exit 2
fi
EXPECTED_BUILD_MODE="production"
if [[ "${CT_VISUAL_TEST_BUILD:-0}" -eq 1 ]]; then
    EXPECTED_BUILD_MODE="visual-test"
fi
if [[ ! -x "${BIN}" ]]; then
    NEEDS_BUILD=1
else
    CURRENT_BUILD_MODE="production"
    if [[ -f "${BUILD_MODE_FILE}" ]]; then
        CURRENT_BUILD_MODE="$(<"${BUILD_MODE_FILE}")"
    fi
    if [[ "${CURRENT_BUILD_MODE}" != "${EXPECTED_BUILD_MODE}" ]]; then
        NEEDS_BUILD=1
    fi
    for SOURCE in "${SOURCES[@]}"; do
        if [[ "${SOURCE}" -nt "${BIN}" ]]; then
            NEEDS_BUILD=1
            break
        fi
    done
    if [[ "scripts/build-user.command" -nt "${BIN}" ]]; then
        NEEDS_BUILD=1
    fi
fi

if [[ "${NEEDS_BUILD}" -eq 1 ]]; then
    SWIFT_FLAGS=()
    if [[ "${CT_VISUAL_TEST_BUILD:-0}" -eq 1 ]]; then
        SWIFT_FLAGS+=("-D" "CT_VISUAL_TEST_BUILD")
    fi
    CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc \
        "${SWIFT_FLAGS[@]}" "${SOURCES[@]}" -o "${BIN}"
    printf '%s\n' "${EXPECTED_BUILD_MODE}" > "${BUILD_MODE_FILE}"
fi

# Conventional double-clickable macOS bundle. The bare binary remains in
# place because lower-level smoke harnesses exercise it directly.
if [[ -d "${APP}" ]]; then
    rm -rf "${APP}"
fi
mkdir -p "${APP_MACOS}" "${APP_RESOURCES}"
cp packaging/macos/User-Info.plist "${APP_CONTENTS}/Info.plist"
cp "${BIN}" "${APP_BIN}"
cp src-tauri/icons/icon.icns "${APP_RESOURCES}/ControlTower.icns"
chmod 755 "${APP_BIN}"

# Local development builds are ad-hoc signed so macOS validates the exact
# bundle the user opens. The release pipeline disables this pass and applies
# the Developer ID signature exactly once through scripts/sign.sh.
if [[ "${CT_SKIP_ADHOC_SIGN:-0}" -eq 0 ]]; then
    codesign --force --deep --sign - "${APP}" >/dev/null
fi

if [[ "${1:-}" == "--build-only" ]]; then
    echo "${APP}"
    exit 0
fi

open "${APP}"
