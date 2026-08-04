import Foundation

@main
struct ProjectMigrationContractDriver {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("expected plan and partial-apply fixtures")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let report = try decoder.decode(
            WorkspaceMigrationReport.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )

        precondition(report.schemaVersion == "1.1")
        precondition(report.result == .actionRequired)
        precondition(report.summary.eligible == 1)
        precondition(report.summary.held == 1)
        precondition(report.summary.residualGuidance == 1)
        precondition(report.summary.totalGuided == 3)
        precondition(report.candidates.map(\.state) == [.eligible, .held, .residualGuidance])
        precondition(report.candidates[0].action?.migrationKinds == [.claudeCanonicalEntry, .codexPortableCopy])
        precondition(report.candidates[0].action?.willPreserve.first?.kind == .instruction)
        precondition(report.ledger.isEmpty)
        precondition(report.applySummary == nil)

        let applied = try decoder.decode(
            WorkspaceMigrationReport.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        )
        precondition(applied.result == .partial)
        precondition(applied.ledger.map(\.status) == [.applied, .rolledBack, .unchanged])
        precondition(applied.ledger[1].completedActions.first?.status == .rolledBack)
        precondition(applied.ledger[1].error != nil)
        precondition(applied.applySummary?.applied == 1)
        precondition(applied.applySummary?.failed == 1)
        precondition(applied.applySummary?.remainingGuided == 2)
        precondition(applied.applySummary?.updatedStillGuided == 0)
        precondition(applied.applySummary?.failedStillGuided == 1)
        precondition(applied.applySummary?.detail.hasPrefix("2 projects still need") == true)
        precondition(applied.after?.summary.totalGuided == 2)
        precondition(applied.diagnostics?.state == .available)
        precondition(applied.diagnostics?.path?.hasSuffix("fixture-run.json") == true)

        print("project-migration DTO fixtures: PASS")
    }
}
