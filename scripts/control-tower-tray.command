#!/bin/bash
# Thin alias for scripts/build-user.command, kept so the pre-existing
# double-clickable entry point (and anything that already shells out to this
# exact filename) keeps working. `build-user.command` (added when the app
# split into an explicit USER-face / ADMIN-face build, see
# `scripts/build-admin.command`'s header) is the real build script now — this
# file just builds it, then runs it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/build-user.command" "$@"
