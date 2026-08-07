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
  "${CONTENTS}/Resources/ControlTower.icns" \
  "${CONTENTS}/Resources/aviator-glyph.svg"; do
  if [[ ! -e "${required}" ]]; then
    echo "missing User bundle artifact: ${required}" >&2
    exit 1
  fi
done

cmp assets/brand/aviator-glyph.svg "${CONTENTS}/Resources/aviator-glyph.svg"
if rg -Fq 'systemSymbolName: "eyeglasses"' native/models.swift; then
  echo "the menu-bar aviators loader regained a substitute icon" >&2
  exit 1
fi
if [[ "$(rg -c 'button\.image = AviatorGlyph\.load' native/control-tower-tray.swift)" != "1" ]]; then
  echo "the status item is not assigned exactly one aviators base image" >&2
  exit 1
fi
if rg -q 'ProviderCard|Microsoft 365|Salesforce|Slack' native/wizard.swift; then
  echo "the User wizard regained the speculative provider catalog" >&2
  exit 1
fi
if rg -Fq 'Inert placeholder: Settings' native/control-tower-tray.swift; then
  echo "the native Settings entry point is inert again" >&2
  exit 1
fi
rg -Fq 'native/user-settings.swift' scripts/build-user.command
rg -Fq 'UserSettingsWindowController.shared.show()' native/control-tower-tray.swift
if [[ "$(rg -Fc 'openSettings()' native/control-tower-tray.swift)" -lt "3" ]]; then
  echo "popover and menu Settings entries no longer share one open path" >&2
  exit 1
fi
rg -Fq 'title: "Your connections"' native/wizard.swift
rg -Fq 'No additional organization connections are available in Control Tower right now.' native/wizard.swift
if ! sed -n '/func continueWithoutFailedProjects()/,/^    }/p' native/wizard.swift | rg -Fq 'beginVerify()'; then
  echo "the project-failure continue action no longer advances to verification" >&2
  exit 1
fi
verify_source="$(sed -n '/func beginVerify()/,/^    }/p' native/wizard.swift)"
if [[ "${verify_source}" != *'CliClient.shared.reconciliationRun()'* ]] ||
  [[ "${verify_source}" == *'CliClient.shared.doctor()'* ]] ||
  [[ "${verify_source}" == *'CliClient.shared.update()'* ]] ||
  [[ "${verify_source}" == *'CliClient.shared.workspaces()'* ]]; then
  echo "Verify is not exclusively rendering the complete Python setup journey" >&2
  exit 1
fi
rg -Fq '["reconcile", "run", "--json"]' native/cli-client.swift
rg -Fq '["support", "latest", "--json"]' native/cli-client.swift

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${PLIST}")" == "com.everyoneneedsacopilot.controltower" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${PLIST}")" == "Copilot Control Tower" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${PLIST}")" == "true" ]]
[[ -x "${APP_BIN}" ]]

codesign --verify --deep --strict "${APP}"
scripts/verify-user-automation.sh "${APP}" >/dev/null

# Pixel inspection builds can load deterministic wizard states, but the hook
# must be compiled out of the User app people install.
if strings "${APP_BIN}" | rg -q 'CT_VISUAL_SCENARIO|completion-fallback' ||
  nm "${APP_BIN}" | rg -q 'loadVisualScenario'; then
  echo "visual-test hook is present in the production User app" >&2
  exit 1
fi

# adopt-and-project-setup spec self-tests (in-binary, offline — see
# native/control-tower-tray.swift's `AppDelegate.applicationDidFinishLaunching`
# for the harness contract these three env vars trigger).
onboard_question_output="$(CT_ONBOARD_QUESTION_SELFTEST=1 "${APP_BIN}")"
if [[ "${onboard_question_output}" != *"SELFTEST onboardQuestion repoRowDecode=pass askCount=2 reviewCount=1 componentId=pass declineDetail=pass"* ]]; then
  echo "One question first selftest failed: ${onboard_question_output}" >&2
  exit 1
fi

projects_step_output="$(CT_PROJECTS_STEP_SELFTEST=1 "${APP_BIN}")"
if [[ "${projects_step_output}" != *"SELFTEST projectsStep workspaceDecode=pass discovery=pass preselect=pass rootsDecode=pass stageOrder=pass settingsAftercare=pass settingsTopology=pass triage=pass diagnostic=pass"* ]]; then
  echo "Your projects step selftest failed: ${projects_step_output}" >&2
  exit 1
fi

tray_projects_output="$(CT_TRAY_PROJECTS_SELFTEST=1 "${APP_BIN}")"
if [[ "${tray_projects_output}" != *"SELFTEST trayProjects notice=pass rows=pass routes=pass automatic=pass automaticNotice=pass revert=pass diagnostic=pass"* ]]; then
  echo "Tray projects drill-in selftest failed: ${tray_projects_output}" >&2
  exit 1
fi

setup_progress_output="$(CT_SETUP_PROGRESS_SELFTEST=1 "${APP_BIN}")"
if [[ "${setup_progress_output}" != *"SELFTEST setupProgress neverStarted=pass distinctWorking=pass realResults=pass blockedDetail=pass countLine=pass fixedDenominator=pass noDenominator=pass"* ]]; then
  echo "Setup progress selftest failed: ${setup_progress_output}" >&2
  exit 1
fi

setup_transaction_output="$(
  scripts/headless-setup-transaction.sh --app "${APP}"
)"
if [[ "${setup_transaction_output}" != *"SELFTEST setupTransaction apply=ready layerManifest=applied onboardDoctor=healthy verify=operational"* ]]; then
  echo "Setup transaction selftest failed: ${setup_transaction_output}" >&2
  exit 1
fi

tray_wait_output="$(CT_TRAY_WAIT_SELFTEST=1 "${APP_BIN}")"
if [[ "${tray_wait_output}" != *"SELFTEST trayWait join=pass add=pass undo=pass namedSpinner=pass"* ]]; then
  echo "Tray named-wait selftest failed: ${tray_wait_output}" >&2
  exit 1
fi

# Exercise the production headless seam through the real app binary and the
# same CliClient typed verb Detect uses. The mock owns ecosystem computation;
# this assertion covers app location/spawn/schema/decode/reporting only.
headless_detect_output="$(
  CT_CLI_PATH="${REPO_ROOT}/src-tauri/fixtures/mock-cc" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    "${APP_BIN}" --headless-detect
)"
/usr/bin/python3 - "${headless_detect_output}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["mode"] == "headless-detect"
assert payload["contract"] == "pass"
assert payload["read_only"] is True
assert payload["calls"] == ["auth-status", "doctor", "onboard-plan"]
assert payload["auth"]["status"] == "authorized"
assert payload["doctor"]["status"] == "healthy"
assert payload["products"] == ["claude", "codex"]
assert payload["layer_manifest"]["result"] == "changes-required"
PY

# Every production Detect call is gating. A healthy onboarding plan must not
# hide an unreadable auth or doctor response.
if CT_CLI_PATH="${REPO_ROOT}/src-tauri/fixtures/mock-cc" \
    CT_AUTH_SCENARIO=exit-2 \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    "${APP_BIN}" --headless-detect >/dev/null 2>&1
then
  echo "headless Detect accepted an unreadable auth status" >&2
  exit 1
fi

if CT_CLI_PATH="${REPO_ROOT}/src-tauri/fixtures/mock-cc" \
    CT_AUTH_SCENARIO=signed-out \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    "${APP_BIN}" --headless-detect >/dev/null 2>&1
then
  echo "headless Detect accepted a signed-out account" >&2
  exit 1
fi

if CT_CLI_PATH="${REPO_ROOT}/src-tauri/fixtures/mock-cc" \
    CT_FIXTURE=exit-2 \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    "${APP_BIN}" --headless-detect >/dev/null 2>&1
then
  echo "headless Detect accepted an unreadable doctor/onboard response" >&2
  exit 1
fi

# The wizard's Set up step once faked its progress: a Swift-built label array
# advanced by `cyclePhases`' own `Task.sleep`, running after the real call had
# already returned. Progress must come from the CLI's reported stages, so keep
# that pattern from coming back. Matches the definition, not the word, since
# the comment explaining the removal names it too.
if rg -q 'func +cyclePhases' native/wizard.swift; then
  echo "Wizard setup progress is timer-driven again (cyclePhases returned)" >&2
  exit 1
fi

echo "user app bundle tests: PASS"
