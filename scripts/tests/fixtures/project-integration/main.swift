import Foundation

@main
struct ProjectIntegrationContractDriver {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fputs("usage: driver status-all guided owner\n", stderr)
            exit(2)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        func report(at path: String) throws -> WorkspacesReport {
            try decoder.decode(
                WorkspacesReport.self,
                from: Data(contentsOf: URL(fileURLWithPath: path))
            )
        }

        let all = try report(at: CommandLine.arguments[1])
        let guided = try report(at: CommandLine.arguments[2])
        let owner = try report(at: CommandLine.arguments[3])
        let classes = Set(all.workspaces.map(\.classification.rawValue))
        let expected = Set([
            "ready",
            "safe-finish",
            "guided-integration",
            "owner-decision",
            "could-not-verify",
        ])
        guard all.schemaVersion == "1.1",
              classes == expected,
              all.classificationSummary.total == 5,
              all.classificationSummary.safeFinish == 1,
              all.workspaces.first(where: {
                  $0.classification == .safeFinish
              })?.safeAction?.applyVerb == "finish",
              guided.workspaces.first?.integrationPlan?.prompt?.text.isEmpty == false,
              owner.workspaces.first?.integrationPlan?.ownerHandoff?.text.isEmpty == false,
              owner.workspaces.first?.integrationPlan?.verification.command.prefix(3)
                  == ["cc", "workspace", "verify"] else {
            fputs("project-integration contract assertion failed\n", stderr)
            exit(1)
        }
        print("project-integration DTO contract: pass")
    }
}
