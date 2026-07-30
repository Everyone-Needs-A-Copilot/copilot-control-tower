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

    var color: NSColor {
        switch self {
        case .ready: return .systemGreen
        case .needsSetup: return .systemBlue
        case .needsAttention: return .systemOrange
        case .notJoined, .couldNotCheck: return .secondaryLabelColor
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
                aliases: ["foundation"],
                doctor: doctor
            )
            let organization = checkerTier(
                component: component,
                layer: .org,
                aliases: ["org", "organization", "org-internal"],
                doctor: doctor
            )
            let department = checkerTier(
                component: component,
                layer: .dept,
                aliases: ["dept", "department"],
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
        aliases: Set<String>,
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
                && $0.layer.map { layerName in
                    aliases.contains(layerName)
                        || aliases.contains(where: { layerName.hasSuffix("-\($0)") })
                } == true
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

        Task {
            async let authResult = CliClient.shared.authStatus()
            async let doctorResult = CliClient.shared.doctor()
            async let personalResult = CliClient.shared.onboardPlan(
                components: UserSettingsComponent.allCases.map(\.rawValue)
            )
            async let layersResult = CliClient.shared.layers()
            async let projectsResult = CliClient.shared.workspaces()

            let auth = await authResult
            let doctor = await doctorResult
            let personal = await personalResult
            let layers = await layersResult
            let projects = await projectsResult

            authState = auth.loadedState
            doctorState = doctor.loadedState
            personalState = personal.loadedState
            layersState = layers.loadedState
            projectsState = projects.loadedState
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
    }

    @ViewBuilder
    private var setupHeader: some View {
        switch model.personalState {
        case .waiting, .loading:
            VStack(alignment: .leading, spacing: 6) {
                Text("Your setup")
                    .font(.largeTitle.weight(.semibold))
                loadingRow("Checking your Personal setup…")
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text("Your setup")
                    .font(.largeTitle.weight(.semibold))
                Text("Control Tower couldn't check whether Personal setup is complete.")
                    .font(.title3.weight(.semibold))
                Text("Nothing was changed, and Control Tower will not call the ecosystem ready without that report.")
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Button("Try again") { model.load() }
                    .buttonStyle(.bordered)
            }
        case .loaded(let personal):
            let ready = UserSettingsRender.personalReadyCount(personal)
            let needsAction = UserSettingsRender.personalNeedsAction(personal)
            VStack(alignment: .leading, spacing: 8) {
                Text("Your setup")
                    .font(.largeTitle.weight(.semibold))
                Text(needsAction
                    ? "Your copilots work, but Personal setup is incomplete"
                    : "Your ecosystem is ready")
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(needsAction
                    ? "\(ready) of 4 Personal components are ready. Finish the others now or return here later."
                    : "Knowledge, CLI, Claude, and Codex have verified Personal spaces. Department setup remains optional.")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                if needsAction {
                    Button("Finish Personal Setup", action: onFinishPersonalSetup)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private var copilotsContent: some View {
        if case .loading = model.personalState {
            loadingRow("Checking Knowledge, CLI, Claude, and Codex…")
        } else if case .waiting = model.personalState {
            loadingRow("Checking Knowledge, CLI, Claude, and Codex…")
        } else {
            let statuses = UserSettingsRender.componentStatuses(
                doctor: loaded(model.doctorState),
                personal: loaded(model.personalState),
                layers: loaded(model.layersState)
            )
            VStack(alignment: .leading, spacing: 10) {
                Text("Each Copilot has the same four tiers. Personal is yours; its repository is private.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
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
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: component.overallKind.symbol)
                    .foregroundColor(Color(nsColor: component.overallKind.color))
                    .accessibilityHidden(true)
                Text(component.id.label)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(component.overall)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: component.overallKind.color))
            }
            .contentShape(Rectangle())
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("\(component.id.label), \(component.overall)")
    }

    private func tierRow(_ tier: UserSettingsTierStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tier.kind.symbol)
                .foregroundColor(Color(nsColor: tier.kind.color))
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.label)
                    .font(.caption.weight(.semibold))
                Text(tier.detail)
                    .font(.caption2)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(tier.state)
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: tier.kind.color))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
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
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: auth.state == .authorized
                    ? "checkmark.circle.fill"
                    : "person.crop.circle.badge.exclamationmark")
                    .foregroundColor(Color(nsColor: auth.state == .authorized
                        ? .systemGreen
                        : .systemOrange))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub")
                        .font(.callout.weight(.semibold))
                    Text(githubDetail(auth))
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
                Text(auth.state == .authorized ? "Ready" : "Needs sign-in")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .accessibilityElement(children: .combine)
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
                        HStack(spacing: 10) {
                            Image(systemName: category.systemImage)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                    .font(.callout.weight(.semibold))
                                Text(category.shortMeaning)
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            }
                            Spacer()
                            Text("\(count)")
                                .font(.title3.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("\(count), \(category.title), \(category.shortMeaning)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Come back whenever you want")
                        .font(.callout.weight(.semibold))
                    Text("Finish one or two projects now, or return later. Every unfinished route stays available under Your projects.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
