#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ct-project-integration.XXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc \
  -parse-as-library \
  "${ROOT_DIR}/native/cli-dtos.swift" \
  "${ROOT_DIR}/scripts/tests/fixtures/project-integration/main.swift" \
  -o "${BUILD_DIR}/project-integration-contract"

"${BUILD_DIR}/project-integration-contract" \
  "${ROOT_DIR}/scripts/tests/fixtures/workspaces/status-all-1.1.json" \
  "${ROOT_DIR}/scripts/tests/fixtures/workspaces/status-project-guided-1.1.json" \
  "${ROOT_DIR}/scripts/tests/fixtures/workspaces/status-project-owner-1.1.json"

expected_schema_sha="470a663277f77b0d60359103e1f206852f05c1b7392f3b5c31b1810b90c75c33"
actual_schema_sha="$(shasum -a 256 "${ROOT_DIR}/docs/01-architecture/schemas/workspaces.schema.json" | awk '{print $1}')"
if [[ "${actual_schema_sha}" != "${expected_schema_sha}" ]]; then
  echo "workspaces schema is not the frozen CLI schema" >&2
  exit 1
fi

rg -Fq '"workspace", "finish"' "${ROOT_DIR}/native/cli-client.swift"
rg -Fq '"workspace", "verify"' "${ROOT_DIR}/native/cli-client.swift"
rg -Fq '"workspace", "plan"' "${ROOT_DIR}/native/cli-client.swift"
rg -Fq '"workspace", "hold"' "${ROOT_DIR}/native/cli-client.swift"

echo "project-integration contract test: PASS"
