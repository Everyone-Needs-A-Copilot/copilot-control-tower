#!/usr/bin/env bash
# Release gate for the returning-person ecosystem and project-aftercare view.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

assert_source() {
    local label="$1"
    local pattern="$2"
    local path="$3"
    if ! rg -q -- "${pattern}" "${path}"; then
        echo "FAIL: ${label}" >&2
        exit 1
    fi
    echo "PASS: ${label}"
}

assert_source "four fixed Copilot components" \
    'case knowledge|case cli|case claude|case codex' \
    native/user-settings.swift
assert_source "all four tiers are rendered" \
    'let tiers = \[foundation, organization, department, personalTier\]' \
    native/user-settings.swift
assert_source "Personal checks request all components" \
    'components: UserSettingsComponent\.allCases\.map' \
    native/user-settings.swift
assert_source "readiness remains truthful when Personal is incomplete" \
    'Your copilots work, but Personal setup is incomplete' \
    native/user-settings.swift
assert_source "Personal and private are distinguished" \
    'Personal is yours; its repository is private' \
    native/user-settings.swift
assert_source "completed project categories route to Step 7" \
    'reopenForProjects\(category: category\)' \
    native/user-settings.swift
assert_source "project aftercare can be deferred" \
    'Finish one or two projects now, or return later' \
    native/user-settings.swift
assert_source "aggregate helper reports the full component contract" \
    '"components"' \
    docs/01-architecture/schemas/onboard.schema.json
assert_source "UX walkthrough includes setup-incomplete recovery" \
    'Personal setup is incomplete' \
    docs/40-initiatives/02-enac-self-onboarding/walkthroughs/09-completed-setup-topology-uxd-walkthrough.html
assert_source "UI walkthrough includes focused project aftercare" \
    'Come back whenever you want' \
    docs/40-initiatives/02-enac-self-onboarding/walkthroughs/10-completed-setup-topology-uids-walkthrough.html

scripts/build-user.command --build-only >/dev/null
selftest="$(
    CT_PROJECTS_STEP_SELFTEST=1 \
        "build/Copilot Control Tower.app/Contents/MacOS/Copilot Control Tower"
)"
expected='settingsAftercare=pass settingsTopology=pass'
if [[ "${selftest}" != *"${expected}"* ]]; then
    echo "FAIL: completed-state binary selftest: ${selftest}" >&2
    exit 1
fi
echo "PASS: completed-state binary topology and aftercare selftest"

echo "completed setup acceptance: PASS"
