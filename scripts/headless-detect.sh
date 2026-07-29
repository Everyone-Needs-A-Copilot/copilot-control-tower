#!/bin/bash
# Run the production User app's exact Detect seam without showing any UI.
#
# This launches the app executable with --headless-detect. The binary uses
# its normal bundle-relative cc locator, Process boundary, schema gate, and
# EcosystemOnboardReport decoder, then exits before creating a status item or
# wizard window. Only PATH is replaced to match a Finder launch; the signed-in
# user session, HOME, Keychain access, and launchd environment are preserved.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_PATH="${REPO_ROOT}/build/Copilot Control Tower.app"
USE_FINDER_PATH=true

usage() {
    cat <<'EOF'
Usage: scripts/headless-detect.sh [options]

Options:
  --app PATH       App bundle to inspect. Defaults to build/Copilot Control Tower.app.
  --current-path   Preserve the current shell PATH instead of simulating Finder.
  -h, --help       Show this help.

The command is read-only. It never passes --apply and never opens the app UI.
EOF
}

die() {
    echo "headless Detect: $*" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            [[ $# -ge 2 ]] || die "--app requires a path"
            APP_PATH="$2"
            shift 2
            ;;
        --current-path)
            USE_FINDER_PATH=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

case "${APP_PATH}" in
    /*) ;;
    *) APP_PATH="${REPO_ROOT}/${APP_PATH}" ;;
esac

APP_BINARY="${APP_PATH}/Contents/MacOS/Copilot Control Tower"
[[ -x "${APP_BINARY}" ]] || die "no executable User app at ${APP_PATH}"
[[ -x "${APP_PATH}/Contents/Resources/cc" ]] ||
    die "the app does not contain an executable cc helper"

output="$(mktemp "${TMPDIR:-/tmp}/control-tower-headless-detect.XXXXXX")"
cleanup() {
    rm -f "${output}"
}
trap cleanup EXIT

run_status=0
if [[ "${USE_FINDER_PATH}" == true ]]; then
    env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        "${APP_BINARY}" --headless-detect >"${output}" || run_status=$?
else
    "${APP_BINARY}" --headless-detect >"${output}" || run_status=$?
fi

if ! /usr/bin/python3 - "${output}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("mode") != "headless-detect":
    raise SystemExit("the app returned the wrong headless mode")
if payload.get("read_only") is not True:
    raise SystemExit("the app did not confirm a read-only plan")
if payload.get("products") != ["claude", "codex"]:
    raise SystemExit("Detect did not inspect both supported products")
if payload.get("contract") != "pass":
    raise SystemExit(payload.get("error") or "the Detect contract failed")
if not isinstance(payload.get("layer_manifest"), dict):
    raise SystemExit("Detect did not inspect the layer manifest")
PY
then
    cat "${output}"
    if [[ "${run_status}" -ne 0 ]]; then
        exit "${run_status}"
    fi
    exit 1
fi

cat "${output}"
[[ "${run_status}" -eq 0 ]] ||
    die "the app reported a failed Detect contract (exit ${run_status})"
