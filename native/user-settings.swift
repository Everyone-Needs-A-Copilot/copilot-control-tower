//
// Copilot Control Tower — native User Settings.
//
// This is the post-onboarding home for the two setup questions a returning
// person still needs to be able to answer: which organization connections are
// actually available, and what happened across their projects. It performs
// read-only typed CLI calls on open and renders those reports without resetting
// first-run state or replaying setup.
//

import AppKit
import SwiftUI

enum UserSettingsLoadState<Value> {
    case waiting
    case loading
    case loaded(Value)
    case failed
}

struct UserSettingsProjectSummary: Equatable {
    let total: Int
    let ready: Int
    let actionable: Int
    let needsReview: Int
}

enum UserSettingsRender {
    static func isActionable(_ workspace: WorkspaceEntry) -> Bool {
        (workspace.state == .setupAvailable || workspace.state == .activationRequired)
            && workspace.canApplyNow
    }

    static func projectSummary(_ report: WorkspacesReport) -> UserSettingsProjectSummary {
        let ready = report.workspaces.filter { $0.state == .ready }.count
        let actionable = report.workspaces.filter(isActionable).count
        return UserSettingsProjectSummary(
            total: report.summary.total,
            ready: ready,
            actionable: actionable,
            needsReview: max(0, report.summary.total - ready - actionable)
        )
    }
}

@MainActor
final class UserSettingsModel: ObservableObject {
    @Published private(set) var authState: UserSettingsLoadState<AuthStatus> = .waiting
    @Published private(set) var projectsState: UserSettingsLoadState<WorkspacesReport> = .waiting

    private var isLoading = false

    /// Read-only by construction: Settings never calls an apply/configure
    /// verb merely because the window opened.
    func load() {
        guard !isLoading else { return }
        isLoading = true
        authState = .loading
        projectsState = .loading

        Task {
            async let authResult = CliClient.shared.authStatus()
            async let projectsResult = CliClient.shared.workspaces()
            let auth = await authResult
            let projects = await projectsResult

            switch auth {
            case .success(let report): self.authState = .loaded(report)
            case .failure: self.authState = .failed
            }
            switch projects {
            case .success(let report): self.projectsState = .loaded(report)
            case .failure: self.projectsState = .failed
            }
            self.isLoading = false
        }
    }
}

struct UserSettingsView: View {
    @ObservedObject var model: UserSettingsModel
    let onManageProjects: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your setup")
                        .font(.largeTitle.weight(.semibold))
                    Text("See what is connected, what is ready, and anything that needs another person to review.")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
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
        .frame(minWidth: 640, idealWidth: 700, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
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
            VStack(alignment: .leading, spacing: 16) {
                settingsGroupLabel(auth.state == .authorized ? "Ready to use" : "Needs attention")
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: auth.state == .authorized ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                        .foregroundColor(
                            auth.state == .authorized
                                ? Color(nsColor: .systemGreen)
                                : Color(nsColor: .systemOrange)
                        )
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
                .accessibilityLabel("GitHub, \(auth.state == .authorized ? "ready" : "needs sign-in"), \(githubDetail(auth))")

                Divider()

                settingsGroupLabel("Available to connect")
                Text("No additional organization connections are available in Control Tower right now.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder
    private var projectsContent: some View {
        switch model.projectsState {
        case .waiting, .loading:
            loadingRow("Checking your projects…")
        case .failed:
            checkFailed(
                title: "Control Tower couldn't check your projects.",
                detail: "Nothing was changed. Try again when the setup helper is available."
            )
        case .loaded(let report):
            loadedProjects(report)
        }
    }

    @ViewBuilder
    private func loadedProjects(_ report: WorkspacesReport) -> some View {
        let summary = UserSettingsRender.projectSummary(report)
        let actionable = report.workspaces.filter(UserSettingsRender.isActionable)
        let needsReview = report.workspaces.filter {
            $0.state != .ready && !UserSettingsRender.isActionable($0)
        }
        let ready = report.workspaces.filter { $0.state == .ready }

        VStack(alignment: .leading, spacing: 14) {
            if report.discovery?.state == .notGranted {
                Text("No projects folder is selected. Control Tower is not watching any folder.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose your projects folder…", action: onManageProjects)
                    .buttonStyle(.bordered)
            } else if report.discovery?.state == .declined {
                Text("You chose not to use project setup on this Mac.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Button("Set up projects…", action: onManageProjects)
                    .buttonStyle(.bordered)
            } else if report.workspaces.isEmpty {
                Text("No projects were found in the selected folder. New projects there can receive your copilots automatically.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    "\(summary.total) projects found: \(summary.ready) already set up, "
                        + "\(summary.actionable) available to set up now, and "
                        + "\(summary.needsReview) need review."
                )
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(
                        "\(summary.total) projects found. \(summary.ready) already set up. "
                            + "\(summary.actionable) available to set up now. "
                            + "\(summary.needsReview) need review."
                    )

                if !actionable.isEmpty {
                    settingsGroupLabel("Available to set up")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(actionable) { workspace in
                            projectRow(workspace, status: ProjectRowRender.caption(for: workspace), needsReview: false)
                            if workspace.id != actionable.last?.id { Divider() }
                        }
                    }
                    Button("Choose projects to set up…", action: onManageProjects)
                        .buttonStyle(.bordered)
                }

                if !needsReview.isEmpty {
                    DisclosureGroup("\(needsReview.count) need review") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(needsReview) { workspace in
                                projectRow(workspace, status: ProjectRowRender.caption(for: workspace), needsReview: true)
                                if workspace.id != needsReview.last?.id { Divider() }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.callout.weight(.semibold))

                    Text("Control Tower left these projects unchanged. The reason under each project tells you what the person who manages it needs to review.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !ready.isEmpty {
                    DisclosureGroup("\(ready.count) already set up") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(ready) { workspace in
                                projectRow(workspace, status: "Already set up.", needsReview: false)
                                if workspace.id != ready.last?.id { Divider() }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.callout.weight(.semibold))
                }
            }
        }
    }

    private func projectRow(_ workspace: WorkspaceEntry, status: String, needsReview: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: needsReview ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundColor(
                    needsReview
                        ? Color(nsColor: .systemOrange)
                        : Color(nsColor: .secondaryLabelColor)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.callout.weight(.semibold))
                Text(status)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if needsReview {
                Text("Needs review")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            needsReview
                ? "\(workspace.name), needs review, \(status)"
                : "\(workspace.name), \(status)"
        )
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

    private func settingsGroupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
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
        .accessibilityElement(children: .contain)
    }
}

@MainActor
final class UserSettingsWindowController: NSWindowController {
    static let shared = UserSettingsWindowController()

    private let model = UserSettingsModel()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Copilot Control Tower Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("CopilotControlTowerUserSettings")
        self.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: UserSettingsView(
                model: model,
                onManageProjects: { [weak window] in
                    window?.close()
                    WizardWindowController.shared.reopenForProjects()
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
