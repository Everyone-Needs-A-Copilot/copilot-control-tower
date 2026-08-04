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
        precondition(decodedAssess.defaultSelection.first?.components == [.claude, .codex])
        precondition(decodedAssess.defaultSelection.first?.category == .newSetup)
        precondition(decodedAssess.machineSummary.state == .ready)
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

        let client = CliClient.shared
        switch await client.reconciliationAssess() {
        case .success(.report(let report)):
            precondition(report.phase == .assess)
            precondition(report.result == .actionRequired)
        default:
            fatalError("assess did not preserve its report")
        }

        switch await client.reconciliationPlan(request: request) {
        case .success(.report(let report)):
            precondition(report.phase == .plan)
            precondition(report.planId == "plan_22222222222222222222222222222222")
        default:
            fatalError("plan did not preserve its report")
        }
        try assertRequest(phase: "plan", captureDirectory: captureDirectory, expected: requestBytes) { argv in
            argv.count == 5
                && argv[0...2] == ["reconcile", "plan", "--request"]
                && argv[4] == "--json"
        }

        switch await client.reconciliationApply(
            request: request,
            planId: "plan_22222222222222222222222222222222"
        ) {
        case .success(.report(let report)):
            precondition(report.phase == .apply)
            precondition(report.result == .partial)
            precondition(report.ledger.first?.status == .incompleteRollback)
        default:
            fatalError("apply did not preserve its partial report")
        }
        try assertRequest(phase: "apply", captureDirectory: captureDirectory, expected: requestBytes) { argv in
            argv.count == 7
                && argv[0...2] == ["reconcile", "apply", "--request"]
                && argv[4...6] == ["--plan-id", "plan_22222222222222222222222222222222", "--json"]
        }

        switch await client.reconciliationVerify(request: request) {
        case .success(.report(let report)):
            precondition(report.phase == .verify)
            precondition(report.result == .blocked)
        default:
            fatalError("verify did not preserve its blocked report")
        }
        try assertRequest(phase: "verify", captureDirectory: captureDirectory, expected: requestBytes) { argv in
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
        switch await client.reconciliationPlan(request: request) {
        case .success(.error(let report)):
            precondition(report.exitCode == 2)
            precondition(report.error.code == "invalid-request")
        default:
            fatalError("structured Python error was not preserved")
        }
        try assertRequest(phase: "plan", captureDirectory: captureDirectory, expected: requestBytes) { argv in
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
