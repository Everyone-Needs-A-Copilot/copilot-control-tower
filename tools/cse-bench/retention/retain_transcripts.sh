#!/usr/bin/env bash
# retain_transcripts.sh
#
# Append-only archiver for Claude Code and Codex CLI transcripts.
#
# WHY: Claude Code's own retention policy actively deletes transcripts
# (observed corpus shrink 113->108 sessions in ~24h). Deleted transcripts
# are the only irreversible data loss in the CSE Verification & Benchmark
# Program (finding F-6). This script mirrors both transcript sources into
# an archive that is NEVER pruned by this script -- files that disappear
# from the source remain in the archive forever (until a human deletes
# them by hand).
#
# Sources:
#   ~/.claude/projects/   (Claude Code transcripts)
#   ~/.codex/sessions/    (Codex transcripts)
#
# Destination:
#   ~/.claude/transcript-archive/claude-projects/
#   ~/.claude/transcript-archive/codex-sessions/
#
# Contract: rsync -a WITHOUT --delete. Files updated at the source may
# overwrite their archived copy (that's fine, same content lineage).
# Files removed at the source are NEVER removed from the archive by this
# script. There is no flag, no override, no exception -- delete is simply
# never passed to rsync.
#
# Dependencies: rsync, find, du (all present on stock macOS). No other
# tooling required.
set -euo pipefail

# ---------------------------------------------------------------------------
# Absolute paths only -- this script is invoked by launchd with a minimal
# environment, so it must not depend on $HOME being set the way an
# interactive shell would set it, and must not rely on PATH lookups for
# anything beyond the standard macOS tool locations.
# ---------------------------------------------------------------------------
readonly HOME_DIR="${HOME:-/Users/$(id -un)}"

readonly SRC_CLAUDE="${HOME_DIR}/.claude/projects"
readonly SRC_CODEX="${HOME_DIR}/.codex/sessions"

readonly ARCHIVE_ROOT="${HOME_DIR}/.claude/transcript-archive"
readonly DST_CLAUDE="${ARCHIVE_ROOT}/claude-projects"
readonly DST_CODEX="${ARCHIVE_ROOT}/codex-sessions"

readonly RUN_LOG="${ARCHIVE_ROOT}/runs.log"

readonly RSYNC_BIN="/usr/bin/rsync"
readonly FIND_BIN="/usr/bin/find"
readonly DU_BIN="/usr/bin/du"

# ISO 8601 UTC timestamp for this run.
readonly RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log() {
    printf '%s [retain_transcripts] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
}

# count_files DIR -> integer file count, 0 if DIR does not exist.
count_files() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        "$FIND_BIN" "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
    else
        printf '0'
    fi
}

# archive_bytes DIR -> total size in bytes, 0 if DIR does not exist.
archive_bytes() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        "$DU_BIN" -sk "$dir" 2>/dev/null | awk '{print $1 * 1024}'
    else
        printf '0'
    fi
}

# sync_source SRC DST LABEL
#
# Mirrors SRC into DST with rsync -a (no --delete). Skips gracefully with
# a log line if SRC does not exist -- a missing source (e.g. Codex not
# installed on this machine) must never fail the whole run.
sync_source() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [[ ! -d "$src" ]]; then
        log "SKIP ${label}: source not found at ${src}"
        return 0
    fi

    mkdir -p "$dst"

    # Trailing slash on src copies contents of src into dst, not src itself
    # as a subdirectory -- this is what makes DST mirror SRC's contents.
    "$RSYNC_BIN" -a "${src}/" "${dst}/"
    log "SYNC ${label}: ${src} -> ${dst}"
}

main() {
    mkdir -p "$ARCHIVE_ROOT" "$DST_CLAUDE" "$DST_CODEX"

    log "run start"

    sync_source "$SRC_CLAUDE" "$DST_CLAUDE" "claude-projects"
    sync_source "$SRC_CODEX" "$DST_CODEX" "codex-sessions"

    local src_claude_count dst_claude_count dst_claude_bytes
    local src_codex_count dst_codex_count dst_codex_bytes

    src_claude_count="$(count_files "$SRC_CLAUDE")"
    dst_claude_count="$(count_files "$DST_CLAUDE")"
    dst_claude_bytes="$(archive_bytes "$DST_CLAUDE")"

    src_codex_count="$(count_files "$SRC_CODEX")"
    dst_codex_count="$(count_files "$DST_CODEX")"
    dst_codex_bytes="$(archive_bytes "$DST_CODEX")"

    # Run record: ISO timestamp, files-in-source, files-in-archive,
    # bytes-in-archive, per source. Pipe-delimited, one line per run,
    # append-only.
    printf '%s claude-projects src_files=%s archive_files=%s archive_bytes=%s | codex-sessions src_files=%s archive_files=%s archive_bytes=%s\n' \
        "$RUN_TS" \
        "$src_claude_count" "$dst_claude_count" "$dst_claude_bytes" \
        "$src_codex_count" "$dst_codex_count" "$dst_codex_bytes" \
        >> "$RUN_LOG"

    log "run complete"
}

main "$@"
