#!/usr/bin/env bash
# Verifies the double-clickable User app bundle that people actually launch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

APP="${REPO_ROOT}/build/Copilot Control Tower.app"
CONTENTS="${APP}/Contents"
APP_BIN="${CONTENTS}/MacOS/Copilot Control Tower"
PLIST="${CONTENTS}/Info.plist"

bash scripts/build-user.command --build-only >/dev/null

for required in \
  "${PLIST}" \
  "${APP_BIN}" \
  "${CONTENTS}/Resources/ControlTower.icns"; do
  if [[ ! -e "${required}" ]]; then
    echo "missing User bundle artifact: ${required}" >&2
    exit 1
  fi
done

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${PLIST}")" == "com.everyoneneedsacopilot.controltower" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${PLIST}")" == "Copilot Control Tower" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${PLIST}")" == "true" ]]
[[ -x "${APP_BIN}" ]]

codesign --verify --deep --strict "${APP}"

echo "user app bundle tests: PASS"
