#!/bin/bash
# Builds the USER face of Copilot Control Tower: the tray/popover + the
# first-run wizard, WITHOUT Admin mode. Explicit file list (never a
# `native/*.swift` glob) so this build can never accidentally pull in
# `native/admin.swift`/`native/admin-support.swift` — those two are Admin-only
# and are compiled by `scripts/build-admin.command` instead.
#
# Phase F note (native-rebuild plan, WS foundation): until a later phase
# guards `native/control-tower-tray.swift`'s Admin menu-item wiring behind
# `#if CT_ADMIN_BUILD`, THIS SCRIPT WILL FAIL TO LINK — the tray file
# references `AdminWindowController` (defined in `native/admin-support.swift`,
# not compiled here) unconditionally. That is expected and tracked, not a
# Phase F regression: Phase F's own build gate is `build-admin.command`
# (which compiles the old code and the new CLI-seam files together
# successfully), not this script — see `scripts/tests/smoke-cli.sh` and the
# Phase F plan extract's own note on this exact ordering.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR=".copilot/control-tower-tray"
BIN="${BUILD_DIR}/Copilot Control Tower"
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
if [[ ! -x "${BIN}" ]]; then
    NEEDS_BUILD=1
else
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
    CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc "${SOURCES[@]}" -o "${BIN}"
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
# bundle the user opens. Distribution still uses Developer ID + notarization.
codesign --force --deep --sign - "${APP}" >/dev/null

if [[ "${1:-}" == "--build-only" ]]; then
    echo "${APP}"
    exit 0
fi

open "${APP}"
