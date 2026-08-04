#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WIZARD="${ROOT_DIR}/native/wizard.swift"

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
require_source "Set(report.defaultSelection.map(\\.path))"
require_source "selection.requestSelection"
require_source "reconciliationSelectedProjectPaths.isSubset(of: allowed)"
require_source "Set up and fix all"
require_source "Choose projects individually"
require_source "Every project gets Claude Copilot and Codex Copilot."
reject_source "toggleReconciliationComponent"
reject_source "selectReconciliationRecipe"
reject_source "reconciliationComponentSelection"

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
    "projects-reconciliation-review" \
    "projects-reconciliation-receipt" \
    "projects-reconciliation-recovery"; do
    require_source "${scenario}"
done
require_source "CT_VISUAL_RECONCILIATION_FIXTURES"

echo "reconciliation wizard source contract: PASS"
