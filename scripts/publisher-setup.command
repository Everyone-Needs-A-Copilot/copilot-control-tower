#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR=".copilot/publisher-setup"
BIN="${BUILD_DIR}/publisher-setup"
SOURCE="scripts/publisher_setup.swift"

mkdir -p "${BUILD_DIR}"

if [[ ! -x "${BIN}" || "${SOURCE}" -nt "${BIN}" ]]; then
    /usr/bin/env swiftc "${SOURCE}" -o "${BIN}"
fi

exec "${BIN}"
