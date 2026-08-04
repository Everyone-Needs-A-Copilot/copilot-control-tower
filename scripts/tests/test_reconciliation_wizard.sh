#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WIZARD="${ROOT_DIR}/native/wizard.swift"
CLIENT="${ROOT_DIR}/native/cli-client.swift"
DTOS="${ROOT_DIR}/native/cli-dtos.swift"

require_source() {
    local needle="$1"
    if ! rg -Fq -- "${needle}" "${WIZARD}"; then
        echo "reconciliation wizard: missing source invariant: ${needle}" >&2
        exit 1
    fi
}

reject_source() {
    local needle="$1"
    if rg -Fq -- "${needle}" "${WIZARD}"; then
        echo "reconciliation wizard: retired source remains: ${needle}" >&2
        exit 1
    fi
}

# The old grouped-migration renderer and its app-side cohort arithmetic are
# retired. Reconciliation owns the complete assess/select/plan/apply/verify
# lifecycle now.
reject_source "WorkspaceMigration"
reject_source "workspaceMigrationPlan"
reject_source "applyWorkspaceMigration"
reject_source "projectMigrationReport"

require_source "reconciliationAssess()"
require_source "reconciliationPlan(request: request)"
require_source "reviewedReconciliationRequest = request"
require_source "request: request,"
require_source "planId: plan.planId"
require_source "verifyReconciliation(request: request)"
require_source "reconciliationVerify(request: request)"
require_source "reconciliationRecover()"

# Python authors the complete safe default batch. Swift may only subtract
# projects from it; it never exposes a per-component or recipe choice.
require_source "reconciliationSelectedProjectPaths: Set<String> = []"
require_source "report.authorizedSelectionPaths"
require_source "report.requestSelections("
require_source "reconciliationSelectedProjectPaths.isSubset(of: allowed)"
require_source "Set up and fix all"
require_source "Choose projects individually"
require_source "Every project gets Claude Copilot and Codex Copilot."
require_source "Resolve \\(model.reconciliationSelectedProjectCount)"
require_source "reconciliationAssistantProjectSelectionRow"
reject_source "toggleReconciliationComponent"
reject_source "selectReconciliationRecipe"
reject_source "reconciliationComponentSelection"

# Assistant preparation is a separate bounded seam. Terminal receives exactly
# the located helper and opaque session id; it never receives paths, prompts,
# or proposal content, and the legacy prompt launcher is not used.
for needle in \
    'reconciliationAssistantPrepare(' \
    'ReconciliationAssistantLauncher.open(sessionId: report.sessionId)' \
    'reconciliationAssistantStatus(' \
    '.attachingAssistantProposal(proposalId)' \
    'ReconciliationAssistantTerminalCommand('; do
    require_source "${needle}"
done
if ! rg -Fq -- 'arguments = ["reconcile", "assistant-run", "--session-id", sessionId]' "${CLIENT}"; then
    echo "reconciliation wizard: assistant Terminal argv is not exact" >&2
    exit 1
fi
if rg -n 'ProjectIntegrationLauncher\.open|prompt|projectPath' "${WIZARD}" \
    | rg 'ReconciliationAssistantLauncher|prepareReconciliationAssistant|pollReconciliationAssistant'; then
    echo "reconciliation wizard: assistant preparation leaked into the prompt launcher" >&2
    exit 1
fi
for field in 'assistantSelection' 'resolutionSummary' 'assistantProposalId'; do
    if ! rg -Fq -- "${field}" "${DTOS}"; then
        echo "reconciliation wizard: missing assistant DTO field: ${field}" >&2
        exit 1
    fi
done

# The renderer must use contract-authored counts, explanations, operations,
# outcomes, verification, diagnostics, and next actions.
for field in \
    "summary.projectCounts" \
    "summary.overlapExplanation" \
    "report.batchSummary" \
    "report.machineSummary" \
    "report.defaultSelection" \
    "operation.description" \
    "entry.detail" \
    "entry.verification" \
    "rollback.detail" \
    "diagnostics.detail" \
    "report.nextActions"; do
    require_source "${field}"
done

# Deterministic visual routes use the same decoded schema fixtures as the
# native contract test, without inspecting or changing live projects.
for scenario in \
    "projects-reconciliation-select" \
    "projects-reconciliation-individual" \
    "projects-reconciliation-assistant-select" \
    "projects-reconciliation-assistant-individual" \
    "projects-reconciliation-assistant-preparing" \
    "projects-reconciliation-assistant-running" \
    "projects-reconciliation-assistant-ready" \
    "projects-reconciliation-assistant-permission" \
    "projects-reconciliation-assistant-unavailable" \
    "projects-reconciliation-review" \
    "projects-reconciliation-receipt" \
    "projects-reconciliation-recovery"; do
    require_source "${scenario}"
done
require_source "CT_VISUAL_RECONCILIATION_FIXTURES"

echo "reconciliation wizard source contract: PASS"
