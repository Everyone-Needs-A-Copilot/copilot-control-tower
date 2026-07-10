//
// Copilot Control Tower — native first-run wizard (S2, the ONLY install path).
//
// A titled `NSWindow` (NavigationSplitView roadmap sidebar + StepShell content
// pane + pinned footer), opened on demand from the tray popover's "Set up"
// action and the tray's dev-only "Open Wizard (dev)" menu item — see
// `native/control-tower-tray.swift`'s `StatusBarController.openWizard()`.
// Reuses `scripts/publisher_setup.swift`'s roadmap-sidebar / StepShell grammar
// verbatim (same anatomy: eyebrow, title, intro, content region, footer with
// leading Back, trailing primary) so the two apps read as one family, per
//   - docs/03-design/control-tower-interaction-spec.md §3 (the corrected
//     single self-install path: no managed-silent lane, D4; Departments (S11)
//     and the split Integrations register (S12 shared + S5 personal) are
//     first-class steps; the device-flow sheet's "no countdown, no token"
//     rule; named-phase materialize with no ETA; holding as first-class,
//     never a dead end).
//   - docs/03-design/control-tower-visual-system.md §6.3 (the wizard shell in
//     the Publisher-Setup roadmap grammar, corrected to this build's step set).
//   - src/types.ts (WizardState/WizardPhaseTag/WizardStepKind/
//     WizardProductOption/WizardLayerSlot/SigninState — mirrored below,
//     `product -> component` renamed per D2).
//
// MOCK-BACKED, same as the tray: `copilot layers --json` / the real
// `wizard_*` IPC commands are not shelled out to (those verbs are not yet
// frozen — native-experience-architecture.md §6 open decisions 3/4/7). Every
// transition in `WizardModel` below is a scripted, timed mock so the flow can
// be judged end to end; each mock seam is commented with the real verb it
// will bind to once WS-A lands.
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory` and this
// same discipline in `control-tower-tray.swift` / `publisher_setup.swift`): no
// blocking `Process`/file I/O may run during a SwiftUI `@State`/`@StateObject`
// `init()`. `WizardModel.init()` (the default memberwise init via property
// defaults — there is no explicit `init()` body) is pure: every mock "async"
// transition below is scheduled from a user action or a view `.onAppear`,
// never from a property initializer, and uses `DispatchQueue.main.asyncAfter`
// (never a blocking `Process.waitUntilExit()`).

import AppKit
import SwiftUI

// MARK: - Wizard roadmap (10 design-spec rows collapsed to this build's 8; see
// WizardPhase.integrations's own doc for the one deliberate step-combination).

/// The sidebar roadmap stages (`WizardPhaseTag` with the `question` phase
/// expanded into its sub-stages, per interaction-spec §3.4). Holding never
/// adds its own row — it renders inline over whichever stage raised it
/// (`WizardModel.currentStage` maps a `.holding` phase back to its origin).
enum WizardStage: Int, CaseIterable, Identifiable {
    case welcome, detect, chooseComponents, departments, integrations, materialize, verify, done
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .detect: return "Detect"
        case .chooseComponents: return "Choose components"
        case .departments: return "Departments"
        case .integrations: return "Integrations"
        case .materialize: return "Set up"
        case .verify: return "Verify"
        case .done: return "Done"
        }
    }
}

// MARK: - Step data (mirrors src/types.ts, product -> component per D2)

/// One checkbox row on the Choose-components step. Mirrors `src/types.ts`
/// `WizardProductOption` (`{id, label, pre_checked}`), renamed field-for-field
/// per D2. `granted == false` renders visible but permanently disabled — the
/// "honest slot, never hidden" rule (interaction-spec §3.5 step 3): a user may
/// uncheck a granted option but can never check an ungranted one.
struct ComponentOption: Identifiable {
    let id: String
    let label: String
    let granted: Bool
    var checked: Bool

    static let mockCatalog: [ComponentOption] = [
        ComponentOption(id: "claude", label: "Claude Copilot", granted: true, checked: true),
        ComponentOption(id: "cli", label: "CLI Copilot", granted: true, checked: true),
        ComponentOption(id: "knowledge", label: "Knowledge Copilot", granted: true, checked: true),
        ComponentOption(id: "codex", label: "Codex Copilot", granted: false, checked: false),
    ]
}

/// A department's join state (S11). Mirrors the `copilot layers --json` shape
/// interaction-spec §4.5 sketches (`entitled` x `joined` x an optional
/// `reason`), collapsed to one enum for this mock. `.joining` is this app's
/// own transient render state while `layers join <id>` is in flight.
enum DepartmentJoinState: Equatable {
    case joined
    case availableToJoin
    case joining
    case notEntitled(reason: String)
}

struct DepartmentRow: Identifiable {
    let id: String
    let name: String
    var state: DepartmentJoinState

    /// Mirrors interaction-spec §4.5's own worked example verbatim (Sales /
    /// Engineering / Marketing) so this mock reads as the real thing.
    static let mockCatalog: [DepartmentRow] = [
        DepartmentRow(id: "sales", name: "Sales", state: .availableToJoin),
        DepartmentRow(id: "engineering", name: "Engineering", state: .joined),
        DepartmentRow(id: "marketing", name: "Marketing", state: .notEntitled(reason: "Not available to you")),
    ]
}

/// One read-only row in the Shared integrations register (S12). Mirrors the
/// `copilot integrations --json` shape the design doc names (not yet a frozen
/// verb — native-experience-architecture.md §6 open decision 4).
struct SharedIntegrationRow: Identifiable {
    let id: String
    let name: String
    let available: Bool
}

/// The department -> shared-integration mock mapping this build uses to
/// demonstrate D6 ("shared integrations simply appear connected because the
/// joined department provisioned them") without a real integrations read.
private let mockSharedIntegrationsByDepartment: [String: [String]] = [
    "engineering": ["Workday"],
    "sales": ["Salesforce"],
]

/// Mirrors `src/types.ts` `SigninStatus` exactly.
enum SigninStatus: String {
    case idle, pending, authorized, denied, expired, timeout
}

/// Mirrors `src/types.ts` `SigninState` field-for-field — RENDER data only
/// (invariant #6). There is no field here a real token/credential could ever
/// occupy; a real device-flow seam (S3, `cc auth <integration> --json`) would
/// only ever populate `userCode`/`verificationURI`, never a secret.
struct SigninState {
    var status: SigninStatus = .idle
    var userCode: String?
    var verificationURI: String?
}

/// Named-phase materialize progress (`WizardState.phase_label` + a discrete
/// phase count, never an ETA — interaction-spec §3.5 step 7).
struct MaterializePhaseState {
    var label: String = ""
    var index: Int = 0
    var total: Int = 0
}

/// The honest holding terminal (`WizardPhaseTag = "holding"`, §3.6) —
/// first-class, never a fake error screen. `reason` is always plain language,
/// with the owner named where knowable (IT / network / entitlement), the same
/// discipline `WizardState.error` holds in the real contract.
struct HoldingInfo {
    let title: String
    let reason: String
    let origin: WizardStage
}

/// The wizard's own phase state machine — NOT a 1:1 mirror of `WizardPhaseTag`
/// (that tag is coarser; this expands `question` into this build's concrete
/// sub-steps, matching how the roadmap sidebar itself is specified in
/// interaction-spec §3.4).
enum WizardPhase {
    case welcome
    case detecting
    case detected
    case chooseComponents
    case departments
    /// Combines S12 (Shared, read-only, entitlement-provisioned, no sign-in —
    /// interaction-spec §2.6/§4.4) and S5 (Personal, device-flow sign-in —
    /// §3.5.1) into ONE wizard step, per this build's explicit task scope.
    /// **Deviation flagged:** interaction-spec §3.5 step 6 frames "Sign in" as
    /// personal-only and states shared integrations are "never a wizard step"
    /// on their own — they simply appear connected once a department is
    /// joined (D6). This mock renders both registers on one screen so a user
    /// sees, side by side, what's already there because he's entitled
    /// (Shared) versus what he still has to do himself (Personal sign-in).
    /// The two registers stay visually and structurally separate within the
    /// step (D7.2's mandatory split is never violated) — they are only
    /// co-located, not merged into one list. Flagged for design/TA to
    /// reconcile against the strict spec reading in a later pass.
    case integrations
    case materializing
    case verifying
    case verified
    case done
    case holding(HoldingInfo)
}

// MARK: - Wizard model

/// Pure state + mock transitions. `init()` is the implicit memberwise default
/// (every `@Published` property below has a literal default) — nothing here
/// runs I/O or a subprocess at initialization time, so it is safe to
/// instantiate from `WizardWindowController`'s own `init` (itself invoked
/// lazily, off the SwiftUI attribute graph, from an AppKit action — see that
/// class below).
@MainActor
final class WizardModel: ObservableObject {
    @Published var phase: WizardPhase = .welcome
    @Published var detected: [String] = []
    @Published var componentOptions: [ComponentOption] = ComponentOption.mockCatalog
    @Published var departments: [DepartmentRow] = DepartmentRow.mockCatalog
    @Published var signin = SigninState()
    @Published var showSigninSheet = false
    @Published var materialize = MaterializePhaseState()

    private var materializeInFlight = false

    // MARK: Derived

    var currentStage: WizardStage {
        switch phase {
        case .welcome: return .welcome
        case .detecting, .detected: return .detect
        case .chooseComponents: return .chooseComponents
        case .departments: return .departments
        case .integrations: return .integrations
        case .materializing: return .materialize
        case .verifying, .verified: return .verify
        case .done: return .done
        case .holding(let info): return info.origin
        }
    }

    var checkedGrantedComponents: [ComponentOption] {
        componentOptions.filter { $0.granted && $0.checked }
    }

    var joinedDepartments: [DepartmentRow] {
        departments.filter { $0.state == .joined }
    }

    var sharedIntegrations: [SharedIntegrationRow] {
        joinedDepartments.flatMap { department -> [SharedIntegrationRow] in
            (mockSharedIntegrationsByDepartment[department.id] ?? []).map { name in
                SharedIntegrationRow(id: "\(department.id)-\(name)", name: name, available: true)
            }
        }
    }

    // MARK: Welcome -> Detect

    /// Called once from `WizardRootView`'s `.task`, never from `init()` (the
    /// AttributeGraph constraint this file's header documents). A no-op today
    /// (Welcome has nothing to pre-fetch) — kept as the one seam every other
    /// native file in this app uses for "first render, not init" work, so a
    /// future real `get_wizard_state()` priming call has an obvious home.
    func start() {}

    func getStarted() {
        beginDetect()
    }

    /// Mock for `get_wizard_state()` after `wizard_advance` (detect phase).
    func beginDetect() {
        phase = .detecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, case .detecting = self.phase else { return }
            self.detected = [
                "Claude Copilot — foundation and org layers already current",
                "CLI Copilot — foundation layer already current",
                "No personal layer found yet on this Mac",
            ]
            self.phase = .detected
        }
    }

    func continueFromDetect() {
        phase = .chooseComponents
    }

    // MARK: Choose components

    /// Mock for `wizard_choose_products` (never re-enables an ungranted id).
    func toggleComponent(_ id: String) {
        guard let index = componentOptions.firstIndex(where: { $0.id == id }) else { return }
        guard componentOptions[index].granted else { return }
        componentOptions[index].checked.toggle()
    }

    func continueFromChooseComponents() {
        guard !checkedGrantedComponents.isEmpty else { return }
        phase = .departments
    }

    // MARK: Departments (S11)

    /// Mock for `copilot layers join <id>`.
    func joinDepartment(_ id: String) {
        guard let index = departments.firstIndex(where: { $0.id == id }) else { return }
        guard departments[index].state == .availableToJoin else { return }
        departments[index].state = .joining
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, let i = self.departments.firstIndex(where: { $0.id == id }) else { return }
            self.departments[i].state = .joined
        }
    }

    func continueFromDepartments() {
        phase = .integrations
    }

    // MARK: Integrations (S12 shared + S5 personal device-flow)

    /// Mock for `wizard_begin_signin`, then the `wizard_poll_signin` cadence
    /// (`WizardState.signin_interval_secs`) — collapsed here to one scheduled
    /// mock transition to `.authorized` since there is no real backend to
    /// poll. No countdown/timer is ever rendered from this (§3.5.1).
    func beginSignIn() {
        signin = SigninState(status: .pending, userCode: "WKQX-7F2P", verificationURI: "https://example.com/device")
        showSigninSheet = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.signin.status == .pending else { return }
            self.signin.status = .authorized
        }
    }

    func openSigninPage() {
        guard let raw = signin.verificationURI, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    /// DEV-ONLY simulation of the three non-happy-path terminal states a real
    /// device-flow backend would otherwise produce (`SigninStatus`: denied /
    /// expired / timeout). There is no real seam to trigger these from in this
    /// mock build. Flagged for removal once S3's real `cc auth --json` seam
    /// lands — same "dev-only, flagged" convention as the tray's own
    /// "Preview state (dev only)" menu (`control-tower-tray.swift`).
    func devSetSigninStatus(_ status: SigninStatus) {
        signin.status = status
    }

    func retrySignIn() {
        beginSignIn()
    }

    func dismissSigninSheet() {
        showSigninSheet = false
    }

    func skipIntegrations() {
        beginMaterialize()
    }

    func continueFromIntegrations() {
        guard signin.status == .authorized else { return }
        beginMaterialize()
    }

    // MARK: Materialize (named phase, no ETA)

    /// Mock for the `materialize` phase: cycles `WizardState.phase_label`
    /// through one named phase per chosen component plus one per joined
    /// department, then a closing phase — an indeterminate `ProgressView`
    /// throughout, a discrete "phase N of M" count only, never a time.
    func beginMaterialize() {
        guard !materializeInFlight else { return }
        materializeInFlight = true
        phase = .materializing
        var labels = checkedGrantedComponents.map { "Setting up \($0.label)..." }
        labels += joinedDepartments.map { "Bringing in your \($0.name) department..." }
        labels.append("Finishing up...")
        runMaterializePhases(labels, index: 0)
    }

    private func runMaterializePhases(_ labels: [String], index: Int) {
        guard index < labels.count else {
            materializeInFlight = false
            beginVerify()
            return
        }
        materialize = MaterializePhaseState(label: labels[index], index: index + 1, total: labels.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.runMaterializePhases(labels, index: index + 1)
        }
    }

    // MARK: Verify

    /// `done` is reachable only via this parsed-Healthy path (types.ts
    /// discipline) — there is no code path in this model that sets
    /// `phase = .done` from anywhere except `continueFromVerify()` below,
    /// itself only reachable once `.verified` renders.
    func beginVerify() {
        phase = .verifying
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, case .verifying = self.phase else { return }
            self.phase = .verified
        }
    }

    func continueFromVerify() {
        phase = .done
    }

    // MARK: Holding (§3.6)

    /// DEV-ONLY trigger. A real holding is always CLI-driven (a genuine
    /// unreadable/network/entitlement condition), never something a user
    /// presses — this exists only so the honest-terminal render can be judged
    /// without a real failing backend. Same dev-only convention as
    /// `devSetSigninStatus` above.
    func simulateHolding(from stage: WizardStage) {
        let reason: String
        switch stage {
        case .detect:
            reason = "I can't read what's already set up on this Mac right now, so I won't guess. Waiting for network."
        case .materialize:
            reason = "Waiting on setup from your organization before this can finish."
        case .verify:
            reason = "This department is no longer available to you, so setup can't reach Healthy yet."
        default:
            reason = "Something is holding this step back."
        }
        phase = .holding(HoldingInfo(title: "Setup is holding.", reason: reason, origin: stage))
    }

    func tryAgainAfterHolding() {
        guard case .holding(let info) = phase else { return }
        switch info.origin {
        case .detect: beginDetect()
        case .materialize:
            materializeInFlight = false
            beginMaterialize()
        case .verify: beginVerify()
        default: phase = .welcome
        }
    }

    // MARK: Roadmap review (completed rows are tappable, read-only)

    func reviewStage(_ stage: WizardStage) {
        switch stage {
        case .welcome: phase = .welcome
        case .detect: phase = .detected
        case .chooseComponents: phase = .chooseComponents
        case .departments: phase = .departments
        case .integrations: phase = .integrations
        case .materialize: phase = .materializing
        case .verify: phase = .verified
        case .done: phase = .done
        }
    }

    // MARK: Dev-only restart (re-run the flow without relaunching the app)

    func restart() {
        phase = .welcome
        detected = []
        componentOptions = ComponentOption.mockCatalog
        departments = DepartmentRow.mockCatalog
        signin = SigninState()
        showSigninSheet = false
        materialize = MaterializePhaseState()
        materializeInFlight = false
    }
}

// MARK: - Shared step shell (reused grammar from scripts/publisher_setup.swift's
// StepShell: eyebrow -> title -> intro -> content -> pinned footer action bar)

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

/// The persistent roadmap sidebar — always shows all 8 stages with done /
/// current / upcoming state, same grammar as Publisher Setup's
/// `RoadmapSidebar` (`.sidebar` list style picks up the system sidebar
/// material/vibrancy automatically).
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
        .sheet(isPresented: $model.showSigninSheet) {
            SigninSheetView(model: model)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .welcome: welcomeView
        case .detecting, .detected: detectView
        case .chooseComponents: chooseComponentsView
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
        case .detecting: return "detecting"
        case .detected: return "detected"
        case .chooseComponents: return "chooseComponents"
        case .departments: return "departments"
        case .integrations: return "integrations"
        case .materializing: return "materializing-\(model.materialize.index)"
        case .verifying: return "verifying"
        case .verified: return "verified"
        case .done: return "done"
        case .holding(let info): return "holding-\(info.origin.rawValue)"
        }
    }

    // MARK: Welcome

    // Owner directive: the aviators glyph is menu-bar-tray-ONLY (see
    // `AviatorGlyph`'s doc comment in `native/models.swift`) — this welcome
    // hero must render the full-color Control Tower illustration instead
    // (`ControlTowerGlyph`, `docs/10-reference/control-tower.svg`), never tinted,
    // at a size where its detail actually reads (76pt — the illustration is
    // square, unlike the wide aviators glyph it replaces here).
    private var welcomeHeroImage: some View {
        Image(nsImage: ControlTowerGlyph.load(targetHeight: 76))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 76, height: 76)
            .accessibilityLabel("Copilot Control Tower")
    }

    private var welcomeView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    welcomeHeroImage

                    VStack(spacing: 12) {
                        Text("Welcome to Copilot Control Tower.")
                            .font(.largeTitle.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(nsColor: .labelColor))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Control Tower keeps your Claude, CLI, Codex, and Knowledge Copilots current, quietly, in the background. This takes a minute, and you won't need a terminal.")
                            .font(.body)
                            .lineSpacing(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 32)
                .padding(.top, 56)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    model.getStarted()
                } label: {
                    Text("Get Started")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Detect

    private var detectView: some View {
        stepShell(
            eyebrow: "Step 2 of 8",
            title: "Checking what's already here",
            intro: "Control Tower looks at what's already set up on this Mac before asking you anything."
        ) {
            if case .detecting = model.phase {
                verifyingCard("Checking what's already here...")
            } else {
                sectionCard("What was found") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.detected, id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
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
            Button { model.phase = .welcome } label: { Text("Back") }
                .buttonStyle(.bordered)
            devButton("Simulate holding (dev)") { model.simulateHolding(from: .detect) }
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

    // MARK: Choose components

    private var chooseComponentsView: some View {
        stepShell(
            eyebrow: "Step 3 of 8",
            title: "Which copilots do you want set up?",
            intro: "These are your CSE components, not products. Something you're not entitled to shows disabled, never hidden."
        ) {
            sectionCard("Components") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.componentOptions) { option in
                        Toggle(isOn: Binding(
                            get: { option.checked },
                            set: { _ in model.toggleComponent(option.id) }
                        )) {
                            Text(option.label)
                                .font(.body)
                                .foregroundColor(Color(nsColor: option.granted ? .labelColor : .tertiaryLabelColor))
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!option.granted)
                        .help(option.granted ? "" : "Your ecosystem doesn't grant this component.")
                        .padding(.vertical, 4)
                        .accessibilityLabel("\(option.label), \(componentAccessibilityWord(option))")
                    }
                }
            }

            if model.checkedGrantedComponents.isEmpty {
                calloutBlock("Choose at least one component to continue.", symbol: "exclamationmark.circle")
            }
        } leadingActions: {
            Button { model.phase = .detected } label: { Text("Back") }
                .buttonStyle(.bordered)
        } primaryAction: {
            Button { model.continueFromChooseComponents() } label: { Text("Continue") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.checkedGrantedComponents.isEmpty)
        }
    }

    private func componentAccessibilityWord(_ option: ComponentOption) -> String {
        guard option.granted else { return "not entitled" }
        return option.checked ? "checked" : "unchecked"
    }

    // MARK: Departments (S11)

    private var departmentsView: some View {
        stepShell(
            eyebrow: "Step 4 of 8",
            title: "Departments you can join",
            intro: "Joining brings in a department's shared layer. This list stays available later in Settings and the menu-bar popover — you can always join more, or come back to this one."
        ) {
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
        } leadingActions: {
            Button { model.phase = .chooseComponents } label: { Text("Back") }
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
        case .notEntitled(let reason):
            Text(reason).font(.caption).foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
    }

    private func departmentAccessibilityWord(_ state: DepartmentJoinState) -> String {
        switch state {
        case .joined: return "joined"
        case .availableToJoin: return "available to join"
        case .joining: return "joining"
        case .notEntitled: return "not available to you"
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
        case .joined, .notEntitled:
            EmptyView()
        }
    }

    // MARK: Integrations (S12 shared + S5 personal)

    private var integrationsView: some View {
        stepShell(
            eyebrow: "Step 5 of 8",
            title: "Integrations",
            intro: "Shared integrations are already there because you're entitled — nothing to sign into. Your own accounts need your own sign-in."
        ) {
            if !model.sharedIntegrations.isEmpty {
                sectionCard("Shared — available because you're entitled") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.sharedIntegrations) { row in
                            HStack {
                                Image(systemName: "building.2")
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                Text(row.name)
                                    .font(.body)
                                    .foregroundColor(Color(nsColor: .labelColor))
                                Spacer()
                                Text(row.available ? "Available" : "Not available right now")
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: row.available ? .secondaryLabelColor : .tertiaryLabelColor))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(row.name), \(row.available ? "available" : "not available right now")")
                        }
                    }
                }
            }

            sectionCard("Your accounts") {
                personalSigninRow
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
                .disabled(model.signin.status != .authorized)
        }
    }

    @ViewBuilder
    private var personalSigninRow: some View {
        switch model.signin.status {
        case .idle:
            HStack {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Text("Sign in to keep your personal layer in sync.")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                Spacer()
                Button { model.beginSignIn() } label: { Text("Sign in") }
                    .buttonStyle(.borderedProminent)
            }
        case .pending:
            HStack {
                ProgressView().controlSize(.small)
                Text("Waiting for you to finish in your browser…")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Button { model.showSigninSheet = true } label: { Text("Show code") }
                    .buttonStyle(.bordered)
            }
        case .authorized:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(nsColor: .systemGreen))
                Text("Signed in.")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                Spacer()
            }
        case .denied, .expired, .timeout:
            HStack {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(Color(nsColor: .systemOrange))
                Text(signinFailureCaption)
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Button { model.retrySignIn() } label: { Text("Try again") }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var signinFailureCaption: String {
        switch model.signin.status {
        case .denied: return "That sign-in was declined."
        case .expired: return "That code expired."
        case .timeout: return "That took too long."
        default: return ""
        }
    }

    // MARK: Materialize (named phase, no ETA)

    private var materializeView: some View {
        stepShell(
            eyebrow: "Step 6 of 8",
            title: model.materialize.label.isEmpty ? "Setting up" : model.materialize.label,
            intro: "This may take a few minutes. Keep this window open, or continue in the menu bar and check back."
        ) {
            HStack(spacing: 12) {
                ProgressView()
                if model.materialize.total > 0 {
                    Text("Phase \(model.materialize.index) of \(model.materialize.total) named phases")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
        } leadingActions: {
            devButton("Simulate holding (dev)") { model.simulateHolding(from: .materialize) }
        } primaryAction: {
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Setting up…")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
    }

    // MARK: Verify

    private var verifyView: some View {
        stepShell(
            eyebrow: "Step 7 of 8",
            title: "Verify",
            intro: "The only success here is everything actually being current."
        ) {
            if case .verifying = model.phase {
                verifyingCard("Checking your setup…")
            } else {
                verifyResultCard(
                    symbol: "checkmark.seal.fill",
                    tint: Color(nsColor: .systemGreen),
                    title: "Everything checks out.",
                    accessibilityLabel: "Verified: everything checks out"
                ) {
                    EmptyView()
                }
            }
        } leadingActions: {
            devButton("Simulate holding (dev)") { model.simulateHolding(from: .verify) }
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

    // MARK: Done

    private var doneView: some View {
        stepShell(
            eyebrow: "Step 8 of 8",
            title: "You're set up.",
            intro: "Control Tower now lives quietly in your menu bar. When it has nothing to say, it says nothing — that quiet glyph is you, being current."
        ) {
            calloutBlock(
                "New departments you become entitled to later will quietly appear as \"Join available\" in the menu bar, whenever you're ready for them.",
                symbol: "building.2"
            )
        } leadingActions: {
            devButton("Restart (dev)") { model.restart() }
        } primaryAction: {
            Button { onClose() } label: { Text("Done") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Holding (§3.6, first-class, never a dead end)

    private func holdingView(_ info: HoldingInfo) -> some View {
        stepShell(
            eyebrow: "Setup is holding",
            title: info.title,
            intro: info.reason
        ) {
            EmptyView()
        } leadingActions: {
            Button { onClose() } label: { Text("Continue in the menu bar") }
                .buttonStyle(.bordered)
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
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func calloutBlock(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private func verifyResultCard<Content: View>(
        symbol: String,
        tint: Color,
        title: String,
        accessibilityLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, tint)
                    .font(.system(size: 22))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// A small, visually subdued text button for the dev-only affordances
    /// scattered through this file (`simulateHolding`, `restart`) — same
    /// "flagged for removal, not shipped chrome" convention the tray's own
    /// "Preview state (dev only)" menu documents.
    private func devButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
    }
}

// MARK: - Personal sign-in device-flow sheet (S5, §3.5.1)

struct SigninSheetView: View {
    @ObservedObject var model: WizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sign in to keep everything in sync.")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))

            switch model.signin.status {
            case .idle:
                ProgressView()
            case .pending:
                pendingContent
            case .authorized:
                authorizedContent
            case .denied, .expired, .timeout:
                failedContent
            }

            Divider()

            // DEV-ONLY: simulates the three terminal states a real device-flow
            // backend would otherwise produce — see
            // `WizardModel.devSetSigninStatus`'s own doc.
            HStack(spacing: 8) {
                Text("Dev preview:")
                    .font(.caption2)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                devTextButton("Denied") { model.devSetSigninStatus(.denied) }
                devTextButton("Expired") { model.devSetSigninStatus(.expired) }
                devTextButton("Timeout") { model.devSetSigninStatus(.timeout) }
                devTextButton("Authorized") { model.devSetSigninStatus(.authorized) }
            }

            HStack {
                Spacer()
                dismissButton
            }
        }
        .padding(24)
        .frame(width: 420)
        .onChange(of: model.signin.status) {
            if model.signin.status == .authorized {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if model.signin.status == .authorized {
                        model.dismissSigninSheet()
                    }
                }
            }
        }
    }

    /// Two distinct `ButtonStyle` conformances (`.borderedProminent` vs
    /// `.bordered`) can't be chosen between with a ternary on one `Button` (the
    /// modifier is generic over a single concrete style) — an `if`/`else`
    /// branch, each with its own style, is the correct fix.
    @ViewBuilder
    private var dismissButton: some View {
        if model.signin.status == .authorized {
            Button {
                model.dismissSigninSheet()
            } label: {
                Text("Done")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        } else {
            Button {
                model.dismissSigninSheet()
            } label: {
                Text("Cancel")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var pendingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your code")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                HStack {
                    Text(model.signin.userCode ?? "")
                        .font(.title2.monospaced())
                        .textSelection(.enabled)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Spacer()
                    Button {
                        let board = NSPasteboard.general
                        board.clearContents()
                        board.setString(model.signin.userCode ?? "", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy code")
                }
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button {
                model.openSigninPage()
            } label: {
                Label("Open Sign-in Page", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to finish in your browser…")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
    }

    private var authorizedContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(nsColor: .systemGreen))
            Text("Signed in.")
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
        }
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(failureMessage)
                .font(.body)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Button {
                model.retrySignIn()
            } label: {
                Text(model.signin.status == .expired ? "Get a new code" : "Try again")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var failureMessage: String {
        switch model.signin.status {
        case .denied: return "That sign-in was declined."
        case .expired: return "That code expired."
        case .timeout: return "That took too long."
        default: return ""
        }
    }

    private func devTextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(.plain)
        .font(.caption2)
        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
    }
}

// MARK: - Wizard window controller

/// Owns the wizard's single `NSWindow` + its `WizardModel` for the lifetime of
/// the app. A singleton (`shared`) so both entry points — the popover's
/// "Set up" action and the tray's dev-only "Open Wizard (dev)" menu item
/// (`control-tower-tray.swift`) — reuse the SAME window/model instead of
/// spawning a second wizard (interaction-spec §1: "at most one instance" of
/// the wizard container). `isReleasedWhenClosed = false` so closing the
/// window (Done / the titlebar close button) never deallocates it — the next
/// `show()` reopens the same window with whatever state it was last in
/// (matching "completed rows are tappable to review earlier answers" being
/// meaningful even after a close/reopen).
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
    }
}
