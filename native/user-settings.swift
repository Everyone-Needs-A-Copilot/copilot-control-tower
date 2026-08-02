//
// Copilot Control Tower — completed User Settings.
//
// This is the returning-person home. It deliberately keeps four independent
// CLI reports separate: doctor (active component/layer evidence), personal
// onboarding (Personal repository truth), layers (department availability),
// and workspaces (the same project classifications Step 7 renders). Opening
// Settings is read-only; every mutation routes back through the existing
// onboarding/project flows.
//

import AppKit
import SwiftUI

enum UserSettingsLoadState<Value> {
    case waiting
    case loading
    case loaded(Value)
    case failed
}

enum UserSettingsComponent: String, CaseIterable, Identifiable {
    case knowledge
    case cli
    case claude
    case codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .knowledge: return "Knowledge Copilot"
        case .cli: return "CLI Copilot"
        case .claude: return "Claude Copilot"
        case .codex: return "Codex Copilot"
        }
    }
}

enum UserSettingsTierKind {
    case ready
    case needsSetup
    case needsAttention
    case notJoined
    case couldNotCheck

    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .needsSetup: return "wrench.adjustable"
        case .needsAttention: return "exclamationmark.triangle.fill"
        case .notJoined: return "circle"
        case .couldNotCheck: return "questionmark.circle"
        }
    }

    /// The raw NSColor -- glyphs keep using this directly (shape carries the
    /// state, colour there is redundant decoration; WCAG 1.4.11).
    var color: NSColor {
        switch self {
        case .ready: return .systemGreen
        case .needsSetup: return .systemBlue
        case .needsAttention: return .systemOrange
        case .notJoined, .couldNotCheck: return .secondaryLabelColor
        }
    }

    /// The same state, mapped onto the shared appearance-corrected ramp
    /// (`CTColor.state(_:)`) for TEXT only (task 222 P1-5, G-5) -- raw
    /// `.systemGreen`/`.systemOrange` measure 2.22:1/2.31:1 as text on the
    /// light page, under this product's own 4.5:1 floor.
    var ctState: CTState {
        switch self {
        case .ready: return .ready
        case .needsSetup: return .actionable
        case .needsAttention: return .attention
        case .notJoined, .couldNotCheck: return .neutral
        }
    }
}

struct UserSettingsTierStatus: Identifiable {
    let id: Layer
    let label: String
    let state: String
    let detail: String
    let kind: UserSettingsTierKind
}

struct UserSettingsComponentStatus: Identifiable {
    let id: UserSettingsComponent
    let overall: String
    let overallKind: UserSettingsTierKind
    let tiers: [UserSettingsTierStatus]
}

enum UserSettingsRender {
    static func projectCategories(_ report: WorkspacesReport) -> [ProjectTriageCategory] {
        ProjectTriageRender.nonEmptyCategories(report.workspaces)
    }

    static func componentStatuses(
        doctor: DoctorReport?,
        personal: OnboardReport?,
        layers: LayersReport?
    ) -> [UserSettingsComponentStatus] {
        UserSettingsComponent.allCases.map { component in
            let foundation = checkerTier(
                component: component,
                layer: .foundation,
                doctor: doctor
            )
            let organization = checkerTier(
                component: component,
                layer: .org,
                doctor: doctor
            )
            let department = checkerTier(
                component: component,
                layer: .dept,
                doctor: doctor,
                absentKind: layers == nil ? .couldNotCheck : .notJoined,
                absentState: layers == nil ? "Could not check" : "Not joined",
                absentDetail: layers == nil
                    ? "The department catalog could not be checked."
                    : "No active Department evidence was reported for this component."
            )
            let personalTier = personalStatus(component: component, report: personal)
            let tiers = [foundation, organization, department, personalTier]
            let overallKind: UserSettingsTierKind
            let overall: String
            if personalTier.kind == .needsSetup {
                overallKind = .needsSetup
                overall = "Needs Personal setup"
            } else if tiers.contains(where: { $0.kind == .needsAttention }) {
                overallKind = .needsAttention
                overall = "Needs attention"
            } else if tiers.contains(where: { $0.kind == .couldNotCheck }) {
                overallKind = .couldNotCheck
                overall = "Could not fully check"
            } else if foundation.kind == .ready,
                      organization.kind == .ready,
                      personalTier.kind == .ready {
                overallKind = .ready
                overall = "Ready"
            } else {
                overallKind = .needsAttention
                overall = "Setup incomplete"
            }
            return UserSettingsComponentStatus(
                id: component,
                overall: overall,
                overallKind: overallKind,
                tiers: tiers
            )
        }
    }

    static func topologyStatuses(
        _ report: EcosystemOnboardReport,
        doctor: DoctorReport? = nil
    ) -> [UserSettingsComponentStatus] {
        UserSettingsComponent.allCases.map { component in
            let rows = report.layers
                .filter { $0.product == component.rawValue }
                .sorted { $0.rank > $1.rank }
            let tiers = rows.map { row -> UserSettingsTierStatus in
                let layer: Layer
                switch row.role {
                case "foundation": layer = .foundation
                case "organization": layer = .org
                case "department": layer = .dept
                default: layer = .personal
                }
                let label = row.role == "department"
                    ? (row.unit?.capitalized ?? "Department")
                    : tierLabel(layer)
                let action = row.action ?? "review"
                let kind: UserSettingsTierKind
                let state: String
                switch action {
                case "reuse":
                    let verified = doctor?.checkers.contains {
                        $0.product == component.rawValue
                            && $0.layerRole == row.role
                            && $0.severity == .pass
                    } == true
                    if row.syncState == "local-changes" {
                        kind = .needsAttention
                        state = "Local work preserved"
                    } else if verified {
                        kind = .ready
                        state = "Ready"
                    } else {
                        kind = .needsAttention
                        state = "Found, not verified"
                    }
                case "create": kind = .needsSetup; state = "Needs creation"
                case "download": kind = .needsSetup; state = "Needs download"
                case "initialize": kind = .needsSetup; state = "Needs initialization"
                case "repair": kind = .needsAttention; state = "Needs update"
                default: kind = .needsAttention; state = "Needs review"
                }
                return UserSettingsTierStatus(
                    id: layer,
                    label: label,
                    state: state,
                    detail: row.detail ?? "Control Tower could not explain this layer.",
                    kind: kind
                )
            }
            let ready = !tiers.isEmpty && tiers.allSatisfy { $0.kind == .ready }
            return UserSettingsComponentStatus(
                id: component,
                overall: ready ? "Ready" : "Needs setup",
                overallKind: ready ? .ready : .needsSetup,
                tiers: tiers
            )
        }
    }

    static func personalReadyCount(_ report: OnboardReport) -> Int {
        UserSettingsComponent.allCases.filter { component in
            personalStatus(component: component, report: report).kind == .ready
        }.count
    }

    static func personalNeedsAction(_ report: OnboardReport) -> Bool {
        report.result != .ready && report.result != .applied
    }

    private static func checkerTier(
        component: UserSettingsComponent,
        layer: Layer,
        doctor: DoctorReport?,
        absentKind: UserSettingsTierKind = .needsAttention,
        absentState: String = "Not connected",
        absentDetail: String? = nil
    ) -> UserSettingsTierStatus {
        guard let doctor else {
            return UserSettingsTierStatus(
                id: layer,
                label: tierLabel(layer),
                state: "Could not check",
                detail: "The active setup report could not be read.",
                kind: .couldNotCheck
            )
        }
        let matching = doctor.checkers.filter {
            $0.product == component.rawValue
                && $0.layerRole == canonicalRole(layer)
        }
        guard !matching.isEmpty else {
            return UserSettingsTierStatus(
                id: layer,
                label: tierLabel(layer),
                state: absentState,
                detail: absentDetail
                    ?? "The setup helper did not report an active \(tierLabel(layer)) layer.",
                kind: absentKind
            )
        }
        let worst: CliSeverity = matching.contains(where: { $0.severity == .fail })
            ? .fail
            : matching.contains(where: { $0.severity == .warn }) ? .warn : .pass
        let detail = matching.first(where: { $0.severity == worst })?.detail
            ?? "The setup helper verified this layer."
        switch worst {
        case .pass:
            return UserSettingsTierStatus(
                id: layer,
                label: tierLabel(layer),
                state: "Ready",
                detail: detail,
                kind: .ready
            )
        case .warn:
            return UserSettingsTierStatus(
                id: layer,
                label: tierLabel(layer),
                state: "Needs review",
                detail: detail,
                kind: .needsAttention
            )
        case .fail:
            return UserSettingsTierStatus(
                id: layer,
                label: tierLabel(layer),
                state: "Needs attention",
                detail: detail,
                kind: .needsAttention
            )
        }
    }

    private static func canonicalRole(_ layer: Layer) -> String {
        switch layer {
        case .foundation: return "foundation"
        case .org: return "organization"
        case .dept: return "department"
        case .personal: return "personal"
        }
    }

    private static func personalStatus(
        component: UserSettingsComponent,
        report: OnboardReport?
    ) -> UserSettingsTierStatus {
        guard let report,
              let row = report.repositories.first(where: { $0.component == component.rawValue }) else {
            return UserSettingsTierStatus(
                id: .personal,
                label: "Personal",
                state: "Could not check",
                detail: "The Personal setup report could not be read.",
                kind: .couldNotCheck
            )
        }
        let technical = "Stored in \(row.owner)/\(row.name), a private GitHub repository only you can access."
        switch row.state {
        case .missing:
            return UserSettingsTierStatus(
                id: .personal,
                label: "Personal",
                state: "Needs setup",
                detail: row.packageDetail,
                kind: .needsSetup
            )
        case .created:
            return UserSettingsTierStatus(
                id: .personal,
                label: "Personal",
                state: "Ready",
                detail: technical,
                kind: .ready
            )
        case .existingPrivate:
            if ["ready", "seeded", "adopted"].contains(row.packageState) {
                return UserSettingsTierStatus(
                    id: .personal,
                    label: "Personal",
                    state: "Ready",
                    detail: technical,
                    kind: .ready
                )
            }
            if row.packageState == "empty" || row.packageState == "adoptable" {
                return UserSettingsTierStatus(
                    id: .personal,
                    label: "Personal",
                    state: "Needs setup",
                    detail: row.packageDetail,
                    kind: .needsSetup
                )
            }
            return UserSettingsTierStatus(
                id: .personal,
                label: "Personal",
                state: "Needs attention",
                detail: row.packageDetail,
                kind: .needsAttention
            )
        case .conflictPublic, .unknown:
            return UserSettingsTierStatus(
                id: .personal,
                label: "Personal",
                state: "Needs attention",
                detail: row.detail,
                kind: .needsAttention
            )
        }
    }

    private static func tierLabel(_ layer: Layer) -> String {
        switch layer {
        case .foundation: return "Foundation"
        case .org: return "Organization"
        case .dept: return "Department"
        case .personal: return "Personal"
        }
    }
}

@MainActor
final class UserSettingsModel: ObservableObject {
    @Published private(set) var authState: UserSettingsLoadState<AuthStatus> = .waiting
    @Published private(set) var doctorState: UserSettingsLoadState<DoctorReport> = .waiting
    @Published private(set) var personalState: UserSettingsLoadState<OnboardReport> = .waiting
    @Published private(set) var layersState: UserSettingsLoadState<LayersReport> = .waiting
    @Published private(set) var projectsState: UserSettingsLoadState<WorkspacesReport> = .waiting
    @Published private(set) var topologyState: UserSettingsLoadState<EcosystemOnboardReport> = .waiting
    /// "Your connections" card's organization roster (task 221 bridge stage
    /// C) -- `ConnectionsLoadState`, not `UserSettingsLoadState<ConnectionsReport>`,
    /// because this one card needs the real `CliError` to tell a
    /// verb-unavailable `cc` build apart from any other read failure
    /// (`native/render-state.swift`'s own doc comment on why).
    @Published private(set) var connectionsState: ConnectionsLoadState = .waiting

    private var isLoading = false

    /// Read-only by construction: Settings never calls apply merely because
    /// the window opened.
    func load() {
        guard !isLoading else { return }
        isLoading = true
        authState = .loading
        doctorState = .loading
        personalState = .loading
        layersState = .loading
        projectsState = .loading
        topologyState = .loading
        connectionsState = .loading

        Task {
            async let authResult = CliClient.shared.authStatus()
            async let doctorResult = CliClient.shared.doctor()
            async let personalResult = CliClient.shared.onboardPlan(
                components: UserSettingsComponent.allCases.map(\.rawValue)
            )
            async let layersResult = CliClient.shared.layers()
            async let projectsResult = CliClient.shared.workspaces()
            async let topologyResult = CliClient.shared.ecosystemOnboardPlan(products: ["claude", "codex"])
            async let connectionsResult = CliClient.shared.connections()

            let auth = await authResult
            let doctor = await doctorResult
            let personal = await personalResult
            let layers = await layersResult
            let projects = await projectsResult
            let topology = await topologyResult
            let connections = await connectionsResult

            authState = auth.loadedState
            doctorState = doctor.loadedState
            personalState = personal.loadedState
            layersState = layers.loadedState
            projectsState = projects.loadedState
            topologyState = topology.loadedState
            switch connections {
            case .success(let report): connectionsState = .loaded(report)
            case .failure(let error): connectionsState = .failed(error)
            }
            isLoading = false
        }
    }
}

private extension Result {
    var loadedState: UserSettingsLoadState<Success> {
        switch self {
        case .success(let value): return .loaded(value)
        case .failure: return .failed
        }
    }
}

struct UserSettingsView: View {
    @ObservedObject var model: UserSettingsModel
    let onFinishPersonalSetup: () -> Void
    let onManageProjects: (ProjectTriageCategory?) -> Void
    @State private var expandedComponents: Set<UserSettingsComponent> = []
    /// The Connect sheet's row (task 222) — presentation-only, dropped the
    /// moment the sheet closes, exactly as `native/wizard.swift`'s step 6
    /// holds it.
    @State private var connectingRow: ConnectionRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                setupHeader

                settingsCard(title: "Your copilots") {
                    copilotsContent
                }

                settingsCard(title: "Your connections") {
                    connectionsContent
                }

                settingsCard(title: "Your projects") {
                    projectsContent
                }
            }
            .padding(28)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 650, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $connectingRow) { row in
            ConnectSheet(row: row) { _ in
                // Same discipline as the wizard's step 6: re-read everything
                // from the CLI rather than patching the one row this app just
                // changed.
                connectingRow = nil
                model.load()
            } onCancel: {
                connectingRow = nil
            }
        }
    }

    @ViewBuilder
    private var setupHeader: some View {
        switch model.topologyState {
        case .waiting, .loading:
            VStack(alignment: .leading, spacing: CTSpace.sm) {
                Text("Your setup")
                    .ctText(CTType.hero)
                loadingRow("Checking every Copilot repository and layer…")
            }
        case .failed:
            VStack(alignment: .leading, spacing: CTSpace.md) {
                Text("Your setup")
                    .ctText(CTType.hero)
                Text("Control Tower couldn't check whether the ecosystem is complete.")
                    .ctText(CTType.sectionTitle)
                Text("Nothing was changed, and Control Tower will not call the ecosystem ready without that report.")
                    .ctText(CTType.lead)
                Button("Try again") { model.load() }
                    .buttonStyle(.bordered)
            }
        case .loaded(let topology):
            let doctor = loaded(model.doctorState)
            let statuses = UserSettingsRender.topologyStatuses(topology, doctor: doctor)
            let ready = statuses.flatMap(\.tiers).filter { $0.kind == .ready }.count
            let needsAction = ready != topology.layers.count
            VStack(alignment: .leading, spacing: CTSpace.md) {
                Text("Your setup")
                    .ctText(CTType.hero)
                Text(needsAction
                    ? "Your Copilot setup is incomplete"
                    : "Your ecosystem is ready")
                    .ctText(CTType.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(needsAction
                    ? "\(ready) of \(topology.layers.count) expected layers are already in place. Finish the others now or return here later."
                    : "Knowledge, CLI, Claude, and Codex have verified Foundation, Organization, Department, and Personal layers.")
                    .ctText(CTType.lead)
                    .fixedSize(horizontal: false, vertical: true)
                if needsAction {
                    Button("Finish Copilot Setup", action: onFinishPersonalSetup)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private var copilotsContent: some View {
        if case .loading = model.topologyState {
            loadingRow("Checking Knowledge, CLI, Claude, and Codex…")
        } else if case .waiting = model.topologyState {
            loadingRow("Checking Knowledge, CLI, Claude, and Codex…")
        } else {
            let topology = loaded(model.topologyState)
            let statuses = topology.map {
                UserSettingsRender.topologyStatuses($0, doctor: loaded(model.doctorState))
            } ?? []
            VStack(alignment: .leading, spacing: 10) {
                if let root = topology?.stages.first(where: { $0.stage == "repository-location" })?.path {
                    VStack(alignment: .leading, spacing: CTSpace.hair) {
                        Text("Copilot repository folder")
                            .ctText(CTType.rowDetail, color: CTColor.ink)
                        Text(root)
                            .ctText(CTType.mono)
                            .textSelection(.enabled)
                        Text("New Copilot repositories are created or downloaded here, beside the ones you already have.")
                            .ctText(CTType.caption)
                    }
                    .ctCard(.well)
                }
                Text("Each Copilot shows Foundation, Organization, your joined Department, and Personal as separate evidence-backed layers.")
                    .ctText(CTType.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Personal is yours; its repository is private, but its checkout stays visible in your Copilot repository folder.")
                    .ctText(CTType.caption)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(statuses) { component in
                    componentCard(component)
                }
            }
        }
    }

    private func componentCard(_ component: UserSettingsComponentStatus) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedComponents.contains(component.id) },
                set: { expanded in
                    if expanded {
                        expandedComponents.insert(component.id)
                    } else {
                        expandedComponents.remove(component.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                ForEach(component.tiers) { tier in
                    tierRow(tier)
                    if tier.id != component.tiers.last?.id { Divider() }
                }
            }
            .padding(.top, CTSpace.sm)
        } label: {
            HStack(spacing: CTSpace.sm) {
                Image(systemName: component.overallKind.symbol)
                    .foregroundColor(Color(nsColor: component.overallKind.color))
                    .accessibilityHidden(true)
                Text(component.id.label)
                    .ctText(CTType.rowTitle)
                Spacer()
                Text(component.overall)
                    .ctText(CTType.status, color: CTColor.state(component.overallKind.ctState))
            }
            .contentShape(Rectangle())
        }
        .ctCard()
        .accessibilityLabel("\(component.id.label), \(component.overall)")
    }

    private func tierRow(_ tier: UserSettingsTierStatus) -> some View {
        HStack(alignment: .top, spacing: CTSpace.sm) {
            Image(systemName: tier.kind.symbol)
                .foregroundColor(Color(nsColor: tier.kind.color))
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CTSpace.hair) {
                Text(tier.label)
                    .ctText(CTType.rowTitle)
                Text(tier.detail)
                    .ctText(CTType.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(tier.state)
                .ctText(CTType.status, color: CTColor.state(tier.kind.ctState))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, CTSpace.rowV)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier.label), \(tier.state), \(tier.detail)")
    }

    @ViewBuilder
    private var connectionsContent: some View {
        switch model.authState {
        case .waiting, .loading:
            loadingRow("Checking your connections…")
        case .failed:
            checkFailed(
                title: "Control Tower couldn't check your connections.",
                detail: "Nothing was changed. Try again when the setup helper is available."
            )
        case .loaded(let auth):
            VStack(alignment: .leading, spacing: CTSpace.sm) {
                CTCardTitle("Ready to use")
                VStack(alignment: .leading, spacing: 0) {
                    CTStatusRow(
                        glyph: .filledDot(.neutral),
                        title: "GitHub",
                        detail: githubDetail(auth),
                        trailing: .status(auth.state == .authorized ? "Ready" : "Needs sign-in", .neutral)
                    )

                    if case .loaded(let report) = model.connectionsState {
                        let ready = ConnectionsRender.readyRows(report)
                        if !ready.isEmpty {
                            Divider()
                            ForEach(Array(ready.enumerated()), id: \.element.id) { index, row in
                                connectionReadyRow(row)
                                if index < ready.count - 1 { Divider() }
                            }
                        }
                    }
                }

                organizationConnectionsSection
            }
        }
    }

    private func githubDetail(_ auth: AuthStatus) -> String {
        switch auth.state {
        case .authorized:
            return "Signed in as \(auth.identity?.login ?? "your GitHub account")."
        case .signedOut:
            return "This Mac is not signed in to GitHub."
        }
    }

    /// The organization's declared connections roster (task 221 bridge stage
    /// C), rendered directly beneath the GitHub row -- same `ConnectionsRender`
    /// grouping `native/wizard.swift`'s step 6 uses, independent styling.
    ///
    /// The "Available to connect" header (and its rows) disappears entirely
    /// once nothing is pending -- same correction as the wizard's step 6
    /// (spec §5.3): never left standing as an empty shell once the CLI has
    /// confirmed there is nothing left to connect.
    @ViewBuilder
    private var organizationConnectionsSection: some View {
        switch model.connectionsState {
        case .waiting, .loading:
            loadingRow("Checking your organization's connections…")

        case .loaded(let report):
            let needsConnect = ConnectionsRender.needsConnectRows(report)
            let noStore = ConnectionsRender.noStoreRows(report)
            if report.connections.isEmpty {
                Text(ConnectionsRender.unavailableDetail(report))
                    .ctText(CTType.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !needsConnect.isEmpty || !noStore.isEmpty {
                CTCardTitle("Available to connect")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(needsConnect.enumerated()), id: \.element.id) { index, row in
                        connectionNeedsConnectRow(row)
                        if index < needsConnect.count - 1 || !noStore.isEmpty { Divider() }
                    }
                    if !noStore.isEmpty {
                        connectionsNoStoreGroup(noStore, storeDetail: report.store.detail)
                    }
                }
            }

        case .failed(let error):
            VStack(alignment: .leading, spacing: CTSpace.xs) {
                Text("No additional organization connections are available in Control Tower right now.")
                    .ctText(CTType.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
                if error.looksLikeMissingConnectionsVerb {
                    Text(ConnectionsRender.updateHint)
                        .ctText(CTType.caption)
                }
            }
        }
    }

    /// `secret_state == ready` org row.
    private func connectionReadyRow(_ row: ConnectionRow) -> some View {
        CTStatusRow(
            glyph: .filledDot(.neutral),
            title: row.name.capitalized,
            detail: row.description,
            trailing: .status("Ready", .neutral),
            accessibilityLabelOverride: "\(row.name.capitalized), ready, \(row.description)"
        )
    }

    /// `secret_state == needs-connect` org row -- names what is actually
    /// missing, in plain language, never tier/mode jargon, and carries the
    /// same Connect affordance the wizard's step 6 does (task 222), on the
    /// same rule: `needs-connect` only, never a `no-store` row.
    private func connectionNeedsConnectRow(_ row: ConnectionRow) -> some View {
        let missingDetail = ConnectionsRender.needsConnectDetail(row)
        return CTStatusRow(
            glyph: .ring,
            title: row.name.capitalized,
            detail: row.description,
            footnote: missingDetail,
            trailing: .button("Connect…", accessibilityLabel: "Connect \(row.name.capitalized)") {
                connectingRow = row
            }
        )
    }

    /// `secret_state == no-store` rows -- grouped under one honest
    /// explanation (`store.detail`) rather than one line per row.
    private func connectionsNoStoreGroup(_ rows: [ConnectionRow], storeDetail: String?) -> some View {
        VStack(alignment: .leading, spacing: CTSpace.xs) {
            Text(storeDetail ?? "Your organization's shared secret store could not be checked on this Mac.")
                .ctText(CTType.rowDetail)
                .fixedSize(horizontal: false, vertical: true)
            Text(rows.map { $0.name.capitalized }.joined(separator: ", "))
                .ctText(CTType.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, CTSpace.sm)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var projectsContent: some View {
        switch model.projectsState {
        case .waiting, .loading:
            loadingRow("Checking your projects…")
        case .failed:
            checkFailed(
                title: "Control Tower couldn't check your projects.",
                detail: "Nothing was changed. Your Copilot setup above remains available."
            )
        case .loaded(let report):
            loadedProjects(report)
        }
    }

    @ViewBuilder
    private func loadedProjects(_ report: WorkspacesReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if report.discovery?.state == .notGranted {
                Text("No projects folder is selected. Control Tower is not watching any folder.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Button("Choose your projects folder…") { onManageProjects(nil) }
                    .buttonStyle(.bordered)
            } else if report.discovery?.state == .declined {
                Text("You chose not to use project setup on this Mac. You can return whenever you want.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Button("Set up projects…") { onManageProjects(nil) }
                    .buttonStyle(.bordered)
            } else if report.workspaces.isEmpty {
                Text("No projects were found in the selected folder.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Button("Review project folders…") { onManageProjects(nil) }
                    .buttonStyle(.bordered)
            } else {
                Text("\(report.summary.total) projects found. \(ProjectTriageRender.summary(report.workspaces))")
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(UserSettingsRender.projectCategories(report)) { category in
                    let count = ProjectTriageRender.workspaces(
                        report.workspaces,
                        in: category
                    ).count
                    Button {
                        onManageProjects(category)
                    } label: {
                        HStack(spacing: CTSpace.sm) {
                            Image(systemName: category.systemImage)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: CTSpace.hair) {
                                Text(category.title)
                                    .ctText(CTType.rowTitle)
                                Text(category.shortMeaning)
                                    .ctText(CTType.rowDetail)
                            }
                            Spacer()
                            // Deliberate scale break, kept as-is (spec P2-4):
                            // the count numeral stays `.title3.semibold`.
                            Text("\(count)")
                                .font(.title3.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .ctCard()
                    .accessibilityLabel("\(count), \(category.title), \(category.shortMeaning)")
                }

                VStack(alignment: .leading, spacing: CTSpace.xs) {
                    Text("Come back whenever you want")
                        .ctText(CTType.rowTitle)
                    Text("Finish one or two projects now, or return later. Every unfinished route stays available under Your projects.")
                        .ctText(CTType.rowDetail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .ctCard(.well)

                Button("Open project aftercare…") { onManageProjects(nil) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func loaded<Value>(_ state: UserSettingsLoadState<Value>) -> Value? {
        if case .loaded(let value) = state { return value }
        return nil
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CTSpace.md) {
            CTCardTitle(title)
            content()
        }
        .ctCard()
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private func checkFailed(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
                .foregroundColor(Color(nsColor: .systemOrange))
            Text(detail)
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { model.load() }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - The Connect sheet (task 222)

/// The one surface in this app that ever takes a secret VALUE from a person.
///
/// It lives here, rather than beside either caller, because BOTH connections
/// surfaces present the identical sheet — `native/wizard.swift`'s step 6 and
/// this file's own "Your connections" card. That is a deliberate exception to
/// this app's usual "shared derivation, independent views" convention: the row
/// treatments differ between a full-window wizard step and a settings card and
/// are duplicated on purpose, but a modal that handles credentials must behave
/// identically in both places, and duplicating it would mean maintaining two
/// copies of the rules below.
///
/// The rules, all of which are load-bearing:
///   - Values are held in `@State` for exactly as long as the sheet is open,
///     are passed once to `CliClient.connect` (which writes them to the child's
///     stdin and nothing else), and are cleared the moment the sheet closes.
///   - `SecureField` means the value is never rendered, never in an
///     accessibility label, and never in a screenshot.
///   - Nothing here decides whether the connection worked. The CLI re-checks
///     after writing and returns the row; `ConnectRender.outcome(for:)` reads
///     its verdict (invariant #1).
///   - Every terminal state names an actor or a self-retry, per the
///     honest-degrade floor in `docs/03-design/connect-experience-walkthrough.md`
///     §2 (HMW-3). There is no dead end on this sheet.
///
/// This sheet is the BRIDGE, not the destination: the ratified design in
/// `docs/05-security/self-service-store-provisioning.md` §5.2 removes the
/// pasted value entirely, by having the store answer to the person's own
/// GitHub team membership. It exists because a member whose organization has
/// not wired that up yet is otherwise stuck with a screen that promises a
/// Connect button and has never had one.
struct ConnectSheet: View {
    let row: ConnectionRow
    /// Called with the CLI's own re-checked row once it comes back ready — the
    /// caller refreshes from THIS row rather than assuming, and closes.
    let onConnected: (ConnectionRow) -> Void
    let onCancel: () -> Void

    @State private var values: [String: String] = [:]
    @State private var working = false
    @State private var outcome: ConnectRender.Outcome?
    /// First-field autofocus (spec §5.2: "set in `.onAppear`. Tab moves
    /// between fields in CLI order"). `String?` keyed on the credential NAME
    /// itself, never a value.
    @FocusState private var focusedField: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Every missing name, in the CLI's own order — never re-sorted, never
    /// filtered, and never a name this app decided was needed.
    private var fields: [String] { row.missing }

    private var canSubmit: Bool {
        !working && !fields.isEmpty && fields.allSatisfy { !(values[$0] ?? "").isEmpty }
    }

    /// `380 + 64 × fields.count`, clamped to 560 (spec §5.1) — replaces the
    /// prior binary `fields.count > 2 ? 560 : 470`.
    private var sheetHeight: CGFloat {
        min(380 + 64 * CGFloat(fields.count), 560)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CTSpace.xl) {
            VStack(alignment: .leading, spacing: CTSpace.hair) {
                Text("Connect \(row.name.capitalized)")
                    .ctText(CTType.sectionTitle)
                Text(row.description)
                    .ctText(CTType.lead)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Whoever set up your organization's shared store gives you these. Control Tower hands them straight to this Mac's keychain — they are never shown again, never written into a project, and never sent anywhere.")
                .ctText(CTType.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: CTSpace.lg) {
                ForEach(fields, id: \.self) { name in
                    VStack(alignment: .leading, spacing: CTSpace.xs) {
                        // The credential NAME, verbatim, never
                        // uppercase-transformed — it is data from the CLI,
                        // and monospaced so `O`/`0` and `I`/`l` stay
                        // distinguishable (spec §5.2).
                        Text(name)
                            .ctText(CTType.monoLabel)
                        SecureField("", text: binding(for: name))
                            .textFieldStyle(.roundedBorder)
                            .disabled(working)
                            .focused($focusedField, equals: name)
                            .accessibilityLabel(name)
                    }
                }
            }
            .ctCard(.well)

            if let outcome {
                outcomeView(outcome)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            HStack(spacing: CTSpace.md) {
                if working {
                    ProgressView().controlSize(.small)
                    Text("Saving these to your keychain…")
                        .ctText(CTType.body)
                }
                Spacer()
                Button { onCancel() } label: { Text("Cancel") }
                    .buttonStyle(.bordered)
                    .disabled(working)
                Button { submit() } label: { Text(outcome == nil ? "Connect" : "Try again") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(.top, CTSpace.section - CTSpace.xl)
        }
        .padding(CTSpace.section)
        .frame(width: 520, height: sheetHeight)
        .animation(reduceMotion ? CTMotion.reduced : CTMotion.normal, value: outcome)
        .onAppear { focusedField = fields.first }
    }

    /// Three outcomes, all CLI-authored, none of them a dead end, none of
    /// them red — red is reserved for `cli-unreadable` only (spec §5.4); a
    /// credential that did not take is `.attention`, because the person can
    /// act on it. Both non-empty cases render inside the same
    /// `CTCalloutNote(.attention)` / `.ctCard(.well)` shape every other
    /// honest degrade in this product uses, rather than an inline `Label`
    /// unique to this sheet.
    @ViewBuilder
    private func outcomeView(_ outcome: ConnectRender.Outcome) -> some View {
        switch outcome {
        case .connected:
            // The receipt is the row behind this sheet, never a state here
            // (spec §5.3 / G-12's celebration correction): `onConnected`
            // already fired above and the caller is about to dismiss this
            // sheet. Reached only in the instant before that happens, and
            // posts no success state at all.
            EmptyView()

        case .notConnected(let title, let details):
            CTCalloutNote(
                kind: .attention,
                lead: title,
                body: details,
                actor: "Nothing else on this Mac was changed. Check the values with whoever gave them to you, then try again."
            )
            .ctCard(.well)

        case .unreadable(let sentence):
            CTCalloutNote(
                kind: .attention,
                lead: sentence,
                actor: "You can close this and try again whenever you want."
            )
            .ctCard(.well)
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? "" },
            set: { values[name] = $0 }
        )
    }

    private func submit() {
        guard canSubmit else { return }
        working = true
        outcome = nil
        // The payload is built from the CLI's OWN `missing` names, handed to
        // `CliClient.connect` once, and dropped: `values` is cleared below
        // whatever the result, so a sheet left open after a failure never
        // still holds what was typed.
        let payload = fields.reduce(into: [String: String]()) { result, name in
            result[name] = values[name] ?? ""
        }
        Task { @MainActor in
            let result = await CliClient.shared.connect(serviceId: row.id, values: payload)
            values = [:]
            working = false
            switch result {
            case .success(let report):
                let decided = ConnectRender.outcome(for: report)
                outcome = decided
                if case .connected(let fresh) = decided { onConnected(fresh) }
            case .failure(let error):
                outcome = ConnectRender.outcome(for: error)
            }
        }
    }
}

@MainActor
final class UserSettingsWindowController: NSWindowController {
    static let shared = UserSettingsWindowController()

    private let model = UserSettingsModel()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Copilot Control Tower"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 650)
        window.center()
        window.setFrameAutosaveName("CopilotControlTowerUserSettings")
        self.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: UserSettingsView(
                model: model,
                onFinishPersonalSetup: { [weak window] in
                    window?.close()
                    WizardWindowController.shared.reopenForPersonalSetup()
                },
                onManageProjects: { [weak window] category in
                    window?.close()
                    WizardWindowController.shared.reopenForProjects(category: category)
                }
            )
        )
    }

    func show() {
        model.load()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
