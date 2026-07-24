#!/usr/bin/env bash
# Verifies the zero-terminal Admin readiness contract and macOS app bundle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR="${REPO_ROOT}/.copilot/control-tower-admin"
BIN="${BUILD_DIR}/Copilot Control Tower (Admin)"
APP="${REPO_ROOT}/build/Copilot Control Tower Admin.app"
CONTENTS="${APP}/Contents"
RESOURCES="${CONTENTS}/Resources"

bash scripts/build-admin.command --build-only >/dev/null

for required in \
  "${CONTENTS}/Info.plist" \
  "${CONTENTS}/MacOS/Copilot Control Tower Admin" \
  "${RESOURCES}/ControlTower.icns" \
  "${RESOURCES}/scripts/admin_bootstrap.sh" \
  "${RESOURCES}/bin/gh" \
  "${RESOURCES}/bin/jq"; do
  if [[ ! -e "${required}" ]]; then
    echo "missing Admin bundle artifact: ${required}" >&2
    exit 1
  fi
done

if ! rg -Fq '/usr/bin/curl' "${RESOURCES}/scripts/admin_bootstrap.sh"; then
  echo "packaged Admin engine does not carry the absolute macOS store probe" >&2
  exit 1
fi
if rg -q 'exec .*\/dev\/tcp' "${RESOURCES}/scripts/admin_bootstrap.sh"; then
  echo "packaged Admin engine still uses unsupported Bash /dev/tcp" >&2
  exit 1
fi

placeholder_reference_count="$(
  rg -o 'AdminPlaceholder\.(publisher|admin|pointOfContact|organization|oauthClientID|department|storeAddress|workspaceID|environment|sharedSecretPath|githubUsername|departmentScope)' \
    native/admin.swift native/admin-support.swift |
    wc -l |
    tr -d ' '
)"
if [[ "${placeholder_reference_count}" != "16" ]]; then
  echo "expected all 16 Admin form placeholder references, found ${placeholder_reference_count}" >&2
  exit 1
fi

for expected_copy in \
  "e.g. Jordan Vale" \
  "e.g. Earl Reyes" \
  "e.g. Priya Shah" \
  "e.g. acme-co" \
  "e.g. Iv1.a1b2c3d4e5f6a7b8" \
  "e.g. Accounting" \
  "e.g. https://vault.acme-co.com" \
  "e.g. workspace-acme" \
  "e.g. prod" \
  "e.g. /shared" \
  "e.g. octocat"; do
  if ! rg -Fq "${expected_copy}" native/admin.swift; then
    echo "missing Admin placeholder copy: ${expected_copy}" >&2
    exit 1
  fi
done

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${CONTENTS}/Info.plist")" == "com.everyoneneedsacopilot.controltower.admin" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${CONTENTS}/Info.plist")" == "Copilot Control Tower Admin" ]]
codesign --verify --deep --strict "${APP}"

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ct-admin-readiness.XXXXXX")"
cleanup() {
  rm -rf "${FIXTURE_ROOT}"
}
trap cleanup EXIT

mkdir -p "${FIXTURE_ROOT}/tools"
cat > "${FIXTURE_ROOT}/tools/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "gh version fixture"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  printf '%s\n' '{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"earladmin","tokenSource":"keyring","scopes":"admin:org, read:org, repo","gitProtocol":"https"}]}}'
  exit 0
fi
if [[ "${1:-}" == "api" && "${2:-}" == "orgs/acme-co/memberships/earladmin" ]]; then
  echo "admin:active"
  exit 0
fi
echo "unexpected fixture gh invocation: $*" >&2
exit 2
EOF
cat > "${FIXTURE_ROOT}/tools/jq" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "jq-fixture"
  exit 0
fi
exit 2
EOF
chmod 755 "${FIXTURE_ROOT}/tools/gh" "${FIXTURE_ROOT}/tools/jq"

output="$(
  HOME="${FIXTURE_ROOT}/home" \
  CT_ADMIN_TOOLS_DIR="${FIXTURE_ROOT}/tools" \
  CT_ADMIN_READINESS_SELFTEST=1 \
  CT_ADMIN_ORG=acme-co \
  "${BIN}"
)"

for expected in \
  "adminTools=pass" \
  "signedIn=pass" \
  "owner=pass" \
  "scopes=pass"; do
  if [[ "${output}" != *"${expected}"* ]]; then
    echo "Admin readiness selftest did not report ${expected}: ${output}" >&2
    exit 1
  fi
done

harness_output="$(
  CT_ADMIN_HARNESS_SELFTEST=1 \
  "${BIN}"
)"
if [[ "${harness_output}" != *"ADMIN_HARNESSES selected=claude,codex yaml=pass json=pass single=pass empty=pass"* ]]; then
  echo "Admin harness selftest did not preserve both default selections through the brief: ${harness_output}" >&2
  exit 1
fi

completion_department_output="$(
  HOME="${FIXTURE_ROOT}/home-completion" \
  CT_ADMIN_COMPLETION_DEPARTMENT_SELFTEST=1 \
  "${BIN}"
)"
if [[ "${completion_department_output}" != *"ADMIN_COMPLETION_DEPARTMENTS restore=pass duplicate=pass valid=pass routed=pass complete=pass reopened=pass"* ]]; then
  echo "Admin completion/department selftest failed: ${completion_department_output}" >&2
  exit 1
fi

if rg -Fq 'Picker("", selection: $model.harness)' native/admin.swift; then
  echo "Admin still uses an exclusive harness picker" >&2
  exit 1
fi

echo "admin app bundle tests: PASS"
