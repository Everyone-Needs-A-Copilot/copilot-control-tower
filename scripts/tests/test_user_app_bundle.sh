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

# adopt-and-project-setup spec self-tests (in-binary, offline — see
# native/control-tower-tray.swift's `AppDelegate.applicationDidFinishLaunching`
# for the harness contract these three env vars trigger).
onboard_question_output="$(CT_ONBOARD_QUESTION_SELFTEST=1 "${APP_BIN}")"
if [[ "${onboard_question_output}" != *"SELFTEST onboardQuestion repoRowDecode=pass askCount=1 reviewCount=1 componentId=pass"* ]]; then
  echo "One question first selftest failed: ${onboard_question_output}" >&2
  exit 1
fi

projects_step_output="$(CT_PROJECTS_STEP_SELFTEST=1 "${APP_BIN}")"
if [[ "${projects_step_output}" != *"SELFTEST projectsStep workspaceDecode=pass discovery=pass preselect=pass rootsDecode=pass stageOrder=pass"* ]]; then
  echo "Your projects step selftest failed: ${projects_step_output}" >&2
  exit 1
fi

tray_projects_output="$(CT_TRAY_PROJECTS_SELFTEST=1 "${APP_BIN}")"
if [[ "${tray_projects_output}" != *"SELFTEST trayProjects notice=pass rows=pass"* ]]; then
  echo "Tray projects drill-in selftest failed: ${tray_projects_output}" >&2
  exit 1
fi

echo "user app bundle tests: PASS"
