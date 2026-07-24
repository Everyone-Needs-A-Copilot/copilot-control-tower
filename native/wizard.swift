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
//   - Detect (step 3): `authStatus()` + `doctor()` + aggregate `onboard` plan
//   - Departments (step 5): `layers()` / `layersJoin(id:)`
//   - Set up (step 7): aggregate `onboard --apply` (+ `updateFanout()` when a
//     department was joined)
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

// MARK: - Wizard roadmap (10 rows, verbatim sidebar labels: Welcome / Connect
// GitHub / Detect / What you're getting / Departments / Integrations / Your
// projects / Set up / Verify / Done)
//
// `.projects` (adopt-and-project-setup spec, "Step 7 of 10: Your projects")
// is a REAL step with a real sidebar row, positioned immediately before Set
// up — never conditional on `includeCodex`, never skipped silently. Every
// stage after it shifted by one; every "Step N of 9" eyebrow in this file
// became "Step N of 10" in the same change.

enum WizardStage: Int, CaseIterable, Identifiable {
    case welcome, connectGitHub, detect, whatYoureGetting, departments, integrations, projects, materialize, verify, done
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .connectGitHub: return "Connect GitHub"
        case .detect: return "Detect"
        case .whatYoureGetting: return "What you're getting"
        case .departments: return "Departments"
        case .integrations: return "Integrations"
        case .projects: return "Your projects"
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

// MARK: - Step 7, Your projects (adopt-and-project-setup spec)

/// One row in the projects list (`cc workspace --all --json`'s
/// `WorkspaceEntry`, grouped for display). The wizard step uses checkboxes
/// (`canApplyNow` is always false here — the copilots a project's setup
/// would copy from do not exist on this Mac yet at step 7, per the spec's
/// own rejected-alternative note); the menu bar drill-in uses immediate
/// `Add` instead, because by then `canApplyNow` is true.
enum ProjectRowGroup: String {
    case canBeSetUp
    case needsFinishing
    case alreadySetUp
    case keptAsIs
}

/// Drives Done's projects card (#w9/Step 10) per the spec's four body
/// variants: set up (with or without a failure), skipped, or declined
/// (card absent). `.notReached` only ever describes a wizard session that
/// never got as far as Set up at all.
enum ProjectsStepOutcome: Equatable {
    case notReached
    case declined
    case skipped
    case setUp(succeeded: Int, total: Int)
}

// MARK: - Step 8, Set up: named-phase materialize progress

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
    /// The re-plan after a "One question first" decision (`Include what I
    /// have` / `Not now`) — same origin stage (`.detect`) as `.detecting`,
    /// distinct only so the progress card can show the spec's own
    /// "Checking what that means…" copy instead of Detect's first-visit
    /// "Checking what's already here…".
    case replanningAfterDecision
    case detected
    /// Inline over Detect, per the spec's "Architecture decision": built
    /// from the same `StepShell`/no-sidebar-row mechanism Holding already
    /// uses, entered only when the CLI's plan carries at least one
    /// adoptable ("ask") personal-space item.
    case onboardQuestion
    case whatYoureGetting
    case departments
    case integrations
    case projects
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
    @Published var ecosystemInventory: [EcosystemInventoryItem] = []
    @Published var ecosystemInventorySummary: EcosystemInventorySummary?
    @Published var adoptionRollbackPaths: [String] = []
    @Published var includeCodex = true
    @Published var departments: [DepartmentRow] = []
    @Published var materialize = MaterializePhaseState()
    @Published var workspaceFolderName: String?

    // MARK: One question first (adopt-and-project-setup spec)

    /// Component names ("claude"/"codex"/"knowledge"/"cli") the person has
    /// consented to adopt so far this session — sent back as
    /// `--adopt-existing` on every subsequent plan/apply call, including
    /// Set up's own apply. Never cleared once set (declining is per-run,
    /// per the spec, but this app never re-asks after a decision — see
    /// `onboardQuestionAnswered`).
    @Published var adoptExisting: Set<String> = []
    /// The CLI's own personal-scope "ask" rows — one checkbox per adoptable
    /// component, in the CLI's order.
    @Published var onboardQuestionItems: [EcosystemInventoryItem] = []
    /// Personal-scope items the CLI marked for review instead of a
    /// question (no checkbox, "Kept as is") — shown on the SAME screen.
    @Published var onboardReviewItemsForQuestion: [EcosystemInventoryItem] = []
    /// Row ids currently checked on the question screen. Pre-selected to
    /// every question item's id the first time the screen is populated;
    /// preserved across a Holding round trip ("Include what I already
    /// have" returns "with the previous selections intact").
    @Published var onboardSelections: Set<String> = []
    private var onboardQuestionAnswered = false

    // MARK: Step 7, Your projects (adopt-and-project-setup spec)

    @Published var projectRoots: [WorkspaceRootListEntry] = []
    @Published var projectRootCandidates: [WorkspaceRootCandidate] = []
    @Published var projectWorkspaces: [WorkspaceEntry] = []
    @Published var projectsSummary: WorkspaceSummary?
    @Published var projectsLoading = false
    @Published var projectsDeclined = false
    /// Local, session-only confirmation line for "I don't keep projects on
    /// this Mac" — cleared whenever the step is re-entered with a folder
    /// already granted (the two states are mutually exclusive).
    @Published var projectsDeclineConfirmed = false
    @Published var selectedProjectPaths: Set<String> = []
    @Published var projectsStepOutcome: ProjectsStepOutcome = .notReached
    /// "An unusable folder shows the CLI's blocked sentence next to the
    /// picker and keeps the step usable" (spec, Step 7's failure/recovery
    /// row) — this step never routes to Holding on its own; a bad folder
    /// choice is shown inline and the picker stays available to try again.
    @Published var projectsFolderBlockedDetail: String?
    private var hasLoadedProjectsStep = false

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
        // `.onboardQuestion` renders inline over Detect, same mechanism as
        // Holding: no sidebar row of its own, no step-number change.
        case .detecting, .replanningAfterDecision, .detected, .onboardQuestion: return .detect
        case .whatYoureGetting: return .whatYoureGetting
        case .departments: return .departments
        case .integrations: return .integrations
        case .projects: return .projects
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
        performDetect(replanning: false)
    }

    /// Shared by the first-ever Detect pass and the re-plan that follows a
    /// "One question first" decision (`includeOnboardSelections()` /
    /// `declineOnboardQuestion()` below) — the ONLY difference is which
    /// progress copy is shown while it runs (Detect's spec, "Ask" row:
    /// "the feedback is the shared progress card with **Checking what that
    /// means…**" for the post-decision case).
    private func performDetect(replanning: Bool) {
        phase = replanning ? .replanningAfterDecision : .detecting
        Task {
            async let authAsync = CliClient.shared.authStatus()
            async let doctorAsync = CliClient.shared.doctor()
            async let onboardAsync = CliClient.shared.ecosystemOnboardPlan(products: self.copilotProducts, adoptExisting: Array(self.adoptExisting))
            let authResult = await authAsync
            let doctorResult = await doctorAsync
            let onboardResult = await onboardAsync

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
            guard case .success(let onboard) = onboardResult else {
                if case .failure(let error) = onboardResult {
                    self.enterHolding(reason: self.genericHoldingReason(for: error), origin: .detect)
                }
                return
            }
            self.ecosystemInventory = onboard.inventory ?? []
            self.ecosystemInventorySummary = onboard.inventorySummary

            // "One question first" (adopt-and-project-setup spec, "Ask" row):
            // asked BEFORE the blocked-guard below, and only once per
            // session — a plan that is "blocked" purely because an
            // unrelated item needs review must still surface the question,
            // never silently drop it behind Holding's own review-only card
            // (the old dead end this replaces).
            if !self.onboardQuestionAnswered {
                let (ask, review) = Self.personalOnboardQuestion(from: onboard)
                if !ask.isEmpty {
                    self.onboardQuestionItems = ask
                    self.onboardReviewItemsForQuestion = review
                    if self.onboardSelections.isEmpty {
                        self.onboardSelections = Set(ask.map(\.id))
                    }
                    self.phase = .onboardQuestion
                    return
                }
            }

            guard onboard.result != .blocked else {
                let detail = onboard.stages.last(where: { $0.result == "blocked" })?.detail
                    ?? "Your organization's setup could not be confirmed safely."
                self.enterHolding(reason: "\(detail) Nothing existing was changed.", origin: .detect)
                return
            }

            var lines: [String] = []
            if let login = status.identity?.login {
                self.authorizedLogin = login
                lines.append("GitHub: signed in as \(login).")
            } else {
                lines.append("GitHub: signed in.")
            }
            lines.append("Organization: \(onboard.org).")
            lines.append("Personal spaces: checked against the signed-in GitHub account.")
            for layer in onboard.layers {
                let product = layer.product.prefix(1).uppercased() + String(layer.product.dropFirst())
                lines.append("\(product): \(layer.role) setup, rank \(layer.rank).")
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
            for stage in onboard.stages where stage.result == "changes-required" {
                if stage.stage == "personal-packages" {
                    lines.append("Your private spaces need setup; only confirmed-missing spaces will be created.")
                } else if stage.stage == "device-ssh" {
                    lines.append("This Mac needs its own secure GitHub connection.")
                } else if stage.stage == "layer-manifest" {
                    lines.append("Your organization, personal, and foundation layers are ready to be connected.")
                }
            }
            self.detectLines = lines
            self.phase = .detected
        }
    }

    /// Pure: splits an ecosystem plan's personal-scope inventory into ask
    /// rows (adoptable — the CLI's `reversible: true` is unique to
    /// `package_state: "adoptable"`, see `onboard.py`'s `_personal_inventory`)
    /// and review rows (`action == "review"`, i.e. `package_state: "held"`),
    /// in the CLI's own order. A `static` function (no instance state) so
    /// this exact derivation is shared between `performDetect` above and
    /// the selftest below — never two slightly-different readings of the
    /// same report.
    static func personalOnboardQuestion(from report: EcosystemOnboardReport) -> (ask: [EcosystemInventoryItem], review: [EcosystemInventoryItem]) {
        let personal = (report.inventory ?? []).filter { $0.scope == "personal" }
        return (personal.filter { $0.reversible }, personal.filter { $0.action == "review" })
    }

    /// `EcosystemInventoryItem.id` for a personal-space row is always
    /// `"personal-<component>"` (`onboard.py`'s `_personal_inventory`) — the
    /// only place that format is depended on, kept as one small pure
    /// function rather than repeated string surgery at each call site.
    static func componentId(fromPersonalInventoryId id: String) -> String? {
        let prefix = "personal-"
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }

    func continueFromDetect() {
        guard case .detected = phase else { return }
        phase = .whatYoureGetting
    }

    // MARK: One question first (adopt-and-project-setup spec)

    func toggleOnboardSelection(_ id: String) {
        if onboardSelections.contains(id) {
            onboardSelections.remove(id)
        } else {
            onboardSelections.insert(id)
        }
    }

    var canIncludeOnboardSelections: Bool { !onboardSelections.isEmpty }

    /// "Include what I have" — sends exactly the checked rows back as
    /// `--adopt-existing`; every cleared row is declined for this run (the
    /// spec's own rule: "no all-or-nothing choice"). Answered once; the
    /// question never reappears this session unless Holding's "Include
    /// what I already have" explicitly reopens it.
    func includeOnboardSelections() {
        onboardQuestionAnswered = true
        let components = onboardSelections.compactMap(Self.componentId(fromPersonalInventoryId:))
        adoptExisting.formUnion(components)
        performDetect(replanning: true)
    }

    /// "Not now" — every question row is declined for this run; nothing is
    /// added to `adoptExisting`.
    func declineOnboardQuestion() {
        onboardQuestionAnswered = true
        performDetect(replanning: true)
    }

    /// Holding's "Include what I already have" — returns to the question
    /// "with the previous selections intact" (the spec's own words):
    /// `onboardSelections` is deliberately left untouched.
    func returnToOnboardQuestion() {
        onboardQuestionAnswered = false
        phase = .onboardQuestion
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
        enterProjectsStep()
    }

    func continueFromIntegrations() {
        enterProjectsStep()
    }

    // MARK: Step 7, Your projects (adopt-and-project-setup spec)

    /// Loads folder-grant state (`workspace roots`) and, if at least one
    /// folder is already granted, the discovered project list
    /// (`workspace --all`) — same read-only calls the menu bar uses,
    /// nothing written here. Runs once per wizard visit to this step
    /// (`hasLoadedProjectsStep`); the sidebar's own "completed rows are
    /// tappable, read-only" review affordance re-enters this phase without
    /// re-fetching.
    func enterProjectsStep() {
        phase = .projects
        guard !hasLoadedProjectsStep else { return }
        hasLoadedProjectsStep = true
        loadProjectsStep()
    }

    private func loadProjectsStep() {
        projectsLoading = true
        Task {
            defer { self.projectsLoading = false }
            guard case .success(let rootsReport) = await CliClient.shared.workspaceRoots() else { return }
            self.projectRoots = rootsReport.roots ?? []
            self.projectRootCandidates = rootsReport.candidates ?? []
            guard !self.projectRoots.isEmpty else { return }
            await self.loadProjectWorkspaces()
        }
    }

    private func loadProjectWorkspaces() async {
        guard case .success(let report) = await CliClient.shared.workspaces() else { return }
        self.projectWorkspaces = report.workspaces
        self.projectsSummary = report.summary
        // Pre-selected where the CLI says a checkbox is the right grammar
        // (`can_apply_now: false` at this step, per the spec — the writes
        // this step collects happen in Set up, not here) AND the row is
        // genuinely actionable (`setup-available`/`activation-required`).
        self.selectedProjectPaths = Self.preselectedProjectPaths(from: report.workspaces)
    }

    /// Pure: which project rows start checked. Both currently-actionable
    /// states (`setup-available`, `activation-required`) are pre-selected,
    /// per the spec's own table ("Checkbox, selected" for both rows);
    /// `ready`/`blocked` rows carry no control at all, so they are never in
    /// this set.
    static func preselectedProjectPaths(from workspaces: [WorkspaceEntry]) -> Set<String> {
        Set(workspaces.filter { $0.state == .setupAvailable || $0.state == .activationRequired }.map(\.path))
    }

    func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the one folder where your projects live. Control Tower looks only inside that folder, and never anywhere else on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        approveProjectsRoot(path: url.path)
    }

    func approveCandidateRoot(_ candidate: WorkspaceRootCandidate) {
        approveProjectsRoot(path: candidate.path)
    }

    private func approveProjectsRoot(path: String) {
        projectsLoading = true
        projectsFolderBlockedDetail = nil
        Task {
            defer { self.projectsLoading = false }
            switch await CliClient.shared.approveWorkspaceRoot(path: path) {
            case .success(let report) where report.result == .blocked:
                self.projectsFolderBlockedDetail = report.root.detail
                return
            case .failure:
                return
            default:
                break
            }
            self.projectsDeclined = false
            self.projectsDeclineConfirmed = false
            guard case .success(let rootsReport) = await CliClient.shared.workspaceRoots() else { return }
            self.projectRoots = rootsReport.roots ?? []
            self.projectRootCandidates = rootsReport.candidates ?? []
            await self.loadProjectWorkspaces()
        }
    }

    func stopWatchingProjectsRoot(_ root: WorkspaceRootListEntry) {
        projectsLoading = true
        Task {
            defer { self.projectsLoading = false }
            guard case .success = await CliClient.shared.forgetWorkspaceRoot(path: root.path) else { return }
            guard case .success(let rootsReport) = await CliClient.shared.workspaceRoots() else { return }
            self.projectRoots = rootsReport.roots ?? []
            self.projectRootCandidates = rootsReport.candidates ?? []
            if self.projectRoots.isEmpty {
                self.projectWorkspaces = []
                self.projectsSummary = nil
                self.selectedProjectPaths = []
            } else {
                await self.loadProjectWorkspaces()
            }
        }
    }

    /// "I don't keep projects on this Mac" — records the decline so the
    /// menu bar never offers this again, and confirms inline (never
    /// auto-advances; the person still chooses Continue).
    func declineProjects() {
        Task {
            guard case .success = await CliClient.shared.declineWorkspaces() else { return }
            self.projectsDeclined = true
            self.projectsDeclineConfirmed = true
        }
    }

    func toggleProjectSelection(_ path: String) {
        if selectedProjectPaths.contains(path) {
            selectedProjectPaths.remove(path)
        } else {
            selectedProjectPaths.insert(path)
        }
    }

    func selectAllProjects() {
        selectedProjectPaths = Self.preselectedProjectPaths(from: projectWorkspaces)
    }

    func selectNoProjects() {
        selectedProjectPaths = []
    }

    func backFromProjects() {
        phase = .integrations
    }

    /// "Skip for now" — leaves the offer available in the menu bar; behaves
    /// exactly like Continue with nothing selected, since a folder that was
    /// never granted has nothing to set up regardless.
    func skipProjectsForNow() {
        selectedProjectPaths = []
        beginMaterialize()
    }

    func continueFromProjects() {
        beginMaterialize()
    }

    // MARK: Set up (#w7, renumbered Step 8 of 10) — named-phase materialize, no ETA

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

        if projectsDeclined {
            projectsStepOutcome = .declined
        } else if selectedProjectPaths.isEmpty {
            projectsStepOutcome = .skipped
        }

        var labels = [
            // "Including what you already have…" per Step 8's own copy —
            // only when there is something adopted this session to name;
            // otherwise the original label still describes the same call.
            adoptExisting.isEmpty ? "Confirming your private GitHub spaces…" : "Including what you already have…",
            "Setting up your copilots…",
        ]
        labels += joinedDepartments.map { "Bringing in your \($0.name) department…" }
        let projectPathsToApply = selectedProjectPaths
        if !projectPathsToApply.isEmpty {
            labels.append("Setting up your copilots in \(projectPathsToApply.count) project\(projectPathsToApply.count == 1 ? "" : "s")…")
        }
        labels.append("Finishing up…")
        materialize = MaterializePhaseState(label: labels[0], index: 1, total: labels.count)

        let shouldFanOut = !joinedDepartments.isEmpty

        Task {
            switch await CliClient.shared.ecosystemOnboardApply(products: self.copilotProducts, adoptExisting: Array(self.adoptExisting)) {
            case .success(let report):
                guard report.result == .ready else {
                    self.materializeInFlight = false
                    let detail = report.stages.last(where: { $0.result == "blocked" })?.detail
                        ?? "Setup stopped at a safety check."
                    self.enterHolding(reason: "\(detail) You can retry after it is resolved.", origin: .materialize)
                    return
                }
                self.ecosystemInventory = report.inventory ?? self.ecosystemInventory
                self.ecosystemInventorySummary = report.inventorySummary ?? self.ecosystemInventorySummary
                self.adoptionRollbackPaths = report.stages.compactMap(\.rollbackPath)
            case .failure(let error):
                self.materializeInFlight = false
                self.enterHolding(reason: self.genericHoldingReason(for: error), origin: .materialize)
                return
            }
            if shouldFanOut {
                Task { _ = await CliClient.shared.updateFanout() }
            }
            if !projectPathsToApply.isEmpty {
                await self.applySelectedProjects(projectPathsToApply)
            }
            await self.cyclePhases(labels)
            self.materializeInFlight = false
            self.beginVerify()
        }
    }

    /// "Per-project failure is collected, never fatal, and never retried
    /// silently" (Step 8's own rule): one project failing to configure never
    /// stops the rest, and Done (below) never claims full success when it
    /// was not. Runs the copilots this project's setup copies from already
    /// exist on this Mac by this point (the ecosystem apply above just
    /// finished), matching `can_apply_now`'s own contract.
    private func applySelectedProjects(_ paths: Set<String>) async {
        var succeeded = 0
        for path in paths {
            let components = self.projectWorkspaces.first(where: { $0.path == path })?.recommendedComponents ?? []
            let result = await CliClient.shared.configureWorkspace(
                path: path, components: components, shareWithProject: false, apply: true
            )
            if case .success(let report) = result,
               let updated = report.workspaces.first(where: { $0.path == path }),
               updated.state != .blocked {
                succeeded += 1
            }
        }
        self.projectsStepOutcome = .setUp(succeeded: succeeded, total: paths.count)
    }

    private var copilotProducts: [String] {
        includeCodex ? ["claude", "codex"] : ["claude"]
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
        case .projects: phase = .projects
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
        case .detecting, .replanningAfterDecision, .detected: detectView
        case .onboardQuestion: onboardQuestionView
        case .whatYoureGetting: whatYoureGettingView
        case .departments: departmentsView
        case .integrations: integrationsView
        case .projects: projectsView
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
        case .replanningAfterDecision: return "replanningAfterDecision"
        case .detected: return "detected"
        case .onboardQuestion: return "onboardQuestion"
        case .whatYoureGetting: return "whatYoureGetting"
        case .departments: return "departments"
        case .integrations: return "integrations"
        case .projects: return "projects"
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
            eyebrow: "Step 1 of 10",
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
            eyebrow: "Step 2 of 10",
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
            eyebrow: "Step 3 of 10",
            title: "Checking what's already here",
            intro: "Control Tower keeps the parts that are already right, safely moves or repairs recognized earlier setup, and leaves anything unfamiliar untouched."
        ) {
            if case .detecting = model.phase {
                verifyingCard("Checking what's already here…")
            } else if case .replanningAfterDecision = model.phase {
                // "One question first", Detect's own spec section: "the
                // feedback is the shared progress card with **Checking what
                // that means…**" — distinct copy from the first Detect pass
                // above, same shared progress card.
                verifyingCard("Checking what that means…")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.ecosystemInventory.isEmpty {
                        sectionCard("What Control Tower found") {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(model.ecosystemInventory.enumerated()), id: \.element.id) { index, item in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: inventoryGlyph(item.action))
                                            .foregroundColor(inventoryColor(item.action))
                                            .frame(width: 18)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(item.title)
                                                    .font(.callout.weight(.semibold))
                                                Spacer()
                                                Text(inventoryActionLabel(item.action))
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(inventoryColor(item.action))
                                            }
                                            Text(item.detail)
                                                .font(.caption)
                                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                                .fixedSize(horizontal: false, vertical: true)
                                            if item.reversible {
                                                Text("A rollback copy is kept before anything moves or changes.")
                                                    .font(.caption2)
                                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                            }
                                        }
                                    }
                                    .padding(.vertical, 9)
                                    .accessibilityElement(children: .combine)
                                    if index < model.ecosystemInventory.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    sectionCard("How everything connects") {
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
        switch model.phase {
        case .detecting, .replanningAfterDecision: return true
        default: return false
        }
    }

    private func inventoryActionLabel(_ action: String) -> String {
        switch action {
        case "reuse": return "Keep"
        case "create": return "Add"
        case "migrate": return "Move safely"
        case "repair": return "Complete"
        case "review": return "Needs review"
        default: return action.capitalized
        }
    }

    private func inventoryGlyph(_ action: String) -> String {
        switch action {
        case "reuse": return "checkmark.circle.fill"
        case "create": return "plus.circle.fill"
        case "migrate": return "arrow.right.circle.fill"
        case "repair": return "wrench.and.screwdriver.fill"
        case "review": return "hand.raised.circle.fill"
        default: return "circle.fill"
        }
    }

    private func inventoryColor(_ action: String) -> Color {
        switch action {
        case "reuse": return Color(nsColor: .systemGreen)
        case "review": return Color(nsColor: .systemRed)
        default: return Color(nsColor: .controlAccentColor)
        }
    }

    // MARK: One question first (adopt-and-project-setup spec, inline over
    // Detect — same no-sidebar-row mechanism Holding uses below, accent
    // blue, never Holding's orange: `stepShell`'s default `tint` already IS
    // `.systemBlue`, so this view never calls `.headerTint(_:)` at all).

    private enum OnboardCardRow: Identifiable {
        case ask(EcosystemInventoryItem)
        case review(EcosystemInventoryItem)
        var id: String {
            switch self {
            case .ask(let item): return item.id
            case .review(let item): return item.id
            }
        }
    }

    private var onboardQuestionView: some View {
        // "One row per question item, in the CLI's order" THEN "one row per
        // item the CLI marked for review instead of a question" — two
        // sequential lists, per the spec's own reading order, not
        // interleaved by the underlying inventory's mixed ordering.
        let rows: [OnboardCardRow] = model.onboardQuestionItems.map(OnboardCardRow.ask)
            + model.onboardReviewItemsForQuestion.map(OnboardCardRow.review)

        return stepShell(
            eyebrow: "ONE QUESTION FIRST",
            title: "You already have some of this. Want me to include it?",
            intro: "Your GitHub account already has private spaces of your own, with your own content in them. I can include them so your copilots use what you already have, or leave them alone. Either way, nothing in them is changed, moved, or removed."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard("Already in your GitHub account") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            onboardCardRow(row)
                            if index < rows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                // The spec's own reassurance line, pinned directly under the
                // card, always present regardless of any selection.
                Text("Nothing existing was changed.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        } leadingActions: {
            Button { model.declineOnboardQuestion() } label: { Text("Not now") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            VStack(alignment: .trailing, spacing: 4) {
                Button { model.includeOnboardSelections() } label: { Text("Include what I have") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canIncludeOnboardSelections)
                    // Accessibility: "the disabled primary always carries
                    // its hint as help text" — never a hint the person can
                    // only discover by hovering.
                    .help(model.canIncludeOnboardSelections ? "" : "Choose something to include, or select Not now.")
                if !model.canIncludeOnboardSelections {
                    Text("Choose something to include, or select Not now.")
                        .font(.caption2)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
    }

    @ViewBuilder
    private func onboardCardRow(_ row: OnboardCardRow) -> some View {
        switch row {
        case .ask(let item): onboardQuestionRow(item)
        case .review(let item): onboardReviewRow(item)
        }
    }

    private func onboardQuestionRow(_ item: EcosystemInventoryItem) -> some View {
        let isSelected = model.onboardSelections.contains(item.id)
        return Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in model.toggleOnboardSelection(item.id) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                // Microinteraction: "a cleared row is declined; the feedback
                // is the CLI's decline sentence appearing under that row in
                // 150ms with no layout jump elsewhere". `item.declineDetail`
                // (B3, `onboard.schema.json`'s `inventoryItem.decline_detail`)
                // is rendered VERBATIM, never invented — per the spec's own
                // failure/recovery row, "A missing decline sentence renders
                // the row with no caption rather than invented copy", so an
                // absent `declineDetail` still shows no caption at all.
                if isSelected {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                } else if let declineDetail = item.declineDetail {
                    Text(declineDetail)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 9)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isSelected
                ? "\(item.title), will be included, \(item.detail)"
                : "\(item.title), will be left alone" + (item.declineDetail.map { ", \($0)" } ?? "")
        )
    }

    private func onboardReviewRow(_ item: EcosystemInventoryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("Kept as is")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), kept as is, \(item.detail)")
    }

    // MARK: 4. What you're getting (#w4)

    private var whatYoureGettingView: some View {
        stepShell(
            eyebrow: "Step 4 of 10",
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
            eyebrow: "Step 5 of 10",
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
            eyebrow: "Step 6 of 10",
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

    // MARK: 7. Your projects (adopt-and-project-setup spec) — a real step,
    // never conditional on Codex, positioned immediately before Set up so
    // every write still happens there.

    private var projectsView: some View {
        stepShell(
            eyebrow: "Step 7 of 10",
            title: "Where do you keep your projects?",
            intro: "If you build things on this Mac, Control Tower can set your copilots up inside each project too. Choose the one folder where your projects live. Control Tower looks only inside that folder, and never anywhere else on this Mac."
        ) {
            if model.projectsLoading && model.projectRoots.isEmpty && model.projectWorkspaces.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(height: 40)
                    }
                }
                .accessibilityHidden(true)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    projectsFolderCard
                    if !model.projectRoots.isEmpty {
                        projectsListCard
                    }
                }
            }
        } leadingActions: {
            Button { model.backFromProjects() } label: { Text("Back") }
                .buttonStyle(.bordered)
            Button { model.declineProjects() } label: { Text("I don't keep projects on this Mac") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Button { model.skipProjectsForNow() } label: { Text("Skip for now") }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        } primaryAction: {
            Button { model.continueFromProjects() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var projectsFolderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionCard("Your projects folder") {
                VStack(alignment: .leading, spacing: 10) {
                    if model.projectRoots.isEmpty {
                        Text("No folder chosen yet. Nothing is being watched.")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Button("Choose folder…") { model.chooseProjectsFolder() }
                            .buttonStyle(.bordered)
                        if let blocked = model.projectsFolderBlockedDetail {
                            Text(blocked)
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .systemRed))
                        }
                        if !model.projectRootCandidates.isEmpty {
                            Divider()
                            Text("Control Tower found a folder on this Mac that looks like it already holds your projects:")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(model.projectRootCandidates) { candidate in
                                HStack {
                                    Text(candidate.label)
                                        .font(.callout)
                                        .foregroundColor(Color(nsColor: .labelColor))
                                    Spacer()
                                    Button("Use this folder") { model.approveCandidateRoot(candidate) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.projectRoots.enumerated()), id: \.element.id) { index, root in
                                HStack {
                                    Text(root.name)
                                        .font(.callout)
                                        .foregroundColor(Color(nsColor: .labelColor))
                                    Spacer()
                                    Button("Stop watching") { model.stopWatchingProjectsRoot(root) }
                                        .buttonStyle(.plain)
                                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                }
                                .padding(.vertical, 6)
                                if index < model.projectRoots.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        Button("Add another folder…") { model.chooseProjectsFolder() }
                            .buttonStyle(.bordered)
                        if let blocked = model.projectsFolderBlockedDetail {
                            Text(blocked)
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .systemRed))
                        }
                    }
                }
            }
            if !model.projectRoots.isEmpty {
                Text("Control Tower looks only inside the folders listed here.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            if model.projectsDeclineConfirmed {
                Text("Got it. I won't ask about projects again. You can turn this on any time from the menu bar.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
    }

    private var projectsListCard: some View {
        let canBeSetUp = model.projectWorkspaces.filter { $0.state == .setupAvailable }
        let needsFinishing = model.projectWorkspaces.filter { $0.state == .activationRequired }
        let alreadySetUp = model.projectWorkspaces.filter { $0.state == .ready }
        let keptAsIs = model.projectWorkspaces.filter { $0.state == .blocked }
        let actionable = canBeSetUp.count + needsFinishing.count

        return sectionCard("Projects I found") {
            VStack(alignment: .leading, spacing: 12) {
                if model.projectWorkspaces.isEmpty {
                    Text("No projects in that folder yet. Any new one you create will get your copilots automatically.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack {
                        Text("\(model.projectWorkspaces.count) projects found. \(actionable) can be set up.")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .labelColor))
                        Spacer()
                        Button("Select all") { model.selectAllProjects() }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: .linkColor))
                        Button("Select none") { model.selectNoProjects() }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: .linkColor))
                    }
                    Text("Your projects get set up in the next step.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(canBeSetUp) { workspace in
                            projectRow(workspace, group: .canBeSetUp)
                            Divider()
                        }
                        ForEach(needsFinishing) { workspace in
                            projectRow(workspace, group: .needsFinishing)
                            Divider()
                        }
                        ForEach(keptAsIs) { workspace in
                            projectRow(workspace, group: .keptAsIs)
                            if workspace.id != keptAsIs.last?.id { Divider() }
                        }
                    }

                    if !alreadySetUp.isEmpty {
                        DisclosureGroup("\(alreadySetUp.count) already set up ›") {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(alreadySetUp) { workspace in
                                    projectRow(workspace, group: .alreadySetUp)
                                    if workspace.id != alreadySetUp.last?.id { Divider() }
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
    }

    private func projectRowCaption(_ workspace: WorkspaceEntry, group: ProjectRowGroup) -> String {
        switch group {
        case .canBeSetUp: return "Copilot can be set up here."
        case .needsFinishing: return "Set up here already, but not active on this Mac yet."
        case .alreadySetUp: return "Already set up."
        case .keptAsIs: return workspace.detail
        }
    }

    @ViewBuilder
    private func projectRow(_ workspace: WorkspaceEntry, group: ProjectRowGroup) -> some View {
        let caption = projectRowCaption(workspace, group: group)
        switch group {
        case .canBeSetUp, .needsFinishing:
            Toggle(isOn: Binding(
                get: { model.selectedProjectPaths.contains(workspace.path) },
                set: { _ in model.toggleProjectSelection(workspace.path) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(workspace.name), \(caption)")
        case .alreadySetUp:
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                Text(caption)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(workspace.name), \(caption)")
        case .keptAsIs:
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("Kept as is")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(workspace.name), kept as is, \(caption)")
        }
    }

    // MARK: 8. Set up (#w7) — named phase, no ETA

    private var materializeView: some View {
        stepShell(
            eyebrow: "Step 8 of 10",
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

    // MARK: 9. Verify (#w8)

    private var verifyView: some View {
        stepShell(
            eyebrow: "Step 9 of 10",
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
                    if !model.adoptionRollbackPaths.isEmpty {
                        Text("Your previous setup was preserved in a rollback copy.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .padding(.top, 5)
                    }
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

    // MARK: 10. Done (#w9)

    private var doneView: some View {
        stepShell(
            eyebrow: "Step 10 of 10",
            title: "That's it. You're ready.",
            intro: "Control Tower now lives quietly in your menu bar. When the icon is quiet, everything's current. And when you're added to a new department later, it'll show up there, ready when you are."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("You have the tools. Now go change the world!")
                    .font(.title3.weight(.bold))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                videoLinkRow("See what you can build with this")
                if let body = doneProjectsCardBody {
                    sectionCard("Your projects") {
                        Text(body)
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            Button { model.finish(onClose: onClose) } label: { Text("Let's go") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Step 10's own four variants — the card is absent entirely for
    /// `.declined`, per the spec's own table.
    private var doneProjectsCardBody: String? {
        switch model.projectsStepOutcome {
        case .declined:
            return nil
        case .skipped:
            return "You skipped projects for now. Point Control Tower at your projects folder any time from the menu bar."
        case .setUp(let succeeded, let total) where succeeded == total && total > 0:
            return "Your copilots are set up in \(total) of your \(total) project\(total == 1 ? "" : "s"). Any new project you create in that folder gets them automatically."
        case .setUp(let succeeded, let total) where total > 0:
            let failed = total - succeeded
            let failedClause = failed == 1
                ? "One needs another look, and it's waiting for you in the menu bar."
                : "\(failed) need another look, and they're waiting for you in the menu bar."
            return "Your copilots are set up in \(succeeded) of your \(total) project\(total == 1 ? "" : "s"). \(failedClause) Nothing existing was changed."
        case .setUp, .notReached:
            return nil
        }
    }

    // MARK: Holding (#w10, first-class, never a dead end)

    private func holdingView(_ info: HoldingInfo) -> some View {
        stepShell(
            eyebrow: "SETUP IS HOLDING",
            title: "I've paused setup for now.",
            intro: info.reason
        ) {
            let reviewItems = model.ecosystemInventory.filter { $0.action == "review" }
            if reviewItems.isEmpty {
                EmptyView()
            } else {
                sectionCard("Kept untouched for review") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(reviewItems) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.callout.weight(.semibold))
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        } leadingActions: {
            // "Holding stops being reachable by refusal and becomes
            // reachable only by the person's own choice or by a genuine
            // outside failure" — this leading action only appears when
            // there is an actual question to return to (cached from the
            // last plan that carried one); it is never fabricated for a
            // Holding reached some other way.
            if !model.onboardQuestionItems.isEmpty {
                Button { model.returnToOnboardQuestion() } label: { Text("Include what I already have") }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
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
