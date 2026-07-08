#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$(cd "${ROOT_DIR}/plugins/codex-copilot" && pwd -P)"
FRAMEWORK_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd -P)"
SHARED_GATE="${FRAMEWORK_ROOT}/scripts/copilot-gate.sh"

if [[ ! -f "${SHARED_GATE}" ]]; then
  echo "copilot-gate: shared gate not found at ${SHARED_GATE}" >&2
  exit 2
fi

exec bash "${SHARED_GATE}" "$@"
