#!/usr/bin/env bash
# Real per-user launchd proof for crash-only supervision. Uses a unique label,
# a temporary app bundle/home, and trap-owned cleanup; never touches the
# production LaunchAgent or /Applications.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="${ROOT}/packaging/launchd/install-watchdog.sh"
UNINSTALL="${ROOT}/packaging/launchd/uninstall-watchdog.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ct-watchdog-test.XXXXXX")"
LABEL="com.everyoneneedsacopilot.controltower.test.$(id -u).$$"
TEST_HOME="${SCRATCH}/home"
APP="${SCRATCH}/Copilot Control Tower.app"
APP_CONTENTS="${APP}/Contents"
APP_EXECUTABLE="${APP_CONTENTS}/MacOS/Copilot Control Tower"
RESOURCES="${APP_CONTENTS}/Resources"
DOMAIN="gui/$(id -u)"

watchdog_env=(
    CT_WATCHDOG_TEST_MODE=1
    CT_WATCHDOG_TEST_LABEL="${LABEL}"
    CT_WATCHDOG_TEST_HOME="${TEST_HOME}"
    CT_WATCHDOG_TEST_UID="$(id -u)"
    CT_WATCHDOG_TEST_LAUNCHCTL=/bin/launchctl
    CT_WATCHDOG_TEST_THROTTLE=1
)

cleanup() {
    env "${watchdog_env[@]}" "${UNINSTALL}" >/dev/null 2>&1 || true
    rm -rf "${SCRATCH}"
}
trap cleanup EXIT

mkdir -p "${APP_CONTENTS}/MacOS" "${RESOURCES}" "${TEST_HOME}"
CC=/usr/bin/cc PATH=/usr/bin:$PATH /usr/bin/env swiftc \
    "${ROOT}/scripts/tests/fixtures/watchdog/main.swift" \
    -o "${APP_EXECUTABLE}"
/usr/bin/plutil -create xml1 "${APP_CONTENTS}/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string \
    com.everyoneneedsacopilot.controltower "${APP_CONTENTS}/Info.plist"

wait_for_lines() {
    local expected="$1"
    local deadline=$((SECONDS + 15))
    while (( SECONDS < deadline )); do
        local actual=0
        if [[ -f "${RESOURCES}/probe.log" ]]; then
            actual="$(wc -l < "${RESOURCES}/probe.log" | tr -d ' ')"
        fi
        if [[ "${actual}" == "${expected}" ]]; then
            return 0
        fi
        sleep 0.2
    done
    echo "FAIL: expected ${expected} watchdog launches" >&2
    [[ -f "${RESOURCES}/probe.log" ]] && cat "${RESOURCES}/probe.log" >&2
    return 1
}

assert_installed_shape() {
    local plist="${TEST_HOME}/Library/LaunchAgents/${LABEL}.plist"
    [[ -f "${plist}" ]]
    [[ "$(stat -f '%Lp' "${plist}")" == "600" ]]
    [[ "$(/usr/bin/plutil -extract Label raw "${plist}")" == "${LABEL}" ]]
    [[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw "${plist}")" == "${APP_EXECUTABLE}" ]]
    [[ "$(/usr/bin/plutil -extract KeepAlive.SuccessfulExit raw "${plist}")" == "false" ]]
    [[ "$(/usr/bin/plutil -extract RunAtLoad raw "${plist}")" == "false" ]]
    [[ "$(/usr/bin/plutil -extract EnvironmentVariables.CT_WATCHDOG_MANAGED raw "${plist}")" == "1" ]]
}

# Clean Quit: explicit activation launches once; exit 0 remains stopped.
printf '0\n' > "${RESOURCES}/remaining-crashes"
env "${watchdog_env[@]}" "${INSTALL}" --activate "${APP}" >/dev/null
assert_installed_shape
wait_for_lines 1
sleep 2
[[ "$(wc -l < "${RESOURCES}/probe.log" | tr -d ' ')" == "1" ]]
echo "PASS: clean exit remains stopped"

# Uninstall removes both the loaded user job and its exact plist.
env "${watchdog_env[@]}" "${UNINSTALL}" >/dev/null
[[ ! -e "${TEST_HOME}/Library/LaunchAgents/${LABEL}.plist" ]]
if /bin/launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
    echo "FAIL: watchdog remained loaded after uninstall" >&2
    exit 1
fi
echo "PASS: uninstall removes supervision"

# Repeated crashes: two non-zero exits relaunch; the following exit 0 stops.
rm -f "${RESOURCES}/probe.log"
printf '2\n' > "${RESOURCES}/remaining-crashes"
env "${watchdog_env[@]}" "${INSTALL}" --activate "${APP}" >/dev/null
wait_for_lines 3
sleep 2
[[ "$(wc -l < "${RESOURCES}/probe.log" | tr -d ' ')" == "3" ]]
echo "PASS: non-zero exits restart and later clean exit stops"

# Installed output must never broaden into KeepAlive=true or RunAtLoad=true.
plist="${TEST_HOME}/Library/LaunchAgents/${LABEL}.plist"
if rg -n '<key>KeepAlive</key>[[:space:]]*<true/>' "${plist}"; then
    echo "FAIL: KeepAlive became unconditional" >&2
    exit 1
fi
echo "native watchdog lifecycle: PASS"

# A bundled copy must reject every repository-only authority override before
# executing the supplied fake launchctl.
bundled_scripts="${SCRATCH}/Bundled.app/Contents/Resources/watchdog"
mkdir -p "${bundled_scripts}"
cp "${INSTALL}" "${UNINSTALL}" "${ROOT}/packaging/launchd/com.everyoneneedsacopilot.controltower.plist" \
    "${bundled_scripts}/"
fake_launchctl="${SCRATCH}/fake-launchctl"
fake_marker="${SCRATCH}/fake-launchctl-ran"
cat > "${fake_launchctl}" <<EOF
#!/bin/bash
touch '${fake_marker}'
exit 0
EOF
chmod 755 "${fake_launchctl}"
if CT_WATCHDOG_TEST_MODE=1 \
   CT_WATCHDOG_TEST_LABEL="${LABEL}.bypass" \
   CT_WATCHDOG_TEST_HOME="${TEST_HOME}" \
   CT_WATCHDOG_TEST_LAUNCHCTL="${fake_launchctl}" \
   "${bundled_scripts}/install-watchdog.sh" "${APP}" >/dev/null 2>&1; then
    echo "FAIL: bundled lifecycle accepted test authority overrides" >&2
    exit 1
fi
[[ ! -e "${fake_marker}" ]]
if CT_WATCHDOG_TEST_MODE=1 \
   CT_WATCHDOG_TEST_LABEL="${LABEL}.bypass" \
   CT_WATCHDOG_TEST_HOME="${TEST_HOME}" \
   CT_WATCHDOG_TEST_LAUNCHCTL="${fake_launchctl}" \
   "${bundled_scripts}/uninstall-watchdog.sh" >/dev/null 2>&1; then
    echo "FAIL: bundled uninstall accepted test authority overrides" >&2
    exit 1
fi
[[ ! -e "${fake_marker}" ]]
echo "PASS: bundled lifecycle rejects test authority overrides"
