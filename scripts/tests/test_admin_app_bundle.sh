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

echo "admin app bundle tests: PASS"
