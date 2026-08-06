import Darwin
import Foundation

@main
struct ReconciliationContractDriver {
    private static func fixture(_ name: String, in directory: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("\(name).json"))
    }

    private static func lines(_ path: String) throws -> [String] {
        try String(contentsOfFile: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func capturedPath(_ phase: String, in directory: String) throws -> String {
        try String(contentsOfFile: "\(directory)/\(phase).request-path", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func assertRequest(
        phase: String,
        captureDirectory: String,
        expected: Data,
        expectedArguments: ([String]) -> Bool
    ) throws {
        let capturedRequest = try Data(contentsOf: URL(fileURLWithPath: "\(captureDirectory)/\(phase).request"))
        precondition(capturedRequest == expected)
        let mode = try String(contentsOfFile: "\(captureDirectory)/\(phase).mode", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(mode == "600")
        let ownerUID = try String(contentsOfFile: "\(captureDirectory)/\(phase).uid", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(ownerUID == String(Darwin.geteuid()))
        let requestPath = try capturedPath(phase, in: captureDirectory)
        let privateParent = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!)
            .appendingPathComponent("Library/Caches/com.everyoneneedsacopilot.controltower/cc-runtime")
            .appendingPathComponent("reconciliation-requests")
            .standardizedFileURL.path
        precondition(URL(fileURLWithPath: requestPath).deletingLastPathComponent().standardizedFileURL.path == privateParent)
        precondition(!FileManager.default.fileExists(atPath: requestPath))
        let capturedArguments = try lines("\(captureDirectory)/\(phase).argv")
        precondition(expectedArguments(capturedArguments))
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("expected mock path, fixture directory, and capture directory")
        }
        let mockPath = CommandLine.arguments[1]
        let fixtureDirectory = CommandLine.arguments[2]
        let captureDirectory = CommandLine.arguments[3]
        setenv("CT_CLI_PATH", mockPath, 1)
        setenv("CT_RECONCILE_FIXTURE_DIR", fixtureDirectory, 1)
        setenv("CT_RECONCILE_CAPTURE_DIR", captureDirectory, 1)
        unsetenv("CT_RECONCILE_RESPONSE")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decodedAssess = try decoder.decode(
            ReconciliationAssessReport.self,
            from: fixture("assess", in: fixtureDirectory)
        )
        precondition(decodedAssess.result == .actionRequired)
        precondition(decodedAssess.projects.first?.route == .safeSetupAvailable)
        precondition(decodedAssess.batchSummary.selected == 1)
        precondition(decodedAssess.defaultSelection.first?.components == [.claude])
        precondition(decodedAssess.defaultSelection.first?.category == .newSetup)
        precondition(decodedAssess.machineSummary.state == .ready)
        precondition(decodedAssess.assistantSelection.isEmpty)
        precondition(decodedAssess.resolutionSummary.totalActionable == 1)
        precondition(decodedAssess.resolutionSummary.managedSeparately == 1)
        precondition(decodedAssess.summary.scopeCounts.productProjects == 1)
        precondition(decodedAssess.summary.scopeCounts.ecosystemRepositories == 1)
        precondition(decodedAssess.projects.last?.route == .ecosystemManaged)
        precondition(decodedAssess.projects.last?.scope.isEcosystemRepository == true)
        var contradictoryScopeObject = try JSONSerialization.jsonObject(
            with: fixture("assess", in: fixtureDirectory)
        ) as! [String: Any]
        var contradictoryProjects = contradictoryScopeObject["projects"]
            as! [[String: Any]]
        contradictoryProjects[0]["scope"] = [
            "kind": "product-project",
            "product": "claude",
        ]
        contradictoryScopeObject["projects"] = contradictoryProjects
        do {
            _ = try decoder.decode(
                ReconciliationAssessReport.self,
                from: JSONSerialization.data(withJSONObject: contradictoryScopeObject)
            )
            preconditionFailure("contradictory repository scope decoded successfully")
        } catch {
            // Product projects cannot smuggle ecosystem provenance past the
            // conditional response contract.
        }
        var assistedObject = try JSONSerialization.jsonObject(
            with: fixture("assess", in: fixtureDirectory)
        ) as! [String: Any]
        assistedObject["assistant_selection"] = [
            [
                "path": "/Projects/Two",
                "components": ["codex"],
                "category": "correction",
            ]
        ]
        assistedObject["resolution_summary"] = [
            "automatic": 1,
            "claude_assisted": 1,
            "total_actionable": 2,
            "managed_separately": 1,
            "left_unchanged": [
                "held": 0,
                "owner_decision": 0,
                "could_not_verify": 0,
                "excluded": 0,
                "source_unavailable": 0,
                "other": 0,
            ],
            "new_setup": 1,
            "correction": 1,
        ]
        let assistedAssess = try decoder.decode(
            ReconciliationAssessReport.self,
            from: JSONSerialization.data(withJSONObject: assistedObject)
        )
        precondition(
            assistedAssess.authorizedSelectionPaths
                == Set(["/Projects/One", "/Projects/Two"])
        )
        precondition(assistedAssess.authoredSelectionCount == 2)
        precondition(
            assistedAssess.requestSelections(
                selectedPaths: assistedAssess.authorizedSelectionPaths
            ).map(\.path) == ["/Projects/One", "/Projects/Two"]
        )
        precondition(
            assistedAssess.assistantSelection.first?.components == [.codex]
        )
        precondition(assistedAssess.resolutionSummary.totalActionable == 2)
        precondition(assistedAssess.resolutionSummary.newSetup == 1)
        precondition(assistedAssess.resolutionSummary.correction == 1)
        let decodedPrepare = try decoder.decode(
            ReconciliationAssistantPrepareReport.self,
            from: fixture("assistant-prepare", in: fixtureDirectory)
        )
        precondition(decodedPrepare.phase == .assistantPrepare)
        precondition(decodedPrepare.selectedProjects == ["/Projects/Team; literal/One"])
        precondition(decodedPrepare.progress.stage == .sessionPrepared)
        precondition(decodedPrepare.progress.liveness == .waiting)
        let decodedRunning = try decoder.decode(
            ReconciliationAssistantStatusReport.self,
            from: fixture("assistant-status-running", in: fixtureDirectory)
        )
        precondition(decodedRunning.result == .running)
        precondition(decodedRunning.proposalId == nil)
        precondition(decodedRunning.progress.stage == .claudeCodeRunning)
        precondition(decodedRunning.progress.liveness == .active)
        let decodedStale = try decoder.decode(
            ReconciliationAssistantStatusReport.self,
            from: fixture("assistant-status-stale", in: fixtureDirectory)
        )
        precondition(decodedStale.progress.liveness == .stale)
        let decodedReady = try decoder.decode(
            ReconciliationAssistantStatusReport.self,
            from: fixture("assistant-status-ready", in: fixtureDirectory)
        )
        precondition(decodedReady.result == .ready)
        precondition(decodedReady.proposalId == "proposal_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        precondition(decodedReady.progress.stage == .ready)
        precondition(decodedReady.progress.liveness == .complete)
        let decodedGuidePrepare = try decoder.decode(
            ReconciliationGuideReport.self,
            from: fixture("guide-prepare", in: fixtureDirectory)
        )
        let decodedGuideRunning = try decoder.decode(
            ReconciliationGuideReport.self,
            from: fixture("guide-status-running", in: fixtureDirectory)
        )
        let decodedGuideAction = try decoder.decode(
            ReconciliationGuideReport.self,
            from: fixture("guide-status-action-required", in: fixtureDirectory)
        )
        let decodedGuideReady = try decoder.decode(
            ReconciliationGuideReport.self,
            from: fixture("guide-status-ready", in: fixtureDirectory)
        )
        precondition(decodedGuidePrepare.phase == .prepare)
        precondition(decodedGuidePrepare.progress.state == .prepared)
        precondition(decodedGuideRunning.progress.verifiedProjectCount == 1)
        precondition(decodedGuideAction.projectStatus.last?.reasons.count == 2)
        precondition(decodedGuideReady.result == .ready)
        precondition(decodedGuideReady.progress.remainingProjectCount == 0)
        let decodedPlan = try decoder.decode(
            ReconciliationPlanReport.self,
            from: fixture("plan", in: fixtureDirectory)
        )
        precondition(decodedPlan.plans.first?.operations.first?.kind == .createFileFromSource)
        let decodedApply = try decoder.decode(
            ReconciliationApplyReport.self,
            from: fixture("apply", in: fixtureDirectory)
        )
        precondition(decodedApply.ledger.first?.status == .incompleteRollback)
        let decodedVerify = try decoder.decode(
            ReconciliationVerifyReport.self,
            from: fixture("verify", in: fixtureDirectory)
        )
        precondition(decodedVerify.result == .blocked)
        let decodedRecover = try decoder.decode(
            ReconciliationRecoverReport.self,
            from: fixture("recover", in: fixtureDirectory)
        )
        precondition(decodedRecover.recoveries.first?.outcome == .rolledBack)

        let request = ReconciliationRequest(
            roots: ["/Projects/Team; literal"],
            projects: [
                ReconciliationProjectSelection(
                    path: "/Projects/Team; literal/One",
                    components: [.claude, .codex],
                    recipeIds: [.claude: "claude-safe-1", .codex: "codex-safe-1"]
                ),
            ]
        )
        let requestBytes = try request.encoded()
        let expectedRequest = Data(#"{"projects":[{"components":["claude","codex"],"path":"\/Projects\/Team; literal\/One","recipe_ids":{"claude":"claude-safe-1","codex":"codex-safe-1"}}],"roots":["\/Projects\/Team; literal"],"schema_version":"1.0"}"#.utf8)
        precondition(requestBytes == expectedRequest)
        precondition(decodedPrepare.matches(request: request))
        precondition(
            decodedRunning.transition(
                expectedSessionId: decodedPrepare.sessionId,
                request: request
            ) == .running
        )
        precondition(
            decodedStale.transition(
                expectedSessionId: decodedPrepare.sessionId,
                request: request
            ) == .running
        )
        precondition(
            decodedReady.transition(
                expectedSessionId: decodedPrepare.sessionId,
                request: request
            ) == .ready(
                proposalId: "proposal_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            )
        )
        precondition(
            decodedReady.transition(
                expectedSessionId: "session_tampered",
                request: request
            ) == .incompatible
        )
        var tamperedStatusObject = try JSONSerialization.jsonObject(
            with: fixture("assistant-status-ready", in: fixtureDirectory)
        ) as! [String: Any]
        tamperedStatusObject["selected_projects"] = ["/Projects/Other"]
        let tamperedStatus = try decoder.decode(
            ReconciliationAssistantStatusReport.self,
            from: JSONSerialization.data(withJSONObject: tamperedStatusObject)
        )
        precondition(
            tamperedStatus.transition(
                expectedSessionId: decodedPrepare.sessionId,
                request: request
            ) == .incompatible
        )
        let proposalRequest = request.attachingAssistantProposal(
            "proposal_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        )
        let proposalRequestBytes = try proposalRequest.encoded()
        let expectedProposalRequest = Data(#"{"assistant_proposal_id":"proposal_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","projects":[{"components":["claude","codex"],"path":"\/Projects\/Team; literal\/One","recipe_ids":{"claude":"claude-safe-1","codex":"codex-safe-1"}}],"roots":["\/Projects\/Team; literal"],"schema_version":"1.0"}"#.utf8)
        precondition(proposalRequestBytes == expectedProposalRequest)

        let guideRequest = ReconciliationRequest(
            roots: ["/Projects"],
            projects: assistedAssess.requestSelections(
                selectedPaths: assistedAssess.authorizedSelectionPaths
            )
        )
        precondition(
            decodedGuidePrepare.matches(request: guideRequest, phase: .prepare)
        )
        precondition(
            decodedGuideReady.matches(request: guideRequest, phase: .status)
        )

        let terminalCommand = ReconciliationGuideTerminalCommand(
            executableURL: URL(fileURLWithPath: "/Applications/Control Tower/cc"),
            assistantExecutableURL: URL(fileURLWithPath: "/Applications/Codex/bin/codex"),
            assistant: "codex",
            assistantDisplayName: "Codex",
            workspaceRoot: "/Projects/Team; literal",
            additionalWorkspaceRoots: ["/Projects/Client sites"],
            instructionsPath: "/Projects/Team; literal/.copilot-control-tower/INSTRUCTIONS.md",
            guideId: "guide_11111111111111111111111111111111"
        )
        precondition(terminalCommand.executableURL.path == "/Applications/Control Tower/cc")
        precondition(terminalCommand.commandLine.contains("guide-start"))
        precondition(terminalCommand.commandLine.contains("guide-finalize"))
        precondition(terminalCommand.commandLine.contains("COPILOT_SETUP_HELPER"))
        precondition(terminalCommand.commandLine.contains("'/Projects/Team; literal'"))
        precondition(terminalCommand.commandLine.contains("--add-dir '/Projects/Client sites'"))
        precondition(terminalCommand.commandLine.contains("$(/bin/cat"))

        let client = CliClient.shared
        switch await client.reconciliationAssess() {
        case .success(.report(let report)):
            precondition(report.phase == .assess)
            precondition(report.result == .actionRequired)
        default:
            fatalError("assess did not preserve its report")
        }


        switch await client.reconciliationAssistantPrepare(request: request) {
        case .success(.report(let report)):
            precondition(report.phase == .assistantPrepare)
            precondition(report.sessionId == "session_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        default:
            fatalError("assistant prepare did not preserve its report")
        }
        try assertRequest(
            phase: "assistant-prepare",
            captureDirectory: captureDirectory,
            expected: requestBytes
        ) { argv in
            argv.count == 5
                && argv[0...2] == ["reconcile", "assistant-prepare", "--request"]
                && argv[4] == "--json"
        }

        setenv("CT_RECONCILE_RESPONSE", "assistant-status-running", 1)
        switch await client.reconciliationAssistantStatus(
            sessionId: "session_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ) {
        case .success(.report(let report)):
            precondition(report.result == .running)
            precondition(report.proposalId == nil)
        default:
            fatalError("assistant running status did not preserve its report")
        }
        setenv("CT_RECONCILE_RESPONSE", "assistant-status-ready", 1)
        switch await client.reconciliationAssistantStatus(
            sessionId: "session_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ) {
        case .success(.report(let report)):
            precondition(report.result == .ready)
            precondition(report.proposalId == "proposal_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        default:
            fatalError("assistant ready status did not preserve its report")
        }
        let assistantStatusArguments = try lines(
            "\(captureDirectory)/assistant-status.argv"
        )
        precondition(
            assistantStatusArguments
                == [
                    "reconcile", "assistant-status", "--session-id",
                    "session_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "--json",
                ]
        )
        unsetenv("CT_RECONCILE_RESPONSE")

        switch await client.reconciliationGuidePrepare(request: guideRequest) {
        case .success(.report(let report)):
            precondition(report.phase == .prepare)
            precondition(report.matches(request: guideRequest, phase: .prepare))
        default:
            fatalError("guide prepare did not preserve its report")
        }
        try assertRequest(
            phase: "guide-prepare",
            captureDirectory: captureDirectory,
            expected: try guideRequest.encoded()
        ) { argv in
            argv.count == 5
                && argv[0...2] == ["reconcile", "guide-prepare", "--request"]
                && argv[4] == "--json"
        }

        setenv("CT_RECONCILE_RESPONSE", "guide-status-running", 1)
        switch await client.reconciliationGuideStatus(
            guideId: "guide_11111111111111111111111111111111"
        ) {
        case .success(.report(let report)):
            precondition(report.phase == .status)
            precondition(report.progress.verifiedProjectCount == 1)
        default:
            fatalError("guide status did not preserve its report")
        }
        setenv("CT_RECONCILE_RESPONSE", "guide-status-action-required", 1)
        switch await client.reconciliationGuideFinalize(
            guideId: "guide_11111111111111111111111111111111"
        ) {
        case .success(.report(let report)):
            precondition(report.result == .actionRequired)
            precondition(report.projectStatus.last?.reasons.count == 2)
        default:
            fatalError("guide final verification did not preserve its report")
        }
        unsetenv("CT_RECONCILE_RESPONSE")

        switch await client.reconciliationPlan(request: proposalRequest) {
        case .success(.report(let report)):
            precondition(report.phase == .plan)
            precondition(report.planId == "plan_22222222222222222222222222222222")
        default:
            fatalError("plan did not preserve its report")
        }
        try assertRequest(phase: "plan", captureDirectory: captureDirectory, expected: proposalRequestBytes) { argv in
            argv.count == 5
                && argv[0...2] == ["reconcile", "plan", "--request"]
                && argv[4] == "--json"
        }

        switch await client.reconciliationApply(
            request: proposalRequest,
            planId: "plan_22222222222222222222222222222222"
        ) {
        case .success(.report(let report)):
            precondition(report.phase == .apply)
            precondition(report.result == .partial)
            precondition(report.ledger.first?.status == .incompleteRollback)
        default:
            fatalError("apply did not preserve its partial report")
        }
        try assertRequest(phase: "apply", captureDirectory: captureDirectory, expected: proposalRequestBytes) { argv in
            argv.count == 7
                && argv[0...2] == ["reconcile", "apply", "--request"]
                && argv[4...6] == ["--plan-id", "plan_22222222222222222222222222222222", "--json"]
        }

        switch await client.reconciliationVerify(request: proposalRequest) {
        case .success(.report(let report)):
            precondition(report.phase == .verify)
            precondition(report.result == .blocked)
        default:
            fatalError("verify did not preserve its blocked report")
        }
        try assertRequest(phase: "verify", captureDirectory: captureDirectory, expected: proposalRequestBytes) { argv in
            argv.count == 5
                && argv[0...2] == ["reconcile", "verify", "--request"]
                && argv[4] == "--json"
        }

        switch await client.reconciliationRecover() {
        case .success(.report(let report)):
            precondition(report.phase == .recover)
            precondition(report.result == .partial)
        default:
            fatalError("recover did not preserve its partial report")
        }

        setenv("CT_RECONCILE_RESPONSE", "error", 1)
        switch await client.reconciliationPlan(request: proposalRequest) {
        case .success(.error(let report)):
            precondition(report.exitCode == 2)
            precondition(report.error.code == "invalid-request")
        default:
            fatalError("structured Python error was not preserved")
        }
        try assertRequest(phase: "plan", captureDirectory: captureDirectory, expected: proposalRequestBytes) { argv in
            argv.count == 5
                && argv[0...2] == ["reconcile", "plan", "--request"]
                && argv[4] == "--json"
        }

        setenv("CT_RECONCILE_RESPONSE", "schema-high", 1)
        switch await client.reconciliationAssess() {
        case .failure(.schemaOutOfRange): break
        default: fatalError("newer schema was not rejected before report decoding")
        }

        setenv("CT_RECONCILE_RESPONSE", "wrong-phase", 1)
        switch await client.reconciliationAssess() {
        case .failure(.parse): break
        default: fatalError("wrong response phase was not rejected")
        }

        setenv("CT_RECONCILE_RESPONSE", "error-mismatch", 1)
        switch await client.reconciliationAssess() {
        case .failure(.parse): break
        default: fatalError("an error body/exit mismatch was not rejected")
        }

        setenv("CT_RECONCILE_RESPONSE", "success-exit-two", 1)
        switch await client.reconciliationAssess() {
        case .failure(.parse): break
        default: fatalError("a success report on exit 2 was not rejected")
        }
        unsetenv("CT_RECONCILE_RESPONSE")

        let assessArguments = try lines("\(captureDirectory)/assess.argv")
        let recoverArguments = try lines("\(captureDirectory)/recover.argv")
        precondition(assessArguments == ["reconcile", "assess", "--json"])
        precondition(recoverArguments == ["reconcile", "recover", "--json"])
        print("reconciliation DTO/client contract: PASS")
    }
}
