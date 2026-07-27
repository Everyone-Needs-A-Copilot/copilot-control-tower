//
// scripts/tests/smoke-cli.sh's scratch driver.
//
// Compiled together with native/cli-client.swift + native/cli-dtos.swift +
// native/render-state.swift + native/models.swift (NOT the tray/wizard/admin
// files — this only exercises the CLI seam, not any AppKit UI) into a
// throwaway binary that runs `CliClient` against `CT_CLI_PATH=<mock-cc>` for
// a spread of the real fixture corpus, printing the derived badge + sentence
// per doctor fixture, then asserting the specific values the Phase F plan
// names. Exits non-zero on any mismatch.
//
// This is a Phase F stand-in for the real `CT_SELFTEST` hook (that lands in
// Phase I) — see the Phase F plan extract's own note on this substitution.

import Foundation

var failureCount = 0

func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String = "") {
    if passed {
        print("ok - \(name)")
    } else {
        failureCount += 1
        print("not ok - \(name)  (\(detail()))")
    }
}

// MARK: - Locate the mock CLI + fixture corpus (passed in by smoke-cli.sh)

guard CommandLine.arguments.count >= 2 else {
    print("usage: smoke-cli-main <path-to-mock-cc>")
    exit(2)
}
let mockCC = CommandLine.arguments[1]
setenv("CT_CLI_PATH", mockCC, 1)

// MARK: - doctor: print badge + sentence for every corpus fixture

let doctorFixtures = [
    "healthy-clean-fleet",
    "it-config-incomplete-org-mdm",
    "needs-attention-codex-dept-fail",
    "offline",
    "setup-needed-first-run",
    "signed-out-claude-personal",
    "syncing-knowledge-org",
    "update-available-cli-foundation",
    "updating-app-self-update",
    "waiting-for-network-startup",
]

func renderDoctor(fixture: String) async -> RenderState {
    setenv("CT_FIXTURE", fixture, 1)
    switch await CliClient.shared.doctor() {
    case .success(let report):
        return RenderState.from(report, joinable: nil)
    case .failure(let error):
        return RenderState.unreadable(error)
    }
}

var rendered: [String: RenderState] = [:]
for fixture in doctorFixtures {
    let state = await renderDoctor(fixture: fixture)
    rendered[fixture] = state
    print("doctor/\(fixture): badge=\(state.header.glyphState) sentence=\"\(state.header.sentence)\"")
}

// MARK: - Assertions (at least the set the Phase F plan names)

if let healthy = rendered["healthy-clean-fleet"] {
    check("healthy-clean-fleet badge is .none", healthy.header.glyphState == .none, "got \(healthy.header.glyphState)")
    check(
        "healthy-clean-fleet sentence is verbatim",
        healthy.header.sentence == "Everything is set up.",
        "got \(healthy.header.sentence)"
    )
} else {
    check("healthy-clean-fleet rendered", false)
}

if let offline = rendered["offline"] {
    check("offline badge is .cloudSlash", offline.header.glyphState == .cloudSlash, "got \(offline.header.glyphState)")
} else {
    check("offline rendered", false)
}

if let signedOut = rendered["signed-out-claude-personal"] {
    check("signed-out-claude-personal badge is .key", signedOut.header.glyphState == .key, "got \(signedOut.header.glyphState)")
} else {
    check("signed-out-claude-personal rendered", false)
}

// MARK: - exit-2: the CLI's own "no trustworthy body" signal

setenv("CT_FIXTURE", "exit-2", 1)
switch await CliClient.shared.doctor() {
case .success:
    check("exit-2 fails to decode as a doctor success", false, "decoded successfully, expected .exit2 failure")
case .failure(let error):
    let isExit2: Bool
    if case .exit2 = error { isExit2 = true } else { isExit2 = false }
    check("exit-2 maps to CliError.exit2", isExit2, "got \(error)")
    let state = RenderState.unreadable(error)
    print("doctor/exit-2: badge=\(state.header.glyphState) sentence=\"\(state.header.sentence)\"")
    check("exit-2 renders .bang", state.header.glyphState == .bang, "got \(state.header.glyphState)")
}

// MARK: - schema-version-above-max: SchemaGate must reject before trusting anything else

setenv("CT_FIXTURE", "schema-version-above-max", 1)
switch await CliClient.shared.doctor() {
case .success:
    check("schema-version-above-max fails to decode", false, "decoded successfully, expected .schemaOutOfRange failure")
case .failure(let error):
    let isSchemaOutOfRange: Bool
    if case .schemaOutOfRange = error { isSchemaOutOfRange = true } else { isSchemaOutOfRange = false }
    check("schema-version-above-max maps to CliError.schemaOutOfRange", isSchemaOutOfRange, "got \(error)")
    let state = RenderState.unreadable(error)
    print("doctor/schema-version-above-max: badge=\(state.header.glyphState) sentence=\"\(state.header.sentence)\"")
    check("schema-version-above-max renders .bang", state.header.glyphState == .bang, "got \(state.header.glyphState)")
}

// MARK: - schema-version-below-min: the same gate, the other direction

setenv("CT_FIXTURE", "schema-version-below-min", 1)
switch await CliClient.shared.doctor() {
case .success:
    check("schema-version-below-min fails to decode", false, "decoded successfully, expected .schemaOutOfRange failure")
case .failure(let error):
    let isSchemaOutOfRange: Bool
    if case .schemaOutOfRange = error { isSchemaOutOfRange = true } else { isSchemaOutOfRange = false }
    check("schema-version-below-min maps to CliError.schemaOutOfRange", isSchemaOutOfRange, "got \(error)")
}

// MARK: - missing security fields fail closed (destructive/severity)

for fixture in ["checker-missing-destructive", "checker-missing-severity"] {
    setenv("CT_FIXTURE", fixture, 1)
    switch await CliClient.shared.doctor() {
    case .success:
        check("\(fixture) fails to decode", false, "decoded successfully, expected .missingSecurityField failure")
    case .failure(let error):
        let isMissingSecurityField: Bool
        if case .missingSecurityField = error { isMissingSecurityField = true } else { isMissingSecurityField = false }
        check("\(fixture) maps to CliError.missingSecurityField", isMissingSecurityField, "got \(error)")
    }
}

// MARK: - layers: decode the list_report corpus cleanly

for fixture in ["available", "joined", "not-entitled", "offline"] {
    setenv("CT_FIXTURE", fixture, 1)
    switch await CliClient.shared.layers() {
    case .success(let report):
        check("layers/\(fixture) decodes", true)
        _ = report
    case .failure(let error):
        check("layers/\(fixture) decodes", false, "got \(error)")
    }
}

// MARK: - auth: initiate, poll, status all decode

switch await CliClient.shared.authLoginInitiate() {
case .success:
    check("auth login initiate decodes", true)
case .failure(let error):
    check("auth login initiate decodes", false, "got \(error)")
}

switch await CliClient.shared.authStatus() {
case .success:
    check("auth status decodes", true)
case .failure(let error):
    check("auth status decodes", false, "got \(error)")
}

switch await CliClient.shared.authGrantInitiate() {
case .success(let grant):
    check(
        "auth grant initiate is least privilege",
        grant.kind == "grant-device-code"
            && grant.permission == "write:public_key"
            && grant.expiresIn == 900
    )
case .failure(let error):
    check("auth grant initiate decodes", false, "got \(error)")
}

switch await CliClient.shared.authGrantPoll(deviceCode: "mock-grant-device-code-0000") {
case .success(let poll):
    check(
        "auth grant poll decodes",
        poll.kind == "grant-poll" && poll.status == .granted
    )
case .failure(let error):
    check("auth grant poll decodes", false, "got \(error)")
}

// MARK: - onboard: plan then apply decode the fail-closed repository contract

switch await CliClient.shared.onboardPlan(components: ["knowledge", "cli", "claude", "codex"]) {
case .success(let report):
    check("onboard plan decodes", report.result == .changesRequired)
    check("onboard plan includes four components", report.repositories.count == 4)
    check("onboard plan reuses existing private Claude repo", report.repositories.first(where: { $0.component == "claude" })?.state == .existingPrivate)
case .failure(let error):
    check("onboard plan decodes", false, "got \(error)")
}

switch await CliClient.shared.onboardApply(components: ["knowledge", "cli", "claude", "codex"]) {
case .success(let report):
    check("onboard apply decodes", report.result == .applied)
    check("onboard apply reports three created", report.summary.created == 3)
case .failure(let error):
    check("onboard apply decodes", false, "got \(error)")
}

switch await CliClient.shared.ecosystemOnboardPlan(products: ["claude", "codex"]) {
case .success(let report):
    check("ecosystem onboard plan decodes", report.result == .changesRequired)
    check("ecosystem onboard plan discovers the organization", report.org == "acme-co")
    check("ecosystem onboard plan carries the complete transaction", report.stages.contains(where: { $0.stage == "device-ssh" }) && report.stages.contains(where: { $0.stage == "codex-plugin" }))
    check("ecosystem onboard plan carries six content-free layers", report.layers.count == 6)
    check("ecosystem layer ranks preserve personal, organization, foundation precedence", Set(report.layers.map(\.rank)) == Set([10, 30, 40]))
    check("ecosystem onboard plan carries adoption inventory", report.inventory?.count == 3)
    check("ecosystem onboard plan identifies reversible manifest repair", report.inventory?.first(where: { $0.id == "layer-manifest" })?.reversible == true)
case .failure(let error):
    check("ecosystem onboard plan decodes", false, "got \(error)")
}

switch await CliClient.shared.ecosystemOnboardApply(products: ["claude", "codex"]) {
case .success(let report):
    check("ecosystem onboard apply decodes", report.result == .ready)
    check("ecosystem onboard apply finishes doctor", report.stages.last?.stage == "doctor")
    check("ecosystem onboard apply includes both products", Set(report.layers.map(\.product)) == Set(["claude", "codex"]))
    check("ecosystem onboard apply carries rollback evidence", report.stages.first(where: { $0.stage == "layer-manifest" })?.rollbackPath != nil)
case .failure(let error):
    check("ecosystem onboard apply decodes", false, "got \(error)")
}

// MARK: - workspace: invisible status then explicit setup apply

switch await CliClient.shared.workspaces() {
case .success(let report):
    check("workspace status decodes", report.result == .actionRequired)
    check("workspace status offers one project", report.summary.setupAvailable == 1)
    check("workspace status recommends both hosts", report.workspaces.first?.recommendedComponents == ["claude", "codex"])
case .failure(let error):
    check("workspace status decodes", false, "got \(error)")
}

switch await CliClient.shared.configureWorkspace(
    path: "/tmp/example-project",
    components: ["claude", "codex"],
    shareWithProject: true,
    apply: true
) {
case .success(let report):
    check("workspace configure decodes", report.result == .applied)
    check("workspace configure requires explicit installed proof", report.workspaces.first?.state == .ready)
case .failure(let error):
    check("workspace configure decodes", false, "got \(error)")
}

switch await CliClient.shared.approveWorkspaceRoot(path: "/tmp/Projects") {
case .success(let report):
    check("workspace root approval decodes", report.result == .applied)
    check("workspace root approval exposes only display name", report.root.name == "Projects")
case .failure(let error):
    check("workspace root approval decodes", false, "got \(error)")
}

// MARK: - projects: freshness --all-projects (all_projects_freshness shape)

setenv("CT_FIXTURE", "mixed-fresh-and-stale", 1)
switch await CliClient.shared.freshnessAllProjects() {
case .success:
    check("freshness --all-projects (mixed-fresh-and-stale) decodes", true)
case .failure(let error):
    check("freshness --all-projects (mixed-fresh-and-stale) decodes", false, "got \(error)")
}

// MARK: - projects: update --fanout (fanout_report shape) — the "12 of 14" line

setenv("CT_FIXTURE", "12-of-14-updated", 1)
switch await CliClient.shared.updateFanout() {
case .success(let report):
    let headline = FanoutRender.headline(report)
    print("fanout/12-of-14-updated headline: \"\(headline)\"")
    check("fanout headline contains \"12\"", headline.contains("12"), "got \"\(headline)\"")
    check("fanout summary.updated == 12", report.summary.updated == 12, "got \(report.summary.updated)")
    let rows = FanoutRender.rows(report)
    check("fanout rows non-empty", !rows.isEmpty, "got \(rows.count) rows")
case .failure(let error):
    check("update --fanout (12-of-14-updated) decodes", false, "got \(error)")
}

// MARK: - Summary

if failureCount == 0 {
    print("smoke-cli: ALL ASSERTIONS PASSED")
    exit(0)
} else {
    print("smoke-cli: \(failureCount) ASSERTION(S) FAILED")
    exit(1)
}
