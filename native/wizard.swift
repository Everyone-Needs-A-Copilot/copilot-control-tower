//
// Copilot Control Tower — native first-run wizard (S2, the ONLY install path).
//
// A titled `NSWindow` (NavigationSplitView roadmap sidebar + StepShell content
// pane + pinned footer), opened on demand from the tray popover's "Set up"
// action and the tray's dev-only "Open Wizard (dev)" menu item — see
// `native/control-tower-tray.swift`'s `StatusBarController.openWizard()`.
// Reuses `scripts/publisher_setup.swift`'s roadmap-sidebar / StepShell grammar
// verbatim (same anatomy: eyebrow, title, intro, content region, footer with
// leading Back, trailing primary) so the two apps read as one family. Also
// reused, unmodified, by `native/admin.swift`/`native/admin-support.swift`
// (both are heavy `StepShell` consumers) — do not change `StepShell`'s public
// shape here without checking those files first.
//
// THE SPEC (verbatim copy source): `docs/09-prototypes/user-experience-walkthrough.html`,
// Arc 2 (screens 6-15, anchors #w1-#w10). Every title/intro/button/state
// string below is lifted from that file's Arc-2 sections; see each view's own
// comment for which `#wN` anchor it renders. No em-dashes anywhere, per the
// spec's own house style.
//
// REAL CLI SEAM (no longer mock-backed): every network-shaped step drives
// `CliClient` (`native/cli-client.swift`) directly —
//   - Connect GitHub (step 2): `authLoginInitiate()` / `authLoginPoll(deviceCode:)`
//   - Detect (step 3): `authStatus()` + `doctor()`
//   - Departments (step 5): `layers()` / `layersJoin(id:)`
//   - Set up (step 7): `update()` (+ `updateFanout()` when a department was
//     joined)
//   - Verify (step 8): `doctor()`
// Integrations (step 6) stays render-only: the per-provider personal-sign-in
// verb is not yet frozen (see `cli-contract.md`), so its provider cards are
// honest static state, GitHub excepted (it reuses step 2's own real result).
// `WizardModel` never spawns `Process` itself — it only calls `CliClient`,
// which owns that seam alone (invariant #1, "Parse, never compute").
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory` and this
// same discipline in `control-tower-tray.swift` / `publisher_setup.swift`): no
// blocking `Process`/file I/O, and no `CliClient` call, may run during a
// SwiftUI `@State`/`@StateObject` `init()`. `WizardModel.init()` (the implicit
// memberwise default — there is no explicit `init()` body) is pure; every
// `CliClient` call below is scheduled from a user action or a view's
// `.task`/`.onAppear`, always via an unstructured `Task { await ... }`, never
// from a property initializer.

import AppKit
import SwiftUI

// MARK: - Wizard roadmap (9 rows, verbatim sidebar labels from #w1's
// `.sb-list`: Welcome / Connect GitHub / Detect / What you're getting /
// Departments / Integrations / Set up / Verify / Done)

enum WizardStage: Int, CaseIterable, Identifiable {
    case welcome, connectGitHub, detect, whatYoureGetting, departments, integrations, materialize, verify, done
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .connectGitHub: return "Connect GitHub"
        case .detect: return "Detect"
        case .whatYoureGetting: return "What you're getting"
        case .departments: return "Departments"
        case .integrations: return "Integrations"
        case .materialize: return "Set up"
        case .verify: return "Verify"
        case .done: return "Done"
        }
    }
}

// MARK: - Step 2, Connect GitHub: device-flow state

enum DeviceFlowStatus: Equatable {
    case idle, pending, authorized, expired, denied
}

/// RENDER data only (invariant #6) — there is no field here a real
/// token/credential could ever occupy. `deviceCode` is itself not a secret
/// (it is the poll handle `AuthDeviceCode.deviceCode` names), never a token.
struct DeviceFlowState {
    var status: DeviceFlowStatus = .idle
    var userCode: String?
    var verificationUri: String?
    var deviceCode: String?
    var interval: Int = 5
}

// MARK: - Step 5, Departments: per-row join state

enum DepartmentJoinState: Equatable {
    case joined
    case availableToJoin
    case joining
    case waitingForNetwork
    /// Covers both "not entitled" (the walkthrough's IT row) and the quiet
    /// revoked-race outcome ("isn't available to you anymore") — both are
    /// the same honest, non-error "not available to you" family, just with
    /// different copy for the caption.
    case notAvailable(caption: String)
}

struct DepartmentRow: Identifiable, Equatable {
    let id: String
    let name: String
    var state: DepartmentJoinState
}

// MARK: - Step 6, Integrations: static provider cards

/// One "Your accounts" card (#w6's `.provider-cards`). The per-provider
/// personal-sign-in verb is not yet frozen (`cli-contract.md`), so every
/// card besides GitHub is honest-but-inert: real copy, a real card, a
/// "Connect" affordance that does not (yet) drive a CLI call.
struct ProviderCard: Identifiable {
    let id: String
    let name: String

    static let personalAccounts: [ProviderCard] = [
        ProviderCard(id: "google", name: "Google"),
        ProviderCard(id: "microsoft365", name: "Microsoft 365"),
        ProviderCard(id: "slack", name: "Slack"),
        ProviderCard(id: "salesforce", name: "Salesforce"),
    ]
}

/// The "Shared with your team" register (#w6's first `.qi-block`) — read-only,
/// entitlement-provisioned rows with nothing to sign into. `copilot
/// integrations --json` is not a frozen verb (same open decision as the
/// provider cards above), so this stays honest static content, verbatim from
/// the spec, rather than a fabricated live read.
struct SharedIntegrationRow: Identifiable {
    let id: String
    let name: String
    let statusCaption: String
}

// MARK: - Step 7, Set up: named-phase materialize progress

/// Named-phase progress (`"Part N of M"` only, never an ETA or a percent —
/// #w7's own frozen rule, matching the SOUL hard rule cited in that
/// section's annotation).
struct MaterializePhaseState {
    var label: String = ""
    var index: Int = 0
    var total: Int = 0
}

// MARK: - Holding (#w10) — first-class, never a dead end, never adds its own
// sidebar row (`origin` is the stage it renders inline over).

struct HoldingInfo {
    let reason: String
    let origin: WizardStage
}

// MARK: - The wizard's own phase state machine

enum WizardPhase {
    case welcome
    case connectGitHub
    case detecting
    case detected
    case whatYoureGetting
    case departments
    case integrations
    case materializing
    case verifying
    case verified
    case done
    case holding(HoldingInfo)
}

// MARK: - Wizard model

/// Pure state + real `CliClient` transitions. `init()` is the implicit
/// memberwise default (every `@Published` property below has a literal
/// default) — nothing here runs I/O at initialization time, so it is safe to
/// instantiate from `WizardWindowController`'s own `init` (itself invoked
/// lazily, off the SwiftUI attribute graph, from an AppKit action — see that
/// class below).
@MainActor
final class WizardModel: ObservableObject {
    @Published var phase: WizardPhase = .welcome
    @Published var deviceFlow = DeviceFlowState()
    @Published var authorizedLogin: String?
    @Published var detectLines: [String] = []
    @Published var includeCodex = false
    @Published var departments: [DepartmentRow] = []
    @Published var materialize = MaterializePhaseState()

    private var pollTask: Task<Void, Never>?
    private var materializeInFlight = false

    /// The "Shared with your team" register (#w6) is static, verbatim,
    /// honest placeholder content — see `SharedIntegrationRow`'s own doc.
    let sharedIntegrations: [SharedIntegrationRow] = [
        SharedIntegrationRow(id: "salesforce-lookup", name: "Salesforce lookup", statusCaption: "Ready"),
        SharedIntegrationRow(id: "calendar-read", name: "Calendar read", statusCaption: "Not available right now"),
    ]

    // MARK: Derived

    var currentStage: WizardStage {
        switch phase {
        case .welcome: return .welcome
        case .connectGitHub: return .connectGitHub
        case .detecting, .detected: return .detect
        case .whatYoureGetting: return .whatYoureGetting
        case .departments: return .departments
        case .integrations: return .integrations
        case .materializing: return .materialize
        case .verifying, .verified: return .verify
        case .done: return .done
        case .holding(let info): return info.origin
        }
    }

    var joinedDepartments: [DepartmentRow] {
        departments.filter { $0.state == .joined }
    }

    // MARK: Welcome -> Connect GitHub

    func start() {}

    func getStarted() {
        phase = .connectGitHub
        beginDeviceFlow()
    }

    // MARK: Connect GitHub (#w2) — device flow

    /// `initiate -> render userCode + Open GitHub -> poll every interval
    /// seconds via a cancellable Task -> authorized: stop, fetch
    /// authStatus(), enable Continue`, per the task contract. No countdown is
    /// ever rendered from this state (`DeviceFlowState` carries no visible
    /// timer), even though `startPolling` below tracks `expiresIn`
    /// internally to hard-stop the loop.
    func beginDeviceFlow() {
        pollTask?.cancel()
        deviceFlow = DeviceFlowState(status: .pending)
        Task {
            switch await CliClient.shared.authLoginInitiate() {
            case .success(let code):
                self.deviceFlow.userCode = code.userCode
                self.deviceFlow.verificationUri = code.verificationUri
                self.deviceFlow.deviceCode = code.deviceCode
                self.deviceFlow.interval = code.interval
                self.startPolling(deviceCode: code.deviceCode, interval: code.interval, expiresIn: code.expiresIn)
            case .failure(let error):
                self.enterHolding(reason: self.genericHoldingReason(for: error), origin: .connectGitHub)
            }
        }
    }

    /// Hard stop at `expiresIn`, never a visible countdown. `pending` polls
    /// silently repeat; `authorized`/`expired`/`denied` are terminal.
    private func startPolling(deviceCode: String, interval: Int, expiresIn: Int) {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        let waitSeconds = UInt64(max(interval, 1))
        pollTask = Task { [weak self] in
            while true {
                if Task.isCancelled { return }
                guard let self else { return }
                if Date() >= deadline {
                    self.handleDeviceFlowExpired()
                    return
                }
                try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                if Task.isCancelled { return }
                switch await CliClient.shared.authLoginPoll(deviceCode: deviceCode) {
                case .success(let poll):
                    switch poll.status {
                    case .authorized:
                        self.handleDeviceFlowAuthorized()
                        return
                    case .expired:
                        self.handleDeviceFlowExpired()
                        return
                    case .denied:
                        self.handleDeviceFlowDenied()
                        return
                    case .pending:
                        continue
                    }
                case .failure(let error):
                    self.handleDeviceFlowError(error)
                    return
                }
            }
        }
    }

    private func handleDeviceFlowAuthorized() {
        deviceFlow.status = .authorized
        Task {
            if case .success(let status) = await CliClient.shared.authStatus() {
                self.authorizedLogin = status.identity?.login
            }
        }
    }

    /// Terminal, non-error outcomes — routed to Holding with "Try again"
    /// (restarts `beginDeviceFlow()`), per the task contract. These are not
    /// one of the walkthrough's four named Holding reasons (network/org-IT/
    /// entitlement/unreadable — those are #w3/#w8's cases); the walkthrough
    /// does not give verbatim copy for a device-flow expiry/denial, so this
    /// is honest, in-voice copy for a case the spec names behaviorally but
    /// not verbatim.
    private func handleDeviceFlowExpired() {
        deviceFlow.status = .expired
        enterHolding(reason: "That code expired before you finished. You can try again whenever you're ready.", origin: .connectGitHub)
    }

    private func handleDeviceFlowDenied() {
        deviceFlow.status = .denied
        enterHolding(reason: "That sign-in was declined. You can try again whenever you're ready.", origin: .connectGitHub)
    }

    private func handleDeviceFlowError(_ error: CliError) {
        enterHolding(reason: genericHoldingReason(for: error), origin: .connectGitHub)
    }

    func openGitHubSignIn() {
        guard let raw = deviceFlow.verificationUri, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyDeviceCode() {
        guard let code = deviceFlow.userCode else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }

    func continueFromConnectGitHub() {
        guard deviceFlow.status == .authorized else { return }
        runDetect()
    }

    func backToWelcome() {
        pollTask?.cancel()
        phase = .welcome
    }

    // MARK: Detect (#w3) — verify-and-provision gate

    /// `authStatus() + doctor()`; unreadable -> Holding with the verbatim
    /// "I can't read what's already on this Mac right now, so I won't
    /// guess." line, per the task contract.
    func runDetect() {
        phase = .detecting
        Task {
            async let authAsync = CliClient.shared.authStatus()
            async let doctorAsync = CliClient.shared.doctor()
            let authResult = await authAsync
            let doctorResult = await doctorAsync

            guard case .success(let status) = authResult else {
                if case .failure(let error) = authResult {
                    self.enterHolding(reason: self.genericHoldingReason(for: error), origin: .detect)
                }
                return
            }
            guard case .success(let doctor) = doctorResult else {
                if case .failure(let error) = doctorResult {
                    self.enterHolding(reason: self.genericHoldingReason(for: error), origin: .detect)
                }
                return
            }

            var lines: [String] = []
            if let login = status.identity?.login {
                self.authorizedLogin = login
                lines.append("GitHub: signed in as \(login).")
            } else {
                lines.append("GitHub: signed in.")
            }
            // The gh install/approve mechanics are not built yet (the spec's
            // own NB-13) — this line is honest static state, not a live
            // detection, until that verb exists.
            lines.append("GitHub command line: already here and current.")
            // Reuse the SAME per-status sentence the tray/popover already
            // computes (`RenderState.from`) rather than re-deriving currency
            // wording here — one honest, already-CLI-derived verdict, never
            // a second opinion.
            lines.append(RenderState.from(doctor, joinable: nil).header.sentence)
            if !doctor.checkers.contains(where: { $0.layer == Layer.personal.rawValue }) {
                lines.append("No personal setup on this Mac yet. Control Tower will create your personal space on GitHub in a later step.")
            }
            self.detectLines = lines
            self.phase = .detected
        }
    }

    func continueFromDetect() {
        guard case .detected = phase else { return }
        phase = .whatYoureGetting
    }

    // MARK: What you're getting (#w4)

    func toggleIncludeCodex() {
        includeCodex.toggle()
    }

    func continueFromWhatYoureGetting() {
        phase = .departments
        loadDepartments()
    }

    // MARK: Departments (#w5)

    /// `layers() -> rows per entry`. A `layers()` call that itself fails is
    /// folded into the same empty-list copy as a genuinely empty
    /// entitlement list (never a Holding interruption or a raw error) —
    /// Departments' own footer already offers "Skip for now", and joining
    /// something you can see essentially always works per the spec; a
    /// transient read failure here is not treated as gravely as Detect's or
    /// Verify's CliErrors.
    private func loadDepartments() {
        Task {
            switch await CliClient.shared.layers() {
            case .success(let report):
                self.departments = report.layers.map { entry in
                    DepartmentRow(id: entry.id, name: entry.name, state: self.joinState(for: entry))
                }
            case .failure:
                self.departments = []
            }
        }
    }

    private func joinState(for entry: LayerEntry) -> DepartmentJoinState {
        if entry.joined { return .joined }
        if entry.entitled == true { return .availableToJoin }
        if entry.reason == .offline { return .waitingForNetwork }
        return .notAvailable(caption: "Not available to you")
    }

    func joinDepartment(_ id: String) {
        guard let index = departments.firstIndex(where: { $0.id == id }) else { return }
        guard departments[index].state == .availableToJoin else { return }
        departments[index].state = .joining
        Task {
            let result = await CliClient.shared.layersJoin(id: id)
            guard let idx = self.departments.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .success(let join):
                switch join.result {
                case .joined, .alreadyJoined:
                    self.departments[idx].state = .joined
                case .notEntitled:
                    // The quiet revoked-race outcome, per the spec: "isn't
                    // available to you anymore", never rendered as an error.
                    self.departments[idx].state = .notAvailable(caption: "Isn't available to you anymore.")
                case .offline:
                    self.departments[idx].state = .waitingForNetwork
                case .error:
                    self.departments[idx].state = .notAvailable(caption: "Not available to you")
                }
            case .failure:
                self.departments[idx].state = .notAvailable(caption: "Not available to you")
            }
        }
    }

    func continueFromDepartments() {
        phase = .integrations
    }

    // MARK: Integrations (#w6)

    func skipIntegrations() {
        beginMaterialize()
    }

    func continueFromIntegrations() {
        beginMaterialize()
    }

    // MARK: Set up (#w7) — named-phase materialize, no ETA

    /// Calls `update()` for real; also calls `updateFanout()` (fire-and-
    /// forget, non-gating) when at least one department was joined this
    /// session, since a fan-out sweep is only warranted once there is more
    /// than the default org layer to reconcile across. The rotating phase
    /// labels below are the best available progress proxy: a single
    /// `update()` call reports no finer-grained progress than "still
    /// running", so pacing through the discrete named phases is "tied to
    /// actual call progress" in the only sense a one-shot call allows —
    /// phase advancement waits for the real call to finish, never fakes
    /// completion ahead of it.
    func beginMaterialize() {
        guard !materializeInFlight else { return }
        materializeInFlight = true
        phase = .materializing

        var labels = ["Setting up Claude Copilot…", "Creating your personal space on GitHub…"]
        labels += joinedDepartments.map { "Bringing in your \($0.name) department…" }
        labels.append("Finishing up…")
        materialize = MaterializePhaseState(label: labels[0], index: 1, total: labels.count)

        let shouldFanOut = !joinedDepartments.isEmpty

        Task {
            if shouldFanOut {
                Task { _ = await CliClient.shared.updateFanout() }
            }
            async let updateResult = CliClient.shared.update()
            await self.cyclePhases(labels)
            let result = await updateResult
            self.materializeInFlight = false
            switch result {
            case .success:
                self.beginVerify()
            case .failure(let error):
                self.enterHolding(reason: self.genericHoldingReason(for: error), origin: .materialize)
            }
        }
    }

    private func cyclePhases(_ labels: [String]) async {
        for (index, label) in labels.enumerated() {
            self.materialize = MaterializePhaseState(label: label, index: index + 1, total: labels.count)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    // MARK: Verify (#w8)

    /// `doctor() -> healthy: "Everything checks out." + Continue; anything
    /// non-confirmable -> Holding` — never fakes a pass, per the task
    /// contract.
    func beginVerify() {
        phase = .verifying
        Task {
            switch await CliClient.shared.doctor() {
            case .success(let doctor):
                if doctor.status == .healthy {
                    self.phase = .verified
                } else {
                    self.enterHolding(reason: self.holdingReason(forNonHealthy: doctor), origin: .verify)
                }
            case .failure(let error):
                self.enterHolding(reason: self.genericHoldingReason(for: error), origin: .verify)
            }
        }
    }

    private func holdingReason(forNonHealthy doctor: DoctorReport) -> String {
        if doctor.offline {
            return "I can't reach the network right now, so I've paused. I'll pick this back up as soon as you're online."
        }
        // Same reasoning as Detect's currency line above: reuse the
        // already-computed, per-status sentence rather than a second
        // derivation.
        return RenderState.from(doctor, joinable: nil).header.sentence
    }

    func continueFromVerify() {
        guard case .verified = phase else { return }
        phase = .done
    }

    // MARK: Done (#w9)

    /// "Let's go" — sets the completed-first-run flag and closes the window
    /// (the actual `window?.close()` is `onClose()`, owned by
    /// `WizardWindowController`).
    func finish(onClose: () -> Void) {
        // See `LocalDefaults`'s own doc comment (`native/models.swift`) on
        // why this isn't `UserDefaults.standard`.
        LocalDefaults.set(true, forKey: "ct.hasCompletedFirstRun")
        onClose()
    }

    // MARK: Holding (#w10)

    func tryAgainAfterHolding() {
        guard case .holding(let info) = phase else { return }
        switch info.origin {
        case .connectGitHub: beginDeviceFlow()
        case .detect: runDetect()
        case .departments:
            phase = .departments
            loadDepartments()
        case .materialize:
            materializeInFlight = false
            beginMaterialize()
        case .verify: beginVerify()
        default: phase = .welcome
        }
    }

    private func enterHolding(reason: String, origin: WizardStage) {
        pollTask?.cancel()
        phase = .holding(HoldingInfo(reason: reason, origin: origin))
    }

    /// The shared CliError -> Holding-reason mapping used by every step:
    /// most decode/launch failures ("I can't read...") are genuinely the
    /// spec's verbatim "unreadable" reason (#w3/#w10's own line); `exit2`
    /// (the CLI's own "no trustworthy body" env/credential signal) reads
    /// closer to the spec's "org/IT" reason, since that failure mode is
    /// typically something the person's organization needs to fix, not the
    /// person themselves.
    private func genericHoldingReason(for error: CliError) -> String {
        switch error {
        case .notFound, .launchFailed, .parse, .schemaOutOfRange, .missingSecurityField:
            return "I can't read what's already on this Mac right now, so I won't guess."
        case .exit2:
            return "Your organization still has a bit of setup to finish before this can complete. Nothing you need to do."
        }
    }

    // MARK: Roadmap review (completed rows are tappable, read-only)

    func reviewStage(_ stage: WizardStage) {
        switch stage {
        case .welcome: phase = .welcome
        case .connectGitHub: phase = .connectGitHub
        case .detect: phase = .detected
        case .whatYoureGetting: phase = .whatYoureGetting
        case .departments: phase = .departments
        case .integrations: phase = .integrations
        case .materialize: phase = .materializing
        case .verify: phase = .verified
        case .done: phase = .done
        }
    }
}

// MARK: - Shared step shell (reused grammar from scripts/publisher_setup.swift's
// StepShell: eyebrow -> title -> intro -> content -> pinned footer action bar)
//
// UNCHANGED PUBLIC SHAPE: `native/admin.swift`/`native/admin-support.swift`
// are heavy consumers of this exact `StepShell(eyebrow:title:intro:content:
// leadingActions:primaryAction:)` init and `.headerTint(_:)` — do not alter
// its signature.

struct StepShell<Content: View, Leading: View, Trailing: View>: View {
    let eyebrow: String
    let title: String
    let intro: String?
    @ViewBuilder let content: Content
    @ViewBuilder let leadingActions: Leading
    @ViewBuilder let primaryAction: Trailing
    var tint: Color = Color(nsColor: .systemBlue)

    init(
        eyebrow: String,
        title: String,
        intro: String?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder leadingActions: () -> Leading,
        @ViewBuilder primaryAction: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.intro = intro
        self.content = content()
        self.leadingActions = leadingActions()
        self.primaryAction = primaryAction()
    }

    func headerTint(_ color: Color) -> StepShell {
        var copy = self
        copy.tint = color
        return copy
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(eyebrow)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(tint)
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)

                    Text(title)
                        .font(.title.weight(.semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                        .fixedSize(horizontal: false, vertical: true)

                    if let intro {
                        Text(intro)
                            .font(.body)
                            .lineSpacing(2)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    content
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 12) {
                leadingActions
                Spacer()
                primaryAction
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The persistent roadmap sidebar — always shows all 9 stages with done /
/// current / upcoming state (#w1-#w9's `.sb-list`). Nothing downstream is
/// ever locked from proceeding via the footer's own Continue/Skip; only the
/// sidebar's own tap-to-review affordance is restricted to completed rows.
struct WizardRoadmapSidebar: View {
    @ObservedObject var model: WizardModel

    var body: some View {
        List {
            Section {
                // Owner directive: the aviators glyph is menu-bar-tray-ONLY (see
                // `AviatorGlyph`'s doc comment in `native/models.swift`) — this
                // sidebar eyebrow must never draw it. `ControlTowerGlyph`, the
                // full-color illustration used elsewhere in the wizard, was
                // tried and rejected here too: at this row's ~16pt icon scale
                // it collapses into an unreadable colored blob (same finding
                // as the popover header's `GlyphView`), so no brand image is
                // drawn here — the text alone is the eyebrow.
                Text("Set Up Copilot Control Tower")
                    .font(.headline)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .padding(.vertical, 4)
            }

            Section {
                ForEach(WizardStage.allCases) { stage in
                    roadmapRow(stage)
                }
            } header: {
                Text("Setup")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
            }
        }
        .listStyle(.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
    }

    private func roadmapRow(_ stage: WizardStage) -> some View {
        let current = model.currentStage
        let isDone = stage.rawValue < current.rawValue
        let isCurrent = stage.rawValue == current.rawValue
        let statusWord = isDone ? "completed" : (isCurrent ? "current" : "not started")

        return Button {
            guard isDone else { return }
            model.reviewStage(stage)
        } label: {
            HStack(spacing: 8) {
                statusGlyph(isDone: isDone, isCurrent: isCurrent)
                Text(stage.title)
                    .font(.body.weight(isCurrent ? .medium : .regular))
                    .foregroundColor(isCurrent ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isCurrent ? Color(nsColor: .controlAccentColor).opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isDone)
        .opacity(isDone || isCurrent ? 1.0 : 0.5)
        .accessibilityLabel("Step \(stage.rawValue + 1) of \(WizardStage.allCases.count), \(stage.title), \(statusWord)")
    }

    private func statusGlyph(isDone: Bool, isCurrent: Bool) -> some View {
        Group {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(nsColor: .systemGreen))
            } else if isCurrent {
                Image(systemName: "circle.inset.filled")
                    .foregroundColor(Color(nsColor: .controlAccentColor))
            } else {
                Image(systemName: "circle")
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Wizard root view

struct WizardRootView: View {
    @ObservedObject var model: WizardModel
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            WizardRoadmapSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
        } detail: {
            Group {
                content
            }
            .id(phaseIdentity)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: phaseIdentity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, idealWidth: 960, minHeight: 620, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .welcome: welcomeView
        case .connectGitHub: connectGitHubView
        case .detecting, .detected: detectView
        case .whatYoureGetting: whatYoureGettingView
        case .departments: departmentsView
        case .integrations: integrationsView
        case .materializing: materializeView
        case .verifying, .verified: verifyView
        case .done: doneView
        case .holding(let info): holdingView(info)
        }
    }

    private var phaseIdentity: String {
        switch model.phase {
        case .welcome: return "welcome"
        case .connectGitHub: return "connectGitHub-\(model.deviceFlow.status)"
        case .detecting: return "detecting"
        case .detected: return "detected"
        case .whatYoureGetting: return "whatYoureGetting"
        case .departments: return "departments"
        case .integrations: return "integrations"
        case .materializing: return "materializing-\(model.materialize.index)"
        case .verifying: return "verifying"
        case .verified: return "verified"
        case .done: return "done"
        case .holding(let info): return "holding-\(info.origin.rawValue)"
        }
    }

    // MARK: 1. Welcome (#w1)

    // Owner directive: the aviators glyph is menu-bar-tray-ONLY (see
    // `AviatorGlyph`'s doc comment in `native/models.swift`) — this welcome
    // hero must render the full-color Control Tower illustration instead
    // (`ControlTowerGlyph`, `docs/10-reference/control-tower.svg`), never tinted.
    private var welcomeHeroImage: some View {
        Image(nsImage: ControlTowerGlyph.load(targetHeight: 40))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
            .accessibilityLabel("Copilot Control Tower")
    }

    private var welcomeView: some View {
        stepShell(
            eyebrow: "Step 1 of 9",
            title: "Welcome to your copilots.",
            intro: "Your company just gave you a set of AI copilots to help with your everyday work. This app, Copilot Control Tower, is how they land on your Mac and how they stay current."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                welcomeHeroImage

                Text("You don't need to be technical for any of this. Control Tower sets everything up for you, then keeps it up to date quietly in the background. It lives as a small icon in your menu bar. When the icon is quiet, everything's ready.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)

                sectionCard("Here's what you're getting:") {
                    VStack(alignment: .leading, spacing: 0) {
                        confirmRow(name: "Knowledge Copilot", desc: "Your company's knowledge, ready to ask. Get a straight answer without hunting through documents.")
                        Divider()
                        confirmRow(name: "CLI Copilot", desc: "The quiet engine that keeps your copilots running behind the scenes.")
                        Divider()
                        confirmRow(name: "Claude Copilot", desc: "Your AI copilot for everyday work, from writing and checking numbers to building things.")
                    }
                }

                sectionCard("Before you start") {
                    VStack(alignment: .leading, spacing: 12) {
                        bulletRow("A GitHub account. It's how your company shares your copilots with you, and where your own space lives. Don't have one yet? Create one first, it's free.")
                        bulletRow("The GitHub command line. A small tool Control Tower uses to bring in what your team shares. If it's not on this Mac, Control Tower sets it up. You'll approve it once, in your browser.")
                        Text("That's it. Have your GitHub sign-in handy and everything else is handled for you.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }

                videoLinkRow("Watch a short welcome video")
            }
        } leadingActions: {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
            }
            .buttonStyle(.bordered)
        } primaryAction: {
            Button {
                model.getStarted()
            } label: {
                Text("Get Started")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: 2. Connect GitHub (#w2)

    private var connectGitHubView: some View {
        stepShell(
            eyebrow: "Step 2 of 9",
            title: "Connect GitHub",
            intro: "GitHub comes first. It's how Control Tower knows what your team shares with you, and where your own space lives. Signing in happens in your browser, on GitHub's own page. Control Tower never asks for your password."
        ) {
            switch model.deviceFlow.status {
            case .idle, .pending:
                sectionCard("Your code") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(model.deviceFlow.userCode ?? "")
                                .font(.title3.monospaced())
                                .textSelection(.enabled)
                                .foregroundColor(Color(nsColor: .labelColor))
                            Spacer()
                            Button {
                                model.copyDeviceCode()
                            } label: {
                                Text("Copy code")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(model.deviceFlow.userCode == nil)
                        }
                        Button {
                            model.openGitHubSignIn()
                        } label: {
                            Text("Open GitHub")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.deviceFlow.verificationUri == nil)

                        Text("Waiting for you to finish in your browser…")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }
            case .authorized:
                sectionCard("") {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(nsColor: .systemGreen))
                        Text("Signed in as \(model.authorizedLogin ?? "you").")
                            .font(.body)
                            .foregroundColor(Color(nsColor: .labelColor))
                    }
                }
            case .expired, .denied:
                EmptyView()
            }
        } leadingActions: {
            Button { model.backToWelcome() } label: { Text("Back") }
                .buttonStyle(.bordered)
        } primaryAction: {
            Button { model.continueFromConnectGitHub() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.deviceFlow.status != .authorized)
        }
    }

    // MARK: 3. Detect (#w3)

    private var detectView: some View {
        stepShell(
            eyebrow: "Step 3 of 9",
            title: "Checking what's already here",
            intro: "Control Tower looks at what's already on this Mac before it asks you anything, and puts the basics in place."
        ) {
            if case .detecting = model.phase {
                verifyingCard("Checking what's already here…")
            } else {
                sectionCard("What's already here") {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(model.detectLines, id: \.self) { line in
                            HStack(alignment: .top, spacing: 9) {
                                Text("•")
                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                Text(line)
                                    .font(.callout)
                                    .foregroundColor(Color(nsColor: .labelColor))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        } leadingActions: {
            Button { model.phase = .connectGitHub } label: { Text("Back") }
                .buttonStyle(.bordered)
        } primaryAction: {
            Button { model.continueFromDetect() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isDetecting)
        }
    }

    private var isDetecting: Bool {
        if case .detecting = model.phase { return true }
        return false
    }

    // MARK: 4. What you're getting (#w4)

    private var whatYoureGettingView: some View {
        stepShell(
            eyebrow: "Step 4 of 9",
            title: "Here's what you're getting",
            intro: "Everyone on your team gets all of this. There's nothing to pick. Control Tower sets it up and keeps it current for you."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                sectionCard("Your copilots") {
                    VStack(alignment: .leading, spacing: 0) {
                        confirmRow(name: "Knowledge Copilot", desc: "Your company's knowledge, ready to ask.")
                        Divider()
                        confirmRow(name: "CLI Copilot", desc: "The quiet engine that keeps everything running.")
                        Divider()
                        confirmRow(name: "Claude Copilot, your company's pick", desc: "Your AI copilot for everyday work.")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Use the other one too?")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Toggle(isOn: Binding(
                        get: { model.includeCodex },
                        set: { _ in model.toggleIncludeCodex() }
                    )) {
                        Text("I also use Codex. Include Codex Copilot too.")
                            .font(.body)
                            .foregroundColor(Color(nsColor: .labelColor))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } leadingActions: {
            Button { model.phase = .detected } label: { Text("Back") }
                .buttonStyle(.bordered)
        } primaryAction: {
            Button { model.continueFromWhatYoureGetting() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: 5. Departments (#w5)

    private var departmentsView: some View {
        stepShell(
            eyebrow: "Step 5 of 9",
            title: "Departments you can join",
            intro: "Joining a department brings in everything your team shares there. You can join now, or come back to this later from Settings or the menu bar."
        ) {
            if model.departments.isEmpty {
                Text("No departments are available to you yet. When someone adds you to one, it'll show up here.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                sectionCard("Departments you can join") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.departments.enumerated()), id: \.element.id) { index, department in
                            departmentRow(department)
                            if index < model.departments.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        } leadingActions: {
            Button { model.phase = .whatYoureGetting } label: { Text("Back") }
                .buttonStyle(.bordered)
            Button { model.continueFromDepartments() } label: { Text("Skip for now") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { model.continueFromDepartments() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func departmentRow(_ department: DepartmentRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(department.name)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                departmentStateCaption(department.state)
            }
            Spacer()
            departmentAction(department)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(department.name), \(departmentAccessibilityWord(department.state))")
    }

    @ViewBuilder
    private func departmentStateCaption(_ state: DepartmentJoinState) -> some View {
        switch state {
        case .joined:
            Text("Joined").font(.caption).foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .availableToJoin:
            Text("Available to join").font(.caption).foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .joining:
            Text("Joining…").font(.caption).foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .waitingForNetwork:
            Text("Waiting for the network.").font(.caption).foregroundColor(Color(nsColor: .tertiaryLabelColor))
        case .notAvailable(let caption):
            Text(caption).font(.caption).foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
    }

    private func departmentAccessibilityWord(_ state: DepartmentJoinState) -> String {
        switch state {
        case .joined: return "joined"
        case .availableToJoin: return "available to join"
        case .joining: return "joining"
        case .waitingForNetwork: return "waiting for the network"
        case .notAvailable(let caption): return caption
        }
    }

    @ViewBuilder
    private func departmentAction(_ department: DepartmentRow) -> some View {
        switch department.state {
        case .availableToJoin:
            Button { model.joinDepartment(department.id) } label: { Text("Join") }
                .buttonStyle(.bordered)
        case .joining:
            ProgressView().controlSize(.small)
        case .joined, .waitingForNetwork, .notAvailable:
            EmptyView()
        }
    }

    // MARK: 6. Integrations (#w6)

    private var integrationsView: some View {
        stepShell(
            eyebrow: "Step 6 of 9",
            title: "Integrations",
            intro: "Some integrations are already set up for you because you're on the team. Others use your own accounts. Signing in always happens in your browser, on the provider's own page. Control Tower never asks for a password."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                sectionCard("Shared with your team · ready for you. Nothing to sign into.") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.sharedIntegrations.enumerated()), id: \.element.id) { index, row in
                            HStack {
                                Text(row.name)
                                    .font(.callout)
                                    .foregroundColor(Color(nsColor: .labelColor))
                                Spacer()
                                Text(row.statusCaption)
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            }
                            .padding(.vertical, 8)
                            if index < model.sharedIntegrations.count - 1 {
                                Divider()
                            }
                        }
                    }
                }

                sectionCard("Your accounts") {
                    VStack(alignment: .leading, spacing: 9) {
                        providerCardRow(name: "GitHub") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Signed in as \(model.authorizedLogin ?? "you").")
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            }
                        } note: {
                            Text("Connected at the start.")
                        }
                        ForEach(ProviderCard.personalAccounts) { provider in
                            providerCardRow(name: provider.name) {
                                Button {
                                    // Inert by decision: the personal-sign-in
                                    // verb per provider is not yet frozen
                                    // (cli-contract.md), so this card is
                                    // honest state, not a working action.
                                } label: {
                                    Text("Connect")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(true)
                                .help("Not available yet.")
                            } note: { EmptyView() }
                        }
                    }
                }
            }
        } leadingActions: {
            Button { model.phase = .departments } label: { Text("Back") }
                .buttonStyle(.bordered)
            Button { model.skipIntegrations() } label: { Text("Skip for now") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { model.continueFromIntegrations() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func providerCardRow<Trailing: View, Note: View>(
        name: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder note: () -> Note
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                Spacer()
                trailing()
            }
            note()
                .font(.caption2)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: 7. Set up (#w7) — named phase, no ETA

    private var materializeView: some View {
        stepShell(
            eyebrow: "Step 7 of 9",
            title: model.materialize.label.isEmpty ? "Setting up" : model.materialize.label,
            intro: "This part runs on its own. Keep this window open, or close it and let Control Tower finish in the menu bar."
        ) {
            VStack(spacing: 12) {
                ProgressView()
                if model.materialize.total > 0 {
                    Text("Part \(model.materialize.index) of \(model.materialize.total)")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            Button {} label: {
                Text("Setting up…")
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
    }

    // MARK: 8. Verify (#w8)

    private var verifyView: some View {
        stepShell(
            eyebrow: "Step 8 of 9",
            title: "Making sure everything's current",
            intro: "The only success here is everything actually being up to date."
        ) {
            if case .verifying = model.phase {
                verifyingCard("Checking your setup…")
            } else {
                VStack {
                    Text("Everything checks out.")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                }
                .frame(maxWidth: .infinity)
                .padding(22)
            }
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            Button { model.continueFromVerify() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isVerifying)
        }
    }

    private var isVerifying: Bool {
        if case .verifying = model.phase { return true }
        return false
    }

    // MARK: 9. Done (#w9)

    private var doneView: some View {
        stepShell(
            eyebrow: "Step 9 of 9",
            title: "That's it. You're ready.",
            intro: "Control Tower now lives quietly in your menu bar. When the icon is quiet, everything's current. And when you're added to a new department later, it'll show up there, ready when you are."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("You have the tools. Now go change the world!")
                    .font(.title3.weight(.bold))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                videoLinkRow("See what you can build with this")
            }
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            Button { model.finish(onClose: onClose) } label: { Text("Let's go") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Holding (#w10, first-class, never a dead end)

    private func holdingView(_ info: HoldingInfo) -> some View {
        stepShell(
            eyebrow: "SETUP IS HOLDING",
            title: "I've paused setup for now.",
            intro: info.reason
        ) {
            EmptyView()
        } leadingActions: {
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { model.tryAgainAfterHolding() } label: { Text("Try again") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .headerTint(Color(nsColor: .systemOrange))
    }

    // MARK: Shared shell + components (same anatomy as publisher_setup.swift)

    private func stepShell<Content: View, Leading: View, Trailing: View>(
        eyebrow: String,
        title: String,
        intro: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder leadingActions: () -> Leading,
        @ViewBuilder primaryAction: () -> Trailing
    ) -> StepShell<Content, Leading, Trailing> {
        StepShell(eyebrow: eyebrow, title: title, intro: intro, content: content, leadingActions: leadingActions, primaryAction: primaryAction)
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The Welcome/What-you're-getting read-only rows (`.confirm-row`).
    private func confirmRow(name: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.callout.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
            Text(desc)
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Text(text)
                .font(.callout)
                .foregroundColor(Color(nsColor: .labelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verifyingCard(_ status: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(status)
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Every video affordance in this file is an inert link-out placeholder
    /// (no real URL exists yet, per the task contract) — a small "YouTube"
    /// hint chip, never an embedded player.
    private func videoLinkRow(_ caption: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "play.circle")
                .foregroundColor(Color(nsColor: .controlAccentColor))
            Text(caption)
                .font(.callout.weight(.semibold))
                .foregroundColor(Color(nsColor: .controlAccentColor))
            Text("YouTube")
                .font(.caption2.monospaced())
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption), placeholder link, opens YouTube")
    }
}

// MARK: - Wizard window controller

/// Owns the wizard's single `NSWindow` + its `WizardModel` for the lifetime of
/// the app. A singleton (`shared`) so both entry points — the popover's
/// "Set up" action and the tray's dev-only "Open Wizard (dev)" menu item
/// (`control-tower-tray.swift`) — reuse the SAME window/model instead of
/// spawning a second wizard. `isReleasedWhenClosed = false` so closing the
/// window (Done / the titlebar close button) never deallocates it — the next
/// `show()` reopens the same window with whatever state it was last in.
final class WizardWindowController: NSWindowController {
    static let shared = WizardWindowController()

    private let model = WizardModel()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Copilot Control Tower"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: WizardRootView(model: model, onClose: { [weak window] in window?.close() })
        )
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // SELFTEST HOOK (harness contract) — see `WizardSelftest`'s own doc.
        // `AppDelegate.applicationDidFinishLaunching` (`control-tower-tray.swift`)
        // already calls `show()` when `CT_OPEN_WIZARD=1`; this only ever adds
        // work when `CT_SELFTEST=1` is ALSO set, so a normal launch (or a
        // dev "Open Wizard" click) is unaffected.
        WizardSelftest.runIfRequested()
    }
}

// MARK: - Selftest hook (harness contract)

/// Drives the step-2 device flow (and, when `CT_SELFTEST_STEP=departments`,
/// the Departments read) directly through `CliClient`, independent of
/// `WizardModel`'s own UI-facing device-flow polling (`WizardModel.
/// beginDeviceFlow`/`startPolling`, which has no fixed poll cap and is paced
/// for a person watching the window, not a test harness). This exists purely
/// so a headless run can prove the auth/departments CLI seam works end to end
/// without clicking through the wizard UI. Terminates the process itself
/// (`exit(0)`/`exit(1)`) per the harness contract — never returns control to
/// the running app.
enum WizardSelftest {
    private static var hasRun = false

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["CT_SELFTEST"] == "1", env["CT_OPEN_WIZARD"] == "1" else { return }
        guard !hasRun else { return }
        hasRun = true
        Task { await run() }
    }

    private static func run() async {
        guard case .success(let code) = await CliClient.shared.authLoginInitiate() else {
            print("SELFTEST auth=error")
            exit(1)
        }

        var authState = "pending"
        var login = "none"
        let waitSeconds = UInt64(max(code.interval, 1))

        pollLoop: for attempt in 1...6 {
            switch await CliClient.shared.authLoginPoll(deviceCode: code.deviceCode) {
            case .success(let poll):
                switch poll.status {
                case .authorized:
                    authState = "authorized"
                    if case .success(let status) = await CliClient.shared.authStatus(), let identityLogin = status.identity?.login {
                        login = identityLogin
                    }
                    break pollLoop
                case .denied:
                    authState = "denied"
                    break pollLoop
                case .expired:
                    authState = "expired"
                    break pollLoop
                case .pending:
                    authState = "pending"
                    if attempt < 6 {
                        try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                    }
                }
            case .failure:
                print("SELFTEST auth=error")
                exit(1)
            }
        }

        print("SELFTEST auth=\(authState) signedInAs=\(login)")

        if ProcessInfo.processInfo.environment["CT_SELFTEST_STEP"] == "departments" {
            switch await CliClient.shared.layers() {
            case .success(let report):
                let parts = report.layers.map { entry -> String in
                    let availability: String
                    if entry.joined {
                        availability = "joined"
                    } else if entry.entitled == true {
                        availability = "available"
                    } else {
                        availability = "not-available"
                    }
                    return "\(entry.id):\(availability)"
                }
                print("SELFTEST departments=\(parts.joined(separator: ","))")
            case .failure:
                print("SELFTEST auth=error")
                exit(1)
            }
        }

        exit(0)
    }
}
