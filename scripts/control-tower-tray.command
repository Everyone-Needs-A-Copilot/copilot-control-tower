#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR=".copilot/control-tower-tray"
BIN="${BUILD_DIR}/control-tower-tray"
# The app is split across multiple files (models.swift shared, wizard.swift
# the S2 first-run wizard, control-tower-tray.swift the tray/popover +
# app entry point) but still compiles to ONE binary — `swiftc native/*.swift`
# compiles them together as one module, same convention `-o` has always used.
SOURCES=(native/*.swift)

mkdir -p "${BUILD_DIR}"

# CC=/usr/bin/cc PATH=/usr/bin:$PATH avoids the `copilot` CLI's own `cc` alias
# shadowing the real C compiler on this machine (see repo memory:
# "cc name collision breaks cargo" — the same collision can shadow the
# Swift toolchain's C compiler lookup for any linked C dependency).
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
    CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc "${SOURCES[@]}" -o "${BIN}"
fi

exec "${BIN}"
