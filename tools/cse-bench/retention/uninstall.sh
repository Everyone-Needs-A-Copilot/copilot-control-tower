#!/usr/bin/env bash
# uninstall.sh -- unregister the transcript-retention LaunchAgent.
#
# Bootouts/unloads the job from launchd, removes the plist from
# ~/Library/LaunchAgents/, and removes the deployed runtime copy of the
# script from ~/Library/Application Support/<label>/ (see install.sh for
# why a deployed copy exists -- launchd cannot execute the repo copy
# directly on this machine).
#
# Does NOT touch ~/.claude/transcript-archive -- the archive is
# append-only historical data and is never deleted by any script in this
# directory, install or uninstall.
set -euo pipefail

readonly HOME_DIR="${HOME:-/Users/$(id -un)}"
readonly LABEL="com.copilot.cse.transcript-retention"
readonly PLIST_DST="${HOME_DIR}/Library/LaunchAgents/${LABEL}.plist"
readonly DEPLOY_DIR="${HOME_DIR}/Library/Application Support/${LABEL}"

log() {
    printf '[uninstall] %s\n' "$1"
}

if launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1; then
    log "booted out ${LABEL} via 'launchctl bootout'"
elif launchctl unload "$PLIST_DST" >/dev/null 2>&1; then
    log "unloaded ${LABEL} via 'launchctl unload'"
else
    log "job was not loaded (nothing to unload)"
fi

if [[ -f "$PLIST_DST" ]]; then
    rm -f "$PLIST_DST"
    log "removed ${PLIST_DST}"
else
    log "plist not present at ${PLIST_DST} (nothing to remove)"
fi

if [[ -d "$DEPLOY_DIR" ]]; then
    rm -rf "$DEPLOY_DIR"
    log "removed deployed runtime copy at ${DEPLOY_DIR}"
else
    log "no deployed runtime copy at ${DEPLOY_DIR} (nothing to remove)"
fi

log "uninstall complete. Archive left untouched at ${HOME_DIR}/.claude/transcript-archive"
