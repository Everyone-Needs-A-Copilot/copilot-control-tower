#!/bin/bash
# Exercise the production User app's exact Set up -> Verify orchestration
# without UI and without touching the current user's setup.
#
# The app is forced to use the repository's inert mock-cc fixture. The fixture
# records argv so this proof requires the real `onboard ... --apply --json`
# and follow-up `doctor --json` calls, not merely a decodable canned response.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_PATH="${REPO_ROOT}/build/Copilot Control Tower.app"
MOCK_CC="${REPO_ROOT}/src-tauri/fixtures/mock-cc"

usage() {
    cat <<'EOF'
Usage: scripts/headless-setup-transaction.sh [options]

Options:
  --app PATH       App bundle to inspect. Defaults to build/Copilot Control Tower.app.
  --mock-cc PATH   Inert mock helper. Defaults to src-tauri/fixtures/mock-cc.
  -h, --help       Show this help.

The command never invokes the app's bundled real cc helper and never opens UI.
EOF
}

die() {
    echo "headless setup transaction: $*" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            [[ $# -ge 2 ]] || die "--app requires a path"
            APP_PATH="$2"
            shift 2
            ;;
        --mock-cc)
            [[ $# -ge 2 ]] || die "--mock-cc requires a path"
            MOCK_CC="$2"
            shift 2
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
case "${MOCK_CC}" in
    /*) ;;
    *) MOCK_CC="${REPO_ROOT}/${MOCK_CC}" ;;
esac

APP_BINARY="${APP_PATH}/Contents/MacOS/Copilot Control Tower"
[[ -x "${APP_BINARY}" ]] || die "no executable User app at ${APP_PATH}"
[[ -x "${MOCK_CC}" ]] || die "mock helper is not executable at ${MOCK_CC}"
[[ "$(basename "${MOCK_CC}")" == "mock-cc" ]] ||
    die "the proof accepts only an inert helper named mock-cc"

invocation_log="$(mktemp "${TMPDIR:-/tmp}/control-tower-setup-invocations.XXXXXX")"
output="$(mktemp "${TMPDIR:-/tmp}/control-tower-setup-report.XXXXXX")"
cleanup() {
    rm -f "${invocation_log}" "${output}"
}
trap cleanup EXIT

env \
    CT_CLI_PATH="${MOCK_CC}" \
    CT_ALLOW_INERT_SETUP_PROOF=1 \
    CT_MOCK_INVOCATION_LOG="${invocation_log}" \
    CT_SETUP_TRANSACTION_SELFTEST=1 \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    "${APP_BINARY}" >"${output}"

expected='SELFTEST setupTransaction apply=ready layerManifest=applied onboardDoctor=healthy verify=healthy'
rg -Fxq "${expected}" "${output}" ||
    die "the production WizardModel did not complete Set up -> Verify"
rg -Fxq 'onboard --org auto --products claude,codex --apply --json' "${invocation_log}" ||
    die "the app did not send the exact ecosystem apply command"
rg -Fxq 'doctor --json' "${invocation_log}" ||
    die "the app did not perform the separate verify-time doctor call"

cat "${output}"
