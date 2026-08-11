#!/bin/bash
# Verify the signed User app can request macOS permission to open guided
# Claude Code/Codex sessions in Terminal. Source code that merely contains an
# AppleScript string is not sufficient: hardened-runtime signing and TCC also
# require the Apple Events entitlement and a user-facing purpose string.

set -euo pipefail

APP_PATH="${1:?usage: verify-user-automation.sh /path/to/Copilot Control Tower.app}"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"

if [[ ! -d "${APP_PATH}" || ! -f "${PLIST_PATH}" ]]; then
    echo "error: User app bundle is incomplete at ${APP_PATH}" >&2
    exit 1
fi

purpose="$({ plutil -extract NSAppleEventsUsageDescription raw "${PLIST_PATH}"; } 2>/dev/null || true)"
if [[ -z "${purpose}" ]]; then
    echo "error: User app is missing NSAppleEventsUsageDescription" >&2
    exit 1
fi

entitlements_file="$(mktemp "${TMPDIR:-/tmp}/control-tower-entitlements.XXXXXX")"
cleanup() {
    rm -f "${entitlements_file}"
}
trap cleanup EXIT

if ! codesign -d --xml --entitlements - "${APP_PATH}" >"${entitlements_file}" 2>/dev/null; then
    echo "error: could not read User app signing entitlements" >&2
    exit 1
fi

automation="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :com.apple.security.automation.apple-events' \
        "${entitlements_file}" 2>/dev/null || true
)"
if [[ "${automation}" != "true" ]]; then
    echo "error: signed User app cannot request Terminal automation permission" >&2
    exit 1
fi

echo "user automation contract: PASS"
