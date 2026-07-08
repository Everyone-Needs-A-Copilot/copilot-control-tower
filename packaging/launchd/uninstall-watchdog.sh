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
DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_NUM="$(id -u)"

/bin/launchctl bootout "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || true
rm -f "${DEST}"

echo "watchdog uninstalled: ${DEST} (gui/${UID_NUM}/${LABEL})"
