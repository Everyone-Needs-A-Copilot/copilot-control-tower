#!/bin/bash
# M4 Stream-D / S6 — removes the crash-only watchdog LaunchAgent.
#
# Companion to install-watchdog.sh. Also the shape of the "watchdog
# self-`bootout`s if its own Program path goes missing" guard
# (architecture.md §7, fixes B-H2) — a signed uninstaller / the app's own
# startup check calls this same `bootout` + `rm` sequence when it detects
# its bundle has been dragged to the Trash, so a deleted app never leaves an
# orphaned LaunchAgent pointed at a nonexistent binary.
#
# NOT executed by this session (constraint: no `launchctl` against the live
# system) — `bash -n` syntax-checked only.

set -euo pipefail

LABEL="com.everyoneneedsacopilot.controltower"
HOME_ROOT="${HOME}"
LAUNCHCTL="/bin/launchctl"
UID_NUM="$(id -u)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_TEST_SCRIPT=0
case "${SCRIPT_DIR}" in
    */packaging/launchd) SOURCE_TEST_SCRIPT=1 ;;
esac

if [[ "${CT_WATCHDOG_TEST_MODE:-0}" == "1" ]]; then
    [[ "${SOURCE_TEST_SCRIPT}" == "1" ]] || {
        echo "error: watchdog test overrides are unavailable in a bundled app" >&2
        exit 1
    }
    LABEL="${CT_WATCHDOG_TEST_LABEL:?CT_WATCHDOG_TEST_LABEL is required}"
    HOME_ROOT="${CT_WATCHDOG_TEST_HOME:?CT_WATCHDOG_TEST_HOME is required}"
    LAUNCHCTL="${CT_WATCHDOG_TEST_LAUNCHCTL:-/bin/launchctl}"
    UID_NUM="${CT_WATCHDOG_TEST_UID:-$(id -u)}"
fi

if [[ "${SOURCE_TEST_SCRIPT}" != "1" ]]; then
    for override_name in \
        CT_WATCHDOG_TEST_MODE CT_WATCHDOG_TEST_LABEL CT_WATCHDOG_TEST_HOME \
        CT_WATCHDOG_TEST_LAUNCHCTL CT_WATCHDOG_TEST_UID; do
        [[ -z "${!override_name:-}" ]] || {
            echo "error: watchdog test override is forbidden in production" >&2
            exit 1
        }
    done
fi

DEST_DIR="${HOME_ROOT}/Library/LaunchAgents"
DEST="${DEST_DIR}/${LABEL}.plist"

if [[ -L "${DEST_DIR}" || -L "${DEST}" ]]; then
    echo "error: refusing a symlinked watchdog destination" >&2
    exit 1
fi

"${LAUNCHCTL}" bootout "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || true
rm -f "${DEST}"

echo "watchdog uninstalled: ${DEST} (gui/${UID_NUM}/${LABEL})"
