#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HARNESS="${REPO_ROOT}/scripts/headless-detect.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/control-tower-headless-test.XXXXXX")"

cleanup() {
    rm -rf "${SCRATCH}"
}
trap cleanup EXIT

APP="${SCRATCH}/Copilot Control Tower.app"
APP_BINARY="${APP}/Contents/MacOS/Copilot Control Tower"
mkdir -p "$(dirname "${APP_BINARY}")" "${APP}/Contents/Resources"

cat >"${APP_BINARY}" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" > "${CT_TEST_ARGS}"
printf '%s\n' "${PATH}" > "${CT_TEST_PATH}"
if [[ "${CT_TEST_CONTRACT:-pass}" == "pass" ]]; then
    printf '%s\n' '{"auth":{"kind":"status","schema_version":"1.0","status":"authorized"},"calls":["auth-status","doctor","onboard-plan"],"contract":"pass","doctor":{"offline":false,"schema_version":"1.0","score":100,"status":"healthy"},"helper":"/tmp/cc","layer_manifest":{"result":"changes-required"},"mode":"headless-detect","org":"acme-co","products":["claude","codex"],"read_only":true,"result":"changes-required","schema_version":"1.0"}'
else
    printf '%s\n' '{"calls":["auth-status","doctor","onboard-plan"],"contract":"fail","error":"simulated failure","mode":"headless-detect","products":["claude","codex"],"read_only":true}'
fi
EOF
chmod +x "${APP_BINARY}"
printf '#!/bin/bash\n' > "${APP}/Contents/Resources/cc"
chmod +x "${APP}/Contents/Resources/cc"

CT_TEST_ARGS="${SCRATCH}/args" \
CT_TEST_PATH="${SCRATCH}/path" \
    "${HARNESS}" --app "${APP}" >"${SCRATCH}/report.json"

[[ "$(<"${SCRATCH}/args")" == "--headless-detect" ]]
[[ "$(<"${SCRATCH}/path")" == "/usr/bin:/bin:/usr/sbin:/sbin" ]]
/usr/bin/python3 - "${SCRATCH}/report.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["contract"] == "pass"
assert payload["read_only"] is True
assert payload["calls"] == ["auth-status", "doctor", "onboard-plan"]
assert payload["auth"]["status"] == "authorized"
assert payload["doctor"]["status"] == "healthy"
assert payload["products"] == ["claude", "codex"]
PY

current_path="${SCRATCH}/current-bin:/usr/bin:/bin"
CT_TEST_ARGS="${SCRATCH}/current-args" \
CT_TEST_PATH="${SCRATCH}/current-path" \
PATH="${current_path}" \
    "${HARNESS}" --app "${APP}" --current-path >"${SCRATCH}/current-report.json"
[[ "$(<"${SCRATCH}/current-path")" == "${current_path}" ]]

if CT_TEST_ARGS="${SCRATCH}/failed-args" \
    CT_TEST_PATH="${SCRATCH}/failed-path" \
    CT_TEST_CONTRACT=fail \
    "${HARNESS}" --app "${APP}" >"${SCRATCH}/failed-report.json" 2>/dev/null
then
    echo "headless Detect accepted a failed contract" >&2
    exit 1
fi

echo "headless Detect harness: PASS"
