#!/usr/bin/env bash
# Screen-level acceptance gate for walkthroughs 05–08.
#
# Defaults to the release candidate helper in packaging/cc. A development
# build may supply CT_ACCEPTANCE_CC, but that does not satisfy the signed,
# notarized release gate in verify-vendored-cc.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CC_PATH="${CT_ACCEPTANCE_CC:-${REPO_ROOT}/packaging/cc/cc}"
CLAUDE_ROOT="${CT_ACCEPTANCE_CLAUDE_ROOT:-/Volumes/Dev/Sites/COPILOT/claude-copilot}"
CODEX_ROOT="${CT_ACCEPTANCE_CODEX_ROOT:-/Volumes/Dev/Sites/COPILOT/codex-copilot}"

passes=0
failures=0
critical_failures=0

pass() {
    passes=$((passes + 1))
    echo "PASS $1 — $2"
}

fail() {
    failures=$((failures + 1))
    if [[ "${3:-standard}" == "critical" ]]; then
        critical_failures=$((critical_failures + 1))
    fi
    echo "FAIL $1 — $2" >&2
}

check_rg() {
    local id="$1" title="$2" pattern="$3" file="$4" importance="${5:-standard}"
    if rg -Fq "${pattern}" "${REPO_ROOT}/${file}"; then
        pass "${id}" "${title}"
    else
        fail "${id}" "${title}" "${importance}"
    fi
}

# Walkthrough 05 / 06: truthful setup and visual realization.
check_rg 05-01 "named four-copilot roster" '["Knowledge Copilot", "CLI Copilot", "Claude Copilot", "Codex Copilot"]' native/wizard.swift critical
check_rg 05-02 "exact setup inventory remains CLI-authored" 'self.ecosystemInventory = onboard.inventory ?? []' native/wizard.swift critical
check_rg 05-03 "progress uses a fixed real denominator" 'outcomes reported.' native/wizard.swift critical
check_rg 05-04 "Mac readiness comes from post-setup Doctor" 'self.verifiedCopilotState = RenderState.from(doctor, joinable: nil)' native/wizard.swift critical
check_rg 05-05 "projects use all five authoritative classifications" 'ProjectTriageCategory.allCases.filter' native/wizard.swift critical
check_rg 05-06 "safe review shows preservation boundaries" 'wizardProjectContractPanel(' native/wizard.swift critical
check_rg 05-07 "safe, guided, and owner routes stay distinct" 'case .ownerDecision: return "Review decision"' native/wizard.swift critical
check_rg 05-08 "safe write requires returned Ready classification" 'updated.classification == .ready' native/wizard.swift critical
check_rg 05-09 "final screen reports authoritative project outcomes" 'wizardVerifiedProjectSummary' native/wizard.swift
check_rg 05-10 "popover uses readable component status and layers" 'component.layers.map { "\($0.layer.label): \($0.severity.rawValue)" }' native/control-tower-tray.swift
check_rg 05-11 "unresolved states retain reason and actor routes" 'case .couldNotVerify: return "Couldn'\''t confirm"' native/wizard.swift critical
check_rg 06-V "high-fidelity wizard uses native cards, hierarchy, and status labels" 'sectionCard("Your Copilot setup")' native/wizard.swift

# Walkthrough 07 / 08: project integration and aftercare.
check_rg 07-01 "schema fixture covers all five project classifications" '"could-not-verify": 1' src-tauri/fixtures/workspaces/status-all-1.1.json critical
check_rg 07-02 "project register focuses one next-action category" 'wizardProjectCategoryList(category)' native/wizard.swift
check_rg 07-03 "Ready details expose capability and evidence" 'wizardProjectEvidencePanel(workspace)' native/wizard.swift
check_rg 07-04 "safe finish is review-first" 'case .safeFinish, .excluded: return "Review"' native/control-tower-tray.swift critical
check_rg 07-05 "safe finishing passes the opaque action id" 'actionId: action.id' native/wizard.swift critical
check_rg 07-06 "one-sided integrations render per-component assessments" 'ForEach(workspace.components, id: \.component.rawValue)' native/control-tower-tray.swift
check_rg 07-07 "guided route shows detected and preserved facts" 'projectPreservationRow("Detected", values: plan.detected)' native/control-tower-tray.swift
check_rg 07-08 "deep specialization keeps capability counts visible" 'projectCapabilitySummary(workspace.capabilities)' native/control-tower-tray.swift
check_rg 07-09 "mixed customization carries explicit stop conditions" 'plan.stopConditions + plan.verification.stopConditions' native/control-tower-tray.swift critical
check_rg 07-10 "guided plan states Detected/Required/Preserve/Must not" 'wizardProjectFactRow("Must not", prohibited)' native/wizard.swift
check_rg 07-11 "authorized author can run Codex or Claude Code visibly" 'Button("Run in Claude Code")' native/wizard.swift
check_rg 07-12 "full generated prompt is reviewable" 'DisclosureGroup("Full guided prompt")' native/wizard.swift
check_rg 07-13 "non-owner gets copy and Share handoff actions" 'ShareLink(item: handoff)' native/control-tower-tray.swift
check_rg 07-14 "returning from an assistant triggers CLI verification" 'model.verifyPendingProjectOnReturn()' native/wizard.swift critical
check_rg 07-15 "verification remains authoritative and fail-closed" 'The project remains incomplete.' native/control-tower-tray.swift critical
check_rg 07-16 "completed custom capability stays visible in register" 'wizardCapabilitySummary(workspace.capabilities)' native/wizard.swift
check_rg 07-17 "unfinished project work remains available after setup" 'Every unfinished route stays available under Your projects in Copilot Control Tower' native/wizard.swift critical
check_rg 07-18 "menu-bar aftercare repeats the durable return path" 'Project setup is always available here. Finish one or two projects now' native/control-tower-tray.swift critical
check_rg 07-19 "could-not-confirm exposes exact diagnostic evidence" 'ProjectTriageRender.diagnosticReport(workspace)' native/control-tower-tray.swift critical
check_rg 07-20 "guided setup launches a visible Terminal session" 'tell application "Terminal"' native/control-tower-tray.swift critical
check_rg 07-21 "helper-authored read-only diagnosis launches visibly" 'Button("Diagnose in Claude Code")' native/wizard.swift critical
check_rg 07-22 "signed User app can request Terminal automation" 'scripts/verify-user-automation.sh "${app_path}"' scripts/package-user-release.sh critical
check_rg 07-23 "guided assistants use resolved absolute executables" 'guard let executablePath = resolveExecutable(assistant.command)' native/control-tower-tray.swift critical
check_rg 08-V "high-fidelity popover has readable status hierarchy" 'Text(component.worstSeverity == .pass ? "Ready"' native/control-tower-tray.swift

# Exact embedded-helper boundary. These are critical and intentionally fail
# against the stale packaged helper until a new upstream artifact is pinned.
if [[ -x "${CC_PATH}" ]] && [[ "$("${CC_PATH}" --version 2>/dev/null)" == "cc version 1.7.16" ]]; then
    pass PKG-01 "exact helper is version 1.7.16"
else
    fail PKG-01 "exact helper is version 1.7.16" critical
fi

workspace_help="$("${CC_PATH}" workspace --help 2>/dev/null || true)"
if [[ "${workspace_help}" == *"finish"* && "${workspace_help}" == *"verify"* &&
      "${workspace_help}" == *"plan"* && "${workspace_help}" == *"hold"* ]]; then
    pass PKG-02 "exact helper exposes finish, verify, plan, and hold"
else
    fail PKG-02 "exact helper exposes finish, verify, plan, and hold" critical
fi

# Exercise the helper as an installed executable when authoritative framework
# sources are present. It must classify three routes, apply only the opaque
# safe action, and independently verify Ready.
if [[ -x "${CC_PATH}" && -d "${CLAUDE_ROOT}" && -d "${CODEX_ROOT}" ]]; then
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/ct-walkthrough-acceptance.XXXXXX")"
    mkdir -p "${scratch}/home" "${scratch}/safe" "${scratch}/guided" "${scratch}/owner/.copilot"
    git -C "${scratch}/safe" init -q
    git -C "${scratch}/guided" init -q
    git -C "${scratch}/owner" init -q
    cp "${REPO_ROOT}/README.md" "${scratch}/guided/CLAUDE.md"
    cp "${REPO_ROOT}/README.md" "${scratch}/guided/AGENTS.md"
    printf '%s\n' '{"decision_required":true,"owner":"project-owner"}' > "${scratch}/owner/.copilot/project-owner.json"

    run_cc() {
        env \
            HOME="${scratch}/home" \
            CC_PATHS_CLAUDE_COPILOT_ROOT="${CLAUDE_ROOT}" \
            CC_PATHS_CODEX_COPILOT_ROOT="${CODEX_ROOT}" \
            "${CC_PATH}" "$@"
    }

    run_cc workspace --project "${scratch}/safe" --json > "${scratch}/safe-before.json"
    run_cc workspace plan --project "${scratch}/guided" --json > "${scratch}/guided.json"
    run_cc workspace plan --project "${scratch}/owner" --json > "${scratch}/owner.json"
    action_id="$(
        /usr/bin/python3 -c \
            'import json,sys; p=json.load(open(sys.argv[1])); print((p["workspaces"][0].get("safe_action") or {}).get("id",""))' \
            "${scratch}/safe-before.json"
    )"
    if /usr/bin/python3 - "${scratch}" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
def workspace(name):
    return json.loads((root / name).read_text())["workspaces"][0]
assert workspace("safe-before.json")["classification"] == "safe-finish"
assert workspace("guided.json")["classification"] == "guided-integration"
assert workspace("guided.json")["integration_plan"]["prompt"]["text"]
assert workspace("owner.json")["classification"] == "owner-decision"
assert workspace("owner.json")["integration_plan"]["owner_handoff"]["text"]
PY
    then
        pass CLEAN-01 "clean helper classifies safe, guided, and owner routes"
    else
        fail CLEAN-01 "clean helper classifies safe, guided, and owner routes" critical
    fi

    if [[ -n "${action_id}" ]] &&
       run_cc workspace finish --project "${scratch}/safe" --action-id "${action_id}" --apply --json > "${scratch}/safe-after.json" &&
       run_cc workspace verify --project "${scratch}/safe" --json > "${scratch}/safe-verify.json" &&
       /usr/bin/python3 - "${scratch}" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
for name in ("safe-after.json", "safe-verify.json"):
    payload = json.loads((root / name).read_text())
    assert payload["schema_version"] == "1.1"
    assert payload["workspaces"][0]["classification"] == "ready"
PY
    then
        pass CLEAN-02 "clean safe finish and independent verify return Ready"
    else
        fail CLEAN-02 "clean safe finish and independent verify return Ready" critical
    fi
else
    fail CLEAN-01 "clean helper classifies safe, guided, and owner routes" critical
    fail CLEAN-02 "clean safe finish and independent verify return Ready" critical
fi

total=$((passes + failures))
coverage=$((passes * 10000 / total))
printf 'walkthrough acceptance: %d/%d = %d.%02d%%; critical failures=%d\n' \
    "${passes}" "${total}" "$((coverage / 100))" "$((coverage % 100))" "${critical_failures}"

if (( coverage < 9500 || critical_failures > 0 )); then
    exit 1
fi
