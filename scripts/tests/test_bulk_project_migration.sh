#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ct-bulk-project-migration.XXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc \
  -parse-as-library \
  "${ROOT_DIR}/native/cli-dtos.swift" \
  "${ROOT_DIR}/scripts/tests/fixtures/project-migration/main.swift" \
  -o "${BUILD_DIR}/project-migration-contract"

"${BUILD_DIR}/project-migration-contract" \
  "${ROOT_DIR}/src-tauri/fixtures/workspaces/migration-plan-1.0.json" \
  "${ROOT_DIR}/src-tauri/fixtures/workspaces/migration-apply-partial-1.0.json"

expected_schema_sha="8ffa5e2ac8902546ed58bd3a2560dbae195f97668a79ec06397fb5cdfc6dd268"
actual_schema_sha="$(shasum -a 256 "${ROOT_DIR}/docs/01-architecture/schemas/workspace-migrations.schema.json" | awk '{print $1}')"
if [[ "${actual_schema_sha}" != "${expected_schema_sha}" ]]; then
  echo "workspace migrations schema is not the frozen CLI schema" >&2
  exit 1
fi

rg -Fq 'await decodeVerb(["workspace", "migrate", "--all", "--json"])' "${ROOT_DIR}/native/cli-client.swift"
rg -Fq '"--plan-id", planId, "--apply", "--json"' "${ROOT_DIR}/native/cli-client.swift"
rg -Fq 'Review \(report.summary.eligible) updates' "${ROOT_DIR}/native/wizard.swift"
rg -Fq 'showsBulkMigrationConfirmation = true' "${ROOT_DIR}/native/wizard.swift"
rg -Fq 'Full project receipt' "${ROOT_DIR}/native/wizard.swift"
rg -Fq 'projectMigrationApplyReport = applied' "${ROOT_DIR}/native/wizard.swift"
rg -Fq 'CT_VISUAL_SCENARIO' "${ROOT_DIR}/native/wizard.swift"

for walkthrough in \
  09-bulk-project-migration-uxd-walkthrough.html \
  10-bulk-project-migration-uids-walkthrough.html; do
  test -f "${ROOT_DIR}/docs/40-initiatives/02-enac-self-onboarding/walkthroughs/${walkthrough}"
done

echo "bulk-project-migration contract test: PASS"
