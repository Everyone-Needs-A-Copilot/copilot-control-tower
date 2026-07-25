//
// Copilot Control Tower — Admin mode, part 2.
//
// Continues `native/admin.swift` (read that file's header first): surfaces
// 9-16, the brief writer, the deterministic plan/apply/verify shelling, and
// `AdminWindowController`. Compiles into the same module as every other
// `native/*.swift` file.

import AppKit
import SwiftUI

// MARK: - AdminModel: readable + machine-readable standup briefs

extension AdminModel {
    private func yamlQuote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    // `validDepartments` and `storeKindSlug` are shared, non-private
    // computed properties on `AdminModel` (native/admin.swift), also used by
    // `briefFingerprint` — no local duplicates here.

    /// Builds the exact front-matter + prose shape admin-standup-contract.md
    /// §1.2 specifies. This is legibility/collection only — the engine
    /// (`scripts/admin_bootstrap.sh`, owned elsewhere) is the sole authority
    /// that ever creates anything from it.
    func buildBriefContents() -> String {
        let depts = validDepartments
        var lines: [String] = ["---"]
        lines.append("schema_version: \"1.0\"")
        lines.append("org: \(orgSlug)")
        lines.append("harness:")
        for harness in orderedHarnesses {
            lines.append("  - \(harness.rawValue)")
        }
        lines.append("github_app:")
        lines.append("  client_id: \(yamlQuote(githubOAuthClientID))")
        if depts.isEmpty {
            lines.append("departments: []")
        } else {
            lines.append("departments:")
            for dept in depts { lines.append("  - \(dept.slug)") }
        }
        lines.append("store:")
        switch storeStatus {
        case .connected:
            lines.append("  status: connected")
            lines.append("  type: \(storeKindSlug)")
            lines.append("  endpoint: \(storeAddress)")
            lines.append("  workspace_id: \(yamlQuote(storeWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)))")
            lines.append("  environment: \(storeEnvironment.trimmingCharacters(in: .whitespacesAndNewlines))")
            lines.append("  secret_path: \(yamlQuote(storeSecretPath.trimmingCharacters(in: .whitespacesAndNewlines)))")
            if depts.isEmpty {
                lines.append("  team_scopes: []")
            } else {
                lines.append("  team_scopes:")
                for dept in depts {
                    let scope = storeScopeByDepartment[dept.id] ?? "dept/\(dept.slug)"
                    lines.append("    - { team: \(dept.slug), scope: \(scope) }")
                }
            }
        case .deferred, .undecided:
            lines.append("  status: deferred")
        }
        lines.append("contacts:")
        lines.append("  publisher: \(yamlQuote(contactPublisher))")
        lines.append("  admin: \(yamlQuote(contactAdmin))")
        lines.append("  point_of_contact: \(yamlQuote(contactPointOfContact))")
        lines.append("---")
        lines.append("")
        lines.append("# Standup brief for \(orgSlug)")
        lines.append("")
        lines.append("## What this describes")
        lines.append(describeSummarySentence(depts))
        lines.append("")
        lines.append("## Departments")
        if depts.isEmpty {
            lines.append("None yet.")
        } else {
            for dept in depts { lines.append("- \(dept.name)") }
        }
        lines.append("")
        lines.append("## Shared secret store")
        lines.append(storeProseSentence(depts))
        lines.append("")
        lines.append("## Company GitHub app")
        lines.append("The public OAuth App Client ID is \(githubOAuthClientID). The client secret is never collected or used.")
        lines.append("")
        lines.append("## What this file is")
        lines.append("A plain description Admin uses for its read-only plan, explicit setup action, and Setup check. GitHub is the source of truth.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Machine-readable twin of the human-readable standup brief. The app
    /// passes this to the deterministic engine so the packaged Admin path has
    /// no Python or YAML-parser prerequisite.
    func buildBriefJSONContents() -> String? {
        let depts = validDepartments
        var store: [String: Any] = ["status": storeStatus == .connected ? "connected" : "deferred"]
        if storeStatus == .connected {
            store["type"] = storeKindSlug
            store["endpoint"] = storeAddress
            store["workspace_id"] = storeWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
            store["environment"] = storeEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
            store["secret_path"] = storeSecretPath.trimmingCharacters(in: .whitespacesAndNewlines)
            store["team_scopes"] = depts.map { dept in
                [
                    "team": dept.slug,
                    "scope": storeScopeByDepartment[dept.id] ?? "dept/\(dept.slug)",
                ]
            }
        }
        let payload: [String: Any] = [
            "schema_version": "1.0",
            "org": orgSlug,
            "harness": orderedHarnesses.map(\.rawValue),
            "github_app": ["client_id": githubOAuthClientID],
            "departments": depts.map(\.slug),
            "store": store,
            "contacts": [
                "publisher": contactPublisher,
                "admin": contactAdmin,
                "point_of_contact": contactPointOfContact,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json + "\n"
    }

    private func describeSummarySentence(_ depts: [DepartmentEntry]) -> String {
        let deptPart = depts.isEmpty
            ? "no departments yet"
            : "departments " + depts.map { $0.name }.joined(separator: " and ")
        let storePart = storeStatus == .connected
            ? "Its shared secret store is connected."
            : "Its shared secret store isn't connected yet."
        return "\(orgSlug), using \(selectedHarnessDisplayNames), with \(deptPart). \(storePart) This file carries no secrets and no integrations."
    }

    private func storeProseSentence(_ depts: [DepartmentEntry]) -> String {
        switch storeStatus {
        case .connected:
            let mapping = depts.map { dept -> String in
                let scope = storeScopeByDepartment[dept.id] ?? "dept/\(dept.slug)"
                return "\(dept.name) -> \(scope)"
            }.joined(separator: ", ")
            return "Connected: \(storeKind.rawValue) at \(storeAddress).\(mapping.isEmpty ? "" : " " + mapping + ".")"
        case .deferred, .undecided:
            return "Not connected yet. Connect one before your first shared integration can work."
        }
    }

    /// Writes the operator-readable brief and its machine-readable twin.
    func writeBrief() async {
        briefWriteState = .working
        guard githubOAuthClientIDIsValid, selectedHarnessesAreValid else {
            briefWriteState = .failure
            return
        }
        let contents = buildBriefContents()
        guard let jsonContents = buildBriefJSONContents() else {
            briefWriteState = .failure
            return
        }
        async let markdownWrite = AdminIO.writeFile(contents: contents, to: AdminPaths.briefPath)
        async let jsonWrite = AdminIO.writeFile(contents: jsonContents, to: AdminPaths.briefJSONPath)
        let (wroteMarkdown, wroteJSON) = await (markdownWrite, jsonWrite)
        let wrote = wroteMarkdown && wroteJSON
        briefWriteState = wrote ? .success : .failure
    }

    func loadRepositoryPlan() async {
        repositoryPlanState = .working
        repositoryPlan = nil
        repositorySetupMessage = nil
        guard FileManager.default.fileExists(atPath: AdminPaths.enginePath) else {
            repositoryPlanState = .failure
            repositorySetupMessage = "I can't find the organization setup engine on this Mac, so I won't guess."
            return
        }
        let result = await ShellRunner.run(
            executable: "/bin/bash",
            arguments: [AdminPaths.enginePath, "--plan", "--brief", AdminPaths.briefJSONPath, "--json"],
            timeout: AdminPaths.engineTimeout
        )
        guard !result.timedOut else {
            repositoryPlanState = .failure
            repositorySetupMessage = "GitHub didn't respond in time, so I stopped checking the repository inventory. Nothing was created. Check your connection and try again."
            return
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = result.stdout.data(using: .utf8),
              let plan = try? decoder.decode(AdminRepositoryPlan.self, from: data),
              Self.isSchemaVersionSupported(plan.schemaVersion)
        else {
            repositoryPlanState = .failure
            repositorySetupMessage = "I couldn't read the repository inventory, so I won't create anything. Check GitHub access and try again."
            return
        }
        repositoryPlan = plan
        repositoryPlanState = .success
        if plan.result == .blocked {
            repositorySetupMessage = "One or more repositories are public or unreadable. Nothing will be created until that is resolved."
        }
    }

    /// Rewrites the brief and reloads the repository plan only when
    /// something that feeds the brief actually changed since the last
    /// successful write (`briefFingerprint`) AND a plan has already been
    /// attempted for that unchanged brief. Both conditions must hold to
    /// skip — either one alone is not enough:
    ///   - Fingerprint changed (Back + edit + return): always redo, so
    ///     Review never shows a stale plan/command (QA fix, predates this
    ///     comment).
    ///   - Fingerprint unchanged but no plan attempted yet: this is
    ///     `restoreSavedStateIfAvailable()`'s case (`native/admin.swift`) —
    ///     restoring a saved brief at launch sets `lastWrittenBriefFingerprint`
    ///     directly, without ever calling `writeBrief()`/`loadRepositoryPlan()`.
    ///     Without this second condition, Review's fingerprint guard "matched"
    ///     a plan that was never actually loaded, leaving `repositoryPlanState`
    ///     permanently `.idle` — the real bug this comment fixes (see
    ///     `CT_ADMIN_REVIEW_RESTORE_SELFTEST`). The plan reflects live GitHub
    ///     state and staleness matters, so the honest fix is to actually load
    ///     it here rather than persist a stale one just to dodge the guard.
    func refreshReviewIfNeeded() async {
        let briefUpToDate = lastWrittenBriefFingerprint == briefFingerprint
        let planAttempted = repositoryPlanState != .idle
        guard !(briefUpToDate && planAttempted) else { return }
        await refreshReview()
    }

    func refreshReview() async {
        let fingerprint = briefFingerprint
        await writeBrief()
        if briefWriteState == .success {
            lastWrittenBriefFingerprint = fingerprint
            await loadRepositoryPlan()
        }
    }
}

// MARK: - Admin's own repository-plan shape (`admin_bootstrap.sh --plan
// --json`) — deliberately NOT `OnboardReport`/`RepositoryPlanRow`
// (`native/cli-dtos.swift`), even though both describe
// "component/role/owner/name/state/action/detail" rows. Those types are
// `cc onboard --scope personal --json`'s contract: its rows additionally
// carry `rank`/`package_state`/`package_action`/`package_detail`, fields
// required (non-optional) on `RepositoryPlanRow` by design (see that type's
// own doc comment and `CT_ONBOARD_QUESTION_SELFTEST`). `admin_bootstrap.sh`'s
// `run_repository_plan()` has never emitted those — it is a different
// producer with a different, simpler schema. Reusing `OnboardReport` here
// used to make Swift's synthesized `Decodable` throw on every real plan load
// (a missing required key), independent of and in addition to the
// fingerprint-guard bug above; this dedicated type matches
// `admin_bootstrap.sh`'s actual output, no more and no less.
struct AdminRepositoryPlanRow: Decodable {
    let component: String
    let role: String
    let unit: String?
    let owner: String
    let name: String
    let visibility: String?
    let state: RepositoryState
    let action: String
    let detail: String
}

struct AdminRepositoryPlan: Decodable {
    let schemaVersion: String
    let scope: String
    let owner: String
    let mode: String
    let result: OnboardResult
    let repositories: [AdminRepositoryPlanRow]
    // `admin_bootstrap.sh` never emits `summary.adoptable` (that is `cc
    // onboard`-only); `RepositoryPlanSummary.adoptable` is already optional,
    // so reusing that summary shape here is a real, not coincidental, fit.
    let summary: RepositoryPlanSummary
}

// MARK: - Progress and waiting: the mutating organization run
//
// docs/40-initiatives/02-enac-self-onboarding/walkthroughs/progress-and-waiting-spec.md,
// pattern P1 "filling checklist". Replaces the boolean-shaped
// `repositoryApplyState: WriteState` this run used to report through — a
// plain `.working` a re-run could get stuck in forever, since a boolean
// can't say "started but silent" — with a phase that carries real
// timestamps and can only ever animate a NAMED row (spec §2, "The rule that
// makes never-started unmistakable").
//
// Every fact below is parsed straight off `scripts/admin_bootstrap.sh`'s
// own NDJSON step lines (`{"step","result","detail"}`, one per completed
// step, vocabulary frozen at admin-standup-contract.md:542-556) or off the
// plan the administrator already approved (`AdminRepositoryPlan`, above) —
// CLAUDE.md invariant #1, parse never compute. The one thing this file
// computes on its own is which row `buildApplyRunRows()` built is *next*:
// that list is ordered to match `run_standup()`'s own frozen execution
// order (default access, then every organization space, then each
// department's spaces and team in turn, then the setup file), so "the
// first row nobody has heard about yet" is a fact about static code
// structure already true before the run starts, never a guess about live
// GitHub state.

/// Named subject of live run progress. There is no path to constructing an
/// unnamed one — every initializer call in this file supplies a real
/// `rowID`/`title` pulled off an actual `RunRow`.
struct RunSubject: Equatable {
    let rowID: String
    let title: String
}

/// One row's accumulated engine result. "Worse always wins": a space that
/// was created and then failed branch protection reads as unfinished,
/// never as done (spec §4, "Counting rules").
enum RunRowResult: Equatable {
    case done(detail: String)
    case failed(detail: String)
    case refused(detail: String)

    var severity: Int {
        switch self {
        case .done: return 0
        case .failed, .refused: return 1
        }
    }

    /// `engineResult` is `admin_bootstrap.sh`'s frozen `result` vocabulary
    /// (admin-standup-contract.md:542-556: created|already-present|updated|
    /// skipped|refused|failed). Anything outside it is a result this app
    /// has never seen the engine emit — fail closed to "couldn't finish"
    /// rather than silently rendering an unrecognized value green.
    static func from(engineResult: String, detail: String) -> RunRowResult {
        switch engineResult {
        case "created", "already-present", "updated", "skipped":
            return .done(detail: detail)
        case "refused":
            return .refused(detail: detail)
        default:
            return .failed(detail: detail.isEmpty
                ? "Setup reported a result I don't recognize, so I'm treating it as unfinished."
                : detail)
        }
    }
}

/// One row of the run's checklist: one space, one department team, the
/// organization's default access, or the setup file (spec §4, "The list,
/// and where its number comes from").
struct RunRow: Identifiable, Equatable {
    let id: String
    let title: String
    /// The GitHub-facing name, shown only as small secondary evidence —
    /// never the label a person is asked to recognise (spec §3, "How a
    /// space is named").
    var evidence: String?
    var result: RunRowResult?

    /// "A worse result always wins over a better one" (spec §4).
    mutating func absorb(_ incoming: RunRowResult) {
        guard let existing = result else { result = incoming; return }
        if incoming.severity >= existing.severity { result = incoming }
    }
}

/// `notStarted`, `alive`, `stalled`, `ended` — spec §2's four-case phase.
/// `alive`'s `subject` is `nil` only during the read-only preamble
/// (`readiness`/`brief`/`validate-slug`/`repository-plan` lines, before any
/// row has a name yet); the moment a real per-row line lands, `subject`
/// names it. `RunWorkingIndicator` (below) is the one view that draws the
/// animated indicator, and it takes a non-optional `RunSubject`, so a call
/// site can only reach it by first unwrapping a real one.
enum RunPhase: Equatable {
    case notStarted
    case alive(startedAt: Date, lastLineAt: Date, subject: RunSubject?)
    case stalled(lastSubject: RunSubject?)
    case ended(RunOutcome)
}

enum RunOutcome: Equatable {
    case allDone
    case unfinished(count: Int)
    /// The engine refused before changing anything else (`refuse()`,
    /// exit 2). `instruction` is its own stderr sentence, shown verbatim.
    case refused(instruction: String)
    /// `ShellRunner`'s hard bound (`AdminPaths.engineTimeout`) killed the
    /// child — a distinct, honest outcome from a real engine result.
    case timedOut
}

/// Pure step-id parsing (`admin_bootstrap.sh`'s frozen step-id vocabulary —
/// spec §4's "How the engine's lines land on rows" table). No knowledge of
/// ordering lives here, only which row, if any, a step name points at.
enum ApplyStepTarget: Equatable {
    case preamble
    case defaultAccess
    case setupFile
    case repository(name: String)
    case departmentTeam(unit: String)

    static func parse(_ step: String) -> ApplyStepTarget {
        if step == "org-base-permission" { return .defaultAccess }
        if step == "ecosystem-yml" || step == "leak-scan" { return .setupFile }
        if let repo = suffix(of: step, after: "org-repo:") { return .repository(name: repo) }
        if let repo = suffix(of: step, after: "branch-protection:") { return .repository(name: repo) }
        if let repo = suffix(of: step, after: "layer-package:") { return .repository(name: repo) }
        if let rest = suffix(of: step, after: "dept-repo:"), let (_, repo) = splitOnce(rest) {
            return .repository(name: repo)
        }
        if let rest = suffix(of: step, after: "dept-grant:"), let (unit, _) = splitOnce(rest) {
            return .departmentTeam(unit: unit)
        }
        if let unit = suffix(of: step, after: "dept-team:") { return .departmentTeam(unit: unit) }
        // The frozen preamble steps (readiness/brief/validate-slug/
        // repository-plan), and any step id this build has never seen,
        // name no row — never guess one.
        return .preamble
    }

    var rowID: String? {
        switch self {
        case .preamble: return nil
        case .defaultAccess: return "default-access"
        case .setupFile: return "setup-file"
        case .repository(let name): return name
        case .departmentTeam(let unit): return "team:\(unit)"
        }
    }

    private static func suffix(of value: String, after prefix: String) -> String? {
        guard value.hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count))
    }

    private static func splitOnce(_ value: String) -> (String, String)? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let head = String(value[value.startIndex..<colon])
        let tail = String(value[value.index(after: colon)...])
        guard !head.isEmpty, !tail.isEmpty else { return nil }
        return (head, tail)
    }
}

/// One `{"step","result","detail"}` line off `admin_bootstrap.sh`'s stdout.
private struct AdminStepLine: Decodable {
    let step: String
    let result: String
    let detail: String
}

/// Turns the plan's already-known `component`/`unit` fields — or, for a
/// step the plan never listed, the same naming convention parsed back out
/// of the repo name the engine reported — into the friendly title spec §3
/// specifies ("How a space is named"). `@MainActor` only because it calls
/// `AdminModel.departmentDisplayName(forSlug:knownDepartments:)`, itself
/// actor-isolated only because it lives on `AdminModel`; every real call
/// site here is already on the main actor (`AdminModel`'s own methods).
@MainActor
enum RunRowNaming {
    static func componentTitle(_ component: String) -> String {
        switch component {
        case "knowledge": return "Knowledge Copilot"
        case "cli": return "CLI Copilot"
        case "claude": return "Claude Copilot"
        case "codex": return "Codex Copilot"
        default:
            guard let first = component.first else { return "This space" }
            return "\(first.uppercased())\(component.dropFirst()) Copilot"
        }
    }

    /// Parses `<component>-copilot-<unit>` / `<component>-copilot-internal`
    /// back into its parts — the same convention
    /// `admin_bootstrap.sh`'s `_org_triplet_repos`/`_dept_triplet_repos`
    /// generate names with, read in reverse. Parsing, not computing.
    static func componentAndUnit(fromRepoName repoName: String) -> (component: String, unit: String?) {
        guard let range = repoName.range(of: "-copilot-") else { return (repoName, nil) }
        let component = String(repoName[repoName.startIndex..<range.lowerBound])
        let rest = String(repoName[range.upperBound...])
        return (component, rest == "internal" ? nil : rest)
    }

    static func repositoryTitle(component: String, unit: String?, departments: [DepartmentEntry]) -> String {
        let title = componentTitle(component)
        guard let unit, !unit.isEmpty else { return "\(title), for your whole organization" }
        return "\(title), for \(AdminModel.departmentDisplayName(forSlug: unit, knownDepartments: departments))"
    }

    static func teamTitle(unit: String, departments: [DepartmentEntry]) -> String {
        let name = AdminModel.departmentDisplayName(forSlug: unit, knownDepartments: departments)
        return "The \(name) team, so \(name) can reach its spaces"
    }
}

extension AdminModel {
    /// Builds the run's checklist in the SAME order `run_standup()` first
    /// touches each row (see this section's header comment) — the default
    /// access row, then every organization space, then each department's
    /// spaces and team in turn, then the setup file.
    func buildApplyRunRows() -> [RunRow] {
        guard let plan = repositoryPlan else { return [] }
        var rows: [RunRow] = [
            RunRow(id: "default-access", title: "Your organization's default access", evidence: orgSlug.isEmpty ? nil : orgSlug),
        ]
        let orgRows = plan.repositories.filter { $0.unit == nil }
        rows.append(contentsOf: orgRows.map(runRow(fromPlanRow:)))
        for dept in validDepartments {
            let deptRows = plan.repositories.filter { $0.unit == dept.slug }
            rows.append(contentsOf: deptRows.map(runRow(fromPlanRow:)))
            rows.append(RunRow(
                id: "team:\(dept.slug)",
                title: RunRowNaming.teamTitle(unit: dept.slug, departments: departments),
                evidence: dept.slug
            ))
        }
        rows.append(RunRow(id: "setup-file", title: "Your organization's setup file", evidence: "ecosystem.yml"))
        return rows
    }

    private func runRow(fromPlanRow planRow: AdminRepositoryPlanRow) -> RunRow {
        RunRow(
            id: planRow.name,
            title: RunRowNaming.repositoryTitle(component: planRow.component, unit: planRow.unit, departments: departments),
            evidence: "\(planRow.owner)/\(planRow.name)"
        )
    }

    /// Freezes which rows came from the approved plan, so a later line
    /// naming something outside it can be told apart (`applyExtraRowCount`)
    /// without recomputing the plan.
    func seedApplyKnownRows() {
        applyKnownRowIDs = Set(applyRunRows.map(\.id))
    }

    /// The next row this run hasn't heard about yet, in checklist order —
    /// the only "current" this file ever asserts, and only because
    /// `buildApplyRunRows()` mirrors the engine's own frozen execution
    /// order 1:1 (see this section's header comment).
    func currentRunSubject() -> RunSubject? {
        applyRunRows.first(where: { $0.result == nil }).map { RunSubject(rowID: $0.id, title: $0.title) }
    }

    var applyDoneCount: Int {
        applyRunRows.filter {
            if case .done = $0.result { return true }
            return false
        }.count
    }

    var applyExtraRowCount: Int {
        applyRunRows.filter { !applyKnownRowIDs.contains($0.id) }.count
    }

    var applyIsRunning: Bool {
        switch applyRunPhase {
        case .alive, .stalled: return true
        case .notStarted, .ended: return false
        }
    }

    /// The repository names the plan WILL check, computed the same way
    /// `admin_bootstrap.sh`'s naming convention does (`<component>-copilot-
    /// internal` / `<component>-copilot-<unit>`) — known from what's
    /// already been typed in Describe, before GitHub has answered anything.
    /// Used only to preview the inventory card's row list and count while
    /// its real check is still in flight (P2's "every row Not checked
    /// yet"); never a stand-in for the real, GitHub-confirmed plan.
    var plannedRepositoryPreview: [String] {
        var names = selectedComponentRepoTokens.map { "\($0)-copilot-internal" }
        for dept in validDepartments {
            names.append(contentsOf: selectedComponentRepoTokens.map { "\($0)-copilot-\(dept.slug)" })
        }
        return names
    }

    /// Feeds one raw stdout line from the engine — parsing only, real-time
    /// or replayed (the selftest drives this directly with fabricated
    /// lines, out of order, exactly as a real chatty run could deliver
    /// them). Ignores anything that doesn't decode as
    /// `{"step","result","detail"}`; a malformed line is never grounds to
    /// invent a row.
    func handleApplyStepLine(_ raw: String) {
        let decoder = JSONDecoder()
        guard let data = raw.data(using: .utf8),
              let line = try? decoder.decode(AdminStepLine.self, from: data)
        else { return }

        let now = Date()
        let target = ApplyStepTarget.parse(line.step)
        guard let rowID = target.rowID else {
            touchApplyPhase(now: now)
            return
        }

        if let index = applyRunRows.firstIndex(where: { $0.id == rowID }) {
            applyRunRows[index].absorb(.from(engineResult: line.result, detail: line.detail))
        } else {
            var row = unplannedRow(for: target, rowID: rowID)
            row.absorb(.from(engineResult: line.result, detail: line.detail))
            applyRunRows.append(row)
        }
        touchApplyPhase(now: now)
    }

    /// Built on demand for a step naming something the approved plan never
    /// listed (spec §4, "Counting rules": "a line naming something not in
    /// the approved plan appends a row and adds one"). `.defaultAccess`/
    /// `.setupFile` are unreachable here — those two row ids are always
    /// pre-seeded by `buildApplyRunRows()`.
    private func unplannedRow(for target: ApplyStepTarget, rowID: String) -> RunRow {
        switch target {
        case .repository(let name):
            let (component, unit) = RunRowNaming.componentAndUnit(fromRepoName: name)
            return RunRow(id: rowID, title: RunRowNaming.repositoryTitle(component: component, unit: unit, departments: departments), evidence: name)
        case .departmentTeam(let unit):
            return RunRow(id: rowID, title: RunRowNaming.teamTitle(unit: unit, departments: departments), evidence: unit)
        case .defaultAccess, .setupFile, .preamble:
            return RunRow(id: rowID, title: rowID, evidence: nil)
        }
    }

    private func touchApplyPhase(now: Date) {
        let subject = currentRunSubject()
        switch applyRunPhase {
        case .notStarted, .stalled:
            applyRunPhase = .alive(startedAt: now, lastLineAt: now, subject: subject)
        case .alive(let startedAt, _, _):
            applyRunPhase = .alive(startedAt: startedAt, lastLineAt: now, subject: subject)
        case .ended:
            break // a line after the run ended is not expected; never reopen a finished run
        }
    }

    /// The row keeps its indicator but gains "Still working on this one" —
    /// still `alive`, not yet `stalled` (spec §3, "Working, silent a
    /// while").
    static let applySlowThreshold: TimeInterval = 8
    /// Past this much silence, the run leaves `alive` for `stalled` (spec
    /// §2's watchdog) — well under `AdminPaths.engineTimeout`, so the UI
    /// can say so before the OS-level bound would kill the child.
    static let applyStallThreshold: TimeInterval = 45

    /// Pure — takes `now` as an argument rather than reading `Date()`
    /// itself, so the selftest can fire the watchdog deterministically
    /// instead of waiting `applyStallThreshold` real seconds. This is the
    /// ONE thing a clock is allowed to decide in this file: whether a real,
    /// already-recorded `lastLineAt` is old enough to call silence — never
    /// a new step name, a new count, or a position (contrast the retired
    /// `wizard.swift` `cyclePhases`, which slept to invent "Part N of M"
    /// with no real signal behind it at all).
    static func applyPhaseAfterSilence(_ phase: RunPhase, now: Date, stallThreshold: TimeInterval) -> RunPhase {
        guard case .alive(_, let lastLineAt, let subject) = phase else { return phase }
        guard now.timeIntervalSince(lastLineAt) >= stallThreshold else { return phase }
        return .stalled(lastSubject: subject)
    }

    func armApplyWatchdog() {
        applyWatchdogTask?.cancel()
        applyWatchdogTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.applyRunPhase = Self.applyPhaseAfterSilence(self.applyRunPhase, now: Date(), stallThreshold: Self.applyStallThreshold)
            }
        }
    }

    func disarmApplyWatchdog() {
        applyWatchdogTask?.cancel()
        applyWatchdogTask = nil
    }

    /// "Keep waiting" — nothing was cancelled or resumed (the real process
    /// never paused; the engine is additive and safe to run again either
    /// way). This only resets the UI's own silence window, so a still-live
    /// process gets a fresh `applyStallThreshold` before the card returns.
    func keepWaitingOnApplyRun() {
        guard case .stalled(let lastSubject) = applyRunPhase else { return }
        let now = Date()
        applyRunPhase = .alive(startedAt: now, lastLineAt: now, subject: lastSubject)
    }

    /// Surface 8's "Set up organization" — the real, additive engine call,
    /// streamed line by line onto `applyRunRows`/`applyRunPhase`. Never
    /// reads `repositoryApplyState`-style booleans; the whole run lives in
    /// `RunPhase`.
    func applyRepositoryPlan() async {
        guard repositoryPlan?.result != .blocked else { return }
        applyRunRows = buildApplyRunRows()
        seedApplyKnownRows()
        repositorySetupMessage = nil
        let now = Date()
        applyRunPhase = .alive(startedAt: now, lastLineAt: now, subject: nil)
        armApplyWatchdog()

        // The engine repeats its complete fail-closed repository preflight
        // before any mutation; this is the explicit application
        // confirmation the administrator approved in Review.
        let result = await ShellRunner.run(
            executable: "/bin/bash",
            arguments: [AdminPaths.enginePath, "--brief", AdminPaths.briefJSONPath],
            timeout: AdminPaths.engineTimeout,
            onStdoutLine: { [weak self] line in
                Task { @MainActor in
                    self?.handleApplyStepLine(line)
                }
            }
        )
        disarmApplyWatchdog()

        guard !result.timedOut else {
            applyRunPhase = .ended(.timedOut)
            repositorySetupMessage = "GitHub didn't respond in time, so setup stopped safely. Existing repositories were not overwritten. Check your connection and try again."
            return
        }

        if result.exitCode == 2 {
            let instruction = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            applyRunPhase = .ended(.refused(instruction: instruction.isEmpty
                ? "Setup stopped on purpose before changing anything else."
                : instruction))
            await loadRepositoryPlan()
            return
        }

        let unfinishedCount = applyRunRows.filter {
            if case .done = $0.result { return false }
            return true
        }.count

        if result.exitCode == 0, unfinishedCount == 0 {
            applyRunPhase = .ended(.allDone)
            repositorySetupMessage = "Organization repositories are in place. Existing private repositories were reused and confirmed-missing repositories were created private."
            await loadRepositoryPlan()
        } else {
            applyRunPhase = .ended(.unfinished(count: unfinishedCount))
            await loadRepositoryPlan()
            repositorySetupMessage = "Organization setup stopped safely. Existing repositories were not overwritten. Resolve the reported GitHub issue, then try again."
        }
    }

    /// Review's primary button — runs the engine, then advances to the
    /// handed-off surface only when the run actually ended with every row
    /// done. Anything else (unfinished, refused, timed out) keeps the
    /// administrator on Review, looking at `RunChecklistView`'s own
    /// summary and recovery actions.
    func runApplyAndAdvanceIfDone() async {
        await applyRepositoryPlan()
        if case .ended(.allDone) = applyRunPhase {
            advance(from: .review)
        }
    }
}

// MARK: - Progress and waiting: shared rendering (the mutating run, and the
// P2/P4 "no answer" tier both Review cards and the Setup check gain below)

/// The ONE place this app constructs an animated, indeterminate
/// `ProgressView` for a run/wait surface. Requiring a real `RunSubject`
/// (never optional, never a plain `Bool`) as its only argument means a
/// caller can only reach this by first proving it has a named thing to
/// attach it to — there is no path from `RunPhase.notStarted`, or from an
/// operation that hasn't started, to this initializer (spec §2, "The
/// animated indicator is only reachable from alive"; §1's "a bare spinner
/// with no named subject is never correct anywhere in this product").
struct RunWorkingIndicator: View {
    let subject: RunSubject

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Working on it now")
    }
}

/// Real elapsed time since a real start signal — never a source of a new
/// fact, only a threshold check used to pick between two already-written
/// sentences for a call that is honestly still running long (P0→P4's
/// settle delay, P2/P4's "no answer" tier). `snooze` only defers the next
/// check (used by a card's own "Keep waiting"); it never resets `startedAt`,
/// so the real elapsed time a screen reader's queryable value would report
/// is never lied about.
struct SlowCallWatcher {
    private(set) var startedAt: Date?
    private var snoozedUntil: Date?

    mutating func arm() {
        startedAt = Date()
        snoozedUntil = nil
    }

    mutating func reset() {
        startedAt = nil
        snoozedUntil = nil
    }

    mutating func snooze(for interval: TimeInterval) {
        snoozedUntil = Date().addingTimeInterval(interval)
    }

    func isPast(_ delay: TimeInterval, now: Date) -> Bool {
        guard let startedAt else { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        return now.timeIntervalSince(startedAt) >= delay
    }
}

enum WaitClock {
    /// P0's "the result, nothing else" window before a fast local write is
    /// allowed to become visible as a P4 named wait.
    static let settleDelay: TimeInterval = 0.4
    /// Past this much real elapsed time, a P2/P4 wait's copy switches to
    /// its honest "no answer yet" tier.
    static let noAnswerDelay: TimeInterval = 20
}

/// View-facing row state — computed fresh from `RunRow.result` plus the
/// run's own `RunPhase`, never stored on the row itself (spec §2, "A row's
/// state is computed from the run, not stored on the row"). Six named
/// shapes, eight cases (`workingSlow` and `neverReported` refine `working`/
/// `notStarted` with their own copy, per spec §3's row-state table).
enum RunRowDisplay: Equatable {
    case notStarted
    case working
    case workingSlow
    case done(detail: String)
    case failed(detail: String)
    case refused(detail: String)
    case noAnswer
    case neverReported
}

/// The running/ended state of Review's "Set up organization" (P1, filling
/// checklist — spec §4). Every row, count, and result rendered here comes
/// from `AdminModel.applyRunRows`/`applyRunPhase`, themselves built only
/// from the engine's own NDJSON lines and the approved plan; this view
/// never invents a name, a position, or a duration of its own. The
/// 1-second timer below is a redraw PULSE only — it recomputes how long
/// it's been since the last REAL line arrived (`RunPhase.alive`'s own
/// `lastLineAt`), never advances a count or fabricates a step name
/// (contrast `wizard.swift`'s retired `cyclePhases`, which slept to invent
/// "Part N of M" with nothing real behind it).
struct RunChecklistView: View {
    @ObservedObject var model: AdminModel
    @State private var now = Date()
    @State private var showDone = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            countLine
            if model.applyRunRows.count > 7, isCountedPhase {
                ProgressView(value: Double(model.applyDoneCount), total: Double(max(model.applyRunRows.count, 1)))
                    .accessibilityHidden(true)
            }
            if case .stalled = model.applyRunPhase {
                stallCard
            }
            rowList
            if model.applyExtraRowCount > 0 {
                Text(model.applyExtraRowCount == 1
                    ? "Setup also handled 1 thing that wasn't in your plan. That's fine."
                    : "Setup also handled \(model.applyExtraRowCount) things that weren't in your plan. That's fine.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            if let outcomeLine {
                Text(outcomeLine)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(outcomeIsFailure ? Color(nsColor: .systemRed) : Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onReceive(ticker) { now = $0 }
        .accessibilityElement(children: .contain)
    }

    private var isCountedPhase: Bool {
        switch model.applyRunPhase {
        case .alive, .stalled: return true
        case .notStarted, .ended: return false
        }
    }

    @ViewBuilder
    private var countLine: some View {
        if isCountedPhase, model.applyRunRows.count >= 2 {
            Text("\(model.applyDoneCount) of \(model.applyRunRows.count) done.")
                .font(.callout.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Setting up your organization")
                .accessibilityValue("\(model.applyDoneCount) of \(model.applyRunRows.count) done")
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var stallCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(nsColor: .systemOrange))
                        .accessibilityHidden(true)
                    Text("No answer yet.")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                }
                Text("Setup hasn't reported anything for a while. Nothing has been undone, and nothing is lost.")
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Keep waiting") { model.keepWaitingOnApplyRun() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button("See what's really on GitHub") {
                        model.selection = .onboarding(.setupCheck)
                        model.runSetupCheck()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var firstUnresolvedIndex: Int? {
        model.applyRunRows.firstIndex(where: { $0.result == nil })
    }

    /// The most recently finished row stays visible in full — evidence of
    /// forward motion — even while every other finished row collapses
    /// (spec §4, "Long steps, and what stays on screen"). Only applies
    /// while the run is still counted; once it's ended, every success is
    /// eligible for the roll-up.
    private var pinnedRecentIndex: Int? {
        guard isCountedPhase, let boundary = firstUnresolvedIndex, boundary > 0 else { return nil }
        return boundary - 1
    }

    private func isCollapsible(_ row: RunRow, at index: Int) -> Bool {
        guard !showDone, case .done = row.result else { return false }
        return index != pinnedRecentIndex
    }

    private var collapsedDoneCount: Int {
        guard !showDone else { return 0 }
        return model.applyRunRows.enumerated().filter { index, row in
            guard case .done = row.result else { return false }
            return index != pinnedRecentIndex
        }.count
    }

    private var rowList: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.applyRunRows.enumerated()), id: \.element.id) { index, row in
                    if !isCollapsible(row, at: index) {
                        runRowView(row)
                        if index < model.applyRunRows.count - 1 { Divider() }
                    }
                }
                if collapsedDoneCount > 0 {
                    Button(showDone
                        ? "Hide what's done"
                        : (collapsedDoneCount == 1 ? "Show what's done (1 done.)" : "Show what's done (\(collapsedDoneCount) done.)")
                    ) {
                        showDone.toggle()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .controlAccentColor))
                    .padding(.top, 8)
                }
            }
        }
    }

    private func rowDisplayState(_ row: RunRow) -> RunRowDisplay {
        if let result = row.result {
            switch result {
            case .done(let detail): return .done(detail: detail)
            case .failed(let detail): return .failed(detail: detail)
            case .refused(let detail): return .refused(detail: detail)
            }
        }
        switch model.applyRunPhase {
        case .notStarted:
            return .notStarted
        case .alive(_, let lastLineAt, let subject):
            guard subject?.rowID == row.id else { return .notStarted }
            return now.timeIntervalSince(lastLineAt) >= AdminModel.applySlowThreshold ? .workingSlow : .working
        case .stalled(let lastSubject):
            return lastSubject?.rowID == row.id ? .noAnswer : .notStarted
        case .ended:
            return .neverReported
        }
    }

    private func runRowView(_ row: RunRow) -> some View {
        let state = rowDisplayState(row)
        return HStack(alignment: .top, spacing: 10) {
            rowGlyph(state, row: row)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                if let evidence = row.evidence, !evidence.isEmpty {
                    Text(evidence)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
                Text(rowLine(state))
                    .font(.caption)
                    .foregroundColor(rowTextColor(state))
                    .fixedSize(horizontal: false, vertical: true)
                if case .workingSlow = state {
                    Text("Still working on this one. GitHub can be slow to answer.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.15), value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(rowAccessibilityWord(state))\(rowAccessibilityDetail(state))")
    }

    @ViewBuilder
    private func rowGlyph(_ state: RunRowDisplay, row: RunRow) -> some View {
        switch state {
        case .notStarted:
            Image(systemName: "circle").foregroundColor(Color(nsColor: .tertiaryLabelColor)).accessibilityHidden(true)
        case .working, .workingSlow:
            RunWorkingIndicator(subject: RunSubject(rowID: row.id, title: row.title))
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundColor(Color(nsColor: .systemGreen)).accessibilityHidden(true)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(Color(nsColor: .systemRed)).accessibilityHidden(true)
        case .refused:
            Image(systemName: "hand.raised.circle.fill").foregroundColor(Color(nsColor: .systemRed)).accessibilityHidden(true)
        case .noAnswer:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Color(nsColor: .systemOrange)).accessibilityHidden(true)
        case .neverReported:
            Image(systemName: "questionmark.circle").foregroundColor(Color(nsColor: .secondaryLabelColor)).accessibilityHidden(true)
        }
    }

    private func rowLine(_ state: RunRowDisplay) -> String {
        switch state {
        case .notStarted: return "Not started yet."
        case .working, .workingSlow: return "Working on it now."
        case .done(let detail): return detail
        case .failed(let detail): return "Couldn't finish this one. Everything before it is still in place. \(detail)"
        case .refused(let detail): return "Setup stopped here on purpose. Nothing after this was changed. \(detail)"
        case .noAnswer: return "No answer yet."
        case .neverReported: return "Setup didn't say what happened here."
        }
    }

    private func rowTextColor(_ state: RunRowDisplay) -> Color {
        switch state {
        case .failed, .refused: return Color(nsColor: .systemRed)
        case .noAnswer: return Color(nsColor: .systemOrange)
        case .done: return Color(nsColor: .labelColor)
        case .notStarted, .working, .workingSlow, .neverReported: return Color(nsColor: .secondaryLabelColor)
        }
    }

    private func rowAccessibilityWord(_ state: RunRowDisplay) -> String {
        switch state {
        case .notStarted: return "not started yet"
        case .working: return "working on it now"
        case .workingSlow: return "still working on this one"
        case .done: return "done"
        case .failed: return "couldn't finish"
        case .refused: return "stopped on purpose"
        case .noAnswer: return "no answer yet"
        case .neverReported: return "not reported"
        }
    }

    private func rowAccessibilityDetail(_ state: RunRowDisplay) -> String {
        switch state {
        case .done(let detail), .failed(let detail), .refused(let detail):
            return detail.isEmpty ? "" : ", \(detail)"
        case .notStarted, .working, .workingSlow, .noAnswer, .neverReported:
            return ""
        }
    }

    private var outcomeLine: String? {
        guard case .ended(let outcome) = model.applyRunPhase else { return nil }
        switch outcome {
        case .allDone:
            return nil // the caller advances away; nothing to show here
        case .unfinished(let count):
            return count == 1
                ? "Setup stopped with 1 thing unfinished. Everything else is in place, and running setup again only picks up what's missing."
                : "Setup stopped with \(count) things unfinished. Everything else is in place, and running setup again only picks up what's missing."
        case .refused(let instruction):
            return "Setup stopped on purpose before changing anything else. \(instruction)"
        case .timedOut:
            return "GitHub didn't respond in time, so setup stopped safely. Existing repositories were not overwritten. Check your connection and try again."
        }
    }

    private var outcomeIsFailure: Bool {
        guard case .ended(let outcome) = model.applyRunPhase else { return false }
        if case .allDone = outcome { return false }
        return true
    }
}

/// Review's "The file setup wrote for you" card body (P0, escalating to P4
/// past `WaitClock.settleDelay` — spec §6). A local file write gets no
/// spinner at all until it's genuinely still running past the settle
/// delay; only past `WaitClock.noAnswerDelay` does it read as unusual.
struct BriefCardBody: View {
    @ObservedObject var model: AdminModel
    @State private var watcher = SlowCallWatcher()
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.briefWriteState {
            case .idle:
                HStack(spacing: 10) {
                    Image(systemName: "circle").foregroundColor(Color(nsColor: .tertiaryLabelColor)).accessibilityHidden(true)
                    Text("Not written yet.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Spacer()
                    Button("Write it now") { Task { await model.refreshReview() } }
                        .buttonStyle(.bordered)
                }
            case .working:
                workingView
            case .failure:
                VStack(alignment: .leading, spacing: 8) {
                    Text("I couldn't write the setup file, so I won't hand off a command that points at nothing. Try again.")
                        .foregroundColor(Color(nsColor: .systemRed))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") {
                        Task { await model.refreshReview() }
                    }
                    .buttonStyle(.bordered)
                }
            case .success:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Setup wrote a plain description of your organization you can read:")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(AdminPaths.briefPathDisplay)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(Color(nsColor: .labelColor))
                        Button {
                            AdminIO.revealInFinder(AdminPaths.briefPath)
                        } label: {
                            Text("Reveal ›")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(nsColor: .controlAccentColor))
                    }
                    Text("At a glance: \(model.orgSlug) · \(model.selectedHarnessDisplayNames) · \(model.departments.filter { !$0.slug.isEmpty }.count) departments · \(model.storeAtAGlance).")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Text("It carries no secrets and no integrations.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onChange(of: model.briefWriteState) { newValue in
            if newValue == .working { watcher.arm() } else { watcher.reset() }
        }
    }

    @ViewBuilder
    private var workingView: some View {
        if watcher.isPast(WaitClock.noAnswerDelay, now: now) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Still writing your setup file. That's unusual for a file on this Mac.")
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await model.refreshReview() } }
                    .buttonStyle(.bordered)
            }
        } else if watcher.isPast(WaitClock.settleDelay, now: now) {
            HStack(spacing: 8) {
                RunWorkingIndicator(subject: RunSubject(rowID: "brief", title: "Your organization's setup file"))
                Text("Writing your setup file…")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
        // Within the settle delay: P0's "the result, nothing else" —
        // nothing is drawn at all yet.
    }
}

/// Review's "What Admin found on GitHub" card body (P2 — spec §6). While
/// working, the full target list is already knowable locally (the same
/// naming convention `admin_bootstrap.sh` uses, `AdminModel.
/// plannedRepositoryPreview`), so every row can honestly read "Not checked
/// yet." rather than showing nothing at all.
struct RepositoryInventoryCardBody: View {
    @ObservedObject var model: AdminModel
    @State private var watcher = SlowCallWatcher()
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.repositoryPlanState {
            case .idle:
                HStack(spacing: 10) {
                    Image(systemName: "circle").foregroundColor(Color(nsColor: .tertiaryLabelColor)).accessibilityHidden(true)
                    Text("Not checked yet.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Spacer()
                    Button("Check GitHub now") { Task { await model.loadRepositoryPlan() } }
                        .buttonStyle(.bordered)
                }
            case .working:
                workingView
            case .failure:
                Text(model.repositorySetupMessage ?? "I couldn't read the repository inventory, so I won't create anything.")
                    .foregroundColor(Color(nsColor: .systemRed))
                Button("Try again") { Task { await model.loadRepositoryPlan() } }
                    .buttonStyle(.bordered)
            case .success:
                if let plan = model.repositoryPlan {
                    ForEach(plan.repositories, id: \.name) { repository in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: RepositoryInventoryGlyphs.glyph(repository.state))
                                .foregroundColor(RepositoryInventoryGlyphs.color(repository.state))
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(repository.owner)/\(repository.name)")
                                        .font(.system(.callout, design: .monospaced))
                                    Spacer()
                                    Text(RepositoryInventoryGlyphs.action(repository.state))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(RepositoryInventoryGlyphs.color(repository.state))
                                }
                                Text(repository.detail)
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Text("\(plan.summary.existing) kept · \(plan.summary.missing) to create privately · \(plan.summary.blocked) needing review")
                        .font(.callout.weight(.semibold))
                    Text("Admin rechecks this inventory immediately before setup. Existing private repositories are reused, compatible content is completed additively, and every new repository is private.")
                        .font(.callout.weight(.medium))
                }
                if let message = model.repositorySetupMessage {
                    Text(message)
                        .foregroundColor(model.repositoryPlan?.result == .blocked ? Color(nsColor: .systemRed) : Color(nsColor: .secondaryLabelColor))
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onChange(of: model.repositoryPlanState) { newValue in
            if newValue == .working { watcher.arm() } else { watcher.reset() }
        }
    }

    @ViewBuilder
    private var workingView: some View {
        let preview = model.plannedRepositoryPreview
        if preview.isEmpty {
            Text("There's nothing to set up here. Check your organization name and departments.")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        } else if watcher.isPast(WaitClock.noAnswerDelay, now: now) {
            VStack(alignment: .leading, spacing: 10) {
                Text("GitHub hasn't answered yet. Nothing has been changed.")
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Keep waiting") { watcher.snooze(for: WaitClock.noAnswerDelay) }
                        .buttonStyle(.borderedProminent)
                    Button("Try again") { Task { await model.loadRepositoryPlan() } }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RunWorkingIndicator(subject: RunSubject(rowID: "inventory", title: "What Admin found on GitHub"))
                    Text("Checking your \(preview.count) spaces on GitHub. Nothing is being changed.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                ForEach(preview, id: \.self) { name in
                    HStack(spacing: 8) {
                        Image(systemName: "circle").foregroundColor(Color(nsColor: .tertiaryLabelColor)).accessibilityHidden(true)
                        Text(name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Text("Not checked yet.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Spacer()
                    }
                }
            }
        }
    }
}

/// Shared with `AdminRootView`'s Review surface (native/admin.swift) —
/// pulled out so `RepositoryInventoryCardBody` above doesn't need access to
/// `AdminRootView`'s own private helpers.
enum RepositoryInventoryGlyphs {
    static func action(_ state: RepositoryState) -> String {
        switch state {
        case .existingPrivate: return "Keep"
        case .missing: return "Create privately"
        case .created: return "Created privately"
        case .conflictPublic, .unknown: return "Review"
        }
    }

    static func glyph(_ state: RepositoryState) -> String {
        switch state {
        case .existingPrivate, .created: return "checkmark.circle.fill"
        case .missing: return "plus.circle.fill"
        case .conflictPublic, .unknown: return "hand.raised.circle.fill"
        }
    }

    static func color(_ state: RepositoryState) -> Color {
        switch state {
        case .existingPrivate, .created: return Color(nsColor: .systemGreen)
        case .missing: return Color(nsColor: .controlAccentColor)
        case .conflictPublic, .unknown: return Color(nsColor: .systemRed)
        }
    }
}

// MARK: - AdminModel: the verify verb (admin-standup-contract.md §3) — REAL
// shell-out to `scripts/admin_bootstrap.sh --verify --json`, rendered never
// computed. Degrades honestly if the engine or `gh` is missing.

extension AdminModel {
    func runSetupCheck() {
        Task { await performSetupCheck() }
    }

    private func performSetupCheck() async {
        verifyState = .working
        verifyDegradedLine = nil
        verifyRows = []
        verifyMustFix = 0
        verifyUnknown = 0

        guard FileManager.default.fileExists(atPath: AdminPaths.enginePath) else {
            verifyDegradedLine = "I can't find the setup check engine on this Mac, so I won't guess."
            verifyUnknown = 1
            verifyState = .success
            return
        }

        guard AdminPaths.bundledTool("gh") != nil else {
            verifyDegradedLine = "This Admin app is incomplete, so I can't read what's really on GitHub. Download or rebuild the complete app."
            verifyUnknown = 1
            verifyState = .success
            return
        }

        let result = await ShellRunner.run(
            executable: "/bin/bash",
            arguments: [AdminPaths.enginePath, "--verify", "--brief", AdminPaths.briefJSONPath, "--json"],
            timeout: AdminPaths.engineTimeout
        )

        guard !result.timedOut else {
            verifyDegradedLine = "GitHub didn't respond in time, so I couldn't finish the setup check. Check your connection and try again."
            verifyUnknown = 1
            verifyState = .success
            return
        }

        guard let payload = Self.parseVerifyPayload(result.stdout), Self.isSchemaVersionSupported(payload.schemaVersion) else {
            let honest = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            verifyDegradedLine = honest.isEmpty
                ? "Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up."
                : honest
            verifyUnknown = 1
            verifyState = .success
            return
        }

        verifyRows = payload.rows
        verifyMustFix = payload.mustFix
        verifyUnknown = payload.unknown
        verifyState = .success
    }

    static func isSchemaVersionSupported(_ version: String) -> Bool {
        version.hasPrefix("1.")
    }

    static func parseVerifyPayload(_ jsonString: String) -> (schemaVersion: String, rows: [VerifyRow], mustFix: Int, unknown: Int)? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = obj["schema_version"] as? String,
              let checksArray = obj["checks"] as? [[String: Any]],
              let summary = obj["summary"] as? [String: Any]
        else { return nil }

        let rows: [VerifyRow] = checksArray.compactMap { dict in
            guard let check = dict["check"] as? String,
                  let status = dict["status"] as? String,
                  let detail = dict["detail"] as? String
            else { return nil }
            let owner = dict["owner"] as? String ?? ""
            let fixSurface = dict["fix_surface"] as? String ?? "none"
            return VerifyRow(check: check, status: status, detail: detail, owner: owner, fixSurface: fixSurface)
        }
        let mustFix = summary["must_fix"] as? Int ?? 0
        let unknown = summary["unknown"] as? Int ?? 0
        return (schemaVersion, rows, mustFix, unknown)
    }

    /// The count-never-score summary line (copy deck §3.12), pluralized
    /// honestly, never a percentage or gauge.
    var verifySummaryLine: String {
        if verifyMustFix == 0 && verifyUnknown == 0 { return "Everything is set up and verified." }
        let mustFixPart: String
        if verifyMustFix == 0 { mustFixPart = "Nothing must be fixed." }
        else if verifyMustFix == 1 { mustFixPart = "1 thing must be fixed." }
        else { mustFixPart = "\(verifyMustFix) things must be fixed." }
        let unknownPart: String
        if verifyUnknown == 0 { unknownPart = "Nothing couldn't be checked." }
        else if verifyUnknown == 1 { unknownPart = "1 thing couldn't be checked." }
        else { unknownPart = "\(verifyUnknown) things couldn't be checked." }
        return mustFixPart + " " + unknownPart
    }

    func jumpTarget(for fixSurface: String) -> AdminSelection? {
        switch fixSurface {
        case "describe": return .onboarding(.describeOrg)
        case "connect-github": return .onboarding(.connectGitHub)
        case "connect-store": return .governance(.connectStore)
        default: return nil
        }
    }
}

// MARK: - Surface 9: Organization setup completed

extension AdminRootView {
    var handedOffView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Organization setup is in place",
            intro: "Admin finished the approved setup action. Run the independent Setup check before handing the result to users."
        ) {
            AdminCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The Setup check reads GitHub again from scratch. It confirms that the private spaces, organization setup, OAuth handoff, store pointer, and foundation references match your plan.")
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        model.advance(from: .handedOff)
                    } label: {
                        Text("Run the Setup check")
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Your organization's setup lives on GitHub, and the Setup check reads it fresh every time.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
            }
        } leadingActions: {
            backButton { model.goBack(from: .handedOff) }
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Surface 10: Setup check (real verify shell-out, rendered not
// computed; count-never-score; drift + deferred-store + beyond-plan rows)

extension AdminRootView {
    var setupCheckView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "The setup check",
            intro: "An honest look at what's really on GitHub now. Every red names who has to fix it."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if model.verifyState == .idle {
                    AdminCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Run the setup check before you hand this over. It catches blockers before your organization does.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Run the setup check") {
                                model.runSetupCheck()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .foregroundColor(Color(nsColor: .labelColor))
                    }
                } else {
                    Text("This reads what's really on GitHub, not what you typed here. If setup did more or less than your plan, you'll see it below.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)

                    SetupCheckBody(model: model)
                }
            }
        } leadingActions: {
            if model.verifyState != .idle {
                Button("Run it again") { model.runSetupCheck() }
                    .buttonStyle(.bordered)
            }
        } primaryAction: {
            primaryButton(
                "Continue",
                enabled: model.verifyState == .success && model.verifyDegradedLine == nil && model.verifyMustFix == 0
            ) {
                model.advance(from: .setupCheck)
            }
        }
    }

}

/// Setup check's post-"never run" body (P2, read only — spec §6). Owns its
/// own settle clock so "Checking what's really on GitHub" can honestly
/// escalate to "GitHub hasn't answered yet" past `WaitClock.noAnswerDelay`
/// real seconds — a separate `View` from `AdminRootView` only so it can
/// hold that `@State` (a computed property can't).
struct SetupCheckBody: View {
    @ObservedObject var model: AdminModel
    @State private var watcher = SlowCallWatcher()
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.verifyState == .working {
                workingView
            } else if let degraded = model.verifyDegradedLine {
                AdminCard {
                    Text(degraded)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                AdminCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.verifyRows.enumerated()), id: \.offset) { index, row in
                            verifyRowView(row)
                            if index < model.verifyRows.count - 1 { Divider() }
                        }
                    }
                }

                Text(model.verifySummaryLine)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onReceive(ticker) { now = $0 }
        .onChange(of: model.verifyState) { newValue in
            if newValue == .working { watcher.arm() } else { watcher.reset() }
        }
    }

    @ViewBuilder
    private var workingView: some View {
        if watcher.isPast(WaitClock.noAnswerDelay, now: now) {
            AdminCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GitHub hasn't answered yet. Nothing was changed by checking.")
                        .foregroundColor(Color(nsColor: .labelColor))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { model.runSetupCheck() }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            HStack(spacing: 8) {
                RunWorkingIndicator(subject: RunSubject(rowID: "setup-check", title: "The setup check"))
                Text("Checking what's really on GitHub. This only reads, it changes nothing.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
    }

    private func verifyRowView(_ row: VerifyRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            verifyGlyph(row.status)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.detail)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                if row.status == "present-undeclared" {
                    Text("This wasn't in your plan. Setup added it, and that's fine.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            Spacer()
            if row.status == "pass" {
                Text("Ready")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            if !row.owner.isEmpty, row.status == "fail" || row.status == "unknown" || row.status == "deferred" {
                OwnerChip(owner: row.owner)
            }
            if row.status == "fail" || row.status == "deferred", let target = model.jumpTarget(for: row.fixSurface) {
                Button(row.status == "deferred" ? "Connect ›" : "Go fix this") {
                    model.selection = target
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .controlAccentColor))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.check), \(row.status)\(row.owner.isEmpty ? "" : ", " + row.owner)")
    }

    private func verifyGlyph(_ status: String) -> some View {
        Group {
            switch status {
            case "pass":
                Image(systemName: "checkmark.circle.fill").foregroundColor(Color(nsColor: .systemGreen))
            case "fail":
                Image(systemName: "xmark.circle.fill").foregroundColor(Color(nsColor: .systemRed))
            case "unknown":
                Image(systemName: "questionmark.circle").foregroundColor(Color(nsColor: .systemOrange))
            case "deferred":
                Image(systemName: "circle.dotted").foregroundColor(Color(nsColor: .secondaryLabelColor))
            case "present-undeclared":
                Image(systemName: "circle.fill").foregroundColor(Color(nsColor: .secondaryLabelColor))
            default:
                Image(systemName: "circle").foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Surface 11: Done, and what now

extension AdminRootView {
    var doneView: some View {
        StepShell(
            eyebrow: model.onboardingIsComplete ? "ONBOARDING COMPLETE" : "ONBOARDING",
            title: "Your organization is set up",
            intro: model.onboardingIsComplete
                ? "All onboarding steps are checked. Use Governance whenever the organization changes."
                : "Everything is verified. Finish setup to check off onboarding and move into ongoing administration."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AdminCard {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(nsColor: .systemGreen))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.onboardingIsComplete ? "Onboarding complete" : "Everything is verified")
                                .font(.body.weight(.semibold))
                            Text(
                                model.onboardingIsComplete
                                    ? "Control Tower is ready for your team. Adding a department later will reopen review and verification."
                                    : "The spaces exist, teams can reach them, and the setup file matches GitHub."
                            )
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                AdminCard(title: "Invite the team, on GitHub") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(inviteTeamLine)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open your teams ›") {
                            let org = model.orgSlug
                            if let url = URL(string: "https://github.com/orgs/\(org)/teams") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(nsColor: .controlAccentColor))
                    }
                }
                AdminCard(title: "Point users at the app") {
                    Text("Your team installs Copilot Control Tower themselves, and it sets them up from what you just built. Send them the app, and they'll see the departments they're on.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.body)
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            backButton { model.goBack(from: .done) }
        } primaryAction: {
            if model.onboardingIsComplete {
                primaryButton("Close Administration") {
                    NSApp.keyWindow?.performClose(nil)
                }
            } else {
                primaryButton("Finish setup") {
                    model.finishOnboarding()
                }
            }
        }
    }

    /// Copy deck §3.13's worked example names "Sales" verbatim; the real
    /// surface substitutes the org's actual first department (QA fix), and
    /// falls back to a neutral phrasing when none exist yet, keeping the
    /// same sentence shape.
    private var inviteTeamLine: String {
        if let first = model.departments.first(where: { !$0.slug.isEmpty }) {
            return "People join a department by being added to its team on GitHub. Add someone to the \(first.name) team and they can join \(first.name) from their own copilot. This app never manages people. GitHub does."
        }
        return "People join a department by being added to its team on GitHub. This app never manages people. GitHub does."
    }
}

// MARK: - Governance Surface 12: Add a department (routes into Describe)

extension AdminRootView {
    var addDepartmentView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Add a department",
            intro: "Review what is already set up, then add only what is new."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AdminCard(title: "Current departments") {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.validDepartments.isEmpty {
                            Text("No departments are set up yet.")
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(Array(model.validDepartments.enumerated()), id: \.element.id) { index, department in
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(nsColor: .systemGreen))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(department.name)
                                            .font(.body.weight(.semibold))
                                        Text(department.slug)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                    }
                                    Spacer()
                                    Text("\(model.selectedComponentRepoTokens.count) private spaces")
                                        .font(.caption)
                                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                }
                                .padding(.vertical, 9)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    "\(department.name), repository name \(department.slug), "
                                        + "\(model.selectedComponentRepoTokens.count) private spaces"
                                )
                                if index < model.validDepartments.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                AdminCard(title: "Add another department") {
                    VStack(alignment: .leading, spacing: 10) {
                        SecretGuardedField(
                            label: "Department name",
                            value: Binding(
                                get: { model.pendingDepartmentName },
                                set: {
                                    model.pendingDepartmentName = $0
                                    model.pendingDepartmentTouched = true
                                }
                            ),
                            placeholder: AdminPlaceholder.department,
                            accessibilityName: "New department name"
                        )
                        .frame(maxWidth: 320)

                        if let validation = model.pendingDepartmentValidationMessage {
                            Text(validation)
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .systemRed))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isStaticText)
                        } else if let preview = model.pendingDepartmentPreview {
                            Text(preview)
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Nothing changes until you review the addition.")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }

                        Button("Review department setup") {
                            model.beginPendingDepartmentAddition()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canReviewPendingDepartment)
                        .accessibilityHint(
                            model.canReviewPendingDepartment
                                ? "Adds this department to the setup plan and opens Review setup."
                                : "Enter a new department name that is not already listed."
                        )
                    }
                }
            }
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Governance Surface 13: Someone left (instructional guidance only,
// triggers nothing; CONTRACT SEAM below on the lookup result)

extension AdminRootView {
    var someoneLeftView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Someone left",
            intro: "This app doesn't manage people. When someone leaves, remove them from their teams on GitHub. Then rotate the keys those teams could reach in your shared store, so their old access is worthless."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text("Who left")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    TextField(AdminPlaceholder.githubUsername, text: $model.someoneLeftLookup)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .accessibilityLabel("GitHub username of the person who left")
                    Button("Look up") {
                        model.someoneLeftLookedUp = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.someoneLeftLookup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if model.someoneLeftLookedUp {
                    // CONTRACT SEAM: reading a person's real team membership
                    // and the registry-derived key names they could reach
                    // needs a live, per-person `gh` read this build does not
                    // implement. Render the designed honest holding line
                    // rather than invent team/key rows.
                    AdminCard {
                        Text("I couldn't read the result of this, so I won't guess.")
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Governance Surface 14: Connect the shared store (deferred case;
// rewrites the SAME canonical brief per admin-standup-contract.md §1.4)

extension AdminRootView {
    var connectStoreGovernanceView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Connect the shared store",
            intro: "Connect the store that holds your organization's shared keys. Your integrations will need it before they can work. A shared secret store hands out keys by GitHub team, so a key never lives in a repo or in this app."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                AdminCard {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Store type")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            Picker("", selection: $model.storeKind) {
                                ForEach(StoreKind.allCases) { kind in
                                    Text(kind.rawValue).tag(kind)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }

                        SecretGuardedField(
                            label: "Store address",
                            value: $model.storeAddress,
                            placeholder: AdminPlaceholder.storeAddress,
                            helpText: "This is a web address, not a secret."
                        )
                        .frame(maxWidth: 360)

                        if !model.departments.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Which teams can use it")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                ForEach(model.departments) { dept in
                                    if !dept.slug.isEmpty {
                                        HStack {
                                            Text(dept.name).frame(width: 120, alignment: .leading)
                                            Text("→").foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                            SecretGuardedField(
                                                label: "",
                                                value: model.scopeBinding(for: dept),
                                                placeholder: AdminPlaceholder.departmentScope(dept.slug),
                                                accessibilityName: "Shared secret path for \(dept.name)"
                                            )
                                            .frame(maxWidth: 220)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                AdminCard(title: "How this is added") {
                    Text("Admin adds the store pointer to your organization's setup. It checks the existing repositories first and never deletes or overwrites unfamiliar content.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.body)
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            primaryButton(
                "Review store update",
                enabled: model.storeAddressLooksValid && !model.storeAddress.isEmpty && model.storeConnectionDetailsAreValid
            ) {
                Task {
                    model.storeStatus = .connected
                    await model.writeBrief()
                    if model.briefWriteState == .success {
                        await model.loadRepositoryPlan()
                        model.selection = .onboarding(.review)
                    }
                }
            }
        }
    }
}

// MARK: - Governance Surface 15: Org setup (read-only summary)

extension AdminRootView {
    var orgSetupView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Your organization's setup",
            intro: "Everything your organization hands out, in one place. This comes from your organization's setup on GitHub. It isn't editable here, by design."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if model.orgSlug.isEmpty {
                    AdminCard {
                        Text("Describe your organization first, so there's something here to read.")
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                } else {
                    AdminCard(title: "Copilots & harness") {
                        Text("Harnesses: \(model.selectedHarnessDisplayNames). \(model.selectedComponentDisplayNames.joined(separator: " · ")).")
                    }
                    AdminCard(title: "Departments") {
                        let names = model.departments.filter { !$0.slug.isEmpty }.map { $0.name }
                        Text(names.isEmpty ? "None yet." : names.joined(separator: " · "))
                    }
                    AdminCard(title: "Published integrations") {
                        // CONTRACT SEAM: no seam reads per-repo registry
                        // manifests yet (admin-standup-contract.md §5); this
                        // always renders the honest empty state rather than
                        // invent published entries.
                        Text("None published yet.")
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                    AdminCard(title: "Where your shared keys come from") {
                        if model.storeStatus == .connected {
                            Text(model.storeAddress)
                                .font(.system(.callout, design: .monospaced))
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Not connected yet. Connect one before your first shared integration can work.")
                                Button("Connect the store ›") {
                                    model.selection = .governance(.connectStore)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(Color(nsColor: .controlAccentColor))
                            }
                        }
                    }
                }
            }
            .font(.body)
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Governance Surface 16: Analytics (off by default)

extension AdminRootView {
    var analyticsView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Usage data",
            intro: "Off. Nothing is shared unless you turn this on and your organization signs off on it."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Share anonymous usage data", isOn: $model.analyticsEnabled)
                    .toggleStyle(.switch)

                AdminCard(title: "What this would share") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Which copilots and departments this Mac has set up.")
                        Text("How often this app is opened.")
                        Text("Whether setup finished without errors.")
                    }
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            .font(.body)
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Admin window controller

/// Owns the Admin window + its `AdminModel` for the app's lifetime, same
/// singleton shape as `WizardWindowController`. `isReleasedWhenClosed =
/// false` so closing the window never deallocates it — reopening picks up
/// wherever Earl left off (nothing is lost by closing mid-progression, since
/// nothing here is locked; interaction-design §1.3).
final class AdminWindowController: NSWindowController {
    static let shared = AdminWindowController()

    private let model = AdminModel()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Administration"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentViewController = NSHostingController(rootView: AdminRootView(model: model))
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
