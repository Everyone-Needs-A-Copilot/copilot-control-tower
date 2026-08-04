#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ct-reconciliation.XXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

cp "${ROOT_DIR}/scripts/tests/fixtures/reconciliation/mock-cc.sh" "${BUILD_DIR}/cc"
chmod 700 "${BUILD_DIR}/cc"
mkdir -m 700 "${BUILD_DIR}/capture" "${BUILD_DIR}/home"

CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc \
  -parse-as-library \
  "${ROOT_DIR}/native/cli-dtos.swift" \
  "${ROOT_DIR}/native/cli-client.swift" \
  "${ROOT_DIR}/scripts/tests/fixtures/reconciliation/main.swift" \
  -o "${BUILD_DIR}/reconciliation-contract"

HOME="${BUILD_DIR}/home" "${BUILD_DIR}/reconciliation-contract" \
  "${BUILD_DIR}/cc" \
  "${ROOT_DIR}/scripts/tests/fixtures/reconciliation" \
  "${BUILD_DIR}/capture"

python3 - "${ROOT_DIR}" "${BUILD_DIR}/capture" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

root = Path(sys.argv[1])
capture = Path(sys.argv[2])
response_path = root / "docs/01-architecture/schemas/reconcile.schema.json"
request_path = root / "docs/01-architecture/schemas/reconcile-request.schema.json"
response_schema = json.loads(response_path.read_text())
request_schema = json.loads(request_path.read_text())
Draft202012Validator.check_schema(response_schema)
Draft202012Validator.check_schema(request_schema)
Draft202012Validator(request_schema).validate(
    json.loads((capture / "assistant-prepare.request").read_text())
)
validator = Draft202012Validator(response_schema)
fixtures = root / "scripts/tests/fixtures/reconciliation"
for name in (
    "assess", "assistant-prepare", "assistant-run",
    "assistant-status-running", "assistant-status-ready",
    "plan", "apply", "verify", "recover", "error",
):
    validator.validate(json.loads((fixtures / f"{name}.json").read_text()))
if not list(validator.iter_errors(json.loads((fixtures / "schema-high.json").read_text()))):
    raise SystemExit("schema-high fixture unexpectedly conforms to schema 1.0")
print("reconciliation JSON schemas/fixtures: PASS")
PY

expected_request_sha="a39cf5b9ce00dca1e632f5584c308bf4ab4af1726c26654422743e0c2fae056c"
expected_response_sha="e134f84c6712d95af1921d0846a98d5ecab497e70cb3afdefde84bbabb836606"
actual_request_sha="$(shasum -a 256 "${ROOT_DIR}/docs/01-architecture/schemas/reconcile-request.schema.json" | awk '{print $1}')"
actual_response_sha="$(shasum -a 256 "${ROOT_DIR}/docs/01-architecture/schemas/reconcile.schema.json" | awk '{print $1}')"
[[ "${actual_request_sha}" == "${expected_request_sha}" ]]
[[ "${actual_response_sha}" == "${expected_response_sha}" ]]

if rg -n 'WorkspaceMigration' \
  "${ROOT_DIR}/native/cli-dtos.swift" \
  "${ROOT_DIR}/native/cli-client.swift" \
  "${ROOT_DIR}/scripts/tests/fixtures/reconciliation"; then
  echo "retired WorkspaceMigration contract remains in the native seam" >&2
  exit 1
fi

echo "reconciliation contract test: PASS"
