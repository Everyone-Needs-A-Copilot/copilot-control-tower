#!/usr/bin/env bash
# install.sh -- register the transcript-retention LaunchAgent.
#
# Deploys a runtime copy of retain_transcripts.sh and bootstraps the
# LaunchAgent into the current user's launchd GUI domain so it runs
# hourly (StartInterval 3600) and immediately once at load (RunAtLoad
# true).
#
# WHY A DEPLOYED COPY INSTEAD OF RUNNING THE REPO SCRIPT IN PLACE:
# on this machine the repo lives on an external USB-attached volume
# (/Volumes/...). macOS blocks launchd-spawned processes (bash, cat, any
# system binary) from even *reading* files on that volume -- this is a
# TCC/"Files and Folders" privacy protection for external volumes with no
# scriptable grant path (it requires an interactive System Settings
# prompt, and launchd background jobs have no UI to prompt with). This is
# independent of file permissions/ownership; chmod does not fix it.
# Verified directly: `launchctl bootstrap` running `/bin/cat` on a file on
# the repo volume fails with "Operation not permitted", while the exact
# same file executed interactively works fine.
#
# The fix: install.sh copies the script to a stable location on the boot
# volume (~/Library/Application Support/<label>/) that launchd CAN read,
# and points the installed LaunchAgent plist at that copy. The repo copy
# remains the single source of truth for the script's logic -- re-run
# install.sh after editing retain_transcripts.sh to redeploy the change.
#
# Never touches the transcript archive itself -- this script only manages
# the LaunchAgent registration and its own deployed-copy directory.
set -euo pipefail

readonly HOME_DIR="${HOME:-/Users/$(id -un)}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LABEL="com.copilot.cse.transcript-retention"
readonly PLIST_SRC="${SCRIPT_DIR}/${LABEL}.plist"
readonly PLIST_DST="${HOME_DIR}/Library/LaunchAgents/${LABEL}.plist"
readonly ARCHIVE_ROOT="${HOME_DIR}/.claude/transcript-archive"

readonly REPO_SCRIPT="${SCRIPT_DIR}/retain_transcripts.sh"
readonly DEPLOY_DIR="${HOME_DIR}/Library/Application Support/${LABEL}"
readonly DEPLOY_SCRIPT="${DEPLOY_DIR}/retain_transcripts.sh"

log() {
    printf '[install] %s\n' "$1"
}

if [[ ! -f "$PLIST_SRC" ]]; then
    printf '[install] ERROR: plist template not found at %s\n' "$PLIST_SRC" >&2
    exit 1
fi
if [[ ! -f "$REPO_SCRIPT" ]]; then
    printf '[install] ERROR: retain_transcripts.sh not found at %s\n' "$REPO_SCRIPT" >&2
    exit 1
fi

mkdir -p "${HOME_DIR}/Library/LaunchAgents"
mkdir -p "$ARCHIVE_ROOT"
mkdir -p "$DEPLOY_DIR"

cp "$REPO_SCRIPT" "$DEPLOY_SCRIPT"
chmod +x "$DEPLOY_SCRIPT"
log "deployed runtime copy to ${DEPLOY_SCRIPT}"

# Rewrite the ProgramArguments script path in the plist template (which
# points at the repo copy, for readability/review) to the deployed copy
# launchd can actually execute. All other settings (label, interval,
# RunAtLoad, log paths) pass through unchanged.
sed "s#${REPO_SCRIPT}#${DEPLOY_SCRIPT}#" "$PLIST_SRC" > "$PLIST_DST"
log "wrote LaunchAgent plist to ${PLIST_DST} (script path -> deployed copy)"

# Unload any stale prior registration before (re-)bootstrapping, so
# reinstalling after an edit doesn't fail on an already-loaded label.
launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true

if launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null; then
    log "bootstrapped ${LABEL} via 'launchctl bootstrap'"
else
    log "'launchctl bootstrap' unavailable or failed; falling back to 'launchctl load'"
    launchctl load "$PLIST_DST"
    log "loaded ${LABEL} via 'launchctl load'"
fi

log "install complete. Verify with:"
log "  launchctl print gui/$(id -u)/${LABEL}"
log "  tail ${ARCHIVE_ROOT}/runs.log"
