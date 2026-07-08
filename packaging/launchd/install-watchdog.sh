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
# NOT executed by this session (constraint: no `launchctl load` against the
# live system) — this is the install mechanism for a real deploy / the app's
# own first-run setup hook to shell out to, not something run during
# development or CI verification. `bash -n` syntax-checks clean; that is the
# extent of this session's verification.
#
# Usage: install-watchdog.sh [/path/to/Copilot Control Tower.app]
# Defaults to /Applications/Copilot Control Tower.app.

set -euo pipefail

APP_PATH="${1:-/Applications/Copilot Control Tower.app}"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${TEMPLATE_DIR}/com.everyoneneedsacopilot.controltower.plist"
LABEL="com.everyoneneedsacopilot.controltower"
DEST_DIR="${HOME}/Library/LaunchAgents"
DEST="${DEST_DIR}/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs/CopilotControlTower"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "error: app bundle not found at ${APP_PATH}" >&2
    exit 1
fi

mkdir -p "${DEST_DIR}" "${LOG_DIR}"

# Substitute placeholders — never hand-edit the template in place, so a
# fresh install always starts from the reviewed, lint-clean checked-in file.
sed \
    -e "s#__HOME__#${HOME}#g" \
    -e "s#__APP_PATH__#${APP_PATH}#g" \
    "${TEMPLATE}" > "${DEST}"

/usr/bin/plutil -lint "${DEST}"

# Per-user gui domain only (invariant: per-user, not per-machine). Bootout
# first so re-running this script is idempotent (a stale prior load with a
# different Program path doesn't linger alongside the new one).
UID_NUM="$(id -u)"
/bin/launchctl bootout "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/${UID_NUM}" "${DEST}"

echo "watchdog installed: ${DEST} (gui/${UID_NUM}/${LABEL})"
