#!/bin/bash
# M4 Stream-D / S6 — installs the crash-only watchdog LaunchAgent.
#
# Renders the checked-in template (`com.everyoneneedsacopilot.controltower.plist`)
# by substituting `__HOME__`/`__APP_PATH__` with real, this-machine values
# (launchd does not expand `~` inside a plist string), writes the result to
# `~/Library/LaunchAgents/`, and loads it via the per-user
# `launchctl bootstrap gui/$UID` domain — never a system/root LaunchDaemon,
# never `sudo launchctl load` (per-user, not per-machine — architecture.md
# §8.3). Admin-free by construction: everything here is userland.
#
# Usage: install-watchdog.sh [--activate] [/path/to/Copilot Control Tower.app]
# Defaults to /Applications/Copilot Control Tower.app.

set -euo pipefail

ACTIVATE=0
if [[ "${1:-}" == "--activate" ]]; then
    ACTIVATE=1
    shift
fi
[[ $# -le 1 ]] || { echo "error: too many arguments" >&2; exit 2; }

APP_PATH="${1:-/Applications/Copilot Control Tower.app}"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${TEMPLATE_DIR}/com.everyoneneedsacopilot.controltower.plist"
LABEL="com.everyoneneedsacopilot.controltower"
HOME_ROOT="${HOME}"
LAUNCHCTL="/bin/launchctl"
UID_NUM="$(id -u)"
THROTTLE_INTERVAL=10
SOURCE_TEST_SCRIPT=0

case "${TEMPLATE_DIR}" in
    */packaging/launchd) SOURCE_TEST_SCRIPT=1 ;;
esac

# Tests use a unique label/home and the real per-user launchctl domain without
# touching the production job. This seam exists only in the repository source
# tree. A copy bundled below Contents/Resources/watchdog rejects it outright.
if [[ "${CT_WATCHDOG_TEST_MODE:-0}" == "1" ]]; then
    [[ "${SOURCE_TEST_SCRIPT}" == "1" ]] || {
        echo "error: watchdog test overrides are unavailable in a bundled app" >&2
        exit 1
    }
    LABEL="${CT_WATCHDOG_TEST_LABEL:?CT_WATCHDOG_TEST_LABEL is required}"
    HOME_ROOT="${CT_WATCHDOG_TEST_HOME:?CT_WATCHDOG_TEST_HOME is required}"
    LAUNCHCTL="${CT_WATCHDOG_TEST_LAUNCHCTL:-/bin/launchctl}"
    UID_NUM="${CT_WATCHDOG_TEST_UID:-$(id -u)}"
    THROTTLE_INTERVAL="${CT_WATCHDOG_TEST_THROTTLE:-1}"
fi

if [[ "${SOURCE_TEST_SCRIPT}" != "1" ]]; then
    for override_name in \
        CT_WATCHDOG_TEST_MODE CT_WATCHDOG_TEST_LABEL CT_WATCHDOG_TEST_HOME \
        CT_WATCHDOG_TEST_LAUNCHCTL CT_WATCHDOG_TEST_UID CT_WATCHDOG_TEST_THROTTLE; do
        [[ -z "${!override_name:-}" ]] || {
            echo "error: watchdog test override is forbidden in production" >&2
            exit 1
        }
    done
fi

case "${APP_PATH}" in
    /*) ;;
    *) echo "error: app path must be absolute: ${APP_PATH}" >&2; exit 1 ;;
esac
[[ -f "${TEMPLATE}" ]] || { echo "error: watchdog template not found" >&2; exit 1; }

APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/Copilot Control Tower"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
DEST_DIR="${HOME_ROOT}/Library/LaunchAgents"
DEST="${DEST_DIR}/${LABEL}.plist"
LOG_DIR="${HOME_ROOT}/Library/Logs/CopilotControlTower"

if [[ ! -d "${APP_PATH}" || ! -x "${APP_EXECUTABLE}" ]]; then
    echo "error: app bundle not found at ${APP_PATH}" >&2
    exit 1
fi
if [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "${INFO_PLIST}" 2>/dev/null || true)" \
      != "com.everyoneneedsacopilot.controltower" ]]; then
    echo "error: app bundle identifier is not Copilot Control Tower" >&2
    exit 1
fi
if [[ "${SOURCE_TEST_SCRIPT}" != "1" ]]; then
    [[ "$(cd "${APP_PATH}/.." && pwd -P)/$(basename "${APP_PATH}")" == \
       "/Applications/Copilot Control Tower.app" ]] || {
        echo "error: production watchdog requires the canonical Applications bundle" >&2
        exit 1
    }
    /usr/bin/codesign --verify --strict \
        --requirements '=anchor apple generic and certificate leaf[subject.OU] = "3SYGVX2HB8"' \
        "${APP_PATH}" >/dev/null 2>&1 || {
        echo "error: app does not satisfy the Control Tower Developer ID trust anchor" >&2
        exit 1
    }
fi
if [[ -L "${DEST_DIR}" || -L "${LOG_DIR}" || -L "${DEST}" ]]; then
    echo "error: refusing a symlinked watchdog destination" >&2
    exit 1
fi

mkdir -p "${DEST_DIR}" "${LOG_DIR}"
chmod 700 "${DEST_DIR}" "${LOG_DIR}"

# Render into an owned temporary file, validate, then atomically replace the
# exact LaunchAgent plist. `plutil` receives paths as argument values, so an
# ampersand or other sed metacharacter in a user name cannot corrupt XML.
TEMP_PLIST="$(mktemp "${DEST}.tmp.XXXXXX")"
cleanup() {
    rm -f "${TEMP_PLIST}"
}
trap cleanup EXIT
cp "${TEMPLATE}" "${TEMP_PLIST}"
/usr/bin/plutil -replace Label -string "${LABEL}" "${TEMP_PLIST}"
/usr/bin/plutil -replace ProgramArguments.0 -string "${APP_EXECUTABLE}" "${TEMP_PLIST}"
/usr/bin/plutil -replace ThrottleInterval -integer "${THROTTLE_INTERVAL}" "${TEMP_PLIST}"
/usr/bin/plutil -replace StandardOutPath -string "${LOG_DIR}/watchdog.out.log" "${TEMP_PLIST}"
/usr/bin/plutil -replace StandardErrorPath -string "${LOG_DIR}/watchdog.err.log" "${TEMP_PLIST}"
/usr/bin/plutil -lint "${TEMP_PLIST}"
chmod 600 "${TEMP_PLIST}"
mv -f "${TEMP_PLIST}" "${DEST}"
trap - EXIT

/usr/bin/plutil -lint "${DEST}"

# Per-user gui domain only (invariant: per-user, not per-machine). Bootout
# first so re-running this script is idempotent (a stale prior load with a
# different Program path doesn't linger alongside the new one).
"${LAUNCHCTL}" bootout "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || true
"${LAUNCHCTL}" bootstrap "gui/${UID_NUM}" "${DEST}"
if [[ "${ACTIVATE}" == "1" ]]; then
    "${LAUNCHCTL}" kickstart -k "gui/${UID_NUM}/${LABEL}"
fi

echo "watchdog installed: ${DEST} (gui/${UID_NUM}/${LABEL}, activated=${ACTIVATE})"
