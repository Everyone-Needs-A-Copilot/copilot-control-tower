#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR=".copilot/control-tower-tray"
BIN="${BUILD_DIR}/control-tower-tray"
SOURCE="native/control-tower-tray.swift"

mkdir -p "${BUILD_DIR}"

# CC=/usr/bin/cc PATH=/usr/bin:$PATH avoids the `copilot` CLI's own `cc` alias
# shadowing the real C compiler on this machine (see repo memory:
# "cc name collision breaks cargo" — the same collision can shadow the
# Swift toolchain's C compiler lookup for any linked C dependency).
if [[ ! -x "${BIN}" || "${SOURCE}" -nt "${BIN}" ]]; then
    CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc "${SOURCE}" -o "${BIN}"
fi

exec "${BIN}"
